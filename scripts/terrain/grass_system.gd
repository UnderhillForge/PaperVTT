extends Node3D
class_name GrassSystem

@export_group("Map Settings")
@export var map_size: Vector2 = Vector2(256, 256)
@export var chunk_size: float = 16.0
@export var terrain_node: NodePath

@export_group("Grass Settings")
@export var blades_per_chunk: int = 2000
@export var density_scale: float = 1.0
@export var grass_material: ShaderMaterial
@export var view_distance: float = 100.0
@export var lod_distance: float = 50.0


@export_group("Shader Settings")
@export var wind_strength: float = 0.5
@export var wind_speed: float = 1.0
@export var wind_direction_deg: float = 45.0
@export var grass_height: float = 1.0
@export var sway_amount: float = 0.2
@export var base_color: Color = Color(0.2, 0.5, 0.1)
@export var tip_color: Color = Color(0.5, 0.8, 0.2)
@export var noise_strength: float = 0.3

var _grass_meshes: Array[Mesh] = []
var _chunks: Dictionary = {}
var _player: Node3D
var _initialized: bool = false
var _density_map: Image
var _color_map: Image  # Stores RGB colors per pixel for per-location grass color
var _chunk_colors: Dictionary = {}  # Maps chunk coords to dominant color
var _material_cache: Dictionary = {}  # Cache of materials per color (as Color key)
var _current_stroke_color: Color = Color(0.2, 0.5, 0.1)  # Default green, used for new paintings

func _ready():
	_load_grass_meshes()
	_player = get_viewport().get_camera_3d()

func _process(_delta):
	if not _initialized: return
	if not _player:
		_player = get_viewport().get_camera_3d()
		if not _player: return
	_update_visible_chunks()

func initialize(size: Vector2, d_map: Image = null):
	map_size = size
	if d_map:
		_density_map = d_map
	else:
		_density_map = Image.create(int(map_size.x), int(map_size.y), false, Image.FORMAT_RF)
		# Start with no grass; painting tools add density where the GM wants it.
		_density_map.fill(Color(0, 0, 0, 1))
	
	# Initialize color map with default grass color
	_color_map = Image.create(int(map_size.x), int(map_size.y), false, Image.FORMAT_RGB8)
	_color_map.fill(_current_stroke_color)
	
	_clear_chunks()
	_initialized = true
	_update_visible_chunks()


func clear_all() -> void:
	"""Remove all painted grass density and clear visible chunk instances."""
	if _density_map != null:
		_density_map.fill(Color(0, 0, 0, 1))
	if _color_map != null:
		_color_map.fill(_current_stroke_color)
	_material_cache.clear()
	_clear_chunks()


func _init_shader_material():
	if not grass_material:
		grass_material = ShaderMaterial.new()
		var shader_res = load("res://shaders/grass.gdshader")
		if shader_res:
			grass_material.shader = shader_res
			_update_shader_params()
		else:
			push_error("GrassSystem: Could not load grass shader.")

func _update_shader_params():
	if not grass_material: return
	grass_material.set_shader_parameter("wind_strength", wind_strength)
	grass_material.set_shader_parameter("wind_speed", wind_speed)
	var wind_dir = Vector2(cos(deg_to_rad(wind_direction_deg)), sin(deg_to_rad(wind_direction_deg)))
	grass_material.set_shader_parameter("wind_direction", wind_dir)
	grass_material.set_shader_parameter("grass_height", grass_height)
	grass_material.set_shader_parameter("sway_amount", sway_amount)
	grass_material.set_shader_parameter("base_color", base_color)
	grass_material.set_shader_parameter("tip_color", tip_color)
	grass_material.set_shader_parameter("noise_strength", noise_strength)

func _load_grass_meshes():
	_init_shader_material()
	var paths = ["res://assets/meshes/GrassMeshes/grass.glb", "res://assets/meshes/GrassMeshes/grass2.glb"]
	for path in paths:
		if not ResourceLoader.exists(path):
			continue
		var resource = load(path)
		if resource is Mesh:
			_grass_meshes.append(resource)
		elif resource is PackedScene:
			var extracted = _extract_mesh_from_scene(resource)
			if extracted:
				_grass_meshes.append(extracted)
	if _grass_meshes.size() == 0: push_error("GrassSystem: No meshes loaded.")

func _extract_mesh_from_scene(scene_res: PackedScene) -> Mesh:
	# Imported GLB assets are often PackedScenes; pull the first mesh for MultiMesh use.
	var root = scene_res.instantiate()
	if root == null:
		return null
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and node.mesh:
			found = node.mesh
			break
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	root.free()
	return found

func _get_random_grass_mesh() -> Mesh:
	if _grass_meshes.size() == 0: return null
	return _grass_meshes[randi() % _grass_meshes.size()]

func _update_visible_chunks():
	var p_pos = _player.global_position
	var px = floor(p_pos.x / chunk_size)
	var pz = floor(p_pos.z / chunk_size)
	var radius = ceil(view_distance / chunk_size)
	var current_chunks = []
	for x in range(int(px - radius), int(px + radius + 1)):
		for z in range(int(pz - radius), int(pz + radius + 1)):
			var coords = Vector2i(x, z)
			current_chunks.append(coords)
			if not _chunks.has(coords): _create_chunk(coords)
	var to_remove = []
	for coords in _chunks.keys():
		if coords not in current_chunks: to_remove.append(coords)
	for coords in to_remove:
		_chunks[coords].queue_free()
		_chunks.erase(coords)

func _create_chunk(coords: Vector2i):
	var chunk = MultiMeshInstance3D.new()
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh = _get_random_grass_mesh()
	if not mesh: return
	mm.mesh = mesh
	mm.instance_count = 0 
	chunk.multimesh = mm
	
	# Use colored material for this chunk
	var chunk_color = _get_dominant_chunk_color(coords)
	var colored_material = _get_or_create_material(chunk_color)
	chunk.material_override = colored_material
	
	add_child(chunk)
	_chunks[coords] = chunk
	_rebuild_chunk(coords)

func _rebuild_chunk(coords: Vector2i):
	var chunk = _chunks[coords]
	var mm = chunk.multimesh
	var instances = []
	var count = int(blades_per_chunk * density_scale)
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(coords)
	for i in range(count):
		var lx = rng.randf_range(0, chunk_size)
		var lz = rng.randf_range(0, chunk_size)
		var gx = coords.x * chunk_size + lx
		var gz = coords.y * chunk_size + lz
		if gx < 0 or gx >= map_size.x or gz < 0 or gz >= map_size.y: continue
		var d = _density_map.get_pixel(int(gx), int(gz)).r
		if rng.randf() > d: continue
		var pos = Vector3(gx, 0, gz)
		var blade_basis = Basis().rotated(Vector3.UP, rng.randf_range(0, TAU))
		var scale_val = rng.randf_range(0.6, 1.2)
		blade_basis = blade_basis.scaled(Vector3(scale_val, scale_val, scale_val))
		instances.append(Transform3D(blade_basis, pos))
	mm.instance_count = instances.size()
	for i in range(instances.size()): mm.set_instance_transform(i, instances[i])

func apply_brush(mode: String, world_pos: Vector3, brush_size: float, brush_strength: float):
	var pos = Vector2(world_pos.x, world_pos.z)
	var radius = brush_size
	var strength = brush_strength
	if mode == "grasserase":
		strength = -strength
		
	var start_x = max(0, int(pos.x - radius))
	var end_x = min(int(map_size.x) - 1, int(pos.x + radius))
	var start_z = max(0, int(pos.y - radius))
	var end_z = min(int(map_size.y) - 1, int(pos.y + radius))
	
	var affected_chunks = []
	for x in range(start_x, end_x + 1):
		for z in range(start_z, end_z + 1):
			var dist = pos.distance_to(Vector2(x, z))
			if dist <= radius:
				var falloff = 1.0 - (dist / radius)
				var current_val = _density_map.get_pixel(x, z).r
				var val = clamp(current_val + strength * falloff, 0.0, 1.0)
				_density_map.set_pixel(x, z, Color(val, 0, 0, 1))
				
				# Paint the stroke color to the color map (if painting, not erasing)
				if strength > 0.0:
					_color_map.set_pixel(x, z, _current_stroke_color)
				
				var cx = int(floor(float(x) / chunk_size))
				var cz = int(floor(float(z) / chunk_size))
				var c = Vector2i(cx, cz)
				if not c in affected_chunks:
					affected_chunks.append(c)
	
	for coords in affected_chunks:
		if _chunks.has(coords):
			# Update chunk material if color changed
			_chunk_colors.erase(coords)  # Clear cached color
			_rebuild_chunk(coords)

func set_density_scale(val: float):
	density_scale = val
	_clear_chunks()
	_update_visible_chunks()

func set_view_distance(val: float):
	view_distance = val

func set_base_color(color: Color):
	base_color = color
	_update_shader_params()

func set_tip_color(color: Color):
	tip_color = color
	_update_shader_params()

func set_sway_amount(val: float):
	sway_amount = val
	_update_shader_params()

func set_noise_strength(val: float):
	noise_strength = val
	_update_shader_params()

func set_grass_height(val: float):
	grass_height = val
	_update_shader_params()

func set_wind_strength(val: float):
	wind_strength = val
	_update_shader_params()

func set_wind_direction_deg(val: float):
	wind_direction_deg = val
	_update_shader_params()

func set_stroke_color(color: Color):
	"""Set the color used for new grass painting strokes."""
	_current_stroke_color = color

func get_stroke_color() -> Color:
	"""Get the current stroke color."""
	return _current_stroke_color

func _get_or_create_material(color: Color) -> ShaderMaterial:
	"""Get or create a material instance with the given color."""
	# Use color as a key in the cache
	var color_key = color
	if _material_cache.has(color_key):
		return _material_cache[color_key]
	
	# Create a new material instance with this color
	var mat = grass_material.duplicate() as ShaderMaterial
	mat.set_shader_parameter("base_color", Vector3(color.r, color.g, color.b) * 0.5)  # Darker for base
	mat.set_shader_parameter("tip_color", color)  # Use stroke color for tip
	
	_material_cache[color_key] = mat
	return mat

func _get_dominant_chunk_color(coords: Vector2i) -> Color:
	"""Sample the color map to get the dominant color in a chunk region."""
	if _chunk_colors.has(coords):
		return _chunk_colors[coords]
	
	var chunk_x_start = int(coords.x * chunk_size)
	var chunk_z_start = int(coords.y * chunk_size)
	var chunk_x_end = min(int(chunk_x_start + chunk_size), int(map_size.x))
	var chunk_z_end = min(int(chunk_z_start + chunk_size), int(map_size.y))
	
	# Sample the center of the chunk
	var sample_x = int((chunk_x_start + chunk_x_end) / 2.0)
	var sample_z = int((chunk_z_start + chunk_z_end) / 2.0)
	
	if sample_x >= 0 and sample_x < int(map_size.x) and sample_z >= 0 and sample_z < int(map_size.y):
		var color = _color_map.get_pixel(sample_x, sample_z)
		_chunk_colors[coords] = color
		return color
	
	return _current_stroke_color

func _clear_chunks():
	for chunk in _chunks.values(): chunk.queue_free()
	_chunks.clear()
	_chunk_colors.clear()
