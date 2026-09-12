#include "combat_fields.h"
#include "combat_geometry.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <map>
#include <chrono>

namespace {
#define DECLARE_FIELD(type, name, initial) type name = initial;
struct Enemy {
    JARJAR_ENEMY_FIELDS(DECLARE_FIELD)
    double radius = 0, move_speed = 0, contact_damage = 0;
    int64_t xp_value = 0, special_interval = 0, telegraph_ticks = 0;
};
struct Projectile {
    JARJAR_PROJECTILE_FIELDS(DECLARE_FIELD)
    std::unordered_set<int64_t> hit_enemies, hit_nodes;
    int visual_kind = 0;
    bool evolved = false;
};
struct ProjectileIntersection {
    double time = INFINITY;
    int64_t entity_id = INT64_MAX;
    int slot = -1;
    bool operator<(const ProjectileIntersection &other) const {
        return time < other.time || (time == other.time && entity_id < other.entity_id);
    }
};
struct Xp { JARJAR_XP_FIELDS(DECLARE_FIELD) bool vacuum = false; };
struct Node { JARJAR_NODE_FIELDS(DECLARE_FIELD) };
#undef DECLARE_FIELD

// Stable slots, a dense live list, and generation-checked handles. Resizing does
// not change IDs or invalidate handles; clears never reset a generation.
template<class T> struct Pool {
    std::vector<T> slots;
    std::vector<int> active, free, dense;
    int64_t overflow = 0, reused = 0, next_generation = 1;
    bool resize(int capacity) {
        if (capacity < 0) return false;
        for (int i : active) if (i >= capacity) return false;
        int old = int(slots.size());
        slots.resize(capacity); dense.resize(capacity, -1);
        free.erase(std::remove_if(free.begin(), free.end(), [capacity](int i) { return i >= capacity; }), free.end());
        for (int i = capacity - 1; i >= old; --i) free.push_back(i);
        return true;
    }
    int acquire() {
        if (free.empty() || next_generation == INT64_MAX) { ++overflow; return -1; }
        int i = free.back(); free.pop_back();
        int64_t generation = slots[i].generation;
        if (generation > 0) ++reused;
        slots[i] = T(); slots[i].generation = next_generation++;
        dense[i] = int(active.size()); active.push_back(i);
        return i;
    }
    bool valid(int i, int64_t generation = -1) const {
        return i >= 0 && i < int(slots.size()) && dense[i] >= 0 &&
            (generation < 0 || slots[i].generation == generation);
    }
    bool release(int i, int64_t generation = -1) {
        if (!valid(i, generation)) return false;
        int position = dense[i], last = active.back();
        active[position] = last; dense[last] = position; active.pop_back();
        dense[i] = -1; free.push_back(i);
        return true;
    }
    void clear() {
        active.clear(); free.clear(); std::fill(dense.begin(), dense.end(), -1);
        for (int i = int(slots.size()) - 1; i >= 0; --i) {
            int64_t generation = slots[i].generation;
            slots[i] = T(); slots[i].generation = generation; free.push_back(i);
        }
    }
    Array indices() const { Array result; for (int i : active) result.push_back(i); return result; }
    Dictionary stats() const {
        Dictionary result;
        result["capacity"] = int64_t(slots.size()); result["active"] = int64_t(active.size());
        result["free"] = int64_t(free.size()); result["overflow"] = overflow; result["reused"] = reused;
        return result;
    }
    int orphan_count() const {
        std::vector<bool> seen(slots.size(), false); int errors = 0;
        for (int p = 0; p < int(active.size()); ++p) {
            int i = active[p];
            if (i < 0 || i >= int(slots.size())) { ++errors; continue; }
            if (seen[i] || dense[i] != p) ++errors; seen[i] = true;
        }
        for (int i : free) {
            if (i < 0 || i >= int(slots.size())) { ++errors; continue; }
            if (seen[i] || dense[i] != -1) ++errors; seen[i] = true;
        }
        for (bool exists : seen) if (!exists) ++errors;
        return errors;
    }
};

template<class T> void append_number(Dictionary &d, const T &key, double amount) {
    d[key] = double(d.get(key, 0.0)) + amount;
}
}

class JarjarCombatWorld : public RefCounted {
    GDCLASS(JarjarCombatWorld, RefCounted)
    Pool<Enemy> enemies;
    Pool<Projectile> projectiles;
    Pool<Xp> pickups;
    std::vector<Node> nodes;
    std::unordered_map<int64_t, int> enemy_slots;
    Grid grid;
    Grid separation_grid;
    std::vector<int64_t> separation_ids, separation_candidates;
    std::vector<Vector2> separation_positions;
    std::vector<int64_t> projectile_candidates, explosion_candidates, shape_candidates;
    std::vector<ProjectileIntersection> projectile_intersections;
    std::vector<Enemy *> target_candidates;
    mutable std::vector<int64_t> snapshot_ids, query_candidates;
    mutable std::vector<double> radius_values;
    double maximum_radius = 0;
    double attract_radius = 0, collect_radius = 0, attract_speed = 0;
    int64_t overflow_merges = 0;
    int64_t tick = 0;
    Vector2 player;
    double player_radius = 0, damage_radius = 0, node_radius = 0;
    Vector2 damage_center;
    bool stopped = false;
    struct Death { Enemy body; StringName source; double distance; };
    std::map<int64_t, Death> deaths;
    struct HitTotals {
        double damage = 0, maximum_damage = 0, maximum_center = 0, maximum_outer = 0;
        int64_t count = 0, visible = 0, enemy_type = 0;
        Vector2 position;
    };
    std::map<String, HitTotals> damage_totals;
    double effect_radius = 0, target_radius = 0;
    int64_t hit_glow_ticks = 0;
    std::map<StringName, Vector2i> weapon_visuals;

    Enemy *enemy(int64_t id) {
        auto found = enemy_slots.find(id);
        return found == enemy_slots.end() ? nullptr : &enemies.slots[found->second];
    }
    bool targetable(const Enemy &e) const { return e.alive && tick >= e.activation_tick; }
    bool eligible(const Enemy &e) const {
        return targetable(e) && e.hp > 0 && double(e.position.distance_squared_to(damage_center)) <= damage_radius * damage_radius;
    }
    bool in_damage(const Vector2 &p) const {
        return double(p.distance_squared_to(damage_center)) <= damage_radius * damage_radius;
    }
    static Vector2 contact_direction(uint64_t id) {
        const Vector2 directions[4] = { Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1) };
        return directions[id % 4];
    }
    bool acquirable(const Enemy &e) const {
        return targetable(e) && e.hp > 0 && double(e.position.distance_squared_to(player)) <= target_radius * target_radius;
    }
    Enemy *nearest(const Vector2 &origin) {
        Enemy *selected = nullptr; double distance = INFINITY;
        for (int i : enemies.active) {
            auto &e = enemies.slots[i]; if (!acquirable(e)) continue;
            double d = e.position.distance_squared_to(origin);
            if (!selected || d < distance || (d == distance && e.entity_id < selected->entity_id)) {
                selected = &e; distance = d;
            }
        }
        return selected;
    }
    void apply_damage(Enemy &e, double amount, const StringName &source, double outer) {
        double center = e.position.distance_to(player);
        if (!targetable(e) || center > damage_radius + .0001 || outer > effect_radius + .0001) return;
        double applied = std::min(e.hp, std::max(0.0, amount));
        if (applied <= 0) return;
        e.hp = std::max(0.0, e.hp - applied); e.hit_flash_until_tick = tick + hit_glow_ticks;
        auto &h = damage_totals[String(source)];
        h.damage += applied; ++h.count; if (in_damage(e.position)) ++h.visible;
        h.maximum_damage = std::max(h.maximum_damage, applied);
        h.maximum_center = std::max(h.maximum_center, center); h.maximum_outer = std::max(h.maximum_outer, outer);
        h.position = e.position; h.enemy_type = e.enemy_type;
        if (e.hp <= 0 && !deaths.count(e.entity_id)) deaths.emplace(e.entity_id, Death{e, source, center});
    }
    void hit(Enemy &e, Projectile &p, const Vector2 &position, double outer, bool apply, Array &records) {
        if (apply) apply_damage(e, p.damage, p.source_effect_id, outer);
        else {
            Dictionary record;
            record["entity_id"] = e.entity_id; record["damage"] = p.damage;
            record["source_effect_id"] = p.source_effect_id; record["source_entity_id"] = p.source_entity_id;
            record["position"] = position; record["direction"] = p.velocity.normalized();
            record["weapon_id"] = p.weapon_id; record["effect_outer_distance"] = outer;
            records.push_back(record);
        }
    }
    void damage_node_circle(const Vector2 &center, double radius, double damage, Array &destroyed) {
        if (damage <= 0) return;
        double combined = std::max(0.0, radius) + node_radius;
        for (int i = 0; i < int(nodes.size()); ++i) {
            auto &n = nodes[i];
            if (!n.active || n.hp <= 0 || double(n.position.distance_squared_to(center)) > combined * combined) continue;
            n.hp = std::max(0.0, n.hp - damage);
            if (n.hp <= 0) destroyed.push_back(i);
        }
    }
    static Transform3D enemy_transform(const Enemy &e) {
        const double heights[6] = { 1.0, .65, 1.35, 1.1, 1.7, 2.4 };
        double height = heights[std::clamp(int(e.enemy_type), 0, 5)], diameter = std::max(.35, e.radius / .4);
        return Transform3D(Basis().scaled(Vector3(real_t(diameter), real_t(height), real_t(diameter))), Vector3(e.position.x, real_t(.5 * height), e.position.y));
    }
    static Transform3D projectile_transform(const Projectile &p) {
        double progress = p.total_lifetime_ticks > 0 ? std::clamp(p.elapsed_ticks / double(p.total_lifetime_ticks), 0.0, 1.0) : 0;
        double height = .35 + (p.movement_kind == 2 ? 1.8 * 4.0 * progress * (1.0 - progress) : 0.0);
        return Transform3D(Basis().scaled(Vector3(1, 1, 1) * real_t(std::max(.25, p.radius / .16))), Vector3(p.position.x, real_t(height), p.position.y));
    }
    static void append_transform(std::vector<float> &buffer, const Transform3D &t) {
        // MultiMesh.buffer uses three row-major vec4 rows, including translation.
        for (int row = 0; row < 3; ++row) {
            for (int column = 0; column < 3; ++column) buffer.push_back(t.basis[row][column]);
            buffer.push_back(t.origin[row]);
        }
    }
    static void append_color(std::vector<float> &buffer, const Color &color) {
        buffer.insert(buffer.end(), {color.r, color.g, color.b, color.a});
    }
    static PackedFloat32Array packed_buffer(const std::vector<float> &buffer) {
        PackedFloat32Array result; result.resize(int64_t(buffer.size()));
        if (!buffer.empty()) std::copy(buffer.begin(), buffer.end(), result.ptrw()); return result;
    }

protected:
    static void _bind_methods();

public:
    int64_t api_version() const { return 3; }
    bool configure_pool(int kind, int capacity) {
        if (kind == 0) {
            bool result = enemies.resize(capacity);
            if (!result) return false;
            const size_t count = size_t(capacity);
            grid.reserve(count); separation_grid.reserve(count);
            separation_ids.reserve(count); separation_candidates.reserve(count); separation_positions.reserve(count);
            projectile_candidates.reserve(count); explosion_candidates.reserve(count); projectile_intersections.reserve(count);
            shape_candidates.reserve(count); target_candidates.reserve(count);
            snapshot_ids.reserve(count); query_candidates.reserve(count); radius_values.reserve(count);
            for (int i : enemies.free) enemies.slots[i].alive = false;
            return result;
        }
        if (kind == 1) return projectiles.resize(capacity);
        if (kind == 2) return pickups.resize(capacity);
        return false;
    }
    Dictionary pool_stats(int kind) const {
        if (kind == 0) return enemies.stats();
        if (kind == 1) return projectiles.stats();
        Dictionary result = pickups.stats(); result["overflow_merges"] = overflow_merges; return result;
    }
    Array pool_indices(int kind) const {
        if (kind == 0) return enemies.indices();
        if (kind == 1) return projectiles.indices();
        return pickups.indices();
    }
    int pool_orphans(int kind) const {
        if (kind == 0) return enemies.orphan_count();
        if (kind == 1) return projectiles.orphan_count();
        return pickups.orphan_count();
    }
    void reset_reuse(int kind) {
        if (kind == 0) enemies.reused = 0;
        else if (kind == 1) projectiles.reused = 0;
        else pickups.reused = 0;
    }
    void record_enemy_overflow() { ++enemies.overflow; }
    void clear_pool(int kind) {
        if (kind == 0) {
            enemies.clear(); enemy_slots.clear(); grid.clear();
            for (auto &e : enemies.slots) e.alive = false;
            deaths.clear(); damage_totals.clear();
        } else if (kind == 1) projectiles.clear();
        else { pickups.clear(); overflow_merges = 0; }
    }

#define GET_FIELD(type, name, initial) if (key == StringName(#name)) return s.name;
#define SET_FIELD(type, name, initial) if (key == StringName(#name)) { s.name = type(value); return; }
    Variant enemy_get(int slot, const StringName &key) const {
        if (slot < 0 || slot >= int(enemies.slots.size())) return Variant();
        const auto &s = enemies.slots[slot]; JARJAR_ENEMY_FIELDS(GET_FIELD) return Variant();
    }
    void enemy_set(int slot, const StringName &key, const Variant &value) {
        if (slot < 0 || slot >= int(enemies.slots.size())) return;
        auto &s = enemies.slots[slot]; JARJAR_ENEMY_FIELDS(SET_FIELD)
    }
    Variant projectile_get(int slot, const StringName &key) const {
        if (slot < 0 || slot >= int(projectiles.slots.size())) return Variant();
        const auto &s = projectiles.slots[slot]; JARJAR_PROJECTILE_FIELDS(GET_FIELD) return Variant();
    }
    void projectile_set(int slot, const StringName &key, const Variant &value) {
        if (slot < 0 || slot >= int(projectiles.slots.size())) return;
        auto &s = projectiles.slots[slot]; JARJAR_PROJECTILE_FIELDS(SET_FIELD)
    }
    Variant xp_get(int slot, const StringName &key) const {
        if (slot < 0 || slot >= int(pickups.slots.size())) return Variant();
        const auto &s = pickups.slots[slot]; JARJAR_XP_FIELDS(GET_FIELD) return Variant();
    }
    void xp_set(int slot, const StringName &key, const Variant &value) {
        if (slot < 0 || slot >= int(pickups.slots.size())) return;
        auto &s = pickups.slots[slot]; JARJAR_XP_FIELDS(SET_FIELD)
    }
    Variant node_get(int slot, const StringName &key) const {
        if (slot < 0 || slot >= int(nodes.size())) return Variant();
        const auto &s = nodes[slot]; JARJAR_NODE_FIELDS(GET_FIELD) return Variant();
    }
    void node_set(int slot, const StringName &key, const Variant &value) {
        if (slot < 0 || slot >= int(nodes.size())) return;
        auto &s = nodes[slot]; JARJAR_NODE_FIELDS(SET_FIELD)
    }
#undef GET_FIELD
#undef SET_FIELD

    int spawn_enemy(const Dictionary &data) {
        int64_t id = data.get("entity_id", -1);
        if (id < 0 || enemy_slots.count(id)) return -1;
        int slot = enemies.acquire(); if (slot < 0) return -1;
        auto &s = enemies.slots[slot];
#define READ_FIELD(type, name, initial) if (data.has(#name)) s.name = type(data[#name]);
        JARJAR_ENEMY_FIELDS(READ_FIELD)
        s.radius = data.get("radius", 0.0); s.move_speed = data.get("move_speed", 0.0);
        s.contact_damage = data.get("contact_damage", 0.0); s.xp_value = data.get("xp_value", 0);
        s.special_interval = data.get("special_interval", 0); s.telegraph_ticks = data.get("telegraph_ticks", 0);
        s.alive = true; enemy_slots[id] = slot;
        return slot;
    }
    int spawn_projectile(const Dictionary &data) {
        int slot = projectiles.acquire(); if (slot < 0) return -1;
        auto &s = projectiles.slots[slot]; JARJAR_PROJECTILE_FIELDS(READ_FIELD)
        s.active = true; s.visual_kind = data.get("visual_kind", 0); s.evolved = data.get("evolved", false);
        return slot;
    }
#undef READ_FIELD
    int spawn_projectile_pattern(const Dictionary &data, const PackedVector2Array &positions, const PackedVector2Array &directions, const Vector2 &origin, int64_t serial, int count, int64_t born_tick) {
        if (positions.is_empty() || directions.is_empty() || serial < 0 || count <= 0) return 0;
        Projectile base;
#define READ_PATTERN(type, name, initial) if (data.has(#name)) base.name = type(data[#name]);
        JARJAR_PROJECTILE_FIELDS(READ_PATTERN)
#undef READ_PATTERN
        int spawned = 0;
        for (int n = 0; n < count; ++n) {
            int slot = projectiles.acquire(); if (slot < 0) break;
            auto &p = projectiles.slots[slot]; int64_t generation = p.generation;
            p = base; p.generation = generation; p.active = true;
            Vector2 direction = directions[(serial + n) % directions.size()];
            p.position = origin + positions[(serial + n) % positions.size()]; p.previous_position = p.position;
            p.velocity = direction * real_t(p.speed); p.target_position = p.position + direction * real_t(p.remaining_distance);
            p.previous_remaining_distance = p.remaining_distance; p.born_tick = born_tick;
            ++spawned;
        }
        return spawned;
    }
    void trim_projectiles(int count) {
        while (int(projectiles.active.size()) > std::max(0, count)) release_projectile(projectiles.active.back(), -1);
    }
    bool remove_enemy(int64_t id) {
        auto found = enemy_slots.find(id); if (found == enemy_slots.end()) return false;
        int i = found->second; enemies.release(i); enemy_slots.erase(found);
        enemies.slots[i].alive = false; return true;
    }
    int enemy_slot(int64_t id) const {
        auto found = enemy_slots.find(id); return found == enemy_slots.end() ? -1 : found->second;
    }
    Array enemy_ids() const {
        auto &ids = snapshot_ids; ids.clear();
        for (int i : enemies.active) ids.push_back(enemies.slots[i].entity_id);
        std::sort(ids.begin(), ids.end()); Array result;
        for (auto id : ids) result.push_back(id); return result;
    }
    bool release_projectile(int slot, int64_t generation) {
        if (!projectiles.release(slot, generation)) return false;
        projectiles.slots[slot].active = false; return true;
    }
    bool projectile_valid(int slot, int64_t generation) const { return projectiles.valid(slot, generation); }
    void projectile_clear_hits(int slot) {
        if (slot >= 0 && slot < int(projectiles.slots.size())) projectiles.slots[slot].hit_enemies.clear();
    }
    void projectile_mark_hit(int slot, int64_t id) {
        if (projectiles.valid(slot)) projectiles.slots[slot].hit_enemies.insert(id);
    }
    PackedInt64Array projectile_handles() const {
        PackedInt64Array result;
        result.resize(int64_t(projectiles.active.size()) * 2);
        int64_t *data = result.ptrw();
        for (int i : projectiles.active) {
            *data++ = i; *data++ = projectiles.slots[i].generation;
        }
        return result;
    }
    int add_node() { nodes.emplace_back(); return int(nodes.size()) - 1; }
    void clear_nodes() { nodes.clear(); }

    void configure_xp(double attraction, double collection, double speed) {
        attract_radius = attraction; collect_radius = collection; attract_speed = speed;
    }
    int spawn_xp(const Vector2 &position, int64_t value, int64_t born_tick, const Vector2 &player_position) {
        if (value <= 0) return -1;
        if (pickups.free.empty()) {
            int farthest = -1; double distance = -1;
            for (int i : pickups.active) {
                double d = pickups.slots[i].position.distance_squared_to(player_position);
                if (d > distance) { distance = d; farthest = i; }
            }
            if (farthest >= 0) { pickups.slots[farthest].value += value; ++overflow_merges; }
            return farthest;
        }
        int i = pickups.acquire(); auto &s = pickups.slots[i];
        s.active = true; s.position = position; s.value = value; s.born_tick = born_tick;
        return i;
    }
    bool release_xp(int slot, int64_t generation) {
        if (!pickups.release(slot, generation)) return false;
        pickups.slots[slot].active = false; pickups.slots[slot].vacuum = false; return true;
    }
    int64_t collect_xp(const Vector2 &position, double delta, int64_t current_tick) {
        int64_t value = 0; size_t p = 0;
        const double step = attract_speed * std::max(0.0, delta);
        while (p < pickups.active.size()) {
            int i = pickups.active[p]; auto &s = pickups.slots[i];
            if (s.born_tick >= current_tick) { ++p; continue; }
            double d = s.position.distance_squared_to(position);
            if (s.vacuum || d <= attract_radius * attract_radius) {
                s.position = s.position.move_toward(position, real_t(step));
                d = s.position.distance_squared_to(position);
            }
            if (d > collect_radius * collect_radius) { ++p; continue; }
            value += s.value; release_xp(i, s.generation);
        }
        return value;
    }
    int vacuum_xp() { for (int i : pickups.active) pickups.slots[i].vacuum = true; return int(pickups.active.size()); }
    int64_t xp_total_value() const {
        int64_t result = 0; for (int i : pickups.active) result += pickups.slots[i].value; return result;
    }
    void shift_pool(int kind, const Vector2 &offset) {
        if (kind == 0) {
            for (int i : enemies.active) {
                auto &s = enemies.slots[i]; s.position -= offset; s.telegraph_position -= offset;
            }
        } else if (kind == 1) {
            for (int i : projectiles.active) {
                auto &s = projectiles.slots[i]; s.position -= offset; s.previous_position -= offset; s.target_position -= offset;
            }
        } else for (int i : pickups.active) pickups.slots[i].position -= offset;
    }
    Transform3D xp_transform(int slot) const {
        const auto &s = pickups.slots[slot];
        double scale = 1.0 + std::min(1.0, std::log(double(std::max(int64_t(1), s.value))) * 0.08);
        return Transform3D(Basis().scaled(Vector3(1, 1, 1) * real_t(scale)), Vector3(s.position.x, .22f, s.position.y));
    }
    Array xp_transforms() const {
        Array result; for (int i : pickups.active) result.push_back(xp_transform(i)); return result;
    }
    PackedVector3Array xp_columns() const {
        PackedVector3Array result; result.resize(int64_t(pickups.slots.size()) * 4);
        for (int i : pickups.active) {
            Transform3D t = xp_transform(i);
            for (int j = 0; j < 3; ++j) result.set(i * 4 + j, t.basis.get_column(j));
            result.set(i * 4 + 3, t.origin);
        }
        return result;
    }

    void set_context(const Dictionary &context) {
        tick = context["tick"]; player = context["player"]; damage_center = player;
        player_radius = context["player_radius"]; target_radius = context["target_radius"];
        damage_radius = context["damage_radius"]; effect_radius = context["effect_radius"];
        node_radius = context["node_radius"]; stopped = context["stopped"];
        hit_glow_ticks = context["hit_glow_ticks"];
    }
    Array important_ids() const {
        Array result;
        for (int i : enemies.active) if (enemies.slots[i].enemy_type >= 4) result.push_back(enemies.slots[i].entity_id);
        result.sort(); return result;
    }
    int64_t first_enemy_of_type(int type) const {
        for (int i : enemies.active) if (enemies.slots[i].enemy_type == type) return enemies.slots[i].entity_id;
        return -1;
    }
    int normal_count() const {
        int count = 0;
        for (int i : enemies.active) {
            const auto &e = enemies.slots[i]; if (e.enemy_type < 4 && !e.is_swarm_event && e.encounter_owner_id < 0) ++count;
        }
        return count;
    }
    bool has_swarm() const {
        for (int i : enemies.active) if (enemies.slots[i].is_swarm_event) return true;
        return false;
    }
    void rebuild_grid(int64_t current_tick) {
        tick = current_tick; grid.clear(); grid.cell_size = 2.0; maximum_radius = 0;
        for (int i : enemies.active) {
            const auto &e = enemies.slots[i]; if (!targetable(e)) continue;
            grid.insert(e.entity_id, e.position); maximum_radius = std::max(maximum_radius, e.radius);
        }
    }
    double grid_maximum_radius() const { return maximum_radius; }
    Array body_radii() const {
        auto &radii = radius_values; radii.clear();
        for (int i : enemies.active) radii.push_back(enemies.slots[i].radius);
        std::sort(radii.begin(), radii.end()); radii.erase(std::unique(radii.begin(), radii.end()), radii.end());
        Array result; for (double radius : radii) result.push_back(radius); return result;
    }
    void insert_enemy_index(int64_t id, const Vector2 &position) { grid.insert(id, position); }
    Array query_enemies(const Vector2 &lower, const Vector2 &upper) const {
        auto &candidates = query_candidates; grid.query(lower, upper, candidates);
        Array result; for (auto id : candidates) result.push_back(id); return result;
    }
    void separate_enemies(const Array &ids, int64_t current_tick) {
        tick = current_tick;
        auto &sorted = separation_ids; sorted.clear();
        for (int64_t n = 0; n < ids.size(); ++n) {
            int64_t id = ids[n]; Enemy *e = enemy(id); if (e && targetable(*e)) sorted.push_back(id);
        }
        if (!std::is_sorted(sorted.begin(), sorted.end())) std::sort(sorted.begin(), sorted.end());
        sorted.erase(std::unique(sorted.begin(), sorted.end()), sorted.end());
        auto &separation = separation_grid; separation.clear(); separation.cell_size = 2.0; double max_radius = 0;
        auto &positions = separation_positions; positions.clear();
        for (auto id : sorted) {
            Enemy &e = *enemy(id); positions.push_back(e.position); separation.insert(id, e.position);
            max_radius = std::max(max_radius, e.radius);
        }
        auto &candidates = separation_candidates;
        for (size_t i = 0; i < sorted.size(); ++i) {
            Enemy &e = *enemy(sorted[i]); Vector2 position = e.position;
            Vector2 extent = Vector2(1, 1) * real_t(e.radius + max_radius);
            separation.query(positions[i] - extent, positions[i] + extent, candidates);
            std::sort(candidates.begin(), candidates.end());
            for (auto id : candidates) {
                if (id <= e.entity_id) continue;
                Enemy &other = *enemy(id); Vector2 offset = other.position - position;
                double d2 = offset.length_squared(), contact = e.radius + other.radius;
                if (d2 >= contact * contact) continue;
                double d = std::sqrt(d2);
                Vector2 direction = d > 0 ? offset / real_t(d) : contact_direction(uint64_t(e.entity_id) + uint64_t(id));
                Vector2 correction = direction * real_t((contact - d) * .5);
                position -= correction; other.position += correction;
            }
            e.position = position;
        }
    }
    Dictionary advance_enemies(const Array &ids, const Vector2 &position, int64_t current_tick, const Dictionary &config) {
        tick = current_tick; player = position;
        double body_radius = config["player_radius"], boss_scale = config["boss_scale"];
        bool stop = config["stopped"], despawn = config["despawn"];
        Dictionary retention = config["retention"];
        Array exited, special; int far_count = 0, exits = 0;
        for (int64_t n = 0; n < ids.size(); ++n) {
            int64_t id = ids[n]; Enemy *e = enemy(id); if (!e) continue;
            if (e->enemy_type == 5) special.push_back(id);
            if (despawn && e->enemy_type < 4 && !e->is_swarm_event && e->encounter_owner_id < 0 && retention.has(e->radius)) {
                Rect2 bounds = retention[e->radius];
                if (!bounds.has_point(e->position)) { remove_enemy(id); ++far_count; continue; }
            }
            if (!targetable(*e)) continue;
            double scale = stop ? (e->enemy_type == 5 ? boss_scale : 0.0) : 1.0;
            if (scale <= 0) continue;
            double step = e->move_speed * scale / 60.0;
            if (e->movement_kind == 1) {
                double travel = std::min(e->remaining_travel_distance, step);
                e->position += e->fixed_direction * real_t(travel);
                e->remaining_travel_distance = std::max(0.0, e->remaining_travel_distance - travel);
                if (e->remaining_travel_distance <= 0) exited.push_back(id);
            } else if (e->encounter_owner_id >= 0) e->position = e->position.move_toward(player, real_t(step));
            else {
                Vector2 offset = e->position - player; double distance = offset.length();
                Vector2 direction = distance > 0 ? offset / real_t(distance) : contact_direction(uint64_t(id));
                double contact = body_radius + e->radius;
                if (distance < contact) e->position = player + direction * real_t(contact);
                else if (distance > contact) e->position -= direction * real_t(std::min(step, distance - contact));
            }
            if (e->special_interval > 0) e->special_elapsed_ticks += scale;
            if (e->boss_charge_active) e->boss_charge_elapsed_ticks += scale;
            if (e->enemy_type == 5) e->boss_action_age_ticks += scale;
            if (e->telegraph_active) e->telegraph_elapsed_ticks += scale;
        }
        separate_enemies(ids, current_tick);
        for (int64_t n = 0; n < exited.size(); ++n) if (remove_enemy(exited[n])) ++exits;
        // EnemySystem rebuilds after the boss boundary correction, before spawns.
        Dictionary result; result["special"] = special; result["far_despawns"] = far_count; result["swarm_exits"] = exits;
        return result;
    }
    Array visible_counts(const Vector2 &position, int64_t current_tick, double visible_radius, double engaged_radius) const {
        int visible = 0, engaged = 0, materializing = 0, normal = 0, normal_engaged = 0;
        for (int i : enemies.active) {
            const auto &e = enemies.slots[i]; double d = e.position.distance_squared_to(position);
            bool ready = current_tick >= e.activation_tick;
            if (!ready) ++materializing;
            if (d <= visible_radius * visible_radius) ++visible;
            if (ready && d <= engaged_radius * engaged_radius) ++engaged;
            if (e.enemy_type < 4 && !e.is_swarm_event && e.encounter_owner_id < 0) {
                ++normal; if (ready) ++normal_engaged;
            }
        }
        Array result; result.push_back(visible); result.push_back(engaged); result.push_back(materializing);
        result.push_back(normal); result.push_back(normal_engaged); return result;
    }
    int64_t nearest_enemy(const Vector2 &origin) { Enemy *e = nearest(origin); return e ? e->entity_id : -1; }
    Array target_ids(const Vector2 &origin, bool by_distance, double travel_limit) {
        auto &candidates = target_candidates; candidates.clear();
        for (int i : enemies.active) {
            auto &e = enemies.slots[i]; if (!acquirable(e)) continue;
            if (travel_limit >= 0 && e.position.distance_to(player) > travel_limit + e.radius) continue;
            candidates.push_back(&e);
        }
        std::sort(candidates.begin(), candidates.end(), [origin, by_distance](const Enemy *a, const Enemy *b) {
            double x = a->position.distance_squared_to(origin), y = b->position.distance_squared_to(origin);
            return by_distance && x != y ? x < y : a->entity_id < b->entity_id;
        });
        Array result; for (const Enemy *e : candidates) result.push_back(e->entity_id); return result;
    }
    Dictionary choose_target_shots(int amount, double travel_limit, const Dictionary &damage, const Ref<RandomNumberGenerator> &rng) {
        Array ids = target_ids(player, false, travel_limit), shots;
        Dictionary result; result["direction"] = Vector2();
        if (!ids.is_empty()) {
            result["direction"] = (enemy(ids[0])->position - player).normalized();
            for (int i = 0; i < amount; ++i) {
                int64_t index = rng.is_valid() ? rng->randi_range(0, int32_t(ids.size() - 1)) : 0;
                Enemy &e = *enemy(ids[index]); double value = damage["base"], chance = damage["chance"];
                if (chance > 0 && rng.is_valid() && rng->randf() < std::clamp(chance, 0.0, 1.0)) value *= std::max(1.0, double(damage["multiplier"]));
                Dictionary shot; shot["id"] = e.entity_id; shot["direction"] = (e.position - player).normalized(); shot["damage"] = value;
                shots.push_back(shot);
            }
        }
        result["shots"] = shots; return result;
    }
    void move_projectiles(const PackedInt64Array &entries) {
        if (entries.size() % 2 != 0) return;
        const int64_t *handles = entries.ptr();
        for (int64_t n = 0; n < entries.size(); n += 2) {
            int64_t raw_slot = handles[n], generation = handles[n + 1];
            if (raw_slot < 0 || raw_slot >= int64_t(projectiles.slots.size()) || generation <= 0) continue;
            int slot = int(raw_slot);
            if (!projectiles.valid(slot, generation)) continue;
            auto &p = projectiles.slots[slot]; if (p.born_tick >= tick) continue;
            double scale = stopped && p.faction == StringName("enemy") ? p.stop_time_scale : 1.0;
            p.previous_position = p.position; p.previous_remaining_distance = p.remaining_distance; p.expired_this_tick = false;
            if (scale <= 0) continue;
            if (p.movement_kind == 1) {
                Enemy *e = enemy(p.target_entity_id);
                if (!e || !acquirable(*e)) { e = nearest(p.position); p.target_entity_id = e ? e->entity_id : -1; }
                if (e) p.velocity = (e->position - p.position).normalized() * real_t(p.speed);
            } else if (p.movement_kind == 3 && p.outbound_distance_remaining <= .0001) {
                if (!p.return_phase_started) { p.hit_enemies.clear(); p.return_phase_started = true; }
                p.target_position = player; p.velocity = (player - p.position).normalized() * real_t(p.speed);
                p.remaining_distance = std::min(p.remaining_distance, double(p.position.distance_to(player)));
            }
            Vector2 movement = p.velocity * real_t(scale) / real_t(60.0);
            double limit = p.remaining_distance;
            if (p.movement_kind == 3 && !p.return_phase_started) limit = std::min(limit, p.outbound_distance_remaining);
            movement = movement.limit_length(real_t(std::max(0.0, limit))); p.position += movement;
            p.remaining_distance = std::max(0.0, p.remaining_distance - double(movement.length()));
            if (p.movement_kind == 3 && !p.return_phase_started) p.outbound_distance_remaining = std::max(0.0, p.outbound_distance_remaining - double(movement.length()));
            p.remaining_lifetime = std::max(0.0, p.remaining_lifetime - scale / 60.0); p.elapsed_ticks += scale;
            p.expired_this_tick = p.remaining_distance <= 0 || p.remaining_lifetime <= 0;
        }
    }
    Array damage_projectile_nodes(const PackedInt64Array &entries) {
        Array destroyed;
        if (entries.size() % 2 != 0) return destroyed;
        const int64_t *handles = entries.ptr();
        for (int64_t n = 0; n < entries.size(); n += 2) {
            int64_t raw_slot = handles[n], generation = handles[n + 1];
            if (raw_slot < 0 || raw_slot >= int64_t(projectiles.slots.size()) || generation <= 0) continue;
            int slot = int(raw_slot);
            if (!projectiles.valid(slot, generation)) continue;
            auto &p = projectiles.slots[slot];
            if (p.faction != StringName("ally") || p.movement_kind == 2 || p.damage <= 0) continue;
            for (int i = 0; i < int(nodes.size()); ++i) {
                auto &node = nodes[i]; if (!node.active || node.hp <= 0 || p.hit_nodes.count(node.node_id)) continue;
                if (segment_circle_first_t(p.previous_position, p.position, node.position, std::max(0.0, p.radius) + node_radius, 1e-6) < 0) continue;
                p.hit_nodes.insert(node.node_id); node.hp = std::max(0.0, node.hp - p.damage);
                if (node.hp <= 0) destroyed.push_back(i);
            }
        }
        return destroyed;
    }
    Dictionary resolve_projectiles(const PackedInt64Array &entries, bool apply, bool affect_nodes) {
        if (entries.size() % 2 != 0) return Dictionary();
        Array records, resolutions, destroyed;
        auto &candidates = projectile_candidates;
        auto &intersections = projectile_intersections;
        const int64_t *handles = entries.ptr();
        for (int64_t n = 0; n < entries.size(); n += 2) {
            int64_t raw_slot = handles[n], generation = handles[n + 1];
            if (raw_slot < 0 || raw_slot >= int64_t(projectiles.slots.size()) || generation <= 0) continue;
            int slot = int(raw_slot);
            if (!projectiles.valid(slot, generation)) continue;
            auto &p = projectiles.slots[slot];
            if (p.faction != StringName("ally") || p.born_tick >= tick) continue;
            double permitted = effect_radius - std::max(p.radius, p.explosion_radius) + .0001;
            if (permitted < 0 || segment_circle_first_t(p.previous_position, p.position, player, permitted, 1e-6) < 0) {
                release_projectile(slot, generation); continue;
            }
            Vector2 extent = Vector2(1, 1) * real_t(std::max(0.0, p.radius) + maximum_radius + .01);
            grid.query(p.previous_position.min(p.position) - extent, p.previous_position.max(p.position) + extent, candidates);
            intersections.clear();
            const bool arc = p.movement_kind == 2;
            ProjectileIntersection first;
            for (auto id : candidates) {
                auto found = enemy_slots.find(id); if (found == enemy_slots.end()) continue;
                const Enemy &e = enemies.slots[found->second];
                if (!eligible(e) || p.hit_enemies.count(id)) continue;
                double t = segment_circle_first_t(p.previous_position, p.position, e.position, p.radius + e.radius, 1e-6);
                if (!(t >= 0)) continue;
                ProjectileIntersection intersection{t, id, found->second};
                if (arc) { if (intersection < first) first = intersection; }
                else intersections.push_back(intersection);
            }
            if (arc) {
                bool impacted = first.slot >= 0;
                if (impacted) p.position = p.previous_position.lerp(p.position, real_t(first.time));
                double outer = player.distance_to(p.position) + std::max(p.radius, p.explosion_radius);
                if ((impacted || p.expired_this_tick) && outer <= effect_radius + .0001) {
                    if (!apply) {
                        Dictionary resolution; resolution["arc_impact_position"] = p.position;
                        resolution["arc_explosion_radius"] = p.explosion_radius; resolution["arc_damage"] = p.damage;
                        resolutions.push_back(resolution);
                    }
                    double radius = std::max(p.radius, p.explosion_radius);
                    extent = Vector2(1, 1) * real_t(radius + maximum_radius + .01);
                    grid.query(p.position - extent, p.position + extent, explosion_candidates);
                    for (auto id : explosion_candidates) {
                        Enemy *e = enemy(id);
                        if (e && eligible(*e) && e->position.distance_squared_to(p.position) <= (radius + e->radius) * (radius + e->radius))
                            hit(*e, p, p.position, outer, apply, records);
                    }
                    if (affect_nodes) damage_node_circle(p.position, p.explosion_radius, p.damage, destroyed);
                }
                if (impacted || p.expired_this_tick || outer > effect_radius + .0001) release_projectile(slot, generation);
                continue;
            }
            const size_t count = intersections.size();
            const bool sort_all = p.pierce_remaining >= int64_t(count) - 1;
            auto later = [](const ProjectileIntersection &a, const ProjectileIntersection &b) { return b < a; };
            if (sort_all) std::sort(intersections.begin(), intersections.end());
            else std::make_heap(intersections.begin(), intersections.end(), later);
            for (size_t index = 0; index < count; ++index) {
                ProjectileIntersection intersection;
                if (sort_all) intersection = intersections[index];
                else {
                    std::pop_heap(intersections.begin(), intersections.end(), later);
                    intersection = intersections.back(); intersections.pop_back();
                }
                // Slots cannot be recycled inside this stage; deaths remain pending.
                Enemy &e = enemies.slots[intersection.slot]; if (!eligible(e)) continue;
                Vector2 position = p.previous_position.lerp(p.position, real_t(intersection.time));
                double outer = player.distance_to(position) + p.radius;
                if (outer > effect_radius + .0001) continue;
                p.hit_enemies.insert(e.entity_id); hit(e, p, position, outer, apply, records);
                if (--p.pierce_remaining < 0) { release_projectile(slot, generation); break; }
            }
            if (p.active && (p.expired_this_tick || player.distance_to(p.position) + std::max(p.radius, p.explosion_radius) > effect_radius + .0001)) release_projectile(slot, generation);
        }
        Dictionary result; result["hits"] = records; result["resolutions"] = resolutions; result["destroyed_nodes"] = destroyed;
        return result;
    }
    Array hostile_projectile_hits(const PackedInt64Array &entries) {
        Array result;
        if (entries.size() % 2 != 0) return result;
        const int64_t *handles = entries.ptr();
        for (int64_t n = 0; n < entries.size(); n += 2) {
            int64_t raw_slot = handles[n], generation = handles[n + 1];
            if (raw_slot < 0 || raw_slot >= int64_t(projectiles.slots.size()) || generation <= 0) continue;
            int slot = int(raw_slot);
            if (!projectiles.valid(slot, generation)) continue;
            auto &p = projectiles.slots[slot];
            if (p.faction != StringName("enemy") || p.born_tick >= tick || (stopped && p.stop_time_scale <= 0)) continue;
            if (segment_circle_first_t(p.previous_position, p.position, player, p.radius + player_radius, 1e-6) >= 0) {
                Dictionary hit; hit["raw_damage"] = p.damage; hit["source_entity_id"] = p.source_entity_id;
                hit["source_pool_index"] = slot; hit["source_generation"] = p.generation; hit["source_effect_id"] = p.source_effect_id;
                result.push_back(hit); release_projectile(slot, generation);
            } else if (p.expired_this_tick) release_projectile(slot, generation);
        }
        return result;
    }
    Array contact_hits(const Array &ids, double boss_multiplier, double boss_stop_scale) {
        Array result;
        for (int64_t n = 0; n < ids.size(); ++n) {
            Enemy *e = enemy(ids[n]); if (!e || !targetable(*e) || (stopped && (e->enemy_type != 5 || boss_stop_scale <= 0))) continue;
            double contact = player_radius + e->radius;
            if (e->position.distance_squared_to(player) > contact * contact + 1e-6) continue;
            Dictionary hit; hit["type"] = StringName("player_damage"); hit["source_entity_id"] = e->entity_id;
            hit["source_pool_index"] = enemy_slot(e->entity_id); hit["source_generation"] = e->generation;
            hit["source_effect_id"] = StringName("enemy_contact"); hit["position"] = e->position;
            hit["raw_damage"] = e->contact_damage * e->damage_multiplier * (e->enemy_type == 5 ? boss_multiplier : 1.0);
            result.push_back(hit);
        }
        return result;
    }
    void apply_hits(const Array &records) {
        for (int64_t i = 0; i < records.size(); ++i) {
            Dictionary record = records[i]; Enemy *e = enemy(record.get("entity_id", -1));
            if (e) apply_damage(*e, record.get("damage", 0.0), record.get("source_effect_id", StringName()), record.get("effect_outer_distance", 0.0));
        }
    }
    Dictionary attack_shapes(const Array &shapes, const Dictionary &attack, const Ref<RandomNumberGenerator> &rng) {
        double damage = attack["damage"], chance = attack["critical_chance"], critical = attack["critical_multiplier"], outer = attack["outer"];
        StringName source = attack["source"];
        bool deduplicate = attack["deduplicate"];
        std::unordered_set<int64_t> hit_ids; auto &candidates = shape_candidates;
        int64_t hits = 0; Array destroyed;
        for (int64_t i = 0; i < shapes.size(); ++i) {
            if (!deduplicate) hit_ids.clear();
            Dictionary shape = shapes[i]; Vector2 center = shape["center"]; double radius = shape["radius"];
            bool fan = shape.has("direction"); Vector2 direction = shape.get("direction", Vector2());
            double cosine = std::cos(double(shape.get("arc_degrees", 0.0)) * 3.14159265358979323846 / 360.0);
            Vector2 extent = Vector2(1, 1) * real_t(radius + maximum_radius + .01);
            grid.query(center - extent, center + extent, candidates);
            for (auto id : candidates) {
                Enemy *e = enemy(id); if (!e || !eligible(*e) || hit_ids.count(id)) continue;
                Vector2 offset = e->position - center; double r = radius + e->radius;
                if (offset.length_squared() > r * r) continue;
                if (fan && offset.length_squared() > 1e-6 && (direction == Vector2() || direction.normalized().dot(offset.normalized()) < cosine - 1e-6)) continue;
                hit_ids.insert(id); double amount = damage;
                if (chance > 0 && rng.is_valid() && rng->randf() < std::clamp(chance, 0.0, 1.0)) amount *= std::max(1.0, critical);
                apply_damage(*e, amount, source, outer); ++hits;
            }
            damage_node_circle(center, radius, damage, destroyed);
        }
        Dictionary result; result["hit_count"] = hits; result["destroyed_nodes"] = destroyed; return result;
    }
    Array take_damage_totals() {
        Array result;
        for (const auto &pair : damage_totals) {
            const auto &h = pair.second; Dictionary row;
            row["source"] = StringName(pair.first); row["damage"] = h.damage; row["count"] = h.count;
            row["visible"] = h.visible; row["maximum_damage"] = h.maximum_damage; row["maximum_center"] = h.maximum_center;
            row["maximum_outer"] = h.maximum_outer; row["position"] = h.position; row["enemy_type"] = h.enemy_type;
            result.push_back(row);
        }
        damage_totals.clear(); return result;
    }
    void mark_death(int64_t id, const StringName &source, double distance) {
        Enemy *e = enemy(id); if (e && !deaths.count(id)) deaths.emplace(id, Death{*e, source, std::max(0.0, distance)});
    }
    Dictionary finish_deaths(int64_t current_tick, const Vector2 &position, int ordinary_effect_limit) {
        Array effects, important; int ordinary_effects = 0, omitted_effects = 0;
        struct Group { int64_t count = 0, xp = 0, visible = 0; Vector2 position; double maximum_center = 0; };
        std::map<std::tuple<String, int, bool, bool>, Group> groups;
        int merge_slot = -1;
        for (const auto &pair : deaths) {
            const auto &death = pair.second; const auto &e = death.body;
            if (!remove_enemy(e.entity_id)) continue;
            // Once full, every further reward can merge into the same farthest
            // pickup. Its position does not change during the death stage.
            if (pickups.free.empty() && merge_slot >= 0 && e.xp_value > 0) {
                pickups.slots[merge_slot].value += e.xp_value; ++overflow_merges;
            } else {
                int slot = spawn_xp(e.position, e.xp_value, current_tick, position);
                if (pickups.free.empty() && slot >= 0) {
                    merge_slot = -1; double farthest = -1;
                    for (int i : pickups.active) {
                        double d = pickups.slots[i].position.distance_squared_to(position);
                        if (d > farthest) { farthest = d; merge_slot = i; }
                    }
                }
            }
            auto &group = groups[std::make_tuple(String(death.source), int(e.enemy_type), e.is_swarm_event, e.encounter_owner_id >= 0)];
            ++group.count; group.xp += e.xp_value; group.position = e.position;
            group.maximum_center = std::max(group.maximum_center, death.distance);
            if (double(e.position.distance_squared_to(position)) <= damage_radius * damage_radius) ++group.visible;
            bool is_important = e.enemy_type >= 4;
            if (!is_important && ordinary_effects >= ordinary_effect_limit) { ++omitted_effects; continue; }
            Dictionary row;
            row["entity_id"] = e.entity_id; row["enemy_type"] = e.enemy_type; row["position"] = e.position;
            row["body_radius"] = e.radius; row["xp_value"] = e.xp_value; row["elite_serial"] = e.elite_serial;
            row["source_effect_id"] = death.source; row["center_distance"] = death.distance;
            row["is_swarm_event"] = e.is_swarm_event; row["is_encircler"] = e.encounter_owner_id >= 0;
            if (is_important) important.push_back(row);
            else ++ordinary_effects;
            effects.push_back(row);
        }
        Array totals;
        for (const auto &pair : groups) {
            const auto &key = pair.first; const auto &group = pair.second; Dictionary row;
            row["source_effect_id"] = StringName(std::get<0>(key)); row["enemy_type"] = std::get<1>(key);
            row["is_swarm_event"] = std::get<2>(key); row["is_encircler"] = std::get<3>(key);
            row["count"] = group.count; row["xp"] = group.xp; row["visible"] = group.visible;
            row["position"] = group.position; row["maximum_center"] = group.maximum_center;
            totals.push_back(row);
        }
        Dictionary result; result["groups"] = totals; result["effects"] = effects;
        result["important"] = important; result["omitted_effects"] = omitted_effects;
        deaths.clear(); return result;
    }
    void configure_visuals(const Dictionary &definitions) {
        weapon_visuals.clear(); Array keys = definitions.keys();
        for (int64_t i = 0; i < keys.size(); ++i) weapon_visuals[StringName(keys[i])] = definitions[keys[i]];
    }
    Dictionary render_snapshot(int64_t current_tick, bool reduce_motion, bool reduce_flashes, const Array &orbitals, bool evolved_orbitals) const {
        std::vector<float> enemy_buffers[8], projectile_buffers[10], accents[3], xp_buffer;
        Array enemy_transforms, projectile_transforms, xp_values;
        PackedInt32Array enemy_kinds, projectile_kinds; PackedColorArray enemy_custom, projectile_custom;
        std::vector<int> ordered = enemies.active;
        std::sort(ordered.begin(), ordered.end(), [this](int a, int b) { return enemies.slots[a].entity_id < enemies.slots[b].entity_id; });
        for (int i : ordered) {
            const auto &e = enemies.slots[i]; Transform3D t = enemy_transform(e);
            int kind = e.encounter_owner_id >= 0 ? 7 : e.is_swarm_event && e.swarm_red_variant ? 6 : std::clamp(int(e.enemy_type), 0, 5);
            double progress = e.activation_tick > e.spawn_tick ? std::clamp(double(current_tick - e.spawn_tick) / double(e.activation_tick - e.spawn_tick), 0.0, 1.0) : 1.0;
            Color custom(real_t(progress), current_tick < e.hit_flash_until_tick ? 1.f : 0.f, reduce_motion ? 1.f : 0.f, reduce_flashes ? 1.f : 0.f);
            enemy_transforms.push_back(t); enemy_kinds.push_back(kind); enemy_custom.push_back(custom);
            double scale = .12 + .88 * progress * progress * (3.0 - 2.0 * progress);
            t.basis = t.basis.scaled(Vector3(1, 1, 1) * real_t(scale));
            append_transform(enemy_buffers[kind], t); append_color(enemy_buffers[kind], custom);
        }
        auto append_projectile = [&](const Transform3D &t, int kind, bool evolved, double progress) {
            Color custom(evolved ? 1.f : 0.f, real_t(progress), reduce_motion ? 1.f : 0.f, reduce_flashes ? 1.f : 0.f);
            projectile_transforms.push_back(t); projectile_kinds.push_back(kind); projectile_custom.push_back(custom);
            append_transform(projectile_buffers[kind], t); append_color(projectile_buffers[kind], custom);
            if (evolved) {
                Transform3D inner = t, outer = t, core = t;
                inner.basis = inner.basis * Basis(Vector3(0, 1, 0), real_t(3.14159265358979323846 / 12));
                outer.basis = outer.basis * Basis(Vector3(0, 1, 0), real_t(3.14159265358979323846 / 18));
                core.basis = core.basis.scaled(Vector3(1.2f, 1.2f, 1.2f));
                append_transform(accents[0], inner); append_transform(accents[1], outer); append_transform(accents[2], core);
            }
        };
        for (int i : projectiles.active) {
            const auto &p = projectiles.slots[i];
            auto found = weapon_visuals.find(p.weapon_id);
            if (found == weapon_visuals.end()) found = weapon_visuals.find(p.source_effect_id);
            int kind = p.faction == StringName("enemy") ? 9 : found == weapon_visuals.end() ? 0 : found->second.x;
            bool evolved = found != weapon_visuals.end() && found->second.y != 0;
            double progress = p.total_lifetime_ticks > 0 ? std::clamp(p.elapsed_ticks / double(p.total_lifetime_ticks), 0.0, 1.0) : 0;
            append_projectile(projectile_transform(p), kind, evolved, progress);
        }
        for (int64_t i = 0; i < orbitals.size(); ++i) append_projectile(orbitals[i], 6, evolved_orbitals, 1.0);
        for (int i : pickups.active) {
            Transform3D t = xp_transform(i); xp_values.push_back(t); append_transform(xp_buffer, t);
        }
        Array enemy_buckets, projectile_buckets, accent_buffers;
        for (const auto &b : enemy_buffers) enemy_buckets.push_back(packed_buffer(b));
        for (const auto &b : projectile_buffers) projectile_buckets.push_back(packed_buffer(b));
        for (const auto &b : accents) accent_buffers.push_back(packed_buffer(b));
        Dictionary result;
        result["enemy_transforms"] = enemy_transforms; result["enemy_kinds"] = enemy_kinds; result["enemy_custom"] = enemy_custom;
        result["projectile_transforms"] = projectile_transforms; result["projectile_kinds"] = projectile_kinds; result["projectile_custom"] = projectile_custom;
        result["xp_transforms"] = xp_values; result["enemy_buffers"] = enemy_buckets; result["projectile_buffers"] = projectile_buckets;
        result["accent_buffers"] = accent_buffers; result["xp_buffer"] = packed_buffer(xp_buffer);
        return result;
    }
    PackedFloat32Array pack_visuals(const Array &transforms, const Array &colors, const Array &custom_data) const {
        std::vector<float> buffer;
        buffer.reserve(size_t(transforms.size()) * (12 + (colors.is_empty() ? 0 : 4) + (custom_data.is_empty() ? 0 : 4)));
        for (int64_t i = 0; i < transforms.size(); ++i) {
            append_transform(buffer, transforms[i]);
            if (!colors.is_empty()) append_color(buffer, colors[i]);
            if (!custom_data.is_empty()) append_color(buffer, custom_data[i]);
        }
        return packed_buffer(buffer);
    }
    // Render geometry only. No IDs, HP, RNG, cooldowns or hidden future actions.
    Dictionary public_enemy_geometry(int64_t current_tick) const {
        PackedVector2Array positions; PackedInt32Array kinds, shapes; PackedByteArray materializing;
        TypedArray<Transform3D> templates; std::map<std::pair<int, double>, int> template_indices;
        for (int i : enemies.active) {
            const auto &e = enemies.slots[i];
            int kind = e.encounter_owner_id >= 0 ? 7 : e.is_swarm_event && e.swarm_red_variant ? 6 : std::clamp(int(e.enemy_type), 0, 5);
            auto key = std::make_pair(kind, e.radius); auto found = template_indices.find(key);
            if (found == template_indices.end()) {
                int index = int(templates.size()); templates.push_back(enemy_transform(e));
                found = template_indices.emplace(key, index).first;
            }
            positions.push_back(e.position); kinds.push_back(kind); shapes.push_back(found->second);
            materializing.push_back(current_tick < e.activation_tick ? 1 : 0);
        }
        Dictionary result;
        result["positions"] = positions; result["kinds"] = kinds; result["shapes"] = shapes;
        result["materializing"] = materializing; result["templates"] = templates; result["radius_factor"] = .4;
        return result;
    }
    Dictionary public_projectile_geometry() const {
        PackedVector3Array hostile, needles; PackedInt32Array hostile_indices, needle_indices;
        for (int i : projectiles.active) {
            const auto &p = projectiles.slots[i]; bool enemy = p.faction == StringName("enemy");
            auto found = weapon_visuals.find(p.weapon_id);
            if (found == weapon_visuals.end()) found = weapon_visuals.find(p.source_effect_id);
            if (!enemy && (found == weapon_visuals.end() || found->second.x != 3)) continue;
            auto &columns = enemy ? hostile : needles; auto &indices = enemy ? hostile_indices : needle_indices;
            Transform3D t = projectile_transform(p); indices.push_back(int32_t(indices.size()));
            for (int j = 0; j < 3; ++j) columns.push_back(t.basis.get_column(j)); columns.push_back(t.origin);
        }
        Dictionary result; result["hostile"] = hostile; result["hostile_indices"] = hostile_indices;
        result["needles"] = needles; result["needle_indices"] = needle_indices; return result;
    }
};

// BINDINGS
void JarjarCombatWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("api_version"), &JarjarCombatWorld::api_version);
    ClassDB::bind_method(D_METHOD("configure_pool", "kind", "capacity"), &JarjarCombatWorld::configure_pool);
    ClassDB::bind_method(D_METHOD("pool_stats", "kind"), &JarjarCombatWorld::pool_stats);
    ClassDB::bind_method(D_METHOD("pool_indices", "kind"), &JarjarCombatWorld::pool_indices);
    ClassDB::bind_method(D_METHOD("pool_orphans", "kind"), &JarjarCombatWorld::pool_orphans);
    ClassDB::bind_method(D_METHOD("reset_reuse", "kind"), &JarjarCombatWorld::reset_reuse);
    ClassDB::bind_method(D_METHOD("record_enemy_overflow"), &JarjarCombatWorld::record_enemy_overflow);
    ClassDB::bind_method(D_METHOD("clear_pool", "kind"), &JarjarCombatWorld::clear_pool);
    ClassDB::bind_method(D_METHOD("enemy_get", "slot", "key"), &JarjarCombatWorld::enemy_get);
    ClassDB::bind_method(D_METHOD("enemy_set", "slot", "key", "value"), &JarjarCombatWorld::enemy_set);
    ClassDB::bind_method(D_METHOD("projectile_get", "slot", "key"), &JarjarCombatWorld::projectile_get);
    ClassDB::bind_method(D_METHOD("projectile_set", "slot", "key", "value"), &JarjarCombatWorld::projectile_set);
    ClassDB::bind_method(D_METHOD("xp_get", "slot", "key"), &JarjarCombatWorld::xp_get);
    ClassDB::bind_method(D_METHOD("xp_set", "slot", "key", "value"), &JarjarCombatWorld::xp_set);
    ClassDB::bind_method(D_METHOD("node_get", "slot", "key"), &JarjarCombatWorld::node_get);
    ClassDB::bind_method(D_METHOD("node_set", "slot", "key", "value"), &JarjarCombatWorld::node_set);
    ClassDB::bind_method(D_METHOD("spawn_enemy", "data"), &JarjarCombatWorld::spawn_enemy);
    ClassDB::bind_method(D_METHOD("spawn_projectile", "data"), &JarjarCombatWorld::spawn_projectile);
    ClassDB::bind_method(D_METHOD("spawn_projectile_pattern", "data", "positions", "directions", "origin", "serial", "count", "born_tick"), &JarjarCombatWorld::spawn_projectile_pattern);
    ClassDB::bind_method(D_METHOD("trim_projectiles", "count"), &JarjarCombatWorld::trim_projectiles);
    ClassDB::bind_method(D_METHOD("remove_enemy", "id"), &JarjarCombatWorld::remove_enemy);
    ClassDB::bind_method(D_METHOD("enemy_slot", "id"), &JarjarCombatWorld::enemy_slot);
    ClassDB::bind_method(D_METHOD("enemy_ids"), &JarjarCombatWorld::enemy_ids);
    ClassDB::bind_method(D_METHOD("release_projectile", "slot", "generation"), &JarjarCombatWorld::release_projectile);
    ClassDB::bind_method(D_METHOD("projectile_valid", "slot", "generation"), &JarjarCombatWorld::projectile_valid);
    ClassDB::bind_method(D_METHOD("projectile_clear_hits", "slot"), &JarjarCombatWorld::projectile_clear_hits);
    ClassDB::bind_method(D_METHOD("projectile_mark_hit", "slot", "id"), &JarjarCombatWorld::projectile_mark_hit);
    ClassDB::bind_method(D_METHOD("projectile_handles"), &JarjarCombatWorld::projectile_handles);
    ClassDB::bind_method(D_METHOD("add_node"), &JarjarCombatWorld::add_node);
    ClassDB::bind_method(D_METHOD("clear_nodes"), &JarjarCombatWorld::clear_nodes);
    ClassDB::bind_method(D_METHOD("configure_xp", "attraction", "collection", "speed"), &JarjarCombatWorld::configure_xp);
    ClassDB::bind_method(D_METHOD("spawn_xp", "position", "value", "born_tick", "player_position"), &JarjarCombatWorld::spawn_xp);
    ClassDB::bind_method(D_METHOD("release_xp", "slot", "generation"), &JarjarCombatWorld::release_xp);
    ClassDB::bind_method(D_METHOD("collect_xp", "position", "delta", "current_tick"), &JarjarCombatWorld::collect_xp);
    ClassDB::bind_method(D_METHOD("vacuum_xp"), &JarjarCombatWorld::vacuum_xp);
    ClassDB::bind_method(D_METHOD("xp_total_value"), &JarjarCombatWorld::xp_total_value);
    ClassDB::bind_method(D_METHOD("shift_pool", "kind", "offset"), &JarjarCombatWorld::shift_pool);
    ClassDB::bind_method(D_METHOD("xp_transform", "slot"), &JarjarCombatWorld::xp_transform);
    ClassDB::bind_method(D_METHOD("xp_transforms"), &JarjarCombatWorld::xp_transforms);
    ClassDB::bind_method(D_METHOD("xp_columns"), &JarjarCombatWorld::xp_columns);
    ClassDB::bind_method(D_METHOD("set_context", "context"), &JarjarCombatWorld::set_context);
    ClassDB::bind_method(D_METHOD("important_ids"), &JarjarCombatWorld::important_ids);
    ClassDB::bind_method(D_METHOD("first_enemy_of_type", "type"), &JarjarCombatWorld::first_enemy_of_type);
    ClassDB::bind_method(D_METHOD("normal_count"), &JarjarCombatWorld::normal_count);
    ClassDB::bind_method(D_METHOD("has_swarm"), &JarjarCombatWorld::has_swarm);
    ClassDB::bind_method(D_METHOD("rebuild_grid", "current_tick"), &JarjarCombatWorld::rebuild_grid);
    ClassDB::bind_method(D_METHOD("grid_maximum_radius"), &JarjarCombatWorld::grid_maximum_radius);
    ClassDB::bind_method(D_METHOD("body_radii"), &JarjarCombatWorld::body_radii);
    ClassDB::bind_method(D_METHOD("insert_enemy_index", "id", "position"), &JarjarCombatWorld::insert_enemy_index);
    ClassDB::bind_method(D_METHOD("query_enemies", "lower", "upper"), &JarjarCombatWorld::query_enemies);
    ClassDB::bind_method(D_METHOD("separate_enemies", "ids", "current_tick"), &JarjarCombatWorld::separate_enemies);
    ClassDB::bind_method(D_METHOD("advance_enemies", "ids", "position", "current_tick", "config"), &JarjarCombatWorld::advance_enemies);
    ClassDB::bind_method(D_METHOD("visible_counts", "position", "current_tick", "visible_radius", "engaged_radius"), &JarjarCombatWorld::visible_counts);
    ClassDB::bind_method(D_METHOD("nearest_enemy", "origin"), &JarjarCombatWorld::nearest_enemy);
    ClassDB::bind_method(D_METHOD("target_ids", "origin", "by_distance", "travel_limit"), &JarjarCombatWorld::target_ids);
    ClassDB::bind_method(D_METHOD("choose_target_shots", "amount", "travel_limit", "damage", "rng"), &JarjarCombatWorld::choose_target_shots);
    ClassDB::bind_method(D_METHOD("move_projectiles", "entries"), &JarjarCombatWorld::move_projectiles);
    ClassDB::bind_method(D_METHOD("damage_projectile_nodes", "entries"), &JarjarCombatWorld::damage_projectile_nodes);
    ClassDB::bind_method(D_METHOD("resolve_projectiles", "entries", "apply", "affect_nodes"), &JarjarCombatWorld::resolve_projectiles);
    ClassDB::bind_method(D_METHOD("hostile_projectile_hits", "entries"), &JarjarCombatWorld::hostile_projectile_hits);
    ClassDB::bind_method(D_METHOD("contact_hits", "ids", "boss_multiplier", "boss_stop_scale"), &JarjarCombatWorld::contact_hits);
    ClassDB::bind_method(D_METHOD("apply_hits", "records"), &JarjarCombatWorld::apply_hits);
    ClassDB::bind_method(D_METHOD("attack_shapes", "shapes", "attack", "rng"), &JarjarCombatWorld::attack_shapes);
    ClassDB::bind_method(D_METHOD("take_damage_totals"), &JarjarCombatWorld::take_damage_totals);
    ClassDB::bind_method(D_METHOD("mark_death", "id", "source", "distance"), &JarjarCombatWorld::mark_death);
    ClassDB::bind_method(D_METHOD("finish_deaths", "current_tick", "position", "ordinary_effect_limit"), &JarjarCombatWorld::finish_deaths);
    ClassDB::bind_method(D_METHOD("configure_visuals", "definitions"), &JarjarCombatWorld::configure_visuals);
    ClassDB::bind_method(D_METHOD("render_snapshot", "current_tick", "reduce_motion", "reduce_flashes", "orbitals", "evolved_orbitals"), &JarjarCombatWorld::render_snapshot);
    ClassDB::bind_method(D_METHOD("pack_visuals", "transforms", "colors", "custom_data"), &JarjarCombatWorld::pack_visuals);
    ClassDB::bind_method(D_METHOD("public_enemy_geometry", "current_tick"), &JarjarCombatWorld::public_enemy_geometry);
    ClassDB::bind_method(D_METHOD("public_projectile_geometry"), &JarjarCombatWorld::public_projectile_geometry);
}

void register_combat_world() { GDREGISTER_CLASS(JarjarCombatWorld); }
