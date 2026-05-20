extends MarginContainer
class_name EnvironmentPanel

signal environment_setting_changed(setting: String, value: Variant)

const SECTION_SPACING: int = 10

var _time_label: Label = null
var _time_slider: HSlider = null
var _day_length_spin: SpinBox = null
var _pause_time_check: CheckBox = null
var _time_scale_slider: HSlider = null
var _time_scale_value: Label = null

var _override_check: CheckBox = null
var _override_color: ColorPickerButton = null
var _override_energy_slider: HSlider = null
var _override_energy_value: Label = null
var _override_saturation_slider: HSlider = null
var _override_saturation_value: Label = null
var _override_tint_strength_slider: HSlider = null
var _override_tint_strength_value: Label = null
var _override_controls: VBoxContainer = null

var _weather_global_slider: HSlider = null
var _weather_global_value: Label = null
var _weather_stack_check: CheckBox = null
var _weather_rows: Dictionary = {}

var _lightning_enable_check: CheckBox = null
var _lightning_interval_slider: HSlider = null
var _lightning_interval_value: Label = null
var _lightning_intensity_slider: HSlider = null
var _lightning_intensity_value: Label = null
var _lightning_random_check: CheckBox = null
var _full_rebuild_check: CheckBox = null
var _debug_visualize_dirty_rect_check: CheckBox = null

var _updating_ui: bool = false
var _active_weathers: Array[String] = ["normal"]


func _ready() -> void:
	add_theme_constant_override("margin_left", 16)
	add_theme_constant_override("margin_right", 16)
	add_theme_constant_override("margin_top", 14)
	add_theme_constant_override("margin_bottom", 14)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", SECTION_SPACING)
	add_child(root)

	root.add_child(_make_section_title("Time Controls"))
	_time_label = _make_label("Current Time: 12:00")
	root.add_child(_time_label)
	_time_slider = _make_slider(0.0, 23.983333, 12.0, 1.0 / 60.0)
	_time_slider.value_changed.connect(_on_time_changed)
	root.add_child(_time_slider)

	var day_row := HBoxContainer.new()
	day_row.add_child(_make_label("Day Length (min)"))
	_day_length_spin = SpinBox.new()
	_day_length_spin.min_value = 1.0
	_day_length_spin.max_value = 1440.0
	_day_length_spin.step = 0.1
	_day_length_spin.value = 15.0
	_day_length_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_length_spin.value_changed.connect(func(v: float) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("day_length_minutes", v)
	)
	day_row.add_child(_day_length_spin)
	root.add_child(day_row)

	_pause_time_check = CheckBox.new()
	_pause_time_check.text = "Pause Time"
	_pause_time_check.toggled.connect(func(v: bool) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("time_paused", v)
	)
	root.add_child(_pause_time_check)

	var scale_row := HBoxContainer.new()
	scale_row.add_child(_make_label("Time Scale"))
	_time_scale_value = _make_value_label("1.00x")
	scale_row.add_child(_time_scale_value)
	root.add_child(scale_row)
	_time_scale_slider = _make_slider(0.5, 10.0, 1.0, 0.05)
	_time_scale_slider.value_changed.connect(func(v: float) -> void:
		_time_scale_value.text = "%.2fx" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("time_scale", v)
	)
	root.add_child(_time_scale_slider)

	root.add_child(HSeparator.new())
	root.add_child(_make_section_title("Lighting Override"))
	_override_check = CheckBox.new()
	_override_check.text = "Override Time-of-Day Lighting"
	_override_check.toggled.connect(func(v: bool) -> void:
		_override_controls.visible = v
		if _updating_ui:
			return
		environment_setting_changed.emit("lighting_override_enabled", v)
	)
	root.add_child(_override_check)

	_override_controls = VBoxContainer.new()
	_override_controls.add_theme_constant_override("separation", 8)
	_override_controls.visible = false
	root.add_child(_override_controls)

	var color_row := HBoxContainer.new()
	color_row.add_child(_make_label("Light Color"))
	_override_color = ColorPickerButton.new()
	_override_color.color = Color(1.0, 0.95, 0.86, 1.0)
	_override_color.custom_minimum_size = Vector2(96, 28)
	_override_color.color_changed.connect(func(c: Color) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("lighting_override_color", c)
	)
	color_row.add_child(_override_color)
	_override_controls.add_child(color_row)

	var energy_row := HBoxContainer.new()
	energy_row.add_child(_make_label("Brightness / Energy"))
	_override_energy_value = _make_value_label("2.20")
	energy_row.add_child(_override_energy_value)
	_override_controls.add_child(energy_row)
	_override_energy_slider = _make_slider(0.0, 5.0, 2.2, 0.05)
	_override_energy_slider.value_changed.connect(func(v: float) -> void:
		_override_energy_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("lighting_override_energy", v)
	)
	_override_controls.add_child(_override_energy_slider)

	var sat_row := HBoxContainer.new()
	sat_row.add_child(_make_label("Saturation"))
	_override_saturation_value = _make_value_label("1.00")
	sat_row.add_child(_override_saturation_value)
	_override_controls.add_child(sat_row)
	_override_saturation_slider = _make_slider(-1.0, 2.0, 1.0, 0.05)
	_override_saturation_slider.value_changed.connect(func(v: float) -> void:
		_override_saturation_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("lighting_override_saturation", v)
	)
	_override_controls.add_child(_override_saturation_slider)

	var tint_row := HBoxContainer.new()
	tint_row.add_child(_make_label("Tint Strength"))
	_override_tint_strength_value = _make_value_label("0.65")
	tint_row.add_child(_override_tint_strength_value)
	_override_controls.add_child(tint_row)
	_override_tint_strength_slider = _make_slider(0.0, 1.0, 0.65, 0.01)
	_override_tint_strength_slider.value_changed.connect(func(v: float) -> void:
		_override_tint_strength_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("lighting_override_tint_strength", v)
	)
	_override_controls.add_child(_override_tint_strength_slider)

	root.add_child(HSeparator.new())
	root.add_child(_make_section_title("Weather Controls"))
	var global_row := HBoxContainer.new()
	global_row.add_child(_make_label("Weather Intensity"))
	_weather_global_value = _make_value_label("1.00")
	global_row.add_child(_weather_global_value)
	root.add_child(global_row)
	_weather_global_slider = _make_slider(0.0, 3.0, 1.0, 0.01)
	_weather_global_slider.value_changed.connect(func(v: float) -> void:
		_weather_global_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("weather_intensity_global", v)
	)
	root.add_child(_weather_global_slider)

	_weather_stack_check = CheckBox.new()
	_weather_stack_check.text = "Allow Weather Stacking"
	_weather_stack_check.toggled.connect(func(v: bool) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("weather_stacking_enabled", v)
		_update_weather_slider_visibility(v)
	)
	root.add_child(_weather_stack_check)

	_weather_rows = {
		"rain": _make_weather_row("Rain", "rain", 1.0),
		"snow": _make_weather_row("Snow", "snow", 1.0),
		"foggy": _make_weather_row("Fog", "foggy", 1.0),
		"stormy": _make_weather_row("Storm", "stormy", 1.0),
	}
	for key in ["rain", "snow", "foggy", "stormy"]:
		root.add_child(_weather_rows[key]["container"])

	root.add_child(HSeparator.new())
	root.add_child(_make_section_title("Lightning System"))
	_lightning_enable_check = CheckBox.new()
	_lightning_enable_check.text = "Enable Lightning"
	_lightning_enable_check.toggled.connect(func(v: bool) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("lightning_enabled", v)
	)
	root.add_child(_lightning_enable_check)

	var interval_row := HBoxContainer.new()
	interval_row.add_child(_make_label("Average Interval (sec)"))
	_lightning_interval_value = _make_value_label("18.0")
	interval_row.add_child(_lightning_interval_value)
	root.add_child(interval_row)
	_lightning_interval_slider = _make_slider(8.0, 60.0, 18.0, 0.5)
	_lightning_interval_slider.value_changed.connect(func(v: float) -> void:
		_lightning_interval_value.text = "%.1f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("lightning_interval", v)
	)
	root.add_child(_lightning_interval_slider)

	var intensity_row := HBoxContainer.new()
	intensity_row.add_child(_make_label("Intensity"))
	_lightning_intensity_value = _make_value_label("2.20")
	intensity_row.add_child(_lightning_intensity_value)
	root.add_child(intensity_row)
	_lightning_intensity_slider = _make_slider(0.0, 5.0, 2.2, 0.05)
	_lightning_intensity_slider.value_changed.connect(func(v: float) -> void:
		_lightning_intensity_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("lightning_intensity", v)
	)
	root.add_child(_lightning_intensity_slider)

	_lightning_random_check = CheckBox.new()
	_lightning_random_check.text = "Random Variation"
	_lightning_random_check.button_pressed = true
	_lightning_random_check.toggled.connect(func(v: bool) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("lightning_random_variation", v)
	)
	root.add_child(_lightning_random_check)

	root.add_child(HSeparator.new())
	root.add_child(_make_section_title("Debug"))
	_full_rebuild_check = CheckBox.new()
	_full_rebuild_check.text = "Force Full Rebuild"
	_full_rebuild_check.button_pressed = true
	_full_rebuild_check.tooltip_text = "Force the terrain to rebuild the full mesh after every stroke."
	_full_rebuild_check.toggled.connect(func(v: bool) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("full_rebuild_mode", v)
	)
	root.add_child(_full_rebuild_check)

	_debug_visualize_dirty_rect_check = CheckBox.new()
	_debug_visualize_dirty_rect_check.text = "Visualize Dirty Rect (Red)"
	_debug_visualize_dirty_rect_check.button_pressed = false
	_debug_visualize_dirty_rect_check.tooltip_text = "Highlight the dirty rect region with bright red for debugging seam issues."
	_debug_visualize_dirty_rect_check.toggled.connect(func(v: bool) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("debug_visualize_dirty_rect", v)
	)
	root.add_child(_debug_visualize_dirty_rect_check)

	_update_weather_slider_visibility(false)


func set_environment_state(state: Dictionary) -> void:
	_updating_ui = true
	var time_h: float = float(state.get("time_hours", 12.0))
	_time_slider.value = clampf(time_h, 0.0, 23.983333)
	_update_time_label(_time_slider.value)
	_day_length_spin.value = float(state.get("day_length_minutes", 15.0))
	_pause_time_check.button_pressed = bool(state.get("time_paused", false))
	_time_scale_slider.value = float(state.get("time_scale", 1.0))
	_time_scale_value.text = "%.2fx" % _time_scale_slider.value

	_override_check.button_pressed = bool(state.get("lighting_override_enabled", false))
	_override_controls.visible = _override_check.button_pressed
	_override_color.color = state.get("lighting_override_color", Color(1.0, 0.95, 0.86, 1.0))
	_override_energy_slider.value = float(state.get("lighting_override_energy", 2.2))
	_override_energy_value.text = "%.2f" % _override_energy_slider.value
	_override_saturation_slider.value = float(state.get("lighting_override_saturation", 1.0))
	_override_saturation_value.text = "%.2f" % _override_saturation_slider.value
	_override_tint_strength_slider.value = float(state.get("lighting_override_tint_strength", 0.65))
	_override_tint_strength_value.text = "%.2f" % _override_tint_strength_slider.value

	_weather_global_slider.value = float(state.get("weather_intensity_global", 1.0))
	_weather_global_value.text = "%.2f" % _weather_global_slider.value
	_weather_stack_check.button_pressed = bool(state.get("weather_stacking_enabled", false))

	var channels: Dictionary = state.get("weather_channels", {})
	for key in _weather_rows.keys():
		var slider: HSlider = _weather_rows[key]["slider"]
		var value_label: Label = _weather_rows[key]["value"]
		var val: float = float(channels.get(key, 1.0 if key == String(state.get("weather", "normal")) else 0.0))
		slider.value = val
		value_label.text = "%.2f" % val

	_lightning_enable_check.button_pressed = bool(state.get("lightning_enabled", false))
	_lightning_interval_slider.value = float(state.get("lightning_interval", 18.0))
	_lightning_interval_value.text = "%.1f" % _lightning_interval_slider.value
	_lightning_intensity_slider.value = float(state.get("lightning_intensity", 2.2))
	_lightning_intensity_value.text = "%.2f" % _lightning_intensity_slider.value
	_lightning_random_check.button_pressed = bool(state.get("lightning_random_variation", true))
	if _full_rebuild_check != null:
		_full_rebuild_check.button_pressed = bool(state.get("full_rebuild_mode", true))
	if _debug_visualize_dirty_rect_check != null:
		_debug_visualize_dirty_rect_check.button_pressed = bool(state.get("debug_visualize_dirty_rect", false))
	_updating_ui = false

	_update_weather_slider_visibility(_weather_stack_check.button_pressed)


func set_active_weather(active_weathers: Array[String]) -> void:
	_active_weathers = active_weathers.duplicate()
	_update_weather_slider_visibility(_weather_stack_check.button_pressed)


func _update_time_label(time_hours: float) -> void:
	var wrapped: float = fposmod(time_hours, 24.0)
	var hour: int = int(floor(wrapped))
	var minute: int = int(round((wrapped - float(hour)) * 60.0))
	if minute >= 60:
		minute = 0
		hour = (hour + 1) % 24
	_time_label.text = "Current Time: %02d:%02d" % [hour, minute]


func _on_time_changed(value: float) -> void:
	_update_time_label(value)
	if _updating_ui:
		return
	environment_setting_changed.emit("time_hours", value)


func _update_weather_slider_visibility(show_all: bool) -> void:
	var active: Dictionary = {}
	for w in _active_weathers:
		active[String(w)] = true
	for key in _weather_rows.keys():
		var row: HBoxContainer = _weather_rows[key]["container"]
		row.visible = show_all or active.has(key)


func _make_weather_row(label_text: String, weather_id: String, default_value: float) -> Dictionary:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	var label := _make_label(label_text)
	label.custom_minimum_size.x = 120
	container.add_child(label)
	var slider := _make_slider(0.0, 3.0, default_value, 0.01)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(slider)
	var value_label := _make_value_label("%.2f" % default_value)
	container.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("weather_channel_" + weather_id, v)
	)
	return {
		"container": container,
		"slider": slider,
		"value": value_label,
	}


func _make_section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98, 1.0))
	return label


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.70, 0.80, 0.88, 1.0))
	return label


func _make_value_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 64
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.87, 0.93, 0.98, 1.0))
	return label


func _make_slider(min_val: float, max_val: float, default_val: float, step: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = default_val
	slider.custom_minimum_size.y = 22
	return slider
