#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>

using namespace godot;

#include "combat_geometry.h"
void register_combat_world();


class JarjarCombatKernel : public RefCounted {
    GDCLASS(JarjarCombatKernel, RefCounted)

    struct Body { Vector2 position; double radius; };
    Grid index;
    Grid separation_index;
    std::unordered_map<int64_t, Body> damage_bodies;
    std::vector<int64_t> candidates;
    std::vector<int64_t> hit_ids;
    std::vector<double> hit_times;

protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("api_version"), &JarjarCombatKernel::api_version);
        ClassDB::bind_method(D_METHOD("clear_index", "cell_size"), &JarjarCombatKernel::clear_index);
        ClassDB::bind_method(D_METHOD("rebuild_index", "ids", "positions", "cell_size"), &JarjarCombatKernel::rebuild_index);
        ClassDB::bind_method(D_METHOD("insert_id", "id", "position"), &JarjarCombatKernel::insert_id);
        ClassDB::bind_method(D_METHOD("query_aabb", "first", "second"), &JarjarCombatKernel::query_aabb);
        ClassDB::bind_method(D_METHOD("set_damage_bodies", "ids", "positions", "radii"), &JarjarCombatKernel::set_damage_bodies);
        ClassDB::bind_method(D_METHOD("intersect_segments", "starts", "ends", "radii", "padding", "epsilon"), &JarjarCombatKernel::intersect_segments);
        ClassDB::bind_method(D_METHOD("resolve_bodies", "ids", "positions", "radii", "cell_size", "directions"), &JarjarCombatKernel::resolve_bodies);
    }

public:
    int64_t api_version() const { return 2; }

    void clear_index(double cell_size) {
        index.clear();
        damage_bodies.clear();
        ERR_FAIL_COND_MSG(!std::isfinite(cell_size) || cell_size <= 0.0, "Combat cell size must be positive and finite.");
        index.cell_size = cell_size;
    }

    void rebuild_index(const PackedInt64Array &ids, const PackedVector2Array &positions, double cell_size) {
        clear_index(cell_size);
        ERR_FAIL_COND_MSG(ids.size() != positions.size(), "Combat index arrays must have equal lengths.");
        for (int64_t i = 0; i < ids.size(); ++i) index.insert(ids[i], positions[i]);
    }

    void insert_id(int64_t id, const Vector2 &position) { index.insert(id, position); }

    TypedArray<int64_t> query_aabb(const Vector2 &first, const Vector2 &second) {
        index.query(first, second, candidates);
        TypedArray<int64_t> result;
        result.resize(int64_t(candidates.size()));
        for (size_t i = 0; i < candidates.size(); ++i) result[int64_t(i)] = candidates[i];
        return result;
    }

    void set_damage_bodies(const PackedInt64Array &ids, const PackedVector2Array &positions, const PackedFloat64Array &radii) {
        damage_bodies.clear();
        ERR_FAIL_COND_MSG(ids.size() != positions.size() || ids.size() != radii.size(), "Combat body arrays must have equal lengths.");
        for (int64_t i = 0; i < ids.size(); ++i) damage_bodies.emplace(ids[i], Body{positions[i], radii[i]});
    }

    Array intersect_segments(const PackedVector2Array &starts, const PackedVector2Array &ends,
                             const PackedFloat64Array &radii, double padding, double epsilon) {
        ERR_FAIL_COND_V_MSG(starts.size() != ends.size() || starts.size() != radii.size(), Array(), "Combat segment arrays must have equal lengths.");
        hit_ids.clear();
        hit_times.clear();
        PackedInt32Array offsets;
        offsets.resize(starts.size() + 1);
        int32_t *offset_data = offsets.ptrw();
        offset_data[0] = 0;
        for (int64_t segment = 0; segment < starts.size(); ++segment) {
            const Vector2 start = starts[segment], end = ends[segment];
            const double radius = radii[segment];
            const Vector2 extent = Vector2(1, 1) * real_t(std::max(0.0, radius + padding));
            index.query(start.min(end) - extent, start.max(end) + extent, candidates);
            for (int64_t id : candidates) {
                const auto found = damage_bodies.find(id);
                if (found == damage_bodies.end()) continue;
                const Body &body = found->second;
                const double t = segment_circle_first_t(start, end, body.position, radius + body.radius, epsilon);
                if (t < 0.0) continue;
                hit_ids.push_back(id);
                hit_times.push_back(t);
            }
            offset_data[segment + 1] = int32_t(hit_ids.size());
        }
        PackedInt64Array ids;
        PackedFloat64Array times;
        ids.resize(int64_t(hit_ids.size()));
        times.resize(int64_t(hit_times.size()));
        if (!hit_ids.empty()) {
            std::copy(hit_ids.begin(), hit_ids.end(), ids.ptrw());
            std::copy(hit_times.begin(), hit_times.end(), times.ptrw());
        }
        Array result;
        result.push_back(offsets);
        result.push_back(ids);
        result.push_back(times);
        return result;
    }

    PackedVector2Array resolve_bodies(const PackedInt64Array &ids, const PackedVector2Array &positions,
                                     const PackedFloat64Array &radii, double cell_size,
                                     const PackedVector2Array &directions) {
        ERR_FAIL_COND_V_MSG(ids.size() != positions.size() || ids.size() != radii.size(), PackedVector2Array(), "Combat separation arrays must have equal lengths.");
        ERR_FAIL_COND_V_MSG(cell_size <= 0.0 || !std::isfinite(cell_size) || directions.is_empty(), PackedVector2Array(), "Combat separation requires a positive cell size and contact directions.");
        separation_index.clear();
        separation_index.cell_size = cell_size;
        double maximum_radius = 0.0;
        for (int64_t i = 0; i < ids.size(); ++i) {
            separation_index.insert(i, positions[i]);
            maximum_radius = std::max(maximum_radius, radii[i]);
        }
        PackedVector2Array result = positions;
        Vector2 *corrected = result.ptrw();
        // The index stays fixed throughout this pass; corrections are sequential.
        for (int64_t i = 0; i < ids.size(); ++i) {
            Vector2 position = corrected[i];
            const double radius = radii[i];
            const Vector2 extent = Vector2(1, 1) * real_t(std::max(0.0, radius) + std::max(0.0, maximum_radius));
            separation_index.query(positions[i] - extent, positions[i] + extent, candidates);
            std::sort(candidates.begin(), candidates.end());
            for (int64_t other : candidates) {
                if (other <= i) continue;
                const Vector2 offset = corrected[other] - position;
                const double distance_squared = offset.length_squared();
                const double contact_radius = radius + radii[other];
                if (distance_squared >= contact_radius * contact_radius) continue;
                const double distance = std::sqrt(distance_squared);
                // Positive entity IDs use the same cyclic contact direction as GDScript.
                const uint64_t direction_index = (uint64_t(ids[i]) + uint64_t(ids[other])) % uint64_t(directions.size());
                const Vector2 direction = distance > 0.0 ? offset / real_t(distance) : directions[int64_t(direction_index)];
                const Vector2 correction = direction * real_t((contact_radius - distance) * 0.5);
                position -= correction;
                corrected[other] += correction;
            }
            corrected[i] = position;
        }
        return result;
    }
};

static void initialize_combat(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) {
        GDREGISTER_CLASS(JarjarCombatKernel);
        register_combat_world();
    }
}
static void uninitialize_combat(ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT jarjar_combat_init(GDExtensionInterfaceGetProcAddress get_proc_address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address, library, initialization);
    init.register_initializer(initialize_combat);
    init.register_terminator(uninitialize_combat);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
