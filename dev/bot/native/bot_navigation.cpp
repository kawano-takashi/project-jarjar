#include "bot_navigation.h"
#include "bot_view.h"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <algorithm>
#include <map>
#include <limits>
#include <tuple>
#include <vector>

using namespace godot;

void JarjarBotNavigation::_bind_methods() {
    ClassDB::bind_method(D_METHOD("observe_boundaries", "segments", "normals", "tick"), &JarjarBotNavigation::observe_boundaries);
    ClassDB::bind_method(D_METHOD("clear_combat_memory"), &JarjarBotNavigation::clear_combat_memory);
    ClassDB::bind_method(D_METHOD("recenter", "origin"), &JarjarBotNavigation::recenter);
    ClassDB::bind_method(D_METHOD("shift_origin", "displacement"), &JarjarBotNavigation::shift_origin);
    ClassDB::bind_method(D_METHOD("configure", "origin", "dimensions", "cell_size"), &JarjarBotNavigation::configure);
    ClassDB::bind_method(D_METHOD("route", "player", "goal", "positions", "radii", "player_radius"), &JarjarBotNavigation::route);
    ClassDB::bind_method(D_METHOD("match_tracks", "predicted", "old_kinds", "observed", "kinds", "track_cell"), &JarjarBotNavigation::match_tracks);
    ClassDB::bind_method(D_METHOD("remember_loot", "loot", "inverse", "viewport", "tick", "projection", "xp_kind"), &JarjarBotNavigation::remember_loot);
    ClassDB::bind_method(D_METHOD("choose_loot_goal", "frame"), &JarjarBotNavigation::choose_loot_goal);
    ClassDB::bind_method(D_METHOD("nearest_remembered_loot", "kind", "player"), &JarjarBotNavigation::nearest_remembered_loot);
    ClassDB::bind_method(D_METHOD("configure_tracking", "data"), &JarjarBotNavigation::configure_tracking);
    ClassDB::bind_method(D_METHOD("observe_tracks", "frame"), &JarjarBotNavigation::observe_tracks);
    ClassDB::bind_method(D_METHOD("first_boss_position"), &JarjarBotNavigation::first_boss_position);
    ClassDB::bind_method(D_METHOD("route_tracked", "player", "goal", "player_radius"), &JarjarBotNavigation::route_tracked);
}

void JarjarBotNavigation::configure(const Vector2 &p_origin, const Vector2i &p_dimensions, double p_cell_size) {
    origin = p_origin;
    dimensions = p_dimensions;
    cell_size = p_cell_size;
    loot_memory.clear();
    clear_combat_memory();
    grid.instantiate();
    grid->set_region(Rect2i(Vector2i(), dimensions));
    grid->set_offset(origin);
    grid->set_cell_size(Vector2(1, 1) * float(cell_size));
    grid->set_diagonal_mode(AStarGrid2D::DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES);
    grid->update();
}

void JarjarBotNavigation::recenter(const Vector2 &p_origin) {
    ERR_FAIL_COND(grid.is_null());
    if (origin == p_origin) return;
    origin = p_origin;
    grid->set_offset(origin);
    grid->update();
}

void JarjarBotNavigation::shift_origin(const Vector2 &displacement) {
    for (BotBoundary &wall : boundaries) wall.point -= displacement;
    for (Track &track : enemies) track.position -= displacement;
    for (Track &track : bullets) track.position -= displacement;
    Dictionary shifted;
    Array keys = loot_memory.keys();
    for (int64_t i = 0; i < keys.size(); ++i) {
        Vector3i key = keys[i];
        Vector4 entry = loot_memory[key];
        entry.x -= displacement.x;
        entry.y -= displacement.y;
        Vector3i shifted_key(int(std::round(double(entry.x) * 2.0)), int(std::round(double(entry.y) * 2.0)), key.z);
        shifted[shifted_key] = entry;
    }
    loot_memory = shifted;
    recenter(origin - displacement);
}

void JarjarBotNavigation::remember_loot(const PackedVector4Array &loot, const Transform3D &inverse, const Vector2i &viewport, int64_t tick, const Projection &projection, int xp_kind) {
    for (int64_t i = 0; i < loot.size(); ++i) {
        Vector4 entry = loot[i];
        Vector3i key(int(std::round(double(entry.y) * 2.0)), int(std::round(double(entry.z) * 2.0)), int(entry.x));
        loot_memory[key] = Vector4(entry.y, entry.z, entry.w, float(tick));
    }
    Array keys = loot_memory.keys();
    for (int64_t i = 0; i < keys.size(); ++i) {
        Vector3i key = keys[i];
        Vector4 entry = loot_memory[key];
        if (int64_t(entry.w) == tick) continue;
        if (bot_point_inside_view(Vector3(entry.x, 0.3f, entry.y), inverse, projection, viewport, 24.0f) ||
            (key.z == xp_kind && tick - int64_t(entry.w) > 300)) loot_memory.erase(key);
    }
}

std::vector<Vector2> JarjarBotNavigation::remembered_loot_positions(int kind) const {
    std::vector<Vector2> result;
    Array keys = loot_memory.keys();
    for (int64_t i = 0; i < keys.size(); ++i) {
        Vector3i key = keys[i];
        if (key.z != kind) continue;
        Vector4 entry = loot_memory[key];
        result.emplace_back(entry.x, entry.y);
    }
    return result;
}

Vector3 JarjarBotNavigation::nearest_remembered_loot(int kind, const Vector2 &player) const {
    double nearest = std::numeric_limits<double>::infinity();
    Vector3 result;
    for (Vector2 position : remembered_loot_positions(kind)) {
        double distance = position.distance_squared_to(player);
        if (distance < nearest) { nearest = distance; result = Vector3(position.x, position.y, 1.0f); }
    }
    return result;
}

Vector3 JarjarBotNavigation::choose_loot_goal(const Dictionary &frame) const {
    Vector2 player = frame["player"];
    PackedInt32Array kinds = frame["loot_kinds"];
    ERR_FAIL_COND_V(kinds.size() != 5, Vector3());
    bool maxed = frame["maxed"], evolution_ready = frame["evolution_ready"];
    bool hold_evolution_chests = frame["hold_evolution_chests"];
    double hp = frame["hp"], max_hp = frame["max_hp"], pickup_radius = frame["pickup_radius"];
    double player_radius = frame.get("player_radius", 0.0), collect_radius = frame.get("object_collect_radius", 0.0);
    const auto walls = predicted_boundaries();
    using Cell = std::pair<int, int>;
    auto cell_key = [](Vector2 p) -> Cell { return {int(std::floor(double(p.x) / 2.0)), int(std::floor(double(p.y) / 2.0))}; };
    std::map<Cell, std::vector<const Track *>> danger_cells;
    double largest_radius = 0.0;
    for (const Track &enemy : enemies) {
        danger_cells[cell_key(enemy.position)].push_back(&enemy);
        largest_radius = std::max(largest_radius, enemy.radius);
    }
    int cell_range = int(std::ceil((player_radius + largest_radius + 0.02) / 2.0));
    auto open = [&](Vector2 position) {
        auto [x, y] = cell_key(position);
        for (int dx = -cell_range; dx <= cell_range; ++dx) {
            for (int dy = -cell_range; dy <= cell_range; ++dy) {
                auto found = danger_cells.find({x + dx, y + dy});
                if (found == danger_cells.end()) continue;
                // Reject actual body overlap, not every gap within two meters.
                // Routing and movement prediction assess the approach itself.
                for (const Track *enemy : found->second) {
                    double reach = player_radius + enemy->radius + 0.02;
                    if (enemy->position.distance_squared_to(position) < reach * reach) return false;
                }
            }
        }
        return true;
    };
    struct Cluster { Vector2 sum; double weight = 0.0; };
    std::vector<Cluster> clusters;
    std::map<Cell, size_t> cluster_indices;
    double best = -std::numeric_limits<double>::infinity();
    Vector2 best_position;
    bool best_is_node = false;
    bool best_is_xp = false;
    Array keys = loot_memory.keys();
    for (int64_t i = 0; i < keys.size(); ++i) {
        Vector3i key = keys[i];
        Vector4 entry = loot_memory[key];
        Vector2 position(entry.x, entry.y);
        int kind = key.z;
        Vector2 reachable = bot_constrain(position, player_radius + 0.02, walls);
        double reach = kind == kinds[0] ? pickup_radius : (kind == kinds[4] ? 0.0 : collect_radius);
        if (!bot_inside(reachable, player_radius, walls) || reachable.distance_to(position) > reach) continue;
        if (kind != kinds[0]) position = reachable;
        if (kind != kinds[0] && !open(position)) continue;
        double distance = player.distance_to(position);
        double value = 0.0;
        if (kind == kinds[0]) {
            if (maxed) continue;
            Cell cell = cell_key(position);
            auto found = cluster_indices.find(cell);
            if (found == cluster_indices.end()) {
                size_t index = clusters.size();
                clusters.push_back(Cluster());
                found = cluster_indices.emplace(cell, index).first;
            }
            double weight = double(entry.z) * double(entry.z);
            Cluster &cluster = clusters[found->second];
            cluster.sum += position * float(weight);
            cluster.weight += weight;
            continue;
        } else if (kind == kinds[1]) value = 28.0;
        else if (kind == kinds[2]) {
            if (hold_evolution_chests) continue;
            value = evolution_ready ? 70.0 : 28.0;
        } else if (kind == kinds[3]) value = 14.0 + 25.0 * (1.0 - hp / max_hp);
        else if (kind == kinds[4]) value = 2.0;
        double score = value / (distance + 2.0);
        if (score > best) { best = score; best_position = position; best_is_node = kind == kinds[4]; }
    }
    // The vector retains first-seen cell order, like GDScript's Dictionary.
    for (const Cluster &cluster : clusters) {
        double weight = cluster.weight;
        Vector2 position = cluster.sum / float(weight);
        Vector2 approach = position + (player - position).normalized() * float(std::min(pickup_radius - 0.5, double(player.distance_to(position))));
        approach = bot_constrain(approach, player_radius + 0.02, walls);
        if (approach.distance_to(position) > pickup_radius || !bot_inside(approach, player_radius, walls)) continue;
        if (!open(approach)) continue;
        double score = (5.0 + std::sqrt(weight) * 4.0) / (double(player.distance_to(position)) + 2.0);
        if (score > best) { best = score; best_position = approach; best_is_node = false; best_is_xp = true; }
    }
    return Vector3(best_position.x, best_position.y, best > 0.0 ? (best_is_xp ? 3.0f : (best_is_node ? 2.0f : 1.0f)) : 0.0f);
}

Vector2i JarjarBotNavigation::cell(const Vector2 &position) const {
    return Vector2i(((position - origin) / float(cell_size)).round()).clamp(Vector2i(), dimensions - Vector2i(1, 1));
}

Vector2 JarjarBotNavigation::route(const Vector2 &player, const Vector2 &goal, const PackedVector2Array &positions, const PackedFloat64Array &radii, double player_radius) {
    ERR_FAIL_COND_V(grid.is_null() || positions.size() != radii.size(), player);
    const auto walls = predicted_boundaries();
    Vector2 bounded_goal = goal.clamp(origin, grid->get_point_position(dimensions - Vector2i(1, 1)));
    bounded_goal = bot_constrain(bounded_goal, player_radius + 0.05, walls, 0.25);
    grid->fill_weight_scale_region(grid->get_region(), 1.0f);
    grid->fill_solid_region(grid->get_region(), false);
    for (int x = 0; !walls.empty() && x < dimensions.x; ++x) {
        for (int y = 0; y < dimensions.y; ++y) {
            Vector2i id(x, y);
            if (!bot_inside(grid->get_point_position(id), player_radius + 0.02, walls, 0.25)) grid->set_point_solid(id, true);
        }
    }
    for (int64_t i = 0; i < positions.size(); ++i) {
        Vector2 position = positions[i];
        double contact_radius = radii[i] + player_radius;
        double radius = contact_radius + 2.0;
        Vector2i lower = cell(position - Vector2(1, 1) * float(radius));
        Vector2i upper = cell(position + Vector2(1, 1) * float(radius));
        for (int x = lower.x; x <= upper.x; ++x) {
            for (int y = lower.y; y <= upper.y; ++y) {
                Vector2i id(x, y);
                double clearance = double(grid->get_point_position(id).distance_to(position)) - contact_radius;
                if (clearance < 2.0) {
                    double risk = route_risk.size() == size_t(positions.size()) ? route_risk[size_t(i)] : 1.0;
                    double danger = 20.0 * (2.0 - clearance) * (2.0 - clearance) * risk;
                    grid->set_point_weight_scale(id, float(double(grid->get_point_weight_scale(id)) + danger));
                }
            }
        }
    }
    // Rounding must not make a valid position on the wall an unusable start cell.
    auto nearest_open = [&](Vector2 point) {
        Vector2i nearest = cell(point);
        if (!grid->is_point_solid(nearest)) return nearest;
        double best = std::numeric_limits<double>::infinity();
        nearest = Vector2i(-1, -1);
        for (int x = 0; x < dimensions.x; ++x) for (int y = 0; y < dimensions.y; ++y) {
            Vector2i id(x, y);
            if (grid->is_point_solid(id)) continue;
            double distance = grid->get_point_position(id).distance_squared_to(point);
            if (distance < best) { best = distance; nearest = id; }
        }
        return nearest;
    };
    Vector2i start = nearest_open(player), finish = nearest_open(bounded_goal);
    if (start.x < 0 || finish.x < 0) return bot_constrain(player, player_radius, walls);
    PackedVector2Array path = grid->get_point_path(start, finish);
    if (path.is_empty()) return bot_constrain(player, player_radius, walls);
    if (path.size() >= 2) return path[std::min(int64_t(3), path.size() - 1)];
    return bounded_goal;
}

void JarjarBotNavigation::clear_combat_memory() {
    enemies.clear(); bullets.clear(); boundaries.clear(); contact_damage.clear(); route_risk.clear(); boundary_tick = 0;
}

void JarjarBotNavigation::observe_boundaries(const PackedVector4Array &segments, const PackedVector2Array &normals, int64_t tick) {
    ERR_FAIL_COND(segments.size() != normals.size());
    if (tick < boundary_tick) boundaries.clear();
    boundary_tick = tick;
    boundaries.erase(std::remove_if(boundaries.begin(), boundaries.end(), [&](const BotBoundary &wall) {
        return tick - wall.seen_tick > memory_ticks;
    }), boundaries.end());
    for (int64_t i = 0; i < segments.size(); ++i) {
        Vector4 line = segments[i];
        Vector2 point((line.x + line.z) * 0.5f, (line.y + line.w) * 0.5f), normal = normals[i].normalized();
        if (normal.is_zero_approx()) continue;
        auto found = std::find_if(boundaries.begin(), boundaries.end(), [&](const BotBoundary &wall) {
            return wall.normal.dot(normal) > 0.99999f;
        });
        if (found == boundaries.end()) boundaries.push_back({point, normal, 0.0, tick});
        else {
            double elapsed = double(tick - found->seen_tick) / 60.0;
            if (elapsed > 0.0) found->speed = std::max(0.0, double((point - found->point).dot(normal)) / elapsed);
            found->point = point; found->normal = normal; found->seen_tick = tick;
        }
    }
}

std::vector<BotBoundary> JarjarBotNavigation::predicted_boundaries() const {
    auto result = boundaries;
    for (BotBoundary &wall : result) wall.point += wall.normal * float(wall.speed * double(boundary_tick - wall.seen_tick) / 60.0);
    return result;
}

PackedInt32Array JarjarBotNavigation::match_tracks(const PackedVector2Array &predicted, const PackedInt32Array &old_kinds, const PackedVector2Array &observed, const PackedInt32Array &kinds, double track_cell) const {
    ERR_FAIL_COND_V(predicted.size() != old_kinds.size() || observed.size() != kinds.size() || track_cell <= 0, PackedInt32Array());
    using Key = std::tuple<int, int, int>;
    auto key = [track_cell](Vector2 position, int kind) -> Key {
        return {int(std::floor(double(position.x) / track_cell)), int(std::floor(double(position.y) / track_cell)), kind};
    };
    std::map<Key, std::vector<int>> cells;
    const int64_t old_count = predicted.size(), count = observed.size();
    const Vector2 *previous_positions = predicted.ptr(), *positions = observed.ptr();
    const int32_t *previous_kinds = old_kinds.ptr(), *observed_kinds = kinds.ptr();
    std::vector<bool> matched(size_t(old_count), false);
    for (int64_t i = 0; i < old_count; ++i) cells[key(previous_positions[i], previous_kinds[i])].push_back(int(i));
    PackedInt32Array matches;
    matches.resize(count);
    int32_t *output = matches.ptrw();
    for (int64_t i = 0; i < count; ++i) {
        auto [x, y, kind] = key(positions[i], observed_kinds[i]);
        int closest = -1;
        double best_distance = track_cell * track_cell;
        // Preserve neighborhood traversal, previous-track order and strict ties.
        for (int dx = -1; dx <= 1; ++dx) {
            for (int dy = -1; dy <= 1; ++dy) {
                auto found = cells.find({x + dx, y + dy, kind});
                if (found == cells.end()) continue;
                for (int index : found->second) {
                    if (matched[size_t(index)]) continue;
                    double distance = positions[i].distance_squared_to(previous_positions[index]);
                    if (distance < best_distance) {
                        best_distance = distance;
                        closest = index;
                    }
                }
            }
        }
        output[i] = closest;
        if (closest >= 0) matched[size_t(closest)] = true;
    }
    return matches;
}


void JarjarBotNavigation::configure_tracking(const Dictionary &data) {
    Dictionary speeds = data["enemy_speeds"];
    Array kinds = speeds.keys();
    enemy_speeds.clear();
    for (int64_t i = 0; i < kinds.size(); ++i) enemy_speeds[int(kinds[i])] = speeds[kinds[i]];
    tracking_cell = data["track_cell"]; memory_ticks = data["memory_ticks"];
    swarm_speed = data["swarm_speed"];
    swarmer_kind = data["swarmer_kind"]; red_kind = data["red_kind"]; boss_kind = data["boss_kind"];
    enemies.clear(); bullets.clear();
}

std::vector<JarjarBotNavigation::Track> JarjarBotNavigation::track_bodies(const Dictionary &data, const std::vector<Track> &old, const Dictionary &frame, bool bullet) const {
    PackedVector2Array positions = data["positions"];
    PackedInt32Array kinds = data["kinds"];
    PackedFloat64Array radii = data["radii"];
    PackedByteArray materializing = data["materializing"];
    ERR_FAIL_COND_V(positions.size() != kinds.size() || radii.size() != kinds.size() || materializing.size() != kinds.size(), std::vector<Track>());
    Vector2 player = frame["player"];
    Transform3D inverse = frame["inverse"];
    Vector2i viewport = frame["viewport"];
    int64_t tick = frame["tick"];
    double elapsed = frame["elapsed"];
    PackedVector2Array predicted;
    PackedInt32Array old_kinds;
    predicted.resize(int64_t(old.size())); old_kinds.resize(int64_t(old.size()));
    for (size_t i = 0; i < old.size(); ++i) {
        predicted[int64_t(i)] = old[i].position + old[i].velocity * float(elapsed);
        old_kinds[int64_t(i)] = old[i].kind;
    }
    PackedInt32Array matches = match_tracks(predicted, old_kinds, positions, kinds, tracking_cell);
    std::vector<bool> matched(old.size(), false);
    std::vector<Track> result;
    result.reserve(size_t(positions.size()) + old.size());
    for (int64_t i = 0; i < positions.size(); ++i) {
        int index = matches[i];
        Track track;
        auto speed = enemy_speeds.find(kinds[i]);
        if (index < 0) {
            track.fixed = kinds[i] == red_kind;
            if (!bullet) track.velocity = (player - positions[i]).normalized() * float(speed == enemy_speeds.end() ? 0.0 : speed->second);
        } else {
            matched[size_t(index)] = true;
            track = old[size_t(index)];
            track.velocity = (positions[i] - track.position) / float(elapsed);
            if (!bullet && kinds[i] == swarmer_kind) {
                double observed_speed = track.velocity.length();
                if (std::abs(observed_speed - swarm_speed) < 0.03) track.fixed = true;
                else if (speed != enemy_speeds.end() && std::abs(observed_speed - speed->second) < 0.03) track.fixed = false;
            }
            if (!bullet && speed != enemy_speeds.end()) {
                double limit = speed->second;
                if (kinds[i] == swarmer_kind && double(track.velocity.length()) > swarm_speed * 0.7) limit = swarm_speed;
                track.velocity = track.velocity.limit_length(float(limit));
            }
        }
        track.position = positions[i]; track.radius = radii[i]; track.kind = kinds[i];
        track.materializing = materializing[i] != 0; track.seen_tick = tick;
        result.push_back(track);
    }
    Projection projection = frame["projection"];
    for (size_t i = 0; i < old.size(); ++i) {
        if (matched[i] || tick - old[i].seen_tick > memory_ticks) continue;
        Track track = old[i];
        track.position += track.velocity * float(elapsed);
        if (!bot_point_inside_view(Vector3(track.position.x, 0.35f, track.position.y), inverse, projection, viewport, 24.0f)) result.push_back(track);
    }
    return result;
}

void JarjarBotNavigation::observe_tracks(const Dictionary &frame) {
    Dictionary damage = frame.get("contact_damage", Dictionary());
    Array damage_kinds = damage.keys();
    for (int64_t i = 0; i < damage_kinds.size(); ++i) {
        int kind = damage_kinds[i];
        contact_damage[kind] = damage[kind];
    }
    enemies = track_bodies(frame["enemies"], enemies, frame, false);
    bullets = track_bodies(frame["bullets"], bullets, frame, true);
}

Vector3 JarjarBotNavigation::first_boss_position() const {
    for (const Track &track : enemies) if (track.kind == boss_kind) return Vector3(track.position.x, track.position.y, 1.0f);
    return Vector3();
}

Vector2 JarjarBotNavigation::route_tracked(const Vector2 &player, const Vector2 &goal, double player_radius) {
    PackedVector2Array positions;
    PackedFloat64Array radii;
    positions.resize(int64_t(enemies.size())); radii.resize(int64_t(enemies.size()));
    route_risk.resize(enemies.size());
    for (size_t i = 0; i < enemies.size(); ++i) {
        positions[int64_t(i)] = enemies[i].position + enemies[i].velocity * 0.3f;
        radii[int64_t(i)] = enemies[i].radius;
        auto damage = contact_damage.find(enemies[i].kind);
        route_risk[i] = damage == contact_damage.end() ? 1.0 : std::clamp(damage->second, 0.05, 4.0);
    }
    Vector2 result = route(player, goal, positions, radii, player_radius);
    route_risk.clear();
    return result;
}
