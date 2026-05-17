shader_type spatial;
render_mode blend_mix, cull_disabled, depth_prepass_alpha, specular_schlick_ggx;

uniform vec3 water_color : source_color = vec3(0.14, 0.50, 0.56);
uniform float flow_speed : hint_range(0.0, 5.0) = 0.24;
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.32;
uniform float transparency : hint_range(0.5, 1.0) = 0.64;
uniform float foam_amount : hint_range(0.0, 2.0) = 0.14;
uniform float specular_strength : hint_range(0.0, 1.0) = 0.72;

uniform sampler2D normal_texture : hint_normal;
uniform sampler2D foam_texture : hint_default_white;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float width_distance = abs(UV.x - 0.5) * 2.0;
	float center_weight = smoothstep(1.0, 0.12, width_distance);
	float edge_weight = 1.0 - center_weight;
	float flow_variation = 0.5 + 0.5 * sin(UV.y * 6.0 + TIME * flow_speed * 0.85 + UV.x * 1.4);

	vec2 flow_uv_a = UV * vec2(3.4, 3.8) + vec2(TIME * flow_speed * 0.014, TIME * flow_speed * 0.020);
	vec2 flow_uv_b = vec2(UV.y, -UV.x) * vec2(3.2, 3.6) + vec2(-TIME * flow_speed * 0.011, TIME * flow_speed * 0.015);

	vec3 normal_a = texture(normal_texture, flow_uv_a).rgb * 2.0 - 1.0;
	vec3 normal_b = texture(normal_texture, flow_uv_b).rgb * 2.0 - 1.0;
	vec3 blended_normal = normalize(mix(normal_a, normal_b, 0.52));
	blended_normal = normalize(mix(vec3(0.0, 0.0, 1.0), blended_normal, clamp(ripple_strength * 0.36, 0.0, 1.0)));

	float foam_noise_a = texture(foam_texture, UV * vec2(1.6, 3.8) + vec2(TIME * flow_speed * 0.007, TIME * flow_speed * 0.004)).r;
	float foam_noise_b = texture(foam_texture, UV * vec2(2.4, 5.2) + vec2(-TIME * flow_speed * 0.005, TIME * flow_speed * 0.006)).r;
	float foam_noise = mix(foam_noise_a, foam_noise_b, 0.5);
	float edge_foam = smoothstep(0.88, 0.985, foam_noise) * pow(edge_weight, 3.1) * foam_amount;
	float current_foam = smoothstep(0.975, 0.999, foam_noise) * flow_variation * 0.006 * foam_amount;
	float foam_band = edge_foam + current_foam;

	vec3 shallow_color = min(vec3(1.0), water_color * vec3(1.16, 1.12, 1.08) + vec3(0.06, 0.08, 0.07));
	vec3 deep_color = water_color * vec3(0.34, 0.52, 0.68);
	vec3 base_color = mix(shallow_color, deep_color, center_weight);
	base_color = mix(base_color, shallow_color, edge_weight * 0.38);
	base_color += foam_band * vec3(0.16, 0.18, 0.19);

	ALBEDO = base_color;
	NORMAL_MAP = blended_normal;
	NORMAL_MAP_DEPTH = ripple_strength * 0.28;
	ROUGHNESS = mix(0.19, 0.12, center_weight) - foam_band * 0.008;
	SPECULAR = clamp(specular_strength + center_weight * 0.07 + flow_variation * 0.025 + foam_band * 0.03, 0.0, 1.0);
	ALPHA = mix(transparency * 0.26, transparency * 0.62, center_weight);
}
