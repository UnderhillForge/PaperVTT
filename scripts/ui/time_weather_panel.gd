extends Control
class_name TimeWeatherPanel

signal time_changed(time_hours: float)
signal weather_changed(weather_id: String)
signal day_length_changed(minutes_per_day: float)

const WeatherRadialMenuScript: Script = preload("res://scripts/ui/weather_radial_menu.gd")
const TRIGGER_ICON_PATH: String = "res://assets/icons/000000/transparent/1x1/lorc/hourglass.svg"

const WEATHER_CLEAR: String = "normal"
const WEATHER_LABELS: Dictionary = {
	"normal": "Normal",
	"rain": "Rain",
	"snow": "Snow",
	"foggy": "Foggy",
	"stormy": "Stormy",
}

@onready var _time_slider: HSlider = %TimeSlider
@onready var _time_value: Label = %TimeValue
@onready var _day_length_slider: HSlider = %DayLengthSlider
@onready var _day_length_value: Label = %DayLengthValue
@onready var _trigger_button: Button = %TriggerButton
@onready var _time_popup: PanelContainer = %TimePopup
@onready var _time_popup_title: Label = %TimePopupTitle

var _suppress_signals: bool = false
var _weather_id: String = WEATHER_CLEAR
var _weather_radial: Control = null
var _time_hours: float = 8.0
var _minutes_per_day: float = 15.0
var _preview_forced_radial: bool = false
var _preview_forced_time_panel: bool = false
var _trigger_icon: Texture2D = null

@export var preview_open_radial_menu: bool = false
@export var preview_open_time_panel: bool = false
@export var preview_weather_mode: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_apply_style()
	_setup_trigger_icon()
	_trigger_button.pressed.connect(_on_trigger_pressed)
	_time_slider.value_changed.connect(_on_time_slider_changed)
	_day_length_slider.value_changed.connect(_on_day_length_slider_changed)
	_ensure_weather_radial()
	set_time_hours(8.0)
	set_day_length_minutes(15.0)
	set_weather(WEATHER_CLEAR)
	_close_time_popup()
	set_process(true)


func set_time_hours(time_hours: float) -> void:
	var clamped_time: float = clampf(time_hours, 0.0, 23.983333)
	_time_hours = clamped_time
	_suppress_signals = true
	_time_slider.value = clamped_time
	_update_time_label(clamped_time)
	_update_trigger_text()
	_suppress_signals = false


func set_day_length_minutes(minutes_per_day: float) -> void:
	_minutes_per_day = clampf(minutes_per_day, 1.0, 1440.0)
	_suppress_signals = true
	_day_length_slider.value = _minutes_per_day
	_day_length_value.text = "%.1f min" % _minutes_per_day
	_suppress_signals = false


func set_weather(weather_id: String) -> void:
	_weather_id = String(weather_id if WEATHER_LABELS.has(weather_id) else WEATHER_CLEAR)
	_update_trigger_text()


func _on_time_slider_changed(value: float) -> void:
	_time_hours = value
	_update_time_label(value)
	_update_trigger_text()
	if _suppress_signals:
		return
	emit_signal("time_changed", value)


func _on_day_length_slider_changed(value: float) -> void:
	_minutes_per_day = value
	_day_length_value.text = "%.1f min" % _minutes_per_day
	if _suppress_signals:
		return
	emit_signal("day_length_changed", _minutes_per_day)


func _on_trigger_pressed() -> void:
	if _weather_radial == null:
		return
	_close_time_popup()
	if _weather_radial.has_method("is_open") and bool(_weather_radial.call("is_open")):
		_weather_radial.call("close_menu")
		return
	var btn_rect: Rect2 = _trigger_button.get_global_rect()
	var corner: Vector2 = Vector2(btn_rect.position.x - 2.0, btn_rect.position.y + btn_rect.size.y + 2.0)
	_weather_radial.call("open_at", corner, _weather_id)


func _on_weather_selected(weather_id: String) -> void:
	set_weather(weather_id)
	emit_signal("weather_changed", _weather_id)


func _on_time_menu_requested() -> void:
	if _weather_radial != null and _weather_radial.has_method("close_menu"):
		_weather_radial.call("close_menu")
	_open_time_popup()


func _update_time_label(time_hours: float) -> void:
	var wrapped: float = fposmod(time_hours, 24.0)
	var hour: int = int(floor(wrapped))
	var minute: int = int(round((wrapped - float(hour)) * 60.0))
	if minute >= 60:
		minute = 0
		hour = (hour + 1) % 24
	_time_value.text = "%02d:%02d" % [hour, minute]
	_time_popup_title.text = "Time %s" % _time_value.text


func _open_time_popup() -> void:
	var trigger_rect: Rect2 = _trigger_button.get_global_rect()
	var desired_pos: Vector2 = trigger_rect.position + Vector2(trigger_rect.size.x + 12.0, -(_time_popup.size.y + 8.0))
	_time_popup.global_position = desired_pos
	_time_popup.visible = true


func _close_time_popup() -> void:
	_time_popup.visible = false


func _update_trigger_text() -> void:
	_trigger_button.tooltip_text = "Time %s | %s" % [_time_value.text, String(WEATHER_LABELS.get(_weather_id, "Normal"))]


func _ensure_weather_radial() -> void:
	if _weather_radial != null:
		return
	_weather_radial = WeatherRadialMenuScript.new()
	add_child(_weather_radial)
	_weather_radial.top_level = true
	_weather_radial.z_index = 1000
	if _weather_radial.has_signal("weather_selected"):
		_weather_radial.connect("weather_selected", Callable(self, "_on_weather_selected"))
	if _weather_radial.has_signal("time_menu_requested"):
		_weather_radial.connect("time_menu_requested", Callable(self, "_on_time_menu_requested"))


func _apply_style() -> void:
	var trigger_style := StyleBoxFlat.new()
	trigger_style.bg_color = Color(0.02, 0.06, 0.10, 0.96)
	trigger_style.corner_radius_top_left = 18
	trigger_style.corner_radius_top_right = 18
	trigger_style.corner_radius_bottom_left = 18
	trigger_style.corner_radius_bottom_right = 18
	trigger_style.border_width_left = 1
	trigger_style.border_width_top = 1
	trigger_style.border_width_right = 1
	trigger_style.border_width_bottom = 1
	trigger_style.border_color = Color(0.26, 0.41, 0.52, 0.62)
	_trigger_button.add_theme_stylebox_override("normal", trigger_style)
	var trigger_hover: StyleBoxFlat = trigger_style.duplicate()
	trigger_hover.bg_color = Color(0.05, 0.11, 0.18, 0.98)
	var trigger_pressed: StyleBoxFlat = trigger_hover.duplicate()
	trigger_pressed.bg_color = Color(0.07, 0.15, 0.24, 1.0)
	_trigger_button.add_theme_stylebox_override("hover", trigger_hover)
	_trigger_button.add_theme_stylebox_override("pressed", trigger_pressed)
	_trigger_button.text = ""
	_trigger_button.flat = false
	_trigger_button.focus_mode = Control.FOCUS_NONE
	_trigger_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.07, 0.10, 0.86)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.20, 0.28, 0.36, 0.50)
	_time_popup.add_theme_stylebox_override("panel", panel_style)

	_time_slider.min_value = 0.0
	_time_slider.max_value = 23.983333
	_time_slider.step = (1.0 / 60.0)
	_time_slider.custom_minimum_size = Vector2(188.0, 0.0)
	_day_length_slider.min_value = 1.0
	_day_length_slider.max_value = 1440.0
	_day_length_slider.step = 0.1
	_day_length_slider.custom_minimum_size = Vector2(188.0, 0.0)


func _setup_trigger_icon() -> void:
	if not ResourceLoader.exists(TRIGGER_ICON_PATH):
		return
	_trigger_icon = _load_icon_as_white(TRIGGER_ICON_PATH)
	if _trigger_icon != null:
		_trigger_button.icon = _trigger_icon
		_trigger_button.expand_icon = true


func _load_icon_as_white(path: String) -> Texture2D:
	var src: Texture2D = load(path) as Texture2D
	if src == null:
		return null
	var img: Image = src.get_image()
	if img == null or img.is_empty():
		return src
	img.convert(Image.FORMAT_RGBA8)
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.01:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, c.a))
	return ImageTexture.create_from_image(img)


func _unhandled_input(event: InputEvent) -> void:
	if not _time_popup.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not _time_popup.get_global_rect().has_point(mb.global_position) and not _trigger_button.get_global_rect().has_point(mb.global_position):
			_close_time_popup()


func _process(_delta: float) -> void:
	if _weather_radial == null:
		return
	if preview_weather_mode != "" and WEATHER_LABELS.has(preview_weather_mode) and preview_weather_mode != _weather_id:
		set_weather(preview_weather_mode)
		emit_signal("weather_changed", _weather_id)

	if preview_open_radial_menu:
		var _pr: Rect2 = _trigger_button.get_global_rect()
		var _pc: Vector2 = Vector2(_pr.position.x - 2.0, _pr.position.y + _pr.size.y + 2.0)
		if _weather_radial.has_method("open_at"):
			_weather_radial.call("open_at", _pc, _weather_id)
		_preview_forced_radial = true
	elif _preview_forced_radial:
		_preview_forced_radial = false
		if _weather_radial.has_method("is_open") and bool(_weather_radial.call("is_open")):
			_weather_radial.call("close_menu")

	if preview_open_time_panel:
		_open_time_popup()
		_preview_forced_time_panel = true
	elif _preview_forced_time_panel:
		_preview_forced_time_panel = false
		_close_time_popup()
