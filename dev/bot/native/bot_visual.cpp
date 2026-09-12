#include "bot_visual.h"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <godot_cpp/variant/packed_float64_array.hpp>

using namespace godot;

void JarjarBotVisual::_bind_methods() {
    ClassDB::bind_method(D_METHOD("setup", "mesh"), &JarjarBotVisual::setup);
    ClassDB::bind_method(D_METHOD("is_visible", "inverse", "projection", "world"), &JarjarBotVisual::is_visible);
    ClassDB::bind_method(D_METHOD("visible_loot", "inverse", "projection", "transforms", "indices", "kind"), &JarjarBotVisual::visible_loot);
    ClassDB::bind_method(D_METHOD("visible_bodies", "inverse", "projection", "transforms", "indices", "radius_factor"), &JarjarBotVisual::visible_bodies);
}

void JarjarBotVisual::setup(const Ref<Mesh> &p_mesh) {
    ERR_FAIL_COND(p_mesh.is_null());
    bounds = p_mesh->get_aabb();
    // Cache mesh-local triangles only: perspective silhouettes also change
    // when the mesh translates sideways or changes depth.
    faces = p_mesh->get_faces();
}

bool JarjarBotVisual::is_visible(const Transform3D &inverse, const Projection &projection, const Transform3D &world) const {
    return visible_in_frustum(BotFrustum(inverse, projection), world);
}

bool JarjarBotVisual::visible_in_frustum(const BotFrustum &frustum, const Transform3D &world) const {
    if (faces.is_empty()) return false;
    Transform3D local = frustum.inverse * world;
    BotFrustum::Coverage coverage = frustum.classify(local.xform(bounds));
    if (coverage == BotFrustum::OUTSIDE) return false;
    if (coverage == BotFrustum::INSIDE) return true;
    // Clip the actual surfaces, preserving empty corners and ring holes.
    const Vector3 *vertices = faces.ptr();
    for (int64_t i = 0; i + 2 < faces.size(); i += 3) {
        if (frustum.triangle_visible(local.xform(vertices[i]), local.xform(vertices[i + 1]), local.xform(vertices[i + 2]))) return true;
    }
    return false;
}

PackedVector4Array JarjarBotVisual::visible_loot(const Transform3D &inverse, const Projection &projection, const PackedVector3Array &transforms, const PackedInt32Array &indices, int kind) const {
    BotFrustum frustum(inverse, projection);
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
        if (visible_in_frustum(frustum, world))
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

Dictionary JarjarBotVisual::visible_bodies(const Transform3D &inverse, const Projection &projection, const PackedVector3Array &transforms, const PackedInt32Array &indices, double radius_factor) const {
    PackedVector4Array visible = visible_loot(inverse, projection, transforms, indices, 0);
    std::vector<Vector4> sorted;
    for (int64_t i = 0; i < visible.size(); ++i) sorted.push_back(visible[i]);
    std::sort(sorted.begin(), sorted.end(), [](const Vector4 &a, const Vector4 &b) {
        if (a.y != b.y) return a.y < b.y;
        if (a.z != b.z) return a.z < b.z;
        return a.w < b.w;
    });
    PackedVector2Array positions; PackedFloat64Array radii; PackedInt32Array kinds; PackedByteArray materializing;
    kinds.resize(int64_t(sorted.size())); kinds.fill(0); materializing.resize(int64_t(sorted.size())); materializing.fill(0);
    for (const auto &body : sorted) {
        positions.push_back(Vector2(body.y, body.z)); radii.push_back(double(body.w) * radius_factor);
    }
    Dictionary result; result["positions"] = positions; result["radii"] = radii;
    result["kinds"] = kinds; result["materializing"] = materializing; return result;
}

void JarjarBotObserver::configure(const TypedArray<JarjarBotVisual> &p_visuals) {
    visuals.clear();
    for (int64_t i = 0; i < p_visuals.size(); ++i) visuals.push_back(p_visuals[i]);
}

Dictionary JarjarBotObserver::observe_bodies(const Dictionary &frame) {
    BotFrustum frustum(frame["inverse"], frame["projection"]);
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
        if (visuals[size_t(kind[i])]->visible_in_frustum(frustum, transform)) visible.push_back(int(i));
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
