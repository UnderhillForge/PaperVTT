extends Control
class_name WorldBrushInspector

const GM_AUDIO_PANEL_SCRIPT: Script = preload("res://addons/paper_vtt/audio/gm_audio_panel.gd")
const ENVIRONMENT_PANEL_SCRIPT: Script = preload("res://scripts/ui/EnvironmentPanel.gd")

signal brush_size_changed(size: float)
signal brush_strength_changed(strength: float)
signal brush_shape_changed(shape: String)
signal layer_changed(layer: int)
signal tool_setting_changed(setting: String, value: Variant)
signal environment_setting_changed(setting: String, value: Variant)

const BG_COLOR: Color = Color(0.05, 0.07, 0.10, 0.85)
const EDGE_COLOR: Color = Color(0.20, 0.28, 0.36, 0.50)
const TEXT_COLOR: Color = Color(0.85, 0.90, 0.95, 1.0)
const LABEL_COLOR: Color = Color(0.68, 0.76, 0.84, 1.0)
const SLIDER_BG: Color = Color(0.08, 0.12, 0.16, 0.94)
const PANEL_MARGIN: int = 0  # Full edge to edge at top, inner margins on sides
const PANEL_WIDTH: int = 420
const COLLAPSE_HANDLE_WIDTH: int = 36
const ROUNDED_CORNER_RADIUS: int = 12
const HEADER_ICON_SIZE: int = 24
const COLLAPSE_ICON_MAX_WIDTH: int = 18
const INSPECTOR_ICON_PATH: String = "res://assets/icons/000000/transparent/1x1/various-artists/infinity.svg"
const COLLAPSE_ICON_PATH: String = "res://assets/icons/000000/transparent/1x1/viscious-speed/abstract-030.svg"

var _panel: Panel = null
var _scroll_container: ScrollContainer = null
var _vbox: VBoxContainer = null
var _tab_container: TabContainer = null
var _brush_controls_container: VBoxContainer = null
var _size_slider: HSlider = null
var _strength_slider: HSlider = null
var _layer_spinbox: SpinBox = null
var _tool_label: Label = null
var _tool_icon: TextureRect = null
var _collapse_button: Button = null
var _custom_options_container: VBoxContainer = null
var _audio_panel: Control = null
var _environment_panel: Control = null
var _is_collapsed: bool = false

var _current_tool: String = "select"
var _icon_cache: Dictionary = {}

func _ready() -> void:
	# Full-height, right-edge docked layout
	self_modulate = Color.WHITE
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	
	# Anchors: right edge, full height
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	_build_ui()

func get_panel_width() -> int:
	return PANEL_WIDTH

func set_tool(tool_name: String, icon_path: String = "") -> void:
	_current_tool = tool_name
	if _tool_label != null:
		_tool_label.text = _format_tool_label(tool_name)
	if _tool_icon != null and _tool_icon.texture == null:
		_tool_icon.texture = _load_icon(INSPECTOR_ICON_PATH)
	_update_custom_options()

func set_brush_size(size: float) -> void:
	if _size_slider != null:
		_size_slider.value = size

func set_brush_strength(strength: float) -> void:
	if _strength_slider != null:
		_strength_slider.value = strength

func set_active_layer(layer: int) -> void:
	if _layer_spinbox != null:
		_layer_spinbox.value = layer

func _build_ui() -> void:
	# Main panel with rounded corners and transparent dark background
	_panel = Panel.new()
	_panel.self_modulate = Color.WHITE
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	
	# StyleBox with rounded corners
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.border_color = EDGE_COLOR
	sb.border_width_left = 1
	sb.border_width_right = 0  # No right border at edge
	sb.border_width_top = 0    # Extend full height
	sb.border_width_bottom = 0
	sb.corner_radius_top_left = ROUNDED_CORNER_RADIUS
	sb.corner_radius_bottom_left = ROUNDED_CORNER_RADIUS
	sb.corner_radius_top_right = 0  # Flush right edge
	sb.corner_radius_bottom_right = 0
	_panel.add_theme_stylebox_override("panel", sb)
	
	# Root layout with a persistent header and tabbed body content
	_vbox = VBoxContainer.new()
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(_vbox)

	# Left-edge collapse handle stays clickable when panel is collapsed.
	_collapse_button = Button.new()
	_collapse_button.flat = true
	_collapse_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_collapse_button.focus_mode = Control.FOCUS_NONE
	_collapse_button.expand_icon = false
	_collapse_button.icon = null
	_collapse_button.custom_minimum_size = Vector2(COLLAPSE_HANDLE_WIDTH - 6, 32)
	_collapse_button.text = "<"
	_collapse_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_collapse_button.add_theme_color_override("font_color", TEXT_COLOR)
	var handle_style := StyleBoxFlat.new()
	handle_style.bg_color = Color(0.08, 0.13, 0.18, 0.96)
	handle_style.border_width_left = 1
	handle_style.border_width_top = 1
	handle_style.border_width_bottom = 1
	handle_style.border_color = EDGE_COLOR
	handle_style.corner_radius_top_left = 8
	handle_style.corner_radius_bottom_left = 8
	_collapse_button.add_theme_stylebox_override("normal", handle_style)
	_collapse_button.add_theme_stylebox_override("hover", handle_style)
	_collapse_button.add_theme_stylebox_override("pressed", handle_style)
	_collapse_button.tooltip_text = "Collapse Inspector"
	_collapse_button.pressed.connect(_on_toggle_collapse_pressed)
	_collapse_button.z_index = 10
	_collapse_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_collapse_button.offset_left = 2
	_collapse_button.offset_top = 8
	_collapse_button.offset_right = _collapse_button.offset_left + float(COLLAPSE_HANDLE_WIDTH - 6)
	_collapse_button.offset_bottom = _collapse_button.offset_top + 32.0
	_panel.add_child(_collapse_button)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.custom_minimum_size.y = 38
	_vbox.add_child(header)

	_tool_icon = TextureRect.new()
	_tool_icon.custom_minimum_size = Vector2(HEADER_ICON_SIZE, HEADER_ICON_SIZE)
	_tool_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tool_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_tool_icon.texture = _load_icon(INSPECTOR_ICON_PATH)
	header.add_child(_tool_icon)

	_tool_label = Label.new()
	_tool_label.text = "Inspector"
	_tool_label.custom_minimum_size.x = 160
	_tool_label.add_theme_color_override("font_color", TEXT_COLOR)
	_tool_label.add_theme_font_size_override("font_size", 16)
	header.add_child(_tool_label)

	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)

	_vbox.add_child(HSeparator.new())

	_tab_container = TabContainer.new()
	_tab_container.tabs_visible = true
	_tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_tab_container)

	var inspector_tab := VBoxContainer.new()
	inspector_tab.name = "Inspector"
	_tab_container.add_child(inspector_tab)
	_tab_container.set_tab_title(0, "Inspector")

	# ScrollContainer for content overflow
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_tab.add_child(_scroll_container)

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 12)
	_scroll_container.add_child(content_vbox)

	# Margins container for left/right padding
	var margin_cont = MarginContainer.new()
	margin_cont.add_theme_constant_override("margin_left", 16)
	margin_cont.add_theme_constant_override("margin_right", 16)
	margin_cont.add_theme_constant_override("margin_top", 16)
	margin_cont.add_theme_constant_override("margin_bottom", 16)
	content_vbox.add_child(margin_cont)
	
	# Create inner content container
	var inner_vbox = VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 12)
	margin_cont.add_child(inner_vbox)

	inner_vbox.add_child(HSeparator.new())

	_brush_controls_container = VBoxContainer.new()
	_brush_controls_container.add_theme_constant_override("separation", 10)
	inner_vbox.add_child(_brush_controls_container)

	# Brush size
	_brush_controls_container.add_child(_make_label("Brush Size"))
	_size_slider = _make_slider(1.0, 64.0, 10.0, 0.5)
	_size_slider.value_changed.connect(_on_size_changed)
	_brush_controls_container.add_child(_size_slider)

	# Brush strength
	_brush_controls_container.add_child(_make_label("Brush Strength"))
	_strength_slider = _make_slider(0.05, 1.0, 0.25, 0.05)
	_strength_slider.value_changed.connect(_on_strength_changed)
	_brush_controls_container.add_child(_strength_slider)

	# Layer selection
	_brush_controls_container.add_child(_make_label("World Layer"))
	_layer_spinbox = _make_spinbox(0, 20, 0)
	_layer_spinbox.value_changed.connect(_on_layer_changed)
	_brush_controls_container.add_child(_layer_spinbox)

	inner_vbox.add_child(HSeparator.new())

	# Custom options placeholder (prepared for future: Chat, Combat, Compendiums)
	_custom_options_container = VBoxContainer.new()
	_custom_options_container.add_theme_constant_override("separation", 8)
	inner_vbox.add_child(_custom_options_container)

	var music_tab := MarginContainer.new()
	music_tab.name = "Music"
	music_tab.add_theme_constant_override("margin_left", 16)
	music_tab.add_theme_constant_override("margin_right", 16)
	music_tab.add_theme_constant_override("margin_top", 16)
	music_tab.add_theme_constant_override("margin_bottom", 16)
	_tab_container.add_child(music_tab)
	_tab_container.set_tab_title(1, "Music")

	if GM_AUDIO_PANEL_SCRIPT != null:
		var panel_instance: Variant = GM_AUDIO_PANEL_SCRIPT.new()
		if panel_instance is Control:
			_audio_panel = panel_instance as Control
			_audio_panel.visible = true
			music_tab.add_child(_audio_panel)

	if _audio_panel == null:
		music_tab.add_child(_make_label("Music panel unavailable."))

	var environment_tab := MarginContainer.new()
	environment_tab.name = "Environment"
	environment_tab.add_theme_constant_override("margin_left", 0)
	environment_tab.add_theme_constant_override("margin_right", 0)
	environment_tab.add_theme_constant_override("margin_top", 0)
	environment_tab.add_theme_constant_override("margin_bottom", 0)
	_tab_container.add_child(environment_tab)
	_tab_container.set_tab_title(2, "Environment")

	if ENVIRONMENT_PANEL_SCRIPT != null:
		var env_instance: Variant = ENVIRONMENT_PANEL_SCRIPT.new()
		if env_instance is Control:
			_environment_panel = env_instance as Control
			_environment_panel.visible = true
			environment_tab.add_child(_environment_panel)
			if _environment_panel.has_signal("environment_setting_changed"):
				_environment_panel.connect("environment_setting_changed", Callable(self, "_on_environment_setting_changed"))

	if _environment_panel == null:
		environment_tab.add_child(_make_label("Environment panel unavailable."))

	_tab_container.current_tab = 0
	_set_collapsed(false)
	_update_custom_options()

func _update_custom_options() -> void:
	if _brush_controls_container != null:
		_brush_controls_container.visible = _tool_uses_base_brush_controls(_current_tool)

	for child in _custom_options_container.get_children():
		child.queue_free()

	match _current_tool:
		"select":
			_custom_options_container.add_child(_make_label("No brush active."))
			_custom_options_container.add_child(_make_label("Use the Music tab for GM music control."))

		"raise", "lower", "smooth", "paint":
			pass  # Core brush size/strength sliders are sufficient

		"flatten":
			_custom_options_container.add_child(_make_label("Flatten Height"))
			var height_spin := _make_spinbox(-14.0, 38.0, 0.0)
			height_spin.value_changed.connect(func(v): tool_setting_changed.emit("flatten_height", v))
			_custom_options_container.add_child(height_spin)

		"wall":
			_custom_options_container.add_child(_make_label("Wall Type"))
			var wall_type := OptionButton.new()
			wall_type.add_item("Stone")
			wall_type.add_item("Wood")
			wall_type.add_item("Metal")
			wall_type.custom_minimum_size.y = 28
			wall_type.item_selected.connect(func(idx: int):
				var types: Array[String] = ["stone", "wood", "metal"]
				tool_setting_changed.emit("wall_type", types[idx])
			)
			_custom_options_container.add_child(wall_type)
			_custom_options_container.add_child(_make_label("Wall Height"))
			var height_spin := _make_spinbox(1.0, 8.0, 3.4)
			height_spin.value_changed.connect(func(v): tool_setting_changed.emit("wall_height", v))
			_custom_options_container.add_child(height_spin)
			var rect_cb := CheckBox.new()
			rect_cb.text = "Rectangle Mode"
			rect_cb.toggled.connect(func(v): tool_setting_changed.emit("wall_rect_mode", v))
			_custom_options_container.add_child(rect_cb)
			var snap_cb := CheckBox.new()
			snap_cb.text = "Grid Snap"
			snap_cb.button_pressed = true
			snap_cb.toggled.connect(func(v): tool_setting_changed.emit("grid_snap", v))
			_custom_options_container.add_child(snap_cb)

		"waterpaint":
			_custom_options_container.add_child(_make_label("Water Depth"))
			var depth_spin := _make_spinbox(0.5, 25.0, 5.0)
			depth_spin.value_changed.connect(func(v): tool_setting_changed.emit("river_average_depth", v))
			_custom_options_container.add_child(depth_spin)
			_custom_options_container.add_child(_make_label("Water Width"))
			var width_spin := _make_spinbox(1.0, 30.0, 5.0)
			width_spin.value_changed.connect(func(v): tool_setting_changed.emit("river_width", v))
			_custom_options_container.add_child(width_spin)

		"riverdraw":
			_custom_options_container.add_child(_make_label("Water Mode"))
			var mode_btn := OptionButton.new()
			mode_btn.add_item("River")
			mode_btn.add_item("Lake")
			mode_btn.add_item("Fill")
			mode_btn.custom_minimum_size.y = 28
			mode_btn.item_selected.connect(func(idx: int):
				var modes: Array[String] = ["river", "lake", "fill"]
				tool_setting_changed.emit("water_mode", modes[idx])
			)
			_custom_options_container.add_child(mode_btn)
			_custom_options_container.add_child(_make_label("River Width"))
			var width_spin := _make_spinbox(1.0, 30.0, 5.0)
			width_spin.value_changed.connect(func(v): tool_setting_changed.emit("river_width", v))
			_custom_options_container.add_child(width_spin)
			_custom_options_container.add_child(_make_label("Average Depth"))
			var depth_spin := _make_spinbox(0.5, 25.0, 15.0)
			depth_spin.value_changed.connect(func(v): tool_setting_changed.emit("river_average_depth", v))
			_custom_options_container.add_child(depth_spin)

		"snowpaint":
			# Snow amount is controlled via brush strength; show a note
			_custom_options_container.add_child(_make_label("Use Strength slider\nto control snow depth"))

		"texturepaint":
			_custom_options_container.add_child(_make_label("Tile Size"))
			var tile_spin := _make_spinbox(0.5, 20.0, 4.0)
			tile_spin.value_changed.connect(func(v): tool_setting_changed.emit("texture_tile_size", v))
			_custom_options_container.add_child(tile_spin)
			_custom_options_container.add_child(_make_label("Density"))
			var density_slider := _make_slider(0.01, 1.0, 0.5, 0.01)
			density_slider.value_changed.connect(func(v): tool_setting_changed.emit("texture_density", v))
			_custom_options_container.add_child(density_slider)
			_custom_options_container.add_child(_make_label("Edge Softness"))
			var soft_slider := _make_slider(0.0, 1.0, 0.3, 0.05)
			soft_slider.value_changed.connect(func(v): tool_setting_changed.emit("texture_edge_softness", v))
			_custom_options_container.add_child(soft_slider)

		"grasspaint":
			_custom_options_container.add_child(_make_label("Grass Density"))
			var density_slider := _make_slider(0.1, 1.0, 0.7, 0.05)
			density_slider.value_changed.connect(func(v): tool_setting_changed.emit("grass_density", v))
			_custom_options_container.add_child(density_slider)
			_custom_options_container.add_child(_make_label("Grass Height"))
			var height_slider := _make_slider(0.2, 3.0, 1.0, 0.1)
			height_slider.value_changed.connect(func(v): tool_setting_changed.emit("grass_height", v))
			_custom_options_container.add_child(height_slider)

		"stamp":
			var snap_cb := CheckBox.new()
			snap_cb.text = "Grid Snap"
			snap_cb.button_pressed = true
			snap_cb.toggled.connect(func(v): tool_setting_changed.emit("grid_snap", v))
			_custom_options_container.add_child(snap_cb)

func _tool_uses_base_brush_controls(tool_name: String) -> bool:
	match tool_name:
		"raise", "lower", "smooth", "paint", "flatten", "texturepaint", "waterpaint", "snowpaint", "grasspaint":
			return true
		_:
			return false

func _load_icon(icon_path: String) -> Texture2D:
	if _icon_cache.has(icon_path):
		return _icon_cache[icon_path]
	if not ResourceLoader.exists(icon_path):
		return null
	var tex := load(icon_path) as Texture2D
	if tex != null:
		_icon_cache[icon_path] = tex
	return tex

func _on_toggle_collapse_pressed() -> void:
	_set_collapsed(not _is_collapsed)

func _set_collapsed(collapsed: bool) -> void:
	_is_collapsed = collapsed
	custom_minimum_size.x = PANEL_WIDTH
	if collapsed:
		offset_left = -float(COLLAPSE_HANDLE_WIDTH)
		offset_right = float(PANEL_WIDTH - COLLAPSE_HANDLE_WIDTH)
	else:
		offset_left = -float(PANEL_WIDTH)
		offset_right = 0.0
	if _vbox != null:
		_vbox.visible = not collapsed
	if _collapse_button != null:
		_collapse_button.rotation_degrees = 0.0
		_collapse_button.text = ">" if collapsed else "<"
		_collapse_button.tooltip_text = "Expand Inspector" if collapsed else "Collapse Inspector"

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 14)
	return label

func _make_slider(min_val: float, max_val: float, default_val: float, step: float = 0.1) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.step = step
	slider.custom_minimum_size.y = 24
	slider.add_theme_color_override("font_color", TEXT_COLOR)
	var theme := Theme.new()
	slider.add_theme_stylebox_override("background", _make_slider_bg())
	return slider

func _make_slider_bg() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SLIDER_BG
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	return sb

func _make_spinbox(min_val: float, max_val: float, default_val: float) -> SpinBox:
	var spinbox := SpinBox.new()
	spinbox.min_value = min_val
	spinbox.max_value = max_val
	spinbox.value = default_val
	spinbox.step = 0.5 if max_val <= 2.0 else (0.1 if max_val <= 10.0 else 1.0)
	spinbox.custom_minimum_size.y = 28
	spinbox.add_theme_color_override("font_color", TEXT_COLOR)
	return spinbox

func _on_size_changed(value: float) -> void:
	brush_size_changed.emit(value)

func _on_strength_changed(value: float) -> void:
	brush_strength_changed.emit(value)

func _on_layer_changed(value: float) -> void:
	layer_changed.emit(int(value))


func _on_environment_setting_changed(setting: String, value: Variant) -> void:
	environment_setting_changed.emit(setting, value)


func set_environment_state(state: Dictionary) -> void:
	if _environment_panel != null and _environment_panel.has_method("set_environment_state"):
		_environment_panel.call("set_environment_state", state)


func set_environment_active_weather(active_weathers: Array[String]) -> void:
	if _environment_panel != null and _environment_panel.has_method("set_active_weather"):
		_environment_panel.call("set_active_weather", active_weathers)

func _format_tool_label(tool_name: String) -> String:
	match tool_name:
		"raise": return "Raise Terrain"
		"lower": return "Lower Terrain"
		"smooth": return "Smooth Terrain"
		"flatten": return "Flatten Height"
		"paint": return "Terrain Paint"
		"texturepaint": return "Texture Paint"
		"waterpaint": return "Water Paint"
		"snowpaint": return "Snow Paint"
		"riverdraw": return "Water Flow"
		"wall": return "Smart Wall"
		"stamp": return "Place Objects"
		"grasspaint": return "Paint Foliage"
		"select": return "Select / None"
		_: return tool_name.capitalize()
