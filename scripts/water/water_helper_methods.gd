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


static func _curve_tangent(curve: Curve3D, distance: float) -> Vector3:
	var curve_length: float = curve.get_baked_length()
	var epsilon: float = maxf(0.05, curve_length * 0.005)
	var prev_pos: Vector3 = curve.sample_baked(clampf(distance - epsilon, 0.0, curve_length), false)
	var next_pos: Vector3 = curve.sample_baked(clampf(distance + epsilon, 0.0, curve_length), false)
	var tangent: Vector3 = next_pos - prev_pos
	if tangent.length_squared() < 0.000001:
		return Vector3.FORWARD
	return tangent.normalized()


static func _safe_right_vector(tangent: Vector3, fallback_right: Vector3) -> Vector3:
	var right_vector: Vector3 = tangent.cross(Vector3.UP)
	if right_vector.length_squared() < 0.000001:
		return fallback_right
	right_vector = right_vector.normalized()
	if fallback_right != Vector3.ZERO and right_vector.dot(fallback_right) < 0.0:
		right_vector = -right_vector
	return right_vector


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
	var total_segments: int = max(1, steps * step_length_divs)
	var curve_length: float = curve.get_baked_length()
	
	for step in range(total_segments + 1):
		var target_distance: float = (float(step) / float(total_segments)) * curve_length
		var target_pos: Vector3 = curve.sample_baked(target_distance, false)
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

		var progress: float = float(step) / float(total_segments)
		var sampled_width: float = lerp(widths[closest_point], widths[closest_point + 1], closest_interpolate)
		var width_variation: float = 1.0 + (_smooth_noise_01(progress * 5.5, 13.0) - 0.5) * 0.18
		var width_detail: float = (_smooth_noise_01(progress * 15.0, 29.0) - 0.5) * 0.06
		var bend_curvature: float = 0.0
		if step > 0 and step < total_segments:
			var curve_prev: Vector3 = _curve_tangent(curve, maxf(0.0, target_distance - curve_length / float(total_segments) * 0.5))
			var curve_next: Vector3 = _curve_tangent(curve, minf(curve_length, target_distance + curve_length / float(total_segments) * 0.5))
			bend_curvature = clampf(1.0 - curve_prev.dot(curve_next), 0.0, 1.0)
		var bend_scale: float = 1.0 + bend_curvature * 0.08
		if bend_curvature > 0.5:
			bend_scale -= (bend_curvature - 0.5) * 0.26
		river_width_values.append(
			maxf(0.35, sampled_width * bend_scale * width_variation + sampled_width * width_detail)
		)
	
	# Smooth width values to prevent sudden transitions
	if river_width_values.size() > 2:
		var smoothed_values := [river_width_values[0]]
		for i in range(1, river_width_values.size() - 1):
			var smoothed: float = lerpf(
				river_width_values[i],
				(river_width_values[i - 1] + river_width_values[i] + river_width_values[i + 1]) / 3.0,
				0.4
			)
			smoothed_values.append(smoothed)
		smoothed_values.append(river_width_values[-1])
		return smoothed_values
	
	return river_width_values


# Generate river mesh from curve and parameters
static func generate_river_mesh(curve: Curve3D, steps: int, step_length_divs: int, 
								step_width_divs: int, smoothness: float, 
										river_width_values: Array, surface_height_offset: float = 0.10) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curve_length := curve.get_baked_length()
	var total_segments: int = max(1, steps * step_length_divs)
	var prev_right_vector: Vector3 = Vector3.ZERO
	st.set_smooth_group(0)
	
	# Generate vertices
	for step in range(total_segments + 1):
		var progress: float = float(step) / float(total_segments)
		var position: Vector3 = curve.sample_baked(progress * curve_length, false)
		var tangent: Vector3 = _curve_tangent(curve, progress * curve_length)
		var right_vector: Vector3 = _safe_right_vector(tangent, prev_right_vector)
		if prev_right_vector == Vector3.ZERO:
			prev_right_vector = right_vector
		else:
			var bend_alignment: float = clampf(right_vector.dot(prev_right_vector), -1.0, 1.0)
			if bend_alignment < 0.25:
				var bend_smooth: float = clampf(0.20 + bend_alignment * 0.30, 0.14, 0.38)
				right_vector = prev_right_vector.slerp(right_vector, bend_smooth).normalized()
			prev_right_vector = right_vector
		position.y += surface_height_offset
		
		var width_lerp: float = river_width_values[step]
		var width_variation: float = 1.0 + (_smooth_noise_01(progress * 4.0, 41.0) - 0.5) * 0.14
		var bank_left_noise: float = (_smooth_noise_01(progress * 8.0, 73.0) - 0.5) * 0.16
		var bank_right_noise: float = (_smooth_noise_01(progress * 8.0, 89.0) - 0.5) * 0.16
		var bank_wiggle: float = (_smooth_noise_01(progress * 20.0, 17.0) - 0.5) * 0.08
		var curvature: float = 0.0
		var turn_orientation: float = 1.0
		if step > 0 and step < total_segments:
			var tangent_prev: Vector3 = _curve_tangent(curve, maxf(0.0, progress * curve_length - smoothness * 0.5))
			var tangent_next: Vector3 = _curve_tangent(curve, minf(curve_length, progress * curve_length + smoothness * 0.5))
			curvature = clampf(1.0 - tangent_prev.dot(tangent_next), 0.0, 1.0)
			turn_orientation = 1.0 if tangent_prev.cross(tangent_next).dot(Vector3.UP) >= 0.0 else -1.0
		var bend_widen: float = 1.0 + curvature * 0.10
		var bend_tighten: float = 1.0 - curvature * 0.38
		var bend_bias: float = clampf(curvature * 1.5, 0.0, 1.0)
		var signed_left: float = 1.0
		var signed_right: float = -1.0
		var left_outer_bias: float = clampf((turn_orientation * signed_left + 1.0) * 0.5, 0.0, 1.0)
		var right_outer_bias: float = clampf((turn_orientation * signed_right + 1.0) * 0.5, 0.0, 1.0)
		var left_scale: float = maxf(0.20, width_lerp * width_variation * bend_widen)
		var right_scale: float = maxf(0.20, width_lerp * width_variation * bend_widen)
		left_scale *= (1.0 + bank_left_noise + bank_wiggle)
		right_scale *= (1.0 + bank_right_noise - bank_wiggle)
		left_scale *= lerpf(1.0 - bend_bias * 0.42, 1.0 + bend_bias * 0.18, left_outer_bias)
		right_scale *= lerpf(1.0 - bend_bias * 0.42, 1.0 + bend_bias * 0.18, right_outer_bias)
		if curvature > 0.30:
			left_scale *= bend_tighten
			right_scale *= bend_tighten
		if curvature > 0.55:
			left_scale *= 0.88
			right_scale *= 0.88
		
		for w_sub in range(step_width_divs + 1):
			var uv_x: float = float(w_sub) / float(step_width_divs)
			var uv_y: float = progress  # Smooth UV along curve
			st.set_uv(Vector2(uv_x, uv_y))
			var bank_t: float = float(w_sub) / float(step_width_divs)
			var edge_offset: float = lerpf(left_scale, -right_scale, bank_t)
			var edge_noise: float = (_smooth_noise_01(progress * 24.0 + bank_t * 6.0, 61.0) - 0.5) * 0.14
			edge_offset += edge_offset * edge_noise * (0.28 + absf(bank_t - 0.5) * 1.1)
			st.add_vertex(position + right_vector * edge_offset)
	
	# Define triangles - properly connect vertex rings
	for step in range(total_segments):
		for w_sub in range(step_width_divs):
			# Current ring base and next ring base
			var curr_base: int = step * (step_width_divs + 1)
			var next_base: int = (step + 1) * (step_width_divs + 1)
			
			# First triangle of quad
			st.add_index(curr_base + w_sub)
			st.add_index(curr_base + w_sub + 1)
			st.add_index(next_base + w_sub)
			
			# Second triangle of quad
			st.add_index(curr_base + w_sub + 1)
			st.add_index(next_base + w_sub + 1)
			st.add_index(next_base + w_sub)
	
	st.generate_normals()
	st.generate_tangents()
	st.deindex()
	
	var mesh := st.commit()
	return mesh
