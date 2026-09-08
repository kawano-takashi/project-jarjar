#pragma once
#include "bot_boundary.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/a_star_grid2d.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/projection.hpp>
#include <map>
#include <vector>

class JarjarBotNavigation : public godot::RefCounted {
    GDCLASS(JarjarBotNavigation, godot::RefCounted)
    godot::Ref<godot::AStarGrid2D> grid;
    godot::Vector2 origin;
    godot::Vector2i dimensions;
    double cell_size = 1.0;
    godot::Dictionary loot_memory;
    godot::Vector2i cell(const godot::Vector2 &position) const;
protected:
    struct Track {
        godot::Vector2 position, velocity;
        double radius = 0.0;
        int kind = 0;
        int64_t seen_tick = 0;
        bool materializing = false, fixed = false;
    };
    std::vector<Track> enemies, bullets;
    std::vector<BotBoundary> boundaries;
    int64_t boundary_tick = 0;
    std::vector<BotBoundary> predicted_boundaries() const;
    std::map<int, double> enemy_speeds;
    std::map<int, double> contact_damage;
    std::vector<double> route_risk;
    double tracking_cell = 0.75, swarm_speed = 0.0;
    int64_t memory_ticks = 120;
    int swarmer_kind = 0, red_kind = 0, boss_kind = 0;
    std::vector<Track> track_bodies(const godot::Dictionary &data, const std::vector<Track> &old, const godot::Dictionary &frame, bool bullet) const;
    static void _bind_methods();
public:
    void observe_boundaries(const godot::PackedVector4Array &segments, const godot::PackedVector2Array &normals, int64_t tick);
    void clear_combat_memory();
    void configure(const godot::Vector2 &p_origin, const godot::Vector2i &p_dimensions, double p_cell_size);
    void recenter(const godot::Vector2 &p_origin);
    void shift_origin(const godot::Vector2 &displacement);
    godot::Vector2 route(const godot::Vector2 &player, const godot::Vector2 &goal, const godot::PackedVector2Array &positions, const godot::PackedFloat64Array &radii, double player_radius);
    godot::PackedInt32Array match_tracks(const godot::PackedVector2Array &predicted, const godot::PackedInt32Array &old_kinds, const godot::PackedVector2Array &observed, const godot::PackedInt32Array &kinds, double track_cell) const;
    void remember_loot(const godot::PackedVector4Array &loot, const godot::Transform3D &inverse, const godot::Vector2i &viewport, int64_t tick, const godot::Projection &projection, int xp_kind);
    godot::Vector3 choose_loot_goal(const godot::Dictionary &frame) const;
    void configure_tracking(const godot::Dictionary &data);
    void observe_tracks(const godot::Dictionary &frame);
    godot::Vector3 first_boss_position() const;
    godot::Vector2 route_tracked(const godot::Vector2 &player, const godot::Vector2 &goal, double player_radius);
};
