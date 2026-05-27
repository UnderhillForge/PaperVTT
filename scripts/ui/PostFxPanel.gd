extends MarginContainer
class_name PostFxPanel

signal environment_setting_changed(setting: String, value: Variant)

var _updating_ui: bool = false
var _pending_state: Dictionary = {}
var _pending_preview_texture: Texture2D = null

var _preview: TextureRect = null
var _outline_slider: HSlider = null
var _outline_value: Label = null
var _contrast_slider: HSlider = null
var _contrast_value: Label = null
var _saturation_slider: HSlider = null
var _saturation_value: Label = null
var _vignette_slider: HSlider = null
var _vignette_value: Label = null
var _bloom_slider: HSlider = null
var _bloom_value: Label = null
var _tint_strength_slider: HSlider = null
var _tint_strength_value: Label = null
var _tint_picker: ColorPickerButton = null
var _outlines_layer_enable: CheckBox = null
var _outlines_layer_thickness_slider: HSlider = null
var _outlines_layer_depth_sensitivity_slider: HSlider = null
var _outlines_layer_depth_threshold_slider: HSlider = null
var _outlines_layer_normal_sensitivity_slider: HSlider = null
var _outlines_layer_opacity_slider: HSlider = null
var _outlines_layer_color_picker: ColorPickerButton = null

var _preset_option: OptionButton = null
var _shader_code: TextEdit = null
var _ppf_name: LineEdit = null
var _ppf_author: LineEdit = null
var _ppf_description: LineEdit = null
var _ppf_path: LineEdit = null
var _ppf_url: LineEdit = null

func _ready() -> void:
	add_theme_constant_override("margin_left", 16)
	add_theme_constant_override("margin_right", 16)
	add_theme_constant_override("margin_top", 14)
	add_theme_constant_override("margin_bottom", 14)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := Label.new()
	title.text = "Live Post-Process Editor"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 0.98, 1.0))
	root.add_child(title)

	var preview_label := Label.new()
	preview_label.text = "Live Preview"
	root.add_child(preview_label)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(220, 140)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.add_child(_preview)

	var preset_row := HBoxContainer.new()
	var preset_label := Label.new()
	preset_label.text = "Preset"
	preset_row.add_child(preset_label)
	_preset_option = OptionButton.new()
	_preset_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for name in ["Graphic Novel", "Graphic Novel Outlines", "Pen & Ink Outlines", "Watercolor", "Cinematic", "Horror", "Dreamy"]:
		_preset_option.add_item(name)
	preset_row.add_child(_preset_option)
	var apply_preset := Button.new()
	apply_preset.text = "Apply"
	apply_preset.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_apply_preset", _preset_option.get_item_text(_preset_option.selected))
	)
	preset_row.add_child(apply_preset)
	var quick_btn := Button.new()
	quick_btn.text = "Apply Graphic Novel Preset"
	quick_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_apply_preset", "Graphic Novel Outlines")
	)
	preset_row.add_child(quick_btn)
	root.add_child(preset_row)

	_outline_slider = _add_effect_slider(root, "Outline Strength", 0.0, 6.0, 2.35, 0.01, "outline_strength")
	_contrast_slider = _add_effect_slider(root, "Contrast", 0.5, 2.0, 1.0, 0.01, "contrast")
	_saturation_slider = _add_effect_slider(root, "Saturation", 0.0, 2.0, 1.0, 0.01, "saturation")
	_vignette_slider = _add_effect_slider(root, "Vignette", 0.0, 1.0, 0.25, 0.01, "vignette_strength")
	_bloom_slider = _add_effect_slider(root, "Bloom", 0.0, 1.0, 0.12, 0.01, "bloom_strength")
	_tint_strength_slider = _add_effect_slider(root, "Tint Strength", 0.0, 1.0, 0.0, 0.01, "tint_strength")

	root.add_child(HSeparator.new())
	var outlines_title := Label.new()
	outlines_title.text = "Post-Process Outlines Layer"
	root.add_child(outlines_title)

	_outlines_layer_enable = CheckBox.new()
	_outlines_layer_enable.text = "Enable Outlines Layer"
	_outlines_layer_enable.button_pressed = false
	_outlines_layer_enable.toggled.connect(func(v: bool) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_enabled", "value": v})
	)
	root.add_child(_outlines_layer_enable)

	_outlines_layer_thickness_slider = _add_effect_slider(root, "Outline Thickness", 0.5, 8.0, 2.2, 0.1, "outlines_layer_thickness")
	_outlines_layer_depth_threshold_slider = _add_effect_slider(root, "Depth Threshold", 0.001, 0.35, 0.055, 0.001, "outlines_layer_depth_threshold")
	_outlines_layer_depth_sensitivity_slider = _add_effect_slider(root, "Depth Sensitivity", 0.0, 8.0, 1.6, 0.01, "outlines_layer_depth_sensitivity")
	_outlines_layer_normal_sensitivity_slider = _add_effect_slider(root, "Normal Sensitivity", 0.0, 8.0, 1.3, 0.01, "outlines_layer_normal_sensitivity")
	_outlines_layer_opacity_slider = _add_effect_slider(root, "Outline Opacity", 0.0, 1.0, 0.48, 0.01, "outlines_layer_opacity")

	var outlines_color_row := HBoxContainer.new()
	var outlines_color_label := Label.new()
	outlines_color_label.text = "Outline Color"
	outlines_color_row.add_child(outlines_color_label)
	_outlines_layer_color_picker = ColorPickerButton.new()
	_outlines_layer_color_picker.color = Color(0.01, 0.01, 0.01, 1.0)
	_outlines_layer_color_picker.custom_minimum_size = Vector2(96, 28)
	_outlines_layer_color_picker.color_changed.connect(func(c: Color) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "outlines_layer_color", "value": c})
	)
	outlines_color_row.add_child(_outlines_layer_color_picker)
	root.add_child(outlines_color_row)

	var tint_row := HBoxContainer.new()
	var tint_label := Label.new()
	tint_label.text = "Color Tint"
	tint_row.add_child(tint_label)
	_tint_picker = ColorPickerButton.new()
	_tint_picker.color = Color(1.0, 1.0, 1.0, 1.0)
	_tint_picker.custom_minimum_size = Vector2(96, 28)
	_tint_picker.color_changed.connect(func(c: Color) -> void:
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": "color_tint", "value": c})
	)
	tint_row.add_child(_tint_picker)
	root.add_child(tint_row)

	root.add_child(HSeparator.new())
	var shader_label := Label.new()
	shader_label.text = "Custom Shader Code"
	root.add_child(shader_label)
	_shader_code = TextEdit.new()
	_shader_code.custom_minimum_size = Vector2(0, 120)
	_shader_code.placeholder_text = "Paste custom canvas_item shader code here..."
	root.add_child(_shader_code)

	var shader_buttons := HBoxContainer.new()
	var apply_shader := Button.new()
	apply_shader.text = "Apply Shader"
	apply_shader.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_apply_custom_shader", _shader_code.text)
	)
	shader_buttons.add_child(apply_shader)
	var reset_shader := Button.new()
	reset_shader.text = "Reset Shader"
	reset_shader.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_apply_custom_shader", "")
	)
	shader_buttons.add_child(reset_shader)
	root.add_child(shader_buttons)

	root.add_child(HSeparator.new())
	var ppf_label := Label.new()
	ppf_label.text = ".ppf Metadata"
	root.add_child(ppf_label)
	_ppf_name = LineEdit.new()
	_ppf_name.placeholder_text = "Preset Name"
	_ppf_name.text = "New PostFX Preset"
	root.add_child(_ppf_name)
	_ppf_author = LineEdit.new()
	_ppf_author.placeholder_text = "Author"
	root.add_child(_ppf_author)
	_ppf_description = LineEdit.new()
	_ppf_description.placeholder_text = "Description"
	root.add_child(_ppf_description)
	_ppf_path = LineEdit.new()
	_ppf_path.placeholder_text = "user://postfx/my_style.ppf"
	_ppf_path.text = "user://postfx/new_style.ppf"
	root.add_child(_ppf_path)

	var ppf_buttons := HBoxContainer.new()
	var save_btn := Button.new()
	save_btn.text = "Save .ppf"
	save_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_save_local", _ppf_payload())
	)
	ppf_buttons.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "Load .ppf"
	load_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_load_local", _ppf_path.text.strip_edges())
	)
	ppf_buttons.add_child(load_btn)
	var export_btn := Button.new()
	export_btn.text = "Export .ppf"
	export_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_export_local", _ppf_payload())
	)
	ppf_buttons.add_child(export_btn)
	root.add_child(ppf_buttons)

	_ppf_url = LineEdit.new()
	_ppf_url.placeholder_text = "https://example.com/presets/graphic_novel.ppf"
	root.add_child(_ppf_url)
	var import_btn := Button.new()
	import_btn.text = "Import Remote .ppf"
	import_btn.pressed.connect(func() -> void:
		environment_setting_changed.emit("postfx_import_url", _ppf_url.text.strip_edges())
	)
	root.add_child(import_btn)

	if not _pending_state.is_empty():
		set_postfx_state(_pending_state)
	if _pending_preview_texture != null:
		set_postfx_preview_texture(_pending_preview_texture)

func set_postfx_state(state: Dictionary) -> void:
	_pending_state = state.duplicate(true)
	if _outline_slider == null:
		return
	_updating_ui = true
	var effects_by_name: Dictionary = {}
	var effects_variant: Variant = state.get("effects", [])
	if effects_variant is Array:
		for item in effects_variant:
			if item is Dictionary:
				var entry: Dictionary = item
				effects_by_name[String(entry.get("name", ""))] = entry.get("value")
	_set_slider_from_state(_outline_slider, effects_by_name, "outline_strength")
	_set_slider_from_state(_contrast_slider, effects_by_name, "contrast")
	_set_slider_from_state(_saturation_slider, effects_by_name, "saturation")
	_set_slider_from_state(_vignette_slider, effects_by_name, "vignette_strength")
	_set_slider_from_state(_bloom_slider, effects_by_name, "bloom_strength")
	_set_slider_from_state(_tint_strength_slider, effects_by_name, "tint_strength")
	_set_slider_from_state(_outlines_layer_thickness_slider, effects_by_name, "outlines_layer_thickness")
	_set_slider_from_state(_outlines_layer_depth_threshold_slider, effects_by_name, "outlines_layer_depth_threshold")
	_set_slider_from_state(_outlines_layer_depth_sensitivity_slider, effects_by_name, "outlines_layer_depth_sensitivity")
	_set_slider_from_state(_outlines_layer_normal_sensitivity_slider, effects_by_name, "outlines_layer_normal_sensitivity")
	_set_slider_from_state(_outlines_layer_opacity_slider, effects_by_name, "outlines_layer_opacity")
	if _outlines_layer_enable != null and effects_by_name.has("outlines_layer_enabled"):
		_outlines_layer_enable.button_pressed = bool(effects_by_name["outlines_layer_enabled"])
	if _tint_picker != null and state.has("color_tint"):
		_tint_picker.color = state.get("color_tint", Color(1.0, 1.0, 1.0, 1.0))
	if _outlines_layer_color_picker != null and effects_by_name.has("outlines_layer_color"):
		_outlines_layer_color_picker.color = effects_by_name["outlines_layer_color"]
	_updating_ui = false

func set_postfx_preview_texture(texture: Texture2D) -> void:
	_pending_preview_texture = texture
	if _preview != null:
		_preview.texture = texture

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
			_ppf_path.text = path_str
			environment_setting_changed.emit("postfx_load_local", path_str)
			break

func _add_effect_slider(root: VBoxContainer, label_text: String, min_v: float, max_v: float, default_v: float, step_v: float, effect_name: String) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 64
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = "%.2f" % default_v
	row.add_child(value_label)
	root.add_child(row)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.value = default_v
	slider.custom_minimum_size.y = 22
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%.2f" % v
		if _updating_ui:
			return
		environment_setting_changed.emit("postfx_effect", {"name": effect_name, "value": v})
	)
	root.add_child(slider)
	return slider

func _set_slider_from_state(slider: HSlider, effects_by_name: Dictionary, key: String) -> void:
	if slider == null:
		return
	if effects_by_name.has(key):
		slider.value = float(effects_by_name[key])

func _ppf_payload() -> Dictionary:
	return {
		"path": _ppf_path.text.strip_edges(),
		"name": _ppf_name.text.strip_edges(),
		"author": _ppf_author.text.strip_edges(),
		"description": _ppf_description.text.strip_edges(),
		"custom_shader_code": _shader_code.text,
	}
