# Water Helper Methods - Adapted from Waterways by Kasper Arnklit Frandsen
# Utility functions for water/river calculations and mesh generation
# PaperVTT Integration - Simplified for pen-and-ink aesthetic

extends Node

# Barycentric coordinate conversion for triangle ray-casting
static func cart2bary(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	var v = (d11 * d20 - d01 * d21) / denom
	var w = (d00 * d21 - d01 * d20) / denom
	var u = 1.0 - v - w
	return Vector3(u, v, w)


static func bary2cart(a: Vector3, b: Vector3, c: Vector3, barycentric: Vector3) -> Vector3:
	return barycentric.x * a + barycentric.y * b + barycentric.z * c


static func point_in_barycentric(v: Vector3) -> bool:
	return 0 <= v.x and v.x <= 1 and 0 <= v.y and v.y <= 1 and 0 <= v.z and v.z <= 1


static func sum_array(array) -> float:
	var sum = 0.0
	for element in array:
		sum += element
	return sum


static func _hash_01(noise_seed: float) -> float:
	var value: float = sin(noise_seed * 12.9898 + 78.233) * 43758.5453
	return value - floor(value)


static func _smooth_noise_01(position: float, noise_seed: float) -> float:
	var position_floor: float = floor(position)
	var position_frac: float = position - position_floor
	var noise_a: float = _hash_01(position_floor + noise_seed)
	var noise_b: float = _hash_01(position_floor + 1.0 + noise_seed)
	return lerpf(noise_a, noise_b, position_frac)


# Calculate grid size from step count
static func calculate_side(steps: int) -> int:
	var side_float: float = sqrt(steps)
	if fmod(side_float, 1.0) != 0.0:
		side_float += 1.0
	return int(side_float)


# Generate river width values along curve
static func generate_river_width_values(curve: Curve3D, steps: int, step_length_divs: int, 
										_step_width_divs: int, widths: Array) -> Array:
	var river_width_values := []
	
	for step in range(steps * step_length_divs + 1):
		var target_pos: Vector3 = curve.sample_baked((float(step) / float(steps * step_length_divs + 1)) * curve.get_baked_length())
		var closest_dist := 4096.0
		var closest_interpolate: float = 0.0
		var closest_point: int = 0
		
		for c_point in range(curve.get_point_count() - 1):
			for i in range(100):
				var interpolate := float(i) / 100.0
				var pos: Vector3 = curve.sample(c_point, interpolate)
				var dist = pos.distance_to(target_pos)
				if dist < closest_dist:
					closest_dist = dist
					closest_interpolate = interpolate
					closest_point = c_point

		var progress: float = float(step) / float(max(1, steps * step_length_divs))
		var width_variation: float = 1.0 + (_smooth_noise_01(progress * 5.5, 13.0) - 0.5) * 0.18
		var width_detail: float = (_smooth_noise_01(progress * 15.0, 29.0) - 0.5) * 0.06
		var sampled_width: float = lerp(widths[closest_point], widths[closest_point + 1], closest_interpolate)
		river_width_values.append(
			maxf(0.35, sampled_width * width_variation + sampled_width * width_detail)
		)
	
	return river_width_values


# Generate river mesh from curve and parameters
static func generate_river_mesh(curve: Curve3D, steps: int, step_length_divs: int, 
								step_width_divs: int, smoothness: float, 
										river_width_values: Array, surface_height_offset: float = 0.10) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curve_length := curve.get_baked_length()
	st.set_smooth_group(0)
	
	# Generate vertices
	for step in range(steps * step_length_divs + 1):
		var position: Vector3 = curve.sample_baked(float(step) / float(steps * step_length_divs) * curve_length, false)
		var backward_pos: Vector3 = curve.sample_baked((float(step) - smoothness) / float(steps * step_length_divs) * curve_length, false)
		var forward_pos: Vector3 = curve.sample_baked((float(step) + smoothness) / float(steps * step_length_divs) * curve_length, false)
		var forward_vector: Vector3 = forward_pos - backward_pos
		var right_vector: Vector3 = forward_vector.cross(Vector3.UP).normalized()
		position.y += surface_height_offset
		
		var width_lerp: float = river_width_values[step]
		var progress: float = float(step) / float(max(1, steps * step_length_divs))
		var width_variation: float = 1.0 + (_smooth_noise_01(progress * 4.0, 41.0) - 0.5) * 0.14
		var bank_left_noise: float = (_smooth_noise_01(progress * 8.0, 73.0) - 0.5) * 0.18
		var bank_right_noise: float = (_smooth_noise_01(progress * 8.0, 89.0) - 0.5) * 0.18
		var bank_wiggle: float = (_smooth_noise_01(progress * 20.0, 17.0) - 0.5) * 0.08
		var left_edge: float = maxf(0.15, width_lerp * width_variation * (1.0 + bank_left_noise + bank_wiggle))
		var right_edge: float = maxf(0.15, width_lerp * width_variation * (1.0 + bank_right_noise - bank_wiggle))
		
		for w_sub in range(step_width_divs + 1):
			st.set_uv(Vector2(float(w_sub) / float(step_width_divs), float(step) / float(step_length_divs)))
			var bank_t: float = float(w_sub) / float(step_width_divs)
			var edge_offset: float = lerpf(left_edge, -right_edge, bank_t)
			st.add_vertex(position + right_vector * edge_offset)
	
	# Define triangles
	for step in range(steps * step_length_divs):
		for w_sub in range(step_width_divs):
			st.add_index((step * (step_width_divs + 1)) + w_sub)
			st.add_index((step * (step_width_divs + 1)) + w_sub + 1)
			st.add_index((step * (step_width_divs + 1)) + w_sub + 2 + step_width_divs - 1)
			
			st.add_index((step * (step_width_divs + 1)) + w_sub + 1)
			st.add_index((step * (step_width_divs + 1)) + w_sub + 3 + step_width_divs - 1)
			st.add_index((step * (step_width_divs + 1)) + w_sub + 2 + step_width_divs - 1)
	
	st.generate_normals()
	st.generate_tangents()
	st.deindex()
	
	var mesh := st.commit()
	return mesh
