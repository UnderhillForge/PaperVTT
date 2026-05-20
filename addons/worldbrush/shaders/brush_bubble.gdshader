shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.12, 0.75, 1.0, 0.07);
uniform vec4 rim_color : source_color = vec4(0.7, 0.95, 1.0, 0.95);
uniform float pulse_speed : hint_range(0.5, 4.0) = 1.8;
uniform float terrain_height = 0.0;
uniform float bottom_fade_distance : hint_range(0.01, 4.0) = 0.55;

varying vec3 world_pos;

void vertex() {
	// Very subtle noise for organic feel.
	float noise = sin(TIME * 3.0 + VERTEX.x * 6.0) * 0.5 +
			cos(TIME * 2.2 + VERTEX.z * 5.0) * 0.5;
	VERTEX += NORMAL * noise * 0.06;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(UV - vec2(0.5));

	// Very faint body.
	float body = (1.0 - smoothstep(0.0, 0.92, dist)) * 0.15;

	// Strong soap-bubble rim.
	float rim = smoothstep(0.65, 0.93, dist) * (1.0 - smoothstep(0.87, 0.99, dist));

	float pulse = 1.0 + sin(TIME * pulse_speed) * 0.1;

	float below_terrain = terrain_height - world_pos.y;
	float bottom_fade = 1.0 - smoothstep(-bottom_fade_distance, bottom_fade_distance * 1.8, below_terrain);

	ALBEDO = mix(base_color.rgb, rim_color.rgb, rim);
	ALPHA = clamp((body + rim * 2.3) * pulse * bottom_fade, 0.0, 1.0);
}
