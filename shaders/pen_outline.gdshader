shader_type canvas_item;

uniform bool enabled = true;
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
		vec2 px = TEXTURE_PIXEL_SIZE * outline_thickness;

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
		float hatch = hatch_pattern(uv) * hatch_opacity;
		float hatch_blend = hatch * hatch_mask * 0.18;
		vec3 hatched_scene = mix(scene_col.rgb, scene_col.rgb * (1.0 - hatch_blend), hatch_mask);
		vec3 paperized = mix(hatched_scene, hatched_scene * paper_tint.rgb, paper_strength * 0.35);
		vec3 outlined = mix(paperized, outline_color.rgb, outline * outline_color.a * 0.28);
		vec3 out_col = max(vec3(0.0), outlined * (1.0 - (outline * line_darken * 0.35)));
		COLOR = vec4(out_col, scene_col.a);
	}
}