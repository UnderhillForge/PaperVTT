# Water System - Main coordinator for PaperVTT river/water management
# Manages river creation, editing, rendering, and persistence
# Integrates with world layer system and main_controller

extends Node

class_name WaterSystem

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
		"water_color": Color(1.0, 1.0, 1.0),
		"shallow_color": Color(0.26, 0.68, 0.74),
		"deep_color": Color(0.05, 0.23, 0.34),
		"water_depth": 7.5,
		"flow_speed": 0.18,
		"wave_strength": 0.14,
		"normal_scale": 2.0,
		"ripple_mix": 0.58,
		"refraction_strength": 0.016,
		"refraction_mix": 0.18,
		"roughness_value": 0.22,
		"specular_value": 0.18,
		"fresnel_power": 4.0,
		"foam_color": Color(0.95, 0.98, 1.0, 1.0),
		"foam_amount": 0.12,
		"edge_foam_distance": 0.40,
		"alpha_shallow": 0.74,
		"alpha_deep": 0.86,
		"edge_softness": 0.24,
		"depth_scale": 88.0,
	},
	"deep_river": {
		"water_color": Color(1.0, 1.0, 1.0),
		"shallow_color": Color(0.20, 0.54, 0.62),
		"deep_color": Color(0.04, 0.17, 0.28),
		"water_depth": 11.5,
		"flow_speed": 0.24,
		"wave_strength": 0.18,
		"normal_scale": 2.4,
		"ripple_mix": 0.52,
		"refraction_strength": 0.012,
		"refraction_mix": 0.15,
		"roughness_value": 0.24,
		"specular_value": 0.16,
		"fresnel_power": 4.8,
		"foam_color": Color(0.95, 0.98, 1.0, 1.0),
		"foam_amount": 0.16,
		"edge_foam_distance": 0.48,
		"alpha_shallow": 0.76,
		"alpha_deep": 0.88,
		"edge_softness": 0.20,
		"depth_scale": 72.0,
	},
}

# River configuration
const DEFAULT_PARAMETERS = {
	river_step_length_divs = 1,
	river_step_width_divs = 1,
	river_smoothness = 0.5,
	river_width_default = 2.0,
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
	mat.set_shader_parameter("albedo_color", Color(0.15, 0.48, 0.58, 1.0))
	
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
	var depth_value: float = float(river.get("average_depth", 7.5))
	var preset: Dictionary = WATER_PRESETS.get(_current_water_preset, WATER_PRESETS[DEFAULT_WATER_PRESET])
	mat.set_shader_parameter("water_color", preset.get("water_color", Color(1.0, 1.0, 1.0)))
	mat.set_shader_parameter("shallow_color", preset.get("shallow_color", Color(0.24, 0.64, 0.70)))
	mat.set_shader_parameter("deep_color", preset.get("deep_color", Color(0.06, 0.25, 0.35)))
	mat.set_shader_parameter("flow_speed", preset.get("flow_speed", 0.18))
	mat.set_shader_parameter("wave_strength", preset.get("wave_strength", 0.14))
	mat.set_shader_parameter("normal_scale", preset.get("normal_scale", 2.2))
	mat.set_shader_parameter("foam_amount", preset.get("foam_amount", 0.12))
	mat.set_shader_parameter("transparency", clampf(0.94 - depth_value / 40.0, 0.72, 0.90))
	mat.set_shader_parameter("average_depth", depth_value)
	mat.set_shader_parameter("albedo_color", Color(0.15, 0.48, 0.58, 1.0))


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
	var average_depth: float = float(river.get("average_depth", 7.5))
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
		"name": river_name,
		"layer": layer,
		"mesh_instance": river_mesh_instance,
		"curve": Curve3D.new(),
		"widths": [2.0, 2.0],
		"average_depth": 7.5,
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
	var depth_value: float = float(river.get("average_depth", 7.5))
	var surface_height_offset: float = clampf(0.05 + depth_value * 0.006, 0.05, 0.15)
	
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


func set_flow_speed(value: float) -> void:
	if _material_cache.has("default") and _material_cache["default"] is ShaderMaterial:
		(_material_cache["default"] as ShaderMaterial).set_shader_parameter("flow_speed", value)
	for river_id in _rivers:
		var mesh_instance: MeshInstance3D = _rivers[river_id]["mesh_instance"]
		if mesh_instance != null and mesh_instance.material_override is ShaderMaterial:
			(mesh_instance.material_override as ShaderMaterial).set_shader_parameter("flow_speed", value)


func set_water_color(color: Color) -> void:
	if _material_cache.has("default") and _material_cache["default"] is ShaderMaterial:
		(_material_cache["default"] as ShaderMaterial).set_shader_parameter("water_color", color)
	for river_id in _rivers:
		var mesh_instance: MeshInstance3D = _rivers[river_id]["mesh_instance"]
		if mesh_instance != null and mesh_instance.material_override is ShaderMaterial:
			(mesh_instance.material_override as ShaderMaterial).set_shader_parameter("water_color", color)


# Get all rivers
func get_rivers() -> Dictionary:
	return _rivers.duplicate()


# Get rivers on a specific world layer
func get_rivers_on_layer(layer: int) -> Dictionary:
	var layer_rivers = {}
	for river_id in _rivers:
		if _rivers[river_id].get("layer", 0) == layer:
			layer_rivers[river_id] = _rivers[river_id]
	return layer_rivers


# Set active world layer for new rivers
func set_current_layer(layer: int) -> void:
	_current_layer = layer


# Get current layer
func get_current_layer() -> int:
	return _current_layer


# Get river data
func get_river(river_id: int) -> Dictionary:
	return _rivers.get(river_id, {})


# Serialize rivers to dictionary for saving
func serialize_rivers() -> Array:
	var serialized = []
	
	for river_id in _rivers:
		var river = _rivers[river_id]
		var river_data = {
			"id": river_id,
			"name": river["name"],
			"layer": river.get("layer", 0),
			"curve_points": [],
			"widths": river["widths"],
			"average_depth": river.get("average_depth", 7.5),
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
		_rivers[river_id]["average_depth"] = float(river_data.get("average_depth", 7.5))
		_apply_river_material_settings(river_id)
		
		_regenerate_river_mesh(river_id)
