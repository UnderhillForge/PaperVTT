extends Node3D
class_name WorldBrush

@export var terrain_size: float = 256.0
@export var terrain_resolution: int = 96
@export var max_terrain_height: float = 38.0
@export var min_terrain_height: float = -14.0
@export var seed_initial_terrain: bool = true
@export var auto_test_snow: bool = true
@export var enable_dirty_rect_rebuild: bool = false
@export var dirty_rect_border: int = 5
@export var dirty_rebuild_extra_ring: int = 2
@export var dirty_edge_blend_strength: float = 0.45
@export var debug_visualize_dirty_rect: bool = false
@export var debug_rebuild_logging: bool = false
@export var adaptive_large_brush_ratio: float = 0.42
@export var dirty_region_full_rebuild_ratio: float = 0.58
@export var smooth_mode_post_smooth_enabled: bool = true
@export var smooth_mode_post_smooth_strength: float = 0.12
@export var terrain_texture_uv_repeat: float = 8.0
@export var terrain_collision_enabled: bool = true
@export_flags_3d_physics var terrain_collision_layer: int = 1
@export_flags_3d_physics var terrain_collision_mask: int = 1

const TERRAIN_BASE_ALBEDO_PATH: String = "res://assets/world/textures/ground/grass_tile.png"
const TERRAIN_BASE_MATERIAL_PATH: String = "res://assets/world/materials/terrain_base_material.tres"
const TERRAIN_BLEND_SHADER_PATH: String = "res://addons/worldbrush/shaders/chunked_terrain_texture_blend.gdshader"
const MAX_TEXTURE_LAYERS: int = 24
const CONTROL_MAP_COUNT: int = 6
const TOOL_TEXTURE_SUBTRACT: String = "texture_subtract"

var _active_world_layer: int = 0
var _mesh_instance: MeshInstance3D = null
var _terrain_collision_body: StaticBody3D = null
var _terrain_collision_shape: CollisionShape3D = null
var _material: Material = null
var _base_albedo_texture: Texture2D = null
var _base_roughness: float = 0.92
var _brush_preview: MeshInstance3D = null
var _brush_preview_enabled: bool = true
var _brush_preview_radius: float = 10.0

var _layer_heights: Dictionary = {}
var _layer_paint: Dictionary = {}
var _layer_paint_g: Dictionary = {}
var _layer_paint_b: Dictionary = {}
var _layer_paint_a: Dictionary = {}
var _layer_texture_weights: Dictionary = {}
var _layer_water: Dictionary = {}
var _layer_snow: Dictionary = {}
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

var dirty_min: Vector2i = Vector2i.ZERO
var dirty_max: Vector2i = Vector2i.ZERO
var is_dirty: bool = false
var _full_rebuild_mode: bool = false
var _surface_ready: bool = false

func _ready() -> void:
	_ensure_nodes()
	_ensure_layer_data(_active_world_layer)
	if auto_test_snow:
		apply_procedural_snow(2.8, 10.0, 0.6)
	rebuild_mesh()

func set_world_layer(layer: int) -> void:
	_active_world_layer = layer
	_ensure_layer_data(_active_world_layer)
	rebuild_mesh()


func set_full_rebuild_mode(enabled: bool) -> void:
	_full_rebuild_mode = enabled


func get_full_rebuild_mode() -> bool:
	return _full_rebuild_mode

func get_world_layer() -> int:
	return _active_world_layer

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

func apply_brush(tool_name: String, world_pos: Vector3, brush_size: float, brush_strength: float, flatten_height: float = 0.0, _cliff_mode: bool = false, _overhang_amount: float = 0.3, brush_softness: float = 0.42, brush_mode: String = "smooth", texture_slot_index: int = 0, defer_rebuild: bool = false) -> void:
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
	
	# Keep regular LMB softer for natural hills while preserving Shift sharp mode.
	var deformation_strength_multiplier: float = (0.65 + (0.35 * clampf(brush_softness, 0.0, 1.0))) if brush_mode == "smooth" else 1.0
	var is_deformation_tool: bool = tool_name in ["raise", "lower", "smooth", "flatten"]

	for z in range(min_z, max_z + 1):
		var pz: float = -half + float(z) * grid_step
		for x in range(min_x, max_x + 1):
			var px: float = -half + float(x) * grid_step
			var d: float = Vector2(px - local_center.x, pz - local_center.z).length()
			if d > influence_radius:
				continue
			var w: float = get_smooth_falloff(d, influence_radius) if brush_mode == "smooth" else get_sharp_falloff(d, influence_radius)
			var idxv: int = _idx(x, z, n)
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
	if tool_name in ["texturepaint", TOOL_TEXTURE_SUBTRACT]:
		_update_control_maps_from_active_layer()
	_mark_dirty_rect(min_x, max_x, min_z, max_z)
	if not defer_rebuild:
		_rebuild_after_stroke(radius, tool_name)


func flush_deferred_rebuild() -> void:
	if not is_dirty:
		return
	if _full_rebuild_mode or not enable_dirty_rect_rebuild:
		rebuild_mesh()
		return
	rebuild_dirty_mesh()

func begin_texture_stroke(_perf_mode: bool = true, _brush_radius: float = 8.0) -> void:
	pass

func apply_texture_brush(world_pos: Vector3, _albedo: Texture2D = null, _normal: Texture2D = null, _roughness: Texture2D = null, _height: Texture2D = null, _ao: Texture2D = null, brush_size: float = 8.0, brush_strength: float = 0.3, _tile_size: float = 4.0, density: float = 0.75, softness: float = 0.7, _coverage: float = 0.75, _offset: Vector2 = Vector2.ZERO, _rot: float = 0.0, _scale: float = 1.0, _exposure: float = 1.0, _shape: String = "circle", _variation: float = 0.0, _seed: float = 0.0, _variant: int = 0, brush_mode: String = "smooth", texture_id: String = "", defer_rebuild: bool = false) -> void:
	var tex_label: String = "<none>"
	if _albedo != null:
		tex_label = _albedo.resource_path if _albedo.resource_path != "" else _albedo.resource_name
	var slot_idx: int = _ensure_texture_slot(texture_id, _albedo, _normal, _roughness, _tile_size, _scale, _exposure)
	if slot_idx < 0:
		return
	print("Painting with texture: ", tex_label, " | Brush radius: ", brush_size)
	apply_brush("texturepaint", world_pos, brush_size, maxf(brush_strength * density, 0.01), 0.0, false, 0.3, softness, brush_mode, slot_idx, defer_rebuild)

func apply_texture_erase_brush(world_pos: Vector3, brush_size: float = 8.0, brush_strength: float = 0.3, softness: float = 0.7, brush_mode: String = "smooth") -> void:
	apply_brush(TOOL_TEXTURE_SUBTRACT, world_pos, brush_size, brush_strength, 0.0, false, 0.3, softness, brush_mode)

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

func _ensure_nodes() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "TerrainMesh"
		add_child(_mesh_instance)
	_ensure_collision_body()
	_ensure_terrain_material()
	_apply_terrain_material_to_mesh()
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


func _ensure_collision_body() -> void:
	if _terrain_collision_body == null:
		_terrain_collision_body = StaticBody3D.new()
		_terrain_collision_body.name = "TerrainCollision"
		add_child(_terrain_collision_body)
	if _terrain_collision_shape == null:
		_terrain_collision_shape = CollisionShape3D.new()
		_terrain_collision_shape.name = "TerrainCollisionShape"
		_terrain_collision_body.add_child(_terrain_collision_shape)
	_terrain_collision_body.collision_layer = terrain_collision_layer
	_terrain_collision_body.collision_mask = terrain_collision_mask
	_terrain_collision_body.visible = false


func _update_terrain_collision() -> void:
	if not terrain_collision_enabled:
		if _terrain_collision_shape != null:
			_terrain_collision_shape.shape = null
		return
	if _mesh_instance == null or _mesh_instance.mesh == null or not (_mesh_instance.mesh is ArrayMesh):
		return
	_ensure_collision_body()
	var mesh: ArrayMesh = _mesh_instance.mesh as ArrayMesh
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.size() < 3:
		_terrain_collision_shape.shape = null
		return
	var shape := ConcavePolygonShape3D.new()
	shape.data = faces
	_terrain_collision_shape.shape = shape

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
	if _base_albedo_texture == null or blend_shader == null:
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
	fallback.name = "TerrainMaterialFallback"
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


func _apply_terrain_material_to_mesh() -> void:
	if _mesh_instance == null:
		return
	_ensure_terrain_material()
	if _material == null:
		_material = _build_fallback_terrain_material()
	_mesh_instance.material_override = _material
	if _mesh_instance.mesh is ArrayMesh:
		var array_mesh: ArrayMesh = _mesh_instance.mesh as ArrayMesh
		if array_mesh.get_surface_count() > 0:
			array_mesh.surface_set_material(0, _material)
	if debug_rebuild_logging:
		print("Assigned terrain material: ", _material.resource_name if _material != null else "<null>")

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
	var effective_tile_meters: float = maxf(tile_size * maxf(scale, 0.1), 0.25)
	var resolved_uv_scale: float = clampf(terrain_size / effective_tile_meters, 1.0, 1024.0)
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


func _compute_normal(data: PackedFloat32Array, x: int, z: int, step: float) -> Vector3:
	var n: int = terrain_resolution + 1
	var xl: int = maxi(0, x - 1)
	var xr: int = mini(terrain_resolution, x + 1)
	var zd: int = maxi(0, z - 1)
	var zu: int = mini(terrain_resolution, z + 1)
	var hl: float = data[_idx(xl, z, n)]
	var hr: float = data[_idx(xr, z, n)]
	var hd: float = data[_idx(x, zd, n)]
	var hu: float = data[_idx(x, zu, n)]
	var nx: float = hl - hr
	var nz: float = hd - hu
	return Vector3(nx, 2.0 * step, nz).normalized()


func _compute_vertex_color(layer_r: float, layer_g: float, layer_b: float, layer_a: float) -> Color:
	return Color(clampf(layer_r, 0.0, 1.0), clampf(layer_g, 0.0, 1.0), clampf(layer_b, 0.0, 1.0), clampf(layer_a, 0.0, 1.0))


func _average_neighbor_color(paint: PackedFloat32Array, paint_g: PackedFloat32Array, paint_b: PackedFloat32Array, paint_a: PackedFloat32Array, x: int, z: int, stride: int) -> Color:
	var accum: Color = Color(0.0, 0.0, 0.0, 0.0)
	var count: float = 0.0
	for zz in range(maxi(0, z - 1), mini(terrain_resolution, z + 1) + 1):
		for xx in range(maxi(0, x - 1), mini(terrain_resolution, x + 1) + 1):
			var idxv: int = _idx(xx, zz, stride)
			accum += _compute_vertex_color(paint[idxv], paint_g[idxv], paint_b[idxv], paint_a[idxv])
			count += 1.0
	if count <= 0.0:
		return Color(0.20, 0.29, 0.22, 1.0)
	return accum / count


func _average_neighbor_normal(heights: PackedFloat32Array, x: int, z: int, step: float) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var count: float = 0.0
	for zz in range(maxi(0, z - 1), mini(terrain_resolution, z + 1) + 1):
		for xx in range(maxi(0, x - 1), mini(terrain_resolution, x + 1) + 1):
			sum += _compute_normal(heights, xx, zz, step)
			count += 1.0
	if count <= 0.0:
		return _compute_normal(heights, x, z, step)
	return (sum / count).normalized()


func _mark_dirty_rect(min_x: int, max_x: int, min_z: int, max_z: int) -> void:
	var border: int = clampi(dirty_rect_border, 3, 8)
	var expanded_min_x: int = maxi(0, min_x - border)
	var expanded_max_x: int = mini(terrain_resolution, max_x + border)
	var expanded_min_z: int = maxi(0, min_z - border)
	var expanded_max_z: int = mini(terrain_resolution, max_z + border)
	if not is_dirty:
		dirty_min = Vector2i(expanded_min_x, expanded_min_z)
		dirty_max = Vector2i(expanded_max_x, expanded_max_z)
		is_dirty = true
	else:
		dirty_min.x = mini(dirty_min.x, expanded_min_x)
		dirty_min.y = mini(dirty_min.y, expanded_min_z)
		dirty_max.x = maxi(dirty_max.x, expanded_max_x)
		dirty_max.y = maxi(dirty_max.y, expanded_max_z)
	if debug_rebuild_logging:
		var size: Vector2i = dirty_max - dirty_min + Vector2i.ONE
		var risk_str: String = "low" if border >= 4 else "medium"
		print("Dirty Rect: ", size, " | Border: ", border, " | Green splotch risk: ", risk_str)


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


func _rebuild_after_stroke(radius: float, tool_name: String) -> void:
	if _full_rebuild_mode or not enable_dirty_rect_rebuild:
		if debug_rebuild_logging:
			print("Terrain Rebuild Path: FULL REBUILD (dirty rect disabled) | tool: %s | force_full: %s" % [tool_name, str(_full_rebuild_mode)])
		rebuild_mesh()
		return
	var supports_dirty: bool = tool_name in ["raise", "lower", "smooth", "flatten", "texturepaint", TOOL_TEXTURE_SUBTRACT]
	if not supports_dirty:
		_log_rebuild("Rebuild mode: full (tool requires full refresh) | tool: %s" % tool_name)
		rebuild_mesh()
		return
	if radius >= terrain_size * clampf(adaptive_large_brush_ratio, 0.25, 0.80):
		_log_rebuild("Rebuild mode: full (large brush) | radius: %s" % str(radius))
		rebuild_mesh()
		return
	if not is_dirty:
		return
	var dirty_width: int = dirty_max.x - dirty_min.x + 1
	var dirty_height: int = dirty_max.y - dirty_min.y + 1
	if dirty_width <= 0 or dirty_height <= 0:
		_log_rebuild("Rebuild mode: full (invalid dirty bounds)")
		rebuild_mesh()
		return
	var dirty_vertices: int = dirty_width * dirty_height
	var total_vertices: int = (terrain_resolution + 1) * (terrain_resolution + 1)
	if dirty_vertices >= int(ceil(float(total_vertices) * clampf(dirty_region_full_rebuild_ratio, 0.30, 0.90))):
		_log_rebuild("Rebuild mode: full (dirty region too large) | vertices: %d / %d" % [dirty_vertices, total_vertices])
		rebuild_mesh()
		return
	if debug_rebuild_logging:
		print("Terrain Rebuild Path: DIRTY RECT ACTIVE | tool: %s | border: %d | extra_ring: %d | blend: %.2f" % [tool_name, clampi(dirty_rect_border, 3, 8), clampi(dirty_rebuild_extra_ring, 1, 4), clampf(dirty_edge_blend_strength, 0.0, 1.0)])
	rebuild_dirty_mesh()


func _log_rebuild(message: String) -> void:
	if debug_rebuild_logging:
		print(message)

func _idx(x: int, z: int, stride: int) -> int:
	return z * stride + x

func rebuild_mesh() -> void:
	_ensure_layer_data(_active_world_layer)
	var start_time: int = Time.get_ticks_usec()
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var paint_g: PackedFloat32Array = _layer_paint_g[_active_world_layer]
	var paint_b: PackedFloat32Array = _layer_paint_b[_active_world_layer]
	var paint_a: PackedFloat32Array = _layer_paint_a[_active_world_layer]
	var water: PackedFloat32Array = _layer_water[_active_world_layer]
	var snow: PackedFloat32Array = _layer_snow[_active_world_layer]
	var stride: int = terrain_resolution + 1
	var count: int = stride * stride
	var half: float = terrain_size * 0.5
	var step: float = terrain_size / float(terrain_resolution)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	uvs.resize(count)

	for z in range(stride):
		for x in range(stride):
			var i: int = _idx(x, z, stride)
			var px: float = -half + float(x) * step
			var pz: float = -half + float(z) * step
			vertices[i] = Vector3(px, heights[i], pz)
			uvs[i] = Vector2(float(x) / float(terrain_resolution), float(z) / float(terrain_resolution))
			colors[i] = _compute_vertex_color(paint[i], paint_g[i], paint_b[i], paint_a[i])

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
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, Array(), Dictionary(), Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	mesh.set_custom_aabb(AABB(Vector3(-half, min_terrain_height, -half), Vector3(terrain_size, max_terrain_height - min_terrain_height, terrain_size)))
	_mesh_instance.mesh = mesh
	_update_control_maps_from_active_layer()
	_apply_terrain_material_to_mesh()
	_update_terrain_collision()
	is_dirty = false
	dirty_min = Vector2i.ZERO
	dirty_max = Vector2i.ZERO
	_surface_ready = true
	if debug_rebuild_logging:
		print("Full rebuild: %.3f ms" % (float(Time.get_ticks_usec() - start_time) / 1000.0))


func rebuild_dirty_mesh() -> void:
	_ensure_layer_data(_active_world_layer)
	if _mesh_instance == null or _mesh_instance.mesh == null or not (_mesh_instance.mesh is ArrayMesh):
		rebuild_mesh()
		return
	if not is_dirty:
		return
	var mesh := _mesh_instance.mesh as ArrayMesh
	if mesh.get_surface_count() == 0:
		rebuild_mesh()
		return
	var start_time: int = Time.get_ticks_usec()
	var heights: PackedFloat32Array = _layer_heights[_active_world_layer]
	var paint: PackedFloat32Array = _layer_paint[_active_world_layer]
	var paint_g: PackedFloat32Array = _layer_paint_g[_active_world_layer]
	var paint_b: PackedFloat32Array = _layer_paint_b[_active_world_layer]
	var paint_a: PackedFloat32Array = _layer_paint_a[_active_world_layer]
	var water: PackedFloat32Array = _layer_water[_active_world_layer]
	var snow: PackedFloat32Array = _layer_snow[_active_world_layer]
	var stride: int = terrain_resolution + 1
	var half: float = terrain_size * 0.5
	var step: float = terrain_size / float(terrain_resolution)
	var row_vertex_size: int = 12
	var row_normal_size: int = 12
	var row_color_size: int = 4
	var normal_block_offset: int = row_vertex_size * stride * stride
	var dirty_width: int = dirty_max.x - dirty_min.x + 1
	var dirty_height: int = dirty_max.y - dirty_min.y + 1
	var vertex_count: int = dirty_width * dirty_height
	var update_pad: int = clampi(dirty_rebuild_extra_ring, 1, 4)
	var update_min_x: int = maxi(0, dirty_min.x - update_pad)
	var update_max_x: int = mini(terrain_resolution, dirty_max.x + update_pad)
	var update_min_z: int = maxi(0, dirty_min.y - update_pad)
	var update_max_z: int = mini(terrain_resolution, dirty_max.y + update_pad)
	if debug_rebuild_logging:
		print("Dirty Rect: ", dirty_min, "->", dirty_max, " | Size: ", dirty_width, "x", dirty_height, " Vertices: ", vertex_count)

	for z in range(update_min_z, update_max_z + 1):
		var row_count: int = update_max_x - update_min_x + 1
		if row_count <= 0:
			continue
		var position_bytes := PackedByteArray()
		position_bytes.resize(row_count * row_vertex_size)
		var normal_bytes := PackedByteArray()
		normal_bytes.resize(row_count * row_normal_size)
		var color_bytes := PackedByteArray()
		color_bytes.resize(row_count * row_color_size)
		for i in range(row_count):
			var x: int = update_min_x + i
			var idxv: int = _idx(x, z, stride)
			var byte_ofs: int = i * row_vertex_size
			var px: float = -half + float(x) * step
			var pz: float = -half + float(z) * step
			position_bytes.encode_float(byte_ofs + 0, px)
			position_bytes.encode_float(byte_ofs + 4, heights[idxv])
			position_bytes.encode_float(byte_ofs + 8, pz)

			var normal: Vector3 = _compute_normal(heights, x, z, step)
			var n_ofs: int = i * row_normal_size
			normal_bytes.encode_float(n_ofs + 0, normal.x)
			normal_bytes.encode_float(n_ofs + 4, normal.y)
			normal_bytes.encode_float(n_ofs + 8, normal.z)

			var terrain_col: Color = _compute_vertex_color(paint[idxv], paint_g[idxv], paint_b[idxv], paint_a[idxv])
			if debug_visualize_dirty_rect:
				terrain_col = Color.RED
			color_bytes.encode_u32(i * row_color_size, terrain_col.to_rgba32())

		var start_index: int = z * stride + update_min_x
		mesh.surface_update_vertex_region(0, start_index * row_vertex_size, position_bytes)
		mesh.surface_update_vertex_region(0, normal_block_offset + start_index * row_normal_size, normal_bytes)
		mesh.surface_update_attribute_region(0, start_index * row_color_size, color_bytes)

	var seam_start_time: int = Time.get_ticks_usec()
	_blend_dirty_outer_border(mesh, heights, paint, paint_g, paint_b, paint_a, stride, step, row_normal_size, row_color_size, normal_block_offset, update_min_x, update_max_x, update_min_z, update_max_z)
	_apply_terrain_material_to_mesh()
	_update_terrain_collision()
	var seam_time: int = Time.get_ticks_usec() - seam_start_time

	if debug_rebuild_logging:
		print("Dirty Rect Update Applied: ", dirty_min, "->", dirty_max, " | main: ", Time.get_ticks_usec() - start_time - seam_time, "us | seams: ", seam_time, "us")

	is_dirty = false
	dirty_min = Vector2i.ZERO
	dirty_max = Vector2i.ZERO
	if debug_rebuild_logging:
		print("Dirty rebuild: %.3f ms" % (float(Time.get_ticks_usec() - start_time) / 1000.0))


func _blend_dirty_outer_border(mesh: ArrayMesh, heights: PackedFloat32Array, paint: PackedFloat32Array, paint_g: PackedFloat32Array, paint_b: PackedFloat32Array, paint_a: PackedFloat32Array, stride: int, step: float, row_normal_size: int, row_color_size: int, normal_block_offset: int, min_x: int, max_x: int, min_z: int, max_z: int) -> void:
	var blend_strength: float = clampf(dirty_edge_blend_strength, 0.0, 1.0)
	if blend_strength <= 0.0:
		return
	var inner_blend: float = blend_strength * 0.55
	for z in range(min_z, max_z + 1):
		for x in range(min_x, max_x + 1):
			var ring1: bool = (x == min_x or x == max_x or z == min_z or z == max_z)
			var ring2: bool = not ring1 and (x == min_x + 1 or x == max_x - 1 or z == min_z + 1 or z == max_z - 1)
			if not ring1 and not ring2:
				continue
			var b: float = blend_strength if ring1 else inner_blend
			var idxv: int = _idx(x, z, stride)
			var current_normal: Vector3 = _compute_normal(heights, x, z, step)
			var avg_normal: Vector3 = _average_neighbor_normal(heights, x, z, step)
			var blended_normal: Vector3 = current_normal.lerp(avg_normal, b).normalized()

			var normal_bytes := PackedByteArray()
			normal_bytes.resize(row_normal_size)
			normal_bytes.encode_float(0, blended_normal.x)
			normal_bytes.encode_float(4, blended_normal.y)
			normal_bytes.encode_float(8, blended_normal.z)

			var current_color: Color = _compute_vertex_color(paint[idxv], paint_g[idxv], paint_b[idxv], paint_a[idxv])
			var avg_color: Color = _average_neighbor_color(paint, paint_g, paint_b, paint_a, x, z, stride)
			var blended_color: Color = current_color.lerp(avg_color, b)

			var color_bytes := PackedByteArray()
			color_bytes.resize(row_color_size)
			color_bytes.encode_u32(0, blended_color.to_rgba32())

			var normal_offset: int = normal_block_offset + idxv * row_normal_size
			var color_offset: int = idxv * row_color_size
			mesh.surface_update_vertex_region(0, normal_offset, normal_bytes)
			mesh.surface_update_attribute_region(0, color_offset, color_bytes)

func _rebuild_surface() -> void:
	rebuild_mesh()
