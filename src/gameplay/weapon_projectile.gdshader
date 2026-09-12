shader_type spatial;
render_mode blend_mix, depth_draw_never, unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 weapon_color : source_color;
uniform int visual_kind = 0;
uniform float line_width = 0.045;
varying vec4 weapon_data;

void vertex() {
	weapon_data = INSTANCE_CUSTOM;
}

float line(float distance_to_line, float width) {
	return 1.0 - smoothstep(width, width + fwidth(distance_to_line), abs(distance_to_line));
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float mark = 0.0;
	if (visual_kind == 2) {
		mark = line(p.x, line_width) * step(-0.38, p.y) * step(p.y, 0.36);
	} else if (visual_kind == 3) {
		mark = line(p.x, line_width) * step(p.y, 0.55);
	} else if (visual_kind == 4) {
		mark = line(abs(p.x) / 0.72 + abs(p.y) - 0.52, line_width);
	} else if (visual_kind == 5) {
		mark = line(length(p) - 0.74, line_width * 0.65);
	} else if (visual_kind == 6) {
		float triangle = max(abs(p.x) * 0.866 + p.y * 0.5, -p.y);
		mark = line(triangle - 0.25, line_width);
	} else if (visual_kind == 7) {
		mark = line(length(p) - 0.46, line_width);
	}
	// Insets stay inside the real mesh silhouette, including the needle observed by bots.
	float evolved = step(0.5, weapon_data.r);
	vec3 ink = weapon_color.rgb * 0.16;
	vec3 body = mix(weapon_color.rgb, ink, mark * evolved);
	float calm = mix(1.0, 0.82, step(0.5, weapon_data.a));
	ALBEDO = body * calm;
	// Use ordered planar drawing to avoid coplanar flicker and preserve small attacks.
	ALPHA = 1.0;
}
