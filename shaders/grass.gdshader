shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded;  // Changed from depth_draw_always

// Wind parameters
uniform float wind_strength : hint_range(0.0, 2.0) = 0.8;
uniform float wind_speed : hint_range(0.1, 5.0) = 1.8;
uniform float wind_direction_deg : hint_range(0.0, 359.0) = 35.0;

// Grass parameters
uniform float grass_height : hint_range(0.1, 3.0) = 0.85;
uniform float sway_amount : hint_range(0.0, 1.0) = 0.45;

// Color parameters
uniform vec3 base_color : source_color = vec3(0.15, 0.28, 0.12);
uniform vec3 tip_color : source_color = vec3(0.55, 0.68, 0.35);

// Noise
uniform sampler2D color_noise : hint_default_white;
uniform float noise_scale : hint_range(1.0, 100.0) = 25.0;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_pos;
varying float blade_t;

// Simple hash
float hash(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    return fract(p.x * p.y * (p.x + p.y));
}

void vertex() {
    vec3 vert = VERTEX;
    float t = clamp(vert.y + 0.5, 0.0, 1.0);  // 0 = base, 1 = tip
    blade_t = t;
    
    // World position for noise/wind
    world_pos = (MODEL_MATRIX * vec4(vert, 1.0)).xyz;
    
    // Randomness per blade
    float rand1 = hash(world_pos.xz * 0.137);
    float rand2 = hash(world_pos.zx * 0.091);
    
    // Height variation
    float height_var = mix(0.7, 1.15, rand1);
    vert.y *= grass_height * height_var;
    
    // Width taper
    vert.x *= mix(0.055, 0.085, rand2) * (1.0 - t * 0.75);
    
    // Wind calculation
    float wind_angle = radians(wind_direction_deg);
    vec2 wind_dir = vec2(cos(wind_angle), sin(wind_angle));
    
    float time = TIME * wind_speed;
    float wave1 = sin(time * 1.1 + world_pos.x * 0.08) * 0.6;
    float wave2 = sin(time * 0.7 + world_pos.z * 0.11) * 0.4;
    
    float wind_amp = (wind_strength * 0.8) * (wave1 + wave2);
    float bend = wind_amp * t * t;  // stronger at tip
    
    // Apply bend
    vert.xz += wind_dir * bend;
    
    VERTEX = vert;
    NORMAL = normalize(NORMAL); // Optional: re-normalize
}

void fragment() {
    float t = blade_t;
    
    // Base color gradient
    vec3 col = mix(base_color, tip_color, t * t);
    
    // Noise variation
    vec3 noise = texture(color_noise, world_pos.xz / noise_scale).rgb;
    col *= mix(1.0, noise.r * 1.4, noise_strength);
    
    // Stylized tonal steps
    float tonal = floor(t * 3.5) / 3.0;
    col *= mix(0.85, 1.15, tonal);
    
    ALBEDO = col;
    ALPHA = 1.0;           // Important for MultiMesh
    ROUGHNESS = 0.9;
    SPECULAR = 0.1;
    METALLIC = 0.0;
}