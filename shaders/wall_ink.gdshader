shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint_color : source_color = vec4(0.77, 0.76, 0.73, 1.0);
uniform vec4 line_color : source_color = vec4(0.02, 0.02, 0.02, 1.0);
uniform vec4 hatch_color : source_color = vec4(0.14, 0.13, 0.12, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.9;
uniform float edge_strength : hint_range(0.0, 4.0, 0.01) = 1.9;
uniform float edge_power : hint_range(0.5, 8.0, 0.01) = 2.2;
uniform float hatch_density : hint_range(1.0, 80.0, 0.1) = 28.0;
uniform float hatch_strength : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float paper_grain_strength : hint_range(0.0, 1.0, 0.01) = 0.11;
uniform float topdown_ink_boost : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform bool use_window_cutout = false;
uniform vec2 window_cutout_center = vec2(0.0, 0.0);
uniform vec2 window_cutout_size = vec2(0.0, 0.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_tex = false;
uniform vec2 uv_tiling = vec2(1.0, 1.0);
uniform bool is_preview = false;
uniform float preview_alpha : hint_range(0.0, 1.0, 0.01) = 0.34;

varying vec3 v_world_pos;
varying vec3 v_local_pos;

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

void vertex() {
	v_local_pos = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (use_window_cutout) {
		vec2 half_size = max(window_cutout_size * 0.5, vec2(0.0));
		vec2 delta = abs(v_local_pos.xy - window_cutout_center) - half_size;
		if (max(delta.x, delta.y) <= 0.0) {
			discard;
		}
	}

	vec3 world = v_world_pos * 0.42;
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float h0 = abs(sin((world.x + world.z) * hatch_density));
	float h1 = abs(sin((world.x - world.z) * (hatch_density * 0.86)));
	float h2 = abs(sin((world.x * 0.65 + world.z * 1.35) * (hatch_density * 0.52)));
	float hatch = pow(clamp(max(max(h0, h1), h2), 0.0, 1.0), 2.2);
	float face_flatness = 1.0 - abs(n.y);
	float grain = hash12(world.xz * 20.0) * 2.0 - 1.0;

	vec3 base = tint_color.rgb;
	if (use_albedo_tex) {
		vec3 tex_base = texture(albedo_tex, UV * uv_tiling).rgb;
		base *= tex_base;
	}
	base = mix(base, hatch_color.rgb, hatch * hatch_strength * (0.35 + face_flatness * 0.65));
	base *= (1.0 + grain * paper_grain_strength);

	float edge = pow(1.0 - max(dot(n, v), 0.0), edge_power);
	float topdown_factor = clamp(1.0 - abs(v.y), 0.0, 1.0);
	float ink_mix = clamp(edge * edge_strength + topdown_factor * topdown_ink_boost, 0.0, 1.0);
	base = mix(base, line_color.rgb, ink_mix);

	ALBEDO = base;
	ROUGHNESS = roughness_value;
	METALLIC = 0.0;
	SPECULAR = 0.08;

	if (is_preview) {
		ALPHA = preview_alpha;
		EMISSION = mix(base, vec3(0.62, 0.92, 1.0), 0.35);
	}
}
