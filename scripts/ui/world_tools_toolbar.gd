extends PanelContainer

signal tool_changed(tool_name: String)
signal setting_changed(setting_name: String, value: Variant)
signal clear_requested()

@onready var _group_terrain_btn: Button = %GroupTerrain
@onready var _group_foliage_btn: Button = %GroupFoliage
@onready var _group_structures_btn: Button = %GroupStructures
@onready var _group_paint_btn: Button = %GroupPaint
@onready var _group_horizon_btn: Button = %GroupHorizon
@onready var _popout_panel: PanelContainer = %PopoutPanel
@onready var _popout_title: Label = %PopoutTitle
@onready var _terrain_page: VBoxContainer = %TerrainPage
@onready var _foliage_page: VBoxContainer = %FoliagePage
@onready var _structures_page: VBoxContainer = %StructuresPage
@onready var _paint_page: VBoxContainer = %PaintPage
@onready var _horizon_page: VBoxContainer = %HorizonPage

@onready var _brush_size_slider: HSlider = %BrushSizeSlider
@onready var _brush_strength_slider: HSlider = %BrushStrengthSlider
@onready var _flatten_height_slider: HSlider = %FlattenHeightSlider
@onready var _grid_snap_check: CheckBox = %GridSnapCheck
@onready var _brush_size_value: Label = %BrushSizeValue
@onready var _brush_strength_value: Label = %BrushStrengthValue
@onready var _flatten_height_value: Label = %FlattenHeightValue
@onready var _cliff_mode_check: CheckBox = %CliffModeCheck
@onready var _overhang_amount_slider: HSlider = %OverhangAmountSlider
@onready var _overhang_amount_row: HBoxContainer = %OverhangAmountRow
@onready var _overhang_amount_value: Label = %OverhangAmountValue
@onready var _tool_hint: RichTextLabel = %ToolHint
@onready var _grass_density_slider: HSlider = %GrassDensitySlider
@onready var _grass_wind_slider: HSlider = %GrassWindSlider
@onready var _grass_wind_dir_slider: HSlider = %GrassWindDirSlider
@onready var _grass_height_slider: HSlider = %GrassHeightSlider
@onready var _grass_density_value: Label = %GrassDensityValue
@onready var _grass_wind_value: Label = %GrassWindValue
@onready var _grass_wind_dir_value: Label = %GrassWindDirValue
@onready var _grass_height_value: Label = %GrassHeightValue
@onready var _grass_sway_slider: HSlider = get_node_or_null("%GrassSwaySlider")
@onready var _grass_sway_value: Label = get_node_or_null("%GrassSwayValue")
@onready var _grass_base_color_button: ColorPickerButton = get_node_or_null("%GrassBaseColorButton")
@onready var _grass_tip_color_button: ColorPickerButton = get_node_or_null("%GrassTipColorButton")
@onready var _grass_stroke_color_button: ColorPickerButton = get_node_or_null("%GrassStrokeColorButton")
@onready var _grass_stroke_color_row: HBoxContainer = get_node_or_null("%GrassStrokeColorRow")
@onready var _grass_presets_row: HBoxContainer = get_node_or_null("%GrassPresetsRow")
@onready var _spring_green_preset: Button = get_node_or_null("%SpringGreenPreset")
@onready var _mossy_preset: Button = get_node_or_null("%MossyPreset")
@onready var _dead_grass_preset: Button = get_node_or_null("%DeadGrassPreset")
@onready var _pale_grass_preset: Button = get_node_or_null("%PaleGrassPreset")
@onready var _forest_green_preset: Button = get_node_or_null("%ForestGreenPreset")
@onready var _grass_noise_slider: HSlider = get_node_or_null("%GrassNoiseSlider")
@onready var _grass_noise_value: Label = get_node_or_null("%GrassNoiseValue")
@onready var _grass_sway_row: HBoxContainer = get_node_or_null("%GrassSwayRow")
@onready var _grass_color_row: HBoxContainer = get_node_or_null("%GrassColorRow")
@onready var _grass_noise_row: HBoxContainer = get_node_or_null("%GrassNoiseRow")
@onready var _scatter_density_slider: HSlider = %ScatterDensitySlider
@onready var _scatter_density_value: Label = %ScatterDensityValue
@onready var _scatter_scale_min_slider: HSlider = %ScatterScaleMinSlider
@onready var _scatter_scale_max_slider: HSlider = %ScatterScaleMaxSlider
@onready var _scatter_scale_min_value: Label = %ScatterScaleMinValue
@onready var _scatter_scale_max_value: Label = %ScatterScaleMaxValue
@onready var _scatter_rotation_slider: HSlider = %ScatterRotationSlider
@onready var _scatter_rotation_value: Label = %ScatterRotationValue
@onready var _scatter_tilt_slider: HSlider = %ScatterTiltSlider
@onready var _scatter_tilt_value: Label = %ScatterTiltValue
@onready var _tool_mode_label: Label = %ToolModeLabel
@onready var _clear_tool_button: Button = %ClearToolButton
@onready var _wall_height_slider: HSlider = %WallHeightSlider
@onready var _wall_height_value: Label = %WallHeightValue
@onready var _wall_type_option: OptionButton = %WallTypeOption
@onready var _wall_rect_mode_check: CheckBox = %WallRectModeCheck
@onready var _wall_match_heights_check: CheckBox = %WallMatchHeightsCheck
@onready var _wall_foundation_check: CheckBox = %WallFoundationCheck
@onready var _wall_opening_height_snap_check: CheckBox = %WallOpeningHeightSnapCheck
@onready var _wall_jitter_check: CheckBox = %WallJitterCheck
@onready var _river_settings_label: Label = get_node_or_null("%RiverSettingsLabel")
@onready var _river_width_row: HBoxContainer = get_node_or_null("%RiverWidthRow")
@onready var _river_width_slider: HSlider = get_node_or_null("%RiverWidthSlider")
@onready var _river_width_value: Label = get_node_or_null("%RiverWidthValue")
@onready var _river_flow_row: HBoxContainer = get_node_or_null("%RiverFlowRow")
@onready var _river_flow_slider: HSlider = get_node_or_null("%RiverFlowSlider")
@onready var _river_flow_value: Label = get_node_or_null("%RiverFlowValue")
@onready var _river_depth_row: HBoxContainer = get_node_or_null("%RiverDepthRow")
@onready var _river_depth_slider: HSlider = get_node_or_null("%RiverDepthSlider")
@onready var _river_depth_value: Label = get_node_or_null("%RiverDepthValue")
@onready var _river_color_row: HBoxContainer = get_node_or_null("%RiverColorRow")
@onready var _river_color_button: ColorPickerButton = get_node_or_null("%RiverColorButton")
@onready var _water_mode_row: HBoxContainer = get_node_or_null("%WaterModeRow")
@onready var _water_mode_option: OptionButton = get_node_or_null("%WaterModeOption")

@onready var _brush_label: Label = %BrushLabel
@onready var _brush_size_row: HBoxContainer = %BrushSizeRow
@onready var _brush_strength_row: HBoxContainer = %BrushStrengthRow
@onready var _flatten_height_row: HBoxContainer = %FlattenHeightRow
@onready var _separator2: HSeparator = %Separator2
@onready var _grass_settings_label: Label = %GrassSettingsLabel
@onready var _grass_density_row: HBoxContainer = %GrassDensityRow
@onready var _grass_wind_row: HBoxContainer = %GrassWindRow
@onready var _grass_wind_dir_row: HBoxContainer = %GrassWindDirRow
@onready var _grass_height_row: HBoxContainer = %GrassHeightRow
@onready var _scatter_settings_label: Label = %ScatterSettingsLabel
@onready var _scatter_density_row: HBoxContainer = %ScatterDensityRow
@onready var _scatter_scale_min_row: HBoxContainer = %ScatterScaleMinRow
@onready var _scatter_scale_max_row: HBoxContainer = %ScatterScaleMaxRow
@onready var _scatter_rotation_row: HBoxContainer = %ScatterRotationRow
@onready var _scatter_tilt_row: HBoxContainer = %ScatterTiltRow
@onready var _separator3: HSeparator = %Separator3
@onready var _texture_paint_panel: VBoxContainer = %TexturePaintPanel
@onready var _texture_grid: GridContainer = %TextureGrid
@onready var _selected_texture_name_label: Label = %SelectedTextureName
@onready var _selected_texture_preview: TextureRect = %SelectedTexturePreview
@onready var _texture_tile_size_row: HBoxContainer = %TextureTileSizeRow
@onready var _texture_tile_size_slider: HSlider = %TextureTileSizeSlider
@onready var _texture_tile_size_value: Label = %TextureTileSizeValue
@onready var _texture_density_row: HBoxContainer = %TextureDensityRow
@onready var _texture_density_slider: HSlider = %TextureDensitySlider
@onready var _texture_density_value: Label = %TextureDensityValue
@onready var _texture_perf_mode_check: CheckBox = %TexturePerfModeCheck
@onready var _texture_shape_mode_row: HBoxContainer = %TextureShapeModeRow
@onready var _texture_shape_mode_option: OptionButton = %TextureShapeModeOption
@onready var _texture_shape_variation_row: HBoxContainer = %TextureShapeVariationRow
@onready var _texture_shape_variation_slider: HSlider = %TextureShapeVariationSlider
@onready var _texture_shape_variation_value: Label = %TextureShapeVariationValue
@onready var _texture_edge_softness_row: HBoxContainer = %TextureEdgeSoftnessRow
@onready var _texture_edge_softness_slider: HSlider = %TextureEdgeSoftnessSlider
@onready var _texture_edge_softness_value: Label = %TextureEdgeSoftnessValue
@onready var _texture_coverage_row: HBoxContainer = %TextureCoverageRow
@onready var _texture_coverage_slider: HSlider = %TextureCoverageSlider
@onready var _texture_coverage_value: Label = %TextureCoverageValue
@onready var _texture_rotation_row: HBoxContainer = %TextureRotationRow
@onready var _texture_rotation_slider: HSlider = %TextureRotationSlider
@onready var _texture_rotation_value: Label = %TextureRotationValue
@onready var _texture_scale_variation_row: HBoxContainer = %TextureScaleVariationRow
@onready var _texture_scale_variation_slider: HSlider = %TextureScaleVariationSlider
@onready var _texture_scale_variation_value: Label = %TextureScaleVariationValue
@onready var _texture_exposure_row: HBoxContainer = %TextureExposureRow
@onready var _texture_exposure_slider: HSlider = %TextureExposureSlider
@onready var _texture_exposure_value: Label = %TextureExposureValue
@onready var _wall_height_row: HBoxContainer = %WallHeightRow
@onready var _wall_type_row: HBoxContainer = %WallTypeRow

var current_tool: String = "select"
var _tool_buttons: Dictionary = {}
var _button_group: ButtonGroup = ButtonGroup.new()
var _group_buttons: Dictionary = {}
var _active_group: String = "terrain"
var _current_selected_texture: String = ""
var _is_collapsed: bool = false
var _texture_preview_painter: RefCounted = null

func _ready() -> void:
	_group_buttons = {
		"terrain": _group_terrain_btn,
		"foliage": _group_foliage_btn,
		"structures": _group_structures_btn,
		"paint": _group_paint_btn,
		"horizon": _group_horizon_btn,
	}

	for b in get_tree().get_nodes_in_group("tool_button"):
		if b is Button:
			var btn: Button = b as Button
			btn.button_group = _button_group
			btn.toggle_mode = true
			var tool_key: String = String(btn.name).to_lower()
			_tool_buttons[tool_key] = btn
			btn.pressed.connect(_on_tool_button_pressed.bind(tool_key))

	_group_terrain_btn.pressed.connect(func() -> void: _open_group("terrain", true))
	_group_foliage_btn.pressed.connect(func() -> void: _open_group("foliage", true))
	_group_structures_btn.pressed.connect(func() -> void: _open_group("structures", true))
	_group_paint_btn.pressed.connect(func() -> void: _open_group("paint", true))
	_group_horizon_btn.pressed.connect(func() -> void: _open_group("horizon", true))
	_group_terrain_btn.gui_input.connect(_on_group_icon_gui_input.bind("terrain"))
	_group_foliage_btn.gui_input.connect(_on_group_icon_gui_input.bind("foliage"))
	_group_structures_btn.gui_input.connect(_on_group_icon_gui_input.bind("structures"))
	_group_paint_btn.gui_input.connect(_on_group_icon_gui_input.bind("paint"))
	_group_horizon_btn.gui_input.connect(_on_group_icon_gui_input.bind("horizon"))

	_brush_size_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("brush_size", v))
	_brush_strength_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("brush_strength", v))
	_flatten_height_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("flatten_height", v))
	_grid_snap_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("grid_snap", v))
	_cliff_mode_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("cliff_mode", v))
	_overhang_amount_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("overhang_amount", v))
	_grass_density_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_density", v))
	_grass_wind_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_wind", v))
	_grass_wind_dir_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_wind_dir", v))
	_grass_height_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_height", v))
	
	# New grass enhancement controls - optional (may not exist in scene)
	if _grass_sway_slider != null:
		_grass_sway_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_sway", v))
	if _grass_base_color_button != null:
		_grass_base_color_button.color_changed.connect(func(c: Color) -> void: setting_changed.emit("grass_base_color", c))
	if _grass_tip_color_button != null:
		_grass_tip_color_button.color_changed.connect(func(c: Color) -> void: setting_changed.emit("grass_tip_color", c))
	if _grass_stroke_color_button != null:
		_grass_stroke_color_button.color_changed.connect(func(c: Color) -> void: setting_changed.emit("grass_stroke_color", c))
	if _grass_noise_slider != null:
		_grass_noise_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_noise_strength", v))
	
	# Grass color preset buttons
	if _spring_green_preset != null:
		_spring_green_preset.pressed.connect(func() -> void: _set_stroke_color(Color(0.2, 0.5, 0.1, 1)))
	if _mossy_preset != null:
		_mossy_preset.pressed.connect(func() -> void: _set_stroke_color(Color(0.1, 0.3, 0.08, 1)))
	if _dead_grass_preset != null:
		_dead_grass_preset.pressed.connect(func() -> void: _set_stroke_color(Color(0.35, 0.3, 0.1, 1)))
	if _pale_grass_preset != null:
		_pale_grass_preset.pressed.connect(func() -> void: _set_stroke_color(Color(0.4, 0.5, 0.2, 1)))
	if _forest_green_preset != null:
		_forest_green_preset.pressed.connect(func() -> void: _set_stroke_color(Color(0.15, 0.25, 0.1, 1)))
	
	_scatter_density_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("scatter_density", v))
	_scatter_scale_min_slider.value_changed.connect(func(v: float) -> void:
		if v > _scatter_scale_max_slider.value:
			_scatter_scale_max_slider.value = v
		setting_changed.emit("scatter_scale_min", v)
	)
	_scatter_scale_max_slider.value_changed.connect(func(v: float) -> void:
		if v < _scatter_scale_min_slider.value:
			_scatter_scale_min_slider.value = v
		setting_changed.emit("scatter_scale_max", v)
	)
	_scatter_rotation_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("scatter_rotation_randomness", v))
	_scatter_tilt_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("scatter_tilt", v))
	_wall_height_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("wall_height", v))
	_wall_rect_mode_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("wall_rect_mode", v))
	_wall_match_heights_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("wall_match_connected_heights", v))
	_wall_foundation_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("wall_add_foundation", v))
	_wall_opening_height_snap_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("wall_opening_height_snap", v))
	_wall_jitter_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("wall_jitter", v))
	if _river_width_slider != null:
		_river_width_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("river_width", v))
	if _river_flow_slider != null:
		_river_flow_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("river_flow_speed", v))
	if _river_depth_slider != null:
		_river_depth_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("river_average_depth", v))
	if _river_color_button != null:
		_river_color_button.color_changed.connect(func(c: Color) -> void: setting_changed.emit("water_color", c))
	if _water_mode_option != null:
		_water_mode_option.clear()
		_water_mode_option.add_item("River")
		_water_mode_option.set_item_metadata(0, "river")
		_water_mode_option.add_item("Lake / Pond")
		_water_mode_option.set_item_metadata(1, "lake")
		_water_mode_option.add_item("Fill")
		_water_mode_option.set_item_metadata(2, "fill")
		_water_mode_option.select(0)
		_water_mode_option.item_selected.connect(func(index: int) -> void:
			var mode_value: String = "river"
			var md: Variant = _water_mode_option.get_item_metadata(index)
			if md is String and String(md) != "":
				mode_value = String(md)
			setting_changed.emit("water_mode", mode_value)
		)
	_wall_type_option.item_selected.connect(_on_wall_type_selected)

	_wall_type_option.clear()
	_wall_type_option.add_item("Ink Stone")
	_wall_type_option.set_item_metadata(0, "stone")
	_wall_type_option.add_item("Tudor Timber")
	_wall_type_option.set_item_metadata(1, "tudor")
	_wall_type_option.select(0)

	_texture_shape_mode_option.clear()
	_texture_shape_mode_option.add_item("Circle")
	_texture_shape_mode_option.set_item_metadata(0, "circle")
	_texture_shape_mode_option.add_item("Irregular")
	_texture_shape_mode_option.set_item_metadata(1, "irregular")
	_texture_shape_mode_option.add_item("Varied")
	_texture_shape_mode_option.set_item_metadata(2, "varied")
	_texture_shape_mode_option.select(0)

	_texture_tile_size_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("texture_tile_size", v))
	_texture_density_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("texture_density", v))
	_texture_perf_mode_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("texture_perf_mode", v))
	_texture_shape_mode_option.item_selected.connect(_on_texture_shape_mode_selected)
	_texture_shape_variation_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("texture_shape_variation", v))
	_texture_edge_softness_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("texture_edge_softness", v))
	_texture_coverage_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("texture_coverage_limit", v))
	_texture_rotation_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("texture_random_rotation", v))
	_texture_scale_variation_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("texture_scale_variation", v))
	_texture_exposure_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("texture_exposure", v))
	_texture_tile_size_slider.value_changed.connect(_update_value_labels)
	_texture_density_slider.value_changed.connect(_update_value_labels)
	_texture_shape_variation_slider.value_changed.connect(_update_value_labels)
	_texture_edge_softness_slider.value_changed.connect(_update_value_labels)
	_texture_coverage_slider.value_changed.connect(_update_value_labels)
	_texture_rotation_slider.value_changed.connect(_update_value_labels)
	_texture_scale_variation_slider.value_changed.connect(_update_value_labels)
	_texture_exposure_slider.value_changed.connect(_update_value_labels)

	_brush_size_slider.value_changed.connect(_update_value_labels)
	_brush_strength_slider.value_changed.connect(_update_value_labels)
	_flatten_height_slider.value_changed.connect(_update_value_labels)
	_grass_density_slider.value_changed.connect(_update_value_labels)
	_grass_wind_slider.value_changed.connect(_update_value_labels)
	_grass_wind_dir_slider.value_changed.connect(_update_value_labels)
	_grass_height_slider.value_changed.connect(_update_value_labels)
	if _grass_sway_slider != null:
		_grass_sway_slider.value_changed.connect(_update_value_labels)
	if _grass_noise_slider != null:
		_grass_noise_slider.value_changed.connect(_update_value_labels)
	_scatter_density_slider.value_changed.connect(_update_value_labels)
	_scatter_scale_min_slider.value_changed.connect(_update_value_labels)
	_scatter_scale_max_slider.value_changed.connect(_update_value_labels)
	_scatter_rotation_slider.value_changed.connect(_update_value_labels)
	_scatter_tilt_slider.value_changed.connect(_update_value_labels)
	_overhang_amount_slider.value_changed.connect(_update_value_labels)
	_wall_height_slider.value_changed.connect(_update_value_labels)
	if _river_width_slider != null:
		_river_width_slider.value_changed.connect(_update_value_labels)
	if _river_flow_slider != null:
		_river_flow_slider.value_changed.connect(_update_value_labels)
	_clear_tool_button.pressed.connect(func() -> void: clear_requested.emit())

	_cliff_mode_check.toggled.connect(func(v: bool) -> void:
		_overhang_amount_row.visible = v and current_tool == "raise"
		_overhang_amount_slider.visible = v and current_tool == "raise"
	)

	_update_value_labels(0.0)
	_open_group("terrain", false)
	if _tool_buttons.has("select"):
		(_tool_buttons["select"] as Button).button_pressed = true
	_selected_texture_name_label.text = "Selected: none"
	_selected_texture_preview.texture = null
	current_tool = "select"
	_update_tool_hint(current_tool)
	_update_mode_badge(current_tool)
	_update_tool_visibility(current_tool)

func select_tool() -> void:
	set_tool_from_action("tool_select")

func _on_tool_button_pressed(button_name: String) -> void:
	_apply_tool(button_name, true)

func set_tool_from_action(action: String) -> void:
	var action_tool: String = action.replace("tool_", "")
	_apply_tool(action_tool, true)

func get_current_tool() -> String:
	return current_tool

func set_grid_snap_enabled(enabled: bool) -> void:
	_grid_snap_check.button_pressed = enabled

func _open_group(group_name: String, animate: bool) -> void:
	if _is_collapsed:
		_set_collapsed(false, animate)

	_active_group = group_name
	for key in _group_buttons.keys():
		var gbtn: Button = _group_buttons[key]
		gbtn.button_pressed = (key == group_name)

	_terrain_page.visible = group_name == "terrain"
	_foliage_page.visible = group_name == "foliage"
	_structures_page.visible = group_name == "structures"
	_paint_page.visible = group_name == "paint"
	_horizon_page.visible = group_name == "horizon"

	_popout_title.text = _format_tool_name(group_name)
	_animate_popout(animate)
	_update_tool_visibility(current_tool)

func _on_group_icon_gui_input(event: InputEvent, group_name: String) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			_set_collapsed(not _is_collapsed, true)
			accept_event()
			return

	# Keep single-click behavior unchanged when collapsed.
	if _is_collapsed and event is InputEventMouseButton:
		var click_event: InputEventMouseButton = event as InputEventMouseButton
		if click_event.button_index == MOUSE_BUTTON_LEFT and click_event.pressed and not click_event.double_click:
			_open_group(group_name, true)

func _set_collapsed(collapsed: bool, animate: bool) -> void:
	_is_collapsed = collapsed
	if collapsed:
		if animate:
			var hide_tween: Tween = create_tween()
			hide_tween.set_trans(Tween.TRANS_QUAD)
			hide_tween.set_ease(Tween.EASE_IN_OUT)
			hide_tween.tween_property(_popout_panel, "modulate:a", 0.0, 0.12)
			hide_tween.finished.connect(func() -> void:
				_popout_panel.visible = false
			)
		else:
			_popout_panel.visible = false
			_popout_panel.modulate.a = 0.0
		custom_minimum_size.x = 72
	else:
		_popout_panel.visible = true
		if animate:
			_animate_popout(true)
		else:
			_popout_panel.modulate.a = 1.0
			_popout_panel.custom_minimum_size.x = 328
		custom_minimum_size.x = 72

func _animate_popout(animate: bool) -> void:
	if not animate:
		_popout_panel.modulate.a = 1.0
		_popout_panel.custom_minimum_size.x = 328
		return

	_popout_panel.custom_minimum_size.x = 300
	_popout_panel.modulate.a = 0.55
	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_popout_panel, "custom_minimum_size:x", 328, 0.18)
	tween.parallel().tween_property(_popout_panel, "modulate:a", 1.0, 0.16)

func _update_value_labels(_value: float) -> void:
	_brush_size_value.text = "%.1f" % _brush_size_slider.value
	_brush_strength_value.text = "%.2f" % _brush_strength_slider.value
	_flatten_height_value.text = "%.2f" % _flatten_height_slider.value
	_grass_density_value.text = "%.2f" % _grass_density_slider.value
	_grass_wind_value.text = "%.2f" % _grass_wind_slider.value
	_grass_wind_dir_value.text = "%d deg" % int(round(_grass_wind_dir_slider.value))
	_grass_height_value.text = "%.2f" % _grass_height_slider.value
	if _grass_sway_value != null and _grass_sway_slider != null:
		_grass_sway_value.text = "%.2f" % _grass_sway_slider.value
	if _grass_noise_value != null and _grass_noise_slider != null:
		_grass_noise_value.text = "%.2f" % _grass_noise_slider.value
	_scatter_density_value.text = "%.2f" % _scatter_density_slider.value
	_scatter_scale_min_value.text = "%.2f" % _scatter_scale_min_slider.value
	_scatter_scale_max_value.text = "%.2f" % _scatter_scale_max_slider.value
	_scatter_rotation_value.text = "%d deg" % int(round(_scatter_rotation_slider.value))
	_scatter_tilt_value.text = "%d deg" % int(round(_scatter_tilt_slider.value))
	_texture_tile_size_value.text = "%.1f" % _texture_tile_size_slider.value
	_texture_density_value.text = "%.2f" % _texture_density_slider.value
	_texture_shape_variation_value.text = "%d%%" % int(round(_texture_shape_variation_slider.value * 100.0))
	_texture_edge_softness_value.text = "%.2f" % _texture_edge_softness_slider.value
	_texture_coverage_value.text = "%.2f" % _texture_coverage_slider.value
	_texture_rotation_value.text = "%d deg" % int(round(_texture_rotation_slider.value))
	_texture_scale_variation_value.text = "%.2f" % _texture_scale_variation_slider.value
	_texture_exposure_value.text = "%.2f" % _texture_exposure_slider.value
	_overhang_amount_value.text = "%.2f" % _overhang_amount_slider.value
	_wall_height_value.text = "%.1f" % _wall_height_slider.value
	if _river_width_value != null and _river_width_slider != null:
		_river_width_value.text = "%.1f" % _river_width_slider.value
	if _river_flow_value != null and _river_flow_slider != null:
		_river_flow_value.text = "%.2f" % _river_flow_slider.value
	if _river_depth_value != null and _river_depth_slider != null:
		_river_depth_value.text = "%.1f" % _river_depth_slider.value

func _update_tool_hint(tool_name: String) -> void:
	match tool_name:
		"select":
			_tool_hint.text = "[b]Select Mode[/b]  [i]0 / Esc[/i]\nLMB: click character to control\nRMB on terrain: deselect\nNo terrain editing active"
		"stamp":
			_tool_hint.text = "[b]Stamp Mode[/b]  [i]6[/i]\nLMB: place  •  RMB/Q/E: rotate 45 deg\nGrid snap keeps pieces aligned\nEsc: back to Select"
		"raise":
			_tool_hint.text = "[b]Raise Terrain[/b]  [i]1[/i]\nHold LMB and drag\nRadius / Strength tune the brush\nEsc: back to Select"
		"lower":
			_tool_hint.text = "[b]Lower Terrain[/b]  [i]2[/i]\nHold LMB and drag\nEsc: back to Select"
		"smooth":
			_tool_hint.text = "[b]Smooth Terrain[/b]  [i]3[/i]\nHold LMB and drag\nEsc: back to Select"
		"flatten":
			_tool_hint.text = "[b]Flatten Terrain[/b]  [i]4[/i]\nHold LMB and drag\nFlatten Y sets the target height\nEsc: back to Select"
		"paint":
			_tool_hint.text = "[b]Paint Terrain[/b]  [i]5[/i]\nHold LMB and drag\nLower strength for smooth blends\nEsc: back to Select"
		"grasspaint":
			_tool_hint.text = "[b]Paint Grass[/b]  [i]7[/i]\nHold LMB to paint thick swathes\nRadius = area, Strength = fill speed\nEsc: back to Select"
		"grasserase":
			_tool_hint.text = "[b]Erase Grass[/b]  [i]8[/i]\nHold LMB to remove grass\nEsc: back to Select"
		"scatterpaint":
			_tool_hint.text = "[b]Scatter Paint[/b]\nHold LMB to spray selected scatter asset\nUses Radius + Strength and scatter settings\nEsc: back to Select"
		"scattererase":
			_tool_hint.text = "[b]Scatter Erase[/b]\nHold LMB to erase scattered instances\nRadius controls erase area\nEsc: back to Select"
		"texturepaint":
			_tool_hint.text = "[b]Paint Texture[/b]\nHold LMB to airbrush texture onto terrain\nDensity + Edge Softness shape blend and fade\nEsc: back to Select"
		"textureerase":
			_tool_hint.text = "[b]Erase Texture[/b]\nHold LMB to restore terrain to base grass\nRadius / Strength control the erase effect\nEsc: back to Select"
		"horizonmountain":
			_tool_hint.text = "[b]Place Distant Mountain[/b]\nLMB: click to aim direction - mountain placed 3000m away\nMountains are visible from anywhere in the world\nEsc: back to Select"
		"wall":
			_tool_hint.text = "[b]Smart Wall[/b]  [i]9[/i]\nLMB: click A then click B/C for chain walls\nCtrl-drag: rectangle • Shift in drag: perfect square\nRMB or Esc: end chain • Match Connected Heights keeps structures uniform\nRMB menu: Add Window • Ctrl-drag window height, Alt-drag width\nSnap to Standard Heights keeps openings tidy"
		"riverdraw":
			_tool_hint.text = "[b]Water Tool[/b]\n[1] River path  [2] Lake/Pond  [3] Fill\nLMB: place/edit water body\nRMB / Esc: finish active river path"
		_:
			_tool_hint.text = "[b]World Tool[/b]\nSwitch tools from this sidebar or top menu\n[i]Esc: back to Select[/i]"

func _apply_tool(tool_name: String, emit_tool_signal: bool) -> void:
	if tool_name == "scatterpaint" or tool_name == "scattererase":
		tool_name = "select"

	current_tool = tool_name
	if _tool_buttons.has(tool_name):
		(_tool_buttons[tool_name] as Button).button_pressed = true

	_open_group(_group_for_tool(tool_name), true)
	_update_tool_hint(tool_name)
	_update_mode_badge(tool_name)
	_update_tool_visibility(tool_name)

	if emit_tool_signal:
		tool_changed.emit(current_tool)

func _group_for_tool(tool_name: String) -> String:
	match tool_name:
		"raise", "lower", "smooth", "flatten", "paint", "select":
			return "terrain"
		"grasspaint", "grasserase":
			return "foliage"
		"wall", "stamp", "riverdraw":
			return "structures"
		"texturepaint", "textureerase":
			return "paint"
		"horizonmountain":
			return "horizon"
		_:
			return "terrain"

func _update_mode_badge(tool_name: String) -> void:
	if _tool_mode_label == null:
		return
	_tool_mode_label.text = "MODE\n%s" % _format_tool_name(tool_name)
	if tool_name == "select":
		_tool_mode_label.modulate = Color(0.86, 0.9, 0.94, 1.0)
		_clear_tool_button.disabled = true
	else:
		_tool_mode_label.modulate = Color(0.45, 0.9, 1.0, 1.0)
		_clear_tool_button.disabled = false

func _update_tool_visibility(tool_name: String) -> void:
	var is_horizon: bool = tool_name == "horizonmountain"
	var is_wall: bool = tool_name == "wall"
	var is_river: bool = tool_name == "riverdraw"
	var is_grass: bool = (tool_name == "grasspaint" or tool_name == "grasserase")
	var is_scatter: bool = (tool_name == "scatterpaint" or tool_name == "scattererase")
	var is_texture: bool = (tool_name == "texturepaint" or tool_name == "textureerase")
	var has_brush: bool = not is_wall and not is_horizon and not is_river

	_brush_label.visible = has_brush
	_brush_size_row.visible = has_brush
	_brush_size_slider.visible = has_brush
	_brush_strength_row.visible = has_brush
	_brush_strength_slider.visible = has_brush
	_flatten_height_row.visible = (tool_name == "flatten")
	_flatten_height_slider.visible = (tool_name == "flatten")
	_cliff_mode_check.visible = (tool_name == "raise")
	_overhang_amount_row.visible = (tool_name == "raise" and _cliff_mode_check.button_pressed)
	_overhang_amount_slider.visible = (tool_name == "raise" and _cliff_mode_check.button_pressed)
	_separator2.visible = has_brush

	_grass_settings_label.visible = is_grass
	_grass_density_row.visible = is_grass
	_grass_density_slider.visible = is_grass
	_grass_wind_row.visible = is_grass
	_grass_wind_slider.visible = is_grass
	_grass_wind_dir_row.visible = is_grass
	_grass_wind_dir_slider.visible = is_grass
	_grass_height_row.visible = is_grass
	_grass_height_slider.visible = is_grass
	
	# New grass enhancement controls visibility
	if _grass_sway_row != null:
		_grass_sway_row.visible = is_grass
	if _grass_sway_slider != null:
		_grass_sway_slider.visible = is_grass
	if _grass_color_row != null:
		_grass_color_row.visible = is_grass
	if _grass_base_color_button != null:
		_grass_base_color_button.visible = is_grass
	if _grass_tip_color_button != null:
		_grass_tip_color_button.visible = is_grass
	if _grass_stroke_color_row != null:
		_grass_stroke_color_row.visible = is_grass
	if _grass_stroke_color_button != null:
		_grass_stroke_color_button.visible = is_grass
	if _grass_presets_row != null:
		_grass_presets_row.visible = is_grass
	if _spring_green_preset != null:
		_spring_green_preset.visible = is_grass
	if _mossy_preset != null:
		_mossy_preset.visible = is_grass
	if _dead_grass_preset != null:
		_dead_grass_preset.visible = is_grass
	if _pale_grass_preset != null:
		_pale_grass_preset.visible = is_grass
	if _forest_green_preset != null:
		_forest_green_preset.visible = is_grass
	if _grass_noise_row != null:
		_grass_noise_row.visible = is_grass
	if _grass_noise_slider != null:
		_grass_noise_slider.visible = is_grass

	_scatter_settings_label.visible = is_scatter
	_scatter_density_row.visible = is_scatter
	_scatter_density_slider.visible = is_scatter
	_scatter_scale_min_row.visible = is_scatter
	_scatter_scale_min_slider.visible = is_scatter
	_scatter_scale_max_row.visible = is_scatter
	_scatter_scale_max_slider.visible = is_scatter
	_scatter_rotation_row.visible = is_scatter
	_scatter_rotation_slider.visible = is_scatter
	_scatter_tilt_row.visible = is_scatter
	_scatter_tilt_slider.visible = is_scatter

	_separator3.visible = has_brush
	_texture_paint_panel.visible = (is_texture or _active_group == "paint")
	var is_texture_paint_tool: bool = (tool_name == "texturepaint")
	_texture_tile_size_row.visible = is_texture_paint_tool
	_texture_tile_size_slider.visible = is_texture_paint_tool
	_texture_density_row.visible = is_texture_paint_tool
	_texture_density_slider.visible = is_texture_paint_tool
	_texture_perf_mode_check.visible = is_texture_paint_tool
	_texture_shape_mode_row.visible = is_texture_paint_tool
	_texture_shape_mode_option.visible = is_texture_paint_tool
	_texture_shape_variation_row.visible = is_texture_paint_tool
	_texture_shape_variation_slider.visible = is_texture_paint_tool
	_texture_edge_softness_row.visible = is_texture_paint_tool
	_texture_edge_softness_slider.visible = is_texture_paint_tool
	_texture_coverage_row.visible = is_texture_paint_tool
	_texture_coverage_slider.visible = is_texture_paint_tool
	_texture_rotation_row.visible = is_texture_paint_tool
	_texture_rotation_slider.visible = is_texture_paint_tool
	_texture_scale_variation_row.visible = is_texture_paint_tool
	_texture_scale_variation_slider.visible = is_texture_paint_tool
	_texture_exposure_row.visible = is_texture_paint_tool
	_texture_exposure_slider.visible = is_texture_paint_tool

	_wall_height_row.visible = is_wall
	_wall_height_slider.visible = is_wall
	_wall_type_row.visible = is_wall
	_wall_rect_mode_check.visible = is_wall
	_wall_match_heights_check.visible = is_wall
	_wall_foundation_check.visible = is_wall
	_wall_opening_height_snap_check.visible = is_wall
	_wall_jitter_check.visible = is_wall
	if _river_settings_label != null:
		_river_settings_label.visible = is_river
	if _river_width_row != null:
		_river_width_row.visible = is_river
	if _river_width_slider != null:
		_river_width_slider.visible = is_river
	if _river_flow_row != null:
		_river_flow_row.visible = is_river
	if _river_flow_slider != null:
		_river_flow_slider.visible = is_river
	if _river_depth_row != null:
		_river_depth_row.visible = is_river
	if _river_depth_slider != null:
		_river_depth_slider.visible = is_river
	if _river_color_row != null:
		_river_color_row.visible = is_river
	if _water_mode_row != null:
		_water_mode_row.visible = is_river
	if _water_mode_option != null:
		_water_mode_option.visible = is_river

func _format_tool_name(tool_name: String) -> String:
	match tool_name:
		"grasspaint":
			return "Grass Paint"
		"grasserase":
			return "Grass Erase"
		"scatterpaint":
			return "Scatter Paint"
		"scattererase":
			return "Scatter Erase"
		"texturepaint":
			return "Texture Paint"
		"textureerase":
			return "Texture Erase"
		"horizonmountain":
			return "Distant Mountain"
		"riverdraw":
			return "Water Tool"
		"select":
			return "Select"
		"wall":
			return "Smart Wall"
		"terrain":
			return "Terrain"
		"foliage":
			return "Foliage"
		"structures":
			return "Structures"
		"paint":
			return "Paint"
		"horizon":
			return "Horizon"
		_:
			return tool_name.capitalize()

func get_settings() -> Dictionary:
	var wall_type: String = "stone"
	if _wall_type_option != null and _wall_type_option.item_count > 0:
		var md: Variant = _wall_type_option.get_item_metadata(_wall_type_option.selected)
		if md is String and String(md) != "":
			wall_type = String(md)
	return {
		"brush_size": _brush_size_slider.value,
		"brush_strength": _brush_strength_slider.value,
		"flatten_height": _flatten_height_slider.value,
		"grid_snap": _grid_snap_check.button_pressed,
		"cliff_mode": _cliff_mode_check.button_pressed,
		"overhang_amount": _overhang_amount_slider.value,
		"grass_density": _grass_density_slider.value,
		"grass_wind": _grass_wind_slider.value,
		"grass_wind_dir": _grass_wind_dir_slider.value,
		"grass_height": _grass_height_slider.value,
		"grass_sway": _grass_sway_slider.value if _grass_sway_slider != null else 0.3,
		"grass_base_color": _grass_base_color_button.color if _grass_base_color_button != null else Color(0.12, 0.22, 0.10, 1.0),
		"grass_tip_color": _grass_tip_color_button.color if _grass_tip_color_button != null else Color(0.40, 0.49, 0.28, 1.0),
		"grass_noise_strength": _grass_noise_slider.value if _grass_noise_slider != null else 0.15,
		"scatter_density": _scatter_density_slider.value,
		"scatter_scale_min": _scatter_scale_min_slider.value,
		"scatter_scale_max": _scatter_scale_max_slider.value,
		"scatter_rotation_randomness": _scatter_rotation_slider.value,
		"scatter_tilt": _scatter_tilt_slider.value,
		"texture_tile_size": _texture_tile_size_slider.value,
		"texture_density": _texture_density_slider.value,
		"texture_perf_mode": _texture_perf_mode_check.button_pressed,
		"texture_brush_shape_mode": _get_texture_shape_mode_value(),
		"texture_shape_variation": _texture_shape_variation_slider.value,
		"texture_edge_softness": _texture_edge_softness_slider.value,
		"texture_coverage_limit": _texture_coverage_slider.value,
		"texture_random_rotation": _texture_rotation_slider.value,
		"texture_scale_variation": _texture_scale_variation_slider.value,
		"texture_exposure": _texture_exposure_slider.value,
		"wall_height": _wall_height_slider.value,
		"wall_type": wall_type,
		"wall_rect_mode": _wall_rect_mode_check.button_pressed,
		"wall_match_connected_heights": _wall_match_heights_check.button_pressed,
		"wall_add_foundation": _wall_foundation_check.button_pressed,
		"wall_opening_height_snap": _wall_opening_height_snap_check.button_pressed,
		"wall_jitter": _wall_jitter_check.button_pressed,
		"river_width": _river_width_slider.value if _river_width_slider != null else 2.0,
		"river_flow_speed": _river_flow_slider.value if _river_flow_slider != null else 1.0,
		"river_average_depth": _river_depth_slider.value if _river_depth_slider != null else 15.0,
		"water_color": _river_color_button.color if _river_color_button != null else Color(0.2, 0.5, 0.3, 1.0),
		"water_mode": _get_water_mode_value()
	}

func populate_texture_buttons(painter: RefCounted) -> void:
	_texture_preview_painter = painter
	for child in _texture_grid.get_children():
		child.queue_free()

	if painter == null or not painter.has_method("get_textures"):
		var no_tex_label := Label.new()
		no_tex_label.text = "No textures"
		_texture_grid.add_child(no_tex_label)
		return

	var textures: Array = painter.call("get_textures")
	if textures.is_empty():
		var no_tex_label := Label.new()
		no_tex_label.text = "No textures found"
		_texture_grid.add_child(no_tex_label)
		return

	for tex_info in textures:
		if tex_info == null:
			continue

		var tex_id: String = tex_info["id"] if "id" in tex_info else ""
		var tex_name: String = tex_info["display_name"] if "display_name" in tex_info else ""
		if tex_id.is_empty():
			continue

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 64)
		btn.toggle_mode = true
		btn.tooltip_text = tex_name
		btn.add_theme_font_size_override("font_size", 8)
		btn.text = tex_name.substr(0, 3).to_upper()

		if painter.has_method("get_thumbnail_image"):
			var thumb_img: Variant = painter.call("get_thumbnail_image", tex_id, 64)
			if thumb_img != null and thumb_img is Image:
				var tex_2d: ImageTexture = ImageTexture.create_from_image(thumb_img)
				btn.icon = tex_2d
				btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
				btn.text = ""

		btn.pressed.connect(func() -> void:
			_on_texture_selected(tex_id)
		)
		_texture_grid.add_child(btn)

		if _current_selected_texture.is_empty():
			_current_selected_texture = tex_id
			btn.button_pressed = true

	if not _current_selected_texture.is_empty():
		_update_selected_texture_preview(_current_selected_texture)
		setting_changed.emit("selected_texture_id", _current_selected_texture)

func _on_texture_selected(texture_id: String) -> void:
	_current_selected_texture = texture_id
	_update_selected_texture_preview(texture_id)
	setting_changed.emit("selected_texture_id", texture_id)

func _update_selected_texture_preview(texture_id: String) -> void:
	if _selected_texture_name_label != null:
		_selected_texture_name_label.text = "Selected: %s" % texture_id
	if _selected_texture_preview == null:
		return
	if _texture_preview_painter == null:
		_selected_texture_preview.texture = null
		return
	if _texture_preview_painter.has_method("get_texture_display_name"):
		var display_name: String = String(_texture_preview_painter.call("get_texture_display_name", texture_id))
		if display_name != "":
			_selected_texture_name_label.text = "Selected: %s" % display_name
	if _texture_preview_painter.has_method("get_thumbnail_image"):
		var thumb: Variant = _texture_preview_painter.call("get_thumbnail_image", texture_id, 128)
		if thumb != null and thumb is Image:
			_selected_texture_preview.texture = ImageTexture.create_from_image(thumb)
			return
	_selected_texture_preview.texture = null

func _on_wall_type_selected(index: int) -> void:
	if _wall_type_option == null or index < 0 or index >= _wall_type_option.item_count:
		return
	var md: Variant = _wall_type_option.get_item_metadata(index)
	var wall_type: String = "stone"
	if md is String and String(md) != "":
		wall_type = String(md)
	setting_changed.emit("wall_type", wall_type)

func _on_texture_shape_mode_selected(index: int) -> void:
	if _texture_shape_mode_option == null or index < 0 or index >= _texture_shape_mode_option.item_count:
		return
	setting_changed.emit("texture_brush_shape_mode", _get_texture_shape_mode_value())

func _get_texture_shape_mode_value() -> String:
	if _texture_shape_mode_option == null or _texture_shape_mode_option.item_count == 0:
		return "circle"
	var md: Variant = _texture_shape_mode_option.get_item_metadata(_texture_shape_mode_option.selected)
	if md is String and String(md) != "":
		return String(md)
	return "circle"

func _set_stroke_color(color: Color) -> void:
	if _grass_stroke_color_button != null:
		_grass_stroke_color_button.color = color
	setting_changed.emit("grass_stroke_color", color)


func _get_water_mode_value() -> String:
	if _water_mode_option != null and _water_mode_option.item_count > 0:
		var md: Variant = _water_mode_option.get_item_metadata(_water_mode_option.selected)
		if md is String and String(md) != "":
			return String(md)
	return "river"