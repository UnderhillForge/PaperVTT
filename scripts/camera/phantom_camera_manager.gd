extends Node

@export var top_down_priority_active: int = 30
@export var free_orbit_priority_active: int = 20
@export var follow_priority_active: int = 25
@export var camera_priority_inactive: int = 0
@export var top_down_size_min: float = 20.0
@export var top_down_size_max: float = 180.0
@export var top_down_size_step: float = 5.0
@export var top_down_pan_speed: float = 0.018
@export var editor_zoom_min: float = 18.0
@export var editor_zoom_max: float = 140.0
@export var editor_zoom_step: float = 5.0
@export var editor_orbit_sensitivity: float = 0.25
@export var editor_pan_speed: float = 0.022
@export var spring_length_min: float = 3.5
@export var spring_length_max: float = 12.0
@export var spring_zoom_step: float = 0.5
@export var manual_return_delay: float = 1.2
@export var auto_follow_blend_speed: float = 4.0
@export var mouse_sensitivity: float = 0.18
@export var pitch_min: float = -25.0
@export var pitch_max: float = 60.0

@onready var _camera: Camera3D = get_node_or_null("../Camera3D") as Camera3D
@onready var _camera_focus: Node3D = get_node_or_null("../CameraFocus") as Node3D
@onready var _editor_camera: Node = get_node_or_null("../EditorCamera")
@onready var _follow_camera: Node = get_node_or_null("../CharacterFollowCamera")
@onready var _top_down_camera: Node = get_node_or_null("../TopDown2DView")

var _active_target: Node3D = null
var _is_top_down_mode: bool = true
var _third_person_enabled: bool = false
var _manual_look: bool = false
var _manual_timer: float = 0.0
var _right_drag_start: Vector2 = Vector2.ZERO
var _right_dragging: bool = false
var _editor_yaw_degrees: float = -45.0
var _editor_pitch_degrees: float = 35.0
var _editor_distance: float = 30.0

const _RIGHT_DRAG_THRESHOLD: float = 4.0
const _MOVE_SPEED_THRESHOLD: float = 0.35
const _EDITOR_PITCH_MIN: float = 18.0
const _EDITOR_PITCH_MAX: float = 84.0

func _ready() -> void:
	_initialize_editor_camera_defaults()
	_initialize_top_down_camera_defaults()
	_set_top_down_mode(true)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_toggle_primary_view()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _is_top_down_mode:
		_handle_top_down_input(event)
		return

	if not _third_person_enabled:
		_handle_editor_camera_input(event)
		return

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_right_drag_start = mb.position
				_right_dragging = false
			else:
				_right_dragging = false
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_spring_length(-spring_zoom_step)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_spring_length(spring_zoom_step)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if not _right_dragging and event.position.distance_to(_right_drag_start) > _RIGHT_DRAG_THRESHOLD:
			_right_dragging = true
		if _right_dragging:
			_manual_look = true
			_manual_timer = manual_return_delay
			_apply_manual_orbit(event as InputEventMouseMotion)
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _is_top_down_mode:
		return

	if not _third_person_enabled or _follow_camera == null:
		return
	if _active_target == null or not is_instance_valid(_active_target):
		_active_target = _find_selected_target()
		if _active_target != null:
			_follow_camera.call("set_follow_target", _active_target)
		else:
			_set_editor_mode()
			return

	if _manual_look:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_manual_timer = manual_return_delay
		else:
			_manual_timer -= delta
			if _manual_timer <= 0.0:
				_manual_look = false

	if _manual_look:
		return

	if _is_target_moving_forward():
		var rot: Vector3 = _follow_camera.call("get_third_person_rotation_degrees")
		var target_yaw: float = _yaw_behind_target(_active_target)
		var yaw_diff: float = fmod(target_yaw - rot.y + 540.0, 360.0) - 180.0
		rot.y += yaw_diff * clampf(auto_follow_blend_speed * delta, 0.0, 1.0)
		_follow_camera.call("set_third_person_rotation_degrees", rot)

func _handle_top_down_input(event: InputEvent) -> void:
	if _top_down_camera == null:
		return

	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_top_down_size(-top_down_size_step)
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_top_down_size(top_down_size_step)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or (Input.is_key_pressed(KEY_ALT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			_pan_top_down_focus(mm.relative)
			get_viewport().set_input_as_handled()
			return

func _handle_editor_camera_input(event: InputEvent) -> void:
	if _editor_camera == null:
		return

	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_editor_distance = clampf(_editor_distance - editor_zoom_step, editor_zoom_min, editor_zoom_max)
			_apply_editor_camera_pose()
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_editor_distance = clampf(_editor_distance + editor_zoom_step, editor_zoom_min, editor_zoom_max)
			_apply_editor_camera_pose()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			_editor_yaw_degrees -= mm.relative.x * editor_orbit_sensitivity
			_editor_pitch_degrees = clampf(_editor_pitch_degrees - mm.relative.y * editor_orbit_sensitivity, _EDITOR_PITCH_MIN, _EDITOR_PITCH_MAX)
			_apply_editor_camera_pose()
			get_viewport().set_input_as_handled()
			return
		if Input.is_key_pressed(KEY_ALT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_pan_editor_focus(mm.relative)
			_apply_editor_camera_pose()
			get_viewport().set_input_as_handled()
			return

func set_follow_target(target: Node3D) -> void:
	_active_target = target
	if _follow_camera != null:
		_follow_camera.call("set_follow_target", target)
	if _is_top_down_mode:
		return
	if target != null:
		_set_follow_mode(target)
	else:
		_set_editor_mode()

func clear_follow_target() -> void:
	_active_target = null
	if _follow_camera != null:
		_follow_camera.call("set_follow_target", null)
	if not _is_top_down_mode:
		_set_editor_mode()

func has_follow_target() -> bool:
	return _active_target != null and is_instance_valid(_active_target)

func recenter() -> void:
	if _camera_focus != null:
		_camera_focus.global_position = Vector3.ZERO
	_editor_yaw_degrees = -45.0
	_editor_pitch_degrees = 35.0
	_editor_distance = 30.0
	_apply_editor_camera_pose()
	_initialize_top_down_camera_defaults()
	if _is_top_down_mode:
		_apply_view_priorities()
	else:
		_set_editor_mode()

func set_top_down_default() -> void:
	_set_top_down_mode(false)

func toggle_projection_mode() -> void:
	if _is_top_down_mode:
		return
	if _camera == null:
		return
	if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = 24.0
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = 55.0

func _toggle_primary_view() -> void:
	if _is_top_down_mode:
		_set_free_view_from_state()
	else:
		_set_top_down_mode(false)

func _set_top_down_mode(initial: bool) -> void:
	_is_top_down_mode = true
	_manual_look = false
	_manual_timer = 0.0
	_initialize_top_down_camera_defaults()
	_apply_view_priorities()
	if not initial:
		_set_mouse_capture(false)

func _set_free_view_from_state() -> void:
	_is_top_down_mode = false
	if _active_target != null and is_instance_valid(_active_target):
		_set_follow_mode(_active_target)
		return
	_set_editor_mode()

func _set_editor_mode() -> void:
	if _is_top_down_mode:
		return
	_third_person_enabled = false
	_manual_look = false
	_manual_timer = 0.0
	_restore_perspective()
	_apply_editor_camera_pose()
	_apply_view_priorities()
	_restore_perspective.call_deferred()
	_set_mouse_capture(false)

func _set_follow_mode(target: Node3D) -> void:
	if _is_top_down_mode:
		return
	_third_person_enabled = true
	_manual_look = false
	_manual_timer = 0.0
	_restore_perspective()
	if _follow_camera != null:
		_follow_camera.call("set_follow_target", target)
	_apply_view_priorities()
	_set_mouse_capture(false)

func _find_selected_target() -> Node3D:
	for n in get_tree().get_nodes_in_group("character_controller"):
		if n is Node3D and n.has_method("is_selected") and bool(n.call("is_selected")):
			return n as Node3D
	return null

func _apply_manual_orbit(event: InputEventMouseMotion) -> void:
	if _follow_camera == null:
		return
	var rot: Vector3 = _follow_camera.call("get_third_person_rotation_degrees")
	rot.x = clampf(rot.x - event.relative.y * mouse_sensitivity, pitch_min, pitch_max)
	rot.y = wrapf(rot.y - event.relative.x * mouse_sensitivity, 0.0, 360.0)
	_follow_camera.call("set_third_person_rotation_degrees", rot)

func _adjust_spring_length(delta_len: float) -> void:
	if _follow_camera == null:
		return
	var current_len: float = float(_follow_camera.call("get_spring_length"))
	_follow_camera.call("set_spring_length", clampf(current_len + delta_len, spring_length_min, spring_length_max))

func _is_target_moving() -> bool:
	if _active_target == null:
		return false
	if _active_target is CharacterBody3D:
		var body: CharacterBody3D = _active_target as CharacterBody3D
		return Vector2(body.velocity.x, body.velocity.z).length() > _MOVE_SPEED_THRESHOLD
	return false

func _is_target_moving_forward() -> bool:
	if not _is_target_moving():
		return false
	if _active_target == null or not (_active_target is CharacterBody3D):
		return false
	var body: CharacterBody3D = _active_target as CharacterBody3D
	var planar_vel := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if planar_vel.length_squared() < 0.0001:
		return false
	var char_forward := -_active_target.global_basis.z
	char_forward.y = 0.0
	if char_forward.length_squared() < 0.0001:
		return false
	planar_vel = planar_vel.normalized()
	char_forward = char_forward.normalized()
	# Only auto-rotate camera behind character when moving mostly forward.
	return planar_vel.dot(char_forward) > 0.25

func _yaw_behind_target(target: Node3D) -> float:
	var forward: Vector3 = -target.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return float(_follow_camera.call("get_third_person_rotation_degrees").y)
	forward = forward.normalized()
	return rad_to_deg(atan2(-forward.x, -forward.z))

func _apply_view_priorities() -> void:
	if _top_down_camera != null:
		_top_down_camera.call("set_priority", top_down_priority_active if _is_top_down_mode else camera_priority_inactive)
	if _is_top_down_mode:
		if _editor_camera != null:
			_editor_camera.call("set_priority", camera_priority_inactive)
		if _follow_camera != null:
			_follow_camera.call("set_priority", camera_priority_inactive)
		return

	if _third_person_enabled and _active_target != null and is_instance_valid(_active_target):
		if _follow_camera != null:
			_follow_camera.call("set_priority", follow_priority_active)
		if _editor_camera != null:
			_editor_camera.call("set_priority", camera_priority_inactive)
	else:
		if _editor_camera != null:
			_editor_camera.call("set_priority", free_orbit_priority_active)
		if _follow_camera != null:
			_follow_camera.call("set_priority", camera_priority_inactive)

func _adjust_top_down_size(delta_size: float) -> void:
	if _top_down_camera == null:
		return
	var current_size: Variant = _top_down_camera.call("get_size")
	if current_size == null:
		return
	var size_value: float = float(current_size)
	size_value = clampf(size_value + delta_size, top_down_size_min, top_down_size_max)
	_top_down_camera.call("set_size", size_value)

func _pan_top_down_focus(mouse_delta: Vector2) -> void:
	if _camera_focus == null:
		return
	var topdown_size: float = 60.0
	if _top_down_camera != null:
		var size_value: Variant = _top_down_camera.call("get_size")
		if size_value != null:
			topdown_size = float(size_value)
	_camera_focus.global_position += Vector3(-mouse_delta.x, 0.0, -mouse_delta.y) * top_down_pan_speed * topdown_size

func _set_mouse_capture(enabled: bool) -> void:
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _initialize_editor_camera_defaults() -> void:
	if _editor_camera == null:
		return
	# Ensure Simple-follow camera starts offset from target instead of collapsing onto it.
	var current_offset: Vector3 = _editor_camera.call("get_follow_offset") if _editor_camera.has_method("get_follow_offset") else Vector3.ZERO
	if current_offset.length_squared() < 0.001:
		_editor_camera.call("set_follow_offset", Vector3(0.0, 36.0, 36.0))
	_apply_editor_camera_pose()

func _initialize_top_down_camera_defaults() -> void:
	if _top_down_camera == null:
		return
	# Keep top-down view orthographic and locked straight down.
	_top_down_camera.rotation_degrees = Vector3(-89.5, 0.0, 0.0)
	var offset: Vector3 = _top_down_camera.call("get_follow_offset") if _top_down_camera.has_method("get_follow_offset") else Vector3.ZERO
	if offset.length_squared() < 0.001:
		_top_down_camera.call("set_follow_offset", Vector3(0.0, 72.0, 0.0))
	if _top_down_camera.has_method("set_projection"):
		_top_down_camera.call("set_projection", 1) # Orthographic
	if _top_down_camera.has_method("set_size"):
		var current_size: float = float(_top_down_camera.call("get_size"))
		if current_size < top_down_size_min:
			_top_down_camera.call("set_size", clampf(72.0, top_down_size_min, top_down_size_max))

func _apply_editor_camera_pose() -> void:
	if _editor_camera == null or _camera_focus == null:
		return
	var yaw: float = deg_to_rad(_editor_yaw_degrees)
	var pitch: float = deg_to_rad(_editor_pitch_degrees)
	var offset := Vector3(
		_editor_distance * cos(pitch) * sin(yaw),
		_editor_distance * sin(pitch),
		_editor_distance * cos(pitch) * cos(yaw)
	)
	if _editor_camera.has_method("set_follow_offset"):
		_editor_camera.call("set_follow_offset", offset)
	# Place the PCam node at the actual camera world position so look_at
	# produces the correct rotation. Phantom Camera uses global_basis from
	# this node for the Camera3D rotation in SIMPLE follow mode.
	_editor_camera.global_position = _camera_focus.global_position + offset
	_editor_camera.look_at(_camera_focus.global_position, Vector3.UP)

func _pan_editor_focus(mouse_delta: Vector2) -> void:
	if _camera_focus == null or _camera == null:
		return
	var right: Vector3 = _camera.global_basis.x
	var forward: Vector3 = -_camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	_camera_focus.global_position += (-right * mouse_delta.x + forward * mouse_delta.y) * editor_pan_speed * _editor_distance


func _restore_perspective() -> void:
	if _camera == null:
		return
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = 70.0
