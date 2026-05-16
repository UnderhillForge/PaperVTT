class_name TerrainRuntimeEditor
extends RefCounted

var _terrain: Node = null
var _tool_name: String = "raise"
var _brush_size: float = 10.0
var _brush_strength: float = 0.25
var _flatten_height: float = 0.0
var _cliff_mode: bool = false
var _overhang_amount: float = 0.3
var _is_available: bool = false

func initialize(terrain: Node) -> bool:
	_terrain = terrain
	_is_available = _terrain != null and _terrain.has_method("apply_brush")
	return _is_available

func is_available() -> bool:
	return _is_available

func set_tool(tool_name: String, brush_size: float, brush_strength: float, flatten_height: float = 0.0, cliff_mode: bool = false, overhang_amount: float = 0.3) -> void:
	_tool_name = tool_name
	_brush_size = maxf(brush_size, 0.5)
	_brush_strength = clampf(brush_strength, 0.01, 1.0)
	_flatten_height = flatten_height
	_cliff_mode = cliff_mode
	_overhang_amount = overhang_amount

func bootstrap_new_map(seed: int = 1337) -> bool:
	if not is_available():
		return false
	if _terrain.has_method("initialize_new_map"):
		_terrain.call("initialize_new_map", seed)
	return true

func begin_stroke(world_position: Vector3) -> void:
	if not is_available():
		return
	_terrain.call("apply_brush", _tool_name, world_position, _brush_size, _brush_strength, _flatten_height, _cliff_mode, _overhang_amount)

func continue_stroke(world_position: Vector3, _camera_rotation_y: float) -> void:
	if not is_available():
		return
	_terrain.call("apply_brush", _tool_name, world_position, _brush_size, _brush_strength, _flatten_height, _cliff_mode, _overhang_amount)

func end_stroke() -> void:
	pass

func dispose() -> void:
	_terrain = null
	_is_available = false
