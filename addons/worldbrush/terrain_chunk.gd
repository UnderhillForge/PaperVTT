extends Node3D
class_name TerrainChunk

var chunk_coord: Vector2i = Vector2i.ZERO
var min_x: int = 0
var max_x: int = 0
var min_z: int = 0
var max_z: int = 0
var sample_min_x: int = 0
var sample_max_x: int = 0
var sample_min_z: int = 0
var sample_max_z: int = 0
var border_vertices: int = 1

var _mesh_instance: MeshInstance3D = null
var _debug_border_instance: MeshInstance3D = null
var _material: Material = null
var _local_stride: int = 0
var _terrain_resolution: int = 0
var _terrain_size: float = 0.0
var _min_terrain_height: float = 0.0
var _max_terrain_height: float = 0.0
var _debug_border_enabled: bool = false
var _debug_border_color: Color = Color.WHITE
var _debug_border_highlight: bool = false
var _debug_rebuild_logging: bool = false

func setup(coord: Vector2i, grid_min_x: int, grid_max_x: int, grid_min_z: int, grid_max_z: int, material: Material, border_width: int = 1) -> void:
	chunk_coord = coord
	min_x = grid_min_x
	max_x = grid_max_x
	min_z = grid_min_z
	max_z = grid_max_z
	border_vertices = maxi(border_width, 1)
	_material = material
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "ChunkMesh"
		add_child(_mesh_instance)
	# Stagger per-chunk sorting offset so depth-buffer ties are broken
	# consistently in ortho top-down view (sorting_offset shifts the depth
	# sort key without altering actual vertex positions).
	_mesh_instance.sorting_offset = float((coord.x & 0xF) * 16 + (coord.y & 0xF)) * 0.0001
	if _debug_border_instance == null:
		_debug_border_instance = MeshInstance3D.new()
		_debug_border_instance.name = "ChunkDebugBorder"
		_debug_border_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_debug_border_instance)
	if _material != null:
		_mesh_instance.material_override = _material
	_debug_border_instance.visible = false

func intersects_vertex_rect(rect_min_x: int, rect_max_x: int, rect_min_z: int, rect_max_z: int) -> bool:
	if rect_max_x < min_x or rect_min_x > max_x:
		return false
	if rect_max_z < min_z or rect_min_z > max_z:
		return false
	return true

func rebuild_mesh(heights: PackedFloat32Array, paint: PackedFloat32Array, water: PackedFloat32Array, snow: PackedFloat32Array, terrain_resolution: int, terrain_size: float, min_terrain_height: float, max_terrain_height: float) -> void:
	if _mesh_instance == null:
		return
	var old_surface_count: int = 0
	if _mesh_instance.mesh != null:
		if _mesh_instance.mesh is ArrayMesh:
			var existing_mesh: ArrayMesh = _mesh_instance.mesh as ArrayMesh
			old_surface_count = existing_mesh.get_surface_count()
			existing_mesh.clear_surfaces()
		_mesh_instance.mesh = null
		# Clear material binding before assigning fresh geometry to avoid stale render state.
		_mesh_instance.material_override = null
	if _debug_rebuild_logging:
		print("Rebuilding chunk ", chunk_coord, " | Old surfaces: ", old_surface_count)
	_terrain_resolution = terrain_resolution
	_terrain_size = terrain_size
	_min_terrain_height = min_terrain_height
	_max_terrain_height = max_terrain_height
	var width: int = max_x - min_x
	var depth: int = max_z - min_z
	if width <= 0 or depth <= 0:
		_mesh_instance.mesh = null
		if _debug_border_instance != null:
			_debug_border_instance.mesh = null
		return

	sample_min_x = maxi(0, min_x - border_vertices)
	sample_max_x = mini(terrain_resolution, max_x + border_vertices)
	sample_min_z = maxi(0, min_z - border_vertices)
	sample_max_z = mini(terrain_resolution, max_z + border_vertices)

	var stride: int = terrain_resolution + 1
	var sample_width: int = sample_max_x - sample_min_x
	var sample_depth: int = sample_max_z - sample_min_z
	var local_stride: int = sample_width + 1
	var vertex_count: int = local_stride * (sample_depth + 1)
	var half: float = terrain_size * 0.5
	var step: float = terrain_size / float(terrain_resolution)
	_local_stride = local_stride

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	uvs.resize(vertex_count)

	for z_local in range(sample_depth + 1):
		var gz: int = sample_min_z + z_local
		for x_local in range(sample_width + 1):
			var gx: int = sample_min_x + x_local
			var local_idx: int = z_local * local_stride + x_local
			var global_idx: int = gz * stride + gx
			var px: float = -half + float(gx) * step
			var pz: float = -half + float(gz) * step
			vertices[local_idx] = Vector3(px, heights[global_idx], pz)
			uvs[local_idx] = Vector2(float(gx) / float(terrain_resolution), float(gz) / float(terrain_resolution))
			colors[local_idx] = _compute_vertex_color(paint[global_idx], water[global_idx], snow[global_idx])
			normals[local_idx] = _compute_normal(heights, gx, gz, step, terrain_resolution, stride)

	# Explicitly snap all shared chunk-edge vertices/normals from the master height array.
	_snap_shared_border_data(vertices, normals, heights, step, half, stride)

	var tri_count: int = width * depth * 2
	var indices := PackedInt32Array()
	indices.resize(tri_count * 3)
	var wi: int = 0
	for gz in range(min_z, max_z):
		for gx in range(min_x, max_x):
			var local_x: int = gx - sample_min_x
			var local_z: int = gz - sample_min_z
			var a: int = local_z * local_stride + local_x
			var b: int = a + 1
			var c: int = a + local_stride
			var d: int = c + 1
			indices[wi] = a
			indices[wi + 1] = c
			indices[wi + 2] = b
			indices[wi + 3] = b
			indices[wi + 4] = c
			indices[wi + 5] = d
			wi += 6

	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.set_custom_aabb(AABB(
		Vector3(-half, min_terrain_height, -half),
		Vector3(terrain_size, max_terrain_height - min_terrain_height, terrain_size)
	))
	_mesh_instance.mesh = mesh
	# Re-apply the terrain material every rebuild to ensure fresh surface state.
	if _material != null:
		_mesh_instance.material_override = _material
	_update_debug_border(vertices)

func rebuild_region_from_source(heights: PackedFloat32Array, paint: PackedFloat32Array, water: PackedFloat32Array, snow: PackedFloat32Array, terrain_resolution: int, terrain_size: float, min_terrain_height: float, max_terrain_height: float, dirty_min_x: int, dirty_max_x: int, dirty_min_z: int, dirty_max_z: int, border_padding: int = 4, force_rebuild: bool = false) -> void:
	if not force_rebuild and not intersects_vertex_rect(dirty_min_x, dirty_max_x, dirty_min_z, dirty_max_z):
		return
	rebuild_mesh(heights, paint, water, snow, terrain_resolution, terrain_size, min_terrain_height, max_terrain_height)

func set_debug_border(enabled: bool, color: Color = Color.WHITE, highlight: bool = false) -> void:
	_debug_border_enabled = enabled
	_debug_border_color = color
	_debug_border_highlight = highlight
	if _debug_border_instance != null:
		_debug_border_instance.visible = enabled and _debug_border_instance.mesh != null
		# Update the existing border material immediately so color and emission
		# take effect without waiting for the next full mesh rebuild.
		if enabled and _debug_border_instance.material_override != null:
			var mat: StandardMaterial3D = _debug_border_instance.material_override as StandardMaterial3D
			if mat != null:
				mat.albedo_color = color
				mat.emission = color
				mat.emission_energy_multiplier = 3.0 if highlight else 0.75

func set_debug_rebuild_logging(enabled: bool) -> void:
	_debug_rebuild_logging = enabled

func _compute_normal(heights: PackedFloat32Array, x: int, z: int, step: float, terrain_resolution: int, stride: int) -> Vector3:
	var xl: int = maxi(0, x - 1)
	var xr: int = mini(terrain_resolution, x + 1)
	var zd: int = maxi(0, z - 1)
	var zu: int = mini(terrain_resolution, z + 1)
	var hl: float = heights[z * stride + xl]
	var hr: float = heights[z * stride + xr]
	var hd: float = heights[zd * stride + x]
	var hu: float = heights[zu * stride + x]
	var nx: float = hl - hr
	var nz: float = hd - hu
	return Vector3(nx, 2.0 * step, nz).normalized()

func _compute_vertex_color(paint_amt: float, water_amt: float, snow_amt: float) -> Color:
	var terrain_col: Color = Color(0.20, 0.29, 0.22, 1.0)
	terrain_col = terrain_col.lerp(Color(0.40, 0.33, 0.24, 1.0), paint_amt)
	terrain_col = terrain_col.lerp(Color(0.19, 0.40, 0.52, 1.0), water_amt * 0.9)
	terrain_col = terrain_col.lerp(Color(0.91, 0.93, 0.95, 1.0), snow_amt)
	return terrain_col

func _snap_shared_border_data(vertices: PackedVector3Array, normals: PackedVector3Array, heights: PackedFloat32Array, step: float, half: float, stride: int) -> void:
	# Left and right shared borders.
	for gz in range(min_z, max_z + 1):
		_snap_world_vertex(vertices, normals, heights, min_x, gz, step, half, stride)
		_snap_world_vertex(vertices, normals, heights, max_x, gz, step, half, stride)
	# Top and bottom shared borders.
	for gx in range(min_x, max_x + 1):
		_snap_world_vertex(vertices, normals, heights, gx, min_z, step, half, stride)
		_snap_world_vertex(vertices, normals, heights, gx, max_z, step, half, stride)

func _snap_world_vertex(vertices: PackedVector3Array, normals: PackedVector3Array, heights: PackedFloat32Array, gx: int, gz: int, step: float, half: float, stride: int) -> void:
	var local_index: int = _local_index_from_world(gx, gz)
	if local_index < 0 or local_index >= vertices.size():
		return
	var global_index: int = gz * stride + gx
	vertices[local_index] = Vector3(
		-half + float(gx) * step,
		heights[global_index],
		-half + float(gz) * step
	)
	normals[local_index] = _compute_normal(heights, gx, gz, step, _terrain_resolution, stride)

func _local_index_from_world(gx: int, gz: int) -> int:
	var lx: int = gx - sample_min_x
	var lz: int = gz - sample_min_z
	if lx < 0 or lz < 0:
		return -1
	if lx >= _local_stride:
		return -1
	return lz * _local_stride + lx

func _update_debug_border(vertices: PackedVector3Array) -> void:
	if _debug_border_instance == null:
		return
	if not _debug_border_enabled:
		_debug_border_instance.visible = false
		_debug_border_instance.mesh = null
		return
	var points := PackedVector3Array()
	for gx in range(min_x, max_x + 1):
		points.append(_debug_vertex(vertices, gx, min_z))
	for gz in range(min_z + 1, max_z + 1):
		points.append(_debug_vertex(vertices, max_x, gz))
	for gx in range(max_x - 1, min_x - 1, -1):
		points.append(_debug_vertex(vertices, gx, max_z))
	for gz in range(max_z - 1, min_z, -1):
		points.append(_debug_vertex(vertices, min_x, gz))
	if points.size() < 2:
		_debug_border_instance.visible = false
		_debug_border_instance.mesh = null
		return
	var line_vertices := PackedVector3Array()
	for i in range(points.size()):
		line_vertices.append(points[i])
		line_vertices.append(points[(i + 1) % points.size()])
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = line_vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = _debug_border_color
	material.emission_enabled = true
	material.emission = _debug_border_color
	material.emission_energy_multiplier = 3.0 if _debug_border_highlight else 0.75
	material.no_depth_test = true
	_debug_border_instance.mesh = mesh
	_debug_border_instance.material_override = material
	_debug_border_instance.visible = true

func _debug_vertex(vertices: PackedVector3Array, gx: int, gz: int) -> Vector3:
	var local_x: int = gx - sample_min_x
	var local_z: int = gz - sample_min_z
	var idx: int = local_z * _local_stride + local_x
	return vertices[idx] + Vector3(0.0, 0.06, 0.0)
