extends Control
class_name WorldBrushRadialMenu

signal tool_selected(tool_name: String)
signal radius_changed(radius: float)
signal strength_changed(strength: float)

const OUTER_RADIUS: float = 222.0
const INNER_RADIUS: float = 102.0
const SLOT_RADIUS: float = 176.0
const SLOT_SIZE: float = 48.0
const ICON_SIZE: float = 30.0
const BG_COLOR: Color = Color(0.05, 0.07, 0.10, 0.64)
const BG_RING_COLOR: Color = Color(0.10, 0.14, 0.18, 0.82)
const BG_EDGE_COLOR: Color = Color(0.60, 0.72, 0.82, 0.18)
const SLOT_COLOR: Color = Color(0.01, 0.07, 0.12, 0.98)
const SLOT_EDGE: Color = Color(0.28, 0.40, 0.50, 0.34)
const HOVER_COLOR: Color = Color(0.10, 0.47, 0.86, 0.74)
const HOVER_GLOW: Color = Color(0.25, 0.62, 1.0, 0.26)

var _open: bool = false
var _center: Vector2 = Vector2.ZERO
var _pointer: Vector2 = Vector2.ZERO
var _current_tool: String = "select"
var _hovered_index: int = -1
var _visual_hover_angle: float = -PI * 0.5
var _radius: float = 10.0
var _strength: float = 0.25
var _icon_cache: Dictionary = {}

var _tool_defs: Array[Dictionary] = [
	# TOP — terrain sculpting (12 o'clock to 2 o'clock)
	{"tool": "raise",        "label": "Raise",      "icon": "res://addons/worldbrush/Assets/Icons/map_add.png",        "angle_deg": -90.0},
	{"tool": "lower",        "label": "Lower",      "icon": "res://addons/worldbrush/Assets/Icons/map_remove.png",     "angle_deg": -60.0},
	{"tool": "smooth",       "label": "Smooth",     "icon": "res://addons/worldbrush/Assets/Icons/map_smooth.png",     "angle_deg": -30.0},
	{"tool": "flatten",      "label": "Set Height", "icon": "res://addons/worldbrush/Assets/Icons/map_set_height.png", "angle_deg": 0.0},
	# RIGHT — placement / build (3 o'clock to 5 o'clock)
	{"tool": "wall",         "label": "Smart Wall", "icon": "res://addons/worldbrush/Assets/Icons/lock_add.png",       "angle_deg": 30.0},
	{"tool": "stamp",        "label": "Objects",    "icon": "res://addons/worldbrush/Assets/Icons/object_add.png",     "angle_deg": 60.0},
	# BOTTOM — water / weather (6 o'clock to 8 o'clock)
	{"tool": "waterpaint",   "label": "Water",      "icon": "res://addons/worldbrush/Assets/Icons/water_add.png",      "angle_deg": 90.0},
	{"tool": "riverdraw",    "label": "Flow",       "icon": "res://addons/worldbrush/Assets/Icons/flow_add.png",       "angle_deg": 120.0},
	{"tool": "snowpaint",    "label": "Snow",       "icon": "res://addons/worldbrush/Assets/Icons/snow_add.png",       "angle_deg": 150.0},
	# LEFT — paint / art (9 o'clock to 11 o'clock)
	{"tool": "texturepaint", "label": "Texture",    "icon": "res://addons/worldbrush/Assets/Icons/paint_withdot.png",  "angle_deg": 180.0},
	{"tool": "grasspaint",   "label": "Foliage",    "icon": "res://addons/worldbrush/Assets/Icons/foliage_add.png",    "angle_deg": -120.0},
	{"tool": "boundary",     "label": "Cliff Line", "icon": "res://addons/worldbrush/Assets/Icons/map_set_height.png",  "angle_deg": -150.0},
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(true)
	set_process_input(true)
	for def in _tool_defs:
		var icon_path: String = String(def.get("icon", ""))
		if icon_path != "" and ResourceLoader.exists(icon_path):
			_icon_cache[icon_path] = load(icon_path)

func is_open() -> bool:
	return _open

func open_hold(screen_pos: Vector2, current_tool: String, current_radius: float, current_strength: float) -> void:
	_open = true
	visible = true
	_center = screen_pos
	_pointer = screen_pos
	_current_tool = current_tool
	_radius = clampf(current_radius, 1.0, 64.0)
	_strength = clampf(current_strength, 0.05, 1.0)
	_hovered_index = _find_index_for_tool(current_tool)
	if _hovered_index >= 0:
		_visual_hover_angle = _slot_angle(_hovered_index)
	queue_redraw()

func update_pointer(screen_pos: Vector2) -> void:
	if not _open:
		return
	_pointer = screen_pos
	_update_hover_from_pointer()
	queue_redraw()

func confirm_current() -> void:
	if not _open:
		return
	if _hovered_index >= 0 and _hovered_index < _tool_defs.size():
		var tool_name: String = String(_tool_defs[_hovered_index].get("tool", "select"))
		tool_selected.emit(tool_name)
	close_menu()

func close_menu() -> void:
	_open = false
	visible = false
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event is InputEventMouseMotion:
		update_pointer((event as InputEventMouseMotion).position)
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.shift_pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_strength = clampf(_strength + 0.05, 0.05, 1.0)
			strength_changed.emit(_strength)
			queue_redraw()
			accept_event()
			return
		if mb.shift_pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_strength = clampf(_strength - 0.05, 0.05, 1.0)
			strength_changed.emit(_strength)
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_radius = clampf(_radius + 1.0, 1.0, 64.0)
			radius_changed.emit(_radius)
			queue_redraw()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_radius = clampf(_radius - 1.0, 1.0, 64.0)
			radius_changed.emit(_radius)
			queue_redraw()
			accept_event()
			return

func _process(delta: float) -> void:
	if not _open:
		return
	var target_angle: float = _visual_hover_angle
	if _hovered_index >= 0:
		target_angle = _slot_angle(_hovered_index)
	_visual_hover_angle = lerp_angle(_visual_hover_angle, target_angle, clampf(delta * 16.0, 0.0, 1.0))
	queue_redraw()

func _draw() -> void:
	if not _open:
		return

	draw_circle(_center, OUTER_RADIUS, BG_COLOR)
	draw_circle(_center, OUTER_RADIUS - 8.0, BG_RING_COLOR)
	draw_circle(_center, INNER_RADIUS, Color(0.02, 0.04, 0.07, 0.96))
	draw_arc(_center, OUTER_RADIUS - 2.0, 0.0, TAU, 120, BG_EDGE_COLOR, 2.0, true)
	draw_arc(_center, INNER_RADIUS + 6.0, 0.0, TAU, 90, Color(0.40, 0.52, 0.64, 0.15), 1.5, true)

	if _hovered_index >= 0:
		var hover_pos: Vector2 = _center + Vector2(cos(_visual_hover_angle), sin(_visual_hover_angle)) * SLOT_RADIUS
		draw_circle(hover_pos, SLOT_SIZE * 0.75, HOVER_GLOW)
		draw_circle(hover_pos, SLOT_SIZE * 0.55, HOVER_COLOR)

	for i in range(_tool_defs.size()):
		var pos: Vector2 = _slot_position(i)
		var hovered: bool = i == _hovered_index
		var scale_mul: float = 1.15 if hovered else 1.0
		var radius: float = (SLOT_SIZE * 0.5) * scale_mul
		var slot_col: Color = HOVER_COLOR if hovered else SLOT_COLOR
		draw_circle(pos, radius, slot_col)
		draw_arc(pos, radius + 1.4, 0.0, TAU, 48, SLOT_EDGE if not hovered else Color(0.62, 0.82, 1.0, 0.85), 2.0, true)
		_draw_tool_icon(i, pos, hovered)

	_draw_center_info()

func _draw_tool_icon(index: int, pos: Vector2, hovered: bool) -> void:
	var def: Dictionary = _tool_defs[index]
	var icon_path: String = String(def.get("icon", ""))
	var tex: Texture2D = _icon_cache.get(icon_path, null)
	if tex != null:
		var size: float = ICON_SIZE * (1.14 if hovered else 1.0)
		var rect := Rect2(pos - Vector2(size * 0.5, size * 0.5), Vector2(size, size))
		draw_texture_rect(tex, rect, false, Color(1.0, 1.0, 1.0, 0.98))
		return
	var label: String = String(def.get("label", "?"))
	if label.length() > 0:
		draw_string(get_theme_default_font(), pos + Vector2(-5.0, 4.0), label.left(1), HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.9, 0.95, 1.0, 0.95))

func _draw_center_info() -> void:
	var tool_label: String = _current_tool
	if _hovered_index >= 0 and _hovered_index < _tool_defs.size():
		tool_label = String(_tool_defs[_hovered_index].get("label", _current_tool))
	var font: Font = get_theme_default_font()
	var center_top: Vector2 = _center + Vector2(-82.0, -10.0)
	var center_mid: Vector2 = _center + Vector2(-82.0, 12.0)
	var center_bot: Vector2 = _center + Vector2(-82.0, 34.0)
	draw_string(font, center_top, "WorldBrush", HORIZONTAL_ALIGNMENT_LEFT, 164.0, 20, Color(0.80, 0.9, 1.0, 0.94))
	draw_string(font, center_mid, tool_label, HORIZONTAL_ALIGNMENT_LEFT, 164.0, 18, Color(0.96, 0.98, 1.0, 0.98))
	draw_string(font, center_bot, "Radius %.1f   Strength %.2f" % [_radius, _strength], HORIZONTAL_ALIGNMENT_LEFT, 164.0, 16, Color(0.71, 0.82, 0.92, 0.92))

func _update_hover_from_pointer() -> void:
	var delta: Vector2 = _pointer - _center
	var dist: float = delta.length()
	if dist < INNER_RADIUS * 0.62 or dist > OUTER_RADIUS + 16.0:
		_hovered_index = _find_index_for_tool(_current_tool)
		return
	var angle: float = atan2(delta.y, delta.x)
	var best_idx: int = -1
	var best_err: float = INF
	for i in range(_tool_defs.size()):
		var err: float = absf(wrapf(angle - _slot_angle(i), -PI, PI))
		if err < best_err:
			best_err = err
			best_idx = i
	if best_idx >= 0:
		_hovered_index = best_idx

func _slot_angle(index: int) -> float:
	var def: Dictionary = _tool_defs[index]
	if def.has("angle_deg"):
		return deg_to_rad(float(def.get("angle_deg", -90.0)))
	return ((TAU / float(_tool_defs.size())) * float(index)) - PI * 0.5

func _slot_position(index: int) -> Vector2:
	var a: float = _slot_angle(index)
	return _center + Vector2(cos(a), sin(a)) * SLOT_RADIUS

func _find_index_for_tool(tool_name: String) -> int:
	for i in range(_tool_defs.size()):
		if String(_tool_defs[i].get("tool", "")) == tool_name:
			return i
	return -1
