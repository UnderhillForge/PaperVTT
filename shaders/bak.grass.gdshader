shader_type spatial;
render_mode cull_disabled, depth_draw_always;

// Wind parameters
uniform float wind_strength : hint_range(0.0, 2.0) = 0.5;
uniform float wind_speed : hint_range(0.1, 5.0) = 1.0;
uniform float wind_direction_deg : hint_range(0.0, 359.0) = 35.0;

// Grass parameters
uniform float grass_height : hint_range(0.1, 3.0) = 0.65;
uniform float sway_amount : hint_range(0.0, 1.0) = 0.3;

// Color parameters
uniform vec3 base_color : source_color = Color(0.12, 0.22, 0.10, 1.0);
uniform vec3 tip_color : source_color = Color(0.40, 0.49, 0.28, 1.0);

// Noise texture for color variation (optional)
uniform sampler2D color_noise : hint_default_white;
uniform float noise_scale : hint_range(1.0, 100.0) = 20.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.15;

varying vec3 worldPos;
varying float blade_height_t;

// Hash function for pseudo-random values
float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 19.19);
	return fract(p.x * p.y);
}

// 3D rotation matrix around Y axis
mat3 rot_y(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat3(
		vec3(c, 0.0, s),
		vec3(0.0, 1.0, 0.0),
		vec3(-s, 0.0, c)
	);
}

// Rotation around arbitrary axis
mat3 rot_axis(vec3 axis, float a) {
	axis = normalize(axis);
	float s = sin(a);
	float c = cos(a);
	float oc = 1.0 - c;
	return mat3(
		vec3(
			oc * axis.x * axis.x + c,
			oc * axis.x * axis.y - axis.z * s,
			oc * axis.z * axis.x + axis.y * s
		),
		vec3(
			oc * axis.x * axis.y + axis.z * s,
			oc * axis.y * axis.y + c,
			oc * axis.y * axis.z - axis.x * s
		),
		vec3(
			oc * axis.z * axis.x - axis.y * s,
			oc * axis.y * axis.z + axis.x * s,
			oc * axis.z * axis.z + c
		)
	);
}

void vertex() {
	// Normalize vertex position (0 to 1 from base to tip)
	vec3 original_vertex = VERTEX;
	VERTEX.y += 0.5;
	float t = clamp(VERTEX.y, 0.0, 1.0);
	blade_height_t = t;
	
	// Get world position for hashing and wind
	vec3 root = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	
	// Generate blade-specific randomness
	float r0 = hash2(root.xz * 0.1371);
	float r1 = hash2(root.zx * 0.0894 + vec2(0.17, 0.41));
	float r2 = hash2(root.xz * 0.0619 + vec2(0.83, 0.27));
	
	// Height variation
	float h_factor = mix(0.35, 1.0, hash2(root.zx * 0.053 + vec2(0.59, 0.21)));
	float blade_h = grass_height * h_factor;
	float width = mix(0.042, 0.068, r0);
	
	// Scale blade
	VERTEX.y *= blade_h;
	VERTEX.x *= width * (1.0 - t * 0.80);
	
	// Base rotation for blade orientation
	float base_rot = r0 * 6.28318;
	float stiffness = mix(0.75, 1.20, hash2(root.xz * 0.079 + vec2(0.24, 0.88)));
	float phase = hash2(root.xz * 0.101 + vec2(0.63, 0.14)) * 6.28318;
	
	// Main wind direction
	float wind_angle = radians(wind_direction_deg);
	vec2 main_dir = vec2(cos(wind_angle), sin(wind_angle));
	
	// Complex wind simulation
	float g1 = sin(TIME * wind_speed * 0.90 + dot(root.xz, main_dir * 0.090) + phase);
	float g2 = sin(TIME * wind_speed * 0.42 + dot(root.xz, main_dir * 0.031) + phase * 0.37);
	float main_amp = (0.35 + 0.65 * abs(g1)) * (0.78 + 0.22 * g2);
	vec2 main_vec = main_dir * main_amp * wind_strength;
	
	// Random wind component
	vec2 rand_dir = normalize(vec2(
		cos(phase * 1.13 + r1 * 6.28318),
		sin(phase * 0.87 + r2 * 6.28318)
	));
	float independent_wave = sin(TIME * wind_speed * 1.65 + dot(root.xz, rand_dir * 0.18) + phase * 2.10);
	vec2 independent_vec = rand_dir * independent_wave * wind_strength * 0.35;
	
	// Mix wind components
	float independent_mix = step(0.95, hash2(root.xz * 0.043 + vec2(0.31, 0.73)));
	vec2 wind_vec = mix(main_vec, main_vec * 0.65 + independent_vec, independent_mix);
	wind_vec += vec2(
		sin(TIME * wind_speed * 0.55 + root.x * 0.11 + phase),
		cos(TIME * wind_speed * 0.49 + root.z * 0.10 + phase)
	) * (wind_strength * 0.06);
	
	// Sway effect (gentle bending)
	float sway = sin(TIME * wind_speed * 0.3 + phase) * sway_amount * 0.5;
	
	// Droop and bend
	float droop = mix(0.04, 0.16, r2) * t * t;
	float bend = length(wind_vec) * t * t * (0.75 / stiffness);
	vec3 bend_axis = vec3(wind_vec.y, 0.0, -wind_vec.x);
	if (dot(bend_axis, bend_axis) < 0.00001) {
		bend_axis = vec3(1.0, 0.0, 0.0);
	}
	
	// Add sway to rotation
	float steer = (wind_vec.x + wind_vec.y + sway) * 0.15 * t * t;
	
	// Apply rotation
	mat3 m = rot_axis(bend_axis, -(droop + bend)) * rot_y(base_rot + steer);
	VERTEX = m * VERTEX;
	NORMAL = m * NORMAL;
	
	worldPos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Height-based color gradient
	float t = 1.0 - blade_height_t;
	float t2 = t * t;
	
	vec3 col = mix(base_color, tip_color, t2);
	
	// Sample noise for color variation
	vec3 noise_sample = texture(color_noise, worldPos.xz / noise_scale).rgb;
	float noise_variation = mix(1.0, noise_sample.r, noise_strength);
	col *= noise_variation;
	
	// Ambient occlusion from height
	float ao = mix(0.22, 1.0, t2);
	
	// Tonal compression for stylization
	float tonal = floor(t2 * 3.0 + 0.5) / 3.0;
	col *= mix(0.72, 1.08, tonal) * ao;
	
	// Desaturate slightly for more natural look
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, 0.78);
	
	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.62, t);
	SPECULAR = 0.0;
}