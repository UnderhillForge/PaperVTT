shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.1, 0.7, 1.0, 0.18);
uniform vec4 rim_color : source_color = vec4(0.6, 0.9, 1.0, 0.7);
uniform float pulse : hint_range(0.9, 1.15) = 1.0;

void fragment() {
	// Use normal-based detection for fresnel/edge effect
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	
	// Soft body with vertical falloff
	float vertical_distance = abs(VERTEX.y);
	float body_alpha = exp(-vertical_distance * vertical_distance * 0.5);
	
	// Rim effect at edges
	float rim_strength = fresnel * 0.6;
	
	// Blend colors
	ALBEDO = mix(base_color.rgb, rim_color.rgb, rim_strength);
	
	// Final alpha: body + rim highlight
	ALPHA = (body_alpha * base_color.a + rim_strength * rim_color.a) * pulse;
}
