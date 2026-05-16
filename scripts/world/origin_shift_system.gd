## OriginShiftSystem — prevents floating-point precision drift in large worlds.
##
## When the camera's horizontal (XZ) position drifts more than SHIFT_THRESHOLD
## meters from the world origin, all tracked scene nodes are translated back
## toward (0,0,0). Only horizontal drift is corrected; the Y axis is left intact
## so terrain heights stay consistent.
##
## Usage:
##   Add as a child node of your main scene.
##   Call setup() once during _ready() to register the scene references.
##   Optionally call register_node() for additional Node3D objects (characters, etc.)
##   that need to follow the shift.
extends Node

## Emitted after every successful recentering with the applied world offset.
signal world_shifted(offset: Vector3)

## Horizontal distance (meters) from origin that triggers recentering.
@export var shift_threshold: float = 200.0

var _camera: Camera3D = null
var _terrain_root: Node3D = null
var _stamp_root: Node3D = null
var _scatter_system: Node = null
var _wall_system_getter: Callable = Callable()
var _horizon_system: Node3D = null
## Extra Node3D objects that should be shifted (e.g. character controllers).
var _extra_nodes: Array = []


## Register all scene-level systems. Call once from main _ready().
func setup(
		camera: Camera3D,
		terrain_root: Node3D,
		stamp_root: Node3D,
		scatter_system: Node,
		wall_system_getter: Callable,
		horizon_system: Node3D) -> void:
	_camera = camera
	_terrain_root = terrain_root
	_stamp_root = stamp_root
	_scatter_system = scatter_system
	_wall_system_getter = wall_system_getter
	_horizon_system = horizon_system


## Register a Node3D that should be translated on every world shift.
func register_node(n: Node3D) -> void:
	if n != null and not _extra_nodes.has(n):
		_extra_nodes.append(n)


## Unregister a previously registered node (e.g. when it is freed).
func unregister_node(n: Node3D) -> void:
	_extra_nodes.erase(n)


func _process(_delta: float) -> void:
	if _camera == null:
		return

	# Read the orbit camera's logical target position for drift measurement.
	# Falls back to global_position if the camera doesn't expose target_position.
	var target: Vector3 = Vector3.ZERO
	if "target_position" in _camera:
		target = _camera.get("target_position") as Vector3
	else:
		target = _camera.global_position

	var horizontal_drift: float = Vector2(target.x, target.z).length()
	if horizontal_drift < shift_threshold:
		return

	# Shift everything toward the origin using the horizontal component only.
	var offset := Vector3(-target.x, 0.0, -target.z)
	_perform_shift(offset)


func _perform_shift(offset: Vector3) -> void:
	# Terrain root: translate the Node3D — all children (mesh, grass, etc.) follow.
	if is_instance_valid(_terrain_root):
		_terrain_root.global_position += offset

	# Stamp root: translate the Node3D — all placed prefab children follow.
	if is_instance_valid(_stamp_root):
		_stamp_root.global_position += offset

	# Scatter system: node stays at origin; internal record positions are patched
	# so future brush strokes remain correctly mapped.
	if _scatter_system != null and is_instance_valid(_scatter_system):
		if _scatter_system.has_method("apply_origin_shift"):
			_scatter_system.call("apply_origin_shift", offset)

	# Wall system: node stays at origin; stored segment positions are patched
	# so rebuilt geometry appears at the correct new world positions.
	if _wall_system_getter.is_valid():
		var ws: Node = _wall_system_getter.call()
		if ws != null and is_instance_valid(ws) and ws.has_method("apply_origin_shift"):
			ws.call("apply_origin_shift", offset)

	# Horizon system: node translates (mesh children follow) and internal stored
	# positions are patched to keep serialization round-trips consistent.
	if is_instance_valid(_horizon_system):
		_horizon_system.global_position += offset
		if _horizon_system.has_method("apply_origin_shift"):
			_horizon_system.call("apply_origin_shift", offset)

	# Extra registered nodes (character controllers, VFX roots, etc.).
	for item in _extra_nodes:
		if item != null and is_instance_valid(item):
			(item as Node3D).global_position += offset

	# Shift the orbit camera's target_position so it continues looking at the
	# same logical world location without any visible discontinuity.
	if "target_position" in _camera:
		_camera.set("target_position",
				(_camera.get("target_position") as Vector3) + offset)

	world_shifted.emit(offset)
