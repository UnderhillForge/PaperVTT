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
@export var paint_resolution: int = 1024

@onready var terrain_mesh: MeshInstance3D = $TerrainMesh

var _height_image: Image = null
var _height_texture: ImageTexture = null
var _color_image: Image = null
var _color_texture: ImageTexture = null
var _normal_image: Image = null
var _normal_texture: ImageTexture = null
var _roughness_image: Image = null
var _roughness_texture: ImageTexture = null
var _shader_material: ShaderMaterial = null

var _dirty_height: bool = false
var _dirty_color: bool = false
var _dirty_normal: bool = false
var _dirty_roughness: bool = false
var _dirty_height_rect: Rect2i = Rect2i()
var _dirty_color_rect: Rect2i = Rect2i()
var _dirty_normal_rect: Rect2i = Rect2i()
var _dirty_roughness_rect: Rect2i = Rect2i()
var _pending_texture_upload: bool = false
var _upload_accum_sec: float = 0.0
var _texture_stroke_active: bool = false
var _texture_perf_mode: bool = true
var _defer_pbr_upload_during_stroke: bool = false

const _PAINT_UPLOAD_INTERVAL_IDLE_SEC: float = 1.0 / 30.0
const _PAINT_UPLOAD_INTERVAL_ACTIVE_SEC: float = 1.0 / 45.0
const _PAINT_UPLOAD_INTERVAL_ACTIVE_PERF_SEC: float = 1.0 / 24.0
const _MAX_TEXTURE_BRUSH_RADIUS: float = 42.0
const _MAX_TEXTURE_BRUSH_RADIUS_PERF: float = 26.0

const _SHADER_CODE := """
shader_type spatial;
render_mode depth_draw_always, cull_disabled;

uniform sampler2D height_map : filter_linear_mipmap;
uniform sampler2D color_map : source_color, filter_linear;
uniform sampler2D normal_map_paint : hint_normal, filter_linear;
uniform sampler2D roughness_map_paint : filter_linear;
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
	NORMAL_MAP = texture(normal_map_paint, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = clamp(texture(roughness_map_paint, UV).r, 0.06, 1.0);
	SPECULAR = 0.0;
}
"""

func _ready() -> void:
	_build_images_if_needed()
	_rebuild_plane_mesh()
	set_process(true)

func _process(delta: float) -> void:
	if not _pending_texture_upload:
		return
	_upload_accum_sec += delta
	var target_interval: float = _PAINT_UPLOAD_INTERVAL_IDLE_SEC
	if _texture_stroke_active:
		target_interval = _PAINT_UPLOAD_INTERVAL_ACTIVE_PERF_SEC if _texture_perf_mode else _PAINT_UPLOAD_INTERVAL_ACTIVE_SEC
	if _upload_accum_sec >= target_interval:
		_upload_accum_sec = 0.0
		_upload_textures(false)

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

func initialize_new_map(_seed: int) -> void:
	_build_images_if_needed(true)
	# Create completely flat terrain at neutral height (0.5)
	for y in range(_height_image.get_height()):
		for x in range(_height_image.get_width()):
			_height_image.set_pixel(x, y, Color(0.5, 0.0, 0.0, 1.0))
			_color_image.set_pixel(x, y, Color(0.29, 0.40, 0.27, 1.0))

	_upload_textures(true)

func apply_brush(tool_name: String, world_position: Vector3, brush_size: float, brush_strength: float, flatten_height: float = 0.0, cliff_mode: bool = false, overhang_amount: float = 0.3) -> void:
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
				var paint_px: int = int(round((float(px) / float(grid_resolution)) * float(_color_image.get_width() - 1)))
				var paint_py: int = int(round((float(py) / float(grid_resolution)) * float(_color_image.get_height() - 1)))
				paint_px = clampi(paint_px, 0, _color_image.get_width() - 1)
				paint_py = clampi(paint_py, 0, _color_image.get_height() - 1)
				var c: Color = _color_image.get_pixel(paint_px, paint_py)
				_color_image.set_pixel(paint_px, paint_py, c.lerp(base_brush_color, 0.8 * safe_s * falloff))
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

	# Apply cliff mode texture blending if enabled and we modified heights
	if changed and tool_name == "raise" and cliff_mode:
		_apply_cliff_mode_textures(min_x, max_x, min_y, max_y, overhang_amount)

	if changed:
		_mark_dirty_height(min_x, max_x, min_y, max_y)
		if tool_name == "paint" or (tool_name == "raise" and cliff_mode):
			var color_res: int = _color_image.get_width() - 1
			var cmin_x: int = int(floor((float(min_x) / float(grid_resolution)) * float(color_res)))
			var cmax_x: int = int(ceil((float(max_x) / float(grid_resolution)) * float(color_res)))
			var cmin_y: int = int(floor((float(min_y) / float(grid_resolution)) * float(color_res)))
			var cmax_y: int = int(ceil((float(max_y) / float(grid_resolution)) * float(color_res)))
			_mark_dirty_color(clampi(cmin_x, 0, color_res), clampi(cmax_x, 0, color_res), clampi(cmin_y, 0, color_res), clampi(cmax_y, 0, color_res))
		_request_texture_upload()

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
	colors.resize(_color_image.get_width() * _color_image.get_height())
	var idx: int = 0
	for y in range(_height_image.get_height()):
		for x in range(_height_image.get_width()):
			heights[idx] = _height_image.get_pixel(x, y).r
			var c: Color = _color_image.get_pixel(clampi(x, 0, _color_image.get_width() - 1), clampi(y, 0, _color_image.get_height() - 1))
			colors[idx] = [c.r, c.g, c.b, c.a]
			idx += 1
	for y in range(_color_image.get_height()):
		for x in range(_color_image.get_width()):
			if idx >= colors.size():
				break
			var c2: Color = _color_image.get_pixel(x, y)
			colors[idx] = [c2.r, c2.g, c2.b, c2.a]
			idx += 1
	return {
		"map_size": map_size,
		"grid_resolution": grid_resolution,
		"paint_resolution": paint_resolution,
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
	paint_resolution = clampi(int(data.get("paint_resolution", paint_resolution)), 512, 2048)
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
	if colors.size() >= expected:
		var idx_c: int = 0
		for y in range(_color_image.get_height()):
			for x in range(_color_image.get_width()):
				if idx_c >= colors.size():
					break
				var cv: Variant = colors[idx_c]
				if cv is Array and (cv as Array).size() >= 4:
					_color_image.set_pixel(x, y, Color(float(cv[0]), float(cv[1]), float(cv[2]), float(cv[3])))
				idx_c += 1

	_upload_textures(true)
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
	var paint_size: int = maxi(required_size, clampi(paint_resolution, 512, 2048))
	if force_recreate or _height_image == null or _height_image.get_width() != required_size:
		_height_image = Image.create(required_size, required_size, false, Image.FORMAT_RF)
		_height_image.fill(Color(0.5, 0.0, 0.0, 1.0))
	if force_recreate or _color_image == null or _color_image.get_width() != paint_size:
		_color_image = Image.create(paint_size, paint_size, false, Image.FORMAT_RGBA8)
		_color_image.fill(Color(0.29, 0.40, 0.27, 1.0))
	if force_recreate or _normal_image == null or _normal_image.get_width() != paint_size:
		_normal_image = Image.create(paint_size, paint_size, false, Image.FORMAT_RGBA8)
		_normal_image.fill(Color(0.5, 0.5, 1.0, 1.0))
	if force_recreate or _roughness_image == null or _roughness_image.get_width() != paint_size:
		_roughness_image = Image.create(paint_size, paint_size, false, Image.FORMAT_RF)
		_roughness_image.fill(Color(0.92, 0.0, 0.0, 1.0))
	_upload_textures(true)

func _merge_dirty_rect(current: Rect2i, incoming: Rect2i) -> Rect2i:
	if incoming.size.x <= 0 or incoming.size.y <= 0:
		return current
	if current.size.x <= 0 or current.size.y <= 0:
		return incoming
	return current.merge(incoming)

func _mark_dirty_height(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	_dirty_height = true
	_dirty_height_rect = _merge_dirty_rect(_dirty_height_rect, Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))

func _mark_dirty_color(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	_dirty_color = true
	_dirty_color_rect = _merge_dirty_rect(_dirty_color_rect, Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))

func _mark_dirty_normal(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	_dirty_normal = true
	_dirty_normal_rect = _merge_dirty_rect(_dirty_normal_rect, Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))

func _mark_dirty_roughness(min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	_dirty_roughness = true
	_dirty_roughness_rect = _merge_dirty_rect(_dirty_roughness_rect, Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1))

func _request_texture_upload() -> void:
	_pending_texture_upload = true

func _upload_textures(force_all: bool = false) -> void:
	if _height_image == null or _color_image == null or _normal_image == null or _roughness_image == null:
		return
	var update_height: bool = force_all or _dirty_height
	var update_color: bool = force_all or _dirty_color
	var update_normal: bool = force_all or (_dirty_normal and (not _defer_pbr_upload_during_stroke or not _texture_stroke_active))
	var update_roughness: bool = force_all or (_dirty_roughness and (not _defer_pbr_upload_during_stroke or not _texture_stroke_active))
	if _height_texture == null or _height_texture.get_width() != _height_image.get_width():
		_height_texture = ImageTexture.create_from_image(_height_image)
		update_height = false
	elif update_height:
		_height_texture.update(_height_image)
	if _color_texture == null or _color_texture.get_width() != _color_image.get_width():
		_color_texture = ImageTexture.create_from_image(_color_image)
		update_color = false
	elif update_color:
		_color_texture.update(_color_image)
	if _normal_texture == null or _normal_texture.get_width() != _normal_image.get_width():
		_normal_texture = ImageTexture.create_from_image(_normal_image)
		update_normal = false
	elif update_normal:
		_normal_texture.update(_normal_image)
	if _roughness_texture == null or _roughness_texture.get_width() != _roughness_image.get_width():
		_roughness_texture = ImageTexture.create_from_image(_roughness_image)
		update_roughness = false
	elif update_roughness:
		_roughness_texture.update(_roughness_image)
	if _shader_material != null:
		_shader_material.set_shader_parameter("height_map", _height_texture)
		_shader_material.set_shader_parameter("color_map", _color_texture)
		_shader_material.set_shader_parameter("normal_map_paint", _normal_texture)
		_shader_material.set_shader_parameter("roughness_map_paint", _roughness_texture)
	if force_all:
		_dirty_height = false
		_dirty_color = false
		_dirty_normal = false
		_dirty_roughness = false
		_dirty_height_rect = Rect2i()
		_dirty_color_rect = Rect2i()
		_dirty_normal_rect = Rect2i()
		_dirty_roughness_rect = Rect2i()
		_pending_texture_upload = false
		return
	if update_height:
		_dirty_height = false
		_dirty_height_rect = Rect2i()
	if update_color:
		_dirty_color = false
		_dirty_color_rect = Rect2i()
	if update_normal:
		_dirty_normal = false
		_dirty_normal_rect = Rect2i()
	if update_roughness:
		_dirty_roughness = false
		_dirty_roughness_rect = Rect2i()
	_pending_texture_upload = _dirty_height or _dirty_color or _dirty_normal or _dirty_roughness

func set_texture_paint_performance_mode(enabled: bool) -> void:
	_texture_perf_mode = enabled
	_defer_pbr_upload_during_stroke = enabled

func begin_texture_stroke(perf_mode: bool = true, _brush_size: float = 10.0) -> void:
	_texture_stroke_active = true
	set_texture_paint_performance_mode(perf_mode)

func end_texture_stroke() -> void:
	_texture_stroke_active = false
	if _dirty_height or _dirty_color or _dirty_normal or _dirty_roughness:
		_upload_textures(false)

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
	_shader_material.set_shader_parameter("normal_map_paint", _normal_texture)
	_shader_material.set_shader_parameter("roughness_map_paint", _roughness_texture)
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

func _fract(v: float) -> float:
	return v - floor(v)

func _hash2(p: Vector2) -> float:
	var h: float = sin(p.dot(Vector2(127.1, 311.7))) * 43758.5453123
	return _fract(h)

func _value_noise2(p: Vector2) -> float:
	var i: Vector2 = Vector2(floor(p.x), floor(p.y))
	var f: Vector2 = p - i
	var u: Vector2 = Vector2(f.x * f.x * (3.0 - 2.0 * f.x), f.y * f.y * (3.0 - 2.0 * f.y))
	var a: float = _hash2(i)
	var b: float = _hash2(i + Vector2(1.0, 0.0))
	var c: float = _hash2(i + Vector2(0.0, 1.0))
	var d: float = _hash2(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)

func apply_texture_brush(world_position: Vector3, albedo_image: Image, normal_image: Image, roughness_image: Image, height_image: Image, ao_image: Image, brush_size: float, strength: float, tile_size_m: float = 4.0, density: float = 0.75, edge_softness: float = 0.78, coverage_limit: float = 0.75, stroke_offset: Vector2 = Vector2.ZERO, stroke_rotation_deg: float = 0.0, stroke_scale: float = 1.0, exposure: float = 0.95, shape_mode: String = "circle", shape_variation: float = 0.35, shape_seed: float = 0.0, shape_variant: int = 0) -> void:
	if _color_image == null or albedo_image == null:
		return
	
	var uv: Vector2 = _world_to_uv(world_position.x, world_position.z)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return
	
	var paint_resolution_local: int = _color_image.get_width() - 1
	var res_f: float = float(paint_resolution_local)
	var center_x: int = clampi(int(round(uv.x * res_f)), 0, paint_resolution_local)
	var center_y: int = clampi(int(round(uv.y * res_f)), 0, paint_resolution_local)
	var radius_px: float = maxf((brush_size / map_size) * res_f, 1.5)
	var radius_sq: float = radius_px * radius_px
	
	var min_x: int = max(0, int(floor(float(center_x) - radius_px)) - 1)
	var max_x: int = min(paint_resolution_local, int(ceil(float(center_x) + radius_px)) + 1)
	var min_y: int = max(0, int(floor(float(center_y) - radius_px)) - 1)
	var max_y: int = min(paint_resolution_local, int(ceil(float(center_y) + radius_px)) + 1)
	
	var safe_s: float = clampf(strength, 0.01, 1.0)
	var safe_density: float = clampf(density, 0.05, 2.0)
	var safe_edge_softness: float = clampf(edge_softness, 0.0, 1.0)
	var safe_coverage: float = clampf(coverage_limit, 0.05, 1.0)
	var safe_tile: float = maxf(tile_size_m, 0.1)
	var safe_scale: float = clampf(stroke_scale, 0.4, 2.5)
	var safe_exposure: float = clampf(exposure, 0.4, 1.6)
	var safe_shape_variation: float = clampf(shape_variation, 0.0, 1.0)
	var use_irregular: bool = (shape_mode == "irregular" or shape_mode == "varied") and safe_shape_variation > 0.001
	var variant_id: int = shape_variant % 3
	var paint_step: int = 2 if (_texture_perf_mode and _texture_stroke_active and radius_px > 24.0) else 1
	var write_pbr: bool = not (_texture_perf_mode and _texture_stroke_active)
	var noise_freq: float = 4.8
	var noise_amp: float = 0.09
	var edge_warp_strength: float = 1.0
	if variant_id == 1:
		noise_freq = 6.8
		noise_amp = 0.12
		edge_warp_strength = 0.85
	elif variant_id == 2:
		noise_freq = 3.9
		noise_amp = 0.14
		edge_warp_strength = 1.15
	noise_amp *= safe_shape_variation
	var strength_weight: float = lerpf(0.08, 1.0, smoothstep(0.0, 1.0, safe_s))
	var density_weight: float = pow(safe_density, 1.15)
	var fade_start: float = lerpf(0.90, 0.04, safe_edge_softness)
	var angle: float = deg_to_rad(stroke_rotation_deg)
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var tex_w: int = albedo_image.get_width()
	var tex_h: int = albedo_image.get_height()
	var changed: bool = false
	var base_rgb: Vector3 = Vector3(base_brush_color.r, base_brush_color.g, base_brush_color.b)
	var center_world_x: float = world_position.x
	var center_world_z: float = world_position.z
	
	for py in range(min_y, max_y + 1, paint_step):
		for px in range(min_x, max_x + 1, paint_step):
			var dx: float = float(px - center_x)
			var dy: float = float(py - center_y)
			var dsq: float = dx * dx + dy * dy
			if dsq > radius_sq:
				continue
			
			# Edge softness controls where fade begins; smoothstep keeps rings out.
			var dist_n: float = sqrt(dsq) / radius_px
			if use_irregular:
				var edge_zone: float = smoothstep(0.28, 0.98, dist_n)
				var local_uv: Vector2 = Vector2(dx / radius_px, dy / radius_px)
				var p: Vector2 = local_uv * noise_freq + Vector2(shape_seed * 0.13 + float(variant_id) * 7.1, shape_seed * 0.21 - float(variant_id) * 5.3)
				var n0: float = _value_noise2(p)
				var n1: float = _value_noise2(p * 1.9 + Vector2(9.7, 2.6))
				var n: float = (n0 * 0.65 + n1 * 0.35) - 0.5
				dist_n = clampf(dist_n + n * noise_amp * edge_zone * edge_warp_strength, 0.0, 1.0)
			var soft_falloff: float = 1.0 - smoothstep(fade_start, 1.0, dist_n)
			var center_hold: float = 1.0 - smoothstep(0.0, 0.62, dist_n)
			var falloff: float = clampf(soft_falloff * (0.78 + center_hold * 0.22), 0.0, 1.0)
			
			# Convert pixel to world position
			var world_x: float = (float(px) / res_f) * map_size - map_size * 0.5
			var world_z: float = (float(py) / res_f) * map_size - map_size * 0.5
			
			# Rotate/scale UV projection around stroke center, then jitter with per-stroke offset.
			var rel_x: float = world_x - center_world_x
			var rel_z: float = world_z - center_world_z
			var rot_x: float = (rel_x * ca - rel_z * sa) / safe_scale
			var rot_z: float = (rel_x * sa + rel_z * ca) / safe_scale
			var proj_x: float = center_world_x + rot_x + stroke_offset.x
			var proj_z: float = center_world_z + rot_z + stroke_offset.y

			# Sample texture with stable world-space tiling.
			var tile_u: float = fposmod(proj_x / safe_tile, 1.0)
			var tile_v: float = fposmod(proj_z / safe_tile, 1.0)
			var tex_x: int = clampi(int(tile_u * float(tex_w)), 0, tex_w - 1)
			var tex_y: int = clampi(int(tile_v * float(tex_h)), 0, tex_h - 1)
			var tex_color: Color = albedo_image.get_pixel(tex_x, tex_y)
			var tex_normal: Color = Color(0.5, 0.5, 1.0, 1.0)
			if normal_image != null:
				tex_normal = normal_image.get_pixel(tex_x, tex_y)
			var tex_roughness: float = 0.9
			if roughness_image != null:
				tex_roughness = roughness_image.get_pixel(tex_x, tex_y).r
			var tex_height: float = 0.5
			if height_image != null:
				tex_height = height_image.get_pixel(tex_x, tex_y).r
			var tex_ao: float = 1.0
			if ao_image != null:
				tex_ao = ao_image.get_pixel(tex_x, tex_y).r
			
			# Coverage guard: slow down paint as the local pixel is already far from base terrain color.
			var c: Color = _color_image.get_pixel(px, py)
			var c_rgb: Vector3 = Vector3(c.r, c.g, c.b)
			var coverage_now: float = clampf((c_rgb - base_rgb).length() / 0.75, 0.0, 1.0)
			var coverage_gate: float = clampf((safe_coverage - coverage_now) / maxf(safe_coverage, 0.001), 0.0, 1.0)
			var alpha: float = strength_weight * density_weight * falloff * coverage_gate
			if alpha <= 0.0005:
				continue

			# Slightly compress high saturation toward the pattern's luminance for less muddy buildup.
			var ch_r: float = tex_color.r * safe_exposure
			var ch_g: float = tex_color.g * safe_exposure
			var ch_b: float = tex_color.b * safe_exposure
			# Compact highlight rolloff to prevent bright sand/ground blowout.
			ch_r = ch_r / (1.0 + ch_r * 0.42)
			ch_g = ch_g / (1.0 + ch_g * 0.42)
			ch_b = ch_b / (1.0 + ch_b * 0.42)
			var lum: float = ch_r * 0.299 + ch_g * 0.587 + ch_b * 0.114
			# AO and height subtly darken crevices and increase local roughness depth.
			var cavity: float = clampf(1.0 - tex_height, 0.0, 1.0)
			var ao_darkening: float = lerpf(0.82, 1.0, tex_ao)
			var cavity_darkening: float = 1.0 - cavity * 0.08
			ch_r *= ao_darkening * cavity_darkening
			ch_g *= ao_darkening * cavity_darkening
			ch_b *= ao_darkening * cavity_darkening
			# Blend toward base + local terrain color so the pattern integrates.
			var base_mix: float = 0.10
			var local_tint_mix: float = lerpf(0.16, 0.08, center_hold)
			ch_r = lerpf(base_brush_color.r, ch_r, 1.0 - base_mix)
			ch_g = lerpf(base_brush_color.g, ch_g, 1.0 - base_mix)
			ch_b = lerpf(base_brush_color.b, ch_b, 1.0 - base_mix)
			ch_r = lerpf(c.r, ch_r, 1.0 - local_tint_mix)
			ch_g = lerpf(c.g, ch_g, 1.0 - local_tint_mix)
			ch_b = lerpf(c.b, ch_b, 1.0 - local_tint_mix)
			var target: Color = Color(lerpf(lum, ch_r, 0.88), lerpf(lum, ch_g, 0.88), lerpf(lum, ch_b, 0.88), 1.0)
			var blend_alpha: float = clampf(alpha, 0.0, 1.0)
			_color_image.set_pixel(px, py, c.lerp(target, blend_alpha))
			if write_pbr and _normal_image != null:
				var npx: int = clampi(px, 0, _normal_image.get_width() - 1)
				var npy: int = clampi(py, 0, _normal_image.get_height() - 1)
				var ncur: Color = _normal_image.get_pixel(npx, npy)
				var normal_alpha: float = blend_alpha * lerpf(0.55, 0.92, center_hold)
				_normal_image.set_pixel(npx, npy, ncur.lerp(tex_normal, normal_alpha))
			if write_pbr and _roughness_image != null:
				var rpx: int = clampi(px, 0, _roughness_image.get_width() - 1)
				var rpy: int = clampi(py, 0, _roughness_image.get_height() - 1)
				var rcur: float = _roughness_image.get_pixel(rpx, rpy).r
				var bright_bias: float = clampf(maxf(lum - 0.62, 0.0) * 0.6, 0.0, 0.25)
				var rough_target: float = clampf(tex_roughness + cavity * 0.10 + bright_bias, 0.22, 1.0)
				var rnxt: float = lerpf(rcur, rough_target, blend_alpha)
				_roughness_image.set_pixel(rpx, rpy, Color(rnxt, 0.0, 0.0, 1.0))
			changed = true
	
	if changed:
		_mark_dirty_color(min_x, max_x, min_y, max_y)
		if write_pbr:
			_mark_dirty_normal(min_x, max_x, min_y, max_y)
			_mark_dirty_roughness(min_x, max_x, min_y, max_y)
		_request_texture_upload()

func apply_texture_erase_brush(world_position: Vector3, brush_size: float, strength: float, edge_softness: float = 0.78) -> void:
	if _color_image == null:
		return
	
	var uv: Vector2 = _world_to_uv(world_position.x, world_position.z)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return
	
	var paint_resolution_local: int = _color_image.get_width() - 1
	var res_f: float = float(paint_resolution_local)
	var center_x: int = clampi(int(round(uv.x * res_f)), 0, paint_resolution_local)
	var center_y: int = clampi(int(round(uv.y * res_f)), 0, paint_resolution_local)
	var radius_px: float = maxf((brush_size / map_size) * res_f, 1.5)
	var radius_sq: float = radius_px * radius_px
	
	var min_x: int = max(0, int(floor(float(center_x) - radius_px)) - 1)
	var max_x: int = min(paint_resolution_local, int(ceil(float(center_x) + radius_px)) + 1)
	var min_y: int = max(0, int(floor(float(center_y) - radius_px)) - 1)
	var max_y: int = min(paint_resolution_local, int(ceil(float(center_y) + radius_px)) + 1)
	
	var safe_s: float = clampf(strength, 0.01, 1.0)
	var safe_edge_softness: float = clampf(edge_softness, 0.0, 1.0)
	var strength_weight: float = lerpf(0.08, 1.0, smoothstep(0.0, 1.0, safe_s))
	var fade_start: float = lerpf(0.90, 0.04, safe_edge_softness)
	var paint_step: int = 2 if (_texture_perf_mode and _texture_stroke_active and radius_px > 24.0) else 1
	var write_pbr: bool = not (_texture_perf_mode and _texture_stroke_active)
	var changed: bool = false
	
	for py in range(min_y, max_y + 1, paint_step):
		for px in range(min_x, max_x + 1, paint_step):
			var dx: float = float(px - center_x)
			var dy: float = float(py - center_y)
			var dsq: float = dx * dx + dy * dy
			if dsq > radius_sq:
				continue
			
			# Use the same edge-softness profile as texture paint.
			var dist_n: float = sqrt(dsq) / radius_px
			var soft_falloff: float = 1.0 - smoothstep(fade_start, 1.0, dist_n)
			var center_hold: float = 1.0 - smoothstep(0.0, 0.62, dist_n)
			var falloff: float = clampf(soft_falloff * (0.78 + center_hold * 0.22), 0.0, 1.0)
			
			# Blend terrain color back to base grass green
			var c: Color = _color_image.get_pixel(px, py)
			var erase_alpha: float = strength_weight * falloff
			_color_image.set_pixel(px, py, c.lerp(base_brush_color, erase_alpha))
			if write_pbr and _normal_image != null:
				var npx: int = clampi(px, 0, _normal_image.get_width() - 1)
				var npy: int = clampi(py, 0, _normal_image.get_height() - 1)
				var ncur: Color = _normal_image.get_pixel(npx, npy)
				_normal_image.set_pixel(npx, npy, ncur.lerp(Color(0.5, 0.5, 1.0, 1.0), erase_alpha))
			if write_pbr and _roughness_image != null:
				var rpx: int = clampi(px, 0, _roughness_image.get_width() - 1)
				var rpy: int = clampi(py, 0, _roughness_image.get_height() - 1)
				var rcur: float = _roughness_image.get_pixel(rpx, rpy).r
				var rnxt: float = lerpf(rcur, 0.92, erase_alpha)
				_roughness_image.set_pixel(rpx, rpy, Color(rnxt, 0.0, 0.0, 1.0))
			changed = true
	
	if changed:
		_mark_dirty_color(min_x, max_x, min_y, max_y)
		if write_pbr:
			_mark_dirty_normal(min_x, max_x, min_y, max_y)
			_mark_dirty_roughness(min_x, max_x, min_y, max_y)
		_request_texture_upload()

func _apply_cliff_mode_textures(min_x: int, max_x: int, min_y: int, max_y: int, overhang_amount: float) -> void:
	if _height_image == null or _color_image == null:
		return
	
	# Cliff detection thresholds (in degrees)
	const CLIFF_THRESHOLD: float = 60.0
	const BLEND_START: float = 45.0
	
	# Create a working copy for height queries
	var height_snapshot: Image = _height_image.duplicate()
	
	for py in range(min_y, max_y + 1):
		for px in range(min_x, max_x + 1):
			if px <= 0 or px >= grid_resolution or py <= 0 or py >= grid_resolution:
				continue
			
			# Sample 3x3 kernel to estimate slope
			var center_h: float = height_snapshot.get_pixel(px, py).r
			
			# Calculate slope using Sobel-like kernel
			var north_h: float = height_snapshot.get_pixel(px, py - 1).r
			var south_h: float = height_snapshot.get_pixel(px, py + 1).r
			var east_h: float = height_snapshot.get_pixel(px + 1, py).r
			var west_h: float = height_snapshot.get_pixel(px - 1, py).r
			
			var max_height_diff: float = max(
				absf(north_h - center_h),
				max(absf(south_h - center_h),
				max(absf(east_h - center_h), absf(west_h - center_h)))
			)
			
			# Convert height difference to slope angle
			# Assume 1 pixel = 1 meter horizontal distance, height in normalized 0-1 range
			var pixel_vertical_m: float = max_height_diff * max_height
			var slope_rad: float = atan(pixel_vertical_m / 1.0)
			var slope_deg: float = slope_rad * (180.0 / PI)
			
			# Determine texture blend factor based on slope
			var cliff_factor: float = 0.0
			if slope_deg > CLIFF_THRESHOLD:
				cliff_factor = 1.0
			elif slope_deg > BLEND_START:
				# Smooth transition between 45-60 degrees
				cliff_factor = (slope_deg - BLEND_START) / (CLIFF_THRESHOLD - BLEND_START)
			
			# Apply cliff texture blending if needed
			if cliff_factor > 0.01:
				var current_color: Color = _color_image.get_pixel(px, py)
				# Blend toward a rocky/cliff color (darker, more brownish)
				var cliff_color: Color = Color(0.4, 0.35, 0.28, 1.0)
				var blended: Color = current_color.lerp(cliff_color, cliff_factor)
				_color_image.set_pixel(px, py, blended)
			
			# Apply overhang formation if enabled and on cliff edge
			if overhang_amount > 0.01 and slope_deg > CLIFF_THRESHOLD:
				# Small chance to push outward on cliff tops
				var overhang_strength: float = overhang_amount * 0.01
				if randf() < overhang_strength:
					# Slight height increase at cliff edges for visual interest
					var current_h: float = _height_image.get_pixel(px, py).r
					var new_h: float = clampf(current_h + overhang_amount * 0.005, 0.0, 1.0)
					_height_image.set_pixel(px, py, Color(new_h, 0.0, 0.0, 1.0))
