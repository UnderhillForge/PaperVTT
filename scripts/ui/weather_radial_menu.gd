extends Control
class_name WeatherRadialMenu

signal weather_selected(weather_id: String)
signal time_menu_requested

const WEATHER_ICONS: Dictionary = {
	"time": "res://assets/ui/icons/000000/transparent/1x1/lorc/hourglass.svg",
	"normal": "res://assets/ui/icons/000000/transparent/1x1/lorc/sun-radiations.svg",
	"rain": "res://assets/ui/icons/000000/transparent/1x1/lorc/raining.svg",
	"snow": "res://assets/ui/icons/000000/transparent/1x1/lorc/snowing.svg",
	"foggy": "res://assets/ui/icons/000000/transparent/1x1/delapouite/fog.svg",
	"stormy": "res://assets/ui/icons/000000/transparent/1x1/lorc/lightning-storm.svg",
}

const WEATHER_LABELS: Dictionary = {
	"time": "Time",
	"normal": "Clear",
	"rain": "Rain",
	"snow": "Snow",
	"foggy": "Foggy",
	"stormy": "Stormy",
}

const BG_COLOR: Color = Color(0.05, 0.07, 0.10, 0.64)
const BG_RING_COLOR: Color = Color(0.10, 0.14, 0.18, 0.82)
const BG_EDGE_COLOR: Color = Color(0.60, 0.72, 0.82, 0.18)
const SLOT_COLOR: Color = Color(0.01, 0.07, 0.12, 0.98)
const SLOT_EDGE: Color = Color(0.28, 0.40, 0.50, 0.34)
const HOVER_COLOR: Color = Color(0.10, 0.47, 0.86, 0.74)
const HOVER_GLOW: Color = Color(0.25, 0.62, 1.0, 0.26)
const ACTIVE_RING: Color = Color(0.78, 0.90, 1.0, 0.92)
const ACTIVE_FILL: Color = Color(0.13, 0.23, 0.34, 0.96)

const OUTER_RADIUS: float = 182.0
const INNER_RADIUS: float = 48.0
const SLOT_RADIUS: float = 148.0
const SLOT_SIZE: float = 32.0
const ICON_SIZE: float = 19.0
const START_ANGLE: float = deg_to_rad(-90.0)
const END_ANGLE: float = deg_to_rad(0.0)
const ANGLE_TOLERANCE: float = deg_to_rad(7.0)

var _is_open: bool = false
var _center: Vector2 = Vector2.ZERO
var _pointer: Vector2 = Vector2.ZERO
var _hovered_index: int = -1
var _current_weather: String = "normal"
var _icon_cache: Dictionary = {}
var _open_t: float = 0.0
var _open_tween: Tween = null

var _defs: Array[Dictionary] = [
	{"id": "time", "label": "Time"},
	{"id": "normal", "label": "Normal"},
	{"id": "rain", "label": "Rain"},
	{"id": "snow", "label": "Snow"},
	{"id": "foggy", "label": "Foggy"},
	{"id": "stormy", "label": "Stormy"},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	set_process(true)
	for def in _defs:
		var weather_id: String = String(def.get("id", ""))
		var path: String = String(WEATHER_ICONS.get(weather_id, ""))
		if path != "" and ResourceLoader.exists(path):
			var tex: Texture2D = _load_icon_as_white(path)
			if tex != null:
				_icon_cache[path] = tex


func is_open() -> bool:
	return _is_open


func open_at(global_center: Vector2, current_weather: String) -> void:
	_is_open = true
	visible = true
	_center = global_center
	_pointer = global_center
	_current_weather = current_weather
	_hovered_index = _find_index("time")
	_animate_open(true)
	queue_redraw()


func close_menu() -> void:
	_is_open = false
	_animate_open(false)


func _animate_open(opening: bool) -> void:
	if _open_tween != null:
		_open_tween.kill()
	_open_tween = get_tree().create_tween()
	_open_tween.set_trans(Tween.TRANS_CUBIC)
	_open_tween.set_ease(Tween.EASE_OUT if opening else Tween.EASE_IN)
	_open_tween.tween_property(self, "_open_t", 1.0 if opening else 0.0, 0.16)
	if not opening:
		_open_tween.tween_callback(Callable(self, "_finish_close"))


func _finish_close() -> void:
	if _is_open:
		return
	visible = false
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseMotion:
		_pointer = (event as InputEventMouseMotion).position
		_update_hover()
		queue_redraw()
		accept_event()
		return
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _hovered_index >= 0 and _hovered_index < _defs.size() and _is_pointer_in_menu(mb.position):
				var entry_id: String = String(_defs[_hovered_index].get("id", "normal"))
				if entry_id == "time":
					time_menu_requested.emit()
				else:
					weather_selected.emit(entry_id)
			close_menu()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			close_menu()
			accept_event()


func _draw() -> void:
	if not _is_open and _open_t <= 0.01:
		return
	_draw_background()
	draw_circle(_center, lerpf(2.0, 5.0, _open_t), Color(0.10, 0.14, 0.18, 0.82))
	for i in range(_defs.size()):
		_draw_slot(i)


func _draw_background() -> void:
	var outer: float = OUTER_RADIUS * _open_t
	if outer < 1.0:
		return
	draw_arc(_center, outer, START_ANGLE, END_ANGLE, 48, BG_EDGE_COLOR, 2.0, true)
	draw_arc(_center, maxf(outer - 11.0, 1.0), START_ANGLE, END_ANGLE, 48, BG_RING_COLOR, 9.0, true)
	draw_arc(_center, maxf(outer - 20.0, 1.0), START_ANGLE, END_ANGLE, 48, BG_COLOR, 14.0, true)
	draw_arc(_center, maxf(INNER_RADIUS * _open_t, 1.0), START_ANGLE, END_ANGLE, 28, Color(0.30, 0.45, 0.58, 0.22), 1.4, true)


func _draw_slot(index: int) -> void:
	var pos: Vector2 = _slot_position(index)
	var hovered: bool = index == _hovered_index
	var weather_id: String = String(_defs[index].get("id", "normal"))
	var selected: bool = weather_id == _current_weather
	var col: Color = HOVER_COLOR if hovered else (ACTIVE_FILL if selected else SLOT_COLOR)
	var slot_radius: float = (SLOT_SIZE * 0.5) * _open_t * (1.12 if hovered else 1.0)
	if slot_radius <= 0.1:
		return
	if hovered:
		draw_circle(pos, slot_radius + 6.0, HOVER_GLOW)
	draw_circle(pos, slot_radius, col)
	var edge_col: Color = ACTIVE_RING if selected else (SLOT_EDGE if not hovered else Color(0.62, 0.82, 1.0, 0.85))
	draw_arc(pos, slot_radius + 1.0, 0.0, TAU, 32, edge_col, 2.0, true)
	var icon_path: String = String(WEATHER_ICONS.get(weather_id, ""))
	var tex: Texture2D = _icon_cache.get(icon_path, null)
	if tex != null:
		var icon_size: float = ICON_SIZE * (1.15 if hovered else 1.0) * _open_t
		var rect := Rect2(pos - Vector2(icon_size, icon_size) * 0.5, Vector2(icon_size, icon_size))
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, 0.98))


func _update_hover() -> void:
	if _open_t < 0.45:
		return
	var delta: Vector2 = _pointer - _center
	var dist: float = delta.length()
	if dist < INNER_RADIUS * 0.7 or dist > (OUTER_RADIUS * _open_t) + 22.0:
		_hovered_index = _find_index(_current_weather)
		return
	var angle: float = atan2(delta.y, delta.x)
	if angle < (START_ANGLE - ANGLE_TOLERANCE) or angle > (END_ANGLE + ANGLE_TOLERANCE):
		var err_start: float = absf(wrapf(angle - START_ANGLE, -PI, PI))
		var err_end: float = absf(wrapf(angle - END_ANGLE, -PI, PI))
		_hovered_index = _find_index("time") if err_start <= err_end else _find_index("stormy")
		return
	var best_idx: int = -1
	var best_err: float = INF
	for i in range(_defs.size()):
		var err: float = absf(wrapf(angle - _slot_angle(i), -PI, PI))
		if err < best_err:
			best_err = err
			best_idx = i
	_hovered_index = best_idx


func _slot_position(index: int) -> Vector2:
	var a: float = _slot_angle(index)
	return _center + Vector2(cos(a), sin(a)) * (SLOT_RADIUS * _open_t)


func _slot_angle(index: int) -> float:
	if _defs.size() == 1:
		return (START_ANGLE + END_ANGLE) * 0.5
	var t: float = float(index) / float(_defs.size() - 1)
	return lerpf(START_ANGLE, END_ANGLE, t)


func _find_index(weather_id: String) -> int:
	for i in range(_defs.size()):
		if String(_defs[i].get("id", "")) == weather_id:
			return i
	return 0


func _is_pointer_in_menu(pointer_pos: Vector2) -> bool:
	var delta: Vector2 = pointer_pos - _center
	var dist: float = delta.length()
	if dist < INNER_RADIUS * 0.5 or dist > OUTER_RADIUS * maxf(_open_t, 0.01) + 22.0:
		return false
	var angle: float = atan2(delta.y, delta.x)
	return angle >= (START_ANGLE - ANGLE_TOLERANCE) and angle <= (END_ANGLE + ANGLE_TOLERANCE)


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _load_icon_as_white(path: String) -> Texture2D:
	var src: Texture2D = load(path) as Texture2D
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null or img.is_empty():
		return src
	img.convert(Image.FORMAT_RGBA8)
	var white_img: Image = img.duplicate()
	var make_white: bool = _should_convert_to_white(img)
	if make_white:
		for y in range(white_img.get_height()):
			for x in range(white_img.get_width()):
				var c: Color = white_img.get_pixel(x, y)
				if c.a > 0.01:
					white_img.set_pixel(x, y, Color(1.0, 1.0, 1.0, c.a))
	return ImageTexture.create_from_image(white_img)


func _should_convert_to_white(img: Image) -> bool:
	var sum_luma: float = 0.0
	var samples: int = 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.01:
				continue
			sum_luma += (c.r + c.g + c.b) / 3.0
			samples += 1
	if samples == 0:
		return false
	return (sum_luma / float(samples)) < 0.65
