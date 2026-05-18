extends CanvasLayer

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
	_set_enabled(enabled)
	set_performance_mode(performance_mode)

func _process(_delta: float) -> void:
	if not enabled:
		return
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


func set_daylight_factor(value: float) -> void:
	_daylight_factor = clampf(value, 0.0, 1.0)
	_apply_quality_preset()

func _set_enabled(value: bool) -> void:
	if _overlay.material is ShaderMaterial:
		(_overlay.material as ShaderMaterial).set_shader_parameter("enabled", value)
	_overlay.visible = value
	_viewport.disable_3d = not value
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED

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
	material.set_shader_parameter("outline_strength", daytime_outline_strength)
	material.set_shader_parameter("line_darken", daytime_line_darken)
	material.set_shader_parameter("daytime_brightness", lerpf(1.0, 1.07, _daylight_factor))
	material.set_shader_parameter("daytime_contrast", lerpf(1.0, 0.95, _daylight_factor))

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
