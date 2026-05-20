class_name TerrainRuntimeEditor
extends RefCounted

var _terrain: Node = null
var _tool_name: String = "raise"
var _brush_size: float = 10.0
var _brush_strength: float = 0.25
var _brush_softness: float = 0.42
var _brush_mode: String = "smooth"  # "smooth" or "sharp"
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

func set_tool(tool_name: String, brush_size: float, brush_strength: float, flatten_height: float, cliff_mode: bool, overhang_amount: float) -> void:
	_tool_name = tool_name
	_brush_size = maxf(brush_size, 0.5)
	_brush_strength = clampf(brush_strength, 0.01, 1.0)
	_flatten_height = flatten_height
	_cliff_mode = cliff_mode
	_overhang_amount = overhang_amount

func set_brush_falloff(brush_softness: float, brush_mode: String) -> void:
	_brush_softness = clampf(brush_softness, 0.0, 1.0)
	_brush_mode = brush_mode

func begin_stroke(world_position: Vector3) -> void:
	if not is_available():
		return
	_terrain.call("apply_brush", _tool_name, world_position, _brush_size, _brush_strength, _flatten_height, _cliff_mode, _overhang_amount, _brush_softness, _brush_mode)

func continue_stroke(world_position: Vector3, _camera_rotation_y: float) -> void:
	if not is_available():
		return
	_terrain.call("apply_brush", _tool_name, world_position, _brush_size, _brush_strength, _flatten_height, _cliff_mode, _overhang_amount, _brush_softness, _brush_mode)

func end_stroke() -> void:
	pass

func dispose() -> void:
	_terrain = null
	_is_available = false
