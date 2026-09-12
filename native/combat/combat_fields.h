#pragma once
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <cstdint>
using namespace godot;

#define JARJAR_ENEMY_FIELDS(X) \
    X(int64_t, generation, 0) \
    X(int64_t, entity_id, -1) \
    X(int64_t, enemy_type, 0) \
    X(Vector2, position, Vector2()) \
    X(double, hp, 0.0) \
    X(double, max_hp, 0.0) \
    X(double, damage_multiplier, 1.0) \
    X(int64_t, born_tick, 0) \
    X(int64_t, spawn_tick, 0) \
    X(int64_t, activation_tick, 0) \
    X(double, special_elapsed_ticks, 0.0) \
    X(double, telegraph_elapsed_ticks, 0.0) \
    X(bool, telegraph_active, false) \
    X(Vector2, telegraph_position, Vector2()) \
    X(bool, barrage_alternate, false) \
    X(bool, boss_charge_active, false) \
    X(double, boss_charge_elapsed_ticks, 0.0) \
    X(int64_t, boss_charge_interval_ticks, 0) \
    X(int64_t, boss_charge_spoke_count, 0) \
    X(bool, boss_charge_half_step, false) \
    X(double, boss_action_age_ticks, 0.0) \
    X(int64_t, hit_flash_until_tick, -1) \
    X(bool, alive, true) \
    X(int64_t, elite_serial, -1) \
    X(int64_t, boss_phase, 0) \
    X(int64_t, movement_kind, 0) \
    X(int64_t, swarm_group_id, -1) \
    X(Vector2, fixed_direction, Vector2()) \
    X(double, remaining_travel_distance, 0.0) \
    X(bool, swarm_red_variant, false) \
    X(bool, is_swarm_event, false) \
    X(int64_t, encounter_owner_id, -1)

#define JARJAR_PROJECTILE_FIELDS(X) \
    X(int64_t, generation, 0) \
    X(bool, active, false) \
    X(StringName, faction, StringName("")) \
    X(StringName, weapon_id, StringName("")) \
    X(int64_t, source_entity_id, -1) \
    X(Vector2, position, Vector2()) \
    X(Vector2, previous_position, Vector2()) \
    X(Vector2, velocity, Vector2()) \
    X(double, radius, 0.0) \
    X(double, damage, 0.0) \
    X(double, remaining_distance, 0.0) \
    X(double, previous_remaining_distance, 0.0) \
    X(double, outbound_distance_remaining, 0.0) \
    X(double, remaining_lifetime, 0.0) \
    X(Vector2, target_position, Vector2()) \
    X(int64_t, pierce_remaining, 0) \
    X(int64_t, born_tick, 0) \
    X(StringName, source_effect_id, StringName("")) \
    X(int64_t, movement_kind, 0) \
    X(int64_t, target_entity_id, -1) \
    X(double, speed, 0.0) \
    X(double, elapsed_ticks, 0.0) \
    X(int64_t, total_lifetime_ticks, 0) \
    X(int64_t, return_after_ticks, 0) \
    X(bool, return_phase_started, false) \
    X(double, explosion_radius, 0.0) \
    X(double, stop_time_scale, 0.0) \
    X(bool, expired_this_tick, false)

#define JARJAR_XP_FIELDS(X) \
    X(int64_t, generation, 0) \
    X(bool, active, false) \
    X(Vector2, position, Vector2()) \
    X(int64_t, value, 0) \
    X(int64_t, born_tick, 0)

#define JARJAR_NODE_FIELDS(X) \
    X(int64_t, node_id, -1) \
    X(Vector2, position, Vector2()) \
    X(double, hp, 0.0) \
    X(bool, active, false)
