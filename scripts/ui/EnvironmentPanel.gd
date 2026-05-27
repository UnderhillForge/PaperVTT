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

var _postfx_preview: TextureRect = null
var _postfx_outline_slider: HSlider = null
var _postfx_outline_value: Label = null
var _postfx_contrast_slider: HSlider = null
var _postfx_contrast_value: Label = null
var _postfx_saturation_slider: HSlider = null
var _postfx_saturation_value: Label = null
var _postfx_vignette_slider: HSlider = null
var _postfx_vignette_value: Label = null
var _postfx_bloom_slider: HSlider = null
var _postfx_bloom_value: Label = null
var _postfx_tint_slider: HSlider = null
var _postfx_tint_value: Label = null
var _postfx_tint_picker: ColorPickerButton = null
var _postfx_outlines_layer_enable: CheckBox = null
var _postfx_outlines_layer_thickness_slider: HSlider = null
var _postfx_outlines_layer_depth_threshold_slider: HSlider = null
var _postfx_outlines_layer_depth_sensitivity_slider: HSlider = null
var _postfx_outlines_layer_normal_sensitivity_slider: HSlider = null
var _postfx_outlines_layer_opacity_slider: HSlider = null
var _postfx_outlines_layer_color_picker: ColorPickerButton = null
var _postfx_preset_option: OptionButton = null
var _ppf_name_edit: LineEdit = null
var _ppf_author_edit: LineEdit = null
var _ppf_description_edit: LineEdit = null
var _ppf_path_edit: LineEdit = null
var _ppf_remote_url_edit: LineEdit = null
var _postfx_shader_code: TextEdit = null

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
	root.add_child(_make_section_title("Live Post-Process Editor"))

	var preview_label := _make_label("Live Preview")
	root.add_child(preview_label)
	_postfx_preview = TextureRect.new()
	_postfx_preview.custom_minimum_size = Vector2(220, 140)
	_postfx_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_postfx_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_postfx_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.add_child(_postfx_preview)

	var preset_row := HBoxContainer.new()
	preset_row.add_child(_make_label("Preset"))
	_postfx_preset_option = OptionButton.new()
	_postfx_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for name in ["Graphic Novel", "Graphic Novel Outlines", "Pen & Ink Outlines", "Watercolor", "Cinematic", "Horror", "Dreamy"]:
		_postfx_preset_option.add_item(name)
	preset_row.add_child(_postfx_preset_option)
	var apply_preset_btn := Button.new()
	apply_preset_btn.text = "Apply"
	apply_preset_btn.pressed.connect(func() -> void:
		var selected: String = _postfx_preset_option.get_item_text(_postfx_preset_option.selected)
		environment_setting_changed.emit("postfx_apply_preset", selected)
	)
	preset_row.add_child(apply_preset_btn)
	var quick_preset_btn := Button.new()
	quick_preset_btn.text = "Apply Graphic Novel Preset"
	quick_preset_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_apply_preset", "Graphic Novel Outlines")
	)
	preset_row.add_child(quick_preset_btn)
	root.add_child(preset_row)

	var outline_row := HBoxContainer.new()
	outline_row.add_child(_make_label("Outline Strength"))
	_postfx_outline_value = _make_value_label("2.35")
	outline_row.add_child(_postfx_outline_value)
	root.add_child(outline_row)
	_postfx_outline_slider = _make_slider(0.0, 6.0, 2.35, 0.01)
	_postfx_outline_slider.value_changed.connect(func(v: float) -> void:
		_postfx_outline_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outline_strength", "value": v})
	)
	root.add_child(_postfx_outline_slider)

	var contrast_row := HBoxContainer.new()
	contrast_row.add_child(_make_label("Contrast"))
	_postfx_contrast_value = _make_value_label("1.00")
	contrast_row.add_child(_postfx_contrast_value)
	root.add_child(contrast_row)
	_postfx_contrast_slider = _make_slider(0.5, 2.0, 1.0, 0.01)
	_postfx_contrast_slider.value_changed.connect(func(v: float) -> void:
		_postfx_contrast_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "contrast", "value": v})
	)
	root.add_child(_postfx_contrast_slider)

	var saturation_row := HBoxContainer.new()
	saturation_row.add_child(_make_label("Saturation"))
	_postfx_saturation_value = _make_value_label("1.00")
	saturation_row.add_child(_postfx_saturation_value)
	root.add_child(saturation_row)
	_postfx_saturation_slider = _make_slider(0.0, 2.0, 1.0, 0.01)
	_postfx_saturation_slider.value_changed.connect(func(v: float) -> void:
		_postfx_saturation_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "saturation", "value": v})
	)
	root.add_child(_postfx_saturation_slider)

	var vignette_row := HBoxContainer.new()
	vignette_row.add_child(_make_label("Vignette"))
	_postfx_vignette_value = _make_value_label("0.25")
	vignette_row.add_child(_postfx_vignette_value)
	root.add_child(vignette_row)
	_postfx_vignette_slider = _make_slider(0.0, 1.0, 0.25, 0.01)
	_postfx_vignette_slider.value_changed.connect(func(v: float) -> void:
		_postfx_vignette_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "vignette_strength", "value": v})
	)
	root.add_child(_postfx_vignette_slider)

	var bloom_row := HBoxContainer.new()
	bloom_row.add_child(_make_label("Bloom"))
	_postfx_bloom_value = _make_value_label("0.12")
	bloom_row.add_child(_postfx_bloom_value)
	root.add_child(bloom_row)
	_postfx_bloom_slider = _make_slider(0.0, 1.0, 0.12, 0.01)
	_postfx_bloom_slider.value_changed.connect(func(v: float) -> void:
		_postfx_bloom_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "bloom_strength", "value": v})
	)
	root.add_child(_postfx_bloom_slider)

	var postfx_tint_row := HBoxContainer.new()
	postfx_tint_row.add_child(_make_label("Tint Strength"))
	_postfx_tint_value = _make_value_label("0.00")
	postfx_tint_row.add_child(_postfx_tint_value)
	root.add_child(postfx_tint_row)
	_postfx_tint_slider = _make_slider(0.0, 1.0, 0.0, 0.01)
	_postfx_tint_slider.value_changed.connect(func(v: float) -> void:
		_postfx_tint_value.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "tint_strength", "value": v})
	)
	root.add_child(_postfx_tint_slider)

	var tint_picker_row := HBoxContainer.new()
	tint_picker_row.add_child(_make_label("Color Tint"))
	_postfx_tint_picker = ColorPickerButton.new()
	_postfx_tint_picker.color = Color(1.0, 1.0, 1.0, 1.0)
	_postfx_tint_picker.custom_minimum_size = Vector2(96, 28)
	_postfx_tint_picker.color_changed.connect(func(c: Color) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "color_tint", "value": c})
	)
	tint_picker_row.add_child(_postfx_tint_picker)
	root.add_child(tint_picker_row)

	root.add_child(HSeparator.new())
	root.add_child(_make_label("Post-Process Outlines Layer"))

	_postfx_outlines_layer_enable = CheckBox.new()
	_postfx_outlines_layer_enable.text = "Enable Outlines Layer"
	_postfx_outlines_layer_enable.toggled.connect(func(v: bool) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_enabled", "value": v})
	)
	root.add_child(_postfx_outlines_layer_enable)

	var out_thickness_row := HBoxContainer.new()
	out_thickness_row.add_child(_make_label("Outline Thickness"))
	root.add_child(out_thickness_row)
	_postfx_outlines_layer_thickness_slider = _make_slider(0.5, 8.0, 2.2, 0.1)
	_postfx_outlines_layer_thickness_slider.value_changed.connect(func(v: float) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_thickness", "value": v})
	)
	root.add_child(_postfx_outlines_layer_thickness_slider)

	var out_depth_threshold_row := HBoxContainer.new()
	out_depth_threshold_row.add_child(_make_label("Depth Threshold"))
	root.add_child(out_depth_threshold_row)
	_postfx_outlines_layer_depth_threshold_slider = _make_slider(0.001, 0.35, 0.055, 0.001)
	_postfx_outlines_layer_depth_threshold_slider.value_changed.connect(func(v: float) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_depth_threshold", "value": v})
	)
	root.add_child(_postfx_outlines_layer_depth_threshold_slider)

	var out_depth_sensitivity_row := HBoxContainer.new()
	out_depth_sensitivity_row.add_child(_make_label("Depth Sensitivity"))
	root.add_child(out_depth_sensitivity_row)
	_postfx_outlines_layer_depth_sensitivity_slider = _make_slider(0.0, 8.0, 1.6, 0.01)
	_postfx_outlines_layer_depth_sensitivity_slider.value_changed.connect(func(v: float) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_depth_sensitivity", "value": v})
	)
	root.add_child(_postfx_outlines_layer_depth_sensitivity_slider)

	var out_normal_sensitivity_row := HBoxContainer.new()
	out_normal_sensitivity_row.add_child(_make_label("Normal Sensitivity"))
	root.add_child(out_normal_sensitivity_row)
	_postfx_outlines_layer_normal_sensitivity_slider = _make_slider(0.0, 8.0, 1.3, 0.01)
	_postfx_outlines_layer_normal_sensitivity_slider.value_changed.connect(func(v: float) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_normal_sensitivity", "value": v})
	)
	root.add_child(_postfx_outlines_layer_normal_sensitivity_slider)

	var out_opacity_row := HBoxContainer.new()
	out_opacity_row.add_child(_make_label("Outline Opacity"))
	root.add_child(out_opacity_row)
	_postfx_outlines_layer_opacity_slider = _make_slider(0.0, 1.0, 0.48, 0.01)
	_postfx_outlines_layer_opacity_slider.value_changed.connect(func(v: float) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_opacity", "value": v})
	)
	root.add_child(_postfx_outlines_layer_opacity_slider)

	var out_color_row := HBoxContainer.new()
	out_color_row.add_child(_make_label("Outline Color"))
	_postfx_outlines_layer_color_picker = ColorPickerButton.new()
	_postfx_outlines_layer_color_picker.color = Color(0.01, 0.01, 0.01, 1.0)
	_postfx_outlines_layer_color_picker.custom_minimum_size = Vector2(96, 28)
	_postfx_outlines_layer_color_picker.color_changed.connect(func(c: Color) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_color", "value": c})
	)
	out_color_row.add_child(_postfx_outlines_layer_color_picker)
	root.add_child(out_color_row)

	root.add_child(_make_label("Custom Shader Code"))
	_postfx_shader_code = TextEdit.new()
	_postfx_shader_code.custom_minimum_size = Vector2(0, 120)
	_postfx_shader_code.placeholder_text = "Paste custom canvas_item shader code here..."
	root.add_child(_postfx_shader_code)
	var shader_buttons := HBoxContainer.new()
	var apply_shader_btn := Button.new()
	apply_shader_btn.text = "Apply Shader"
	apply_shader_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_apply_custom_shader", _postfx_shader_code.text)
	)
	shader_buttons.add_child(apply_shader_btn)
	var reset_shader_btn := Button.new()
	reset_shader_btn.text = "Reset Shader"
	reset_shader_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_apply_custom_shader", "")
	)
	shader_buttons.add_child(reset_shader_btn)
	root.add_child(shader_buttons)

	root.add_child(_make_label(".ppf Metadata"))
	_ppf_name_edit = LineEdit.new()
	_ppf_name_edit.placeholder_text = "Preset Name"
	_ppf_name_edit.text = "New PostFX Preset"
	root.add_child(_ppf_name_edit)
	_ppf_author_edit = LineEdit.new()
	_ppf_author_edit.placeholder_text = "Author"
	root.add_child(_ppf_author_edit)
	_ppf_description_edit = LineEdit.new()
	_ppf_description_edit.placeholder_text = "Description"
	root.add_child(_ppf_description_edit)
	_ppf_path_edit = LineEdit.new()
	_ppf_path_edit.placeholder_text = "user://postfx/my_style.ppf"
	_ppf_path_edit.text = "user://postfx/new_style.ppf"
	root.add_child(_ppf_path_edit)

	var file_buttons := HBoxContainer.new()
	var save_btn := Button.new()
	save_btn.text = "Save .ppf"
	save_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_save_local", {
			"path": _ppf_path_edit.text.strip_edges(),
			"name": _ppf_name_edit.text.strip_edges(),
			"author": _ppf_author_edit.text.strip_edges(),
			"description": _ppf_description_edit.text.strip_edges(),
			"custom_shader_code": _postfx_shader_code.text,
		})
	)
	file_buttons.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Load .ppf"
	load_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_load_local", _ppf_path_edit.text.strip_edges())
	)
	file_buttons.add_child(load_btn)
	var export_btn := Button.new()
	export_btn.text = "Export .ppf"
	export_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_export_local", {
			"path": _ppf_path_edit.text.strip_edges(),
			"name": _ppf_name_edit.text.strip_edges(),
			"author": _ppf_author_edit.text.strip_edges(),
			"description": _ppf_description_edit.text.strip_edges(),
			"custom_shader_code": _postfx_shader_code.text,
		})
	)
	file_buttons.add_child(export_btn)
	root.add_child(file_buttons)

	_ppf_remote_url_edit = LineEdit.new()
	_ppf_remote_url_edit.placeholder_text = "https://example.com/presets/graphic_novel.ppf"
	root.add_child(_ppf_remote_url_edit)
	var import_remote_btn := Button.new()
	import_remote_btn.text = "Import Remote .ppf"
	import_remote_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_import_url", _ppf_remote_url_edit.text.strip_edges())
	)
	root.add_child(import_remote_btn)

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

	if state.has("postfx") and state.get("postfx") is Dictionary:
		var postfx: Dictionary = state.get("postfx")
		var effects_by_name: Dictionary = {}
		var effects_variant: Variant = postfx.get("effects", [])
		if effects_variant is Array:
			for item in effects_variant:
				if item is Dictionary:
					var entry: Dictionary = item
					effects_by_name[String(entry.get("name", ""))] = entry.get("value")
		if _postfx_outline_slider != null and effects_by_name.has("outline_strength"):
			_postfx_outline_slider.value = float(effects_by_name["outline_strength"])
			_postfx_outline_value.text = "%.2f" % _postfx_outline_slider.value
		if _postfx_contrast_slider != null and effects_by_name.has("contrast"):
			_postfx_contrast_slider.value = float(effects_by_name["contrast"])
			_postfx_contrast_value.text = "%.2f" % _postfx_contrast_slider.value
		if _postfx_saturation_slider != null and effects_by_name.has("saturation"):
			_postfx_saturation_slider.value = float(effects_by_name["saturation"])
			_postfx_saturation_value.text = "%.2f" % _postfx_saturation_slider.value
		if _postfx_vignette_slider != null and effects_by_name.has("vignette_strength"):
			_postfx_vignette_slider.value = float(effects_by_name["vignette_strength"])
			_postfx_vignette_value.text = "%.2f" % _postfx_vignette_slider.value
		if _postfx_bloom_slider != null and effects_by_name.has("bloom_strength"):
			_postfx_bloom_slider.value = float(effects_by_name["bloom_strength"])
			_postfx_bloom_value.text = "%.2f" % _postfx_bloom_slider.value
		if _postfx_tint_slider != null and effects_by_name.has("tint_strength"):
			_postfx_tint_slider.value = float(effects_by_name["tint_strength"])
			_postfx_tint_value.text = "%.2f" % _postfx_tint_slider.value
		if _postfx_tint_picker != null and postfx.has("color_tint"):
			_postfx_tint_picker.color = postfx.get("color_tint", Color(1.0, 1.0, 1.0, 1.0))
		if _postfx_outlines_layer_enable != null and effects_by_name.has("outlines_layer_enabled"):
			_postfx_outlines_layer_enable.button_pressed = bool(effects_by_name["outlines_layer_enabled"])
		if _postfx_outlines_layer_thickness_slider != null and effects_by_name.has("outlines_layer_thickness"):
			_postfx_outlines_layer_thickness_slider.value = float(effects_by_name["outlines_layer_thickness"])
		if _postfx_outlines_layer_depth_threshold_slider != null and effects_by_name.has("outlines_layer_depth_threshold"):
			_postfx_outlines_layer_depth_threshold_slider.value = float(effects_by_name["outlines_layer_depth_threshold"])
		if _postfx_outlines_layer_depth_sensitivity_slider != null and effects_by_name.has("outlines_layer_depth_sensitivity"):
			_postfx_outlines_layer_depth_sensitivity_slider.value = float(effects_by_name["outlines_layer_depth_sensitivity"])
		if _postfx_outlines_layer_normal_sensitivity_slider != null and effects_by_name.has("outlines_layer_normal_sensitivity"):
			_postfx_outlines_layer_normal_sensitivity_slider.value = float(effects_by_name["outlines_layer_normal_sensitivity"])
		if _postfx_outlines_layer_opacity_slider != null and effects_by_name.has("outlines_layer_opacity"):
			_postfx_outlines_layer_opacity_slider.value = float(effects_by_name["outlines_layer_opacity"])
		if _postfx_outlines_layer_color_picker != null and effects_by_name.has("outlines_layer_color"):
			_postfx_outlines_layer_color_picker.color = effects_by_name["outlines_layer_color"]
	if _full_rebuild_check != null:
		_full_rebuild_check.button_pressed = bool(state.get("full_rebuild_mode", true))
	if _debug_visualize_dirty_rect_check != null:
		_debug_visualize_dirty_rect_check.button_pressed = bool(state.get("debug_visualize_dirty_rect", false))
	_updating_ui = false

	_update_weather_slider_visibility(_weather_stack_check.button_pressed)


func set_postfx_preview_texture(texture: Texture2D) -> void:
	if _postfx_preview != null:
		_postfx_preview.texture = texture


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


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if data is Dictionary:
		var dict_data: Dictionary = data
		if dict_data.has("files") and dict_data["files"] is PackedStringArray:
			for file_path in dict_data["files"]:
				if String(file_path).to_lower().ends_with(".ppf"):
					return true
	return false


func _drop_data(_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	var dict_data: Dictionary = data
	if not dict_data.has("files") or not (dict_data["files"] is PackedStringArray):
		return
	for file_path in dict_data["files"]:
		var path_str: String = String(file_path)
		if path_str.to_lower().ends_with(".ppf"):
			if _ppf_path_edit != null:
				_ppf_path_edit.text = path_str
			environment_setting_changed.emit("postfx_load_local", path_str)
			break
