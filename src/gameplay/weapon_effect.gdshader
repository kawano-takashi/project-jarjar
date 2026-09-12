shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform float line_width = 0.012;
uniform bool reduce_flashes = false;
uniform bool reduce_motion = false;
varying vec2 plane_position;
varying vec4 effect_color;
// age, weapon visual kind, fan half-angle / PI (negative for trails), evolved
varying vec4 effect_data;

void vertex() {
	plane_position = VERTEX.xz;
	effect_color = COLOR;
	effect_data = INSTANCE_CUSTOM;
}

float stroke(float distance_to_line, float width) {
	float aa = max(fwidth(distance_to_line), 0.003);
	return 1.0 - smoothstep(width, width + aa, abs(distance_to_line));
}

void fragment() {
	vec2 p = plane_position;
	float age = clamp(effect_data.r, 0.0, 1.0);
	float radius = length(p);
	float kind = floor(effect_data.g + 0.5);
	float mask = 0.0;
	if (effect_data.b < 0.0) {
		mask = (1.0 - smoothstep(0.45, 1.0, abs(p.x))) * (1.0 - abs(p.y));
		mask *= reduce_motion ? 0.0 : 0.3;
	} else {
		float angle = abs(atan(p.x, p.y));
		float half_angle = effect_data.b * PI;
		float inside = half_angle > 3.13 ? 1.0 : 1.0 - smoothstep(half_angle - 0.012, half_angle, angle);
		mask = stroke(radius - (1.0 - line_width), line_width) * inside;
		if (half_angle < 3.13) {
			float edge = stroke((angle - half_angle) * radius, line_width * 0.6);
			mask = max(mask, edge * step(0.08, radius) * step(radius, 1.0));
		}
		if (effect_data.a > 0.5) {
			float inner = stroke(radius - 0.84, line_width * 0.5) * inside;
			if (kind > 7.5) {
				inner *= step(0.25, fract(atan(p.x, p.y) * 8.0 / PI));
			}
			mask = max(mask, inner);
		}
	}
	float fade = (1.0 - age) * (1.0 - age);
	ALBEDO = effect_color.rgb;
	ALPHA = effect_color.a * mask * fade * (reduce_flashes ? 0.55 : 0.85);
}
