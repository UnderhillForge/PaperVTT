shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

const int MAX_TEXTURE_LAYERS = 24;
const int CONTROL_MAP_COUNT = 6;

uniform sampler2D base_albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D control_map_0 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D control_map_1 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D control_map_2 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D control_map_3 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D control_map_4 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D control_map_5 : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2DArray paint_albedo_array : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray paint_normal_array : filter_linear_mipmap, repeat_enable;
uniform sampler2DArray paint_roughness_array : filter_linear_mipmap, repeat_enable;
uniform float paint_uv_scale[MAX_TEXTURE_LAYERS];
uniform float paint_exposure[MAX_TEXTURE_LAYERS];
uniform float base_uv_scale : hint_range(0.1, 1024.0, 0.1) = 8.0;
uniform float base_roughness : hint_range(0.0, 1.0, 0.01) = 0.92;
uniform float terrain_world_size : hint_range(1.0, 8192.0, 1.0) = 256.0;
uniform float triplanar_slope_start : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float triplanar_slope_end : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float triplanar_sharpness : hint_range(1.0, 16.0, 0.1) = 4.0;

varying vec3 world_pos_varying;
varying vec3 world_nrm_varying;

void vertex() {
	world_pos_varying = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm_varying = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 triplanar_weights(vec3 nrm, float sharpness) {
	vec3 w = pow(abs(nrm), vec3(sharpness));
	float inv = 1.0 / max(w.x + w.y + w.z, 0.0001);
	return w * inv;
}

vec4 get_control_map(int map_idx, vec4 c0, vec4 c1, vec4 c2, vec4 c3, vec4 c4, vec4 c5) {
	if (map_idx == 0) {
		return c0;
	}
	if (map_idx == 1) {
		return c1;
	}
	if (map_idx == 2) {
		return c2;
	}
	if (map_idx == 3) {
		return c3;
	}
	if (map_idx == 4) {
		return c4;
	}
	return c5;
}

float get_control_weight(int layer, vec4 c0, vec4 c1, vec4 c2, vec4 c3, vec4 c4, vec4 c5) {
	int map_idx = layer / 4;
	int channel = layer - (map_idx * 4);
	vec4 control_map = get_control_map(map_idx, c0, c1, c2, c3, c4, c5);
	if (channel == 0) {
		return control_map.r;
	}
	if (channel == 1) {
		return control_map.g;
	}
	if (channel == 2) {
		return control_map.b;
	}
	return control_map.a;
}

vec4 sample_albedo_planar(sampler2DArray tex, vec2 uv, float layer_idx, float exposure) {
	vec4 c = texture(tex, vec3(uv, layer_idx));
	c.rgb *= exposure;
	return c;
}

vec4 sample_albedo_triplanar(sampler2DArray tex, vec3 world_pos, vec3 weights, float uv_scale, float exposure, float layer_idx) {
	float inv_size = uv_scale / max(terrain_world_size, 0.001);
	vec2 uv_x = world_pos.zy * inv_size;
	vec2 uv_y = world_pos.xz * inv_size;
	vec2 uv_z = world_pos.xy * inv_size;
	vec4 x_col = texture(tex, vec3(uv_x, layer_idx));
	vec4 y_col = texture(tex, vec3(uv_y, layer_idx));
	vec4 z_col = texture(tex, vec3(uv_z, layer_idx));
	vec4 c = x_col * weights.x + y_col * weights.y + z_col * weights.z;
	c.rgb *= exposure;
	return c;
}

float sample_roughness_planar(sampler2DArray tex, vec2 uv, float layer_idx) {
	return texture(tex, vec3(uv, layer_idx)).r;
}

float sample_roughness_triplanar(sampler2DArray tex, vec3 world_pos, vec3 weights, float uv_scale, float layer_idx) {
	float inv_size = uv_scale / max(terrain_world_size, 0.001);
	vec2 uv_x = world_pos.zy * inv_size;
	vec2 uv_y = world_pos.xz * inv_size;
	vec2 uv_z = world_pos.xy * inv_size;
	float x_rough = texture(tex, vec3(uv_x, layer_idx)).r;
	float y_rough = texture(tex, vec3(uv_y, layer_idx)).r;
	float z_rough = texture(tex, vec3(uv_z, layer_idx)).r;
	return x_rough * weights.x + y_rough * weights.y + z_rough * weights.z;
}

vec4 sample_layer_albedo(sampler2DArray tex, vec2 uv_planar, vec3 world_pos, vec3 tri_w, float uv_scale, float exposure, float tri_mix, float layer_idx) {
	vec4 planar = sample_albedo_planar(tex, uv_planar, layer_idx, exposure);
	vec4 tri = sample_albedo_triplanar(tex, world_pos, tri_w, uv_scale, exposure, layer_idx);
	return mix(planar, tri, tri_mix);
}

float sample_layer_roughness(sampler2DArray tex, vec2 uv_planar, vec3 world_pos, vec3 tri_w, float uv_scale, float tri_mix, float layer_idx) {
	float planar = sample_roughness_planar(tex, uv_planar, layer_idx);
	float tri = sample_roughness_triplanar(tex, world_pos, tri_w, uv_scale, layer_idx);
	return mix(planar, tri, tri_mix);
}

vec3 sample_layer_normal(sampler2DArray tex, vec2 uv_planar, float layer_idx) {
	return texture(tex, vec3(uv_planar, layer_idx)).rgb;
}

void fragment() {
	vec4 weights_0 = clamp(texture(control_map_0, UV), 0.0, 1.0);
	vec4 weights_1 = clamp(texture(control_map_1, UV), 0.0, 1.0);
	vec4 weights_2 = clamp(texture(control_map_2, UV), 0.0, 1.0);
	vec4 weights_3 = clamp(texture(control_map_3, UV), 0.0, 1.0);
	vec4 weights_4 = clamp(texture(control_map_4, UV), 0.0, 1.0);
	vec4 weights_5 = clamp(texture(control_map_5, UV), 0.0, 1.0);
	vec2 uv_base = UV * base_uv_scale;
	vec3 world_pos = world_pos_varying;
	vec3 nrm_world = normalize(world_nrm_varying);
	vec3 tri_w = triplanar_weights(nrm_world, triplanar_sharpness);
	float slope = 1.0 - abs(nrm_world.y);
	float tri_mix = smoothstep(triplanar_slope_start, triplanar_slope_end, slope);

	vec3 base_col = texture(base_albedo_tex, uv_base).rgb;
	vec3 col = vec3(0.0);
	float roughness = 0.0;
	float used_weight = 0.0;
	float best_mask = 0.0;
	vec3 best_normal = vec3(0.5, 0.5, 1.0);

	for (int layer = 0; layer < MAX_TEXTURE_LAYERS; layer++) {
		float weight = get_control_weight(layer, weights_0, weights_1, weights_2, weights_3, weights_4, weights_5);
		if (weight <= 0.0001) {
			continue;
		}
		float uv_scale = paint_uv_scale[layer];
		float exposure = paint_exposure[layer];
		vec2 uv_layer = UV * uv_scale;
		vec4 layer_col = sample_layer_albedo(paint_albedo_array, uv_layer, world_pos, tri_w, uv_scale, exposure, tri_mix, float(layer));
		float layer_rough = sample_layer_roughness(paint_roughness_array, uv_layer, world_pos, tri_w, uv_scale, tri_mix, float(layer));
		float effective_weight = weight * layer_col.a;
		if (effective_weight <= 0.0001) {
			continue;
		}
		col += layer_col.rgb * effective_weight;
		roughness += layer_rough * effective_weight;
		used_weight += effective_weight;
		if (effective_weight > best_mask) {
			best_mask = effective_weight;
			best_normal = sample_layer_normal(paint_normal_array, uv_layer, float(layer));
		}
	}

	float base_mask = clamp(1.0 - used_weight, 0.0, 1.0);
	col += base_col * base_mask;
	roughness += base_roughness * base_mask;

	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.1;
	ROUGHNESS = roughness;

	if (best_mask > 0.001) {
		NORMAL_MAP = best_normal;
		NORMAL_MAP_DEPTH = best_mask;
	}
}
