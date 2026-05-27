extends MenuBar

signal action_requested(action: String)

var _next_id: int = 1
var _id_to_action: Dictionary = {}
var _action_to_id: Dictionary = {}
var _id_to_popup: Dictionary = {}

func _ready() -> void:
	set_flat(true)
	set_switch_on_hover(true)
	set_prefer_global_menu(false)
	visible = true
	custom_minimum_size = Vector2(0, 40)
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_color", Color(0.97, 0.98, 0.99, 1.0))
	add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	add_theme_color_override("font_focus_color", Color(1.0, 1.0, 1.0, 1.0))
	add_theme_color_override("font_disabled_color", Color(0.75, 0.76, 0.78, 1.0))
	_add_menu("File", [
		{"label": "New Map", "action": "file_new_map"},
		{"label": "Import Dungeondraft Map", "action": "file_import_dungeondraft"},
		{"label": "Load", "action": "file_load"},
		{"label": "Save", "action": "file_save"},
		{"label": "Save As", "action": "file_save_as"},
		{"separator": true},
		{"label": "Quit", "action": "file_quit"}
	])
	_add_menu("Map", [
		{"label": "New Mostly Flat Terrain", "action": "map_new_flat"},
		{"label": "New Area", "action": "map_new_area"},
		{"label": "Recenter Camera", "action": "map_recenter_camera"},
		{"label": "Toggle Grid Snapping", "action": "map_toggle_grid"}
	])
	_add_menu("Tools", [
		{"label": "Raise", "action": "tool_raise"},
		{"label": "Lower", "action": "tool_lower"},
		{"label": "Smooth", "action": "tool_smooth"},
		{"label": "Flatten", "action": "tool_flatten"},
		{"label": "Stamp Prefab", "action": "tool_stamp"},
		{"label": "Smart Wall", "action": "tool_wall"}
	])
	_add_menu("GM Tools", [
		{"label": "Asset Browser", "action": "gm_asset_browser"},
		{"label": "World Layers (Phase 2)", "action": "gm_world_layers"},
		{"label": "Lighting (Phase 2)", "action": "gm_lighting"}
	])
	_add_menu("View", [
		{"label": "Toggle Top-Down/3D Camera", "action": "view_toggle_projection"},
		{"label": "Toggle Pen-and-Ink PostFX", "action": "view_toggle_postfx"}
	])
	_add_menu("Configuration", [
		{"label": "Apply Editor Optimization Preset", "action": "config_apply_editor_optimization_preset"},
		{"separator": true},
		{"label": "Disable Post-Process", "action": "config_disable_post_process"},
		{"label": "Toggle Performance Mode", "action": "config_toggle_performance_mode"},
		{"label": "Toggle Ultra Performance", "action": "config_toggle_ultra_performance_mode"},
		{"label": "Toggle Lightweight PostFX", "action": "config_toggle_light_postfx"},
		{"label": "Use Chunked Terrain", "action": "config_toggle_chunked_terrain", "checkable": true},
		{"label": "Debug Draw Chunk Borders", "action": "config_toggle_chunk_borders", "checkable": true},
		{"label": "Debug Chunk Borders (Red)", "action": "config_toggle_chunk_borders_red", "checkable": true},
		{"label": "Highlight Problem Borders", "action": "config_toggle_chunk_borders_highlight", "checkable": true},
		{"separator": true},
		{"label": "Editor Settings", "action": "config_editor"},
		{"label": "Input Settings", "action": "config_input"}
	])
	_add_menu("Help", [
		{"label": "Quick Start", "action": "help_quickstart"},
		{"label": "About PaperVTT", "action": "help_about"}
	])
	# Wire the d20 icon button (sibling in MenuRow) to show an About popup.
	var d20_btn := get_parent().get_node_or_null("D20MenuButton") as MenuButton
	if d20_btn != null:
		d20_btn.get_popup().clear()
		d20_btn.get_popup().add_item("About PaperVTT", 1)
		d20_btn.get_popup().id_pressed.connect(
			func(_id: int) -> void: action_requested.emit("app_about")
		)

func _add_menu(title: String, items: Array) -> void:
	var popup := PopupMenu.new()
	popup.name = title
	popup.set_prefer_native_menu(false)
	popup.id_pressed.connect(_on_menu_id_pressed)
	add_child(popup)
	var menu_index := get_menu_count() - 1
	if menu_index >= 0:
		set_menu_title(menu_index, title)

	for entry in items:
		if bool(entry.get("separator", false)):
			popup.add_separator()
			continue
		var item_id := _next_id
		_next_id += 1
		if bool(entry.get("checkable", false)):
			popup.add_check_item(String(entry.get("label", "")), item_id)
		else:
			popup.add_item(String(entry.get("label", "")), item_id)
		var action: String = String(entry.get("action", ""))
		_id_to_action[item_id] = action
		_action_to_id[action] = item_id
		_id_to_popup[item_id] = popup

func set_action_checked(action: String, checked: bool) -> void:
	if not _action_to_id.has(action):
		return
	var item_id: int = int(_action_to_id[action])
	var popup: PopupMenu = _id_to_popup.get(item_id, null) as PopupMenu
	if popup == null:
		return
	var item_index: int = popup.get_item_index(item_id)
	if item_index < 0:
		return
	popup.set_item_checked(item_index, checked)

func _on_menu_id_pressed(item_id: int) -> void:
	if not _id_to_action.has(item_id):
		return
	action_requested.emit(_id_to_action[item_id])
