shader_type spatial;
render_mode blend_mix, cull_disabled, depth_prepass_alpha, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.24, 0.64, 0.70);
uniform vec3 deep_color : source_color = vec3(0.06, 0.25, 0.35);
uniform vec3 water_color : source_color = vec3(0.18, 0.58, 0.62);
uniform vec4 albedo_color : source_color = vec4(0.18, 0.58, 0.62, 1.0);

uniform float flow_speed : hint_range(0.0, 2.0) = 0.58;  # Increased for more visible flow
uniform float wave_strength : hint_range(0.0, 1.0) = 0.14;
uniform float normal_scale : hint_range(0.1, 12.0) = 2.2;
uniform float average_depth : hint_range(0.4, 18.0) = 7.5;

uniform float transparency : hint_range(0.0, 1.0) = 0.82;
uniform float edge_fade_width : hint_range(0.01, 0.30) = 0.12;
uniform float foam_amount : hint_range(0.0, 2.0) = 0.18;

uniform sampler2D normal_texture : hint_normal;
uniform sampler2D foam_texture : hint_default_white;

void fragment() {
	float width_distance = abs(UV.x - 0.5) * 2.0;
	float center_weight = pow(clamp(1.0 - width_distance, 0.0, 1.0), 1.45);
	float bank_mask = smoothstep(clamp(1.0 - edge_fade_width * 2.5, 0.25, 0.96), 1.0, width_distance);
	float center_flow = smoothstep(0.0, 1.0, center_weight);
	float depth_factor = clamp((average_depth - 0.4) / 17.6, 0.0, 1.0);

	vec2 stream_warp = vec2(
		sin(UV.y * 6.0 + TIME * flow_speed * (0.7 + 0.3 * center_flow) + UV.x * 8.0) * 0.05,
		cos(UV.y * 4.5 - TIME * flow_speed * (0.45 + 0.2 * bank_mask) + UV.x * 5.5) * 0.03
	);
	float current_strength = mix(0.70, 1.28, center_flow);
	vec2 flow_a = UV * normal_scale + vec2(TIME * flow_speed * current_strength * (0.05 + 0.03 * width_distance), TIME * flow_speed * (0.03 + 0.05 * center_flow)) + stream_warp;
	vec2 flow_b = UV * (normal_scale * 0.72) + vec2(-TIME * flow_speed * current_strength * (0.03 + 0.02 * bank_mask), TIME * flow_speed * (0.05 + 0.06 * width_distance)) - stream_warp * 0.5;

	vec3 normal_a = texture(normal_texture, flow_a).rgb * 2.0 - 1.0;
	vec3 normal_b = texture(normal_texture, flow_b).rgb * 2.0 - 1.0;
	vec3 normal_map = normalize(mix(normal_a, normal_b, 0.5));
	normal_map.xy *= wave_strength * mix(0.88, 1.16, center_flow);
	normal_map.z = sqrt(max(0.001, 1.0 - dot(normal_map.xy, normal_map.xy)));

	float length_variation = 0.5 + 0.5 * sin(UV.y * 6.0 + TIME * flow_speed * (0.45 + 0.25 * center_flow) + UV.x * 3.0);
	float bank_variation = 0.45 + 0.55 * bank_mask;
	float depth_t = clamp(center_flow * 0.58 + length_variation * 0.14 + depth_factor * 0.28, 0.0, 1.0);

	vec3 depth_tint = mix(water_color, deep_color, depth_factor * 0.38);
	vec3 base_color = mix(shallow_color * 1.08, deep_color, depth_t);
	base_color = mix(base_color, depth_tint, 0.38 + depth_factor * 0.16);
	base_color = mix(base_color, shallow_color * 1.18, bank_variation * (0.28 + 0.14 * length_variation));
	base_color *= albedo_color.rgb;

	float foam_noise_a = texture(foam_texture, UV * vec2(2.0, 5.0) + vec2(TIME * flow_speed * 0.18, TIME * flow_speed * 0.09)).r;
	float foam_noise_b = texture(foam_texture, UV * vec2(3.0, 7.0) + vec2(-TIME * flow_speed * 0.11, TIME * flow_speed * 0.06)).r;
	float foam_noise = mix(foam_noise_a, foam_noise_b, 0.5);
	float flow_boost = clamp(0.35 + 0.65 * length_variation, 0.0, 1.0);
	float foam_band = bank_mask * flow_boost * (0.86 - depth_factor * 0.28);
	float foam = foam_band * foam_amount * smoothstep(0.48, 0.9, foam_noise);
	float foam_highlight = foam * (0.72 + 0.28 * bank_mask);

	ALBEDO = mix(base_color, vec3(0.95, 0.98, 1.0), foam_highlight);
	ALPHA = clamp(transparency - bank_mask * (0.10 + depth_factor * 0.03) + center_flow * 0.02, 0.46, 0.94);
	NORMAL_MAP = normal_map;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.34, 0.22, bank_mask);
	SPECULAR = mix(0.11, 0.21, bank_mask) * mix(1.0, 0.88, depth_factor);
	METALLIC = 0.0;
}
