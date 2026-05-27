extends Node3D
class_name CameraRig

## Offset pivot: small forward/up offset for a natural viewing position (over-shoulder feel).
@export var offset_pivot_forward: float = 0.3
@export var offset_pivot_up: float = 0.5

## Horizontal pivot (yaw) — orbit left/right around character.
@export var horizontal_pivot_name: String = "HorizontalPivot"

## Vertical pivot (pitch) — tilt up/down. Has pitch limits.
@export var vertical_pivot_name: String = "VerticalPivot"
@export var pitch_min: float = -25.0
@export var pitch_max: float = 60.0

## SpringArm3D settings.
@export var spring_length: float = 8.0
@export var spring_length_min: float = 2.0
@export var spring_length_max: float = 15.0
@export var spring_collision_margin: float = 0.4
@export var spring_collision_mask: int = 1

## Smooth damping for spring arm.
@export var spring_dampening: float = 0.15

## Smooth follow damping when auto-returning to behind-character.
@export var auto_follow_damping: float = 5.0
@export var manual_look_return_delay: float = 1.5

## Orbit damping: speed of camera returning to behind-character on direction change.
## Higher = faster/snappier, Lower = slower/smoother.
@export var orbit_return_speed: float = 8.0
@export var orbit_return_speed_idle: float = 3.0  # Slower return while character is idle

@onready var offset_pivot: Node3D = $OffsetPivot
@onready var horizontal_pivot: Node3D = $OffsetPivot/HorizontalPivot
@onready var vertical_pivot: Node3D = $OffsetPivot/HorizontalPivot/VerticalPivot
@onready var spring_arm: SpringArm3D = $OffsetPivot/HorizontalPivot/VerticalPivot/SpringArm3D
@onready var camera: Camera3D = $OffsetPivot/HorizontalPivot/VerticalPivot/SpringArm3D/Camera3D

var follow_target: Node3D = null
var yaw_degrees: float = 0.0
var pitch_degrees: float = 15.0
var is_manual_looking: bool = false
var manual_look_timeout: float = 0.0

func _ready() -> void:
	_ensure_structure()
	_configure_spring_arm()


func set_follow_target(target: Node3D) -> void:
	follow_target = target
	is_manual_looking = false
	manual_look_timeout = 0.0
	if target != null:
		# Initialize yaw to behind the character
		var char_forward := -target.global_basis.z
		char_forward.y = 0.0
		if char_forward.length_squared() > 0.001:
			char_forward = char_forward.normalized()
			yaw_degrees = fmod(rad_to_deg(atan2(-char_forward.x, -char_forward.z)) + 180.0, 360.0)


func clear_follow_target() -> void:
	follow_target = null
	is_manual_looking = false


func set_pitch(p: float) -> void:
	pitch_degrees = clampf(p, pitch_min, pitch_max)


func set_yaw(y: float) -> void:
	yaw_degrees = fmod(y + 360.0, 360.0)


func adjust_spring_length(delta: float) -> void:
	spring_length = clampf(spring_length + delta, spring_length_min, spring_length_max)
	_configure_spring_arm()


func enable_manual_look() -> void:
	is_manual_looking = true
	manual_look_timeout = manual_look_return_delay


func disable_manual_look() -> void:
	is_manual_looking = false
	manual_look_timeout = 0.0


func _process(delta: float) -> void:
	# Update offset pivot position (small forward bias for over-shoulder feel)
	offset_pivot.position = Vector3(0.0, offset_pivot_up, -offset_pivot_forward)

	# Character follow: auto-orient camera to behind character
	if follow_target != null and is_instance_valid(follow_target):
		_update_follow_behavior(delta)

	# Update rig rotation from yaw/pitch
	horizontal_pivot.rotation.y = deg_to_rad(yaw_degrees)
	vertical_pivot.rotation.x = deg_to_rad(pitch_degrees)

	# Spring arm smooth damping
	if spring_arm.margin != spring_collision_margin:
		spring_arm.margin = spring_collision_margin


func _update_follow_behavior(delta: float) -> void:
	# Determine if character is moving
	var char_vel := Vector3.ZERO
	if follow_target is CharacterBody3D:
		char_vel = (follow_target as CharacterBody3D).velocity
	var char_flat_speed := Vector2(char_vel.x, char_vel.z).length()
	var is_moving := char_flat_speed > 0.35

	# Track manual look timeout
	if is_manual_looking:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			manual_look_timeout = manual_look_return_delay
		else:
			manual_look_timeout -= delta
			if manual_look_timeout <= 0.0:
				is_manual_looking = false

	# Auto-blend yaw toward behind-character when not manually looking
	if not is_manual_looking:
		var char_forward := -follow_target.global_basis.z
		char_forward.y = 0.0
		if char_forward.length_squared() > 0.001:
			char_forward = char_forward.normalized()
			var target_yaw := fmod(rad_to_deg(atan2(-char_forward.x, -char_forward.z)) + 180.0, 360.0)

			# Faster orbit while moving, slower drift while idle
			var orbit_speed := orbit_return_speed if is_moving else orbit_return_speed_idle
			# Smoothly interpolate toward target yaw with proper angle wrapping
			yaw_degrees = _lerp_angle(yaw_degrees, target_yaw, orbit_speed * delta)


func _ensure_structure() -> void:
	if offset_pivot == null:
		offset_pivot = Node3D.new()
		offset_pivot.name = "OffsetPivot"
		add_child(offset_pivot)

	if horizontal_pivot == null:
		horizontal_pivot = Node3D.new()
		horizontal_pivot.name = "HorizontalPivot"
		offset_pivot.add_child(horizontal_pivot)

	if vertical_pivot == null:
		vertical_pivot = Node3D.new()
		vertical_pivot.name = "VerticalPivot"
		horizontal_pivot.add_child(vertical_pivot)

	if spring_arm == null:
		spring_arm = SpringArm3D.new()
		spring_arm.name = "SpringArm3D"
		spring_arm.length = spring_length
		spring_arm.margin = spring_collision_margin
		vertical_pivot.add_child(spring_arm)

	if camera == null:
		camera = Camera3D.new()
		camera.name = "Camera3D"
		spring_arm.add_child(camera)


func _lerp_angle(from: float, to: float, weight: float) -> float:
	"""Smoothly interpolate between two angles with proper wrapping."""
	# Normalize angles to [0, 360)
	from = fmod(from + 360.0, 360.0)
	to = fmod(to + 360.0, 360.0)
	
	# Find shortest path between angles
	var diff := fmod(to - from + 540.0, 360.0) - 180.0
	
	# Lerp along the shortest path
	return fmod(from + diff * clampf(weight, 0.0, 1.0) + 360.0, 360.0)


func _configure_spring_arm() -> void:
	if spring_arm != null:
		spring_arm.length = spring_length
		spring_arm.margin = spring_collision_margin
		spring_arm.collision_mask = spring_collision_mask
