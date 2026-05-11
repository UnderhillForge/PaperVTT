class_name CustomHeightmapTerrain
extends Node3D

## Lightweight heightmap terrain.
## The mesh is a static flat PlaneMesh — no rebuild on brush strokes.
## A GPU vertex shader reads height_map to displace vertices and compute normals.
## Each brush stroke only uploads two small texture updates.

@export var map_size: float = 256.0
@export var grid_resolution: int = 128
@export var max_height: float = 24.0
@export var base_brush_color: Color = Color(0.30, 0.42, 0.28, 1.0)

@onready var terrain_mesh: MeshInstance3D = $TerrainMesh

var _height_image: Image = null
var _height_texture: ImageTexture = null
var _color_image: Image = null
var _color_texture: ImageTexture = null
var _shader_material: ShaderMaterial = null

const _SHADER_CODE := """
shader_type spatial;
render_mode depth_draw_always, cull_disabled;

uniform sampler2D height_map : filter_linear_mipmap;
uniform sampler2D color_map : source_color, filter_linear_mipmap;
uniform float max_height = 24.0;
uniform float map_size = 256.0;

void vertex() {
	float h_raw = texture(height_map, UV).r;
	VERTEX.y = (h_raw - 0.5) * 2.0 * max_height;

	ivec2 sz = textureSize(height_map, 0);
	vec2 texel = vec2(1.0) / vec2(sz);
	float hl = texture(height_map, UV + vec2(-texel.x, 0.0)).r;
	float hr = texture(height_map, UV + vec2( texel.x, 0.0)).r;
	float hd = texture(height_map, UV + vec2(0.0, -texel.y)).r;
	float hu = texture(height_map, UV + vec2(0.0,  texel.y)).r;
	float world_texel = map_size / float(sz.x);
	NORMAL = normalize(vec3(
		(hl - hr) * max_height / world_texel,
		1.0,
		(hd - hu) * max_height / world_texel
	));
}

void fragment() {
	ALBEDO = texture(color_map, UV).rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.0;
}
"""

func _ready() -> void:
	_build_images_if_needed()
	_rebuild_plane_mesh()

func set_mesh_size(size: int) -> void:
	map_size = clampf(float(size), 64.0, 1024.0)
	_rebuild_plane_mesh()
	if _shader_material != null:
		_shader_material.set_shader_parameter("map_size", map_size)

func set_vertex_spacing(spacing: float) -> void:
	var safe_spacing: float = maxf(spacing, 1.0)
	grid_resolution = clampi(int(round(map_size / safe_spacing)), 32, 256)
	_build_images_if_needed(true)
	_rebuild_plane_mesh()

func clear_colliders() -> void:
	# Kept for API compatibility with old terrain calls.
	pass

func initialize_new_map(seed: int) -> void:
	_build_images_if_needed(true)
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.016
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.35

	for y in range(_height_image.get_height()):
		for x in range(_height_image.get_width()):
			var n: float = noise.get_noise_2d(float(x), float(y))
			_height_image.set_pixel(x, y, Color(clampf(0.5 + n * 0.008, 0.0, 1.0), 0.0, 0.0, 1.0))
			_color_image.set_pixel(x, y, Color(0.29, 0.40, 0.27, 1.0))

	_upload_textures()

func apply_brush(tool_name: String, world_position: Vector3, brush_size: float, brush_strength: float, flatten_height: float = 0.0) -> void:
	if _height_image == null:
		return

	var uv: Vector2 = _world_to_uv(world_position.x, world_position.z)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return

	var res_f: float = float(grid_resolution)
	var center_x: int = clampi(int(round(uv.x * res_f)), 0, grid_resolution)
	var center_y: int = clampi(int(round(uv.y * res_f)), 0, grid_resolution)
	var radius_px: float = maxf((brush_size / map_size) * res_f, 1.5)
	var radius_sq: float = radius_px * radius_px

	var min_x: int = max(0, int(floor(float(center_x) - radius_px)) - 1)
	var max_x: int = min(grid_resolution, int(ceil(float(center_x) + radius_px)) + 1)
	var min_y: int = max(0, int(floor(float(center_y) - radius_px)) - 1)
	var max_y: int = min(grid_resolution, int(ceil(float(center_y) + radius_px)) + 1)

	var src_h: Image = _height_image.duplicate()
	var target_flat: float = _height_to_value(flatten_height)
	var safe_s: float = clampf(brush_strength, 0.01, 1.0)
	var paint_only: bool = (tool_name == "paint")
	var changed: bool = false

	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			var dx: float = float(px - center_x)
			var dy: float = float(py - center_y)
			var dsq: float = dx * dx + dy * dy
			if dsq > radius_sq:
				continue
			# Smoothstep cubic falloff — more natural feel than linear
			var t: float = 1.0 - sqrt(dsq) / radius_px
			var falloff: float = t * t * (3.0 - 2.0 * t)

			if paint_only:
				var c: Color = _color_image.get_pixel(px, py)
				_color_image.set_pixel(px, py, c.lerp(base_brush_color, 0.8 * safe_s * falloff))
				changed = true
				continue

			var cur: float = src_h.get_pixel(px, py).r
			var nxt: float = cur
			match tool_name:
				"raise":
					nxt = cur + 0.022 * safe_s * falloff
				"lower":
					nxt = cur - 0.022 * safe_s * falloff
				"flatten":
					nxt = lerpf(cur, target_flat, 0.9 * safe_s * falloff)
				"smooth":
					nxt = lerpf(cur, _neighbor_avg(src_h, px, py), 0.7 * safe_s * falloff)
				_:
					continue
			nxt = clampf(nxt, 0.0, 1.0)
			if absf(nxt - cur) > 0.000001:
				_height_image.set_pixel(px, py, Color(nxt, 0.0, 0.0, 1.0))
				changed = true

	if changed:
		_upload_textures()

func sample_height(x: float, z: float) -> float:
	if _height_image == null:
		return 0.0
	var uv: Vector2 = _world_to_uv(x, z)
	var px: int = clampi(int(round(uv.x * float(grid_resolution))), 0, grid_resolution)
	var py: int = clampi(int(round(uv.y * float(grid_resolution))), 0, grid_resolution)
	return _value_to_height(_height_image.get_pixel(px, py).r)

func get_height(world_position: Vector3) -> float:
	return sample_height(world_position.x, world_position.z)

func get_data() -> Object:
	return self

func serialize_state() -> Dictionary:
	if _height_image == null or _color_image == null:
		return {}
	var heights: Array[float] = []
	heights.resize((grid_resolution + 1) * (grid_resolution + 1))
	var colors: Array = []
	colors.resize((grid_resolution + 1) * (grid_resolution + 1))
	var idx: int = 0
	for y in range(_height_image.get_height()):
		for x in range(_height_image.get_width()):
			heights[idx] = _height_image.get_pixel(x, y).r
			var c: Color = _color_image.get_pixel(x, y)
			colors[idx] = [c.r, c.g, c.b, c.a]
			idx += 1
	return {
		"map_size": map_size,
		"grid_resolution": grid_resolution,
		"max_height": max_height,
		"base_brush_color": [base_brush_color.r, base_brush_color.g, base_brush_color.b, base_brush_color.a],
		"height_values": heights,
		"color_values": colors
	}

func load_state(data: Dictionary) -> void:
	if data.is_empty():
		return
	map_size = float(data.get("map_size", map_size))
	grid_resolution = clampi(int(data.get("grid_resolution", grid_resolution)), 32, 256)
	max_height = float(data.get("max_height", max_height))
	var bbc: Variant = data.get("base_brush_color", null)
	if bbc is Array and (bbc as Array).size() >= 4:
		base_brush_color = Color(float(bbc[0]), float(bbc[1]), float(bbc[2]), float(bbc[3]))

	_build_images_if_needed(true)
	var heights: Array = data.get("height_values", [])
	var colors: Array = data.get("color_values", [])
	var expected: int = (grid_resolution + 1) * (grid_resolution + 1)
	if heights.size() == expected:
		var idx_h: int = 0
		for y in range(_height_image.get_height()):
			for x in range(_height_image.get_width()):
				var hv: float = clampf(float(heights[idx_h]), 0.0, 1.0)
				_height_image.set_pixel(x, y, Color(hv, 0.0, 0.0, 1.0))
				idx_h += 1
	if colors.size() == expected:
		var idx_c: int = 0
		for y in range(_color_image.get_height()):
			for x in range(_color_image.get_width()):
				var cv: Variant = colors[idx_c]
				if cv is Array and (cv as Array).size() >= 4:
					_color_image.set_pixel(x, y, Color(float(cv[0]), float(cv[1]), float(cv[2]), float(cv[3])))
				idx_c += 1

	_upload_textures()
	_rebuild_plane_mesh()

func get_intersection(ray_origin: Vector3, ray_direction: Vector3, _use_collision: bool = true) -> Variant:
	if absf(ray_direction.y) < 0.000001:
		return null
	var half: float = map_size * 0.5

	# Clip t-range to terrain XZ AABB so we don't step through air forever.
	var t_min: float = 0.01
	var t_max: float = 2000.0
	for axis in [0, 2]:
		var orig: float = ray_origin[axis]
		var dir_a: float = ray_direction[axis]
		if absf(dir_a) > 0.00001:
			var t1: float = (-half - orig) / dir_a
			var t2: float = ( half - orig) / dir_a
			t_min = maxf(t_min, minf(t1, t2))
			t_max = minf(t_max, maxf(t1, t2))
		elif absf(orig) > half:
			return null
	if t_max < t_min:
		return null

	# Coarse 48-step march to find sign change, then 8-step binary refine.
	var steps: int = 48
	var dt: float = (t_max - t_min) / float(steps)
	var prev_t: float = t_min
	var prev_p: Vector3 = ray_origin + ray_direction * t_min
	var prev_above: bool = prev_p.y >= sample_height(prev_p.x, prev_p.z)

	for i in range(1, steps + 1):
		var t: float = t_min + float(i) * dt
		var p: Vector3 = ray_origin + ray_direction * t
		var above: bool = p.y >= sample_height(p.x, p.z)
		if prev_above and not above:
			var lo: float = prev_t
			var hi: float = t
			for _r in range(8):
				var mid: float = (lo + hi) * 0.5
				var mp: Vector3 = ray_origin + ray_direction * mid
				if mp.y >= sample_height(mp.x, mp.z):
					lo = mid
				else:
					hi = mid
			var hit: Vector3 = ray_origin + ray_direction * ((lo + hi) * 0.5)
			hit.y = sample_height(hit.x, hit.z)
			return hit
		prev_t = t
		prev_above = above

	# Flat-plane fallback for looking straight down at a very flat map.
	var t0: float = -ray_origin.y / ray_direction.y
	if t0 > 0.0:
		var hit: Vector3 = ray_origin + ray_direction * t0
		if absf(hit.x) <= half and absf(hit.z) <= half:
			hit.y = sample_height(hit.x, hit.z)
			return hit
	return null

func _build_images_if_needed(force_recreate: bool = false) -> void:
	var required_size: int = grid_resolution + 1
	if force_recreate or _height_image == null or _height_image.get_width() != required_size:
		_height_image = Image.create(required_size, required_size, false, Image.FORMAT_RF)
		_height_image.fill(Color(0.5, 0.0, 0.0, 1.0))
	if force_recreate or _color_image == null or _color_image.get_width() != required_size:
		_color_image = Image.create(required_size, required_size, false, Image.FORMAT_RGBA8)
		_color_image.fill(Color(0.29, 0.40, 0.27, 1.0))
	_upload_textures()

func _upload_textures() -> void:
	if _height_image == null or _color_image == null:
		return
	if _height_texture == null or _height_texture.get_width() != _height_image.get_width():
		_height_texture = ImageTexture.create_from_image(_height_image)
	else:
		_height_texture.update(_height_image)
	if _color_texture == null or _color_texture.get_width() != _color_image.get_width():
		_color_texture = ImageTexture.create_from_image(_color_image)
	else:
		_color_texture.update(_color_image)
	if _shader_material != null:
		_shader_material.set_shader_parameter("height_map", _height_texture)
		_shader_material.set_shader_parameter("color_map", _color_texture)

func _rebuild_plane_mesh() -> void:
	if terrain_mesh == null:
		return
	# Static flat PlaneMesh — subdivisions match height image resolution.
	# The GPU shader displaces vertices; no mesh rebuild needed per brush stroke.
	var plane := PlaneMesh.new()
	plane.size = Vector2(map_size, map_size)
	plane.subdivide_width = grid_resolution - 1
	plane.subdivide_depth = grid_resolution - 1
	terrain_mesh.mesh = plane
	_build_shader_material()

func _build_shader_material() -> void:
	if terrain_mesh == null:
		return
	if _shader_material == null:
		var shader := Shader.new()
		shader.code = _SHADER_CODE
		_shader_material = ShaderMaterial.new()
		_shader_material.shader = shader
	_shader_material.set_shader_parameter("max_height", max_height)
	_shader_material.set_shader_parameter("map_size", map_size)
	_shader_material.set_shader_parameter("height_map", _height_texture)
	_shader_material.set_shader_parameter("color_map", _color_texture)
	terrain_mesh.material_override = _shader_material

func _world_to_uv(x: float, z: float) -> Vector2:
	return Vector2((x / map_size) + 0.5, (z / map_size) + 0.5)

func _value_to_height(value: float) -> float:
	return (value - 0.5) * 2.0 * max_height

func _height_to_value(height: float) -> float:
	return clampf((height / (2.0 * max_height)) + 0.5, 0.0, 1.0)

func _neighbor_avg(src: Image, x: int, y: int) -> float:
	# 5×5 kernel for a smooth, round result.
	var sum: float = 0.0
	for oy in range(-2, 3):
		for ox in range(-2, 3):
			sum += src.get_pixel(clampi(x + ox, 0, grid_resolution), clampi(y + oy, 0, grid_resolution)).r
	return sum / 25.0
