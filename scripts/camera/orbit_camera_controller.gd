extends Camera3D

@export var distance: float = 30.0
@export var min_distance: float = 5.0
@export var max_distance: float = 120.0
@export var rotation_speed: float = 0.25
@export var zoom_speed: float = 3.0
@export var zoom_smoothing: float = 10.0
@export var pan_speed: float = 0.03
@export var keyboard_pan_speed: float = 20.0
@export var third_person_distance: float = 7.0
@export var third_person_pitch: float = 22.0
@export var follow_smooth_speed: float = 10.0
@export var follow_height_offset: float = 1.0
@export var auto_follow_return_delay: float = 1.2
@export var auto_follow_blend_speed: float = 4.0

var target_position: Vector3 = Vector3.ZERO
var yaw_degrees: float = -45.0
var pitch_degrees: float = 52.0
var is_top_down: bool = true
var _target_distance: float = 30.0
var _follow_target: Node3D = null
var _is_third_person: bool = false
var _right_drag_start: Vector2 = Vector2.ZERO
var _right_dragging: bool = false
var _is_manual_looking: bool = false
var _manual_look_timeout: float = 0.0
const _RIGHT_ORBIT_THRESHOLD: float = 4.0
const _CHAR_MOVING_THRESHOLD: float = 0.4

func _ready() -> void:
	projection = Camera3D.PROJECTION_PERSPECTIVE
	fov = 55.0
	_target_distance = distance
	_update_camera_transform()

func set_follow_target(target: Node3D) -> void:
	_follow_target = target
	if target != null and not _is_third_person:
		_enter_third_person()

func clear_follow_target() -> void:
	_exit_third_person()
	set_top_down_default()

func _enter_third_person() -> void:
	_is_third_person = true
	_is_manual_looking = false
	_manual_look_timeout = 0.0
	_target_distance = third_person_distance
	distance = third_person_distance
	pitch_degrees = third_person_pitch
	if _follow_target != null:
		target_position = _follow_target.global_position + Vector3(0, follow_height_offset, 0)
		# Start with camera behind the character so the first frame is already right
		yaw_degrees = _yaw_behind_node(_follow_target)
	_update_camera_transform()

func _exit_third_person() -> void:
	_is_third_person = false
	_is_manual_looking = false
	_manual_look_timeout = 0.0
	_follow_target = null

func _unhandled_input(event: InputEvent) -> void:
	# Tab — toggle between third-person follow and top-down editor
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			if _is_third_person:
				_exit_third_person()
				set_top_down_default()
			else:
				for n in get_tree().get_nodes_in_group("character_controller"):
					if n.has_method("is_selected") and bool(n.call("is_selected")):
						set_follow_target(n as Node3D)
						break
			get_viewport().set_input_as_handled()
			return

	if event.is_action_pressed("camera_toggle_projection"):
		toggle_projection_mode()
		get_viewport().set_input_as_handled()
		return

	# Track right-button press for drag-threshold orbit detection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_right_drag_start = event.position
			_right_dragging = false
		else:
			_right_dragging = false

	if event is InputEventMouseMotion:
		# Third-person: right-drag orbits (only after drag threshold so right-click-on-character still works)
		if _is_third_person and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			if not _right_dragging:
				if event.position.distance_to(_right_drag_start) > _RIGHT_ORBIT_THRESHOLD:
					_right_dragging = true
			if _right_dragging:
				_is_manual_looking = true
				_manual_look_timeout = auto_follow_return_delay
				yaw_degrees -= event.relative.x * rotation_speed
				pitch_degrees = clampf(pitch_degrees - event.relative.y * rotation_speed, -15.0, 75.0)
				_update_camera_transform()
				get_viewport().set_input_as_handled()
				return
		# Standard: middle-drag orbits
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			yaw_degrees -= event.relative.x * rotation_speed
			pitch_degrees = clampf(pitch_degrees - event.relative.y * rotation_speed, 10.0, 89.0)
			_update_camera_transform()
			get_viewport().set_input_as_handled()
		elif Input.is_key_pressed(KEY_ALT) and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_pan_from_mouse(event.relative)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_target_distance = clampf(_target_distance - zoom_speed, min_distance, max_distance)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_target_distance = clampf(_target_distance + zoom_speed, min_distance, max_distance)
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	# Third-person follow: smoothly track the character
	if _is_third_person and _follow_target != null and is_instance_valid(_follow_target):
		# Position tracking
		var desired_pos := _follow_target.global_position + Vector3(0, follow_height_offset, 0)
		target_position = target_position.lerp(desired_pos, clampf(follow_smooth_speed * delta, 0.0, 1.0))
		var zoom_t: float = clampf(delta * zoom_smoothing, 0.0, 1.0)
		distance = lerpf(distance, _target_distance, zoom_t)

		# Auto-follow yaw: chase character's facing direction when moving
		var char_vel := Vector3.ZERO
		if _follow_target is CharacterBody3D:
			char_vel = (_follow_target as CharacterBody3D).velocity
		var char_flat_speed := Vector2(char_vel.x, char_vel.z).length()
		var char_is_moving := char_flat_speed > _CHAR_MOVING_THRESHOLD

		# Keep manual look active while RMB held; start countdown on release
		if _is_manual_looking:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				_manual_look_timeout = auto_follow_return_delay
			else:
				_manual_look_timeout -= delta
				if _manual_look_timeout <= 0.0:
					_is_manual_looking = false

		# Smoothly blend yaw toward the direction behind the character while they move
		if not _is_manual_looking and char_is_moving:
			var target_yaw := _yaw_behind_node(_follow_target)
			var yaw_diff := fmod(target_yaw - yaw_degrees + 540.0, 360.0) - 180.0
			yaw_degrees += yaw_diff * clampf(auto_follow_blend_speed * delta, 0.0, 1.0)

		_update_camera_transform()
		return

	var character_selected: bool = false
	for n in get_tree().get_nodes_in_group("character_controller"):
		if n.has_method("is_selected") and bool(n.call("is_selected")):
			character_selected = true
			break

	var move: Vector3 = Vector3.ZERO
	if not character_selected:
		if Input.is_action_pressed("ui_left"):
			move.x -= 1.0
		if Input.is_action_pressed("ui_right"):
			move.x += 1.0
		if Input.is_action_pressed("ui_up"):
			move.z -= 1.0
		if Input.is_action_pressed("ui_down"):
			move.z += 1.0

	if move != Vector3.ZERO:
		var flat_forward := -global_basis.z
		flat_forward.y = 0.0
		flat_forward = flat_forward.normalized()
		var flat_right := global_basis.x
		flat_right.y = 0.0
		flat_right = flat_right.normalized()
		target_position += (flat_right * move.x + flat_forward * move.z).normalized() * keyboard_pan_speed * delta
		_update_camera_transform()

	var zoom_t: float = clampf(delta * zoom_smoothing, 0.0, 1.0)
	var old_distance: float = distance
	distance = lerpf(distance, _target_distance, zoom_t)
	if absf(distance - old_distance) > 0.001:
		_update_camera_transform()

func _pan_from_mouse(relative: Vector2) -> void:
	var right := global_basis.x
	var forward := -global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	target_position += (-right * relative.x + forward * relative.y) * pan_speed * distance
	_update_camera_transform()

func _update_camera_transform() -> void:
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(
		distance * cos(pitch) * sin(yaw),
		distance * sin(pitch),
		distance * cos(pitch) * cos(yaw)
	)
	global_position = target_position + offset
	look_at(target_position, Vector3.UP)

func toggle_projection_mode() -> void:
	is_top_down = not is_top_down
	if is_top_down:
		pitch_degrees = 85.0
	else:
		pitch_degrees = 52.0
	_target_distance = distance
	_update_camera_transform()

# Returns the yaw angle (degrees) that places the camera directly behind node's facing direction.
# In Godot -Z is forward; camera offset uses sin(yaw)/cos(yaw) so "behind" flips both axes.
func _yaw_behind_node(node: Node3D) -> float:
	var forward := -node.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return yaw_degrees  # keep current yaw if character has no planar facing
	forward = forward.normalized()
	return rad_to_deg(atan2(-forward.x, -forward.z))

func recenter() -> void:
	target_position = Vector3.ZERO
	_update_camera_transform()

func set_top_down_default() -> void:
	is_top_down = true
	yaw_degrees = -45.0
	pitch_degrees = 64.0
	distance = 46.0
	_target_distance = distance
	target_position = Vector3.ZERO
	_update_camera_transform()
