#include "bot_visual.h"
#include "bot_navigation.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <limits>
#include <vector>

using namespace godot;

namespace {
// GDScript exposes vector components/method results as doubles, but vector
// operations themselves round through Godot's single-precision Vector2.
struct V2 {
    double x = 0, y = 0;
    V2() = default;
    V2(double px, double py) : x(float(px)), y(float(py)) {}
    V2(Vector2 v) : x(v.x), y(v.y) {}
    Vector2 value() const { return Vector2(float(x), float(y)); }
    V2 operator+(V2 b) const { return value() + b.value(); }
    V2 operator-(V2 b) const { return value() - b.value(); }
    V2 operator*(double s) const { return value() * float(s); }
    V2 operator/(double s) const { return value() / float(s); }
    V2 &operator+=(V2 b) { return *this = *this + b; }
    V2 &operator-=(V2 b) { return *this = *this - b; }
    bool zero() const { return x == 0 && y == 0; }
    double length() const { return value().length(); }
    double length_squared() const { return value().length_squared(); }
    double dot(V2 b) const { return value().dot(b.value()); }
    double cross(V2 b) const { return value().cross(b.value()); }
    double distance_to(V2 b) const { return value().distance_to(b.value()); }
    V2 normalized() const { return value().normalized(); }
};
struct Body {
    V2 position, relative, avoidance, velocity;
    double radius, speed, contact_damage;
    int kind;
    bool fixed;
    bool materializing = false;
};
struct Bullet { V2 relative, velocity; double radius; };
struct Swarm { V2 axis, position, travel; double width, age, spawn_min, spawn_max; };
struct Boss { V2 position; PackedVector2Array spokes; };
struct Frame {
    V2 player, goal, last_move;
    double move_speed, radius, engagement, swarm_speed, swarm_depth, horizon;
    bool boss_active, slow_safe, escape_active;
    int boss_kind, elite_kind, bulwark_kind, encircler_kind;
    std::vector<BotBoundary> boundaries;
    std::vector<Body> enemies;
    std::vector<Bullet> bullets;
    std::vector<Swarm> swarms;
    std::vector<Boss> bosses;
};
double minimum(double a, double b) { return a < b ? a : b; }
double maximum(double a, double b) { return a > b ? a : b; }
double clamp(double v, double lo, double hi) { return v < lo ? lo : (v > hi ? hi : v); }
constexpr double INF = std::numeric_limits<double>::infinity();

using Trajectory = std::array<V2, 61>;

Trajectory predict_player(V2 direction, const Frame &f) {
    Trajectory path;
    path[0] = f.player;
    for (int step = 1; step <= 60; ++step) {
        V2 requested = path[size_t(step - 1)] + direction * (f.move_speed * f.horizon / 60.0);
        path[size_t(step)] = bot_constrain(requested.value(), f.radius, f.boundaries, f.horizon * double(step) / 60.0);
    }
    return path;
}

double contact_exposure(const Trajectory &path, const Frame &f) {
    std::array<double, 60> damage{};
    for (const Body &enemy : f.enemies) {
        if (enemy.materializing || enemy.contact_damage <= 0.0) continue;
        if (f.boundaries.empty()) {
            // A pursuing body cannot cover more than speed * time. Minimize
            // squared distance to the player's straight path minus that expanding
            // reach circle. A positive minimum rules out contact at every instant,
            // without changing any candidate's exposure score. The padding covers
            // contact tolerance and single-precision trajectory accumulation.
            V2 velocity = (path.back() - f.player) / f.horizon;
            double reach = enemy.radius + f.radius + 0.01;
            double speed = enemy.fixed ? enemy.velocity.length() : enemy.speed;
            double quadratic = velocity.length_squared() - speed * speed;
            double linear = -2.0 * (enemy.relative.dot(velocity) + reach * speed);
            double constant = enemy.relative.length_squared() - reach * reach;
            double minimum_gap = minimum(constant, quadratic * f.horizon * f.horizon + linear * f.horizon + constant);
            if (quadratic > 0.0) {
                double time = clamp(-linear / (2.0 * quadratic), 0.0, f.horizon);
                minimum_gap = minimum(minimum_gap, quadratic * time * time + linear * time + constant);
            }
            if (minimum_gap > 0.0) continue;
        }
        V2 position = enemy.position;
        double radius = enemy.radius + f.radius;
        for (int step = 1; step <= 60; ++step) {
            V2 player = path[size_t(step)];
            if (enemy.fixed) {
                position += enemy.velocity * (f.horizon / 60.0);
            } else {
                V2 away = position - player;
                double distance = away.length();
                if (enemy.kind == f.encircler_kind) position -= away.normalized() * minimum(enemy.speed * f.horizon / 60.0, distance);
                else if (distance < radius) position = player + away.normalized() * radius;
                else position -= away.normalized() * minimum(enemy.speed * f.horizon / 60.0, distance - radius);
                if (enemy.kind == f.boss_kind) position = bot_constrain(position.value(), enemy.radius, f.boundaries, f.horizon * double(step) / 60.0);
            }
            double clearance = position.distance_to(player) - radius;
            if (clearance < 0.005) damage[size_t(step - 1)] = maximum(damage[size_t(step - 1)], enemy.contact_damage);
        }
    }
    double total = 0.0;
    for (int step = 0; step < 60; ++step) total += damage[size_t(step)] * (1.0 + double(60 - step) / 60.0) * f.horizon;
    return total;
}

double warning_risk(V2 near_destination, V2 destination, const Frame &f) {
    double risk = 0.0;
    for (const Swarm &warning : f.swarms) {
        V2 tangent(-warning.axis.y, warning.axis.x);
        double width = warning.width * 0.5 + f.radius + 0.5;
        V2 relative = near_destination - warning.position;
        double side_distance = std::abs(relative.dot(tangent));
        if (side_distance >= width) continue;
        double front = -warning.spawn_min + f.swarm_speed * (warning.age + f.horizon) + f.radius;
        double back = -warning.spawn_max - f.swarm_depth + f.swarm_speed * maximum(0.0, warning.age - f.horizon) - f.radius;
        double along = relative.dot(warning.travel.zero() ? warning.axis : warning.travel);
        if ((along >= back && along <= front) || (warning.travel.zero() && -along >= back && -along <= front)) risk += (width - side_distance) * 5000.0;
    }
    for (const Boss &warning : f.bosses) {
        V2 relative = destination - warning.position;
        double lane_clearance = INF;
        for (int64_t i = 0; i < warning.spokes.size(); ++i) {
            V2 spoke(warning.spokes[i]);
            double clearance = relative.dot(spoke) >= 0.0 ? std::abs(relative.cross(spoke)) : relative.length();
            lane_clearance = minimum(lane_clearance, clearance);
        }
        risk += 12.0 / (0.2 + lane_clearance);
    }
    return risk;
}

double movement_score(V2 direction, const Frame &f) {
    V2 player = f.player;
    V2 velocity = direction * f.move_speed;
    double travel_time = f.horizon;
    const Trajectory path = predict_player(direction, f);
    V2 destination = path.back();
    if (!f.boundaries.empty()) velocity = (destination - player) / travel_time;
    double score = direction.dot((f.goal - player).normalized()) * 1000.0;
    score += direction.normalized().dot(f.last_move.normalized()) * 1002.0;
    double immediate_clearance = INF, body_clearance = INF, engagement_distance = INF;
    for (const Body &enemy : f.enemies) {
        V2 relative = enemy.relative;
        V2 relative_velocity = enemy.avoidance - velocity;
        engagement_distance = minimum(engagement_distance, (relative + relative_velocity * f.horizon).length());
        double speed_squared = relative_velocity.length_squared();
        double closest_time = speed_squared < 0.00001 ? 1.0 / 60.0 : clamp(-relative.dot(relative_velocity) / speed_squared, 1.0 / 60.0, travel_time);
        double clearance = (relative + relative_velocity * closest_time).length() - enemy.radius - f.radius;
        double next_clearance = (relative + relative_velocity / 60.0).length() - enemy.radius - f.radius;
        if (enemy.kind != f.encircler_kind) {
            immediate_clearance = minimum(immediate_clearance, next_clearance);
            body_clearance = minimum(body_clearance, next_clearance);
        }
        if (enemy.kind == f.boss_kind && next_clearance < 0.4) score -= 1.0e7 + (0.4 - next_clearance) * 1.0e8;
        if (enemy.kind == f.encircler_kind) continue;
        if (clearance < 0.5) {
            double urgency = (1.1 - closest_time) * (1.1 - closest_time);
            score -= (80.0 + (0.5 - clearance) * 200.0) * urgency / (0.2 + closest_time);
        } else score -= 1.5 / ((clearance + 0.25) * (clearance + 0.25));
    }
    if (!f.boss_active && !f.enemies.empty()) score -= 300.0 * std::pow(maximum(0.0, engagement_distance - f.engagement), 2.0);
    for (const Bullet &bullet : f.bullets) {
        V2 relative = bullet.relative;
        V2 relative_velocity = bullet.velocity - velocity;
        double speed_squared = relative_velocity.length_squared();
        double closest_time = speed_squared < 0.00001 ? 0.0 : clamp(-relative.dot(relative_velocity) / speed_squared, 0.0, travel_time);
        double clearance = (relative + relative_velocity * closest_time).length() - bullet.radius - f.radius;
        if (!f.boundaries.empty()) {
            clearance = INF;
            for (int step = 1; step <= 60; ++step) {
                double time = travel_time * double(step) / 60.0;
                double current = (f.player + relative + bullet.velocity * time).distance_to(path[size_t(step)]) - bullet.radius - f.radius;
                if (current < clearance) { clearance = current; closest_time = time; }
            }
        }
        immediate_clearance = minimum(immediate_clearance, (relative + relative_velocity / 60.0).length() - bullet.radius - f.radius);
        if (clearance < 0.12) score -= 7000.0 / (0.15 + closest_time);
        else if (clearance < 1.0) score -= 4.0 / (clearance + 0.1);
    }
    score -= warning_risk(path[15], destination, f);
    if (direction.zero() && !f.enemies.empty()) score -= 1.0e11;
    if (body_clearance < 0.1) score -= 1.0e7 + (0.1 - body_clearance) * 1.0e8;
    if (immediate_clearance < 0.1) score -= 2000.0 + (0.1 - immediate_clearance) * 20000.0;
    if (direction.length_squared() < 0.5 && !f.slow_safe) score -= 10000.0;
    for (const Body &enemy : f.enemies) {
        if (enemy.kind != f.elite_kind) continue;
        double clearance = (enemy.relative + (enemy.avoidance - velocity) / 60.0).length() - enemy.radius - f.radius;
        if (clearance < 0.8) score -= 1.0e7 + (0.8 - clearance) * 1.0e8;
    }
    for (const Body &enemy : f.enemies) {
        if (enemy.kind != f.bulwark_kind) continue;
        double clearance = (enemy.relative + (enemy.avoidance - velocity) / 60.0).length() - enemy.radius - f.radius;
        if (clearance < 0.4) score -= 1.0e7 + (0.4 - clearance) * 1.0e8;
    }
    // The same physical prediction applies to normal moves and post-hit escape.
    // Public contact damage times exposure distinguishes a brief ring crossing.
    score -= contact_exposure(path, f) * (f.escape_active ? 2000.0 : 1000.0);
    if (!f.boundaries.empty()) {
        V2 requested_next = player + direction * (f.move_speed * travel_time / 60.0);
        score -= requested_next.distance_to(path[1]) * 1.0e7;
        score -= (player + direction * (f.move_speed * travel_time)).distance_to(destination) * 4000.0;
    }
    return score;
}
}

class JarjarBotKernel : public JarjarBotNavigation {
    GDCLASS(JarjarBotKernel, JarjarBotNavigation)
    Frame last_frame;
    bool frame_ready = false;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("score_moves", "frame", "directions"), &JarjarBotKernel::score_moves);
        ClassDB::bind_method(D_METHOD("choose_move", "frame", "directions"), &JarjarBotKernel::choose_move);
        ClassDB::bind_method(D_METHOD("aim_needles", "directions", "count", "navigation_move", "reach"), &JarjarBotKernel::aim_needles);
        ClassDB::bind_method(D_METHOD("api_version"), &JarjarBotKernel::api_version);
    }
public:
    int api_version() const { return 8; }
    Vector2 choose_move(const Dictionary &data, const PackedVector2Array &directions) {
        PackedFloat64Array scores = score_moves(data, directions);
        ERR_FAIL_COND_V(scores.size() != directions.size(), Vector2(float(INF), float(INF)));
        double best = -INF;
        Vector2 selected;
        const double *values = scores.ptr();
        const Vector2 *moves = directions.ptr();
        const int64_t count = scores.size();
        for (int64_t i = 0; i < count; ++i) {
            if (values[i] > best) { best = values[i]; selected = moves[i]; }
        }
        return selected;
    }
    PackedFloat64Array score_moves(const Dictionary &data, const PackedVector2Array &directions) {
        Frame f;
        f.player = Vector2(data["player"]); f.goal = Vector2(data["goal"]); f.last_move = Vector2(data["last_move"]);
        f.move_speed = data["move_speed"]; f.radius = data["player_radius"]; f.engagement = data["engagement"];
        f.horizon = data["horizon"];
        f.swarm_speed = data["swarm_speed"]; f.swarm_depth = data["swarm_depth"];
        f.boss_active = data["boss_active"]; f.slow_safe = true; f.escape_active = data["escape_active"];
        f.boss_kind = data["boss_kind"]; f.elite_kind = data["elite_kind"]; f.bulwark_kind = data["bulwark_kind"];
        f.encircler_kind = data.get("encircler_kind", -1);
        f.boundaries = predicted_boundaries();
        Dictionary frame_damage = data.get("contact_damage", Dictionary());
        double slow_clearance = data["slow_clearance"];
        for (const Track &track : enemies) {
            if (track.position.distance_squared_to(f.player.value()) >= 81.0) continue;
            V2 relative = track.position - f.player.value();
            if (relative.length() - track.radius - f.radius < slow_clearance) f.slow_safe = false;
            V2 avoidance = track.velocity;
            auto speed = enemy_speeds.find(track.kind);
            if (speed != enemy_speeds.end() && !track.fixed) {
                V2 normal = relative.normalized();
                avoidance = V2(-normal.x, -normal.y) * speed->second;
            }
            double inferred_speed = speed == enemy_speeds.end() ? double(track.velocity.length()) : speed->second;
            double damage = frame_damage.get(track.fixed ? red_kind : track.kind, 0.0);
            f.enemies.push_back({track.position, relative, avoidance, track.velocity, track.radius, inferred_speed, damage, track.kind, track.fixed, track.materializing});
        }
        for (const Track &track : bullets) f.bullets.push_back({track.position - f.player.value(), track.velocity, track.radius});
        Array swarms = data["swarms"];
        for (int64_t i = 0; i < swarms.size(); ++i) {
            Array row = swarms[i];
            f.swarms.push_back({Vector2(row[0]), Vector2(row[1]), Vector2(row[2]), row[3], row[4], row[5], row[6]});
        }
        Array bosses = data["bosses"];
        for (int64_t i = 0; i < bosses.size(); ++i) {
            Array row = bosses[i];
            f.bosses.push_back({Vector2(row[0]), PackedVector2Array(row[1])});
        }
        PackedFloat64Array scores;
        scores.resize(directions.size());
        double *output = scores.ptrw();
        const Vector2 *input = directions.ptr();
        for (int64_t i = 0; i < directions.size(); ++i) output[i] = movement_score(input[i], f);
        last_frame = std::move(f);
        frame_ready = true;
        return scores;
    }

    Vector2 aim_needles(const PackedVector2Array &directions, int count, Vector2 navigation_move, double reach) const {
        if (!frame_ready) return navigation_move;
        const Frame &f = last_frame;
        for (const Body &enemy : f.enemies) if (enemy.relative.length() - enemy.radius - f.radius < 1.5) return navigation_move;
        for (const Bullet &bullet : f.bullets) {
            double speed_squared = bullet.velocity.length_squared();
            double closest_time = speed_squared < 0.00001 ? 0.0 : clamp(-bullet.relative.dot(bullet.velocity) / speed_squared, 0.0, 1.0 / 60.0);
            if ((bullet.relative + bullet.velocity * closest_time).length() < bullet.radius + f.radius + 0.15) return navigation_move;
        }
        ERR_FAIL_COND_V(count < 0 || directions.size() <= count, navigation_move);
        double best = 0.0;
        V2 aim;
        for (int index = 0; index < count; ++index) {
            V2 direction = directions[index + 1];
            double score = 0.0;
            for (const Body &enemy : f.enemies) {
                if (enemy.materializing) continue;
                V2 relative = enemy.relative + enemy.velocity * 0.2;
                double along = relative.dot(direction);
                if (along > 0.0 && along < reach && std::abs(relative.cross(direction)) < enemy.radius + 0.25) score += 1.0 / (1.0 + along * 0.1);
            }
            if (score > best) { best = score; aim = direction; }
        }
        if (aim.zero()) return navigation_move;
        V2 adjusted = aim * 0.02;
        V2 next = f.player + adjusted * (f.move_speed / 60.0);
        if (!bot_inside(next.value(), f.radius, f.boundaries, 1.0 / 60.0)) return navigation_move;
        const Trajectory adjusted_path = predict_player(adjusted, f), navigation_path = predict_player(navigation_move, f);
        if (contact_exposure(adjusted_path, f) > contact_exposure(navigation_path, f) + 0.0001) return navigation_move;
        if (warning_risk(adjusted_path[15], adjusted_path.back(), f) > warning_risk(navigation_path[15], navigation_path.back(), f) + 0.0001) return navigation_move;
        for (const Bullet &bullet : f.bullets) {
            for (int step = 1; step <= 60; ++step) {
                V2 position = f.player + bullet.relative + bullet.velocity * (f.horizon * double(step) / 60.0);
                double clearance = position.distance_to(adjusted_path[size_t(step)]) - bullet.radius - f.radius;
                if (clearance < 0.15 && clearance < position.distance_to(navigation_path[size_t(step)]) - bullet.radius - f.radius) return navigation_move;
            }
        }
        return adjusted.value();
    }
};

static void initialize_bot(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(JarjarBotVisual);
        GDREGISTER_CLASS(JarjarBotObserver);
        GDREGISTER_CLASS(JarjarBotNavigation);
        GDREGISTER_CLASS(JarjarBotKernel);
    }
}
static void uninitialize_bot(ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT jarjar_bot_init(GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_bot);
    init.register_terminator(uninitialize_bot);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
