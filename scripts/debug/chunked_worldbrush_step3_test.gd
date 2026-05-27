extends SceneTree

const CHUNKED_WORLDBRUSH_SCRIPT: Script = preload("res://addons/worldbrush/chunked_worldbrush.gd")

const EPSILON: float = 0.0001

var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var host := Node3D.new()
	host.name = "ChunkedTerrainTestHost"
	root.add_child(host)

	var terrain: Node = CHUNKED_WORLDBRUSH_SCRIPT.new()
	terrain.name = "ChunkedWorldBrushUnderTest"
	terrain.auto_test_snow = false
	terrain.seed_initial_terrain = false
	terrain.terrain_size = 256.0
	terrain.terrain_resolution = 96
	terrain.chunk_size_world = 64.0
	terrain.chunk_border_padding = 4
	host.add_child(terrain)

	await process_frame
	terrain.initialize_new_map()
	await process_frame

	_test_new_map_creation(terrain)
	_test_preview_api(terrain)
	_test_small_medium_large_brushes(terrain)
	_test_smooth_vs_sharp_modes(terrain)
	_test_chunk_border_seams(terrain)
	_test_steep_multi_chunk_borders(terrain)
	_test_new_map_reset_after_edits(terrain)

	if _failures.is_empty():
		print("STEP3_TEST: PASS")
		quit(0)
		return

	for failure in _failures:
		push_error("STEP3_TEST: %s" % failure)
	print("STEP3_TEST: FAIL (%d issues)" % _failures.size())
	quit(1)

func _test_new_map_creation(terrain: Node) -> void:
	var chunks: Dictionary = terrain.get("_chunks")
	if chunks.size() != 16:
		_failures.append("Expected 16 chunks on new map, got %d" % chunks.size())
	for key in chunks.keys():
		var chunk: Node = chunks[key] as Node
		if chunk == null:
			_failures.append("Chunk %s missing" % str(key))
			continue
		var mesh_instance: MeshInstance3D = chunk.get_node_or_null("ChunkMesh") as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			_failures.append("Chunk %s has no mesh after new map creation" % str(key))

func _test_preview_api(terrain: Node) -> void:
	terrain.set_brush_preview_enabled(true)
	terrain.set_brush_preview_radius(12.0)
	var preview: MeshInstance3D = terrain.get_node_or_null("BrushPreview") as MeshInstance3D
	if preview == null:
		_failures.append("BrushPreview node was not created")
		return
	if not is_equal_approx(preview.scale.x, 12.0):
		_failures.append("BrushPreview radius did not update")

func _test_small_medium_large_brushes(terrain: Node) -> void:
	terrain.initialize_new_map()
	terrain.apply_brush("raise", Vector3(-96.0, 0.0, -96.0), 6.0, 0.35, 0.0, false, 0.3, 0.42, "smooth")
	var small_changed: int = (terrain.get("_last_rebuilt_chunks") as Array).size()
	if small_changed <= 0:
		_failures.append("Small brush changed no chunks")
	if small_changed >= (terrain.get("_chunks") as Dictionary).size():
		_failures.append("Small brush updated all chunks; expected localized updates")

	terrain.apply_brush("raise", Vector3(-10.0, 0.0, -10.0), 18.0, 0.35, 0.0, false, 0.3, 0.42, "smooth")
	var medium_changed: int = (terrain.get("_last_rebuilt_chunks") as Array).size()
	if medium_changed <= 0:
		_failures.append("Medium brush changed no chunks")

	terrain.apply_brush("raise", Vector3(0.0, 0.0, 0.0), 42.0, 0.35, 0.0, false, 0.3, 0.42, "smooth")
	var large_changed: int = (terrain.get("_last_rebuilt_chunks") as Array).size()
	if large_changed <= 0:
		_failures.append("Large brush changed no chunks")
	if large_changed < medium_changed:
		_failures.append("Large brush changed fewer chunks than medium brush")

func _test_smooth_vs_sharp_modes(terrain: Node) -> void:
	terrain.initialize_new_map()
	terrain.apply_brush("raise", Vector3(-64.0, 0.0, -64.0), 14.0, 0.4, 0.0, false, 0.3, 0.42, "smooth")
	var smooth_center: float = terrain.sample_height(-64.0, -64.0)
	var smooth_edge: float = terrain.sample_height(-55.0, -64.0)

	terrain.initialize_new_map()
	terrain.apply_brush("raise", Vector3(-64.0, 0.0, -64.0), 14.0, 0.4, 0.0, false, 0.3, 0.42, "sharp")
	var sharp_center: float = terrain.sample_height(-64.0, -64.0)
	var sharp_edge: float = terrain.sample_height(-55.0, -64.0)

	if smooth_center <= 0.0 or sharp_center <= 0.0:
		_failures.append("Smooth or sharp raise stroke failed to deform terrain")
	if is_equal_approx(smooth_edge, sharp_edge):
		_failures.append("Smooth and sharp modes produced indistinguishable edge heights")

func _test_chunk_border_seams(terrain: Node) -> void:
	terrain.initialize_new_map()
	terrain.apply_brush("texturepaint", Vector3(0.0, 0.0, 0.0), 14.0, 0.55, 0.0, false, 0.3, 0.42, "smooth")
	terrain.apply_brush("raise", Vector3(0.0, 0.0, 0.0), 14.0, 0.32, 0.0, false, 0.3, 0.42, "smooth")

	var chunks: Dictionary = terrain.get("_chunks")
	var left_chunk: Node = chunks.get(Vector2i(1, 1), null) as Node
	var right_chunk: Node = chunks.get(Vector2i(2, 1), null) as Node
	if left_chunk == null or right_chunk == null:
		_failures.append("Missing adjacent chunks for seam test")
		return

	var left_arrays: Array = _get_chunk_surface_arrays(left_chunk)
	var right_arrays: Array = _get_chunk_surface_arrays(right_chunk)
	if left_arrays.is_empty() or right_arrays.is_empty():
		_failures.append("Unable to read chunk mesh arrays for seam test")
		return

	var left_vertices: PackedVector3Array = left_arrays[Mesh.ARRAY_VERTEX]
	var right_vertices: PackedVector3Array = right_arrays[Mesh.ARRAY_VERTEX]
	var left_normals: PackedVector3Array = left_arrays[Mesh.ARRAY_NORMAL]
	var right_normals: PackedVector3Array = right_arrays[Mesh.ARRAY_NORMAL]
	var left_stride: int = int(left_chunk.get("_local_stride"))
	var right_stride: int = int(right_chunk.get("_local_stride"))
	var left_sample_min_x: int = int(left_chunk.get("sample_min_x"))
	var left_sample_min_z: int = int(left_chunk.get("sample_min_z"))
	var right_sample_min_x: int = int(right_chunk.get("sample_min_x"))
	var right_sample_min_z: int = int(right_chunk.get("sample_min_z"))
	var row_count: int = int(left_chunk.get("max_z")) - int(left_chunk.get("min_z")) + 1
	var border_x: int = int(left_chunk.get("max_x"))
	var left_local_x: int = border_x - left_sample_min_x
	var right_local_x: int = border_x - right_sample_min_x
	if left_local_x < 0 or right_local_x < 0:
		_failures.append("Seam test index setup invalid for chunk sample bounds")
		return

	for z in range(row_count):
		var world_z: int = int(left_chunk.get("min_z")) + z
		var left_local_z: int = world_z - left_sample_min_z
		var right_local_z: int = world_z - right_sample_min_z
		var left_idx: int = left_local_z * left_stride + left_local_x
		var right_idx: int = right_local_z * right_stride + right_local_x
		if left_idx < 0 or right_idx < 0 or left_idx >= left_vertices.size() or right_idx >= right_vertices.size():
			_failures.append("Seam test computed out-of-range border indices at row %d" % z)
			break
		if left_vertices[left_idx].distance_to(right_vertices[right_idx]) > EPSILON:
			_failures.append("Visible seam risk: border vertex mismatch at row %d" % z)
			break
		if left_normals[left_idx].distance_to(right_normals[right_idx]) > 0.01:
			_failures.append("Visible seam risk: border normal mismatch at row %d" % z)
			break

func _test_new_map_reset_after_edits(terrain: Node) -> void:
	terrain.apply_brush("raise", Vector3(32.0, 0.0, 32.0), 10.0, 0.4, 0.0, false, 0.3, 0.42, "smooth")
	var edited_height: float = terrain.sample_height(32.0, 32.0)
	if edited_height <= 0.0:
		_failures.append("Reset test setup failed; terrain did not deform")
	terrain.initialize_new_map()
	var reset_height: float = terrain.sample_height(32.0, 32.0)
	if absf(reset_height) > EPSILON:
		_failures.append("New map creation did not reset terrain data")

func _test_steep_multi_chunk_borders(terrain: Node) -> void:
	terrain.initialize_new_map()
	for i in range(10):
		var x: float = -26.0 + float(i) * 6.2
		var z: float = -18.0 + sin(float(i) * 0.75) * 20.0
		terrain.apply_brush("raise", Vector3(x, 0.0, z), 16.0, 0.75, 0.0, false, 0.3, 0.42, "sharp")

	_assert_shared_border_match(terrain, Vector2i(1, 1), Vector2i(2, 1), "steep-horiz")
	_assert_shared_border_match(terrain, Vector2i(1, 1), Vector2i(1, 2), "steep-vert")
	_assert_shared_border_match(terrain, Vector2i(2, 1), Vector2i(2, 2), "steep-vert-right")

func _assert_shared_border_match(terrain: Node, chunk_a_key: Vector2i, chunk_b_key: Vector2i, label: String) -> void:
	var chunks: Dictionary = terrain.get("_chunks")
	var a_chunk: Node = chunks.get(chunk_a_key, null) as Node
	var b_chunk: Node = chunks.get(chunk_b_key, null) as Node
	if a_chunk == null or b_chunk == null:
		_failures.append("%s: missing chunks for seam assertion" % label)
		return

	var a_arrays: Array = _get_chunk_surface_arrays(a_chunk)
	var b_arrays: Array = _get_chunk_surface_arrays(b_chunk)
	if a_arrays.is_empty() or b_arrays.is_empty():
		_failures.append("%s: missing chunk arrays for seam assertion" % label)
		return

	var a_vertices: PackedVector3Array = a_arrays[Mesh.ARRAY_VERTEX]
	var b_vertices: PackedVector3Array = b_arrays[Mesh.ARRAY_VERTEX]
	var a_normals: PackedVector3Array = a_arrays[Mesh.ARRAY_NORMAL]
	var b_normals: PackedVector3Array = b_arrays[Mesh.ARRAY_NORMAL]
	var a_stride: int = int(a_chunk.get("_local_stride"))
	var b_stride: int = int(b_chunk.get("_local_stride"))
	var a_sample_min_x: int = int(a_chunk.get("sample_min_x"))
	var a_sample_min_z: int = int(a_chunk.get("sample_min_z"))
	var b_sample_min_x: int = int(b_chunk.get("sample_min_x"))
	var b_sample_min_z: int = int(b_chunk.get("sample_min_z"))

	var shared_vertical: bool = int(a_chunk.get("max_x")) == int(b_chunk.get("min_x")) or int(b_chunk.get("max_x")) == int(a_chunk.get("min_x"))
	if shared_vertical:
		var shared_x: int = int(a_chunk.get("max_x")) if int(a_chunk.get("max_x")) == int(b_chunk.get("min_x")) else int(b_chunk.get("max_x"))
		var z_start: int = maxi(int(a_chunk.get("min_z")), int(b_chunk.get("min_z")))
		var z_end: int = mini(int(a_chunk.get("max_z")), int(b_chunk.get("max_z")))
		for wz in range(z_start, z_end + 1):
			var a_idx: int = (wz - a_sample_min_z) * a_stride + (shared_x - a_sample_min_x)
			var b_idx: int = (wz - b_sample_min_z) * b_stride + (shared_x - b_sample_min_x)
			if a_idx < 0 or b_idx < 0 or a_idx >= a_vertices.size() or b_idx >= b_vertices.size():
				_failures.append("%s: out-of-range vertical seam indices" % label)
				return
			if a_vertices[a_idx].distance_to(b_vertices[b_idx]) > EPSILON:
				_failures.append("%s: border vertex mismatch at z=%d" % [label, wz])
				return
			if a_normals[a_idx].distance_to(b_normals[b_idx]) > 0.01:
				_failures.append("%s: border normal mismatch at z=%d" % [label, wz])
				return
		return

	var shared_horizontal: bool = int(a_chunk.get("max_z")) == int(b_chunk.get("min_z")) or int(b_chunk.get("max_z")) == int(a_chunk.get("min_z"))
	if shared_horizontal:
		var shared_z: int = int(a_chunk.get("max_z")) if int(a_chunk.get("max_z")) == int(b_chunk.get("min_z")) else int(b_chunk.get("max_z"))
		var x_start: int = maxi(int(a_chunk.get("min_x")), int(b_chunk.get("min_x")))
		var x_end: int = mini(int(a_chunk.get("max_x")), int(b_chunk.get("max_x")))
		for wx in range(x_start, x_end + 1):
			var a_idx: int = (shared_z - a_sample_min_z) * a_stride + (wx - a_sample_min_x)
			var b_idx: int = (shared_z - b_sample_min_z) * b_stride + (wx - b_sample_min_x)
			if a_idx < 0 or b_idx < 0 or a_idx >= a_vertices.size() or b_idx >= b_vertices.size():
				_failures.append("%s: out-of-range horizontal seam indices" % label)
				return
			if a_vertices[a_idx].distance_to(b_vertices[b_idx]) > EPSILON:
				_failures.append("%s: border vertex mismatch at x=%d" % [label, wx])
				return
			if a_normals[a_idx].distance_to(b_normals[b_idx]) > 0.01:
				_failures.append("%s: border normal mismatch at x=%d" % [label, wx])
				return
		return

	_failures.append("%s: chunks are not adjacent" % label)

func _get_chunk_surface_arrays(chunk: Node) -> Array:
	if chunk == null:
		return []
	var mesh_instance: MeshInstance3D = chunk.get_node_or_null("ChunkMesh") as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null or not (mesh_instance.mesh is ArrayMesh):
		return []
	var mesh: ArrayMesh = mesh_instance.mesh as ArrayMesh
	if mesh.get_surface_count() <= 0:
		return []
	return mesh.surface_get_arrays(0)