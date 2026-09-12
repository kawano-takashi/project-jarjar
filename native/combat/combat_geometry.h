#pragma once
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <unordered_map>
#include <unordered_set>
#include <vector>
using namespace godot;
namespace {

// GDScript scalars are double, but each Vector2 operation rounds to real_t.
// Keep intermediate scalar results double and cast at vector operator boundaries.
struct Grid {
    using Cells = std::unordered_map<uint64_t, std::vector<int64_t>>;
    using Ids = std::unordered_set<int64_t>;
    double cell_size = 1.0;
    Cells cells;
    Ids inserted;
    std::vector<Cells::node_type> spare_cells;
    std::vector<Ids::node_type> spare_ids;
    size_t reserved = 0;
    bool unique = true;

    void reserve(size_t count) {
        if (count <= reserved) return;
        cells.reserve(count); inserted.reserve(count);
        spare_cells.reserve(count); spare_ids.reserve(count);
        reserved = count;
    }

    static uint64_t key(int32_t x, int32_t y) {
        return (uint64_t(uint32_t(x)) << 32) | uint32_t(y);
    }

    Vector2i cell(const Vector2 &position) const {
        return Vector2i(int32_t(std::floor(double(position.x) / cell_size)),
                        int32_t(std::floor(double(position.y) / cell_size)));
    }

    void clear() {
        // Recycle nodes and their vectors without retaining historical coordinates.
        while (!cells.empty()) {
            auto node = cells.extract(cells.begin());
            node.mapped().clear();
            spare_cells.push_back(std::move(node));
        }
        while (!inserted.empty()) spare_ids.push_back(inserted.extract(inserted.begin()));
        unique = true;
    }

    void insert(int64_t id, const Vector2 &position) {
        if (spare_ids.empty()) {
            if (!inserted.insert(id).second) unique = false;
        } else {
            auto node = std::move(spare_ids.back()); spare_ids.pop_back();
            node.value() = id;
            auto result = inserted.insert(std::move(node));
            if (!result.inserted) { unique = false; spare_ids.push_back(std::move(result.node)); }
        }
        const Vector2i location = cell(position);
        uint64_t cell_key = key(location.x, location.y);
        auto found = cells.find(cell_key);
        if (found == cells.end()) {
            if (spare_cells.empty()) found = cells.try_emplace(cell_key).first;
            else {
                auto node = std::move(spare_cells.back()); spare_cells.pop_back();
                node.key() = cell_key;
                found = cells.insert(std::move(node)).position;
            }
        }
        auto &values = found->second;
        values.insert(std::upper_bound(values.begin(), values.end(), id), id);
    }

    void query(const Vector2 &first, const Vector2 &second, std::vector<int64_t> &result) const {
        result.clear();
        const Vector2i lower = cell(first.min(second));
        const Vector2i upper = cell(first.max(second));
        std::unordered_set<int64_t> seen;
        // This traversal and the sorted IDs within a cell are observable hit order.
        for (int64_t row = lower.y; row <= upper.y; ++row) {
            for (int64_t column = lower.x; column <= upper.x; ++column) {
                const auto found = cells.find(key(int32_t(column), int32_t(row)));
                if (found == cells.end()) continue;
                for (int64_t id : found->second) {
                    if (unique || seen.insert(id).second) result.push_back(id);
                }
            }
        }
    }
};

// Same scalar evaluation order and inclusive tolerances as CombatGeometry.
inline double segment_circle_first_t(const Vector2 &start, const Vector2 &end,
                              const Vector2 &center, double combined_radius, double epsilon) {
    const Vector2 delta = end - start;
    const double length_squared = delta.length_squared();
    const double radius = std::max(0.0, combined_radius) + epsilon;
    if (length_squared <= epsilon) {
        return double(start.distance_squared_to(center)) <= radius * radius ? 0.0 : -1.0;
    }
    const Vector2 offset = start - center;
    const double a = length_squared;
    const double b = 2.0 * double(offset.dot(delta));
    const double c = double(offset.length_squared()) - radius * radius;
    if (c <= 0.0) return 0.0;
    const double discriminant = b * b - 4.0 * a * c;
    if (discriminant < -epsilon) return -1.0;
    const double root = std::sqrt(std::max(0.0, discriminant));
    const double first = (-b - root) / (2.0 * a);
    if (first >= -epsilon && first <= 1.0 + epsilon) return std::clamp(first, 0.0, 1.0);
    const double second = (-b + root) / (2.0 * a);
    if (second >= -epsilon && second <= 1.0 + epsilon) return std::clamp(second, 0.0, 1.0);
    return -1.0;
}

} // namespace
