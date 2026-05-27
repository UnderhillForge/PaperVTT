extends CanvasLayer

signal ppf_import_completed(success: bool, message: String)

@export var enabled: bool = false
@export var main_camera_path: NodePath = NodePath("../Camera3D")
@export var performance_mode: bool = false
@export var ultra_performance_mode: bool = false
@export var lightweight_mode: bool = false

@onready var _viewport: SubViewport = $SceneViewport
@onready var _overlay: TextureRect = $FullscreenOverlay

var _capture_camera: Camera3D = null
var _render_scale: float = 1.0
var _daylight_factor: float = 0.0
var _sculpt_mode: bool = false
var _default_shader: Shader = null

const POSTFX_PARAM_DEFAULTS: Dictionary = {
	"outline_strength": 2.35,
	"outline_thickness": 4.0,
	"contrast": 1.0,
	"saturation": 1.0,
	"vignette_strength": 0.25,
	"vignette_softness": 0.55,
	"bloom_strength": 0.12,
	"tint_strength": 0.0,
	"outlines_layer_thickness": 2.2,
	"outlines_layer_depth_sensitivity": 1.6,
	"outlines_layer_depth_threshold": 0.055,
	"outlines_layer_normal_sensitivity": 1.3,
	"outlines_layer_opacity": 0.48,
	"outlines_layer_enabled": false,
	"outlines_layer_color": Color(0.01, 0.01, 0.01, 1.0),
}

const BUILTIN_PRESETS: Dictionary = {
	"Graphic Novel": {
		"outline_strength": 2.8,
		"outline_thickness": 4.8,
		"contrast": 1.2,
		"saturation": 0.78,
		"vignette_strength": 0.22,
		"vignette_softness": 0.6,
		"bloom_strength": 0.05,
		"tint_strength": 0.03,
		"color_tint": Color(0.97, 0.95, 0.91, 1.0),
	},
	"Watercolor": {
		"outline_strength": 1.3,
		"outline_thickness": 2.6,
		"contrast": 0.9,
		"saturation": 0.92,
		"vignette_strength": 0.14,
		"vignette_softness": 0.75,
		"bloom_strength": 0.18,
		"tint_strength": 0.18,
		"color_tint": Color(0.92, 0.96, 0.97, 1.0),
	},
	"Cinematic": {
		"outline_strength": 1.1,
		"outline_thickness": 1.8,
		"contrast": 1.08,
		"saturation": 0.85,
		"vignette_strength": 0.42,
		"vignette_softness": 0.52,
		"bloom_strength": 0.2,
		"tint_strength": 0.16,
		"color_tint": Color(0.95, 0.92, 0.88, 1.0),
	},
	"Horror": {
		"outline_strength": 2.4,
		"outline_thickness": 4.2,
		"contrast": 1.28,
		"saturation": 0.62,
		"vignette_strength": 0.66,
		"vignette_softness": 0.45,
		"bloom_strength": 0.02,
		"tint_strength": 0.25,
		"color_tint": Color(0.86, 0.92, 0.9, 1.0),
	},
	"Dreamy": {
		"outline_strength": 0.8,
		"outline_thickness": 1.5,
		"contrast": 0.84,
		"saturation": 1.08,
		"vignette_strength": 0.12,
		"vignette_softness": 0.8,
		"bloom_strength": 0.3,
		"tint_strength": 0.22,
		"color_tint": Color(0.95, 0.9, 0.98, 1.0),
		"outlines_layer_enabled": false,
	},
	"Graphic Novel Outlines": {
		"outline_strength": 2.95,
		"outline_thickness": 4.6,
		"contrast": 1.16,
		"saturation": 0.82,
		"vignette_strength": 0.28,
		"vignette_softness": 0.62,
		"bloom_strength": 0.05,
		"tint_strength": 0.05,
		"color_tint": Color(0.96, 0.94, 0.90, 1.0),
		"outlines_layer_enabled": true,
		"outlines_layer_color": Color(0.02, 0.02, 0.02, 1.0),
		"outlines_layer_thickness": 2.4,
		"outlines_layer_depth_sensitivity": 1.85,
		"outlines_layer_depth_threshold": 0.052,
		"outlines_layer_normal_sensitivity": 1.35,
		"outlines_layer_opacity": 0.52,
	},
	"Pen & Ink Outlines": {
		"outline_strength": 3.05,
		"outline_thickness": 5.0,
		"contrast": 1.18,
		"saturation": 0.8,
		"vignette_strength": 0.32,
		"vignette_softness": 0.58,
		"bloom_strength": 0.04,
		"tint_strength": 0.04,
		"color_tint": Color(0.97, 0.95, 0.91, 1.0),
		"outlines_layer_enabled": true,
		"outlines_layer_color": Color(0.01, 0.01, 0.01, 1.0),
		"outlines_layer_thickness": 2.55,
		"outlines_layer_depth_sensitivity": 1.95,
		"outlines_layer_depth_threshold": 0.048,
		"outlines_layer_normal_sensitivity": 1.45,
		"outlines_layer_opacity": 0.58,
	},
}

func _ready() -> void:
	_viewport.disable_3d = false
	_viewport.world_3d = get_viewport().world_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sync_viewport_size()

	_capture_camera = Camera3D.new()
	_capture_camera.current = true
	_capture_camera.name = "PostFxCaptureCamera"
	_viewport.add_child(_capture_camera)

	_overlay.texture = _viewport.get_texture()
	if _overlay.material is ShaderMaterial:
		_default_shader = (_overlay.material as ShaderMaterial).shader
	_set_enabled(enabled)
	set_performance_mode(performance_mode)

func _process(_delta: float) -> void:
	_sync_viewport_size()
	_sync_capture_camera()

func set_enabled(value: bool) -> void:
	enabled = value
	_set_enabled(value)

func set_performance_mode(value: bool) -> void:
	performance_mode = value
	if ultra_performance_mode:
		_render_scale = 0.4
	else:
		_render_scale = 0.5 if performance_mode else 1.0
	_apply_quality_preset()
	_sync_viewport_size()

func set_ultra_performance_mode(value: bool) -> void:
	ultra_performance_mode = value
	if ultra_performance_mode:
		performance_mode = true
	_render_scale = 0.4 if ultra_performance_mode else (0.5 if performance_mode else 1.0)
	_apply_quality_preset()
	_sync_viewport_size()

func get_render_scale() -> float:
	return _render_scale

func set_lightweight_mode(value: bool) -> void:
	lightweight_mode = value
	_apply_quality_preset()


func set_sculpt_mode(sculpt_enabled: bool) -> void:
	_sculpt_mode = sculpt_enabled
	_apply_quality_preset()

func set_daylight_factor(value: float) -> void:
	_daylight_factor = clampf(value, 0.0, 1.0)
	_apply_quality_preset()

func _set_enabled(value: bool) -> void:
	if _overlay.material is ShaderMaterial:
		(_overlay.material as ShaderMaterial).set_shader_parameter("enabled", value)
	_overlay.visible = value
	# Keep the capture viewport active so the inspector preview remains live
	# even when fullscreen post-processing is toggled off.
	_viewport.disable_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _apply_quality_preset() -> void:
	if not (_overlay.material is ShaderMaterial):
		return
	var material := _overlay.material as ShaderMaterial
	var base_outline_strength: float = 2.35
	var base_line_darken: float = 0.085
	if performance_mode:
		if ultra_performance_mode:
			material.set_shader_parameter("outline_thickness", 0.0)
			material.set_shader_parameter("outline_strength", 0.0)
			material.set_shader_parameter("hatch_opacity", 0.0)
			material.set_shader_parameter("hatch_scale", 320.0)
			material.set_shader_parameter("paper_strength", 0.0)
			material.set_shader_parameter("line_darken", 0.0)
			material.set_shader_parameter("daytime_brightness", 1.0)
			material.set_shader_parameter("daytime_contrast", 1.0)
			return
		material.set_shader_parameter("outline_thickness", 2.6)
		base_outline_strength = 1.35
		material.set_shader_parameter("hatch_opacity", 0.08)
		material.set_shader_parameter("hatch_scale", 420.0)
		material.set_shader_parameter("paper_strength", 0.01)
		base_line_darken = 0.02
	elif lightweight_mode:
		material.set_shader_parameter("outline_thickness", 3.0)
		base_outline_strength = 1.7
		material.set_shader_parameter("hatch_opacity", 0.12)
		material.set_shader_parameter("hatch_scale", 500.0)
		material.set_shader_parameter("paper_strength", 0.02)
		base_line_darken = 0.04
	else:
		material.set_shader_parameter("outline_thickness", 4.0)
		base_outline_strength = 2.35
		material.set_shader_parameter("hatch_opacity", 0.24)
		material.set_shader_parameter("hatch_scale", 560.0)
		material.set_shader_parameter("paper_strength", 0.05)
		base_line_darken = 0.085

	# Daylight softens line crush and raises tonal lift to keep afternoons bright.
	var daytime_outline_strength: float = lerpf(base_outline_strength, base_outline_strength * 0.78, _daylight_factor)
	var daytime_line_darken: float = lerpf(base_line_darken, base_line_darken * 0.65, _daylight_factor)

	# Sculpt mode further reduces shadow crushing for maximum shape readability.
	if _sculpt_mode:
		daytime_outline_strength *= 0.68
		daytime_line_darken *= 0.45

	material.set_shader_parameter("outline_strength", daytime_outline_strength)
	material.set_shader_parameter("line_darken", daytime_line_darken)
	material.set_shader_parameter("daytime_brightness", lerpf(1.0, 1.07, _daylight_factor) + (0.06 if _sculpt_mode else 0.0))
	material.set_shader_parameter("daytime_contrast", lerpf(1.0, 0.95, _daylight_factor) - (0.03 if _sculpt_mode else 0.0))


func get_preview_texture() -> Texture2D:
	return _viewport.get_texture()


func set_effect_value(effect_name: String, value: Variant) -> void:
	if not (_overlay.material is ShaderMaterial):
		return
	var material := _overlay.material as ShaderMaterial
	if effect_name == "color_tint":
		if _shader_has_uniform(material, "color_tint"):
			material.set_shader_parameter("color_tint", value)
		return
	if _shader_has_uniform(material, effect_name):
		material.set_shader_parameter(effect_name, value)


func apply_builtin_preset(preset_name: String) -> bool:
	if not BUILTIN_PRESETS.has(preset_name):
		return false
	var preset: Dictionary = BUILTIN_PRESETS[preset_name]
	if not preset.has("outlines_layer_enabled"):
		set_effect_value("outlines_layer_enabled", false)
	for key_variant in preset.keys():
		var key: String = String(key_variant)
		set_effect_value(key, preset[key_variant])
	return true


func apply_custom_shader_code(shader_code: String) -> bool:
	if not (_overlay.material is ShaderMaterial):
		return false
	var cleaned: String = shader_code.strip_edges()
	if cleaned.is_empty():
		if _default_shader != null:
			(_overlay.material as ShaderMaterial).shader = _default_shader
		return true
	if not cleaned.contains("shader_type canvas_item"):
		return false
	if not cleaned.contains("void fragment"):
		return false
	var shader := Shader.new()
	shader.code = cleaned
	(_overlay.material as ShaderMaterial).shader = shader
	return true


func get_live_postfx_state() -> Dictionary:
	var state: Dictionary = {
		"enabled": enabled,
		"effects": [],
		"color_tint": Color(1.0, 1.0, 1.0, 1.0),
	}
	if not (_overlay.material is ShaderMaterial):
		return state
	var material := _overlay.material as ShaderMaterial
	var effects: Array[Dictionary] = []
	for key_variant in POSTFX_PARAM_DEFAULTS.keys():
		var key: String = String(key_variant)
		if _shader_has_uniform(material, key):
			effects.append({"name": key, "value": material.get_shader_parameter(key)})
	state["effects"] = effects
	if _shader_has_uniform(material, "color_tint"):
		state["color_tint"] = material.get_shader_parameter("color_tint")
	return state


func save_ppf(path: String, name: String, author: String, description: String, custom_shader_code: String = "") -> bool:
	var data: Dictionary = _build_ppf_data(name, author, description, custom_shader_code)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func load_ppf(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return false
	return apply_ppf_data(parsed as Dictionary)


func apply_ppf_data(ppf: Dictionary) -> bool:
	if not (_overlay.material is ShaderMaterial):
		return false
	if ppf.has("custom_shader_code"):
		var custom_code: String = String(ppf.get("custom_shader_code", "")).strip_edges()
		if not custom_code.is_empty():
			if not apply_custom_shader_code(custom_code):
				return false
	var effects_variant: Variant = ppf.get("effects", [])
	if effects_variant is Array:
		for effect_variant in effects_variant:
			if not (effect_variant is Dictionary):
				continue
			var effect: Dictionary = effect_variant
			var effect_name: String = String(effect.get("name", ""))
			if effect_name == "":
				continue
			var value: Variant = effect.get("value", null)
			if effect.has("params") and effect.get("params") is Dictionary:
				var params: Dictionary = effect.get("params")
				if params.has("value"):
					value = params["value"]
			if value == null:
				continue
			set_effect_value(effect_name, value)
	if ppf.has("color_tint"):
		set_effect_value("color_tint", ppf.get("color_tint"))
	if ppf.has("enabled"):
		set_enabled(bool(ppf.get("enabled")))
	return true


func import_ppf_from_url(url: String) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
		var msg: String = ""
		var ok: bool = false
		if response_code >= 200 and response_code < 300:
			var text: String = body.get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(text)
			if parsed is Dictionary and apply_ppf_data(parsed as Dictionary):
				ok = true
				msg = "Imported .ppf"
			else:
				msg = "Invalid .ppf payload"
		else:
			msg = "HTTP %d while importing .ppf" % response_code
		req.queue_free()
		ppf_import_completed.emit(ok, msg)
	)
	var err: Error = req.request(url)
	if err != OK:
		req.queue_free()
		ppf_import_completed.emit(false, "Failed to start import request")


func get_builtin_preset_names() -> PackedStringArray:
	var names := PackedStringArray()
	for key_variant in BUILTIN_PRESETS.keys():
		names.append(String(key_variant))
	return names


func _build_ppf_data(name: String, author: String, description: String, custom_shader_code: String) -> Dictionary:
	var state: Dictionary = get_live_postfx_state()
	return {
		"name": name,
		"author": author,
		"description": description,
		"effects": state.get("effects", []),
		"color_tint": state.get("color_tint", Color(1.0, 1.0, 1.0, 1.0)),
		"enabled": state.get("enabled", true),
		"custom_shader_code": custom_shader_code,
	}


func _shader_has_uniform(material: ShaderMaterial, uniform_name: String) -> bool:
	if material == null or material.shader == null:
		return false
	for uniform_info in material.shader.get_shader_uniform_list():
		if String(uniform_info.get("name", "")) == uniform_name:
			return true
	return false

func _sync_viewport_size() -> void:
	var size: Vector2i = get_viewport().get_visible_rect().size
	if size.x <= 0 or size.y <= 0:
		return
	var scaled_size := Vector2i(maxi(int(round(float(size.x) * _render_scale)), 1), maxi(int(round(float(size.y) * _render_scale)), 1))
	if _viewport.size != scaled_size:
		_viewport.size = scaled_size

func _sync_capture_camera() -> void:
	if _capture_camera == null:
		return
	var main_camera := _resolve_main_camera()
	if main_camera == null:
		return
	_capture_camera.global_transform = main_camera.global_transform
	_capture_camera.projection = main_camera.projection
	_capture_camera.fov = main_camera.fov
	_capture_camera.size = main_camera.size
	_capture_camera.near = main_camera.near
	_capture_camera.far = main_camera.far

func _resolve_main_camera() -> Camera3D:
	var root := get_tree().current_scene
	if root != null:
		var by_path := root.get_node_or_null(main_camera_path) as Camera3D
		if by_path != null:
			return by_path
	return get_viewport().get_camera_3d()
