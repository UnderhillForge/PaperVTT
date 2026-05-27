class_name CharacterController
extends CharacterBody3D

signal selection_changed(character: CharacterController, selected: bool)

@export var walk_speed: float = 5.0
@export var run_speed: float = 8.0
@export var acceleration: float = 20.0
@export var air_acceleration: float = 7.0
@export var jump_velocity: float = 5.8
@export var gravity_multiplier: float = 1.0
@export var click_stop_distance: float = 0.2
@export var rotate_speed: float = 10.0
@export var manual_turn_speed_degrees: float = 180.0
@export var move_mode: int = 0 # 0 = camera_relative, 1 = world_axes
@export var extra_animation_scenes: Array[PackedScene] = []
@export var preferred_idle_animation: String = ""
@export var preferred_walk_animation: String = ""
@export var preferred_run_animation: String = ""
@export var preferred_jump_animation: String = ""

@export_node_path("NavigationAgent3D") var navigation_agent_path: NodePath
@export_node_path("Node3D") var model_root_path: NodePath

static var active_controller: CharacterController = null

var _camera: Camera3D = null
var _terrain: Node = null
var _nav_agent: NavigationAgent3D = null
var _model_root: Node3D = null
var _anim_player: AnimationPlayer = null
var _is_selected: bool = false
var _has_move_target: bool = false
var _move_target: Vector3 = Vector3.ZERO
var _terrain_grounded: bool = false
var _anim_map: Dictionary = {"idle": "", "walk": "", "run": "", "jump": ""}
var _last_anim: String = ""
var _selection_shadow: MeshInstance3D = null
var _selection_shadow_material: StandardMaterial3D = null
var _selection_pulse: float = 0.0
var _selection_shadow_texture: Texture2D = null

const _SHADOW_SIZE: float = 1.35
const _SHADOW_Y_OFFSET: float = 0.03
const _MOVE_INTENT_THRESHOLD: float = 0.1

func _ready() -> void:
	add_to_group("character_controller")
	if navigation_agent_path != NodePath():
		_nav_agent = get_node_or_null(navigation_agent_path) as NavigationAgent3D
	if model_root_path != NodePath():
		_model_root = get_node_or_null(model_root_path) as Node3D
	if _model_root == null:
		_model_root = self
	_anim_player = _find_animation_player(_model_root)
	_merge_extra_animation_scenes()
	_cache_animation_names()
	_create_selection_shadow()
	_set_selected(false)

func initialize_controller(cam: Camera3D, terrain: Node) -> void:
	_camera = cam
	_terrain = terrain
	_snap_to_terrain_if_available()

func handle_input_event(event: InputEvent, hovered_ui: bool) -> bool:
	if hovered_ui:
		return false

	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if _screen_ray_hits_self(mb.position):
				_has_move_target = false
				_set_selected(true)
				return true
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if _screen_ray_hits_self(mb.position):
				_set_selected(true)
				return true
			if _is_selected:
				var world_point: Variant = _screen_to_world(mb.position)
				if world_point is Vector3:
					_set_move_target(world_point as Vector3)
					return true
	return false

func _physics_process(delta: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * gravity_multiplier
	_terrain_grounded = false

	if not _is_grounded():
		velocity.y -= gravity * delta

	var run_pressed: bool = Input.is_key_pressed(KEY_SHIFT)
	var speed_target: float = run_speed if run_pressed else walk_speed
	var input_dir: Vector2 = _get_move_input() if _is_selected else Vector2.ZERO
	var desired_dir: Vector3 = Vector3.ZERO
	var has_move_intent: bool = false
	var manual_steering_active: bool = false

	if input_dir != Vector2.ZERO:
		_has_move_target = false
		manual_steering_active = true
		_apply_manual_turn(input_dir.x, delta)
		desired_dir = _input_to_character_dir(input_dir)
		has_move_intent = absf(input_dir.y) > _MOVE_INTENT_THRESHOLD
	elif _has_move_target:
		desired_dir = _target_move_dir()
		has_move_intent = desired_dir.length() > _MOVE_INTENT_THRESHOLD

	var target_velocity: Vector3 = desired_dir * speed_target
	target_velocity.y = velocity.y

	var accel: float = acceleration if _is_grounded() else air_acceleration
	velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)

	if _is_selected and _is_grounded() and Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity
		_has_move_target = false

	move_and_slide()
	_snap_to_terrain_if_available()
	if not manual_steering_active:
		_update_facing(delta)
	_update_animation_state(run_pressed, has_move_intent)
	_update_selection_shadow_transform()
	_update_selection_feedback(delta)


func _apply_manual_turn(turn_input: float, delta: float) -> void:
	if absf(turn_input) < 0.001:
		return
	rotation.y -= deg_to_rad(manual_turn_speed_degrees) * turn_input * delta


func _input_to_character_dir(input_dir: Vector2) -> Vector3:
	# Character-relative steering: Up/Down drives along current facing; Left/Right only turns.
	if absf(input_dir.y) < 0.001:
		return Vector3.ZERO
	var forward: Vector3 = _model_root.global_basis.z if _model_root != null else global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	return forward * input_dir.y

func deselect() -> void:
	_set_selected(false)

func _create_selection_shadow() -> void:
	_selection_shadow = MeshInstance3D.new()
	_selection_shadow.name = "SelectionShadow"
	var mesh := QuadMesh.new()
	mesh.size = Vector2(_SHADOW_SIZE, _SHADOW_SIZE)
	_selection_shadow.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.05, 0.12, 0.16, 0.5)
	mat.emission_enabled = false
	_selection_shadow_texture = _build_shadow_texture(128)
	if _selection_shadow_texture != null:
		mat.albedo_texture = _selection_shadow_texture
	_selection_shadow_material = mat
	_selection_shadow.material_override = mat
	_selection_shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_selection_shadow.visible = false
	add_child(_selection_shadow)

func _build_shadow_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size * 0.5, size * 0.5)
	var radius: float = size * 0.5
	for y in size:
		for x in size:
			var p := Vector2(float(x) + 0.5, float(y) + 0.5)
			var t: float = p.distance_to(center) / radius
			t = clampf(t, 0.0, 1.0)
			# Ease out for a softer pen-ink style edge.
			var alpha: float = pow(1.0 - t, 1.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

func is_selected() -> bool:
	return _is_selected

func _set_selected(value: bool) -> void:
	if value and active_controller != null and active_controller != self:
		active_controller._set_selected(false)

	_is_selected = value
	if _selection_shadow != null:
		_selection_shadow.visible = _is_selected
	if _is_selected:
		active_controller = self
		scale = Vector3.ONE * 1.03
	else:
		if active_controller == self:
			active_controller = null
		scale = Vector3.ONE
	selection_changed.emit(self, _is_selected)

func _update_selection_feedback(delta: float) -> void:
	if _selection_shadow == null or _selection_shadow_material == null:
		return
	if not _is_selected:
		_selection_shadow.scale = Vector3.ONE
		_selection_shadow_material.albedo_color = Color(0.05, 0.12, 0.16, 0.5)
		return
	_selection_pulse = fmod(_selection_pulse + delta * 3.0, TAU)
	var pulse: float = 0.5 + 0.5 * sin(_selection_pulse)
	var shadow_scale: float = 1.0 + pulse * 0.05
	_selection_shadow.scale = Vector3(shadow_scale, 1.0, shadow_scale)
	_selection_shadow_material.albedo_color = Color(0.05, 0.12, 0.16, 0.42 + pulse * 0.14)

func _update_selection_shadow_transform() -> void:
	if _selection_shadow == null:
		return
	var sample_pos: Vector3 = global_position
	var ground_y: float = _sample_terrain_height(sample_pos.x, sample_pos.z)
	_selection_shadow.global_position = Vector3(sample_pos.x, ground_y + _SHADOW_Y_OFFSET, sample_pos.z)

func _set_move_target(world_target: Vector3) -> void:
	world_target.y = _sample_terrain_height(world_target.x, world_target.z)
	_move_target = world_target
	_has_move_target = true
	if _nav_agent != null:
		_nav_agent.target_position = world_target

func _get_move_input() -> Vector2:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		dir.y += 1.0
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		dir.y -= 1.0
	return dir.normalized()

func _input_to_world_dir(input_dir: Vector2) -> Vector3:
	if move_mode == 1 or _camera == null:
		return Vector3(input_dir.x, 0.0, input_dir.y).normalized()

	var forward: Vector3 = -_camera.global_basis.z
	forward.y = 0.0
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3.FORWARD
	var right: Vector3 = _camera.global_basis.x
	right.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()
	else:
		right = Vector3.RIGHT
	var out: Vector3 = right * input_dir.x + forward * input_dir.y
	out.y = 0.0
	if out.length_squared() < 0.0001:
		return Vector3.ZERO
	return out.normalized()

func _target_move_dir() -> Vector3:
	var target: Vector3 = _move_target
	# Try NavAgent if available
	if _nav_agent != null and not _nav_agent.is_navigation_finished():
		var nav_next: Vector3 = _nav_agent.get_next_path_position()
		if nav_next.distance_to(global_position) > click_stop_distance * 0.5:
			target = nav_next
	# Direct line-of-sight fallback: always try this to ensure movement works
	var to_target: Vector3 = target - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()
	if dist <= click_stop_distance:
		_has_move_target = false
		if _nav_agent != null:
			_nav_agent.target_position = global_position
		return Vector3.ZERO
	return to_target / maxf(dist, 0.0001)

func _is_grounded() -> bool:
	return is_on_floor() or _terrain_grounded

func _snap_to_terrain_if_available() -> void:
	if _terrain == null or not _terrain.has_method("sample_height"):
		return
	var h: float = _sample_terrain_height(global_position.x, global_position.z)
	if global_position.y <= h + 0.03 and velocity.y <= 0.0:
		global_position.y = h
		velocity.y = 0.0
		_terrain_grounded = true

func _sample_terrain_height(x: float, z: float) -> float:
	if _terrain != null and _terrain.has_method("sample_height"):
		return float(_terrain.call("sample_height", x, z))
	return global_position.y

func _screen_to_world(screen_pos: Vector2) -> Variant:
	if _camera == null:
		return null
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)

	if _terrain != null and _terrain.has_method("get_intersection"):
		var p: Variant = _terrain.call("get_intersection", origin, dir, true)
		if p is Vector3:
			return p

	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 1000.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty() and hit.has("position"):
		return hit["position"]
	return null

func _screen_ray_hits_self(screen_pos: Vector2) -> bool:
	if _camera == null:
		return false
	var origin: Vector3 = _camera.project_ray_origin(screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(screen_pos)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 1000.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider", null)
	if collider == null:
		return false
	if collider == self:
		return true
	if collider is Node:
		return (collider as Node).is_ancestor_of(self) or self.is_ancestor_of(collider as Node)
	return false

func _update_facing(delta: float) -> void:
	var planar_vel: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if planar_vel.length() < 0.05:
		return
	var target_yaw: float = atan2(planar_vel.x, planar_vel.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * rotate_speed, 0.0, 1.0))

func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child in root.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null

func _cache_animation_names() -> void:
	if _anim_player == null:
		return
	for key in _anim_map.keys():
		_anim_map[key] = ""
	_anim_map["idle"] = _resolve_animation_name(preferred_idle_animation, ["Idle_A", "Idle_B"], ["idle"])
	_anim_map["walk"] = _resolve_animation_name(preferred_walk_animation, ["Walking_A", "Walking_B", "Walking_C"], ["walk"])
	_anim_map["run"] = _resolve_animation_name(preferred_run_animation, ["Running_A", "Running_B"], ["run"])
	_anim_map["jump"] = _resolve_animation_name(preferred_jump_animation, ["Jump_Full_Short", "Jump_Full_Long", "Jump_Idle", "Jump_Start"], ["jump", "air"])
	# Ensure locomotion clips loop; jump plays once
	_set_animation_loop(_anim_map["idle"], true)
	_set_animation_loop(_anim_map["walk"], true)
	_set_animation_loop(_anim_map["run"], true)
	_set_animation_loop(_anim_map["jump"], false)

func _set_animation_loop(clip_name: String, should_loop: bool) -> void:
	if _anim_player == null or clip_name == "":
		return
	if not _anim_player.has_animation(clip_name):
		return
	var anim := _anim_player.get_animation(clip_name)
	if anim == null:
		return
	anim.loop_mode = Animation.LOOP_LINEAR if should_loop else Animation.LOOP_NONE

func _resolve_animation_name(preferred: String, exact_candidates: Array[String], contains_candidates: Array[String]) -> String:
	if _anim_player == null:
		return ""
	if preferred != "" and _anim_player.has_animation(preferred):
		return preferred
	for candidate in exact_candidates:
		if _anim_player.has_animation(candidate):
			return candidate
	for animation_name in _anim_player.get_animation_list():
		var lower: String = String(animation_name).to_lower()
		for token in contains_candidates:
			if lower.contains(token):
				return String(animation_name)
	return ""

func _merge_extra_animation_scenes() -> void:
	if _anim_player == null or extra_animation_scenes.is_empty():
		return
	var target_library: AnimationLibrary = _anim_player.get_animation_library("")
	if target_library == null:
		target_library = AnimationLibrary.new()
		_anim_player.add_animation_library("", target_library)
	for scene in extra_animation_scenes:
		if scene == null:
			continue
		var root := scene.instantiate()
		var source_player: AnimationPlayer = _find_animation_player(root)
		if source_player == null:
			root.free()
			continue
		for animation_name in source_player.get_animation_list():
			if _anim_player.has_animation(animation_name):
				continue
			var animation: Animation = source_player.get_animation(animation_name)
			if animation == null:
				continue
			target_library.add_animation(animation_name, animation.duplicate(true))
		root.free()

func _update_animation_state(run_pressed: bool, has_move_intent: bool) -> void:
	if _anim_player == null:
		return
	var state: String = "idle"
	var planar_speed: float = Vector2(velocity.x, velocity.z).length()
	if not _is_grounded():
		state = "jump"
	elif planar_speed > 0.15 or has_move_intent:
		state = "run" if run_pressed else "walk"

	var clip: String = _anim_map.get(state, "")
	if clip == "":
		clip = _anim_map.get("walk", "") if state == "run" else _anim_map.get("idle", "")
	if clip == "":
		return
	if clip == _last_anim and _anim_player.is_playing():
		return

	_anim_player.play(clip, 0.12)
	_last_anim = clip
