extends Node3D
class_name WorldBrush

@export var terrain_size: float = 256.0
@export var terrain_resolution: int = 96
@export var max_terrain_height: float = 38.0
@export var min_terrain_height: float = -14.0
@export var seed_initial_terrain: bool = true
@export var auto_test_snow: bool = true

var _active_world_layer: int = 0
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _brush_preview: MeshInstance3D = null
var _brush_preview_enabled: bool = true
var _brush_preview_radius: float = 10.0

var _layer_heights: Dictionary = {}
var _layer_paint: Dictionary = {}
var _layer_water: Dictionary = {}
var _layer_snow: Dictionary = {}

func _ready() -> void:
	_ensure_nodes()
	_ensure_layer_data(_active_world_layer)
	if auto_test_snow:
		apply_procedural_snow(2.8, 10.0, 0.6)
	_rebuild_surface()

func set_world_layer(layer: int) -> void:
	_active_world_layer = layer
	_ensure_layer_data(_active_world_layer)
	_rebuild_surface()

func get_world_layer() -> int:
	return _active_world_layer

func set_brush_preview_enabled(enabled: bool) -> void:
	_brush_preview_enabled = enabled
	if _brush_preview != null:
		_brush_preview.visible = enabled

func set_brush_preview_radius(radius: float) -> void:
	_brush_preview_radius = maxf(radius, 0.5)
	if _brush_preview != null:
		_brush_preview.scale = Vector3(_brush_preview_radius, 1.0, _brush_preview_radius)

func update_brush_preview(camera: Camera3D, mouse_pos: Vector2) -> void:
	if camera == null or _brush_preview == null:
		return
	if not _brush_preview_enabled:
		_brush_preview.visible = false
		return
	var origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var direction: Vector3 = camera.project_ray_normal(mouse_pos)
	var hit: Variant = get_intersection(origin, direction, true)
	if hit == null:
		_brush_preview.visible = false
		return
	_brush_preview.visible = true
	_brush_preview.global_position = (hit as Vector3) + Vector3(0.05, 0.06, 0.05)
	_brush_preview.scale = Vector3(_brush_preview_radius, 1.0, _brush_preview_radius)

func get_intersection(origin: Vector3, direction: Vector3, _with_water: bool = true) -> Variant:
	if absf(direction.y) < 0.00001:
		return null
	var t: float = (global_position.y - origin.y) / direction.y
	if t < 0.0:
		return null
	var hit: Vector3 = origin + direction * t
	var local_hit: Vector3 = to_local(hit)
	var half: float = terrain_size * 0.5
	if local_hit.x < -half or local_hit.x > half or local_hit.z < -half or local_hit.z > half:
		return null
	var y: float = sample_height(hit.x, hit.z)
	return Vector3(hit.x, y, hit.z)

func sample_height(world_x: float, world_z: float) -> float:
	_ensure_layer_data(_active_world_layer)
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var local: Vector3 = to_local(Vector3(world_x, 0.0, world_z))
	var half: float = terrain_size * 0.5
	var u: float = clampf((local.x + half) / terrain_size, 0.0, 1.0)
	var v: float = clampf((local.z + half) / terrain_size, 0.0, 1.0)
	var n: int = terrain_resolution + 1
	var fx: float = u * float(terrain_resolution)
	var fz: float = v * float(terrain_resolution)
	var x0: int = int(floor(fx))
	var z0: int = int(floor(fz))
	var x1: int = mini(x0 + 1, terrain_resolution)
	var z1: int = mini(z0 + 1, terrain_resolution)
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = heights[_idx(x0, z0, n)]
	var h10: float = heights[_idx(x1, z0, n)]
	var h01: float = heights[_idx(x0, z1, n)]
	var h11: float = heights[_idx(x1, z1, n)]
	var hx0: float = lerpf(h00, h10, tx)
	var hx1: float = lerpf(h01, h11, tx)
	return global_position.y + lerpf(hx0, hx1, tz)

func apply_brush(tool_name: String, world_pos: Vector3, brush_size: float, brush_strength: float, flatten_height: float = 0.0, _cliff_mode: bool = false, _overhang_amount: float = 0.3) -> void:
	_ensure_layer_data(_active_world_layer)
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var water: PackedFloat32Array = _layer_water[_active_world_layer]
	var snow: PackedFloat32Array = _layer_snow[_active_world_layer]
	var snapshot: PackedFloat32Array = heights.duplicate()

	var local_center: Vector3 = to_local(world_pos)
	var half: float = terrain_size * 0.5
	var grid_step: float = terrain_size / float(terrain_resolution)
	var radius: float = maxf(brush_size, 0.5)
	var min_x: int = maxi(0, int(floor(((local_center.x - radius) + half) / grid_step)))
	var max_x: int = mini(terrain_resolution, int(ceil(((local_center.x + radius) + half) / grid_step)))
	var min_z: int = maxi(0, int(floor(((local_center.z - radius) + half) / grid_step)))
	var max_z: int = mini(terrain_resolution, int(ceil(((local_center.z + radius) + half) / grid_step)))
	var n: int = terrain_resolution + 1

	for z in range(min_z, max_z + 1):
		var pz: float = -half + float(z) * grid_step
		for x in range(min_x, max_x + 1):
			var px: float = -half + float(x) * grid_step
			var d: float = Vector2(px - local_center.x, pz - local_center.z).length()
			if d > radius:
				continue
			var w: float = 1.0 - (d / radius)
			w = w * w
			var idxv: int = _idx(x, z, n)
			match tool_name:
				"raise":
					heights[idxv] += brush_strength * w * 0.9
				"lower":
					heights[idxv] -= brush_strength * w * 0.9
				"smooth":
					var avg: float = _neighbor_average(snapshot, x, z)
					heights[idxv] = lerpf(heights[idxv], avg, clampf(brush_strength * w, 0.0, 1.0))
				"flatten":
					heights[idxv] = lerpf(heights[idxv], flatten_height, clampf(brush_strength * w, 0.0, 1.0))
				"paint":
					paint[idxv] = clampf(paint[idxv] + brush_strength * w * 0.5, 0.0, 1.0)
				"texturepaint":
					paint[idxv] = clampf(paint[idxv] + brush_strength * w * 0.6, 0.0, 1.0)
				"textureerase":
					paint[idxv] = clampf(paint[idxv] - brush_strength * w * 0.7, 0.0, 1.0)
				"waterpaint":
					water[idxv] = clampf(water[idxv] + brush_strength * w * 0.55, 0.0, 1.0)
					heights[idxv] -= brush_strength * w * 0.35
					paint[idxv] = clampf(paint[idxv] + brush_strength * w * 0.25, 0.0, 1.0)
				"watererase":
					water[idxv] = clampf(water[idxv] - brush_strength * w * 0.7, 0.0, 1.0)
				"snowpaint":
					snow[idxv] = clampf(snow[idxv] + brush_strength * w * 0.7, 0.0, 1.0)
				"snowerase":
					snow[idxv] = clampf(snow[idxv] - brush_strength * w * 0.8, 0.0, 1.0)
				_:
					pass
			heights[idxv] = clampf(heights[idxv], min_terrain_height, max_terrain_height)

	_layer_heights[_active_world_layer] = heights
	_layer_paint[_active_world_layer] = paint
	_layer_water[_active_world_layer] = water
	_layer_snow[_active_world_layer] = snow
	_rebuild_surface()

func begin_texture_stroke(_perf_mode: bool = true, _brush_radius: float = 8.0) -> void:
	pass

func apply_texture_brush(world_pos: Vector3, _albedo: Texture2D = null, _normal: Texture2D = null, _roughness: Texture2D = null, _height: Texture2D = null, _ao: Texture2D = null, brush_size: float = 8.0, brush_strength: float = 0.3, _tile_size: float = 4.0, density: float = 0.75, _softness: float = 0.7, _coverage: float = 0.75, _offset: Vector2 = Vector2.ZERO, _rot: float = 0.0, _scale: float = 1.0, _exposure: float = 1.0, _shape: String = "circle", _variation: float = 0.0, _seed: float = 0.0, _variant: int = 0) -> void:
	apply_brush("texturepaint", world_pos, brush_size, maxf(brush_strength * density, 0.01))

func apply_texture_erase_brush(world_pos: Vector3, brush_size: float = 8.0, brush_strength: float = 0.3, _softness: float = 0.7) -> void:
	apply_brush("textureerase", world_pos, brush_size, brush_strength)

func end_texture_stroke() -> void:
	pass

func apply_procedural_snow(min_height: float = 2.0, max_height: float = 22.0, intensity: float = 0.8) -> void:
	_ensure_layer_data(_active_world_layer)
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var snow: PackedFloat32Array = _layer_snow[_active_world_layer]
	for i in range(heights.size()):
		var t: float = inverse_lerp(min_height, max_height, heights[i])
		t = clampf(t, 0.0, 1.0)
		snow[i] = clampf(maxf(snow[i], t * intensity), 0.0, 1.0)
	_layer_snow[_active_world_layer] = snow
	_rebuild_surface()

func _ensure_nodes() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		add_child(_mesh_instance)
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.roughness = 0.92
		_material.metallic = 0.0
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh_instance.material_override = _material
	if _brush_preview == null:
		_brush_preview = MeshInstance3D.new()
		_brush_preview.name = "BrushPreview"
		var ring := CylinderMesh.new()
		ring.top_radius = 1.0
		ring.bottom_radius = 1.0
		ring.height = 0.03
		ring.radial_segments = 48
		_brush_preview.mesh = ring
		var ring_mat := StandardMaterial3D.new()
		ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring_mat.albedo_color = Color(0.08, 0.85, 1.0, 0.30)
		ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_brush_preview.material_override = ring_mat
		_brush_preview.visible = false
		add_child(_brush_preview)

func _ensure_layer_data(layer: int) -> void:
	if _layer_heights.has(layer):
		return
	var count: int = (terrain_resolution + 1) * (terrain_resolution + 1)
	var heights := PackedFloat32Array()
	var paint := PackedFloat32Array()
	var water := PackedFloat32Array()
	var snow := PackedFloat32Array()
	heights.resize(count)
	paint.resize(count)
	water.resize(count)
	snow.resize(count)
	for i in range(count):
		heights[i] = 0.0
		paint[i] = 0.0
		water[i] = 0.0
		snow[i] = 0.0
	if seed_initial_terrain:
		_seed_height_data(heights)
	_layer_heights[layer] = heights
	_layer_paint[layer] = paint
	_layer_water[layer] = water
	_layer_snow[layer] = snow

func _seed_height_data(heights: PackedFloat32Array) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.016
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	var stride: int = terrain_resolution + 1
	var half: float = terrain_size * 0.5
	var step: float = terrain_size / float(terrain_resolution)
	for z in range(stride):
		for x in range(stride):
			var idxv: int = _idx(x, z, stride)
			var px: float = -half + float(x) * step
			var pz: float = -half + float(z) * step
			var n: float = noise.get_noise_2d(px, pz)
			heights[idxv] = clampf(n * 5.0, min_terrain_height, max_terrain_height)

func _neighbor_average(data: PackedFloat32Array, x: int, z: int) -> float:
	var n: int = terrain_resolution + 1
	var sum: float = 0.0
	var count: float = 0.0
	for zz in range(maxi(0, z - 1), mini(terrain_resolution, z + 1) + 1):
		for xx in range(maxi(0, x - 1), mini(terrain_resolution, x + 1) + 1):
			sum += data[_idx(xx, zz, n)]
			count += 1.0
	if count <= 0.0:
		return data[_idx(x, z, n)]
	return sum / count

func _idx(x: int, z: int, stride: int) -> int:
	return z * stride + x

func _rebuild_surface() -> void:
	_ensure_layer_data(_active_world_layer)
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var water: PackedFloat32Array = _layer_water[_active_world_layer]
	var snow: PackedFloat32Array = _layer_snow[_active_world_layer]
	var stride: int = terrain_resolution + 1
	var count: int = stride * stride
	var half: float = terrain_size * 0.5
	var step: float = terrain_size / float(terrain_resolution)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)

	for z in range(stride):
		for x in range(stride):
			var i: int = _idx(x, z, stride)
			var px: float = -half + float(x) * step
			var pz: float = -half + float(z) * step
			vertices[i] = Vector3(px, heights[i], pz)
			var snow_amt: float = snow[i]
			var water_amt: float = water[i]
			var paint_amt: float = paint[i]
			var terrain_col: Color = Color(0.20, 0.29, 0.22, 1.0)
			terrain_col = terrain_col.lerp(Color(0.40, 0.33, 0.24, 1.0), paint_amt)
			terrain_col = terrain_col.lerp(Color(0.19, 0.40, 0.52, 1.0), water_amt * 0.9)
			terrain_col = terrain_col.lerp(Color(0.91, 0.93, 0.95, 1.0), snow_amt)
			colors[i] = terrain_col

	for z in range(stride):
		for x in range(stride):
			var i2: int = _idx(x, z, stride)
			var xl: int = maxi(0, x - 1)
			var xr: int = mini(terrain_resolution, x + 1)
			var zd: int = maxi(0, z - 1)
			var zu: int = mini(terrain_resolution, z + 1)
			var hl: float = heights[_idx(xl, z, stride)]
			var hr: float = heights[_idx(xr, z, stride)]
			var hd: float = heights[_idx(x, zd, stride)]
			var hu: float = heights[_idx(x, zu, stride)]
			var nx: float = hl - hr
			var nz: float = hd - hu
			normals[i2] = Vector3(nx, 2.0 * step, nz).normalized()

	var indices := PackedInt32Array()
	indices.resize(terrain_resolution * terrain_resolution * 6)
	var widx: int = 0
	for z2 in range(terrain_resolution):
		for x2 in range(terrain_resolution):
			var a: int = _idx(x2, z2, stride)
			var b: int = _idx(x2 + 1, z2, stride)
			var c: int = _idx(x2, z2 + 1, stride)
			var d: int = _idx(x2 + 1, z2 + 1, stride)
			indices[widx] = a
			indices[widx + 1] = c
			indices[widx + 2] = b
			indices[widx + 3] = b
			indices[widx + 4] = c
			indices[widx + 5] = d
			widx += 6

	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_mesh_instance.mesh = mesh
