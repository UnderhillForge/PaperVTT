extends Control
class_name WorldBrushInspector

const GM_AUDIO_PANEL_SCRIPT: Script = preload("res://addons/paper_vtt/audio/gm_audio_panel.gd")
const ENVIRONMENT_PANEL_SCRIPT: Script = preload("res://scripts/ui/EnvironmentPanel.gd")
const POSTFX_PANEL_SCRIPT: Script = preload("res://scripts/ui/PostFxPanel.gd")

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
const INSPECTOR_ICON_PATH: String = "res://assets/ui/icons/000000/transparent/1x1/various-artists/infinity.svg"
const COLLAPSE_ICON_PATH: String = "res://assets/ui/icons/000000/transparent/1x1/viscious-speed/abstract-030.svg"
const WORLD_TEXTURE_ROOT: String = "res://assets/world/textures"
const TEXTURE_TILE_SIZE: int = 66
const TEXTURE_GRID_GAP: int = 4
const TEXTURE_GRID_MIN_COLUMNS: int = 3
const TEXTURE_GRID_MAX_COLUMNS: int = 5

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
var _postfx_panel: Control = null
var _is_collapsed: bool = false
var _updating_ui: bool = false

var _current_tool: String = "select"
var _current_selected_texture: String = ""
var _texture_grid: GridContainer = null
var _selected_texture_name_label: Label = null
var _selected_texture_preview: TextureRect = null
var _tool_state: Dictionary = {}
var _texture_preview_painter: RefCounted = null
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

func set_tool_state(state: Dictionary) -> void:
	for key in state.keys():
		_tool_state[String(key)] = state[key]
	if state.has("selected_texture_id"):
		_current_selected_texture = String(state.get("selected_texture_id", ""))
	_update_custom_options()

func set_texture_painter(painter: RefCounted) -> void:
	_texture_preview_painter = painter
	if _current_tool == "texturepaint":
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

	var pfx_tab := MarginContainer.new()
	pfx_tab.name = "PFX"
	pfx_tab.add_theme_constant_override("margin_left", 0)
	pfx_tab.add_theme_constant_override("margin_right", 0)
	pfx_tab.add_theme_constant_override("margin_top", 0)
	pfx_tab.add_theme_constant_override("margin_bottom", 0)
	_tab_container.add_child(pfx_tab)
	_tab_container.set_tab_title(3, "PFX")

	if POSTFX_PANEL_SCRIPT != null:
		var pfx_instance: Variant = POSTFX_PANEL_SCRIPT.new()
		if pfx_instance is Control:
			_postfx_panel = pfx_instance as Control
			_postfx_panel.visible = true
			pfx_tab.add_child(_postfx_panel)
			if _postfx_panel.has_signal("environment_setting_changed"):
				_postfx_panel.connect("environment_setting_changed", Callable(self, "_on_environment_setting_changed"))

	if _postfx_panel == null:
		pfx_tab.add_child(_make_label("PFX panel unavailable."))

	_tab_container.current_tab = 0
	_set_collapsed(false)
	_update_custom_options()

func _update_custom_options() -> void:
	if _brush_controls_container != null:
		_brush_controls_container.visible = _tool_uses_base_brush_controls(_current_tool)

	_updating_ui = true
	for child in _custom_options_container.get_children():
		child.queue_free()
	_texture_grid = null
	_selected_texture_name_label = null
	_selected_texture_preview = null

	var world_layer: int = int(_tool_state.get("world_layer", 0))
	var brush_mode: String = String(_tool_state.get("brush_mode", "smooth"))
	var brush_softness: float = clampf(float(_tool_state.get("brush_softness", 0.42)), 0.0, 1.0)
	var smooth_post_pass_enabled: bool = bool(_tool_state.get("smooth_post_pass_enabled", true))
	var smooth_post_pass_strength: float = clampf(float(_tool_state.get("smooth_post_pass_strength", 0.12)), 0.0, 0.35)
	var texture_tile_size: float = clampf(float(_tool_state.get("texture_tile_size", 8.0)), 1.0, 32.0)
	var texture_erase_mode: bool = bool(_tool_state.get("texture_erase_mode", false))
	var texture_stamp_mode: bool = bool(_tool_state.get("texture_stamp_mode", false))
	var texture_stamp_overlap: float = clampf(float(_tool_state.get("texture_stamp_overlap", 0.28)), 0.0, 0.95)
	var texture_stamp_scatter: float = clampf(float(_tool_state.get("texture_stamp_scatter", 0.32)), 0.0, 1.0)
	var selected_texture_id: String = String(_tool_state.get("selected_texture_id", _current_selected_texture))
	var wall_type: String = String(_tool_state.get("wall_type", "stone"))
	var wall_height: float = float(_tool_state.get("wall_height", 3.4))
	var wall_rect_mode: bool = bool(_tool_state.get("wall_rect_mode", false))
	var wall_match_connected_heights: bool = bool(_tool_state.get("wall_match_connected_heights", true))
	var wall_add_foundation: bool = bool(_tool_state.get("wall_add_foundation", true))
	var wall_opening_height_snap: bool = bool(_tool_state.get("wall_opening_height_snap", true))
	var wall_jitter: bool = bool(_tool_state.get("wall_jitter", true))
	var river_width: float = float(_tool_state.get("river_width", 5.0))
	var river_flow_speed: float = float(_tool_state.get("river_flow_speed", 0.24))
	var river_average_depth: float = float(_tool_state.get("river_average_depth", 15.0))
	var water_mode: String = String(_tool_state.get("water_mode", "river"))

	if _current_tool == "select" or _current_tool == "":
		_custom_options_container.add_child(_make_label("Select a tool from the radial menu (V)"))
		_custom_options_container.add_child(_make_label("World Layer: %d" % world_layer))
		_updating_ui = false
		return

	if _current_tool in ["raise", "lower", "smooth", "flatten"]:
		_custom_options_container.add_child(_make_label("Terrain Brush"))
		_custom_options_container.add_child(_make_label("Falloff Type"))
		var falloff_row := HBoxContainer.new()
		var falloff_option := OptionButton.new()
		falloff_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		falloff_option.add_item("Smooth")
		falloff_option.set_item_metadata(0, "smooth")
		falloff_option.add_item("Sharp")
		falloff_option.set_item_metadata(1, "sharp")
		falloff_option.select(0 if brush_mode != "sharp" else 1)
		falloff_option.item_selected.connect(func(index: int) -> void:
			var mode_value: String = "smooth"
			var md: Variant = falloff_option.get_item_metadata(index)
			if md is String and String(md) != "":
				mode_value = String(md)
			tool_setting_changed.emit("brush_mode", mode_value)
		)
		falloff_row.add_child(falloff_option)
		_custom_options_container.add_child(falloff_row)
		if brush_mode == "smooth":
			_custom_options_container.add_child(_make_label("Smoothing Amount"))
			var softness_slider := _make_slider(0.0, 1.0, brush_softness, 0.01)
			softness_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("brush_softness", v))
			_custom_options_container.add_child(softness_slider)
			if _current_tool == "raise" or _current_tool == "lower":
				var post_smooth_check := CheckBox.new()
				post_smooth_check.text = "Post-smooth pass"
				post_smooth_check.button_pressed = smooth_post_pass_enabled
				post_smooth_check.toggled.connect(func(v: bool) -> void: tool_setting_changed.emit("smooth_post_pass_enabled", v))
				_custom_options_container.add_child(post_smooth_check)
				if smooth_post_pass_enabled:
					_custom_options_container.add_child(_make_label("Post-smooth Strength"))
					var post_smooth_slider := _make_slider(0.0, 0.35, smooth_post_pass_strength, 0.01)
					post_smooth_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("smooth_post_pass_strength", v))
					_custom_options_container.add_child(post_smooth_slider)
		_custom_options_container.add_child(_make_label("World Layer: %d" % world_layer))

	if _current_tool == "texturepaint":
		_custom_options_container.add_child(_make_label("Texture Paint"))
		_custom_options_container.add_child(_make_label("Current Texture"))
		var texture_preview_box := VBoxContainer.new()
		texture_preview_box.add_theme_constant_override("separation", 6)
		_selected_texture_name_label = _make_label(selected_texture_id if selected_texture_id != "" else "Selected: none")
		texture_preview_box.add_child(_selected_texture_name_label)
		_selected_texture_preview = TextureRect.new()
		_selected_texture_preview.custom_minimum_size = Vector2(144, 84)
		_selected_texture_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_selected_texture_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_preview_box.add_child(_selected_texture_preview)
		_custom_options_container.add_child(texture_preview_box)
		_texture_grid = GridContainer.new()
		_texture_grid.columns = _compute_texture_grid_columns()
		_texture_grid.add_theme_constant_override("h_separation", TEXTURE_GRID_GAP)
		_texture_grid.add_theme_constant_override("v_separation", TEXTURE_GRID_GAP)
		_custom_options_container.add_child(_make_label("Texture Picker"))
		_custom_options_container.add_child(_texture_grid)
		populate_texture_buttons(_texture_preview_painter)
		_custom_options_container.add_child(_make_label("Texture Scale (m / tile)"))
		var texture_scale_slider := _make_slider(1.0, 32.0, texture_tile_size, 0.1)
		texture_scale_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("texture_tile_size", v))
		_custom_options_container.add_child(texture_scale_slider)
		var erase_mode_check := CheckBox.new()
		erase_mode_check.text = "Erase / Subtract Mode"
		erase_mode_check.button_pressed = texture_erase_mode
		erase_mode_check.toggled.connect(func(v: bool) -> void: tool_setting_changed.emit("texture_erase_mode", v))
		_custom_options_container.add_child(erase_mode_check)
		var stamp_mode_check := CheckBox.new()
		stamp_mode_check.text = "Stamp Mode"
		stamp_mode_check.button_pressed = texture_stamp_mode
		stamp_mode_check.toggled.connect(func(v: bool) -> void: tool_setting_changed.emit("texture_stamp_mode", v))
		_custom_options_container.add_child(stamp_mode_check)
		_custom_options_container.add_child(_make_label("Stamp Overlap"))
		var overlap_slider := _make_slider(0.0, 0.95, texture_stamp_overlap, 0.01)
		overlap_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("texture_stamp_overlap", v))
		_custom_options_container.add_child(overlap_slider)
		_custom_options_container.add_child(_make_label("Stamp Scatter"))
		var scatter_slider := _make_slider(0.0, 1.0, texture_stamp_scatter, 0.01)
		scatter_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("texture_stamp_scatter", v))
		_custom_options_container.add_child(scatter_slider)

	if _current_tool == "waterpaint" or _current_tool == "riverdraw":
		_custom_options_container.add_child(_make_label("Water Settings"))
		if _current_tool == "waterpaint":
			_custom_options_container.add_child(_make_label("Brush strength controls wetting + carve amount"))
		else:
			_custom_options_container.add_child(_make_label("Mode: %s" % water_mode.capitalize()))
		var river_width_row := HBoxContainer.new()
		river_width_row.add_child(_make_label("Brush / Width"))
		var river_width_slider := _make_slider(1.0, 30.0, river_width, 0.1)
		river_width_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("river_width", v))
		river_width_row.add_child(river_width_slider)
		_custom_options_container.add_child(river_width_row)
		var flow_row := HBoxContainer.new()
		flow_row.add_child(_make_label("Flow Speed"))
		var flow_slider := _make_slider(0.0, 3.0, river_flow_speed, 0.01)
		flow_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("river_flow_speed", v))
		flow_row.add_child(flow_slider)
		_custom_options_container.add_child(flow_row)
		var depth_row := HBoxContainer.new()
		depth_row.add_child(_make_label("Depth / Avg Depth"))
		var depth_slider := _make_slider(0.5, 30.0, river_average_depth, 0.1)
		depth_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("river_average_depth", v))
		depth_row.add_child(depth_slider)
		_custom_options_container.add_child(depth_row)

	if _current_tool == "snowpaint" or _current_tool == "snowerase":
		_custom_options_container.add_child(_make_label("Snow Settings"))
		_custom_options_container.add_child(_make_label("Snow Depth / Accumulation"))
		var snow_depth_slider := _make_slider(0.0, 1.0, _strength_slider.value, 0.01)
		snow_depth_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("brush_strength", v))
		_custom_options_container.add_child(snow_depth_slider)
		_custom_options_container.add_child(_make_label("Melt Rate (optional)"))
		var melt_row := HBoxContainer.new()
		var melt_slider := _make_slider(0.0, 1.0, float(_tool_state.get("snow_melt_rate", 0.0)), 0.01)
		melt_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("snow_melt_rate", v))
		melt_row.add_child(melt_slider)
		_custom_options_container.add_child(melt_row)

	if _current_tool == "wall":
		_custom_options_container.add_child(_make_label("Smart Wall"))
		_custom_options_container.add_child(_make_label("Wall Type / Style"))
		var wall_type_option := OptionButton.new()
		wall_type_option.add_item("Stone")
		wall_type_option.set_item_metadata(0, "stone")
		wall_type_option.add_item("Tudor")
		wall_type_option.set_item_metadata(1, "tudor")
		wall_type_option.select(1 if wall_type == "tudor" else 0)
		wall_type_option.item_selected.connect(func(index: int) -> void:
			var wall_value: String = "stone"
			var md: Variant = wall_type_option.get_item_metadata(index)
			if md is String and String(md) != "":
				wall_value = String(md)
			tool_setting_changed.emit("wall_type", wall_value)
		)
		_custom_options_container.add_child(wall_type_option)
		_custom_options_container.add_child(_make_label("Wall Height"))
		var wall_height_slider := _make_slider(1.0, 8.0, wall_height, 0.1)
		wall_height_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("wall_height", v))
		_custom_options_container.add_child(wall_height_slider)
		var openings_check := CheckBox.new()
		openings_check.text = "Default Openings (doors/windows)"
		openings_check.button_pressed = wall_opening_height_snap
		openings_check.toggled.connect(func(v: bool) -> void: tool_setting_changed.emit("wall_opening_height_snap", v))
		_custom_options_container.add_child(openings_check)
		var match_heights_check := CheckBox.new()
		match_heights_check.text = "Match Connected Heights"
		match_heights_check.button_pressed = wall_match_connected_heights
		match_heights_check.toggled.connect(func(v: bool) -> void: tool_setting_changed.emit("wall_match_connected_heights", v))
		_custom_options_container.add_child(match_heights_check)
		var foundation_check := CheckBox.new()
		foundation_check.text = "Add Foundation"
		foundation_check.button_pressed = wall_add_foundation
		foundation_check.toggled.connect(func(v: bool) -> void: tool_setting_changed.emit("wall_add_foundation", v))
		_custom_options_container.add_child(foundation_check)
		var rect_check := CheckBox.new()
		rect_check.text = "Rectangle Mode"
		rect_check.button_pressed = wall_rect_mode
		rect_check.toggled.connect(func(v: bool) -> void: tool_setting_changed.emit("wall_rect_mode", v))
		_custom_options_container.add_child(rect_check)
		var jitter_check := CheckBox.new()
		jitter_check.text = "Jitter"
		jitter_check.button_pressed = wall_jitter
		jitter_check.toggled.connect(func(v: bool) -> void: tool_setting_changed.emit("wall_jitter", v))
		_custom_options_container.add_child(jitter_check)

	if _current_tool == "flatten":
		_custom_options_container.add_child(_make_label("Flatten Height"))
		var height_spin := _make_spinbox(-14.0, 38.0, float(_tool_state.get("flatten_height", 0.0)))
		height_spin.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("flatten_height", v))
		_custom_options_container.add_child(height_spin)

	if _current_tool in ["raise", "lower", "smooth", "flatten", "texturepaint", "waterpaint", "snowpaint", "wall"]:
		_custom_options_container.add_child(_make_label("World Layer: %d" % world_layer))

	if _current_tool == "stamp":
		_custom_options_container.add_child(_make_label("Prefab placement uses the selected asset browser item."))

	if _current_tool == "boundary":
		_custom_options_container.add_child(_make_label("Cliff Line Tool"))
		var selected_boundary = _tool_state.get("boundary_selected", null)
		if selected_boundary == null:
			_custom_options_container.add_child(_make_label("Draw mode active - click terrain to place points\nDouble-click or Enter to finish line\nRight-click to cancel current line"))
		else:
			# Applied status badge
			var is_applied: bool = bool(selected_boundary.get("applied", false))
			if is_applied:
				var status_lbl := Label.new()
				status_lbl.text = "✓ Applied to terrain"
				status_lbl.add_theme_color_override("font_color", Color(0.35, 0.85, 0.5))
				_custom_options_container.add_child(status_lbl)
			# Undo button
			var undo_btn := Button.new()
			undo_btn.text = "Undo (Ctrl+Z)"
			undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			undo_btn.pressed.connect(func() -> void: tool_setting_changed.emit("boundary_undo", true))
			_custom_options_container.add_child(undo_btn)
			# Label / Name
			_custom_options_container.add_child(_make_label("Cliff Line Name"))
			var name_edit := LineEdit.new()
			name_edit.placeholder_text = "Cliff Line"
			name_edit.text = String(selected_boundary.get("label", "Cliff Line"))
			name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_edit.text_changed.connect(func(v: String) -> void: tool_setting_changed.emit("boundary_label", v))
			_custom_options_container.add_child(name_edit)
			# Material dropdown
			_custom_options_container.add_child(_make_label("Face Material"))
			var material_option := OptionButton.new()
			material_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var materials := ["rock", "stone", "dirt", "gravel"]
			var current_material: String = String(selected_boundary.get("face_material", "rock"))
			for i in range(materials.size()):
				var mat_name: String = materials[i]
				material_option.add_item(mat_name.capitalize())
				material_option.set_item_metadata(i, mat_name)
				if mat_name == current_material:
					material_option.select(i)
			material_option.item_selected.connect(func(index: int) -> void:
				var md: Variant = material_option.get_item_metadata(index)
				tool_setting_changed.emit("boundary_material", String(md) if md is String else "rock")
			)
			_custom_options_container.add_child(material_option)
			# Cliff face texture
			_custom_options_container.add_child(_make_label("Cliff Face Texture"))
			var texture_option := OptionButton.new()
			texture_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cliff_texture_paths: Array[String] = [
				"res://assets/world/textures/ground/cliff_brush.png",
				"res://assets/world/textures/ground/cliff2_brush.png",
			]
			var current_texture_path: String = String(selected_boundary.get("wall_texture_id", ""))
			# Normalise empty to the first (default) path so the dropdown reflects reality.
			if current_texture_path == "":
				current_texture_path = cliff_texture_paths[0]
			for tex_idx in range(cliff_texture_paths.size()):
				var tex_path: String = cliff_texture_paths[tex_idx]
				texture_option.add_item(tex_path.get_file())
				texture_option.set_item_metadata(tex_idx, tex_path)
				if tex_path == current_texture_path:
					texture_option.select(tex_idx)
			if texture_option.selected < 0:
				texture_option.select(0)
			texture_option.item_selected.connect(func(index: int) -> void:
				var md: Variant = texture_option.get_item_metadata(index)
				tool_setting_changed.emit("boundary_wall_texture_id", String(md))
			)
			_custom_options_container.add_child(texture_option)
			# Steepness slider
			_custom_options_container.add_child(_make_label("Steepness (0 deg = slope, 90 deg = cliff)"))
			var steep_slider := _make_slider(0.0, 90.0, float(selected_boundary.get("steepness", 80.0)), 1.0)
			steep_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("boundary_steepness", v))
			_custom_options_container.add_child(steep_slider)
			# Raise height slider
			_custom_options_container.add_child(_make_label("Raise Height (m)"))
			var height_slider := _make_slider(0.0, 40.0, float(selected_boundary.get("raise_height", 8.0)), 0.1)
			height_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("boundary_raise_height", v))
			_custom_options_container.add_child(height_slider)
			# Face width
			_custom_options_container.add_child(_make_label("Width of Face (m)"))
			var width_slider := _make_slider(0.5, 15.0, float(selected_boundary.get("wall_brush_width", 3.5)), 0.1)
			width_slider.value_changed.connect(func(v: float) -> void: tool_setting_changed.emit("boundary_wall_brush_width", v))
			_custom_options_container.add_child(width_slider)
			# Direction selector
			_custom_options_container.add_child(_make_label("Direction (Raised Side)"))
			var direction_row := HBoxContainer.new()
			var side_option := OptionButton.new()
			side_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			side_option.add_item("Left of line")
			side_option.set_item_metadata(0, 1)
			side_option.add_item("Right of line")
			side_option.set_item_metadata(1, -1)
			var current_side: int = int(selected_boundary.get("raise_side", 1))
			side_option.select(0 if current_side >= 0 else 1)
			side_option.item_selected.connect(func(index: int) -> void:
				var md: Variant = side_option.get_item_metadata(index)
				tool_setting_changed.emit("boundary_direction", int(md))
			)
			direction_row.add_child(side_option)
			var flip_btn := Button.new()
			flip_btn.text = "Flip"
			flip_btn.pressed.connect(func() -> void:
				var md: Variant = side_option.get_item_metadata(side_option.selected)
				var side_now: int = int(md)
				tool_setting_changed.emit("boundary_direction", -side_now)
			)
			direction_row.add_child(flip_btn)
			_custom_options_container.add_child(direction_row)
			# Apply / Delete buttons
			var btn_row := HBoxContainer.new()
			var apply_btn := Button.new()
			apply_btn.text = "Re-Apply Cliff" if is_applied else "Apply Cliff"
			apply_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			apply_btn.pressed.connect(func() -> void: tool_setting_changed.emit("boundary_apply", true))
			btn_row.add_child(apply_btn)
			var del_btn := Button.new()
			del_btn.text = "Delete"
			del_btn.pressed.connect(func() -> void: tool_setting_changed.emit("boundary_delete", true))
			btn_row.add_child(del_btn)
			_custom_options_container.add_child(btn_row)
			var cave_btn := Button.new()
			cave_btn.text = "Add Cave Entrance"
			cave_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cave_btn.pressed.connect(func() -> void: tool_setting_changed.emit("boundary_add_cave_entrance", true))
			_custom_options_container.add_child(cave_btn)
			# Cave entrance list with per-entry delete
			var entrances: Array = selected_boundary.get("cave_entrances", []) as Array
			if not entrances.is_empty():
				_custom_options_container.add_child(_make_label("Cave Entrances (%d)" % entrances.size()))
				for ent_idx in range(entrances.size()):
					var ent_data: Dictionary = entrances[ent_idx] as Dictionary
					var ent_row := HBoxContainer.new()
					var ent_lbl := Label.new()
					ent_lbl.text = String(ent_data.get("marker_id", "Cave %d" % (ent_idx + 1)))
					ent_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					ent_lbl.clip_text = true
					ent_row.add_child(ent_lbl)
					var ent_del := Button.new()
					ent_del.text = "✕"
					ent_del.tooltip_text = "Delete this cave entrance"
					var captured_idx: int = ent_idx
					ent_del.pressed.connect(func() -> void:
						tool_setting_changed.emit("boundary_delete_cave_entrance", captured_idx)
					)
					ent_row.add_child(ent_del)
					_custom_options_container.add_child(ent_row)

	if _custom_options_container.get_child_count() == 0:
		_custom_options_container.add_child(_make_label("No additional options for this tool."))

	_updating_ui = false
	if _current_tool == "texturepaint" and _current_selected_texture != "" and String(_tool_state.get("selected_texture_id", "")) == "":
		tool_setting_changed.emit("selected_texture_id", _current_selected_texture)

func _tool_uses_base_brush_controls(tool_name: String) -> bool:
	match tool_name:
		"raise", "lower", "smooth", "flatten", "texturepaint", "waterpaint", "snowpaint", "grasspaint":
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


func set_postfx_preview_texture(texture: Texture2D) -> void:
	if _postfx_panel != null and _postfx_panel.has_method("set_postfx_preview_texture"):
		_postfx_panel.call("set_postfx_preview_texture", texture)
	if _environment_panel != null and _environment_panel.has_method("set_postfx_preview_texture"):
		_environment_panel.call("set_postfx_preview_texture", texture)


func set_postfx_state(state: Dictionary) -> void:
	if _postfx_panel != null and _postfx_panel.has_method("set_postfx_state"):
		_postfx_panel.call("set_postfx_state", state)

func populate_texture_buttons(painter: RefCounted) -> void:
	_texture_preview_painter = painter
	if _texture_grid == null:
		return
	for child in _texture_grid.get_children():
		child.queue_free()

	var textures: Array[Dictionary] = _collect_texture_entries()
	if textures.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No texture packs found"
		_texture_grid.add_child(empty_label)
		return

	for tex_info in textures:
		var tex_id: String = String(tex_info.get("id", ""))
		var tex_name: String = String(tex_info.get("display_name", ""))
		var preview_path: String = String(tex_info.get("preview_path", ""))
		if tex_id.is_empty():
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(TEXTURE_TILE_SIZE, TEXTURE_TILE_SIZE)
		btn.toggle_mode = true
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", TEXTURE_TILE_SIZE - 10)
		btn.tooltip_text = tex_name
		btn.add_theme_font_size_override("font_size", 7)
		btn.text = tex_name.substr(0, 3).to_upper()
		var preview_tex: Texture2D = _load_texture_preview(preview_path)
		if preview_tex != null:
			btn.icon = preview_tex
			btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			btn.text = ""
		btn.pressed.connect(func() -> void:
			_on_texture_selected(tex_id)
		)
		_texture_grid.add_child(btn)
		if tex_id == _current_selected_texture:
			btn.button_pressed = true
		elif _current_selected_texture.is_empty():
			_current_selected_texture = tex_id
			btn.button_pressed = true

	if not _current_selected_texture.is_empty():
		_update_selected_texture_preview(_current_selected_texture)
		if not _updating_ui:
			tool_setting_changed.emit("selected_texture_id", _current_selected_texture)
	elif _current_tool == "texturepaint":
		for tex_info in textures:
			var first_tex_id: String = String(tex_info.get("id", ""))
			if first_tex_id != "":
				_current_selected_texture = first_tex_id
				_update_selected_texture_preview(_current_selected_texture)
				break

	if _current_tool == "texturepaint" and not _updating_ui and _current_selected_texture != "" and String(_tool_state.get("selected_texture_id", "")) == "":
		tool_setting_changed.emit("selected_texture_id", _current_selected_texture)

func _compute_texture_grid_columns() -> int:
	var usable_width: float = float(PANEL_WIDTH - 88)
	if _custom_options_container != null and _custom_options_container.size.x > 0.0:
		usable_width = _custom_options_container.size.x
	var tile_span: float = float(TEXTURE_TILE_SIZE + TEXTURE_GRID_GAP)
	var columns: int = int(floor(usable_width / tile_span))
	return clampi(columns, TEXTURE_GRID_MIN_COLUMNS, TEXTURE_GRID_MAX_COLUMNS)

func _on_texture_selected(texture_id: String) -> void:
	_current_selected_texture = texture_id
	_update_selected_texture_preview(texture_id)
	if not _updating_ui:
		tool_setting_changed.emit("selected_texture_id", texture_id)

func _update_selected_texture_preview(texture_id: String) -> void:
	if _selected_texture_name_label != null:
		_selected_texture_name_label.text = "Selected: %s" % _format_texture_display_name(texture_id)
	if _selected_texture_preview == null:
		return
	var preview_path: String = _find_texture_preview_path(texture_id)
	_selected_texture_preview.texture = _load_texture_preview(preview_path)

func _collect_texture_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	_collect_texture_entries_recursive(WORLD_TEXTURE_ROOT, entries, 0)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("display_name", "")).naturalnocasecmp_to(String(b.get("display_name", ""))) < 0
	)
	return entries

func _collect_texture_entries_recursive(folder_path: String, entries: Array[Dictionary], depth: int) -> void:
	if depth > 3:
		return
	var dir: DirAccess = DirAccess.open(folder_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and not name.begins_with("."):
			var lower_name: String = name.to_lower()
			if lower_name.ends_with(".png") or lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg") or lower_name.ends_with(".webp"):
				var texture_path: String = "%s/%s" % [folder_path, name]
				entries.append({
					"id": texture_path,
					"display_name": _format_texture_display_name(texture_path.trim_prefix(WORLD_TEXTURE_ROOT + "/")),
					"preview_path": texture_path,
				})
		elif dir.current_is_dir() and not name.begins_with("."):
			_collect_texture_entries_recursive("%s/%s" % [folder_path, name], entries, depth + 1)
		name = dir.get_next()
	dir.list_dir_end()

func _find_texture_preview_path(texture_id: String) -> String:
	var resolved_path: String = texture_id
	if not resolved_path.begins_with("res://"):
		resolved_path = "%s/%s" % [WORLD_TEXTURE_ROOT, texture_id]
	var lower_resolved_path: String = resolved_path.to_lower()
	if (lower_resolved_path.ends_with(".png") or lower_resolved_path.ends_with(".jpg") or lower_resolved_path.ends_with(".jpeg") or lower_resolved_path.ends_with(".webp")) and ResourceLoader.exists(resolved_path):
		return resolved_path

	var folder_path: String = resolved_path
	var texture_dir: DirAccess = DirAccess.open(folder_path)
	if texture_dir == null:
		return ""
	texture_dir.list_dir_begin()
	var file_name: String = texture_dir.get_next()
	while file_name != "":
		if texture_dir.current_is_dir() or file_name.begins_with("."):
			file_name = texture_dir.get_next()
			continue
		var lower_name: String = file_name.to_lower()
		if lower_name.ends_with(".png") and (lower_name.contains("color") or lower_name.contains("basecolor") or lower_name.contains("base_color") or lower_name.contains("albedo")):
			texture_dir.list_dir_end()
			return "%s/%s" % [folder_path, file_name]
		file_name = texture_dir.get_next()
	texture_dir.list_dir_end()
	texture_dir = DirAccess.open(folder_path)
	if texture_dir == null:
		return ""
	texture_dir.list_dir_begin()
	file_name = texture_dir.get_next()
	while file_name != "":
		if texture_dir.current_is_dir() or file_name.begins_with("."):
			file_name = texture_dir.get_next()
			continue
		if file_name.to_lower().ends_with(".png"):
			texture_dir.list_dir_end()
			return "%s/%s" % [folder_path, file_name]
		file_name = texture_dir.get_next()
	texture_dir.list_dir_end()
	return ""

func _load_texture_preview(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

func _format_texture_display_name(texture_id: String) -> String:
	if texture_id.is_empty():
		return "Selected: none"
	var normalized_id: String = texture_id
	if normalized_id.begins_with(WORLD_TEXTURE_ROOT + "/"):
		normalized_id = normalized_id.trim_prefix(WORLD_TEXTURE_ROOT + "/")
	elif normalized_id.begins_with("res://"):
		normalized_id = normalized_id.trim_prefix("res://")

	var parts: PackedStringArray = normalized_id.split("/", false)
	if parts.is_empty():
		return _format_texture_name_part(texture_id)
	if parts.size() == 1:
		return _format_texture_name_part(parts[0])

	var category_name: String = _format_texture_name_part(parts[parts.size() - 2])
	var set_name: String = _format_texture_name_part(parts[parts.size() - 1])
	return "%s / %s" % [category_name, set_name]

func _format_texture_name_part(part: String) -> String:
	var clean_part: String = part
	var lower_part: String = clean_part.to_lower()
	if lower_part.ends_with(".png") or lower_part.ends_with(".jpg") or lower_part.ends_with(".jpeg") or lower_part.ends_with(".webp"):
		var ext_index: int = clean_part.rfind(".")
		if ext_index > 0:
			clean_part = clean_part.substr(0, ext_index)
	var normalized: String = clean_part.replace("_", " ").replace("-", " ").strip_edges()
	if normalized.is_empty():
		return part
	var words: PackedStringArray = normalized.split(" ", false)
	for i in words.size():
		var w: String = words[i]
		if w.is_empty():
			continue
		words[i] = _normalize_texture_token(w)
	return " ".join(words)

func _normalize_texture_token(token: String) -> String:
	var lower: String = token.to_lower()
	if lower.length() > 1 and lower.ends_with("k"):
		var number_part: String = lower.substr(0, lower.length() - 1)
		if number_part.is_valid_int():
			return "%sK" % number_part
	match lower:
		"png", "jpg", "jpeg", "webp", "ao", "dx", "gl", "pbr", "uv", "uvs", "lod", "id", "hdr", "hdri":
			return lower.to_upper()
		_:
			return token.substr(0, 1).to_upper() + token.substr(1)

func _on_wall_type_selected(index: int) -> void:
	if _tool_state.is_empty():
		return
	tool_setting_changed.emit("wall_type", String(["stone", "tudor"][clampi(index, 0, 1)]))

func _on_texture_shape_mode_selected(index: int) -> void:
	tool_setting_changed.emit("texture_brush_shape_mode", ["circle", "irregular", "varied"][clampi(index, 0, 2)])

func _format_tool_label(tool_name: String) -> String:
	match tool_name:
		"raise": return "Raise Terrain"
		"lower": return "Lower Terrain"
		"smooth": return "Smooth Terrain"
		"flatten": return "Flatten Height"
		"texturepaint": return "Texture Paint"
		"waterpaint": return "Water Paint"
		"snowpaint": return "Snow Paint"
		"riverdraw": return "Water Flow"
		"wall": return "Smart Wall"
		"stamp": return "Place Objects"
		"grasspaint": return "Paint Foliage"
		"select": return "Select / None"
		"boundary": return "Cliff Line"
		_: return tool_name.capitalize()
