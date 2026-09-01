shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

varying vec2 local_plane_position;
varying vec4 trail_color;
varying vec4 trail_custom_data;

const float SWEEP_PORTION = 0.6666667;
const float WAVE_HALF_ANGLE = 0.4799655;
const float AURA_HALF_ANGLE = 1.0471976;
const float WAVE_INNER_RADIUS = 0.62;
const float AURA_INNER_RADIUS = 0.82;
const float EVO_INNER_OFFSET = 0.11;

void vertex() {
	local_plane_position = vec2(VERTEX.x, VERTEX.z);
	trail_color = COLOR;
	trail_custom_data = INSTANCE_CUSTOM;
}

float radial_band(float radius, float inner_radius) {
	float inner_edge = smoothstep(inner_radius, inner_radius + 0.045, radius);
	float outer_edge = 1.0 - smoothstep(0.955, 1.0, radius);
	return inner_edge * outer_edge;
}

float radial_outline(float radius, float center_radius, float half_width) {
	float inner_edge = smoothstep(
		center_radius - half_width,
		center_radius,
		radius
	);
	float outer_edge = 1.0 - smoothstep(
		center_radius,
		center_radius + half_width,
		radius
	);
	return inner_edge * outer_edge;
}

float angular_band(float angle, float half_angle) {
	return 1.0 - smoothstep(half_angle - 0.045, half_angle, abs(angle));
}

void fragment() {
	float age = clamp(trail_custom_data.x, 0.0, 1.0);
	float visual_code = floor(trail_custom_data.y * 5.0 + 0.5);
	float evolved = step(2.5, visual_code);
	float effect_kind = mod(visual_code, 3.0);
	float reduce_motion = step(0.5, trail_custom_data.z);
	float reduce_flashes = step(0.5, trail_custom_data.w);
	float radius = length(local_plane_position);
	float mask = 0.0;
	float fade = 1.0 - age;

	if (effect_kind < 0.5) {
		mask = 1.0 - smoothstep(0.72, 1.0, radius);
	} else {
		float half_angle = effect_kind < 1.5 ? WAVE_HALF_ANGLE : AURA_HALF_ANGLE;
		float inner_radius = effect_kind < 1.5 ? WAVE_INNER_RADIUS : AURA_INNER_RADIUS;
		float angle = atan(local_plane_position.x, local_plane_position.y);
		float normalized_angle = clamp((angle + half_angle) / (2.0 * half_angle), 0.0, 1.0);
		float sweep_progress = clamp(age / SWEEP_PORTION, 0.0, 1.0);
		float reveal = 1.0 - smoothstep(sweep_progress, sweep_progress + 0.025, normalized_angle);
		reveal = mix(reveal, 1.0, reduce_motion);
		float sweep_fade = 1.0 - smoothstep(SWEEP_PORTION, 1.0, age);
		fade = mix(sweep_fade, 1.0 - age, reduce_motion);
		float base_band = radial_band(radius, inner_radius);
		float evo_outline = radial_outline(
			radius,
			max(0.36, inner_radius - EVO_INNER_OFFSET),
			0.018
		);
		float segment_count = effect_kind < 1.5 ? 12.0 : 18.0;
		float segment_phase = fract((angle + 3.14159265) / 6.2831853 * segment_count);
		float segments = smoothstep(0.10, 0.20, segment_phase) * (1.0 - smoothstep(0.78, 0.90, segment_phase));
		float evolved_mask = max(base_band, evo_outline * segments);
		mask = mix(base_band, evolved_mask, evolved) * angular_band(angle, half_angle) * reveal;
	}
	float evolved_core_mask = evolved * (1.0 - smoothstep(0.18, 0.34, radius));
	mask = max(mask, evolved_core_mask);

	float opacity_scale = mix(1.0, 0.6, reduce_flashes);
	float emission_scale = mix(1.25, 0.35, reduce_flashes);
	float alpha = trail_color.a * mask * fade * opacity_scale;
	if (alpha <= 0.001) {
		discard;
	}
	float white_core = evolved_core_mask * mix(1.0, 0.25, reduce_flashes);
	vec3 display_color = mix(trail_color.rgb, vec3(1.0), white_core);
	ALBEDO = display_color;
	EMISSION = display_color * emission_scale;
	ALPHA = alpha;
}
