#pragma once
#include <godot_cpp/variant/vector2.hpp>
#include <vector>
#include <algorithm>

// An inward half-plane inferred from a visible line, never a hidden arena radius.
struct BotBoundary {
    godot::Vector2 point, normal;
    double speed = 0.0;
    int64_t seen_tick = 0;
};

inline godot::Vector2 bot_constrain(const godot::Vector2 &position, double radius,
        const std::vector<BotBoundary> &boundaries, double seconds = 0.0) {
    godot::Vector2 result = position;
    // Alternating projections handle adjacent faces and clipped corner views.
    for (int pass = 0; pass < 3; ++pass) {
        bool changed = false;
        for (const BotBoundary &wall : boundaries) {
            double missing = radius + wall.speed * seconds - double((result - wall.point).dot(wall.normal));
            if (missing > 0.000001) {
                result += wall.normal * float(missing);
                changed = true;
            }
        }
        if (!changed) break;
    }
    return result;
}

inline bool bot_inside(const godot::Vector2 &position, double radius,
        const std::vector<BotBoundary> &boundaries, double seconds = 0.0) {
    for (const BotBoundary &wall : boundaries)
        if (double((position - wall.point).dot(wall.normal)) < radius + wall.speed * seconds - 0.0001) return false;
    return true;
}
