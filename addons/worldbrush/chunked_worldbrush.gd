extends Node3D
class_name ChunkedWorldBrush

const TERRAIN_CHUNK_SCRIPT: Script = preload("res://addons/worldbrush/terrain_chunk.gd")
const TERRAIN_BASE_ALBEDO_PATH: String = "res://assets/world/textures/world/grass_04_2k/grass_04_basecolor_2k.png"

@export var terrain_size: float = 256.0
@export var terrain_resolution: int = 96
@export var max_terrain_height: float = 38.0
@export var min_terrain_height: float = -14.0
@export var seed_initial_terrain: bool = true
@export var auto_test_snow: bool = true
@export var terrain_texture_uv_repeat: float = 50.0
@export var chunk_size_world: float = 64.0
@export var chunk_border_padding: int = 4
@export var chunk_mesh_border_vertices: int = 2
@export var debug_draw_chunk_borders: bool = false
@export var debug_draw_chunk_borders_red: bool = false
@export var debug_highlight_problem_borders: bool = false
@export var debug_chunk_rebuild_logging: bool = false
@export var high_raise_force_full_rebuild_delta: float = 0.75
@export var steep_slope_threshold: float = 1.15
@export var steep_slope_extra_neighbor_ring: int = 1

var _active_world_layer: int = 0
var _layer_heights: Dictionary = {}
var _layer_paint: Dictionary = {}
var _layer_water: Dictionary = {}
var _layer_snow: Dictionary = {}

var _chunk_root: Node3D = null
var _chunks: Dictionary = {}
var _material: StandardMaterial3D = null

var _brush_preview: MeshInstance3D = null
var _brush_preview_enabled: bool = true
var _brush_preview_radius: float = 10.0

var smooth_mode_post_smooth_enabled: bool = true
var smooth_mode_post_smooth_strength: float = 0.12
var _full_rebuild_mode: bool = false
var _chunk_vertex_span: int = 1
var _chunk_count_x: int = 0
var _chunk_count_z: int = 0
var _last_rebuilt_chunks: Array[Vector2i] = []

func _ready() -> void:
	_ensure_nodes()
	_ensure_layer_data(_active_world_layer)
	if auto_test_snow:
		apply_procedural_snow(2.8, 10.0, 0.6)
	else:
		rebuild_mesh()

func set_world_layer(layer: int) -> void:
	_active_world_layer = layer
	_ensure_layer_data(_active_world_layer)
	rebuild_mesh()

func get_world_layer() -> int:
	return _active_world_layer

func initialize_new_map(_seed: int = 0) -> void:
	_layer_heights.clear()
	_layer_paint.clear()
	_layer_water.clear()
	_layer_snow.clear()
	_clear_chunks()
	_ensure_layer_data(_active_world_layer)
	rebuild_mesh()

func serialize_state() -> Dictionary:
	var out: Dictionary = {
		"terrain_backend": "chunked",
		"terrain_size": terrain_size,
		"terrain_resolution": terrain_resolution,
		"max_terrain_height": max_terrain_height,
		"min_terrain_height": min_terrain_height,
		"chunk_size_world": chunk_size_world,
		"active_world_layer": _active_world_layer,
		"layers": {}
	}
	for layer_key in _layer_heights.keys():
		var layer: int = int(layer_key)
		out["layers"][str(layer)] = {
			"heights": _layer_heights[layer],
			"paint": _layer_paint.get(layer, PackedFloat32Array()),
			"water": _layer_water.get(layer, PackedFloat32Array()),
			"snow": _layer_snow.get(layer, PackedFloat32Array())
		}
	return out

func load_state(data: Dictionary) -> void:
	if data.has("terrain_size"):
		terrain_size = float(data.get("terrain_size", terrain_size))
	if data.has("terrain_resolution"):
		terrain_resolution = int(data.get("terrain_resolution", terrain_resolution))
	if data.has("max_terrain_height"):
		max_terrain_height = float(data.get("max_terrain_height", max_terrain_height))
	if data.has("min_terrain_height"):
		min_terrain_height = float(data.get("min_terrain_height", min_terrain_height))
	if data.has("chunk_size_world"):
		chunk_size_world = float(data.get("chunk_size_world", chunk_size_world))
	_active_world_layer = int(data.get("active_world_layer", _active_world_layer))

	_layer_heights.clear()
	_layer_paint.clear()
	_layer_water.clear()
	_layer_snow.clear()
	_clear_chunks()

	var layers: Dictionary = data.get("layers", {})
	for key_variant in layers.keys():
		var key: String = String(key_variant)
		var layer_id: int = int(key)
		var layer_data: Dictionary = layers[key]
		_layer_heights[layer_id] = layer_data.get("heights", PackedFloat32Array())
		_layer_paint[layer_id] = layer_data.get("paint", PackedFloat32Array())
		_layer_water[layer_id] = layer_data.get("water", PackedFloat32Array())
		_layer_snow[layer_id] = layer_data.get("snow", PackedFloat32Array())

	_ensure_layer_data(_active_world_layer)
	rebuild_mesh()

func set_smooth_mode_options(post_smooth_enabled: bool, post_smooth_strength: float = -1.0) -> void:
	smooth_mode_post_smooth_enabled = post_smooth_enabled
	if post_smooth_strength >= 0.0:
		smooth_mode_post_smooth_strength = clampf(post_smooth_strength, 0.0, 0.35)

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

func get_smooth_falloff(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var t: float = clampf(1.0 - (distance / radius), 0.0, 1.0)
	return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

func get_sharp_falloff(distance: float, radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var t: float = clampf(1.0 - (distance / radius), 0.0, 1.0)
	return t * t

func apply_brush(tool_name: String, world_pos: Vector3, brush_size: float, brush_strength: float, flatten_height: float = 0.0, _cliff_mode: bool = false, _overhang_amount: float = 0.3, brush_softness: float = 0.42, brush_mode: String = "smooth") -> void:
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
	var influence_radius: float = radius + (grid_step * 0.5)
	var min_x: int = maxi(0, int(floor(((local_center.x - radius) + half) / grid_step)))
	var max_x: int = mini(terrain_resolution, int(ceil(((local_center.x + radius) + half) / grid_step)))
	var min_z: int = maxi(0, int(floor(((local_center.z - radius) + half) / grid_step)))
	var max_z: int = mini(terrain_resolution, int(ceil(((local_center.z + radius) + half) / grid_step)))
	var n: int = terrain_resolution + 1

	var deformation_strength_multiplier: float = (0.65 + (0.35 * clampf(brush_softness, 0.0, 1.0))) if brush_mode == "smooth" else 1.0
	var is_deformation_tool: bool = tool_name in ["raise", "lower", "smooth", "flatten"]
	var max_height_delta: float = 0.0

	for z in range(min_z, max_z + 1):
		var pz: float = -half + float(z) * grid_step
		for x in range(min_x, max_x + 1):
			var px: float = -half + float(x) * grid_step
			var d: float = Vector2(px - local_center.x, pz - local_center.z).length()
			if d > influence_radius:
				continue
			var w: float = get_smooth_falloff(d, influence_radius) if brush_mode == "smooth" else get_sharp_falloff(d, influence_radius)
			var idxv: int = _idx(x, z, n)
			var before_height: float = heights[idxv]
			var applied_strength: float = brush_strength
			if is_deformation_tool:
				applied_strength *= deformation_strength_multiplier
			match tool_name:
				"raise":
					heights[idxv] += applied_strength * w * 0.9
				"lower":
					heights[idxv] -= applied_strength * w * 0.9
				"smooth":
					var avg: float = _neighbor_average(snapshot, x, z)
					heights[idxv] = lerpf(heights[idxv], avg, clampf(applied_strength * w, 0.0, 1.0))
				"flatten":
					heights[idxv] = lerpf(heights[idxv], flatten_height, clampf(applied_strength * w, 0.0, 1.0))
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
			if is_deformation_tool:
				max_height_delta = maxf(max_height_delta, absf(heights[idxv] - before_height))

	if brush_mode == "smooth" and smooth_mode_post_smooth_enabled and tool_name in ["raise", "lower"]:
		_apply_local_relax_pass(heights, min_x, max_x, min_z, max_z, influence_radius, local_center)

	_layer_heights[_active_world_layer] = heights
	_layer_paint[_active_world_layer] = paint
	_layer_water[_active_world_layer] = water
	_layer_snow[_active_world_layer] = snow
	var force_full_for_raise: bool = tool_name == "raise" and max_height_delta >= maxf(high_raise_force_full_rebuild_delta, 0.1)
	if _full_rebuild_mode:
		rebuild_mesh()
		return
	if force_full_for_raise:
		if debug_chunk_rebuild_logging:
			print("Chunked terrain full rebuild triggered by high raise delta: ", max_height_delta)
		rebuild_mesh()
		return
	_rebuild_chunks_intersecting_rect(min_x, max_x, min_z, max_z)

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
	rebuild_mesh()

func rebuild_mesh() -> void:
	_ensure_layer_data(_active_world_layer)
	_ensure_chunk_layout()
	_last_rebuilt_chunks.clear()
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var water: PackedFloat32Array = _layer_water[_active_world_layer]
	var snow: PackedFloat32Array = _layer_snow[_active_world_layer]
	for key_variant in _chunks.keys():
		var key: Vector2i = key_variant as Vector2i
		var chunk: Node = _chunks[key] as Node
		if chunk != null:
			chunk.set_debug_rebuild_logging(debug_chunk_rebuild_logging)
			chunk.rebuild_mesh(heights, paint, water, snow, terrain_resolution, terrain_size, min_terrain_height, max_terrain_height)
			chunk.set_debug_border(debug_draw_chunk_borders, _chunk_debug_color(key), debug_highlight_problem_borders)
			_last_rebuilt_chunks.append(key)

func _ensure_nodes() -> void:
	if _chunk_root == null:
		_chunk_root = Node3D.new()
		_chunk_root.name = "TerrainChunks"
		add_child(_chunk_root)
	_ensure_terrain_material()
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

func _ensure_terrain_material() -> void:
	if _material != null:
		return
	_material = StandardMaterial3D.new()
	_material.name = "ChunkedTerrainMaterial"
	_material.vertex_color_use_as_albedo = false
	var base_albedo: Texture2D = load(TERRAIN_BASE_ALBEDO_PATH) as Texture2D
	if base_albedo != null:
		_material.albedo_texture = base_albedo
		_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	else:
		_material.albedo_color = Color(0.36, 0.45, 0.32, 1.0)
	var repeat_scale: float = maxf(terrain_texture_uv_repeat, 1.0)
	_material.uv1_scale = Vector3(repeat_scale, repeat_scale, 1.0)
	_material.roughness = 0.92
	_material.metallic = 0.0
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Force fully opaque depth writes — prevents any depth-sort ambiguity in
	# ortho top-down mode that could manifest as lighter-patch artefacts.
	_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY

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

func _apply_local_relax_pass(heights: PackedFloat32Array, min_x: int, max_x: int, min_z: int, max_z: int, influence_radius: float, local_center: Vector3) -> void:
	var n: int = terrain_resolution + 1
	var half: float = terrain_size * 0.5
	var grid_step: float = terrain_size / float(terrain_resolution)
	var strength: float = clampf(smooth_mode_post_smooth_strength, 0.0, 0.35)
	if strength <= 0.0:
		return
	var snapshot: PackedFloat32Array = heights.duplicate()
	for z in range(min_z, max_z + 1):
		var pz: float = -half + float(z) * grid_step
		for x in range(min_x, max_x + 1):
			var px: float = -half + float(x) * grid_step
			var d: float = Vector2(px - local_center.x, pz - local_center.z).length()
			if d > influence_radius:
				continue
			var w: float = get_smooth_falloff(d, influence_radius)
			if w <= 0.0:
				continue
			var idxv: int = _idx(x, z, n)
			var avg: float = _neighbor_average(snapshot, x, z)
			heights[idxv] = lerpf(heights[idxv], avg, strength * w)

func _clear_chunks() -> void:
	_chunks.clear()
	_chunk_vertex_span = 1
	_chunk_count_x = 0
	_chunk_count_z = 0
	if _chunk_root == null:
		return
	var children: Array = _chunk_root.get_children()
	for child_variant in children:
		var child: Node = child_variant as Node
		if child == null:
			continue
		_chunk_root.remove_child(child)
		child.free()

func _ensure_chunk_layout() -> void:
	if _chunk_root == null:
		return
	if not _chunks.is_empty():
		return
	var step: float = terrain_size / float(terrain_resolution)
	_chunk_vertex_span = maxi(1, int(round(chunk_size_world / step)))
	_chunk_count_x = int(ceil(float(terrain_resolution) / float(_chunk_vertex_span)))
	_chunk_count_z = int(ceil(float(terrain_resolution) / float(_chunk_vertex_span)))
	for cz in range(_chunk_count_z):
		for cx in range(_chunk_count_x):
			var min_x: int = cx * _chunk_vertex_span
			var max_x: int = mini(terrain_resolution, (cx + 1) * _chunk_vertex_span)
			var min_z: int = cz * _chunk_vertex_span
			var max_z: int = mini(terrain_resolution, (cz + 1) * _chunk_vertex_span)
			var chunk_node := Node3D.new()
			chunk_node.name = "Chunk_%d_%d" % [cx, cz]
			chunk_node.set_script(TERRAIN_CHUNK_SCRIPT)
			_chunk_root.add_child(chunk_node)
			var chunk: Node = chunk_node as Node
			if chunk != null:
				chunk.setup(Vector2i(cx, cz), min_x, max_x, min_z, max_z, _material, mini(maxi(chunk_mesh_border_vertices, 1), 2))
				chunk.set_debug_rebuild_logging(debug_chunk_rebuild_logging)
				chunk.set_debug_border(debug_draw_chunk_borders, _chunk_debug_color(Vector2i(cx, cz)), debug_highlight_problem_borders)
				_chunks[Vector2i(cx, cz)] = chunk

func _rebuild_chunks_intersecting_rect(min_x: int, max_x: int, min_z: int, max_z: int) -> void:
	_ensure_layer_data(_active_world_layer)
	_ensure_chunk_layout()
	_last_rebuilt_chunks.clear()
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var water: PackedFloat32Array = _layer_water[_active_world_layer]
	var snow: PackedFloat32Array = _layer_snow[_active_world_layer]
	var dynamic_border_padding: int = _compute_dynamic_border_padding(heights, min_x, max_x, min_z, max_z)
	var base_neighbor_ring: int = 1
	var neighbor_ring: int = base_neighbor_ring
	if dynamic_border_padding >= 5:
		neighbor_ring += maxi(steep_slope_extra_neighbor_ring, 1)
	var core_min_chunk_x: int = maxi(0, _vertex_to_chunk_coord(min_x))
	var core_max_chunk_x: int = mini(_chunk_count_x - 1, _vertex_to_chunk_coord(max_x))
	var core_min_chunk_z: int = maxi(0, _vertex_to_chunk_coord(min_z))
	var core_max_chunk_z: int = mini(_chunk_count_z - 1, _vertex_to_chunk_coord(max_z))
	var min_chunk_x: int = maxi(0, core_min_chunk_x - neighbor_ring)
	var max_chunk_x: int = mini(_chunk_count_x - 1, core_max_chunk_x + neighbor_ring)
	var min_chunk_z: int = maxi(0, core_min_chunk_z - neighbor_ring)
	var max_chunk_z: int = mini(_chunk_count_z - 1, core_max_chunk_z + neighbor_ring)
	if debug_chunk_rebuild_logging:
		print("Chunk rebuild ring=", neighbor_ring, " | dynamic border padding=", dynamic_border_padding, " | core=", Vector2i(core_min_chunk_x, core_min_chunk_z), "->", Vector2i(core_max_chunk_x, core_max_chunk_z))
	for cz in range(min_chunk_z, max_chunk_z + 1):
		for cx in range(min_chunk_x, max_chunk_x + 1):
			var key := Vector2i(cx, cz)
			var chunk: Node = _chunks.get(key, null) as Node
			if chunk == null:
				continue
			var is_neighbor_only: bool = cx < core_min_chunk_x or cx > core_max_chunk_x or cz < core_min_chunk_z or cz > core_max_chunk_z
			chunk.set_debug_rebuild_logging(debug_chunk_rebuild_logging)
			chunk.rebuild_region_from_source(
				heights,
				paint,
				water,
				snow,
				terrain_resolution,
				terrain_size,
				min_terrain_height,
				max_terrain_height,
				min_x,
				max_x,
				min_z,
				max_z,
				maxi(dynamic_border_padding, 4),
				is_neighbor_only
			)
			chunk.set_debug_border(debug_draw_chunk_borders, _chunk_debug_color(key), debug_highlight_problem_borders)
			if not _last_rebuilt_chunks.has(key):
				_last_rebuilt_chunks.append(key)

	# Final border-normal synchronization pass across all chunks touched by this stroke.
	_post_rebuild_global_normal_pass(_last_rebuilt_chunks, heights, paint, water, snow, min_x, max_x, min_z, max_z, dynamic_border_padding)

func set_full_rebuild_mode(_enabled: bool) -> void:
	_full_rebuild_mode = _enabled

func get_full_rebuild_mode() -> bool:
	return _full_rebuild_mode

func _vertex_to_chunk_coord(vertex_index: int) -> int:
	if _chunk_vertex_span <= 0:
		return 0
	return int(floor(float(vertex_index) / float(_chunk_vertex_span)))

func _compute_dynamic_border_padding(heights: PackedFloat32Array, min_x: int, max_x: int, min_z: int, max_z: int) -> int:
	var stride: int = terrain_resolution + 1
	var sample_min_x: int = maxi(1, min_x - 2)
	var sample_max_x: int = mini(terrain_resolution - 1, max_x + 2)
	var sample_min_z: int = maxi(1, min_z - 2)
	var sample_max_z: int = mini(terrain_resolution - 1, max_z + 2)
	var max_slope: float = 0.0
	for z in range(sample_min_z, sample_max_z + 1):
		for x in range(sample_min_x, sample_max_x + 1):
			var h: float = heights[_idx(x, z, stride)]
			var dx: float = absf(heights[_idx(x + 1, z, stride)] - h)
			var dz: float = absf(heights[_idx(x, z + 1, stride)] - h)
			max_slope = maxf(max_slope, maxf(dx, dz))
	if max_slope >= steep_slope_threshold * 1.45:
		return 6
	if max_slope >= steep_slope_threshold:
		return 5
	return 4

func set_debug_draw_chunk_borders(enabled: bool) -> void:
	debug_draw_chunk_borders = enabled
	for key_variant in _chunks.keys():
		var key: Vector2i = key_variant as Vector2i
		var chunk: Node = _chunks[key] as Node
		if chunk != null:
			chunk.set_debug_border(debug_draw_chunk_borders, _chunk_debug_color(key), debug_highlight_problem_borders)

func set_debug_draw_chunk_borders_red(enabled: bool) -> void:
	debug_draw_chunk_borders_red = enabled
	if debug_draw_chunk_borders:
		set_debug_draw_chunk_borders(true)

func set_debug_highlight_problem_borders(enabled: bool) -> void:
	debug_highlight_problem_borders = enabled
	if debug_draw_chunk_borders:
		set_debug_draw_chunk_borders(true)

func _chunk_debug_color(coord: Vector2i) -> Color:
	if debug_highlight_problem_borders:
		# Bright yellow with full saturation — maximally visible in top-down ortho.
		return Color(1.0, 0.95, 0.0, 1.0)
	if debug_draw_chunk_borders_red:
		return Color(1.0, 0.05, 0.05, 0.95)
	var hue_seed: float = float(posmod(coord.x * 53 + coord.y * 97, 360)) / 360.0
	return Color.from_hsv(hue_seed, 0.75, 1.0, 0.85)

func _post_rebuild_global_normal_pass(rebuilt_keys: Array[Vector2i], heights: PackedFloat32Array, paint: PackedFloat32Array, water: PackedFloat32Array, snow: PackedFloat32Array, min_x: int, max_x: int, min_z: int, max_z: int, border_padding: int) -> void:
	for key in rebuilt_keys:
		var chunk: Node = _chunks.get(key, null) as Node
		if chunk == null:
			continue
		chunk.rebuild_region_from_source(
			heights,
			paint,
			water,
			snow,
			terrain_resolution,
			terrain_size,
			min_terrain_height,
			max_terrain_height,
			min_x,
			max_x,
			min_z,
			max_z,
			maxi(border_padding, 4),
			true
		)

func _idx(x: int, z: int, stride: int) -> int:
	return z * stride + x
