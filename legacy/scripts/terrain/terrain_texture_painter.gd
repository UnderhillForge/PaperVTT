class_name TerrainTexturePainter
extends RefCounted

const WORLD_TEXTURE_ROOT = "res://assets/textures/world/"
const ALBEDO_NAMES = ["color.png", "albedo.png", "basecolor.png", "_base_2k.png", "_basecolor_2k.png", "_color_2k.png"]
const NORMAL_DX_NAMES = ["normal_dx.png", "normaldx.png"]
const NORMAL_GL_NAMES = ["normal_gl.png", "normalgl.png", "normal.png"]
const ROUGHNESS_NAMES = ["roughness.png", "rough.png"]
const HEIGHT_NAMES = ["height.png", "displacement.png"]
const AO_NAMES = ["ambient_occlusion.png", "ao.png", "occlusion.png"]

class TextureInfo:
	var id: String
	var display_name: String
	var albedo_path: String
	var normal_path: String
	var roughness_path: String
	var height_path: String
	var ao_path: String
	var normal_is_dx: bool = false
	var cached_image: Image = null
	var cached_normal_image: Image = null
	var cached_roughness_image: Image = null
	var cached_height_image: Image = null
	var cached_ao_image: Image = null
	
	func _init(p_id: String, p_name: String, p_albedo: String, p_normal: String, p_roughness: String, p_height: String, p_ao: String, p_normal_is_dx: bool) -> void:
		id = p_id
		display_name = p_name
		albedo_path = p_albedo
		normal_path = p_normal
		roughness_path = p_roughness
		height_path = p_height
		ao_path = p_ao
		normal_is_dx = p_normal_is_dx

var _discovered_textures: Array[TextureInfo] = []
var _texture_map: Dictionary = {}
var selected_texture_id: String = ""

func _init() -> void:
	_discover_textures()

func _discover_textures() -> void:
	_discovered_textures.clear()
	_texture_map.clear()
	
	var dir = DirAccess.open(WORLD_TEXTURE_ROOT)
	if dir == null:
		push_error("Failed to open texture directory: %s" % WORLD_TEXTURE_ROOT)
		return
	
	dir.list_dir_begin()
	var entry = dir.get_next()
	
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		
		var full_path = WORLD_TEXTURE_ROOT.path_join(entry)
		if dir.current_is_dir():
			var best_albedo = _find_best_map(full_path, ALBEDO_NAMES)
			if best_albedo != "":
				var best_normal_dx = _find_best_map(full_path, NORMAL_DX_NAMES)
				var best_normal_gl = _find_best_map(full_path, NORMAL_GL_NAMES)
				var best_normal = best_normal_dx if best_normal_dx != "" else best_normal_gl
				var best_roughness = _find_best_map(full_path, ROUGHNESS_NAMES)
				var best_height = _find_best_map(full_path, HEIGHT_NAMES)
				var best_ao = _find_best_map(full_path, AO_NAMES)
				var tex_info = TextureInfo.new(entry, _human_readable_name(entry), best_albedo, best_normal, best_roughness, best_height, best_ao, best_normal_dx != "")
				_discovered_textures.append(tex_info)
				_texture_map[entry] = tex_info
				if selected_texture_id == "":
					selected_texture_id = entry
		
		entry = dir.get_next()

func _find_best_map(folder_path: String, preferred_names: Array) -> String:
	var dir = DirAccess.open(folder_path)
	if dir == null:
		return ""
	
	dir.list_dir_begin()
	var entry = dir.get_next()
	var found_files: Array[String] = []
	
	while entry != "":
		if not entry.begins_with("."):
			found_files.append(entry)
		entry = dir.get_next()
	
	for candidate in preferred_names:
		var candidate_l: String = String(candidate).to_lower()
		for file in found_files:
			if file.to_lower() == candidate_l or file.to_lower().ends_with(candidate_l):
				return folder_path.path_join(file)
	return ""

func _human_readable_name(folder_name: String) -> String:
	# Convert "cliff_rocks_02_2k" → "Cliff Rocks 02"
	var name = folder_name.replace("_2k", "").replace("_", " ")
	return name.capitalize()

func get_textures() -> Array[TextureInfo]:
	return _discovered_textures

func get_albedo_image(texture_id: String, target_size: int = 1024) -> Image:
	if not _texture_map.has(texture_id):
		return null
	
	var tex_info: TextureInfo = _texture_map[texture_id]
	
	# Return cached if available
	if tex_info.cached_image != null and tex_info.cached_image.get_width() == target_size:
		return tex_info.cached_image
	
	# Load and cache
	if ResourceLoader.exists(tex_info.albedo_path):
		var loaded_tex = load(tex_info.albedo_path) as Texture2D
		if loaded_tex != null:
			var img = loaded_tex.get_image()
			if img != null:
				img.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)
				tex_info.cached_image = img
				return img
	
	push_warning("Failed to load texture: %s" % tex_info.albedo_path)
	return null

func get_thumbnail_image(texture_id: String, size: int = 64) -> Image:
	var img = get_albedo_image(texture_id, maxi(size, 256))
	if img == null:
		return null
	
	var thumbnail = img.duplicate()
	thumbnail.resize(size, size, Image.INTERPOLATE_LANCZOS)
	return thumbnail

func get_pbr_maps(texture_id: String, target_size: int = 1024) -> Dictionary:
	if not _texture_map.has(texture_id):
		return {}
	var info: TextureInfo = _texture_map[texture_id]
	return {
		"id": texture_id,
		"name": info.display_name,
		"albedo": get_albedo_image(texture_id, target_size),
		"normal": _get_map_image(info, "normal", target_size),
		"roughness": _get_map_image(info, "roughness", target_size),
		"height": _get_map_image(info, "height", target_size),
		"ao": _get_map_image(info, "ao", target_size)
	}

func get_texture_display_name(texture_id: String) -> String:
	if not _texture_map.has(texture_id):
		return ""
	return (_texture_map[texture_id] as TextureInfo).display_name

func _get_map_image(info: TextureInfo, map_type: String, target_size: int) -> Image:
	var path: String = ""
	var cache: Image = null
	match map_type:
		"normal":
			path = info.normal_path
			cache = info.cached_normal_image
		"roughness":
			path = info.roughness_path
			cache = info.cached_roughness_image
		"height":
			path = info.height_path
			cache = info.cached_height_image
		"ao":
			path = info.ao_path
			cache = info.cached_ao_image
		_:
			return null

	if cache != null and cache.get_width() == target_size:
		return cache
	if path == "" or not ResourceLoader.exists(path):
		return null

	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return null
	img.resize(target_size, target_size, Image.INTERPOLATE_LANCZOS)

	if map_type == "normal" and info.normal_is_dx:
		# Convert DirectX normal map to OpenGL by inverting green channel.
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var c: Color = img.get_pixel(x, y)
				img.set_pixel(x, y, Color(c.r, 1.0 - c.g, c.b, c.a))

	match map_type:
		"normal":
			info.cached_normal_image = img
		"roughness":
			info.cached_roughness_image = img
		"height":
			info.cached_height_image = img
		"ao":
			info.cached_ao_image = img

	return img
