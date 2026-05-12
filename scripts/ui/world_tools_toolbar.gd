extends PanelContainer

signal tool_changed(tool_name: String)
signal setting_changed(setting_name: String, value: Variant)
signal clear_requested()

@onready var _brush_size_slider: HSlider = %BrushSizeSlider
@onready var _brush_strength_slider: HSlider = %BrushStrengthSlider
@onready var _flatten_height_slider: HSlider = %FlattenHeightSlider
@onready var _grid_snap_check: CheckBox = %GridSnapCheck
@onready var _brush_size_value: Label = %BrushSizeValue
@onready var _brush_strength_value: Label = %BrushStrengthValue
@onready var _flatten_height_value: Label = %FlattenHeightValue
@onready var _tool_hint: RichTextLabel = %ToolHint
@onready var _grass_density_slider: HSlider = %GrassDensitySlider
@onready var _grass_wind_slider: HSlider = %GrassWindSlider
@onready var _grass_wind_dir_slider: HSlider = %GrassWindDirSlider
@onready var _grass_height_slider: HSlider = %GrassHeightSlider
@onready var _grass_density_value: Label = %GrassDensityValue
@onready var _grass_wind_value: Label = %GrassWindValue
@onready var _grass_wind_dir_value: Label = %GrassWindDirValue
@onready var _grass_height_value: Label = %GrassHeightValue
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

@onready var _brush_label: Label = $Margin/Root/BrushLabel
@onready var _brush_size_row: HBoxContainer = $Margin/Root/BrushSizeRow
@onready var _brush_strength_row: HBoxContainer = $Margin/Root/BrushStrengthRow
@onready var _flatten_height_row: HBoxContainer = $Margin/Root/FlattenHeightRow
@onready var _separator2: HSeparator = $Margin/Root/Separator2
@onready var _grass_settings_label: Label = $Margin/Root/GrassSettingsLabel
@onready var _grass_density_row: HBoxContainer = $Margin/Root/GrassDensityRow
@onready var _grass_wind_row: HBoxContainer = $Margin/Root/GrassWindRow
@onready var _grass_wind_dir_row: HBoxContainer = $Margin/Root/GrassWindDirRow
@onready var _grass_height_row: HBoxContainer = $Margin/Root/GrassHeightRow
@onready var _scatter_settings_label: Label = $Margin/Root/ScatterSettingsLabel
@onready var _scatter_density_row: HBoxContainer = $Margin/Root/ScatterDensityRow
@onready var _scatter_scale_min_row: HBoxContainer = $Margin/Root/ScatterScaleMinRow
@onready var _scatter_scale_max_row: HBoxContainer = $Margin/Root/ScatterScaleMaxRow
@onready var _scatter_rotation_row: HBoxContainer = $Margin/Root/ScatterRotationRow
@onready var _scatter_tilt_row: HBoxContainer = $Margin/Root/ScatterTiltRow
@onready var _separator3: HSeparator = $Margin/Root/Separator3
@onready var _wall_height_row: HBoxContainer = $Margin/Root/WallHeightRow
@onready var _wall_type_row: HBoxContainer = $Margin/Root/WallTypeRow

var current_tool: String = "stamp"
var _tool_buttons: Dictionary = {}
var _button_group: ButtonGroup = ButtonGroup.new()

func _ready() -> void:
	for b in get_tree().get_nodes_in_group("tool_button"):
		if b is Button:
			var btn: Button = b as Button
			btn.button_group = _button_group
			btn.toggle_mode = true
			_tool_buttons[String(btn.name).to_lower()] = btn
			btn.pressed.connect(_on_tool_button_pressed.bind(String(btn.name).to_lower()))

	_brush_size_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("brush_size", v))
	_brush_strength_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("brush_strength", v))
	_flatten_height_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("flatten_height", v))
	_grid_snap_check.toggled.connect(func(v: bool) -> void: setting_changed.emit("grid_snap", v))
	_grass_density_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_density", v))
	_grass_wind_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_wind", v))
	_grass_wind_dir_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_wind_dir", v))
	_grass_height_slider.value_changed.connect(func(v: float) -> void: setting_changed.emit("grass_height", v))
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
	_wall_type_option.item_selected.connect(_on_wall_type_selected)

	_wall_type_option.clear()
	_wall_type_option.add_item("Ink Stone")
	_wall_type_option.set_item_metadata(0, "stone")
	_wall_type_option.add_item("Tudor Timber")
	_wall_type_option.set_item_metadata(1, "tudor")
	_wall_type_option.select(0)

	_brush_size_slider.value_changed.connect(_update_value_labels)
	_brush_strength_slider.value_changed.connect(_update_value_labels)
	_flatten_height_slider.value_changed.connect(_update_value_labels)
	_grass_density_slider.value_changed.connect(_update_value_labels)
	_grass_wind_slider.value_changed.connect(_update_value_labels)
	_grass_wind_dir_slider.value_changed.connect(_update_value_labels)
	_grass_height_slider.value_changed.connect(_update_value_labels)
	_scatter_density_slider.value_changed.connect(_update_value_labels)
	_scatter_scale_min_slider.value_changed.connect(_update_value_labels)
	_scatter_scale_max_slider.value_changed.connect(_update_value_labels)
	_scatter_rotation_slider.value_changed.connect(_update_value_labels)
	_scatter_tilt_slider.value_changed.connect(_update_value_labels)
	_wall_height_slider.value_changed.connect(_update_value_labels)
	_clear_tool_button.pressed.connect(func() -> void: clear_requested.emit())

	_update_value_labels(0.0)
	if _tool_buttons.has("select"):
		(_tool_buttons["select"] as Button).button_pressed = true
	current_tool = "select"
	_update_tool_hint(current_tool)
	_update_mode_badge(current_tool)

func select_tool() -> void:
	set_tool_from_action("tool_select")

func _on_tool_button_pressed(button_name: String) -> void:
	_apply_tool(button_name, true)

func set_tool_from_action(action: String) -> void:
	var name := action.replace("tool_", "")
	_apply_tool(name, true)

func get_current_tool() -> String:
	return current_tool

func set_grid_snap_enabled(enabled: bool) -> void:
	_grid_snap_check.button_pressed = enabled

func _update_value_labels(_value: float) -> void:
	_brush_size_value.text = "%.1f" % _brush_size_slider.value
	_brush_strength_value.text = "%.2f" % _brush_strength_slider.value
	_flatten_height_value.text = "%.2f" % _flatten_height_slider.value
	_grass_density_value.text = "%.2f" % _grass_density_slider.value
	_grass_wind_value.text = "%.2f" % _grass_wind_slider.value
	_grass_wind_dir_value.text = "%d°" % int(round(_grass_wind_dir_slider.value))
	_grass_height_value.text = "%.2f" % _grass_height_slider.value
	_scatter_density_value.text = "%.2f" % _scatter_density_slider.value
	_scatter_scale_min_value.text = "%.2f" % _scatter_scale_min_slider.value
	_scatter_scale_max_value.text = "%.2f" % _scatter_scale_max_slider.value
	_scatter_rotation_value.text = "%d°" % int(round(_scatter_rotation_slider.value))
	_scatter_tilt_value.text = "%d°" % int(round(_scatter_tilt_slider.value))
	_wall_height_value.text = "%.1f" % _wall_height_slider.value

func _update_tool_hint(tool_name: String) -> void:
	match tool_name:
		"select":
			_tool_hint.text = "[b]Select Mode[/b]  [i]0 / Esc[/i]\nLMB: click character to control\nRMB on terrain: deselect\nNo terrain editing active"
		"stamp":
			_tool_hint.text = "[b]Stamp Mode[/b]  [i]6[/i]\nLMB: place  •  RMB/Q/E: rotate 45°\nGrid snap keeps pieces aligned\nEsc: back to Select"
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
		"wall":
			_tool_hint.text = "[b]Smart Wall[/b]  [i]9[/i]\nLMB: click A then click B/C for chain walls\nCtrl-drag: rectangle • Shift in drag: perfect square\nRMB or Esc: end chain • Match Connected Heights keeps structures uniform\nRMB menu: Add Window • Ctrl-drag window height, Alt-drag width\nSnap to Standard Heights keeps openings tidy"
		_:
			_tool_hint.text = "[b]World Tool[/b]\nSwitch tools from this sidebar or top menu\n[i]Esc: back to Select[/i]"

func _apply_tool(tool_name: String, emit_signal: bool) -> void:
	current_tool = tool_name
	if _tool_buttons.has(tool_name):
		(_tool_buttons[tool_name] as Button).button_pressed = true
	_update_tool_hint(tool_name)
	_update_mode_badge(tool_name)
	if emit_signal:
		tool_changed.emit(current_tool)
	_update_tool_visibility(tool_name)

func _update_mode_badge(tool_name: String) -> void:
	if _tool_mode_label == null:
		return
	var label := "MODE: %s" % _format_tool_name(tool_name)
	_tool_mode_label.text = label
	if tool_name == "select":
		_tool_mode_label.modulate = Color(0.86, 0.9, 0.94, 1.0)
		_clear_tool_button.disabled = true
	else:
		_tool_mode_label.modulate = Color(0.45, 0.9, 1.0, 1.0)
		_clear_tool_button.disabled = false

func _update_tool_visibility(tool_name: String) -> void:
	var terrain_tools_visible: bool = tool_name != "wall"
	var scatter_controls_visible: bool = (tool_name == "scatterpaint" or tool_name == "scattererase")
	var wall_controls_visible: bool = tool_name == "wall"

	_brush_label.visible = terrain_tools_visible
	_brush_size_row.visible = terrain_tools_visible
	_brush_size_slider.visible = terrain_tools_visible
	_brush_strength_row.visible = terrain_tools_visible
	_brush_strength_slider.visible = terrain_tools_visible
	_flatten_height_row.visible = terrain_tools_visible
	_flatten_height_slider.visible = terrain_tools_visible
	_separator2.visible = terrain_tools_visible
	_grass_settings_label.visible = terrain_tools_visible
	_grass_density_row.visible = terrain_tools_visible
	_grass_density_slider.visible = terrain_tools_visible
	_grass_wind_row.visible = terrain_tools_visible
	_grass_wind_slider.visible = terrain_tools_visible
	_grass_wind_dir_row.visible = terrain_tools_visible
	_grass_wind_dir_slider.visible = terrain_tools_visible
	_grass_height_row.visible = terrain_tools_visible
	_grass_height_slider.visible = terrain_tools_visible
	_scatter_settings_label.visible = scatter_controls_visible
	_scatter_density_row.visible = scatter_controls_visible
	_scatter_density_slider.visible = scatter_controls_visible
	_scatter_scale_min_row.visible = scatter_controls_visible
	_scatter_scale_min_slider.visible = scatter_controls_visible
	_scatter_scale_max_row.visible = scatter_controls_visible
	_scatter_scale_max_slider.visible = scatter_controls_visible
	_scatter_rotation_row.visible = scatter_controls_visible
	_scatter_rotation_slider.visible = scatter_controls_visible
	_scatter_tilt_row.visible = scatter_controls_visible
	_scatter_tilt_slider.visible = scatter_controls_visible
	_separator3.visible = true

	_wall_height_row.visible = wall_controls_visible
	_wall_height_slider.visible = wall_controls_visible
	_wall_type_row.visible = wall_controls_visible
	_wall_rect_mode_check.visible = wall_controls_visible
	_wall_match_heights_check.visible = wall_controls_visible
	_wall_foundation_check.visible = wall_controls_visible
	_wall_opening_height_snap_check.visible = wall_controls_visible
	_wall_jitter_check.visible = wall_controls_visible

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
		"select":
			return "Select / None"
		"wall":
			return "Smart Wall"
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
		"grass_density": _grass_density_slider.value,
		"grass_wind": _grass_wind_slider.value,
		"grass_wind_dir": _grass_wind_dir_slider.value,
		"grass_height": _grass_height_slider.value,
		"scatter_density": _scatter_density_slider.value,
		"scatter_scale_min": _scatter_scale_min_slider.value,
		"scatter_scale_max": _scatter_scale_max_slider.value,
		"scatter_rotation_randomness": _scatter_rotation_slider.value,
		"scatter_tilt": _scatter_tilt_slider.value,
		"wall_height": _wall_height_slider.value,
		"wall_type": wall_type,
		"wall_rect_mode": _wall_rect_mode_check.button_pressed,
		"wall_match_connected_heights": _wall_match_heights_check.button_pressed,
		"wall_add_foundation": _wall_foundation_check.button_pressed,
		"wall_opening_height_snap": _wall_opening_height_snap_check.button_pressed,
		"wall_jitter": _wall_jitter_check.button_pressed
	}

func _on_wall_type_selected(index: int) -> void:
	if _wall_type_option == null or index < 0 or index >= _wall_type_option.item_count:
		return
	var md: Variant = _wall_type_option.get_item_metadata(index)
	var wall_type: String = "stone"
	if md is String and String(md) != "":
		wall_type = String(md)
	setting_changed.emit("wall_type", wall_type)
