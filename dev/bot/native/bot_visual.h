#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector4_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <vector>

class JarjarBotVisual : public godot::RefCounted {
    GDCLASS(JarjarBotVisual, godot::RefCounted)
    godot::Ref<godot::Mesh> mesh;
    godot::AABB bounds;
    bool convex = false;
    godot::Dictionary outlines, triangles;
    struct Plane { double x, y, lower, upper, length; };
    struct Hull { double x = 0.0, y = 0.0; std::vector<Plane> planes; };
    godot::Dictionary hull_indices;
    std::vector<Hull> hulls;
    bool contains_interior_witness(const Hull &hull, godot::Vector2 lower, godot::Vector2 upper) const;
protected:
    static void _bind_methods();
public:
    void setup(const godot::Ref<godot::Mesh> &p_mesh, bool p_convex);
    bool is_visible(const godot::Transform3D &inverse, double half_width, double half_height, const godot::Transform3D &world);
    godot::PackedVector4Array visible_loot(const godot::Transform3D &inverse, double half_width, double half_height, const godot::PackedVector3Array &transforms, const godot::PackedInt32Array &indices, int kind);
};

class JarjarBotObserver : public godot::RefCounted {
    GDCLASS(JarjarBotObserver, godot::RefCounted)
    std::vector<godot::Ref<JarjarBotVisual>> visuals;
protected:
    static void _bind_methods();
public:
    void configure(const godot::TypedArray<JarjarBotVisual> &p_visuals);
    godot::Dictionary observe_bodies(const godot::Dictionary &frame);
};
