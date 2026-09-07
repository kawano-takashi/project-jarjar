#pragma once
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/plane.hpp>
#include <godot_cpp/variant/projection.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <array>
#include <cmath>
#include <utility>

// All inputs come from the observed camera, including its near/far clipping.
struct BotFrustum {
    godot::Transform3D inverse;
    godot::Projection projection;
    std::array<godot::Plane, 6> planes;
    enum Coverage { OUTSIDE, PARTIAL, INSIDE };

    BotFrustum(const godot::Transform3D &p_inverse, const godot::Projection &p_projection)
        : inverse(p_inverse), projection(p_projection) {
        for (int i = 0; i < 6; ++i) planes[size_t(i)] = projection.get_projection_plane(godot::Projection::Planes(i));
    }

    Coverage classify(const godot::AABB &bounds) const {
        godot::Vector3 center = bounds.get_center(), half_size = bounds.size * 0.5f;
        Coverage coverage = INSIDE;
        for (const godot::Plane &plane : planes) {
            double distance = plane.distance_to(center), radius = plane.normal.abs().dot(half_size);
            if (distance > radius) return OUTSIDE;
            if (distance > -radius) coverage = PARTIAL;
        }
        return coverage;
    }

    bool triangle_visible(godot::Vector3 a, godot::Vector3 b, godot::Vector3 c) const {
        // Clipping a triangle against six planes needs at most nine vertices.
        std::array<godot::Vector3, 12> buffer_a{a, b, c}, buffer_b;
        godot::Vector3 *polygon = buffer_a.data(), *clipped = buffer_b.data();
        std::array<double, 12> distances;
        int count = 3;
        for (const godot::Plane &plane : planes) {
            int inside_count = 0;
            for (int i = 0; i < count; ++i) {
                distances[size_t(i)] = plane.distance_to(polygon[size_t(i)]);
                if (distances[size_t(i)] <= 0.0) ++inside_count;
            }
            // An all-inside pass previously copied the same vertices in the
            // same order. Keep that polygon without copying either buffer.
            // Do not test later planes early: clipping can round new vertices.
            if (inside_count == count) continue;
            if (inside_count == 0) return false;
            int output_count = 0;
            godot::Vector3 previous = polygon[size_t(count - 1)];
            double previous_distance = distances[size_t(count - 1)];
            for (int i = 0; i < count; ++i) {
                godot::Vector3 current = polygon[size_t(i)];
                double distance = distances[size_t(i)];
                if ((previous_distance <= 0.0) != (distance <= 0.0)) {
                    clipped[size_t(output_count++)] = previous.lerp(current, float(previous_distance / (previous_distance - distance)));
                }
                if (distance <= 0.0) clipped[size_t(output_count++)] = current;
                previous = current;
                previous_distance = distance;
            }
            if (output_count < 3) return false;
            std::swap(polygon, clipped);
            count = output_count;
        }
        // Reject edge-on/tangent triangles. Divide only after near clipping.
        std::array<godot::Vector2, 12> screen;
        for (int i = 0; i < count; ++i) {
            const godot::Vector3 &point = polygon[size_t(i)];
            godot::Vector4 clip = projection.xform(godot::Vector4(point.x, point.y, point.z, 1.0f));
            if (clip.w <= 0.0f) return false;
            screen[size_t(i)] = godot::Vector2(clip.x, clip.y) / clip.w;
        }
        double area = 0.0;
        for (int i = 2; i < count; ++i) {
            godot::Vector2 u = screen[size_t(i - 1)] - screen[0], v = screen[size_t(i)] - screen[0];
            area += double(u.x) * double(v.y) - double(u.y) * double(v.x);
        }
        return std::abs(area) > 1e-12;
    }
};

inline bool bot_point_inside_view(const godot::Vector3 &position, const godot::Transform3D &inverse,
        const godot::Projection &projection, const godot::Vector2i &viewport, float inset) {
    godot::Vector3 local = inverse.xform(position);
    godot::Vector4 clip = projection.xform(godot::Vector4(local.x, local.y, local.z, 1.0f));
    if (clip.w <= 0.0f || clip.z < -clip.w || clip.z > clip.w) return false;
    godot::Vector2 pixel = (godot::Vector2(clip.x, -clip.y) / clip.w + godot::Vector2(1, 1)) * godot::Vector2(viewport) * 0.5f;
    return godot::Rect2(godot::Vector2(), godot::Vector2(viewport)).grow(-inset).has_point(pixel);
}
