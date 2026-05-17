# Water System - Main coordinator for PaperVTT river/water management
# Manages river creation, editing, rendering, and persistence
# Integrates with world layer system and main_controller

extends Node

class_name WaterSystem

const WATER_MODE_RIVER: String = "river"
const WATER_MODE_LAKE: String = "lake"
const WATER_MODE_FILL: String = "fill"

const WATER_BODY_TYPE_RIVER: String = "river"
const WATER_BODY_TYPE_LAKE: String = "lake"
const WATER_BODY_TYPE_FILL: String = "fill"

const WaterHelperMethods = preload("./water_helper_methods.gd")
const DEFAULT_WATER_NORMAL_TEXTURES: Array[String] = [
	"res://assets/textures/water/water1_normal_bump.png",
]
const DEFAULT_WATER_FOAM_TEXTURES: Array[String] = [
	"res://assets/textures/water/foam_noise.png",
	"res://assets/textures/water/flow_offset_noise.png",
]
const DEFAULT_RIVERBED_TEXTURES: Dictionary = {
	"albedo": "res://assets/textures/water/ground_with_rocks_03_2k/ground_with_rocks_03_color_2k.png",
	"normal": "res://assets/textures/water/ground_with_rocks_03_2k/ground_with_rocks_03_normal_gl_2k.png",
	"roughness": "res://assets/textures/water/ground_with_rocks_03_2k/ground_with_rocks_03_roughness_2k.png",
	"height": "res://assets/textures/water/ground_with_rocks_03_2k/ground_with_rocks_03_height_2k.png",
	"ao": "res://assets/textures/water/ground_with_rocks_03_2k/ground_with_rocks_03_ambient_occlussion_2k.png",
}
const DEFAULT_WATER_PRESET: String = "crystal_clear"
const WATER_PRESETS: Dictionary = {
	"crystal_clear": {
		"water_color": Color(0.14, 0.50, 0.56),
		"water_depth": 7.5,
		"flow_speed": 0.24,
		"ripple_strength": 0.32,
		"transparency": 0.64,
		"foam_amount": 0.14,
		"specular_strength": 0.72,
	},
	"deep_river": {
		"water_color": Color(0.10, 0.40, 0.49),
		"water_depth": 11.5,
		"flow_speed": 0.28,
		"ripple_strength": 0.38,
		"transparency": 0.68,
		"foam_amount": 0.18,
		"specular_strength": 0.76,
	},
}

# River configuration
const DEFAULT_PARAMETERS = {
	river_step_length_divs = 3,  # More segments along curve = smoother bends
	river_step_width_divs = 2,   # More points across width = less stretching
	river_smoothness = 0.5,
	river_width_default = 5.0,   # Doubled for more impressive rivers
	shader_type = 0,  # 0=Water, 1=Custom
	default_layer = 0,  # Ground Floor by default
}

# Node references
var _main_controller: Node = null
var _terrain_node: Node = null
var _rivers: Dictionary = {}  # Dictionary of river objects keyed by unique ID
var _river_container: Node = null  # Container node for all rivers
var _next_river_id: int = 0
var _material_cache: Dictionary = {}  # Material cache for performance
var _current_layer: int = 0  # Current world layer (for new rivers)
var _current_water_preset: String = DEFAULT_WATER_PRESET
var _riverbed_maps: Dictionary = {}
var _lakes: Dictionary = {}  # Dictionary of lake/fill bodies keyed by unique ID
var _next_lake_id: int = 0
var _water_mode: String = WATER_MODE_RIVER

signal river_created(river_id, river_node)
signal river_updated(river_id, river_node)
signal river_deleted(river_id)
signal rivers_changed


func _ready() -> void:
	# Try to find main controller and terrain in scene
	_main_controller = get_node_or_null("/root/Main/MainController")
	
	# Create river container node
	_river_container = Node.new()
	_river_container.name = "Rivers"
	add_child(_river_container)


# Initialize water system with reference to main systems
func initialize(main_controller: Node, terrain_node: Node) -> void:
	_main_controller = main_controller
	_terrain_node = terrain_node
	_load_riverbed_maps()
	
	# Create base water shader material
	_create_water_material()


# Create the water shader material
func _create_water_material() -> ShaderMaterial:
	var mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	apply_water_preset(_current_water_preset, mat)
	mat.set_shader_parameter("water_color", Color(0.14, 0.50, 0.56))
	mat.set_shader_parameter("flow_speed", 0.24)
	mat.set_shader_parameter("ripple_strength", 0.32)
	mat.set_shader_parameter("transparency", 0.64)
	mat.set_shader_parameter("foam_amount", 0.14)
	mat.set_shader_parameter("specular_strength", 0.72)
	
	var normal_texture: Texture2D = _load_texture_from_candidates(DEFAULT_WATER_NORMAL_TEXTURES)
	if normal_texture == null:
		normal_texture = _make_fallback_normal_texture()
	mat.set_shader_parameter("normal_texture", normal_texture)
	
	var foam_texture: Texture2D = _load_texture_from_candidates(DEFAULT_WATER_FOAM_TEXTURES)
	if foam_texture == null:
		foam_texture = _make_fallback_foam_texture()
	mat.set_shader_parameter("foam_texture", foam_texture)
	print("[WaterSystem] material created | shader=", mat.shader, " normal_tex=", normal_texture != null, " foam_tex=", foam_texture != null)
	
	_material_cache["default"] = mat
	return mat


func _apply_layer_visual_style(mat: ShaderMaterial, layer: int) -> void:
	if mat == null:
		return
	if layer >= 0:
		return
	var water_color_variant: Variant = mat.get_shader_parameter("water_color")
	var water_color: Color = water_color_variant as Color if water_color_variant is Color else Color(0.12, 0.48, 0.55)
	var cavern_tint: Color = Color(0.08, 0.20, 0.26)
	mat.set_shader_parameter("water_color", water_color.lerp(cavern_tint, 0.42).darkened(0.12))
	var specular_variant: Variant = mat.get_shader_parameter("specular_strength")
	var specular: float = float(specular_variant) if specular_variant != null else 0.64
	mat.set_shader_parameter("specular_strength", clampf(specular * 0.72, 0.2, 0.9))
	var transparency_variant: Variant = mat.get_shader_parameter("transparency")
	var transparency: float = float(transparency_variant) if transparency_variant != null else 0.62
	mat.set_shader_parameter("transparency", clampf(transparency + 0.03, 0.5, 0.78))


func _refresh_layer_visibility() -> void:
	for river_id in _rivers:
		var river: Dictionary = _rivers[river_id]
		var mesh_instance: MeshInstance3D = river.get("mesh_instance", null)
		if mesh_instance != null:
			mesh_instance.visible = int(river.get("layer", 0)) == _current_layer
	for lake_id in _lakes:
		var lake: Dictionary = _lakes[lake_id]
		var mesh_instance: MeshInstance3D = lake.get("mesh_instance", null)
		if mesh_instance != null:
			mesh_instance.visible = int(lake.get("layer", 0)) == _current_layer


func get_water_presets() -> Array[String]:
	return WATER_PRESETS.keys()


func get_current_water_preset() -> String:
	return _current_water_preset


func apply_water_preset(preset_name: String, target_material: ShaderMaterial = null) -> bool:
	if not WATER_PRESETS.has(preset_name):
		return false

	_current_water_preset = preset_name
	var preset: Dictionary = WATER_PRESETS[preset_name]

	if target_material != null:
		_apply_shader_params(target_material, preset)
		return true

	if _material_cache.has("default") and _material_cache["default"] is ShaderMaterial:
		_apply_shader_params(_material_cache["default"] as ShaderMaterial, preset)

	for river_id in _rivers:
		var mesh_instance: MeshInstance3D = _rivers[river_id].get("mesh_instance", null)
		if mesh_instance != null and mesh_instance.material_override is ShaderMaterial:
			_apply_shader_params(mesh_instance.material_override as ShaderMaterial, preset)
			_apply_river_material_settings(int(river_id))

	return true


func _apply_shader_params(mat: ShaderMaterial, params: Dictionary) -> void:
	for param_name in params.keys():
		mat.set_shader_parameter(str(param_name), params[param_name])


func _load_texture_from_candidates(paths: Array[String]) -> Texture2D:
	for path in paths:
		if ResourceLoader.exists(path):
			var resource: Resource = load(path)
			if resource is Texture2D:
				return resource as Texture2D
	return null


func _make_fallback_normal_texture() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.5, 0.5, 1.0, 1.0))
	return ImageTexture.create_from_image(img)


func _make_fallback_foam_texture() -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.72, 0.72, 0.72, 1.0))
	return ImageTexture.create_from_image(img)


func _duplicate_water_material() -> ShaderMaterial:
	var base_mat: ShaderMaterial = _material_cache.get("default", null)
	if base_mat == null:
		base_mat = _create_water_material()
	var duplicate_mat: ShaderMaterial = base_mat.duplicate(true) as ShaderMaterial
	if duplicate_mat == null:
		duplicate_mat = _create_water_material()
	return duplicate_mat


func _apply_river_material_settings(river_id: int) -> void:
	if not _rivers.has(river_id):
		return
	var river: Dictionary = _rivers[river_id]
	var mesh_instance: MeshInstance3D = river.get("mesh_instance", null)
	if mesh_instance == null:
		return
	if not (mesh_instance.material_override is ShaderMaterial):
		mesh_instance.material_override = _duplicate_water_material()
	var mat: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	var depth_value: float = float(river.get("average_depth", 15.0))
	var preset: Dictionary = WATER_PRESETS.get(_current_water_preset, WATER_PRESETS[DEFAULT_WATER_PRESET])
	mat.set_shader_parameter("water_color", preset.get("water_color", Color(0.14, 0.50, 0.56)))
	mat.set_shader_parameter("flow_speed", preset.get("flow_speed", 0.24))
	mat.set_shader_parameter("ripple_strength", preset.get("ripple_strength", 0.32))
	mat.set_shader_parameter("foam_amount", preset.get("foam_amount", 0.14))
	mat.set_shader_parameter("specular_strength", preset.get("specular_strength", 0.72))
	mat.set_shader_parameter("transparency", clampf(float(preset.get("transparency", 0.64)) - depth_value / 650.0, 0.52, 0.74))
	_apply_layer_visual_style(mat, int(river.get("layer", 0)))


func _apply_lake_material_settings(lake_id: int) -> void:
	if not _lakes.has(lake_id):
		return
	var lake: Dictionary = _lakes[lake_id]
	var mesh_instance: MeshInstance3D = lake.get("mesh_instance", null)
	if mesh_instance == null:
		return
	if not (mesh_instance.material_override is ShaderMaterial):
		mesh_instance.material_override = _duplicate_water_material()
	var mat: ShaderMaterial = mesh_instance.material_override as ShaderMaterial
	var preset: Dictionary = WATER_PRESETS.get(_current_water_preset, WATER_PRESETS[DEFAULT_WATER_PRESET])
	mat.set_shader_parameter("water_color", preset.get("water_color", Color(0.12, 0.48, 0.55)))
	mat.set_shader_parameter("flow_speed", preset.get("flow_speed", 0.26) * 0.65)
	mat.set_shader_parameter("ripple_strength", preset.get("ripple_strength", 0.42) * 0.75)
	mat.set_shader_parameter("foam_amount", preset.get("foam_amount", 0.18) * 0.85)
	mat.set_shader_parameter("specular_strength", preset.get("specular_strength", 0.64) * 0.95)
	mat.set_shader_parameter("transparency", clampf(float(preset.get("transparency", 0.62)) - 0.04, 0.44, 0.66))
	_apply_layer_visual_style(mat, int(lake.get("layer", 0)))


func set_river_average_depth(river_id: int, depth: float) -> void:
	if not _rivers.has(river_id):
		return
	var river: Dictionary = _rivers[river_id]
	river["average_depth"] = clampf(depth, 0.4, 18.0)
	_apply_river_material_settings(river_id)
	_regenerate_river_mesh(river_id)
	emit_signal("river_updated", river_id, river["mesh_instance"])


func set_river_average_depth_all(depth: float) -> void:
	for river_id in _rivers:
		set_river_average_depth(int(river_id), depth)


func _ensure_water_material(mesh_instance: MeshInstance3D) -> ShaderMaterial:
	if mesh_instance.material_override is ShaderMaterial:
		return mesh_instance.material_override as ShaderMaterial
	var mat = _material_cache.get("default", null)
	if not (mat is ShaderMaterial):
		mat = _create_water_material()
	mesh_instance.material_override = mat
	print("[WaterSystem] assigned shader material to river mesh")
	return mat as ShaderMaterial


func _load_riverbed_maps() -> void:
	_riverbed_maps.clear()
	var target_size: int = 1024
	if _terrain_node != null and _terrain_node.has_method("get"):
		target_size = max(256, int(_terrain_node.get("paint_resolution")))
	for key in DEFAULT_RIVERBED_TEXTURES.keys():
		var path: String = str(DEFAULT_RIVERBED_TEXTURES[key])
		if not ResourceLoader.exists(path):
			_riverbed_maps[key] = null
			continue
		var tex: Texture2D = load(path) as Texture2D
		if tex == null:
			_riverbed_maps[key] = null
			continue
		var img: Image = tex.get_image()
		if img == null:
			_riverbed_maps[key] = null
			continue
		if img.get_width() != target_size or img.get_height() != target_size:
			img.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)
		_riverbed_maps[key] = img


func shape_riverbed_for_river(river_id: int, depth_m: float = 0.75, width_multiplier: float = 1.35, paint_strength: float = 0.34) -> void:
	if not _rivers.has(river_id):
		return
	if _terrain_node == null:
		return
	if not _terrain_node.has_method("apply_brush"):
		return

	var river: Dictionary = _rivers[river_id]
	var curve: Curve3D = river.get("curve", null)
	if curve == null or curve.get_baked_length() <= 0.01:
		return

	var widths: Array = river.get("widths", [])
	var average_depth: float = float(river.get("average_depth", 15.0))
	var average_width: float = 2.0
	if not widths.is_empty():
		average_width = WaterHelperMethods.sum_array(widths) / float(widths.size())

	var length: float = curve.get_baked_length()
	var sample_spacing: float = maxf(0.9, average_width * 0.45)
	var sample_count: int = int(maxf(8.0, ceil(length / sample_spacing)))
	var terrain_max_height: float = 24.0
	if _terrain_node.has_method("get"):
		terrain_max_height = float(_terrain_node.get("max_height"))
	var terrain_vertical_range: float = maxf(1.0, terrain_max_height * 2.0)

	for i in range(sample_count + 1):
		var t: float = float(i) / float(sample_count)
		var point: Vector3 = curve.sample_baked(t * length)
		var width_here: float = _sample_width_at_t(widths, t)
		var brush_size: float = maxf(1.2, width_here * width_multiplier)
		var variation: float = 0.82 + 0.26 * sin(t * 12.0 + float(river_id) * 1.37)
		var depth_profile: float = (0.72 + 0.48 * (1.0 - absf(t * 2.0 - 1.0))) * variation
		var local_depth_m: float = maxf(depth_m, average_depth * 0.10) * depth_profile
		var brush_strength: float = clampf((local_depth_m / terrain_vertical_range) * 2.4, 0.12, 1.0)
		var passes: int = int(maxf(1.0, round(local_depth_m / 0.45)))

		for _pass in range(passes):
			_terrain_node.call("apply_brush", "lower", point, brush_size, brush_strength)

		if i % 2 == 0:
			_paint_riverbed_at_point(point, brush_size * 0.9, paint_strength)


func _paint_riverbed_at_point(point: Vector3, brush_size: float, strength: float) -> void:
	if _terrain_node == null or not _terrain_node.has_method("apply_texture_brush"):
		return
	if _riverbed_maps.is_empty():
		return
	var albedo: Image = _riverbed_maps.get("albedo", null)
	if albedo == null:
		return
	_terrain_node.call(
		"apply_texture_brush",
		point,
		albedo,
		_riverbed_maps.get("normal", null),
		_riverbed_maps.get("roughness", null),
		_riverbed_maps.get("height", null),
		_riverbed_maps.get("ao", null),
		brush_size,
		clampf(strength, 0.05, 1.0)
	)


func _sample_width_at_t(widths: Array, t: float) -> float:
	if widths.is_empty():
		return 2.0
	if widths.size() == 1:
		return float(widths[0])
	var f_index: float = clampf(t, 0.0, 1.0) * float(widths.size() - 1)
	var i0: int = int(floor(f_index))
	var i1: int = min(i0 + 1, widths.size() - 1)
	var w_t: float = f_index - float(i0)
	return lerpf(float(widths[i0]), float(widths[i1]), w_t)


# Create a new river
func create_river(river_name: String = "", layer: int = -1) -> Node:
	var river_id = _next_river_id
	_next_river_id += 1
	
	if river_name == "":
		river_name = "River_%d" % river_id
	
	# Use current layer or default to Ground Floor (layer 0)
	if layer < 0:
		layer = _current_layer
	
	# Create mesh instance for river
	var river_mesh_instance = MeshInstance3D.new()
	river_mesh_instance.name = river_name
	river_mesh_instance.set_meta("river_id", river_id)
	
	# Initialize river properties
	var river_data = {
		"id": river_id,
		"type": WATER_BODY_TYPE_RIVER,
		"name": river_name,
		"layer": layer,
		"mesh_instance": river_mesh_instance,
		"curve": Curve3D.new(),
		"widths": [5.0, 5.0],  # Doubled for larger, more impressive rivers
		"average_depth": 15.0,  # Doubled for deeper, more impressive water
		"valid": false,
	}
	
	# Setup curve
	river_data["curve"].bake_interval = 0.05
	river_data["curve"].add_point(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -0.25), Vector3(0.0, 0.0, 0.25))
	river_data["curve"].add_point(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -0.25), Vector3(0.0, 0.0, 0.25))
	
	# Assign material
	river_mesh_instance.material_override = _duplicate_water_material()
	
	# Add to container
	_river_container.add_child(river_mesh_instance)
	river_mesh_instance.visible = layer == _current_layer
	
	# Store in dictionary
	_rivers[river_id] = river_data
	
	# Generate initial mesh
	_regenerate_river_mesh(river_id)
	
	emit_signal("river_created", river_id, river_mesh_instance)
	emit_signal("rivers_changed")
	
	return river_mesh_instance


# Add point to river curve
func add_river_point(river_id: int, position: Vector3, index: int = -1, dir: Vector3 = Vector3.ZERO, width: float = 0.0) -> void:
	if not river_id in _rivers:
		push_error("River ID %d not found" % river_id)
		return
	
	var river = _rivers[river_id]
	var curve = river["curve"]
	var widths = river["widths"]
	
	if index == -1:
		# Add at end
		var last_index = curve.get_point_count() - 1
		var dist = position.distance_to(curve.get_point_position(last_index))
		var new_dir = dir if dir != Vector3.ZERO else (position - curve.get_point_position(last_index) - curve.get_point_out(last_index)).normalized() * 0.25 * dist
		curve.add_point(position, -new_dir, new_dir, -1)
		widths.append(widths[widths.size() - 1])
	else:
		# Add at index
		var dist = curve.get_point_position(index).distance_to(curve.get_point_position(index + 1))
		var new_dir = dir if dir != Vector3.ZERO else (curve.get_point_position(index + 1) - curve.get_point_position(index)).normalized() * 0.25 * dist
		curve.add_point(position, -new_dir, new_dir, index + 1)
		var new_width = width if width != 0.0 else (widths[index] + widths[index + 1]) / 2.0
		widths.insert(index + 1, new_width)
	
	_regenerate_river_mesh(river_id)
	emit_signal("river_updated", river_id, river["mesh_instance"])
	emit_signal("rivers_changed")


# Remove point from river
func remove_river_point(river_id: int, index: int) -> void:
	if not river_id in _rivers:
		push_error("River ID %d not found" % river_id)
		return
	
	var river = _rivers[river_id]
	var curve = river["curve"]
	var widths = river["widths"]
	
	# Don't allow rivers shorter than 2 points
	if curve.get_point_count() <= 2:
		return
	
	curve.remove_point(index)
	widths.remove(index)
	
	_regenerate_river_mesh(river_id)
	emit_signal("river_updated", river_id, river["mesh_instance"])
	emit_signal("rivers_changed")


# Set point position
func set_river_point_position(river_id: int, index: int, position: Vector3) -> void:
	if not river_id in _rivers:
		return
	
	var river = _rivers[river_id]
	river["curve"].set_point_position(index, position)
	_regenerate_river_mesh(river_id)
	emit_signal("river_updated", river_id, river["mesh_instance"])


# Set river width at point
func set_river_width(river_id: int, index: int, width: float) -> void:
	if not river_id in _rivers:
		return
	
	var river = _rivers[river_id]
	river["widths"][index] = width
	_regenerate_river_mesh(river_id)
	emit_signal("river_updated", river_id, river["mesh_instance"])


func set_river_width_all(river_id: int, width: float) -> void:
	if not river_id in _rivers:
		return
	var river = _rivers[river_id]
	for i in range(river["widths"].size()):
		river["widths"][i] = width
	_regenerate_river_mesh(river_id)
	emit_signal("river_updated", river_id, river["mesh_instance"])


# Regenerate river mesh from curve
func _regenerate_river_mesh(river_id: int) -> void:
	if not river_id in _rivers:
		return
	
	var river = _rivers[river_id]
	var curve = river["curve"]
	var widths = river["widths"]
	var mesh_instance: MeshInstance3D = river["mesh_instance"]
	_apply_river_material_settings(river_id)
	
	var average_width = WaterHelperMethods.sum_array(widths) / float(max(1, widths.size()))
	var steps = int(max(1.0, round(curve.get_baked_length() / average_width)))
	var depth_value: float = float(river.get("average_depth", 15.0))
	var surface_height_offset: float = clampf(-0.14 - depth_value * 0.004, -0.18, -0.12)
	
	var river_width_values = WaterHelperMethods.generate_river_width_values(
		curve, steps, 
		DEFAULT_PARAMETERS.river_step_length_divs,
		DEFAULT_PARAMETERS.river_step_width_divs,
		widths
	)
	
	var mesh = WaterHelperMethods.generate_river_mesh(
		curve, steps,
		DEFAULT_PARAMETERS.river_step_length_divs,
		DEFAULT_PARAMETERS.river_step_width_divs,
		DEFAULT_PARAMETERS.river_smoothness,
		river_width_values,
		surface_height_offset
	)
	
	mesh_instance.mesh = mesh
	river["valid"] = true
	print("[WaterSystem] river mesh regenerated id=", river_id, " material=", mesh_instance.material_override, " surface_offset=", surface_height_offset, " depth=", depth_value)


func _triangulate_lake_points(points: Array) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	if points.size() < 3:
		return vertices
	var center: Vector3 = Vector3.ZERO
	for p in points:
		if p is Vector3:
			center += p as Vector3
	center /= float(points.size())
	for i in range(points.size()):
		var next_i: int = (i + 1) % points.size()
		vertices.append(center)
		vertices.append(points[i] as Vector3)
		vertices.append(points[next_i] as Vector3)
	return vertices


func _build_lake_mesh(points: Array, water_level: float, surface_height_offset: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var triangles: PackedVector3Array = _triangulate_lake_points(points)
	if triangles.is_empty():
		return st.commit()
	for i in range(0, triangles.size(), 3):
		for j in range(3):
			var p: Vector3 = triangles[i + j]
			var v: Vector3 = Vector3(p.x, water_level + surface_height_offset, p.z)
			var uv: Vector2 = Vector2(v.x * 0.08, v.z * 0.08)
			st.set_uv(uv)
			st.add_vertex(v)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func create_lake(lake_name: String = "", center: Vector3 = Vector3.ZERO, radius: float = 7.0, layer: int = -1, body_type: String = WATER_BODY_TYPE_LAKE, average_depth: float = 12.0, shape_basin: bool = true) -> Node:
	var lake_id: int = _next_lake_id
	_next_lake_id += 1
	if lake_name == "":
		lake_name = "Lake_%d" % lake_id
	if layer < 0:
		layer = _current_layer
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = lake_name
	mesh_instance.set_meta("lake_id", lake_id)
	mesh_instance.material_override = _duplicate_water_material()
	var points: Array = []
	var resolution: int = 24
	for i in range(resolution):
		var t: float = float(i) / float(resolution)
		var angle: float = t * TAU
		var r_noise: float = 1.0 + (WaterHelperMethods._hash_01(float(lake_id) * 11.7 + float(i) * 0.71) - 0.5) * 0.14
		var p: Vector3 = center + Vector3(cos(angle) * radius * r_noise, 0.0, sin(angle) * radius * r_noise)
		points.append(p)

	var merge_target_id: int = _find_merge_target_lake(points, layer)
	if merge_target_id >= 0 and _lakes.has(merge_target_id):
		var merged_lake: Dictionary = _lakes[merge_target_id]
		var merged_points: Array = []
		merged_points.append_array(merged_lake.get("points", []))
		merged_points.append_array(points)
		merged_lake["points"] = _lake_points_to_hull(merged_points)
		merged_lake["water_level"] = minf(float(merged_lake.get("water_level", center.y)), center.y)
		merged_lake["average_depth"] = maxf(float(merged_lake.get("average_depth", 12.0)), average_depth)
		if body_type == WATER_BODY_TYPE_FILL:
			merged_lake["type"] = WATER_BODY_TYPE_FILL
		_lakes[merge_target_id] = merged_lake
		_regenerate_lake_mesh(merge_target_id)
		if shape_basin:
			_shape_lakebed_for_lake(merge_target_id)
		emit_signal("river_updated", merge_target_id, merged_lake.get("mesh_instance", null))
		emit_signal("rivers_changed")
		return merged_lake.get("mesh_instance", null)

	var lake_data: Dictionary = {
		"id": lake_id,
		"type": body_type,
		"name": lake_name,
		"layer": layer,
		"mesh_instance": mesh_instance,
		"points": points,
		"water_level": center.y,
		"average_depth": maxf(0.2, average_depth),
		"valid": false,
	}
	_lakes[lake_id] = lake_data
	_river_container.add_child(mesh_instance)
	mesh_instance.visible = layer == _current_layer
	_regenerate_lake_mesh(lake_id)
	if shape_basin:
		_shape_lakebed_for_lake(lake_id)
	emit_signal("river_created", lake_id, mesh_instance)
	emit_signal("rivers_changed")
	return mesh_instance


func _query_terrain_height(x: float, z: float, fallback_y: float) -> float:
	if _terrain_node != null:
		if _terrain_node.has_method("sample_height"):
			return float(_terrain_node.call("sample_height", x, z))
		if _terrain_node.has_method("get_height_at_position"):
			return float(_terrain_node.call("get_height_at_position", Vector3(x, 0.0, z)))
	if _main_controller != null and _main_controller.has_method("_sample_terrain_height"):
		return float(_main_controller.call("_sample_terrain_height", x, z))
	return fallback_y


func _lake_points_to_hull(points: Array) -> Array:
	var planar := PackedVector2Array()
	for p in points:
		if p is Vector3:
			var pv: Vector3 = p as Vector3
			planar.append(Vector2(pv.x, pv.z))
	if planar.size() < 3:
		return points.duplicate()
	var hull: PackedVector2Array = Geometry2D.convex_hull(planar)
	if hull.size() < 3:
		return points.duplicate()
	var y_sum: float = 0.0
	var y_count: int = 0
	for p in points:
		if p is Vector3:
			y_sum += (p as Vector3).y
			y_count += 1
	var y_level: float = y_sum / float(max(1, y_count))
	var out_points: Array = []
	for hp in hull:
		out_points.append(Vector3(hp.x, y_level, hp.y))
	return out_points


func _point_inside_polygon_xz(point: Vector3, polygon: Array) -> bool:
	if polygon.size() < 3:
		return false
	var inside: bool = false
	var j: int = polygon.size() - 1
	for i in range(polygon.size()):
		if not (polygon[i] is Vector3) or not (polygon[j] is Vector3):
			j = i
			continue
		var pi: Vector3 = polygon[i] as Vector3
		var pj: Vector3 = polygon[j] as Vector3
		var intersects: bool = ((pi.z > point.z) != (pj.z > point.z))
		if intersects:
			var denom: float = pj.z - pi.z
			if absf(denom) < 0.00001:
				j = i
				continue
			var x_at_z: float = ((pj.x - pi.x) * (point.z - pi.z) / denom) + pi.x
			if point.x < x_at_z:
				inside = not inside
		j = i
	return inside


func _polygon_bounds_xz(points: Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var min_x: float = INF
	var min_z: float = INF
	var max_x: float = -INF
	var max_z: float = -INF
	for p in points:
		if p is Vector3:
			var pv: Vector3 = p as Vector3
			min_x = minf(min_x, pv.x)
			min_z = minf(min_z, pv.z)
			max_x = maxf(max_x, pv.x)
			max_z = maxf(max_z, pv.z)
	if min_x == INF:
		return Rect2()
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))


func _lake_polygons_overlap(points_a: Array, points_b: Array) -> bool:
	if points_a.size() < 3 or points_b.size() < 3:
		return false
	var bounds_a: Rect2 = _polygon_bounds_xz(points_a)
	var bounds_b: Rect2 = _polygon_bounds_xz(points_b)
	if not bounds_a.intersects(bounds_b):
		return false
	for pa in points_a:
		if pa is Vector3 and _point_inside_polygon_xz(pa as Vector3, points_b):
			return true
	for pb in points_b:
		if pb is Vector3 and _point_inside_polygon_xz(pb as Vector3, points_a):
			return true
	return false


func _find_merge_target_lake(points: Array, layer: int) -> int:
	for lake_id in _lakes.keys():
		var lake: Dictionary = _lakes[lake_id]
		if int(lake.get("layer", 0)) != layer:
			continue
		var existing_points: Array = lake.get("points", [])
		if _lake_polygons_overlap(existing_points, points):
			return int(lake_id)
	return -1


func _sample_polygon_edge_water_level(points: Array, fallback_level: float) -> float:
	if points.size() < 3:
		return fallback_level
	var sampled_level: float = fallback_level
	for p in points:
		if p is Vector3:
			var pp: Vector3 = p as Vector3
			sampled_level = minf(sampled_level, _query_terrain_height(pp.x, pp.z, fallback_level) + 0.06)
	return sampled_level


func _shape_lakebed_for_lake(lake_id: int) -> void:
	if not _lakes.has(lake_id):
		return
	if _terrain_node == null or not _terrain_node.has_method("apply_brush"):
		return
	var lake: Dictionary = _lakes[lake_id]
	var points: Array = lake.get("points", [])
	if points.size() < 3:
		return
	var water_level: float = float(lake.get("water_level", 0.0))
	var depth_m: float = maxf(0.2, float(lake.get("average_depth", 12.0)))
	var target_bed_height: float = water_level - depth_m
	var bounds: Rect2 = _polygon_bounds_xz(points)
	if bounds.size.x <= 0.01 or bounds.size.y <= 0.01:
		return

	var sample_spacing: float = clampf(depth_m * 0.12, 1.0, 2.6)
	var brush_size: float = sample_spacing * 1.2
	var z: float = bounds.position.y
	while z <= bounds.position.y + bounds.size.y + 0.001:
		var x: float = bounds.position.x
		while x <= bounds.position.x + bounds.size.x + 0.001:
			var p: Vector3 = Vector3(x, water_level, z)
			if _point_inside_polygon_xz(p, points):
				var current_h: float = _query_terrain_height(x, z, water_level)
				if current_h > target_bed_height + 0.01:
					var delta_h: float = current_h - target_bed_height
					var passes: int = int(clampf(ceil(delta_h / 0.6), 1.0, 18.0))
					var strength: float = clampf(delta_h / 5.0, 0.2, 1.0)
					for _pass in range(passes):
						_terrain_node.call("apply_brush", "lower", p, brush_size, strength)
					_paint_riverbed_at_point(p, maxf(1.2, brush_size * 0.85), 0.34)
			x += sample_spacing
		z += sample_spacing


func create_fill_water(fill_name: String = "", center: Vector3 = Vector3.ZERO, radius: float = 10.0, layer: int = -1, average_depth: float = 12.0) -> Node:
	var node: Node = create_lake(fill_name, center, radius, layer, WATER_BODY_TYPE_FILL, average_depth, false)
	if node is MeshInstance3D and node.has_meta("lake_id"):
		var lake_id: int = int(node.get_meta("lake_id"))
		if _lakes.has(lake_id):
			var points: Array = _lakes[lake_id].get("points", [])
			var sampled_level: float = _sample_polygon_edge_water_level(points, center.y)
			_lakes[lake_id]["water_level"] = sampled_level
			_lakes[lake_id]["average_depth"] = maxf(0.2, average_depth)
			_regenerate_lake_mesh(lake_id)
			_shape_lakebed_for_lake(lake_id)
	return node


func _regenerate_lake_mesh(lake_id: int) -> void:
	if not _lakes.has(lake_id):
		return
	var lake: Dictionary = _lakes[lake_id]
	var mesh_instance: MeshInstance3D = lake.get("mesh_instance", null)
	if mesh_instance == null:
		return
	var points: Array = lake.get("points", [])
	if points.size() < 3:
		return
	var depth_value: float = float(lake.get("average_depth", 12.0))
	var surface_height_offset: float = clampf(-0.14 - depth_value * 0.003, -0.18, -0.12)
	var mesh: Mesh = _build_lake_mesh(points, float(lake.get("water_level", 0.0)), surface_height_offset)
	mesh_instance.mesh = mesh
	_lakes[lake_id]["valid"] = true
	_apply_lake_material_settings(lake_id)


func set_lake_points(lake_id: int, points: Array) -> void:
	if not _lakes.has(lake_id):
		return
	_lakes[lake_id]["points"] = points.duplicate()
	_regenerate_lake_mesh(lake_id)


func add_lake_point(lake_id: int, point: Vector3) -> void:
	if not _lakes.has(lake_id):
		return
	var points: Array = _lakes[lake_id].get("points", [])
	points.append(point)
	_lakes[lake_id]["points"] = points
	_regenerate_lake_mesh(lake_id)


func set_lake_water_level(lake_id: int, water_level: float) -> void:
	if not _lakes.has(lake_id):
		return
	_lakes[lake_id]["water_level"] = water_level
	_regenerate_lake_mesh(lake_id)


func delete_lake(lake_id: int) -> void:
	if not _lakes.has(lake_id):
		return
	var lake: Dictionary = _lakes[lake_id]
	var mesh_instance: MeshInstance3D = lake.get("mesh_instance", null)
	if mesh_instance != null:
		mesh_instance.queue_free()
	_lakes.erase(lake_id)
	emit_signal("rivers_changed")


# Delete a river
func delete_river(river_id: int) -> void:
	if not river_id in _rivers:
		return
	
	var river = _rivers[river_id]
	river["mesh_instance"].queue_free()
	_rivers.erase(river_id)
	
	emit_signal("river_deleted", river_id)
	emit_signal("rivers_changed")


func clear_all() -> void:
	for river_id in _rivers.keys():
		delete_river(river_id)
	for lake_id in _lakes.keys():
		delete_lake(lake_id)


func set_flow_speed(value: float) -> void:
	if _material_cache.has("default") and _material_cache["default"] is ShaderMaterial:
		(_material_cache["default"] as ShaderMaterial).set_shader_parameter("flow_speed", value)
	for river_id in _rivers:
		var mesh_instance: MeshInstance3D = _rivers[river_id]["mesh_instance"]
		if mesh_instance != null and mesh_instance.material_override is ShaderMaterial:
			(mesh_instance.material_override as ShaderMaterial).set_shader_parameter("flow_speed", value)
	for lake_id in _lakes:
		var lake_mesh: MeshInstance3D = _lakes[lake_id].get("mesh_instance", null)
		if lake_mesh != null and lake_mesh.material_override is ShaderMaterial:
			(lake_mesh.material_override as ShaderMaterial).set_shader_parameter("flow_speed", value * 0.7)


func set_water_color(color: Color) -> void:
	if _material_cache.has("default") and _material_cache["default"] is ShaderMaterial:
		(_material_cache["default"] as ShaderMaterial).set_shader_parameter("water_color", color)
	for river_id in _rivers:
		var mesh_instance: MeshInstance3D = _rivers[river_id]["mesh_instance"]
		if mesh_instance != null and mesh_instance.material_override is ShaderMaterial:
			(mesh_instance.material_override as ShaderMaterial).set_shader_parameter("water_color", color)
	for lake_id in _lakes:
		var lake_mesh: MeshInstance3D = _lakes[lake_id].get("mesh_instance", null)
		if lake_mesh != null and lake_mesh.material_override is ShaderMaterial:
			(lake_mesh.material_override as ShaderMaterial).set_shader_parameter("water_color", color)


# Get all rivers
func get_rivers() -> Dictionary:
	return get_rivers_on_layer(_current_layer)


func get_rivers_all() -> Dictionary:
	return _rivers.duplicate()


func get_lakes() -> Dictionary:
	return get_lakes_on_layer(_current_layer)


func get_lakes_all() -> Dictionary:
	return _lakes.duplicate()


# Get rivers on a specific world layer
func get_rivers_on_layer(layer: int) -> Dictionary:
	var layer_rivers = {}
	for river_id in _rivers:
		if _rivers[river_id].get("layer", 0) == layer:
			layer_rivers[river_id] = _rivers[river_id]
	return layer_rivers


func get_lakes_on_layer(layer: int) -> Dictionary:
	var layer_lakes := {}
	for lake_id in _lakes:
		if _lakes[lake_id].get("layer", 0) == layer:
			layer_lakes[lake_id] = _lakes[lake_id]
	return layer_lakes


# Set active world layer for new rivers
func set_current_layer(layer: int) -> void:
	_current_layer = layer
	_refresh_layer_visibility()


func set_water_mode(mode: String) -> void:
	if mode in [WATER_MODE_RIVER, WATER_MODE_LAKE, WATER_MODE_FILL]:
		_water_mode = mode


func get_water_mode() -> String:
	return _water_mode


# Get current layer
func get_current_layer() -> int:
	return _current_layer


# Get river data
func get_river(river_id: int) -> Dictionary:
	if not _rivers.has(river_id):
		return {}
	var river: Dictionary = _rivers[river_id]
	if int(river.get("layer", 0)) != _current_layer:
		return {}
	return river


func get_lake(lake_id: int) -> Dictionary:
	if not _lakes.has(lake_id):
		return {}
	var lake: Dictionary = _lakes[lake_id]
	if int(lake.get("layer", 0)) != _current_layer:
		return {}
	return lake


# Serialize rivers to dictionary for saving
func serialize_rivers() -> Array:
	var serialized = []
	
	for river_id in _rivers:
		var river = _rivers[river_id]
		var river_data = {
			"id": river_id,
			"type": WATER_BODY_TYPE_RIVER,
			"name": river["name"],
			"layer": river.get("layer", 0),
			"curve_points": [],
			"widths": river["widths"],
			"average_depth": river.get("average_depth", 15.0),
		}
		
		# Serialize curve points
		for i in range(river["curve"].get_point_count()):
			var pos = river["curve"].get_point_position(i)
			var in_handle = river["curve"].get_point_in(i)
			var out_handle = river["curve"].get_point_out(i)
			
			river_data["curve_points"].append({
				"position": {"x": pos.x, "y": pos.y, "z": pos.z},
				"in": {"x": in_handle.x, "y": in_handle.y, "z": in_handle.z},
				"out": {"x": out_handle.x, "y": out_handle.y, "z": out_handle.z},
			})
		
		serialized.append(river_data)
	
	return serialized


func serialize_lakes() -> Array:
	var serialized: Array = []
	for lake_id in _lakes:
		var lake: Dictionary = _lakes[lake_id]
		var points_data: Array = []
		for p in lake.get("points", []):
			if p is Vector3:
				var pv: Vector3 = p
				points_data.append({"x": pv.x, "y": pv.y, "z": pv.z})
		serialized.append({
			"id": lake_id,
			"type": lake.get("type", WATER_BODY_TYPE_LAKE),
			"name": lake.get("name", "Lake"),
			"layer": int(lake.get("layer", 0)),
			"water_level": float(lake.get("water_level", 0.0)),
			"average_depth": float(lake.get("average_depth", 12.0)),
			"points": points_data,
		})
	return serialized


func serialize_water_bodies() -> Dictionary:
	return {
		"rivers": serialize_rivers(),
		"lakes": serialize_lakes(),
	}


# Deserialize rivers from saved data
func deserialize_rivers(river_data_array: Array) -> void:
	# Clear existing rivers
	for river_id in _rivers.keys():
		delete_river(river_id)
	
	for river_data in river_data_array:
		var layer = river_data.get("layer", 0)
		var _new_river = create_river(river_data.get("name", "River"), layer)
		var river_id = river_data["id"]
		
		# Restore curve
		var curve = _rivers[river_id]["curve"]
		curve.clear_points()
		
		for point_data in river_data.get("curve_points", []):
			var pos = Vector3(
				point_data["position"]["x"],
				point_data["position"]["y"],
				point_data["position"]["z"]
			)
			var in_h = Vector3(
				point_data["in"]["x"],
				point_data["in"]["y"],
				point_data["in"]["z"]
			)
			var out_h = Vector3(
				point_data["out"]["x"],
				point_data["out"]["y"],
				point_data["out"]["z"]
			)
			curve.add_point(pos, in_h, out_h)
		
		# Restore widths
		_rivers[river_id]["widths"] = river_data.get("widths", [2.0, 2.0])
		_rivers[river_id]["average_depth"] = float(river_data.get("average_depth", 15.0))
		_apply_river_material_settings(river_id)
		
		_regenerate_river_mesh(river_id)
	_refresh_layer_visibility()


func deserialize_lakes(lake_data_array: Array) -> void:
	for lake_id in _lakes.keys():
		delete_lake(lake_id)
	for lake_data in lake_data_array:
		var layer: int = int(lake_data.get("layer", 0))
		var type_name: String = str(lake_data.get("type", WATER_BODY_TYPE_LAKE))
		var center := Vector3.ZERO
		if lake_data.has("points") and (lake_data.get("points") as Array).size() > 0:
			var fp: Dictionary = (lake_data.get("points") as Array)[0]
			center = Vector3(float(fp.get("x", 0.0)), float(fp.get("y", 0.0)), float(fp.get("z", 0.0)))
		var node: Node = create_lake(str(lake_data.get("name", "Lake")), center, 6.0, layer, type_name)
		if not (node is MeshInstance3D) or not node.has_meta("lake_id"):
			continue
		var lake_id: int = int(node.get_meta("lake_id"))
		if not _lakes.has(lake_id):
			continue
		var restored_points: Array = []
		for point_data in lake_data.get("points", []):
			if point_data is Dictionary:
				restored_points.append(Vector3(
					float(point_data.get("x", 0.0)),
					float(point_data.get("y", 0.0)),
					float(point_data.get("z", 0.0))
				))
		if restored_points.size() >= 3:
			_lakes[lake_id]["points"] = restored_points
		_lakes[lake_id]["water_level"] = float(lake_data.get("water_level", center.y))
		_lakes[lake_id]["average_depth"] = float(lake_data.get("average_depth", 12.0))
		_regenerate_lake_mesh(lake_id)
	_refresh_layer_visibility()


func deserialize_water_bodies(data: Dictionary) -> void:
	deserialize_rivers(data.get("rivers", []))
	deserialize_lakes(data.get("lakes", []))
