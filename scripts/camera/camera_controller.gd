extends Node3D
class_name CameraController

var CameraRigScript = preload("res://scripts/camera/camera_rig.gd")

## ============================================================================
## Camera Mode Management
## ============================================================================
enum CameraMode { TOP_DOWN, EDITOR_FREE, CHARACTER_FOLLOW }

@export var starting_mode: CameraMode = CameraMode.TOP_DOWN

## ============================================================================
## Top-Down Mode Settings
## ============================================================================
@export var topdown_orthographic_size: float = 60.0
@export var topdown_size_min: float = 20.0
@export var topdown_size_max: float = 150.0
@export var topdown_size_step: float = 5.0
@export var topdown_pan_speed: float = 0.02
@export var topdown_height: float = 80.0

## ============================================================================
## Editor Free Orbit Settings
## ============================================================================
@export var editor_distance: float = 30.0
@export var editor_distance_min: float = 10.0
@export var editor_distance_max: float = 120.0
@export var editor_zoom_step: float = 3.0
@export var editor_orbit_sensitivity: float = 0.25
@export var editor_pan_speed: float = 0.02
@export var editor_yaw_start: float = -45.0
@export var editor_pitch_start: float = 35.0

## ============================================================================
## Character Follow Mode Settings
## ============================================================================
@export var follow_height_offset: float = 1.3
@export var follow_shoulder_offset_x: float = 0.6
@export var follow_shoulder_offset_y: float = 0.2
@export var follow_smooth_damping: float = 8.0
@export var auto_return_speed: float = 5.0
@export var manual_return_delay: float = 1.2
@export var rmb_orbit_sensitivity: float = 0.2
@export var spring_length: float = 8.0
@export var spring_length_min: float = 2.0
@export var spring_length_max: float = 15.0
@export var spring_zoom_step: float = 0.5

## ============================================================================
## Hierarchical Rig Settings
## ============================================================================
@export var offset_pivot_forward: float = 0.3
@export var offset_pivot_up: float = 0.5
@export var pitch_min: float = -25.0
@export var pitch_max: float = 60.0
@export var spring_collision_mask: int = 1

# References
@onready var camera_rig: Node3D = get_node_or_null("CameraRig")
@onready var viewport_camera: Camera3D = get_viewport().get_camera_3d()

# State
var current_mode: CameraMode = CameraMode.TOP_DOWN
var follow_target: Node3D = null
var is_manual_looking: bool = false
var manual_look_timer: float = 0.0
var rmb_drag_start: Vector2 = Vector2.ZERO
var is_rmb_dragging: bool = false

# Editor mode state
var editor_yaw: float = -45.0
var editor_pitch: float = 35.0
var editor_current_distance: float = 30.0

# Top-down mode state
var topdown_focus: Vector3 = Vector3.ZERO

const RMB_DRAG_THRESHOLD: float = 4.0
const CHARACTER_MOVING_THRESHOLD: float = 0.35


func _ready() -> void:
	_ensure_camera_rig()
	_set_mode(starting_mode)


func _ensure_camera_rig() -> void:
	if camera_rig == null:
		camera_rig = CameraRigScript.new()
		camera_rig.name = "CameraRig"
		camera_rig.offset_pivot_forward = offset_pivot_forward
		camera_rig.offset_pivot_up = offset_pivot_up
		camera_rig.pitch_min = pitch_min
		camera_rig.pitch_max = pitch_max
		camera_rig.spring_length = spring_length
		camera_rig.spring_length_min = spring_length_min
		camera_rig.spring_length_max = spring_length_max
		camera_rig.spring_collision_mask = spring_collision_mask
		camera_rig.auto_follow_damping = auto_return_speed
		camera_rig.manual_look_return_delay = manual_return_delay
		add_child(camera_rig)
		await get_tree().process_frame


func _input(event: InputEvent) -> void:
	# Tab to switch camera modes
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_cycle_camera_mode()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_P:
			if current_mode == CameraMode.EDITOR_FREE:
				toggle_projection_mode()
			get_viewport().set_input_as_handled()
			return


func _unhandled_input(event: InputEvent) -> void:
	match current_mode:
		CameraMode.TOP_DOWN:
			_handle_topdown_input(event)
		CameraMode.EDITOR_FREE:
			_handle_editor_input(event)
		CameraMode.CHARACTER_FOLLOW:
			_handle_follow_input(event)


func _process(delta: float) -> void:
	match current_mode:
		CameraMode.TOP_DOWN:
			_update_topdown(delta)
		CameraMode.EDITOR_FREE:
			_update_editor(delta)
		CameraMode.CHARACTER_FOLLOW:
			_update_follow(delta)


## ============================================================================
## Mode Management
## ============================================================================

func set_follow_target(target: Node3D) -> void:
	follow_target = target
	if target != null and current_mode != CameraMode.CHARACTER_FOLLOW:
		_set_mode(CameraMode.CHARACTER_FOLLOW)
	elif target == null and current_mode == CameraMode.CHARACTER_FOLLOW:
		_set_mode(CameraMode.EDITOR_FREE)


func clear_follow_target() -> void:
	follow_target = null
	if current_mode == CameraMode.CHARACTER_FOLLOW:
		_set_mode(CameraMode.EDITOR_FREE)


func _cycle_camera_mode() -> void:
	match current_mode:
		CameraMode.TOP_DOWN:
			if follow_target != null and is_instance_valid(follow_target):
				_set_mode(CameraMode.CHARACTER_FOLLOW)
			else:
				_set_mode(CameraMode.EDITOR_FREE)
		CameraMode.EDITOR_FREE:
			if follow_target != null and is_instance_valid(follow_target):
				_set_mode(CameraMode.CHARACTER_FOLLOW)
			else:
				_set_mode(CameraMode.TOP_DOWN)
		CameraMode.CHARACTER_FOLLOW:
			_set_mode(CameraMode.TOP_DOWN)


func _set_mode(new_mode: CameraMode) -> void:
	current_mode = new_mode
	is_manual_looking = false
	manual_look_timer = 0.0

	if camera_rig != null:
		if new_mode == CameraMode.CHARACTER_FOLLOW and follow_target != null:
			camera_rig.set_follow_target(follow_target)
		else:
			camera_rig.clear_follow_target()

	if viewport_camera != null:
		match new_mode:
			CameraMode.TOP_DOWN:
				viewport_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
				viewport_camera.size = topdown_orthographic_size
			CameraMode.EDITOR_FREE:
				viewport_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				viewport_camera.fov = 55.0
			CameraMode.CHARACTER_FOLLOW:
				viewport_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				viewport_camera.fov = 55.0


func toggle_projection_mode() -> void:
	if viewport_camera == null or current_mode != CameraMode.EDITOR_FREE:
		return
	if viewport_camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		viewport_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		viewport_camera.size = 30.0
	else:
		viewport_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		viewport_camera.fov = 55.0


## ============================================================================
## Top-Down Mode
## ============================================================================

func _handle_topdown_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			topdown_orthographic_size = clampf(topdown_orthographic_size - topdown_size_step, topdown_size_min, topdown_size_max)
			if viewport_camera != null:
				viewport_camera.size = topdown_orthographic_size
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			topdown_orthographic_size = clampf(topdown_orthographic_size + topdown_size_step, topdown_size_min, topdown_size_max)
			if viewport_camera != null:
				viewport_camera.size = topdown_orthographic_size
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or (Input.is_key_pressed(KEY_ALT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
			var delta: Vector2 = (event as InputEventMouseMotion).relative
			topdown_focus -= Vector3(delta.x, 0.0, delta.y) * topdown_pan_speed * topdown_orthographic_size
			get_viewport().set_input_as_handled()


func _update_topdown(_delta: float) -> void:
	if viewport_camera == null:
		return
	viewport_camera.global_position = topdown_focus + Vector3(0.0, topdown_height, 0.0)
	viewport_camera.look_at(topdown_focus, Vector3.UP)


## ============================================================================
## Editor Free Orbit Mode
## ============================================================================

func _handle_editor_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			editor_current_distance = clampf(editor_current_distance - editor_zoom_step, editor_distance_min, editor_distance_max)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			editor_current_distance = clampf(editor_current_distance + editor_zoom_step, editor_distance_min, editor_distance_max)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			editor_yaw -= mm.relative.x * editor_orbit_sensitivity
			editor_pitch = clampf(editor_pitch - mm.relative.y * editor_orbit_sensitivity, -75.0, 85.0)
			get_viewport().set_input_as_handled()
		elif Input.is_key_pressed(KEY_ALT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var right := viewport_camera.global_basis.x
			var forward := -viewport_camera.global_basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.0001:
				forward = forward.normalized()
			topdown_focus += (-right * mm.relative.x + forward * mm.relative.y) * editor_pan_speed * editor_current_distance
			get_viewport().set_input_as_handled()


func _update_editor(_delta: float) -> void:
	if viewport_camera == null:
		return
	var yaw: float = deg_to_rad(editor_yaw)
	var pitch: float = deg_to_rad(editor_pitch)
	var offset := Vector3(
		editor_current_distance * cos(pitch) * sin(yaw),
		editor_current_distance * sin(pitch),
		editor_current_distance * cos(pitch) * cos(yaw)
	)
	viewport_camera.global_position = topdown_focus + offset
	viewport_camera.look_at(topdown_focus, Vector3.UP)


## ============================================================================
## Character Follow Mode
## ============================================================================

func _handle_follow_input(event: InputEvent) -> void:
	if camera_rig == null:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				rmb_drag_start = event.position
				is_rmb_dragging = false
			else:
				is_rmb_dragging = false

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_rig.adjust_spring_length(-spring_zoom_step)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_rig.adjust_spring_length(spring_zoom_step)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if not is_rmb_dragging:
			if mm.position.distance_to(rmb_drag_start) > RMB_DRAG_THRESHOLD:
				is_rmb_dragging = true
		if is_rmb_dragging:
			camera_rig.enable_manual_look()
			camera_rig.set_pitch(camera_rig.pitch_degrees - mm.relative.y * rmb_orbit_sensitivity)
			camera_rig.set_yaw(camera_rig.yaw_degrees - mm.relative.x * rmb_orbit_sensitivity)
			get_viewport().set_input_as_handled()


func _update_follow(_delta: float) -> void:
	if camera_rig == null or follow_target == null or not is_instance_valid(follow_target):
		follow_target = null
		if current_mode == CameraMode.CHARACTER_FOLLOW:
			_set_mode(CameraMode.EDITOR_FREE)
		return

	# Update the rig's camera to be the actual viewport camera
	if viewport_camera != null and camera_rig.camera != viewport_camera:
		# The camera_rig.camera should already be the one in the hierarchy
		# but ensure the viewport is using it
		if not viewport_camera.current:
			camera_rig.camera.make_current()

	# Reposition follow target to character
	camera_rig.global_position = follow_target.global_position


## ============================================================================
## Utility Methods
## ============================================================================

func recenter() -> void:
	topdown_focus = Vector3.ZERO
	editor_yaw = editor_yaw_start
	editor_pitch = editor_pitch_start
	editor_current_distance = editor_distance


func get_current_mode() -> CameraMode:
	return current_mode


func is_in_character_follow() -> bool:
	return current_mode == CameraMode.CHARACTER_FOLLOW


func is_in_top_down() -> bool:
	return current_mode == CameraMode.TOP_DOWN
