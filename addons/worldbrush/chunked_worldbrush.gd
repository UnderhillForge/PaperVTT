extends Node3D
class_name ChunkedWorldBrush

const TERRAIN_CHUNK_SCRIPT: Script = preload("res://addons/worldbrush/terrain_chunk.gd")
const TERRAIN_BASE_ALBEDO_PATH: String = "res://assets/world/textures/ground/grass_tile.png"
const TERRAIN_BASE_MATERIAL_PATH: String = "res://assets/world/materials/terrain_base_material.tres"
const TERRAIN_BLEND_SHADER_PATH: String = "res://addons/worldbrush/shaders/chunked_terrain_texture_blend.gdshader"
const MAX_TEXTURE_LAYERS: int = 24
const CONTROL_MAP_COUNT: int = 6
const TOOL_TEXTURE_SUBTRACT: String = "texture_subtract"

@export var terrain_size: float = 256.0
@export var terrain_resolution: int = 96
@export var max_terrain_height: float = 38.0
@export var min_terrain_height: float = -14.0
@export var seed_initial_terrain: bool = true
@export var auto_test_snow: bool = true
@export var terrain_texture_uv_repeat: float = 8.0
# 64m chunks align with the project's 256 px/m texel-density baseline.
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
var _layer_paint_g: Dictionary = {}
var _layer_paint_b: Dictionary = {}
var _layer_paint_a: Dictionary = {}
var _layer_texture_weights: Dictionary = {}
var _layer_water: Dictionary = {}
var _layer_snow: Dictionary = {}

var _chunk_root: Node3D = null
var _chunks: Dictionary = {}
var _material: Material = null
var _base_albedo_texture: Texture2D = null
var _base_roughness: float = 0.92
var _texture_slot_ids: PackedStringArray = PackedStringArray([])
var _texture_slot_albedo: Array = []
var _texture_slot_normal: Array = []
var _texture_slot_roughness: Array = []
var _texture_slot_uv_scales: PackedFloat32Array = PackedFloat32Array()
var _texture_slot_exposures: PackedFloat32Array = PackedFloat32Array()
var _texture_array_albedo: Texture2DArray = null
var _texture_array_normal: Texture2DArray = null
var _texture_array_roughness: Texture2DArray = null
var _fallback_flat_normal_texture: Texture2D = null
var _fallback_white_texture: Texture2D = null
var _control_map_images: Array = []
var _control_map_textures: Array = []
var _control_map_resolution: int = 0

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
var _texture_stroke_active: bool = false
var _texture_stroke_perf_mode: bool = true
var _texture_stroke_dirty_valid: bool = false
var _texture_stroke_min_x: int = 0
var _texture_stroke_max_x: int = 0
var _texture_stroke_min_z: int = 0
var _texture_stroke_max_z: int = 0
var _texture_stroke_last_flush_msec: int = 0

const TEXTURE_STROKE_FLUSH_INTERVAL_SEC: float = 0.045
const TEXTURE_STROKE_FLUSH_INTERVAL_PERF_SEC: float = 0.085

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
	_layer_paint_g.clear()
	_layer_paint_b.clear()
	_layer_paint_a.clear()
	_layer_texture_weights.clear()
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
			"paint_g": _layer_paint_g.get(layer, PackedFloat32Array()),
			"paint_b": _layer_paint_b.get(layer, PackedFloat32Array()),
			"paint_a": _layer_paint_a.get(layer, PackedFloat32Array()),
			"texture_layers": _layer_texture_weights.get(layer, []),
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
	_layer_paint_g.clear()
	_layer_paint_b.clear()
	_layer_paint_a.clear()
	_layer_texture_weights.clear()
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
		_layer_paint_g[layer_id] = layer_data.get("paint_g", PackedFloat32Array())
		_layer_paint_b[layer_id] = layer_data.get("paint_b", PackedFloat32Array())
		_layer_paint_a[layer_id] = layer_data.get("paint_a", PackedFloat32Array())
		_layer_texture_weights[layer_id] = layer_data.get("texture_layers", [])
		_layer_water[layer_id] = layer_data.get("water", PackedFloat32Array())
		_layer_snow[layer_id] = layer_data.get("snow", PackedFloat32Array())
		_ensure_texture_weight_layers(layer_id)
		_sync_legacy_paint_channels_from_layers(layer_id)
		_ensure_paint_channels_for_layer(layer_id)

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

func apply_brush(tool_name: String, world_pos: Vector3, brush_size: float, brush_strength: float, flatten_height: float = 0.0, _cliff_mode: bool = false, _overhang_amount: float = 0.3, brush_softness: float = 0.42, brush_mode: String = "smooth", texture_slot_index: int = 0) -> void:
	if tool_name == "textureerase":
		tool_name = TOOL_TEXTURE_SUBTRACT
	_ensure_layer_data(_active_world_layer)
	_ensure_texture_weight_layers(_active_world_layer)
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var paint_g: PackedFloat32Array = _layer_paint_g[_active_world_layer]
	var paint_b: PackedFloat32Array = _layer_paint_b[_active_world_layer]
	var paint_a: PackedFloat32Array = _layer_paint_a[_active_world_layer]
	var texture_layers: Array = _layer_texture_weights[_active_world_layer] as Array
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
	var is_texture_tool: bool = tool_name in ["texturepaint", TOOL_TEXTURE_SUBTRACT]
	var max_height_delta: float = 0.0
	var updated_vertices: int = 0

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
			var before_paint: float = paint[idxv]
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
				"texturepaint":
					var texture_delta: float = brush_strength * w * 1.15
					if texture_slot_index >= 0 and texture_slot_index < MAX_TEXTURE_LAYERS:
						var layer_arr: PackedFloat32Array = texture_layers[texture_slot_index] as PackedFloat32Array
						layer_arr[idxv] = clampf(layer_arr[idxv] + texture_delta, 0.0, 1.0)
						texture_layers[texture_slot_index] = layer_arr
						var total_weight: float = 0.0
						for li in range(MAX_TEXTURE_LAYERS):
							total_weight += float((texture_layers[li] as PackedFloat32Array)[idxv])
						if total_weight > 1.0:
							var inv_total: float = 1.0 / total_weight
							for li in range(MAX_TEXTURE_LAYERS):
								var norm_arr: PackedFloat32Array = texture_layers[li] as PackedFloat32Array
								norm_arr[idxv] = clampf(norm_arr[idxv] * inv_total, 0.0, 1.0)
								texture_layers[li] = norm_arr
				TOOL_TEXTURE_SUBTRACT:
					var erase_delta: float = brush_strength * w * 0.7
					for li in range(MAX_TEXTURE_LAYERS):
						var erase_arr: PackedFloat32Array = texture_layers[li] as PackedFloat32Array
						erase_arr[idxv] = clampf(erase_arr[idxv] - erase_delta, 0.0, 1.0)
						texture_layers[li] = erase_arr
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
			if is_texture_tool and absf(paint[idxv] - before_paint) > 0.00001:
				updated_vertices += 1

	if brush_mode == "smooth" and smooth_mode_post_smooth_enabled and tool_name in ["raise", "lower"]:
		_apply_local_relax_pass(heights, min_x, max_x, min_z, max_z, influence_radius, local_center)

	_layer_heights[_active_world_layer] = heights
	_layer_texture_weights[_active_world_layer] = texture_layers
	_layer_paint[_active_world_layer] = paint
	_layer_paint_g[_active_world_layer] = paint_g
	_layer_paint_b[_active_world_layer] = paint_b
	_layer_paint_a[_active_world_layer] = paint_a
	_layer_water[_active_world_layer] = water
	_layer_snow[_active_world_layer] = snow
	_sync_legacy_paint_channels_from_layers(_active_world_layer)
	if is_texture_tool:
		_update_control_maps_from_active_layer()
	var force_full_for_raise: bool = tool_name == "raise" and max_height_delta >= maxf(high_raise_force_full_rebuild_delta, 0.1)
	if _full_rebuild_mode:
		rebuild_mesh()
		if is_texture_tool:
			print("Texture Paint - Affected chunks: ", _last_rebuilt_chunks.size(), " | Vertices updated: ", updated_vertices)
		return
	if is_texture_tool:
		if _texture_stroke_active:
			_accumulate_texture_stroke_dirty_rect(min_x, max_x, min_z, max_z)
			var now_msec: int = Time.get_ticks_msec()
			var elapsed_sec: float = float(maxi(now_msec - _texture_stroke_last_flush_msec, 0)) / 1000.0
			var flush_interval: float = TEXTURE_STROKE_FLUSH_INTERVAL_PERF_SEC if _texture_stroke_perf_mode else TEXTURE_STROKE_FLUSH_INTERVAL_SEC
			if elapsed_sec >= flush_interval:
				_flush_texture_stroke_dirty_rect(false)
				_texture_stroke_last_flush_msec = now_msec
		else:
			_rebuild_chunks_intersecting_rect(min_x, max_x, min_z, max_z, true)
		if debug_chunk_rebuild_logging:
			print("Texture Paint - Affected chunks: ", _last_rebuilt_chunks.size(), " | Vertices updated: ", updated_vertices)
		return
	if force_full_for_raise:
		if debug_chunk_rebuild_logging:
			print("Chunked terrain full rebuild triggered by high raise delta: ", max_height_delta)
		rebuild_mesh()
		return
	_rebuild_chunks_intersecting_rect(min_x, max_x, min_z, max_z)

func begin_texture_stroke(perf_mode: bool = true, _brush_radius: float = 8.0) -> void:
	_texture_stroke_active = true
	_texture_stroke_perf_mode = perf_mode
	_texture_stroke_dirty_valid = false
	_texture_stroke_last_flush_msec = Time.get_ticks_msec()

func apply_texture_brush(world_pos: Vector3, albedo: Texture2D = null, normal: Texture2D = null, roughness: Texture2D = null, _height: Texture2D = null, _ao: Texture2D = null, brush_size: float = 8.0, brush_strength: float = 0.3, tile_size: float = 4.0, density: float = 0.75, softness: float = 0.7, _coverage: float = 0.75, _offset: Vector2 = Vector2.ZERO, _rot: float = 0.0, scale: float = 1.0, exposure: float = 1.0, _shape: String = "circle", _variation: float = 0.0, _seed: float = 0.0, _variant: int = 0, brush_mode: String = "smooth", texture_id: String = "") -> void:
	var tex_label: String = "<none>"
	if albedo != null:
		tex_label = albedo.resource_path if albedo.resource_path != "" else albedo.resource_name
	var slot_idx: int = _ensure_texture_slot(texture_id, albedo, normal, roughness, tile_size, scale, exposure)
	if slot_idx < 0:
		return
	if debug_chunk_rebuild_logging:
		print("Painting with texture: ", tex_label, " | Brush radius: ", brush_size)
	apply_brush("texturepaint", world_pos, brush_size, maxf(brush_strength * density, 0.01), 0.0, false, 0.3, softness, brush_mode, slot_idx)

func apply_texture_erase_brush(world_pos: Vector3, brush_size: float = 8.0, brush_strength: float = 0.3, softness: float = 0.7, brush_mode: String = "smooth") -> void:
	apply_brush(TOOL_TEXTURE_SUBTRACT, world_pos, brush_size, brush_strength, 0.0, false, 0.3, softness, brush_mode)

func end_texture_stroke() -> void:
	if _texture_stroke_active:
		_flush_texture_stroke_dirty_rect(true)
	_texture_stroke_active = false
	_texture_stroke_dirty_valid = false

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
	_ensure_terrain_material()
	_ensure_chunk_layout()
	_last_rebuilt_chunks.clear()
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var paint_g: PackedFloat32Array = _layer_paint_g[_active_world_layer]
	var paint_b: PackedFloat32Array = _layer_paint_b[_active_world_layer]
	var paint_a: PackedFloat32Array = _layer_paint_a[_active_world_layer]
	var water: PackedFloat32Array = _layer_water[_active_world_layer]
	var snow: PackedFloat32Array = _layer_snow[_active_world_layer]
	for key_variant in _chunks.keys():
		var key: Vector2i = key_variant as Vector2i
		var chunk: Node = _chunks[key] as Node
		if chunk != null:
			if chunk.has_method("set_material"):
				chunk.call("set_material", _material)
			chunk.set_debug_rebuild_logging(debug_chunk_rebuild_logging)
			chunk.rebuild_mesh(heights, paint, paint_g, paint_b, paint_a, water, snow, terrain_resolution, terrain_size, min_terrain_height, max_terrain_height)
			chunk.set_debug_border(debug_draw_chunk_borders, _chunk_debug_color(key), debug_highlight_problem_borders)
			_last_rebuilt_chunks.append(key)
	_update_control_maps_from_active_layer()

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
	_ensure_texture_slot_storage()
	_ensure_texture_library_fallbacks()
	var base_material: StandardMaterial3D = load(TERRAIN_BASE_MATERIAL_PATH) as StandardMaterial3D
	_base_albedo_texture = base_material.albedo_texture if base_material != null else null
	if _base_albedo_texture == null:
		_base_albedo_texture = load(TERRAIN_BASE_ALBEDO_PATH) as Texture2D
	_base_roughness = base_material.roughness if base_material != null else 0.92
	var blend_shader: Shader = load(TERRAIN_BLEND_SHADER_PATH) as Shader
	if _base_albedo_texture == null:
		push_warning("Chunked terrain base albedo missing; using neutral fallback material.")
		_material = _build_fallback_terrain_material()
		return
	if blend_shader == null:
		push_warning("Chunked terrain blend shader missing; falling back to base material rendering.")
		_material = _build_fallback_terrain_material()
		return
	var shader_material := ShaderMaterial.new()
	shader_material.shader = blend_shader
	var repeat_scale: float = maxf(terrain_texture_uv_repeat, 1.0)
	shader_material.set_shader_parameter("base_albedo_tex", _base_albedo_texture)
	shader_material.set_shader_parameter("base_uv_scale", repeat_scale)
	shader_material.set_shader_parameter("base_roughness", _base_roughness)
	shader_material.set_shader_parameter("terrain_world_size", terrain_size)
	_material = shader_material
	_ensure_control_map_textures()
	for i in range(CONTROL_MAP_COUNT):
		(shader_material as ShaderMaterial).set_shader_parameter("control_map_%d" % i, _control_map_textures[i])
	for i in range(MAX_TEXTURE_LAYERS):
		_texture_slot_uv_scales[i] = repeat_scale
		_texture_slot_exposures[i] = 1.0
	_sync_texture_slots_to_material()
	_sync_control_maps_to_material()

func _build_fallback_terrain_material() -> StandardMaterial3D:
	var fallback := StandardMaterial3D.new()
	fallback.name = "ChunkedTerrainFallback"
	fallback.albedo_texture = _base_albedo_texture
	fallback.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	fallback.vertex_color_use_as_albedo = false
	fallback.uv1_scale = Vector3(maxf(terrain_texture_uv_repeat, 1.0), maxf(terrain_texture_uv_repeat, 1.0), 1.0)
	fallback.roughness = _base_roughness
	fallback.metallic = 0.0
	fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	fallback.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return fallback

func _apply_texture_set_to_material(albedo: Texture2D, normal: Texture2D, roughness: Texture2D, tile_size: float, scale: float, exposure: float) -> void:
	_ensure_texture_slot("", albedo, normal, roughness, tile_size, scale, exposure)

func _ensure_texture_slot_storage() -> void:
	if _texture_slot_ids.size() == MAX_TEXTURE_LAYERS:
		return
	_texture_slot_ids = PackedStringArray()
	_texture_slot_albedo.clear()
	_texture_slot_normal.clear()
	_texture_slot_roughness.clear()
	_texture_slot_uv_scales = PackedFloat32Array()
	_texture_slot_exposures = PackedFloat32Array()
	_texture_slot_uv_scales.resize(MAX_TEXTURE_LAYERS)
	_texture_slot_exposures.resize(MAX_TEXTURE_LAYERS)
	for i in range(MAX_TEXTURE_LAYERS):
		_texture_slot_ids.append("")
		_texture_slot_albedo.append(null)
		_texture_slot_normal.append(null)
		_texture_slot_roughness.append(null)
		_texture_slot_uv_scales[i] = maxf(terrain_texture_uv_repeat, 1.0)
		_texture_slot_exposures[i] = 1.0

func _ensure_control_map_textures() -> void:
	var target_size: int = terrain_resolution + 1
	if _control_map_resolution == target_size and _control_map_textures.size() == CONTROL_MAP_COUNT:
		return
	_control_map_images.clear()
	_control_map_textures.clear()
	_control_map_resolution = target_size
	for _i in range(CONTROL_MAP_COUNT):
		var img := Image.create(target_size, target_size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.0, 0.0, 0.0, 0.0))
		_control_map_images.append(img)
		_control_map_textures.append(ImageTexture.create_from_image(img))

func _sync_control_maps_to_material() -> void:
	if _material == null or not (_material is ShaderMaterial):
		return
	_ensure_control_map_textures()
	var shader_material: ShaderMaterial = _material as ShaderMaterial
	for i in range(CONTROL_MAP_COUNT):
		shader_material.set_shader_parameter("control_map_%d" % i, _control_map_textures[i])
	shader_material.set_shader_parameter("terrain_world_size", terrain_size)

func _ensure_texture_slot(texture_id: String, albedo: Texture2D, normal: Texture2D, roughness: Texture2D, tile_size: float, scale: float, exposure: float) -> int:
	_ensure_texture_slot_storage()
	var resolved_id: String = texture_id.strip_edges()
	if resolved_id == "" and albedo != null:
		resolved_id = albedo.resource_path if albedo.resource_path != "" else albedo.resource_name
	if resolved_id == "":
		resolved_id = "__base__"
	for i in range(MAX_TEXTURE_LAYERS):
		if _texture_slot_ids[i] == resolved_id:
			_update_texture_slot(i, albedo, normal, roughness, tile_size, scale, exposure)
			return i
	for i in range(MAX_TEXTURE_LAYERS):
		if _texture_slot_ids[i] == "":
			_texture_slot_ids[i] = resolved_id
			_update_texture_slot(i, albedo, normal, roughness, tile_size, scale, exposure)
			return i
	push_warning("Texture Paint slots full (max %d)." % MAX_TEXTURE_LAYERS)
	return -1

func _update_texture_slot(slot_idx: int, albedo: Texture2D, normal: Texture2D, roughness: Texture2D, tile_size: float, scale: float, exposure: float) -> void:
	if slot_idx < 0 or slot_idx >= MAX_TEXTURE_LAYERS:
		return
	var resolved_albedo: Texture2D = albedo if albedo != null else _fallback_white_texture
	var resolved_normal: Texture2D = normal if normal != null else _fallback_flat_normal_texture
	var resolved_roughness: Texture2D = roughness if roughness != null else _fallback_white_texture
	var resolved_uv_scale: float = _tile_size_to_uv_scale(tile_size, scale)
	var resolved_exposure: float = clampf(exposure, 0.25, 2.0)
	if _texture_slot_albedo[slot_idx] == resolved_albedo and _texture_slot_normal[slot_idx] == resolved_normal and _texture_slot_roughness[slot_idx] == resolved_roughness and is_equal_approx(_texture_slot_uv_scales[slot_idx], resolved_uv_scale) and is_equal_approx(_texture_slot_exposures[slot_idx], resolved_exposure):
		return
	_texture_slot_albedo[slot_idx] = resolved_albedo
	_texture_slot_normal[slot_idx] = resolved_normal
	_texture_slot_roughness[slot_idx] = resolved_roughness
	_texture_slot_uv_scales[slot_idx] = resolved_uv_scale
	_texture_slot_exposures[slot_idx] = resolved_exposure
	_sync_texture_slots_to_material()

func _sync_texture_slots_to_material() -> void:
	if _material == null or not (_material is ShaderMaterial):
		return
	var shader_material: ShaderMaterial = _material as ShaderMaterial
	_sync_texture_arrays_to_material()
	shader_material.set_shader_parameter("paint_albedo_array", _texture_array_albedo)
	shader_material.set_shader_parameter("paint_normal_array", _texture_array_normal)
	shader_material.set_shader_parameter("paint_roughness_array", _texture_array_roughness)
	shader_material.set_shader_parameter("paint_uv_scale", _texture_slot_uv_scales)
	shader_material.set_shader_parameter("paint_exposure", _texture_slot_exposures)

func _ensure_texture_library_fallbacks() -> void:
	if _fallback_flat_normal_texture == null:
		var normal_image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		normal_image.fill(Color(0.5, 0.5, 1.0, 1.0))
		_fallback_flat_normal_texture = ImageTexture.create_from_image(normal_image)
	if _fallback_white_texture == null:
		var white_image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
		white_image.fill(Color(1.0, 1.0, 1.0, 1.0))
		_fallback_white_texture = ImageTexture.create_from_image(white_image)

func _sync_texture_arrays_to_material() -> void:
	_texture_array_albedo = _build_texture_array(_texture_slot_albedo, _fallback_white_texture, true)
	_texture_array_normal = _build_texture_array(_texture_slot_normal, _fallback_flat_normal_texture, false)
	_texture_array_roughness = _build_texture_array(_texture_slot_roughness, _fallback_white_texture, false)

func _build_texture_array(source_textures: Array, fallback_texture: Texture2D, treat_as_color: bool) -> Texture2DArray:
	var images: Array[Image] = []
	images.resize(MAX_TEXTURE_LAYERS)
	var target_size: Vector2i = Vector2i.ZERO
	for i in range(MAX_TEXTURE_LAYERS):
		var texture: Texture2D = source_textures[i] as Texture2D if i < source_textures.size() else null
		if texture == null:
			texture = fallback_texture
		if texture == null:
			return null
		var image: Image = texture.get_image()
		if image == null or image.is_empty():
			return null
		if target_size == Vector2i.ZERO:
			target_size = image.get_size()
		else:
			target_size.x = maxi(target_size.x, image.get_width())
			target_size.y = maxi(target_size.y, image.get_height())
	for i in range(MAX_TEXTURE_LAYERS):
		var texture: Texture2D = source_textures[i] as Texture2D if i < source_textures.size() else null
		if texture == null:
			texture = fallback_texture
		if texture == null:
			return null
		var image: Image = texture.get_image()
		if image == null or image.is_empty():
			return null
		if image.get_width() != target_size.x or image.get_height() != target_size.y:
			image.resize(target_size.x, target_size.y, Image.INTERPOLATE_BILINEAR)
		if image.get_format() != Image.FORMAT_RGBA8:
			image.convert(Image.FORMAT_RGBA8)
		image.generate_mipmaps()
		images[i] = image
	var texture_array := Texture2DArray.new()
	var result: Error = texture_array.create_from_images(images)
	if result != OK:
		push_warning("Terrain texture array build failed with error %s" % result)
		return null
	return texture_array

func _tile_size_to_uv_scale(tile_size: float, scale: float) -> float:
	var effective_tile_meters: float = maxf(tile_size * maxf(scale, 0.1), 0.25)
	return clampf(terrain_size / effective_tile_meters, 1.0, 1024.0)

func _ensure_layer_data(layer: int) -> void:
	if _layer_heights.has(layer):
		_ensure_texture_weight_layers(layer)
		_sync_legacy_paint_channels_from_layers(layer)
		_ensure_paint_channels_for_layer(layer)
		return
	var count: int = (terrain_resolution + 1) * (terrain_resolution + 1)
	var heights := PackedFloat32Array()
	var paint := PackedFloat32Array()
	var paint_g := PackedFloat32Array()
	var paint_b := PackedFloat32Array()
	var paint_a := PackedFloat32Array()
	var water := PackedFloat32Array()
	var snow := PackedFloat32Array()
	heights.resize(count)
	paint.resize(count)
	paint_g.resize(count)
	paint_b.resize(count)
	paint_a.resize(count)
	water.resize(count)
	snow.resize(count)
	for i in range(count):
		heights[i] = 0.0
		paint[i] = 0.0
		paint_g[i] = 0.0
		paint_b[i] = 0.0
		paint_a[i] = 0.0
		water[i] = 0.0
		snow[i] = 0.0
	if seed_initial_terrain:
		_seed_height_data(heights)
	_layer_heights[layer] = heights
	_layer_paint[layer] = paint
	_layer_paint_g[layer] = paint_g
	_layer_paint_b[layer] = paint_b
	_layer_paint_a[layer] = paint_a
	_layer_texture_weights[layer] = []
	_ensure_texture_weight_layers(layer)
	_sync_legacy_paint_channels_from_layers(layer)
	_layer_water[layer] = water
	_layer_snow[layer] = snow

func _ensure_texture_weight_layers(layer: int) -> void:
	var count: int = (terrain_resolution + 1) * (terrain_resolution + 1)
	var layers: Array = _layer_texture_weights.get(layer, []) as Array
	if layers.size() != MAX_TEXTURE_LAYERS:
		var rebuilt_layers: Array = []
		rebuilt_layers.resize(MAX_TEXTURE_LAYERS)
		for i in range(MAX_TEXTURE_LAYERS):
			var arr := PackedFloat32Array()
			arr.resize(count)
			if i < layers.size() and layers[i] is PackedFloat32Array:
				var src: PackedFloat32Array = layers[i] as PackedFloat32Array
				var copy_size: int = mini(src.size(), count)
				for j in range(copy_size):
					arr[j] = clampf(src[j], 0.0, 1.0)
			rebuilt_layers[i] = arr
		layers = rebuilt_layers
	_layer_texture_weights[layer] = layers

func _sync_legacy_paint_channels_from_layers(layer: int) -> void:
	_ensure_paint_channels_for_layer(layer)
	_ensure_texture_weight_layers(layer)
	var layers: Array = _layer_texture_weights[layer] as Array
	var legacy_r: PackedFloat32Array = _layer_paint[layer]
	var legacy_g: PackedFloat32Array = _layer_paint_g[layer]
	var legacy_b: PackedFloat32Array = _layer_paint_b[layer]
	var legacy_a: PackedFloat32Array = _layer_paint_a[layer]
	var l0: PackedFloat32Array = layers[0] as PackedFloat32Array
	var l1: PackedFloat32Array = layers[1] as PackedFloat32Array
	var l2: PackedFloat32Array = layers[2] as PackedFloat32Array
	var l3: PackedFloat32Array = layers[3] as PackedFloat32Array
	for i in range(legacy_r.size()):
		legacy_r[i] = l0[i]
		legacy_g[i] = l1[i]
		legacy_b[i] = l2[i]
		legacy_a[i] = l3[i]
	_layer_paint[layer] = legacy_r
	_layer_paint_g[layer] = legacy_g
	_layer_paint_b[layer] = legacy_b
	_layer_paint_a[layer] = legacy_a

func _update_control_maps_from_active_layer() -> void:
	_ensure_texture_weight_layers(_active_world_layer)
	_ensure_control_map_textures()
	var stride: int = terrain_resolution + 1
	var layer_weights: Array = _layer_texture_weights[_active_world_layer] as Array
	for z in range(stride):
		for x in range(stride):
			var idxv: int = _idx(x, z, stride)
			for cm in range(CONTROL_MAP_COUNT):
				var base_idx: int = cm * 4
				var r: float = float((layer_weights[base_idx + 0] as PackedFloat32Array)[idxv])
				var g: float = float((layer_weights[base_idx + 1] as PackedFloat32Array)[idxv])
				var b: float = float((layer_weights[base_idx + 2] as PackedFloat32Array)[idxv])
				var a: float = float((layer_weights[base_idx + 3] as PackedFloat32Array)[idxv])
				(_control_map_images[cm] as Image).set_pixel(x, z, Color(r, g, b, a))
	for cm in range(CONTROL_MAP_COUNT):
		(_control_map_textures[cm] as ImageTexture).update(_control_map_images[cm] as Image)
	_sync_control_maps_to_material()

func _ensure_paint_channels_for_layer(layer: int) -> void:
	var base_paint: PackedFloat32Array = _layer_paint.get(layer, PackedFloat32Array())
	if not _layer_paint_g.has(layer) or (_layer_paint_g[layer] as PackedFloat32Array).size() != base_paint.size():
		var chan_g := PackedFloat32Array()
		chan_g.resize(base_paint.size())
		_layer_paint_g[layer] = chan_g
	if not _layer_paint_b.has(layer) or (_layer_paint_b[layer] as PackedFloat32Array).size() != base_paint.size():
		var chan_b := PackedFloat32Array()
		chan_b.resize(base_paint.size())
		_layer_paint_b[layer] = chan_b
	if not _layer_paint_a.has(layer) or (_layer_paint_a[layer] as PackedFloat32Array).size() != base_paint.size():
		var chan_a := PackedFloat32Array()
		chan_a.resize(base_paint.size())
		_layer_paint_a[layer] = chan_a

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

func _rebuild_chunks_intersecting_rect(min_x: int, max_x: int, min_z: int, max_z: int, run_global_normal_pass: bool = true) -> void:
	_ensure_layer_data(_active_world_layer)
	_ensure_terrain_material()
	_ensure_chunk_layout()
	_last_rebuilt_chunks.clear()
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var paint_g: PackedFloat32Array = _layer_paint_g[_active_world_layer]
	var paint_b: PackedFloat32Array = _layer_paint_b[_active_world_layer]
	var paint_a: PackedFloat32Array = _layer_paint_a[_active_world_layer]
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
			if chunk.has_method("set_material"):
				chunk.call("set_material", _material)
			var is_neighbor_only: bool = cx < core_min_chunk_x or cx > core_max_chunk_x or cz < core_min_chunk_z or cz > core_max_chunk_z
			chunk.set_debug_rebuild_logging(debug_chunk_rebuild_logging)
			chunk.rebuild_region_from_source(
				heights,
				paint,
				paint_g,
				paint_b,
				paint_a,
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
	if run_global_normal_pass:
		_post_rebuild_global_normal_pass(_last_rebuilt_chunks, heights, paint, paint_g, paint_b, paint_a, water, snow, min_x, max_x, min_z, max_z, dynamic_border_padding)

func _accumulate_texture_stroke_dirty_rect(min_x: int, max_x: int, min_z: int, max_z: int) -> void:
	if not _texture_stroke_dirty_valid:
		_texture_stroke_min_x = min_x
		_texture_stroke_max_x = max_x
		_texture_stroke_min_z = min_z
		_texture_stroke_max_z = max_z
		_texture_stroke_dirty_valid = true
		return
	_texture_stroke_min_x = mini(_texture_stroke_min_x, min_x)
	_texture_stroke_max_x = maxi(_texture_stroke_max_x, max_x)
	_texture_stroke_min_z = mini(_texture_stroke_min_z, min_z)
	_texture_stroke_max_z = maxi(_texture_stroke_max_z, max_z)

func _flush_texture_stroke_dirty_rect(include_global_normal_pass: bool) -> void:
	if not _texture_stroke_dirty_valid:
		return
	_rebuild_chunks_intersecting_rect(_texture_stroke_min_x, _texture_stroke_max_x, _texture_stroke_min_z, _texture_stroke_max_z, include_global_normal_pass)
	_texture_stroke_dirty_valid = false

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

func _post_rebuild_global_normal_pass(rebuilt_keys: Array[Vector2i], heights: PackedFloat32Array, paint: PackedFloat32Array, paint_g: PackedFloat32Array, paint_b: PackedFloat32Array, paint_a: PackedFloat32Array, water: PackedFloat32Array, snow: PackedFloat32Array, min_x: int, max_x: int, min_z: int, max_z: int, border_padding: int) -> void:
	for key in rebuilt_keys:
		var chunk: Node = _chunks.get(key, null) as Node
		if chunk == null:
			continue
		chunk.rebuild_region_from_source(
			heights,
			paint,
			paint_g,
			paint_b,
			paint_a,
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
