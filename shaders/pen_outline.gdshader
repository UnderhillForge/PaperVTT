shader_type canvas_item;

uniform bool enabled = true;
uniform bool fast_mode = false;
uniform float postfx_intensity : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float outline_thickness : hint_range(0.5, 10.0, 0.1) = 7.5;
uniform float outline_strength : hint_range(0.0, 6.0, 0.01) = 5.0;
uniform float edge_threshold : hint_range(0.003, 0.5, 0.003) = 0.015;

uniform float hatch_opacity : hint_range(0.0, 1.0, 0.01) = 0.75;
uniform float hatch_scale : hint_range(50.0, 2000.0, 1.0) = 620.0;
uniform float hatch_contrast : hint_range(0.2, 2.5, 0.01) = 2.2;
uniform vec4 paper_tint : source_color = vec4(0.94, 0.92, 0.86, 1.0);
uniform float paper_strength : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float line_darken : hint_range(0.0, 0.6, 0.01) = 0.14;
uniform float daytime_brightness : hint_range(0.6, 1.4, 0.01) = 1.0;
uniform float daytime_contrast : hint_range(0.6, 1.4, 0.01) = 1.0;
uniform float saturation : hint_range(0.0, 2.0, 0.01) = 1.0;
uniform float contrast : hint_range(0.5, 2.0, 0.01) = 1.0;
uniform float vignette_strength : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float vignette_softness : hint_range(0.05, 1.0, 0.01) = 0.55;
uniform float bloom_strength : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform vec4 color_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float tint_strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform bool outlines_layer_enabled = false;
uniform vec4 outlines_layer_color : source_color = vec4(0.01, 0.01, 0.01, 1.0);
uniform float outlines_layer_thickness : hint_range(0.5, 8.0, 0.1) = 2.2;
uniform float outlines_layer_depth_sensitivity : hint_range(0.0, 8.0, 0.01) = 1.6;
uniform float outlines_layer_depth_threshold : hint_range(0.001, 0.35, 0.001) = 0.055;
uniform float outlines_layer_normal_sensitivity : hint_range(0.0, 8.0, 0.01) = 1.3;
uniform float outlines_layer_opacity : hint_range(0.0, 1.0, 0.01) = 0.48;

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float hatch_pattern(vec2 uv) {
	vec2 p = uv * hatch_scale;
	float a = abs(sin((p.x + p.y) * 0.15));
	float b = abs(sin((p.x - p.y) * 0.12));
	float c = abs(sin(p.x * 0.18)) * abs(sin(p.y * 0.14));
	float r = hash12(floor(p * 0.05));
	float h = max(a, b) * 0.65 + c * 0.35 + r * 0.15;
	return pow(clamp(h, 0.0, 1.0), hatch_contrast) * 1.2;
}

void fragment() {
	vec2 uv = UV;
	vec4 scene_col = texture(TEXTURE, uv);

	if (!enabled) {
		COLOR = scene_col;
	} else {
		float outline_scale = fast_mode ? 0.7 : 1.0;
		float effective_outline_thickness = max(outline_thickness * outline_scale, 0.001);
		vec2 px = TEXTURE_PIXEL_SIZE * effective_outline_thickness;

		float tl = luminance(texture(TEXTURE, uv + vec2(-px.x, -px.y)).rgb);
		float tc = luminance(texture(TEXTURE, uv + vec2(0.0, -px.y)).rgb);
		float tr = luminance(texture(TEXTURE, uv + vec2(px.x, -px.y)).rgb);
		float ml = luminance(texture(TEXTURE, uv + vec2(-px.x, 0.0)).rgb);
		float mr = luminance(texture(TEXTURE, uv + vec2(px.x, 0.0)).rgb);
		float bl = luminance(texture(TEXTURE, uv + vec2(-px.x, px.y)).rgb);
		float bc = luminance(texture(TEXTURE, uv + vec2(0.0, px.y)).rgb);
		float br = luminance(texture(TEXTURE, uv + vec2(px.x, px.y)).rgb);

		float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
		float gy = -tl - 2.0 * tc - tr + bl + 2.0 * bc + br;
		float edge = length(vec2(gx, gy));

		float outline = smoothstep(edge_threshold, edge_threshold * 4.0, edge) * outline_strength;
		outline = clamp(outline, 0.0, 1.0);

		float lum = luminance(scene_col.rgb);
		float hatch_mask = smoothstep(0.02, 0.95, 1.0 - lum);
		float hatch = hatch_pattern(uv) * hatch_opacity * (fast_mode ? 0.65 : 1.0);
		float hatch_blend = hatch * hatch_mask * 0.18;
		vec3 hatched_scene = mix(scene_col.rgb, scene_col.rgb * (1.0 - hatch_blend), hatch_mask);
		vec3 paperized = mix(hatched_scene, hatched_scene * paper_tint.rgb, paper_strength * 0.35);
		vec3 outlined = mix(paperized, outline_color.rgb, outline * outline_color.a * 0.28);
		vec3 out_col = max(vec3(0.0), outlined * (1.0 - (outline * line_darken * 0.35)));

		if (bloom_strength > 0.001) {
			float bloom_radius = fast_mode ? 1.5 : 2.0;
			vec2 bloom_px = TEXTURE_PIXEL_SIZE * bloom_radius;
			vec3 bloom_sample = texture(TEXTURE, uv + vec2(bloom_px.x, 0.0)).rgb;
			bloom_sample += texture(TEXTURE, uv + vec2(-bloom_px.x, 0.0)).rgb;
			if (!fast_mode) {
				bloom_sample += texture(TEXTURE, uv + vec2(0.0, bloom_px.y)).rgb;
				bloom_sample += texture(TEXTURE, uv + vec2(0.0, -bloom_px.y)).rgb;
				bloom_sample *= 0.25;
			} else {
				bloom_sample *= 0.5;
			}
			out_col = mix(out_col, out_col + bloom_sample * 0.22, bloom_strength);
		}

		if (!fast_mode && outlines_layer_enabled && outlines_layer_opacity > 0.001) {
			vec2 o_px = TEXTURE_PIXEL_SIZE * outlines_layer_thickness;
			float o_tl = luminance(texture(TEXTURE, uv + vec2(-o_px.x, -o_px.y)).rgb);
			float o_tc = luminance(texture(TEXTURE, uv + vec2(0.0, -o_px.y)).rgb);
			float o_tr = luminance(texture(TEXTURE, uv + vec2(o_px.x, -o_px.y)).rgb);
			float o_ml = luminance(texture(TEXTURE, uv + vec2(-o_px.x, 0.0)).rgb);
			float o_mc = luminance(texture(TEXTURE, uv).rgb);
			float o_mr = luminance(texture(TEXTURE, uv + vec2(o_px.x, 0.0)).rgb);
			float o_bl = luminance(texture(TEXTURE, uv + vec2(-o_px.x, o_px.y)).rgb);
			float o_bc = luminance(texture(TEXTURE, uv + vec2(0.0, o_px.y)).rgb);
			float o_br = luminance(texture(TEXTURE, uv + vec2(o_px.x, o_px.y)).rgb);

			float d_h = (o_tr + 2.0 * o_mr + o_br - (o_tl + 2.0 * o_ml + o_bl)) * 0.25;
			float d_v = (o_tl + 2.0 * o_tc + o_tr - (o_bl + 2.0 * o_bc + o_br)) * 0.25;
			float depth_edge = length(vec2(d_h, d_v)) * outlines_layer_depth_sensitivity;
			float depth_mask = smoothstep(
				outlines_layer_depth_threshold,
				outlines_layer_depth_threshold * 2.8,
				depth_edge
			);

			float n_h = abs(o_mr - o_ml);
			float n_v = abs(o_bc - o_tc);
			float n_diag = abs(o_tl - o_br) + abs(o_tr - o_bl);
			float normal_edge = ((n_h + n_v) * 0.5 + n_diag * 0.25 + abs(o_mc - o_tc) * 0.2) * outlines_layer_normal_sensitivity;
			float normal_mask = smoothstep(
				outlines_layer_depth_threshold * 0.65,
				outlines_layer_depth_threshold * 2.1,
				normal_edge
			);

			float outline_layer = clamp(max(depth_mask, normal_mask), 0.0, 1.0) * outlines_layer_opacity;
			out_col = mix(out_col, outlines_layer_color.rgb, outline_layer * outlines_layer_color.a);
		}

		float lum2 = luminance(out_col);
		out_col = mix(vec3(lum2), out_col, saturation);
		out_col = (out_col - vec3(0.5)) * contrast + vec3(0.5);
		out_col = mix(out_col, out_col * color_tint.rgb, tint_strength * color_tint.a);

		vec2 centered = uv * 2.0 - 1.0;
		float dist = length(centered);
		float vig = smoothstep(vignette_softness, 1.0, dist);
		out_col *= (1.0 - vig * vignette_strength);

		out_col = (out_col - vec3(0.5)) * daytime_contrast + vec3(0.5);
		out_col *= daytime_brightness;
		out_col = clamp(out_col, vec3(0.0), vec3(1.0));
		vec3 final_rgb = mix(scene_col.rgb, out_col, clamp(postfx_intensity, 0.0, 1.0));
		COLOR = vec4(final_rgb, scene_col.a);
	}
}