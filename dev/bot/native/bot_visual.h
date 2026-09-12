#pragma once
#include "bot_view.h"
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
    godot::AABB bounds;
    godot::PackedVector3Array faces;
protected:
    static void _bind_methods();
public:
    void setup(const godot::Ref<godot::Mesh> &p_mesh);
    bool is_visible(const godot::Transform3D &inverse, const godot::Projection &projection, const godot::Transform3D &world) const;
    bool visible_in_frustum(const BotFrustum &frustum, const godot::Transform3D &world) const;
    godot::PackedVector4Array visible_loot(const godot::Transform3D &inverse, const godot::Projection &projection, const godot::PackedVector3Array &transforms, const godot::PackedInt32Array &indices, int kind) const;
    godot::Dictionary visible_bodies(const godot::Transform3D &inverse, const godot::Projection &projection, const godot::PackedVector3Array &transforms, const godot::PackedInt32Array &indices, double radius_factor) const;
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
