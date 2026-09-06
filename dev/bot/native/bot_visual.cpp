#include "bot_visual.h"
#include <godot_cpp/classes/geometry2d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
#include <godot_cpp/variant/packed_float64_array.hpp>

using namespace godot;

void JarjarBotVisual::_bind_methods() {
    ClassDB::bind_method(D_METHOD("setup", "mesh", "convex"), &JarjarBotVisual::setup);
    ClassDB::bind_method(D_METHOD("is_visible", "inverse", "half_width", "half_height", "world"), &JarjarBotVisual::is_visible);
    ClassDB::bind_method(D_METHOD("visible_loot", "inverse", "half_width", "half_height", "transforms", "indices", "kind"), &JarjarBotVisual::visible_loot);
}

void JarjarBotVisual::setup(const Ref<Mesh> &p_mesh, bool p_convex) {
    mesh = p_mesh;
    bounds = mesh->get_aabb();
    convex = p_convex;
    outlines.clear();
    triangles.clear();
    hull_indices.clear();
    hulls.clear();
}

bool JarjarBotVisual::contains_interior_witness(const Hull &hull, Vector2 lower, Vector2 upper) const {
    // Only certify a disk strictly inside BOTH polygons. Uncertain edge/tangent
    // cases still use Geometry2D. Godot's ClipperD precision is five decimals;
    // this 0.001 m inset is much larger than its coordinate rounding.
    // https://github.com/godotengine/godot/blob/master/core/math/geometry_2d.cpp
    constexpr double inset = 0.001;
    if (hull.planes.size() < 3 || upper.x - lower.x <= inset * 4 || upper.y - lower.y <= inset * 4 ||
        std::max({std::abs(lower.x), std::abs(lower.y), std::abs(upper.x), std::abs(upper.y)}) > 10000.0f) return false;
    double x = std::clamp(hull.x, double(lower.x) + inset * 2, double(upper.x) - inset * 2);
    double y = std::clamp(hull.y, double(lower.y) + inset * 2, double(upper.y) - inset * 2);
    for (const Plane &plane : hull.planes) {
        double projected = plane.x * x + plane.y * y;
        double margin = plane.length * inset;
        if (projected <= plane.lower + margin || projected >= plane.upper - margin) return false;
    }
    return true;
}

bool JarjarBotVisual::is_visible(const Transform3D &inverse, double half_width, double half_height, const Transform3D &world) {
    Transform3D local = inverse * world;
    AABB projected = local.xform(bounds);
    Vector3 end = projected.get_end();
    if (!(projected.position.x <= half_width && end.x >= -half_width &&
          projected.position.y <= half_height && end.y >= -half_height &&
          projected.position.z <= -0.05 && end.z >= -4000.0)) return false;
    if (projected.position.x >= -half_width && end.x <= half_width &&
        projected.position.y >= -half_height && end.y <= half_height) return true;
    Geometry2D *geometry = Geometry2D::get_singleton();
    if (!outlines.has(local.basis)) {
        PackedVector3Array faces = mesh->get_faces();
        Transform3D basis_only(local.basis, Vector3());
        for (int64_t i = 0; i < faces.size(); ++i) faces[i] = basis_only.xform(faces[i]);
        PackedVector2Array points;
        points.resize(faces.size());
        for (int64_t i = 0; i < faces.size(); ++i) points[i] = Vector2(faces[i].x, faces[i].y);
        PackedVector2Array outline = geometry->convex_hull(points);
        outlines[local.basis] = outline;
        if (convex) {
            Hull hull;
            for (int64_t i = 0; i < outline.size(); ++i) { hull.x += outline[i].x; hull.y += outline[i].y; }
            if (!outline.is_empty()) { hull.x /= double(outline.size()); hull.y /= double(outline.size()); }
            for (int64_t i = 0; i < outline.size(); ++i) {
                Vector2 a = outline[i], b = outline[(i + 1) % outline.size()];
                double nx = double(b.y) - double(a.y), ny = double(a.x) - double(b.x);
                double length = std::sqrt(nx * nx + ny * ny);
                if (length == 0.0) continue;
                double lo = nx * outline[0].x + ny * outline[0].y, hi = lo;
                for (int64_t j = 1; j < outline.size(); ++j) {
                    double projection = nx * outline[j].x + ny * outline[j].y;
                    lo = std::min(lo, projection); hi = std::max(hi, projection);
                }
                hull.planes.push_back({nx, ny, lo, hi, length});
            }
            hull_indices[local.basis] = int64_t(hulls.size());
            hulls.push_back(std::move(hull));
        }
        if (!convex) triangles[local.basis] = points;
    }
    Vector2 offset(local.origin.x, local.origin.y);
    Vector2 lower = Vector2(float(-half_width), float(-half_height)) - offset;
    Vector2 upper = Vector2(float(half_width), float(half_height)) - offset;
    if (convex && contains_interior_witness(hulls[size_t(int64_t(hull_indices[local.basis]))], lower, upper)) return true;
    PackedVector2Array rectangle;
    rectangle.push_back(lower);
    rectangle.push_back(Vector2(upper.x, lower.y));
    rectangle.push_back(upper);
    rectangle.push_back(Vector2(lower.x, upper.y));
    if (geometry->intersect_polygons(outlines[local.basis], rectangle).is_empty()) return false;
    if (convex) return true;
    // Keep holes in warning rings, using the same mesh triangles as rendering.
    PackedVector2Array faces = triangles[local.basis];
    for (int64_t i = 0; i < faces.size(); i += 3) {
        Vector2 a = faces[i], b = faces[i+1], c = faces[i+2];
        if (std::max(a.x, std::max(b.x, c.x)) < lower.x || std::min(a.x, std::min(b.x, c.x)) > upper.x ||
            std::max(a.y, std::max(b.y, c.y)) < lower.y || std::min(a.y, std::min(b.y, c.y)) > upper.y) continue;
        PackedVector2Array triangle;
        triangle.push_back(a); triangle.push_back(b); triangle.push_back(c);
        if (!geometry->intersect_polygons(triangle, rectangle).is_empty()) return true;
    }
    return false;
}

PackedVector4Array JarjarBotVisual::visible_loot(const Transform3D &inverse, double half_width, double half_height, const PackedVector3Array &transforms, const PackedInt32Array &indices, int kind) {
    PackedVector4Array result;
    const Vector3 *columns = transforms.ptr();
    const int32_t *slots = indices.ptr();
    const int64_t column_count = transforms.size(), count = indices.size();
    std::vector<Vector4> visible;
    visible.reserve(size_t(count));
    for (int64_t i = 0; i < count; ++i) {
        int64_t offset = int64_t(slots[i]) * 4;
        ERR_FAIL_COND_V(offset < 0 || offset + 3 >= column_count, PackedVector4Array());
        Transform3D world(Basis(columns[offset], columns[offset + 1], columns[offset + 2]), columns[offset + 3]);
        if (is_visible(inverse, half_width, half_height, world))
            visible.push_back(Vector4(float(kind), world.origin.x, world.origin.z, world.basis.get_column(0).length()));
    }
    result.resize(int64_t(visible.size()));
    if (!visible.empty()) std::copy(visible.begin(), visible.end(), result.ptrw());
    return result;
}

void JarjarBotObserver::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "visuals"), &JarjarBotObserver::configure);
    ClassDB::bind_method(D_METHOD("observe_bodies", "frame"), &JarjarBotObserver::observe_bodies);
}

void JarjarBotObserver::configure(const TypedArray<JarjarBotVisual> &p_visuals) {
    visuals.clear();
    for (int64_t i = 0; i < p_visuals.size(); ++i) visuals.push_back(p_visuals[i]);
}

Dictionary JarjarBotObserver::observe_bodies(const Dictionary &frame) {
    Transform3D inverse = frame["inverse"];
    double width = frame["half_width"], height = frame["half_height"];
    PackedVector2Array positions = frame["positions"];
    PackedInt32Array kinds = frame["kinds"], shapes = frame["shapes"];
    PackedByteArray materializing = frame["materializing"];
    TypedArray<Transform3D> templates = frame["templates"];
    double radius_factor = frame["radius_factor"];
    ERR_FAIL_COND_V(positions.size() != kinds.size() || shapes.size() != kinds.size() || materializing.size() != kinds.size(), Dictionary());
    const int64_t count = positions.size();
    const Vector2 *position = positions.ptr();
    const int32_t *kind = kinds.ptr(), *shape = shapes.ptr();
    const uint8_t *arriving = materializing.ptr();
    std::vector<Transform3D> transforms;
    std::vector<double> radii;
    for (int64_t i = 0; i < templates.size(); ++i) {
        Transform3D transform = templates[i];
        transforms.push_back(transform);
        radii.push_back(double(transform.basis.get_column(0).length()) * radius_factor);
    }
    std::vector<int> visible;
    visible.reserve(size_t(count));
    for (int64_t i = 0; i < count; ++i) {
        ERR_FAIL_INDEX_V(shape[i], int64_t(transforms.size()), Dictionary());
        ERR_FAIL_INDEX_V(kind[i], int64_t(visuals.size()), Dictionary());
        Transform3D transform = transforms[size_t(shape[i])];
        transform.origin.x = position[i].x;
        transform.origin.z = position[i].y;
        if (visuals[size_t(kind[i])]->is_visible(inverse, width, height, transform)) visible.push_back(int(i));
    }
    std::sort(visible.begin(), visible.end(), [&](int a, int b) {
        if (kind[a] != kind[b]) return kind[a] < kind[b];
        if (position[a].x != position[b].x) return position[a].x < position[b].x;
        if (position[a].y != position[b].y) return position[a].y < position[b].y;
        if (radii[size_t(shape[a])] != radii[size_t(shape[b])]) return radii[size_t(shape[a])] < radii[size_t(shape[b])];
        if (arriving[a] != arriving[b]) return arriving[a] < arriving[b];
        return a < b;
    });
    PackedVector2Array output_positions;
    PackedInt32Array output_kinds;
    PackedByteArray output_materializing;
    PackedFloat64Array output_radii;
    output_positions.resize(int64_t(visible.size()));
    output_kinds.resize(int64_t(visible.size()));
    output_materializing.resize(int64_t(visible.size()));
    output_radii.resize(int64_t(visible.size()));
    Vector2 *visible_positions = output_positions.ptrw();
    int32_t *visible_kinds = output_kinds.ptrw();
    uint8_t *visible_materializing = output_materializing.ptrw();
    double *visible_radii = output_radii.ptrw();
    for (size_t i = 0; i < visible.size(); ++i) {
        visible_positions[i] = position[visible[i]];
        visible_kinds[i] = kind[visible[i]];
        visible_materializing[i] = arriving[visible[i]];
        visible_radii[i] = radii[size_t(shape[visible[i]])];
    }
    Dictionary result;
    result["positions"] = output_positions;
    result["kinds"] = output_kinds;
    result["materializing"] = output_materializing;
    result["radii"] = output_radii;
    return result;
}
