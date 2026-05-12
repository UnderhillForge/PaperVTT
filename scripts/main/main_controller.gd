extends Node3D

const TerrainRuntimeEditor = preload("res://scripts/services/terrain_runtime_editor.gd")

@onready var terrain_placeholder: Node3D = $Terrain
@onready var camera: Camera3D = $Camera3D
@onready var camera_manager: Node = %CameraManager
@onready var stamp_root: Node3D = $StampRoot
@onready var menu_bar: MenuBar = %MainMenuBar
@onready var world_tools: PanelContainer = %WorldToolsToolbar
@onready var asset_browser: PanelContainer = %AssetBrowser
@onready var status_label: Label = %StatusLabel
@onready var postfx_canvas: CanvasLayer = $PostProcessCanvas
@onready var perf_label: Label = %PerfLabel
@onready var viewport_hint: Label = $EditorCanvas/RootUI/Layout/Body/CenterSpacer/ViewportHint
@onready var optimize_button: Button = %OptimizeButton
@onready var sun_light: DirectionalLight3D = $Sun

var _runtime_terrain_editor: TerrainRuntimeEditor = TerrainRuntimeEditor.new()
var _selected_prefab: String = ""
var _current_tool: String = "stamp"
var _brush_size: float = 10.0
var _brush_strength: float = 0.25
var _flatten_height: float = 0.0
var _grid_snap: bool = true
var _is_tool_dragging: bool = false
var _terrain_node: Node = null
var _grass_system: Node3D = null
var _stamp_rotation_deg: float = 0.0
var _stamp_preview: Node3D = null
var _brush_preview: MeshInstance3D = null
var _stroke_interval_accum: float = 0.0
var _is_stamp_dragging: bool = false
var _stamp_drag_interval_accum: float = 0.0
var _last_stamp_grid_key: Vector2i = Vector2i(999999, 999999)
var _seed_prefab_paths: Array[String] = []
var _room_prefabs: Array[String] = []
var _nature_prefabs: Array[String] = []
var _performance_mode: bool = false
var _ultra_performance_mode: bool = false
var _lightweight_postfx: bool = false
var _post_process_disabled: bool = false
var _perf_overlay_accum: float = 0.0
var _lightweight_editor_mode: bool = false
var _is_editor_runtime: bool = OS.has_feature("editor")

const STROKE_INTERVAL_SEC: float = 1.0 / 90.0
const STAMP_DRAG_INTERVAL_SEC: float = 1.0 / 16.0
const MENU_BAR_SCRIPT: Script = preload("res://scripts/ui/main_menu_bar.gd")
const TOOLBAR_SCENE: PackedScene = preload("res://scenes/ui/WorldToolsToolbar.tscn")
const ASSET_BROWSER_SCENE: PackedScene = preload("res://scenes/ui/AssetBrowser.tscn")
const CUSTOM_TERRAIN_SCENE: PackedScene = preload("res://scenes/terrain/CustomHeightmapTerrain.tscn")
const DUNGEONDRAFT_IMPORTER_SCRIPT: Script = preload("res://scripts/import/dungeondraft_importer.gd")
const GRASS_SYSTEM_SCRIPT: Script = preload("res://scripts/terrain/grass_system.gd")
const PLAYER_CHARACTER_SCENE: PackedScene = preload("res://scenes/characters/PlayerCharacter.tscn")
const WALL_TOOL_SCRIPT: Script = preload("res://scripts/tools/wall_tool.gd")
const USER_SCREENSHOT_PATH: String = "user://full_editor_screenshot.png"
const RES_SCREENSHOT_PATH: String = "res://debug_full_editor.png"
const PREFAB_VISIBILITY_END_NEAR: float = 170.0
const PREFAB_VISIBILITY_END_FAR: float = 260.0
const PREFAB_VISIBILITY_END_NEAR_EDITOR: float = 48.0
const PREFAB_VISIBILITY_END_FAR_EDITOR: float = 72.0
const STARTER_TREE_CLUSTER_COUNT: int = 10
const AUTO_DEBUG_SCREENSHOTS: bool = false
const PERF_OVERLAY_INTERVAL_SEC: float = 0.25
const DISABLE_CUSTOM_POSTFX_DEFAULT: bool = true
const DEFAULT_DUNGEONDRAFT_MAP_PATH: String = "res://dd_testing/test1.dungeondraft_map"
const IMPORT_WALL_TEXTURE_PATH: String = "res://assets/textures/materials/kenney_nature-kit/cliff_block_stone_NW.png"
const IMPORT_FLOOR_TEXTURE_PATH: String = "res://assets/textures/materials/kenney_nature-kit/stone_smallFlatC.png"
const IMPORT_LIGHT_HEIGHT_OFFSET: float = 1.9
const DEFAULT_MAP_SAVE_PATH: String = "user://maps/papervtt_map.pvt"

var _dungeondraft_importer: RefCounted = null
var _dd_import_dialog: FileDialog = null
var _import_prefab_paths: Array[String] = []
var _wall_tool: RefCounted = WALL_TOOL_SCRIPT.new()
var _import_prefab_key_to_path: Dictionary = {}
var _import_wall_material: StandardMaterial3D = null
var _import_floor_material: StandardMaterial3D = null
var _dd_import_settings := {
	"floor_raise_height": 0.15,
	"wall_thickness_m": 0.2,
	"wall_height_m": 2.5,
	"dd_pixels_per_cell": 256.0,
	"world_units_per_cell": 1.524,
	"light_range_scale": 1.524,
	"light_energy_scale": 1.6
}
var _current_map_path: String = DEFAULT_MAP_SAVE_PATH

func _ready() -> void:
	_ensure_editor_ui_layout()
	if menu_bar != null:
		menu_bar.action_requested.connect(_on_menu_action_requested)
	if world_tools != null:
		world_tools.tool_changed.connect(_on_tool_changed)
		world_tools.setting_changed.connect(_on_tool_setting_changed)
		if world_tools.has_signal("clear_requested"):
			world_tools.clear_requested.connect(_on_tool_clear_requested)
	if asset_browser != null:
		asset_browser.prefab_selected.connect(_on_prefab_selected)
		asset_browser.prefab_activated.connect(_on_prefab_activated)
		if asset_browser.has_signal("stamp_mode_requested"):
			asset_browser.stamp_mode_requested.connect(_on_stamp_mode_requested)
	if optimize_button != null:
		optimize_button.pressed.connect(_on_optimize_button_pressed)
	_sync_toolbar_tool_state()
	_load_terrain_extension()
	_setup_dungeondraft_import()
	_terrain_node = _ensure_terrain_node()
	if _is_editor_runtime:
		_apply_editor_optimization_preset(false)
	_setup_preview_nodes()

	var ok: bool = _runtime_terrain_editor.initialize(_terrain_node)
	if ok:
		_set_status("Custom heightmap terrain initialized")
	else:
		_set_status("Heightmap terrain unavailable; stamping remains active")

	# Grass system — created at runtime, parented to terrain placeholder.
	_grass_system = Node3D.new()
	_grass_system.name = "GrassSystem"
	_grass_system.set_script(GRASS_SYSTEM_SCRIPT)
	terrain_placeholder.add_child(_grass_system)
	_grass_system.call("initialize", _terrain_node, camera, 256.0)
	_ensure_character_setup()

	if AUTO_DEBUG_SCREENSHOTS:
		call_deferred("_capture_full_editor_screenshot", "startup")
	if not _load_map_from_path(_current_map_path):
		_create_new_flat_map()
	if DISABLE_CUSTOM_POSTFX_DEFAULT:
		_set_post_process_disabled(true)

func _exit_tree() -> void:
	_runtime_terrain_editor.end_stroke()
	_runtime_terrain_editor.dispose()
	_deactivate_wall_tool()
	if _stamp_preview != null:
		_stamp_preview.queue_free()
	if _brush_preview != null:
		_brush_preview.queue_free()

func _process(delta: float) -> void:
	_perf_overlay_accum += delta
	if _perf_overlay_accum >= PERF_OVERLAY_INTERVAL_SEC:
		_perf_overlay_accum = 0.0
		_update_performance_overlay()
	_update_live_previews()
	if _is_tool_dragging and _current_tool != "stamp":
		_stroke_interval_accum += delta
		while _stroke_interval_accum >= STROKE_INTERVAL_SEC:
			_stroke_interval_accum -= STROKE_INTERVAL_SEC
			_continue_tool_stroke()
	if _is_stamp_dragging and _current_tool == "stamp":
		_stamp_drag_interval_accum += delta
		while _stamp_drag_interval_accum >= STAMP_DRAG_INTERVAL_SEC:
			_stamp_drag_interval_accum -= STAMP_DRAG_INTERVAL_SEC
			_stamp_at_mouse(true)
	if _current_tool == "wall" and _wall_tool != null and _wall_tool.has_method("update_preview"):
		_wall_tool.call("update_preview")

func _unhandled_input(event: InputEvent) -> void:
	if _current_tool != "wall" and _route_input_to_characters(event):
		get_viewport().set_input_as_handled()
		return

	# Global keyboard shortcuts — work even while hovering UI controls
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z and event.ctrl_pressed and _current_tool == "wall":
			if _wall_tool != null and _wall_tool.has_method("undo_last_segment"):
				if bool(_wall_tool.call("undo_last_segment")):
					get_viewport().set_input_as_handled()
					return
		match event.keycode:
			KEY_ESCAPE:
				if _current_tool == "wall" and _wall_tool != null and _wall_tool.has_method("cancel_chain"):
					if bool(_wall_tool.call("cancel_chain")):
						get_viewport().set_input_as_handled()
						return
				_clear_active_tool("Cleared active tool")
				get_viewport().set_input_as_handled()
				return
			KEY_1:
				_switch_tool("raise")
				get_viewport().set_input_as_handled()
				return
			KEY_2:
				_switch_tool("lower")
				get_viewport().set_input_as_handled()
				return
			KEY_3:
				_switch_tool("smooth")
				get_viewport().set_input_as_handled()
				return
			KEY_4:
				_switch_tool("flatten")
				get_viewport().set_input_as_handled()
				return
			KEY_5:
				_switch_tool("paint")
				get_viewport().set_input_as_handled()
				return
			KEY_6:
				_switch_tool("stamp")
				get_viewport().set_input_as_handled()
				return
			KEY_7:
				_switch_tool("grasspaint")
				get_viewport().set_input_as_handled()
				return
			KEY_8:
				_switch_tool("grasserase")
				get_viewport().set_input_as_handled()
				return
			KEY_9:
				_switch_tool("wall")
				get_viewport().set_input_as_handled()
				return

	if get_viewport().gui_get_hovered_control() != null:
		return

	if _current_tool == "wall":
		if _wall_tool != null and _wall_tool.has_method("handle_input_event"):
			var used: Variant = _wall_tool.call("handle_input_event", event)
			if bool(used):
				get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _current_tool == "select":
				if _has_active_character():
					_deselect_all_characters()
					_set_status("Cleared selection")
					get_viewport().set_input_as_handled()
				return
			if _current_tool == "stamp":
				_stamp_at_mouse(false)
				_is_stamp_dragging = true
				_stamp_drag_interval_accum = 0.0
			else:
				_begin_tool_stroke()
		else:
			_is_stamp_dragging = false
			if _is_tool_dragging:
				_is_tool_dragging = false
				if not _current_tool.begins_with("grass"):
					_runtime_terrain_editor.end_stroke()

	if event is InputEventMouseMotion and _is_tool_dragging:
		_continue_tool_stroke()
	if event is InputEventMouseMotion and _is_stamp_dragging and _current_tool == "stamp":
		_stamp_at_mouse(true)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _current_tool == "stamp":
		_rotate_stamp_preview(45.0)
		get_viewport().set_input_as_handled()

	# Right-click on empty terrain deselects the active character (not in stamp mode)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and _current_tool != "stamp":
		if _has_active_character():
			_deselect_all_characters()
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and not event.echo and _current_tool == "stamp":
		if event.keycode == KEY_Q:
			_rotate_stamp_preview(-45.0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			_rotate_stamp_preview(45.0)
			get_viewport().set_input_as_handled()

func _on_menu_action_requested(action: String) -> void:
	if action.begins_with("tool_"):
		world_tools.set_tool_from_action(action)
		return

	match action:
		"file_new_map", "map_new_flat", "map_new_area":
			_create_new_flat_map()
		"file_import_dungeondraft":
			_begin_dungeondraft_import()
		"file_save":
			_save_map_to_path(_current_map_path)
		"file_save_as":
			var stamp: String = Time.get_datetime_string_from_system(false, true).replace(":", "-")
			_current_map_path = "user://maps/papervtt_map_%s.pvt" % stamp
			_save_map_to_path(_current_map_path)
		"file_load":
			if not _load_map_from_path(_current_map_path):
				_set_status("No saved map found")
		"map_recenter_camera":
			if camera_manager != null and camera_manager.has_method("recenter"):
				camera_manager.call("recenter")
		"map_toggle_grid":
			_grid_snap = not _grid_snap
			if world_tools.has_method("set_grid_snap_enabled"):
				world_tools.call("set_grid_snap_enabled", _grid_snap)
			if _wall_tool != null and _wall_tool.has_method("set_snap_grid"):
				_wall_tool.call("set_snap_grid", 0.5 if _grid_snap else 0.01)
			_set_status("Grid snap: %s" % ("On" if _grid_snap else "Off"))
		"view_toggle_projection":
			if camera_manager != null and camera_manager.has_method("toggle_projection_mode"):
				camera_manager.call("toggle_projection_mode")
		"view_toggle_postfx":
			_toggle_postfx()
		"config_apply_editor_optimization_preset":
			_apply_editor_optimization_preset(true)
		"config_disable_post_process":
			_set_post_process_disabled(not _post_process_disabled)
		"config_toggle_performance_mode":
			_set_performance_mode(not _performance_mode)
		"config_toggle_ultra_performance_mode":
			_set_ultra_performance_mode(not _ultra_performance_mode)
		"config_toggle_light_postfx":
			_set_lightweight_postfx(not _lightweight_postfx)
		"file_quit":
			get_tree().quit()
		"help_about", "app_about":
			_show_about_dialog()

func _on_tool_changed(tool_name: String) -> void:
	if _current_tool != tool_name:
		_cancel_active_interactions()
	_current_tool = tool_name
	if _current_tool == "wall":
		_activate_wall_tool()
	else:
		_deactivate_wall_tool()
	_update_active_tool_feedback()
	_set_status("Active tool: %s" % _format_tool_name(tool_name))

func _on_tool_clear_requested() -> void:
	_clear_active_tool("Cleared active tool")

func _on_tool_setting_changed(setting_name: String, value: Variant) -> void:
	match setting_name:
		"brush_size":
			_brush_size = float(value)
		"brush_strength":
			_brush_strength = float(value)
		"flatten_height":
			_flatten_height = float(value)
		"grid_snap":
			_grid_snap = bool(value)
			if _wall_tool != null and _wall_tool.has_method("set_snap_grid"):
				_wall_tool.call("set_snap_grid", 0.5 if _grid_snap else 0.01)
		"grass_wind":
			if _grass_system != null and _grass_system.has_method("set_wind_strength"):
				_grass_system.call("set_wind_strength", float(value))
		"grass_wind_dir":
			if _grass_system != null and _grass_system.has_method("set_wind_direction_deg"):
				_grass_system.call("set_wind_direction_deg", float(value))
		"grass_density":
			if _grass_system != null and _grass_system.has_method("set_density_scale"):
				_grass_system.call("set_density_scale", float(value))
		"grass_height":
			if _grass_system != null and _grass_system.has_method("set_grass_height"):
				_grass_system.call("set_grass_height", float(value))
		"wall_height":
			if _wall_tool != null and _wall_tool.has_method("set_segment_height"):
				_wall_tool.call("set_segment_height", float(value))
		"wall_type":
			if _wall_tool != null and _wall_tool.has_method("set_segment_type"):
				_wall_tool.call("set_segment_type", String(value))
		"wall_rect_mode":
			if _wall_tool != null and _wall_tool.has_method("set_rect_mode_enabled"):
				_wall_tool.call("set_rect_mode_enabled", bool(value))
		"wall_match_connected_heights":
			if _wall_tool != null and _wall_tool.has_method("set_match_connected_heights_enabled"):
				_wall_tool.call("set_match_connected_heights_enabled", bool(value))
		"wall_add_foundation":
			if _wall_tool != null and _wall_tool.has_method("set_rect_foundation_enabled"):
				_wall_tool.call("set_rect_foundation_enabled", bool(value))
		"wall_opening_height_snap":
			if _wall_tool != null and _wall_tool.has_method("set_opening_height_snap_enabled"):
				_wall_tool.call("set_opening_height_snap_enabled", bool(value))
		"wall_jitter":
			if _wall_tool != null and _wall_tool.has_method("set_jitter_enabled"):
				_wall_tool.call("set_jitter_enabled", bool(value))

func _on_prefab_selected(prefab_path: String) -> void:
	_selected_prefab = prefab_path
	_rebuild_stamp_preview()
	_update_active_tool_feedback()
	_set_status("Selected prefab: %s" % prefab_path.get_file())

func _on_stamp_mode_requested() -> void:
	if _current_tool != "stamp":
		_switch_tool("stamp")

func _on_prefab_activated(prefab_path: String) -> void:
	_selected_prefab = prefab_path
	_update_active_tool_feedback()
	_stamp_at_mouse(false)

func _on_optimize_button_pressed() -> void:
	_apply_editor_optimization_preset(true)

func _create_new_flat_map(include_seed_content: bool = true) -> void:
	for child in stamp_root.get_children():
		child.queue_free()
	var wall_system: Node = get_node_or_null("WallSystem")
	if wall_system != null and wall_system.has_method("clear_segments"):
		wall_system.call("clear_segments")
	_stamp_rotation_deg = 0.0
	_stroke_interval_accum = 0.0
	_stamp_drag_interval_accum = 0.0
	_last_stamp_grid_key = Vector2i(999999, 999999)

	if _terrain_node != null:
		if _terrain_node.has_method("clear_colliders"):
			_terrain_node.call("clear_colliders")
		if _terrain_node.has_method("set_mesh_size"):
			_terrain_node.call("set_mesh_size", 128 if _lightweight_editor_mode else 512)
		_configure_visible_terrain()

	if _runtime_terrain_editor.is_available():
		_runtime_terrain_editor.bootstrap_new_map(Time.get_ticks_usec())

	if _grass_system != null and _grass_system.has_method("clear_all"):
		_grass_system.call("clear_all")
	_reset_characters_on_new_map()

	if include_seed_content:
		_seed_default_prefabs()
		_focus_camera_on_seed_content()

	if camera_manager != null and camera_manager.has_method("recenter"):
		camera_manager.call("recenter")
	if camera_manager != null and camera_manager.has_method("set_top_down_default"):
		camera_manager.call("set_top_down_default")

	_set_status("New map ready: flat editable heightmap terrain and starter props")
	if AUTO_DEBUG_SCREENSHOTS:
		call_deferred("_capture_full_editor_screenshot", "new_map")

func _setup_dungeondraft_import() -> void:
	_dungeondraft_importer = DUNGEONDRAFT_IMPORTER_SCRIPT.new()
	_import_prefab_paths.clear()
	_import_prefab_key_to_path.clear()
	_collect_prefabs("res://assets/prefabs", _import_prefab_paths)
	for prefab_path in _import_prefab_paths:
		var key: String = prefab_path.get_file().get_basename().to_lower()
		if not _import_prefab_key_to_path.has(key):
			_import_prefab_key_to_path[key] = prefab_path

	_import_wall_material = _build_import_material(IMPORT_WALL_TEXTURE_PATH, Color(0.86, 0.86, 0.88, 1.0))
	_import_floor_material = _build_import_material(IMPORT_FLOOR_TEXTURE_PATH, Color(0.74, 0.74, 0.72, 1.0))

	_dd_import_dialog = FileDialog.new()
	_dd_import_dialog.name = "DungeondraftImportDialog"
	_dd_import_dialog.title = "Import Dungeondraft Map"
	_dd_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dd_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dd_import_dialog.filters = PackedStringArray(["*.dungeondraft_map ; Dungeondraft Maps"])
	_dd_import_dialog.size = Vector2i(920, 560)
	_dd_import_dialog.file_selected.connect(_on_dungeondraft_file_selected)
	add_child(_dd_import_dialog)

func _build_import_material(texture_path: String, fallback_color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	mat.albedo_color = fallback_color
	var tex: Texture2D = load(texture_path) as Texture2D
	if tex != null:
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(2.2, 2.2, 1.0)
	return mat

func _begin_dungeondraft_import() -> void:
	if DisplayServer.get_name() == "headless":
		_import_dungeondraft_map(DEFAULT_DUNGEONDRAFT_MAP_PATH)
		return
	if _dd_import_dialog == null:
		_set_status("Import dialog unavailable")
		return
	var default_dir: String = ProjectSettings.globalize_path("res://dd_testing")
	if DirAccess.dir_exists_absolute(default_dir):
		_dd_import_dialog.current_dir = default_dir
	_dd_import_dialog.popup_centered_ratio(0.7)

func _on_dungeondraft_file_selected(path: String) -> void:
	_import_dungeondraft_map(path)

func _import_dungeondraft_map(file_path: String) -> void:
	if _dungeondraft_importer == null:
		_set_status("Dungeondraft importer is not available")
		return

	_set_status("Importing Dungeondraft map: %s" % file_path.get_file())
	_create_new_flat_map(false)

	var parsed: Variant = _dungeondraft_importer.call("import_from_file", file_path, _dd_import_settings)
	if not (parsed is Dictionary):
		_set_status("Dungeondraft import failed: parser returned invalid data")
		return
	var result: Dictionary = parsed
	if not bool(result.get("ok", false)):
		_set_status("Dungeondraft import failed: %s" % String(result.get("error", "unknown error")))
		return

	var floor_tiles: Array = result.get("floor_tiles", [])
	var wall_segments: Array = result.get("wall_segments", [])
	var objects: Array = result.get("objects", [])
	var lights: Array = result.get("lights", [])

	var import_root := Node3D.new()
	import_root.name = "ImportedDungeondraft"
	stamp_root.add_child(import_root)

	_raise_terrain_for_imported_floor_tiles(floor_tiles)
	var floor_count: int = _spawn_imported_floor_tiles(import_root, floor_tiles)
	var wall_count: int = _spawn_imported_walls(import_root, wall_segments)
	var object_stats: Dictionary = _spawn_imported_objects(import_root, objects)
	var light_count: int = _spawn_imported_lights(import_root, lights)

	if camera_manager != null and camera_manager.has_method("recenter"):
		camera_manager.call("recenter")
	if camera_manager != null and camera_manager.has_method("set_top_down_default"):
		camera_manager.call("set_top_down_default")

	var warning_count: int = (result.get("warnings", []) as Array).size()
	_set_status("Imported DD map: %d floor tiles, %d walls, %d objects (%d skipped), %d lights, %d warnings" % [
		floor_count,
		wall_count,
		int(object_stats.get("placed", 0)),
		int(object_stats.get("skipped", 0)),
		light_count,
		warning_count
	])

func _raise_terrain_for_imported_floor_tiles(floor_tiles: Array) -> void:
	if not _runtime_terrain_editor.is_available():
		return
	var raise_height: float = float(_dd_import_settings.get("floor_raise_height", 0.15))
	var cell_size: float = float(_dd_import_settings.get("world_units_per_cell", 1.0))
	_runtime_terrain_editor.set_tool("flatten", cell_size * 1.1, 1.0, raise_height)
	for tile_variant in floor_tiles:
		if not (tile_variant is Dictionary):
			continue
		var tile: Dictionary = tile_variant
		var center: Vector3 = tile.get("center", Vector3.ZERO)
		_runtime_terrain_editor.begin_stroke(center)

func _spawn_imported_floor_tiles(parent: Node3D, floor_tiles: Array) -> int:
	var root := Node3D.new()
	root.name = "ImportedFloor"
	parent.add_child(root)

	var count: int = 0
	for tile_variant in floor_tiles:
		if not (tile_variant is Dictionary):
			continue
		var tile: Dictionary = tile_variant
		var center: Vector3 = tile.get("center", Vector3.ZERO)
		var tile_size: float = float(tile.get("cell_size", 1.0))
		var tile_raise: float = float(tile.get("raise_height", 0.15))

		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "FloorTile"
		var box := BoxMesh.new()
		box.size = Vector3(tile_size, 0.08, tile_size)
		mesh_instance.mesh = box
		mesh_instance.material_override = _import_floor_material

		var terrain_y: float = _sample_terrain_height(center.x, center.z)
		mesh_instance.global_position = Vector3(center.x, terrain_y + tile_raise - 0.04, center.z)
		root.add_child(mesh_instance)
		count += 1

	return count

func _spawn_imported_walls(parent: Node3D, wall_segments: Array) -> int:
	var root := Node3D.new()
	root.name = "ImportedWalls"
	parent.add_child(root)

	var count: int = 0
	for segment_variant in wall_segments:
		if not (segment_variant is Dictionary):
			continue
		var segment: Dictionary = segment_variant
		var from: Vector3 = segment.get("from", Vector3.ZERO)
		var to: Vector3 = segment.get("to", Vector3.ZERO)
		var thickness: float = float(segment.get("thickness", 0.2))
		var height: float = float(segment.get("height", 2.5))

		var delta: Vector3 = to - from
		delta.y = 0.0
		var length: float = delta.length()
		if length < 0.05:
			continue

		var wall := MeshInstance3D.new()
		wall.name = "WallSegment"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(length, height, thickness)
		wall.mesh = mesh
		wall.material_override = _import_wall_material

		var mid: Vector3 = (from + to) * 0.5
		var base_y: float = maxf(_sample_terrain_height(from.x, from.z), _sample_terrain_height(to.x, to.z))
		base_y = maxf(base_y, float(_dd_import_settings.get("floor_raise_height", 0.15)))
		wall.global_position = Vector3(mid.x, base_y + (height * 0.5), mid.z)
		wall.rotation.y = atan2(delta.z, delta.x)
		root.add_child(wall)

		var static_body := StaticBody3D.new()
		static_body.name = "WallCollision"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(length, height, thickness)
		shape.shape = box
		static_body.add_child(shape)
		static_body.global_transform = wall.global_transform
		root.add_child(static_body)

		count += 1

	return count

func _spawn_imported_objects(parent: Node3D, objects: Array) -> Dictionary:
	var root := Node3D.new()
	root.name = "ImportedObjects"
	parent.add_child(root)

	var placed: int = 0
	var skipped: int = 0
	for object_variant in objects:
		if not (object_variant is Dictionary):
			skipped += 1
			continue
		var object_data: Dictionary = object_variant
		var source_texture: String = String(object_data.get("texture", ""))
		var prefab_path: String = _match_prefab_for_dd_object(source_texture)
		if prefab_path == "":
			skipped += 1
			continue

		var position: Vector3 = object_data.get("position", Vector3.ZERO)
		var rotation_deg: float = rad_to_deg(float(object_data.get("rotation_rad", 0.0)))
		var scale: Vector3 = object_data.get("scale", Vector3.ONE)
		var placed_node: Node3D = _place_prefab_direct(prefab_path, position, rotation_deg, root, scale)
		if placed_node == null:
			skipped += 1
			continue
		placed += 1

	return {"placed": placed, "skipped": skipped}

func _match_prefab_for_dd_object(texture_path: String) -> String:
	var key: String = texture_path.get_file().get_basename().to_lower()
	if key.contains("wall_torch"):
		var preferred := [
			"res://assets/prefabs/props/core/torch_wall_mounted.tscn",
			"res://assets/prefabs/props/torches/torch_mounted.tscn",
			"res://assets/prefabs/props/torches/torch_lit.tscn"
		]
		for p in preferred:
			if ResourceLoader.exists(p):
				return p

	if _import_prefab_key_to_path.has(key):
		return String(_import_prefab_key_to_path[key])

	for candidate in _import_prefab_paths:
		var lower_candidate: String = candidate.to_lower()
		if key != "" and lower_candidate.contains(key):
			return candidate

	var tokens: PackedStringArray = key.split("_", false)
	for token in tokens:
		if token.length() < 4:
			continue
		for candidate in _import_prefab_paths:
			if candidate.to_lower().contains(token):
				return candidate

	return ""

func _spawn_imported_lights(parent: Node3D, lights: Array) -> int:
	var root := Node3D.new()
	root.name = "ImportedLights"
	parent.add_child(root)

	var count: int = 0
	for light_variant in lights:
		if not (light_variant is Dictionary):
			continue
		var light_data: Dictionary = light_variant
		var pos: Vector3 = light_data.get("position", Vector3.ZERO)
		var terrain_y: float = _sample_terrain_height(pos.x, pos.z)

		var omni := OmniLight3D.new()
		omni.name = "ImportedOmniLight"
		omni.global_position = Vector3(pos.x, terrain_y + IMPORT_LIGHT_HEIGHT_OFFSET, pos.z)
		omni.omni_range = maxf(0.5, float(light_data.get("range", 5.0)))
		omni.light_energy = maxf(0.1, float(light_data.get("intensity", 1.0)))
		omni.light_color = light_data.get("color", Color(1.0, 0.9, 0.7, 1.0))
		omni.shadow_enabled = bool(light_data.get("shadows", true))
		root.add_child(omni)
		count += 1

	return count

func _ensure_character_setup() -> void:
	var root := get_node_or_null("Characters") as Node3D
	if root == null:
		root = Node3D.new()
		root.name = "Characters"
		add_child(root)

	if root.get_child_count() == 0 and PLAYER_CHARACTER_SCENE != null:
		var character := PLAYER_CHARACTER_SCENE.instantiate()
		if character is Node3D:
			root.add_child(character)

	for child in root.get_children():
		if child.has_signal("selection_changed") and not child.selection_changed.is_connected(_on_character_selection_changed):
			child.selection_changed.connect(_on_character_selection_changed)
		if child.has_method("initialize_controller"):
			child.call("initialize_controller", camera, _terrain_node)

func _on_character_selection_changed(character: Node, selected: bool) -> void:
	if selected:
		_set_status("Controlling character: %s" % character.name)
		if camera_manager != null and camera_manager.has_method("set_follow_target") and character is Node3D:
			camera_manager.call("set_follow_target", character as Node3D)
	else:
		if camera_manager != null and camera_manager.has_method("clear_follow_target"):
			camera_manager.call("clear_follow_target")

func _deselect_all_characters() -> void:
	for n in get_tree().get_nodes_in_group("character_controller"):
		if n.has_method("deselect"):
			n.call("deselect")

func _has_active_character() -> bool:
	for n in get_tree().get_nodes_in_group("character_controller"):
		if n.has_method("is_selected") and bool(n.call("is_selected")):
			return true
	return false

func _switch_tool(tool_name: String) -> void:
	if world_tools != null and world_tools.has_method("set_tool_from_action"):
		world_tools.call("set_tool_from_action", "tool_" + tool_name)

func _activate_wall_tool() -> void:
	if _wall_tool == null:
		return
	if _wall_tool.has_method("set_snap_grid"):
		_wall_tool.call("set_snap_grid", 0.5 if _grid_snap else 0.01)
	if _wall_tool.has_method("set_segment_height") and world_tools != null and world_tools.has_method("get_settings"):
		var settings: Dictionary = world_tools.call("get_settings")
		_wall_tool.call("set_segment_height", float(settings.get("wall_height", 3.4)))
		if _wall_tool.has_method("set_segment_type"):
			_wall_tool.call("set_segment_type", String(settings.get("wall_type", "stone")))
		if _wall_tool.has_method("set_rect_mode_enabled"):
			_wall_tool.call("set_rect_mode_enabled", bool(settings.get("wall_rect_mode", false)))
		if _wall_tool.has_method("set_match_connected_heights_enabled"):
			_wall_tool.call("set_match_connected_heights_enabled", bool(settings.get("wall_match_connected_heights", true)))
		if _wall_tool.has_method("set_rect_foundation_enabled"):
			_wall_tool.call("set_rect_foundation_enabled", bool(settings.get("wall_add_foundation", true)))
		if _wall_tool.has_method("set_opening_height_snap_enabled"):
			_wall_tool.call("set_opening_height_snap_enabled", bool(settings.get("wall_opening_height_snap", true)))
		if _wall_tool.has_method("set_jitter_enabled"):
			_wall_tool.call("set_jitter_enabled", bool(settings.get("wall_jitter", true)))
	if _wall_tool.has_method("activate"):
		_wall_tool.call(
			"activate",
			self,
			Callable(self, "_get_mouse_world_position"),
			Callable(self, "_get_mouse_ray"),
			Callable(self, "_sample_terrain_height"),
			Callable(self, "_set_status")
		)

func _deactivate_wall_tool() -> void:
	if _wall_tool != null and _wall_tool.has_method("deactivate"):
		_wall_tool.call("deactivate")

func _sync_toolbar_tool_state() -> void:
	if world_tools != null and world_tools.has_method("get_current_tool"):
		_on_tool_changed(String(world_tools.call("get_current_tool")))

func _clear_active_tool(reason: String) -> void:
	_cancel_active_interactions()
	_deselect_all_characters()
	_switch_tool("select")
	_set_status(reason)

func _cancel_active_interactions() -> void:
	_is_tool_dragging = false
	_is_stamp_dragging = false
	_stroke_interval_accum = 0.0
	_stamp_drag_interval_accum = 0.0
	_last_stamp_grid_key = Vector2i(999999, 999999)
	_runtime_terrain_editor.end_stroke()

func _route_input_to_characters(event: InputEvent) -> bool:
	if event is not InputEventMouseButton:
		return false

	var hovered: bool = get_viewport().gui_get_hovered_control() != null
	for n in get_tree().get_nodes_in_group("character_controller"):
		if n.has_method("handle_input_event"):
			var used: Variant = n.call("handle_input_event", event, hovered)
			if bool(used):
				return true
	return false

func _reset_characters_on_new_map() -> void:
	for n in get_tree().get_nodes_in_group("character_controller"):
		if n is Node3D:
			var c: Node3D = n as Node3D
			var xz := c.global_position
			var y: float = 0.0
			if _terrain_node != null and _terrain_node.has_method("sample_height"):
				y = float(_terrain_node.call("sample_height", xz.x, xz.z))
			c.global_position = Vector3(xz.x, y, xz.z)
		if n.has_method("initialize_controller"):
			n.call("initialize_controller", camera, _terrain_node)

func _ensure_editor_ui_layout() -> void:
	var editor_canvas := get_node_or_null("EditorCanvas") as CanvasLayer
	if editor_canvas != null:
		editor_canvas.layer = 200

	var root_ui := get_node_or_null("EditorCanvas/RootUI") as Control
	if root_ui == null:
		return
	root_ui.visible = true
	root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_ui.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root_ui.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root_ui.position = Vector2.ZERO

	var layout := get_node_or_null("EditorCanvas/RootUI/Layout") as VBoxContainer
	if layout == null:
		layout = VBoxContainer.new()
		layout.name = "Layout"
		layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root_ui.add_child(layout)
	layout.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layout.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layout.position = Vector2.ZERO

	var menu_panel := get_node_or_null("EditorCanvas/RootUI/Layout/MenuPanel") as PanelContainer
	if menu_panel == null:
		menu_panel = PanelContainer.new()
		menu_panel.name = "MenuPanel"
		menu_panel.custom_minimum_size = Vector2(0.0, 44.0)
		layout.add_child(menu_panel)
	menu_panel.visible = true
	menu_panel.z_index = 100

	if menu_bar == null:
		menu_bar = get_node_or_null("EditorCanvas/RootUI/Layout/MenuPanel/MainMenuBar") as MenuBar
	if menu_bar == null:
		menu_bar = MenuBar.new()
		menu_bar.name = "MainMenuBar"
		menu_bar.unique_name_in_owner = true
		menu_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		menu_bar.offset_bottom = 40.0
		menu_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
		menu_bar.set_script(MENU_BAR_SCRIPT)
		menu_panel.add_child(menu_bar)

	menu_bar.visible = true
	menu_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_bar.z_index = 110
	menu_bar.custom_minimum_size = Vector2(0.0, 40.0)

	if world_tools == null:
		world_tools = get_node_or_null("EditorCanvas/RootUI/Layout/Body/WorldToolsToolbar") as PanelContainer
	if world_tools == null:
		var body := get_node_or_null("EditorCanvas/RootUI/Layout/Body") as HSplitContainer
		if body != null:
			var tools_instance := TOOLBAR_SCENE.instantiate()
			if tools_instance is PanelContainer:
				world_tools = tools_instance as PanelContainer
				world_tools.name = "WorldToolsToolbar"
				body.add_child(world_tools)
	if world_tools != null:
		world_tools.visible = true

	if asset_browser == null:
		asset_browser = get_node_or_null("EditorCanvas/RootUI/Layout/Body/AssetBrowser") as PanelContainer
	if asset_browser == null:
		var body2 := get_node_or_null("EditorCanvas/RootUI/Layout/Body") as HSplitContainer
		if body2 != null:
			var browser_instance := ASSET_BROWSER_SCENE.instantiate()
			if browser_instance is PanelContainer:
				asset_browser = browser_instance as PanelContainer
				asset_browser.name = "AssetBrowser"
				body2.add_child(asset_browser)
	if asset_browser != null:
		asset_browser.visible = true

func _capture_full_editor_screenshot(reason: String = "manual") -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	# Capture composited viewport first so UI chrome (menu + toolbars + viewport) is guaranteed in-frame.
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		image = _capture_window_image()
	if image == null:
		_set_status("Screenshot failed: no image available")
		return

	var user_abs: String = ProjectSettings.globalize_path(USER_SCREENSHOT_PATH)
	var res_abs: String = ProjectSettings.globalize_path(RES_SCREENSHOT_PATH)
	var user_ok: bool = image.save_png(user_abs) == OK
	var res_ok: bool = image.save_png(res_abs) == OK
	var screen_image: Image = _capture_window_image()
	if screen_image != null:
		screen_image.save_png(ProjectSettings.globalize_path("user://full_editor_screen_capture.png"))
	if user_ok or res_ok:
		_set_status("Saved full editor screenshot (%s)" % reason)
		print("[PaperVTT] Screenshot saved: %s | %s" % [user_abs, res_abs])
	else:
		_set_status("Screenshot failed to save")

func _capture_window_image() -> Image:
	var screen_idx: int = DisplayServer.window_get_current_screen()
	var screen_image: Image = DisplayServer.screen_get_image(screen_idx)
	if screen_image == null:
		return null
	var window_pos: Vector2i = DisplayServer.window_get_position()
	var window_size: Vector2i = DisplayServer.window_get_size()
	if window_size.x <= 0 or window_size.y <= 0:
		return screen_image

	var x0: int = clampi(window_pos.x, 0, max(screen_image.get_width() - 1, 0))
	var y0: int = clampi(window_pos.y, 0, max(screen_image.get_height() - 1, 0))
	var max_w: int = max(screen_image.get_width() - x0, 1)
	var max_h: int = max(screen_image.get_height() - y0, 1)
	var crop_w: int = clampi(window_size.x, 1, max_w)
	var crop_h: int = clampi(window_size.y, 1, max_h)
	return screen_image.get_region(Rect2i(x0, y0, crop_w, crop_h))

func _toggle_postfx() -> void:
	if postfx_canvas.has_method("set_enabled"):
		postfx_canvas.call("set_enabled", not bool(postfx_canvas.get("enabled")))
		_set_status("PostFX: %s" % ("On" if bool(postfx_canvas.get("enabled")) else "Off"))
	else:
		postfx_canvas.visible = not postfx_canvas.visible
		_set_status("PostFX visibility toggled")

func _set_performance_mode(enabled: bool) -> void:
	_performance_mode = enabled
	if postfx_canvas.has_method("set_performance_mode"):
		postfx_canvas.call("set_performance_mode", _performance_mode)
	if _performance_mode:
		_set_lightweight_postfx(true, false)
	if not _performance_mode:
		_set_ultra_performance_mode(false, false)
	if not _post_process_disabled and postfx_canvas.has_method("set_enabled"):
		postfx_canvas.call("set_enabled", true)
	_apply_editor_render_budget()
	_set_status("Performance Mode: %s" % ("On" if _performance_mode else "Off"))

func _set_ultra_performance_mode(enabled: bool, announce: bool = true) -> void:
	_ultra_performance_mode = enabled
	if postfx_canvas.has_method("set_ultra_performance_mode"):
		postfx_canvas.call("set_ultra_performance_mode", _ultra_performance_mode)
	if _ultra_performance_mode:
		_performance_mode = true
		if postfx_canvas.has_method("set_performance_mode"):
			postfx_canvas.call("set_performance_mode", true)
		_set_lightweight_postfx(true, false)
	_apply_editor_render_budget()
	if announce:
		_set_status("Ultra Performance: %s" % ("On" if _ultra_performance_mode else "Off"))

func _set_lightweight_postfx(enabled: bool, announce: bool = true) -> void:
	_lightweight_postfx = enabled
	if postfx_canvas.has_method("set_lightweight_mode"):
		postfx_canvas.call("set_lightweight_mode", _lightweight_postfx)
	if announce:
		_set_status("Lightweight PostFX: %s" % ("On" if _lightweight_postfx else "Off"))

func _set_post_process_disabled(disabled: bool) -> void:
	_post_process_disabled = disabled
	if postfx_canvas.has_method("set_enabled"):
		postfx_canvas.call("set_enabled", not _post_process_disabled)
	_apply_editor_render_budget()
	_set_status("Post-Process: %s" % ("Disabled" if _post_process_disabled else "Enabled"))

func _apply_editor_optimization_preset(announce: bool = true) -> void:
	_lightweight_editor_mode = true
	OS.set_low_processor_usage_mode(true)
	OS.set_low_processor_usage_mode_sleep_usec(0)
	Engine.set_max_fps(0)
	_set_performance_mode(true)
	_set_ultra_performance_mode(true, false)
	_set_post_process_disabled(true)
	_apply_editor_render_budget()
	if announce:
		_set_status("Editor Optimization Preset applied")

func _apply_editor_render_budget() -> void:
	if not _is_editor_runtime or sun_light == null:
		return
	var viewport := get_viewport()
	if _post_process_disabled or _ultra_performance_mode:
		sun_light.shadow_enabled = false
		sun_light.directional_shadow_max_distance = 0.0
		camera.far = 90.0
		if viewport != null:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = 0.5
			viewport.mesh_lod_threshold = 6.0
	elif _performance_mode:
		sun_light.shadow_enabled = true
		sun_light.directional_shadow_max_distance = 70.0
		camera.far = 120.0
		if viewport != null:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = 0.67
			viewport.mesh_lod_threshold = 4.0
	else:
		sun_light.shadow_enabled = true
		sun_light.directional_shadow_max_distance = 160.0
		camera.far = 220.0
		if viewport != null:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = 1.0
			viewport.mesh_lod_threshold = 2.25

func _update_performance_overlay() -> void:
	if perf_label == null:
		return
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var draw_calls: float = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var mode := "Normal"
	if _post_process_disabled:
		mode = "PostFX Off"
	elif _ultra_performance_mode:
		mode = "Ultra"
	elif _performance_mode:
		mode = "Performance"
	var viewport_scale: float = get_viewport().scaling_3d_scale
	perf_label.text = "FPS: %d\nDraw Calls: %d\nMode: %s\nTool: %s\nViewport: %.2f" % [int(round(fps)), int(round(draw_calls)), mode, _format_tool_name(_current_tool), viewport_scale]

func _update_active_tool_feedback() -> void:
	if viewport_hint == null:
		return
	match _current_tool:
		"select":
			viewport_hint.text = "Mode: Select / None | LMB select character | Empty click clears selection | Esc clears tool"
		"wall":
			viewport_hint.text = "Mode: Smart Wall | LMB chain draw | Ctrl rectangle drag | Shift square (rectangle) / edit (idle) | RMB opening menu | Ctrl+Z undo"
		"stamp":
			var prefab_name := "Pick prefab" if _selected_prefab == "" else _selected_prefab.get_file().get_basename()
			viewport_hint.text = "Mode: Stamp | %s | LMB place | RMB/Q/E rotate | Esc clears tool" % prefab_name
		"raise", "lower", "smooth", "flatten", "paint":
			viewport_hint.text = "Mode: %s | Hold LMB to sculpt | Brush %.1f | Strength %.2f | Esc clears tool" % [_format_tool_name(_current_tool), _brush_size, _brush_strength]
		"grasspaint", "grasserase":
			viewport_hint.text = "Mode: %s | Hold LMB to paint | Radius %.1f | Density %.2f | Esc clears tool" % [_format_tool_name(_current_tool), _brush_size, _brush_strength]
		_:
			viewport_hint.text = "Mode: %s" % _format_tool_name(_current_tool)

func _format_tool_name(tool_name: String) -> String:
	match tool_name:
		"grasspaint":
			return "Grass Paint"
		"grasserase":
			return "Grass Erase"
		"wall":
			return "Smart Wall"
		"select":
			return "Select / None"
		_:
			return tool_name.capitalize()

func _stamp_at_mouse(is_drag_pass: bool) -> void:
	if _selected_prefab == "":
		if not is_drag_pass:
			_set_status("Pick a prefab in the asset browser first")
		return

	var hit: Variant = _get_mouse_world_position()
	if hit == null:
		return

	var packed: PackedScene = load(_selected_prefab) as PackedScene
	if packed == null:
		_set_status("Failed to load prefab: %s" % _selected_prefab)
		return

	var instance := packed.instantiate()
	if not (instance is Node3D):
		_set_status("Prefab root is not Node3D: %s" % _selected_prefab)
		instance.queue_free()
		return

	var place_pos: Vector3 = hit as Vector3
	var grid_key := Vector2i(int(round(place_pos.x)), int(round(place_pos.z)))
	if _grid_snap:
		place_pos.x = round(place_pos.x)
		place_pos.z = round(place_pos.z)
		place_pos.y = _sample_terrain_height(place_pos.x, place_pos.z)
		if is_drag_pass and grid_key == _last_stamp_grid_key:
			instance.queue_free()
			return

	stamp_root.add_child(instance)
	var placed: Node3D = instance as Node3D
	placed.set_meta("prefab_path", _selected_prefab)
	placed.global_position = place_pos
	placed.rotation.y = deg_to_rad(_stamp_rotation_deg)
	_apply_prefab_scale_override(placed, _selected_prefab)
	_apply_prefab_runtime_optimizations(placed, _selected_prefab)
	_ensure_prefab_has_collision(placed)
	_last_stamp_grid_key = Vector2i(int(round(place_pos.x)), int(round(place_pos.z)))
	if not is_drag_pass:
		_set_status("Stamped: %s" % _selected_prefab.get_file())

func _begin_tool_stroke() -> void:
	var hit: Variant = _get_mouse_world_position()
	if hit == null:
		return
	_is_tool_dragging = true
	_stroke_interval_accum = 0.0
	if _current_tool.begins_with("grass"):
		if _grass_system != null and _grass_system.has_method("apply_brush"):
			_grass_system.call("apply_brush", _current_tool, hit as Vector3, _brush_size, _brush_strength)
		return
	_runtime_terrain_editor.set_tool(_current_tool, _brush_size, _brush_strength, _flatten_height)
	_runtime_terrain_editor.begin_stroke(hit as Vector3)

func _continue_tool_stroke() -> void:
	var hit: Variant = _get_mouse_world_position()
	if hit == null:
		return
	if _current_tool.begins_with("grass"):
		if _grass_system != null and _grass_system.has_method("apply_brush"):
			_grass_system.call("apply_brush", _current_tool, hit as Vector3, _brush_size, _brush_strength)
		return
	_runtime_terrain_editor.continue_stroke(hit as Vector3, camera.rotation.y)

func _get_mouse_world_position() -> Variant:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if DisplayServer.get_name() == "headless":
		return _ray_plane_intersection(origin, direction, 0.0)

	if _terrain_node != null and _terrain_node.has_method("get_intersection"):
		var p: Variant = _terrain_node.call("get_intersection", origin, direction, true)
		if p is Vector3:
			var point: Vector3 = p
			if is_nan(point.y) or point.z > 3.0e38:
				return _ray_plane_intersection(origin, direction, 0.0)
			return point

	return _ray_plane_intersection(origin, direction, 0.0)

func _ray_plane_intersection(origin: Vector3, direction: Vector3, y_height: float) -> Variant:
	if absf(direction.y) < 0.0001:
		return null
	var t := (y_height - origin.y) / direction.y
	if t < 0.0:
		return null
	return origin + direction * t

func _get_mouse_ray() -> Dictionary:
	var mouse := get_viewport().get_mouse_position()
	return {
		"origin": camera.project_ray_origin(mouse),
		"direction": camera.project_ray_normal(mouse)
	}

func _show_about_dialog() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "About PaperVTT"
	dlg.dialog_text = "PaperVTT\nTabletop map editor built in Godot 4.7\n\nDesigned for fast in-editor terrain sculpting,\nprefab stamping, and pen-and-ink rendering."
	dlg.size = Vector2i(400, 180)
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)

func _set_status(message: String) -> void:
	status_label.text = message
	print("[PaperVTT] %s" % message)

func _setup_preview_nodes() -> void:
	_stamp_preview = Node3D.new()
	_stamp_preview.name = "StampPreview"
	add_child(_stamp_preview)
	_stamp_preview.visible = false

	_brush_preview = MeshInstance3D.new()
	_brush_preview.name = "BrushPreview"
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.0
	ring.height = 0.04
	ring.radial_segments = 32
	ring.rings = 1
	_brush_preview.mesh = ring
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 0.8, 1.0, 0.22)
	mat.emission_enabled = true
	mat.emission = Color(0.15, 0.8, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.55
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_brush_preview.material_override = mat
	add_child(_brush_preview)
	_brush_preview.visible = false

func _update_live_previews() -> void:
	var hit: Variant = _get_mouse_world_position()
	if hit == null:
		if _stamp_preview != null:
			_stamp_preview.visible = false
		if _brush_preview != null:
			_brush_preview.visible = false
		return

	var point: Vector3 = hit as Vector3
	_update_stamp_preview(point)
	_update_brush_preview(point)

func _update_stamp_preview(world_pos: Vector3) -> void:
	if _stamp_preview == null:
		return
	if _current_tool != "stamp" or _selected_prefab == "":
		_stamp_preview.visible = false
		return
	if _stamp_preview.get_child_count() == 0:
		_rebuild_stamp_preview()
	if _stamp_preview.get_child_count() == 0:
		_stamp_preview.visible = false
		return

	var preview_pos := world_pos
	if _grid_snap:
		preview_pos.x = round(preview_pos.x)
		preview_pos.z = round(preview_pos.z)
	_stamp_preview.global_position = preview_pos
	_stamp_preview.rotation.y = deg_to_rad(_stamp_rotation_deg)
	_stamp_preview.visible = true

func _update_brush_preview(world_pos: Vector3) -> void:
	if _brush_preview == null:
		return
	if _current_tool == "stamp" or _current_tool == "wall":
		_brush_preview.visible = false
		return
	_brush_preview.visible = true
	_brush_preview.global_position = world_pos + Vector3(0.02, 0.02, 0.02)
	_brush_preview.scale = Vector3(_brush_size, 1.0, _brush_size)

func _rotate_stamp_preview(delta_deg: float) -> void:
	_stamp_rotation_deg = fmod(_stamp_rotation_deg + delta_deg + 360.0, 360.0)
	_set_status("Stamp rotation: %d deg" % int(_stamp_rotation_deg))

func _rebuild_stamp_preview() -> void:
	if _stamp_preview == null:
		return
	for child in _stamp_preview.get_children():
		child.queue_free()
	if _selected_prefab == "":
		return

	var packed: PackedScene = load(_selected_prefab) as PackedScene
	if packed == null:
		return
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return
	_apply_prefab_scale_override(inst as Node3D, _selected_prefab)
	_stamp_preview.add_child(inst)
	_apply_ghost_look(inst)

func _apply_ghost_look(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var ghost_mat := StandardMaterial3D.new()
		ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost_mat.albedo_color = Color(0.3, 0.95, 1.0, 0.35)
		ghost_mat.emission_enabled = true
		ghost_mat.emission = Color(0.45, 1.0, 1.0, 1.0)
		ghost_mat.emission_energy_multiplier = 0.8
		ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_node.material_overlay = ghost_mat

	for child in node.get_children():
		_apply_ghost_look(child)

func _load_terrain_extension() -> void:
	# No-op: terrain now uses a built-in custom heightmap scene.
	pass

func _configure_visible_terrain() -> void:
	if _terrain_node == null:
		return
	if _terrain_node.has_method("set_vertex_spacing"):
		_terrain_node.call("set_vertex_spacing", 2.0 if _lightweight_editor_mode else 1.0)

func _seed_default_prefabs() -> void:
	_room_prefabs.clear()
	_nature_prefabs.clear()
	_seed_prefab_paths = _choose_seed_prefabs()
	if _seed_prefab_paths.is_empty() or _room_prefabs.is_empty():
		if not _seed_prefab_paths.is_empty() and _room_prefabs.is_empty():
			_room_prefabs.append(_seed_prefab_paths[0])
		else:
			return
	# Keep starter content extremely lean in editor optimization mode.
	var room_size: float = 18.0
	var side_wall_count: int = 0 if _lightweight_editor_mode else 1
	for i in range(side_wall_count):
		var path: String = _room_prefabs[i % _room_prefabs.size()]
		_place_prefab_direct(path, Vector3(-room_size, 0.0, -6.0 + i * 12.0), 90.0)
		_place_prefab_direct(path, Vector3(room_size, 0.0, -6.0 + i * 12.0), -90.0)
	for i in range(1):
		var path_front: String = _room_prefabs[(i + 1) % _room_prefabs.size()]
		_place_prefab_direct(path_front, Vector3(0.0, 0.0, -room_size), 0.0)
		if not _lightweight_editor_mode:
			_place_prefab_direct(path_front, Vector3(0.0, 0.0, room_size), 180.0)

	# 1-2 nature props around the room for depth cues without excess draw calls.
	if not _nature_prefabs.is_empty():
		_place_prefab_direct(_nature_prefabs[0], Vector3(-28.0, 0.0, -24.0), 0.0)
		if not _performance_mode and not _lightweight_editor_mode:
			_place_prefab_direct(_nature_prefabs[_nature_prefabs.size() - 1], Vector3(26.0, 0.0, -20.0), 35.0)
	_spawn_starter_tree_cluster_multimesh(Vector3(22.0, 0.0, 18.0))

func _choose_seed_prefabs() -> Array[String]:
	var all: Array[String] = []
	_collect_prefabs("res://assets/prefabs", all)
	if all.is_empty():
		return []

	var picks: Array[String] = []
	var desired := ["/walls/", "/walls/", "/walls/", "/nature/trees/", "/nature/trees/"]
	for key in desired:
		var candidate: String = ""
		for p in all:
			if p.to_lower().contains(key):
				candidate = p
				break
		if candidate == "" and key == "/nature/trees/":
			for p in all:
				if p.to_lower().contains("/nature/"):
					candidate = p
					break
		if candidate != "" and not picks.has(candidate):
			picks.append(candidate)
			if key == "/walls/":
				_room_prefabs.append(candidate)
			elif key == "/nature/trees/":
				_nature_prefabs.append(candidate)

	if picks.size() < 4:
		for p in all:
			if not picks.has(p):
				picks.append(p)
				if p.to_lower().contains("/walls/"):
					_room_prefabs.append(p)
				elif p.to_lower().contains("/nature/"):
					_nature_prefabs.append(p)
			if picks.size() >= 4:
				break
	return picks

func _collect_prefabs(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full := "%s/%s" % [path, name]
		if dir.current_is_dir():
			_collect_prefabs(full, out)
		elif name.ends_with(".tscn"):
			out.append(full)
	dir.list_dir_end()

func _place_prefab_direct(prefab_path: String, position_hint: Vector3, rotation_deg: float, parent_override: Node3D = null, extra_scale: Vector3 = Vector3.ONE) -> Node3D:
	var packed: PackedScene = load(prefab_path) as PackedScene
	if packed == null:
		return null
	var inst: Node = packed.instantiate()
	if not (inst is Node3D):
		inst.queue_free()
		return null
	var target_parent: Node3D = parent_override if parent_override != null else stamp_root
	target_parent.add_child(inst)
	var node3d := inst as Node3D
	node3d.set_meta("prefab_path", prefab_path)
	var y := _sample_terrain_height(position_hint.x, position_hint.z)
	node3d.global_position = Vector3(position_hint.x, y, position_hint.z)
	node3d.rotation.y = deg_to_rad(rotation_deg)
	_apply_prefab_scale_override(node3d, prefab_path)
	if prefab_path.to_lower().contains("/walls/"):
		node3d.scale *= Vector3(1.35, 1.35, 1.35)
	elif prefab_path.to_lower().contains("/nature/"):
		node3d.scale *= Vector3(1.15, 1.15, 1.15)
	node3d.scale *= extra_scale
	_apply_prefab_runtime_optimizations(node3d, prefab_path)
	_ensure_prefab_has_collision(node3d)
	return node3d

func _ensure_prefab_has_collision(root: Node3D) -> void:
	if root == null or _has_physics_body(root):
		return
	var world_aabb_list: Array[AABB] = []
	_accumulate_world_aabb(root, world_aabb_list)
	if world_aabb_list.is_empty():
		return
	var aabb: AABB = world_aabb_list[0]
	if aabb.size.length_squared() < 0.0001:
		return
	var static_body := StaticBody3D.new()
	static_body.name = "AutoCollision"
	var col_shape := CollisionShape3D.new()
	col_shape.name = "AutoCollisionShape"
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(aabb.size.x, 0.1), maxf(aabb.size.y, 0.1), maxf(aabb.size.z, 0.1))
	col_shape.shape = box
	static_body.add_child(col_shape)
	stamp_root.add_child(static_body)
	static_body.global_position = aabb.get_center()

func _has_physics_body(node: Node) -> bool:
	if node is StaticBody3D or node is RigidBody3D:
		return true
	for child in node.get_children():
		if _has_physics_body(child):
			return true
	return false

func _accumulate_world_aabb(node: Node, out: Array[AABB]) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var waabb: AABB = mi.global_transform * mi.get_aabb()
			if out.is_empty():
				out.append(waabb)
			else:
				out[0] = out[0].merge(waabb)
	for child in node.get_children():
		_accumulate_world_aabb(child, out)

func _apply_prefab_scale_override(node3d: Node3D, prefab_path: String) -> void:
	if node3d == null or asset_browser == null:
		return
	if asset_browser.has_method("get_scale_for_prefab"):
		var scale_value: Variant = asset_browser.call("get_scale_for_prefab", prefab_path)
		if scale_value is Vector3:
			node3d.scale *= (scale_value as Vector3)

func _apply_prefab_runtime_optimizations(node3d: Node3D, prefab_path: String) -> void:
	var visibility_end: float = PREFAB_VISIBILITY_END_FAR_EDITOR if _lightweight_editor_mode else PREFAB_VISIBILITY_END_FAR
	if prefab_path.to_lower().contains("/nature/"):
		visibility_end = PREFAB_VISIBILITY_END_NEAR_EDITOR if _lightweight_editor_mode else PREFAB_VISIBILITY_END_NEAR
	_apply_visibility_range_recursive(node3d, visibility_end)

func _apply_visibility_range_recursive(node: Node, visibility_end: float) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.visibility_range_begin = 0.0
		gi.visibility_range_end = visibility_end
		gi.visibility_range_end_margin = 18.0
	for child in node.get_children():
		_apply_visibility_range_recursive(child, visibility_end)

func _spawn_starter_tree_cluster_multimesh(center: Vector3) -> void:
	var tree_count: int = 2 if _lightweight_editor_mode else (3 if _ultra_performance_mode else (5 if _performance_mode else STARTER_TREE_CLUSTER_COUNT))
	if tree_count <= 0:
		return
	var cluster := Node3D.new()
	cluster.name = "StarterTreeCluster"
	stamp_root.add_child(cluster)

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.13
	trunk_mesh.bottom_radius = 0.21
	trunk_mesh.height = 1.8

	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.31, 0.2, 0.12, 1.0)

	var canopy_mesh := SphereMesh.new()
	canopy_mesh.radius = 0.86
	canopy_mesh.height = 1.7

	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.2, 0.44, 0.23, 1.0)

	var trunk_mmi := MultiMeshInstance3D.new()
	trunk_mmi.name = "Trunks"
	trunk_mmi.material_override = trunk_mat
	cluster.add_child(trunk_mmi)

	var canopy_mmi := MultiMeshInstance3D.new()
	canopy_mmi.name = "Canopies"
	canopy_mmi.material_override = canopy_mat
	cluster.add_child(canopy_mmi)

	var trunk_mm := MultiMesh.new()
	trunk_mm.mesh = trunk_mesh
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.instance_count = tree_count
	trunk_mmi.multimesh = trunk_mm

	var canopy_mm := MultiMesh.new()
	canopy_mm.mesh = canopy_mesh
	canopy_mm.transform_format = MultiMesh.TRANSFORM_3D
	canopy_mm.instance_count = tree_count
	canopy_mmi.multimesh = canopy_mm

	for i in range(tree_count):
		var angle: float = (TAU / float(tree_count)) * float(i)
		var radius: float = 8.0 + (float(i % 3) * 2.8)
		var x: float = center.x + cos(angle) * radius
		var z: float = center.z + sin(angle) * radius
		var y: float = _sample_terrain_height(x, z)
		var sway: float = sin(float(i) * 1.7) * 0.22
		var trunk_xf := Transform3D(Basis().rotated(Vector3.UP, sway), Vector3(x, y + 0.9, z))
		var canopy_xf := Transform3D(Basis().rotated(Vector3.UP, sway), Vector3(x, y + 2.3, z))
		trunk_mm.set_instance_transform(i, trunk_xf)
		canopy_mm.set_instance_transform(i, canopy_xf)

	_apply_visibility_range_recursive(cluster, PREFAB_VISIBILITY_END_NEAR)

func _sample_terrain_height(x: float, z: float) -> float:
	if _terrain_node != null and _terrain_node.has_method("sample_height"):
		return float(_terrain_node.call("sample_height", x, z))
	if _terrain_node != null and _terrain_node.has_method("get_data"):
		var data: Variant = _terrain_node.call("get_data")
		if data != null and data is Object and (data as Object).has_method("get_height"):
			var h: Variant = (data as Object).call("get_height", Vector3(x, 0.0, z))
			if h is float:
				return h
			if h is int:
				return float(h)
	return 0.0

func _ensure_terrain_node() -> Node:
	if CUSTOM_TERRAIN_SCENE != null:
		var custom_node: Node = CUSTOM_TERRAIN_SCENE.instantiate()
		if custom_node != null:
			custom_node.name = "TerrainRuntime"
			terrain_placeholder.add_child(custom_node)
			return custom_node

	# Fallback to a visible plane so map editing flow still works if Terrain3D is unavailable.
	var ground := MeshInstance3D.new()
	ground.name = "FallbackGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(256, 256)
	ground.mesh = plane
	terrain_placeholder.add_child(ground)
	return terrain_placeholder

func _focus_camera_on_seed_content() -> void:
	if camera_manager == null:
		return
	if camera_manager.has_method("set_top_down_default"):
		camera_manager.call("set_top_down_default")
	if camera_manager.has_method("recenter"):
		camera_manager.call("recenter")

func _get_or_create_wall_system() -> Node:
	var existing: Node = get_node_or_null("WallSystem")
	if existing != null:
		return existing
	var wall_system := Node3D.new()
	wall_system.name = "WallSystem"
	var wall_system_script: Script = load("res://map/walls/wall_system.gd")
	if wall_system_script != null:
		wall_system.set_script(wall_system_script)
	add_child(wall_system)
	return wall_system

func _save_map_to_path(path: String) -> bool:
	var abs_dir: String = ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var data: Dictionary = {
		"version": 2,
		"saved_at": Time.get_datetime_string_from_system(true, true),
		"walls": {},
		"stamps": [],
		"terrain": {}
	}
	var wall_system: Node = _get_or_create_wall_system()
	if wall_system != null and wall_system.has_method("save_data"):
		data["walls"] = wall_system.call("save_data")
	data["stamps"] = _serialize_stamp_instances()
	data["terrain"] = _serialize_terrain_data()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Save failed: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_set_status("Saved map: %s (walls %d, stamps %d)" % [path, int((data["walls"] as Dictionary).get("segments", []).size()), (data["stamps"] as Array).size()])
	return true

func _load_map_from_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is not Dictionary:
		_set_status("Load failed: invalid map format")
		return false
	_create_new_flat_map(false)
	var data: Dictionary = parsed
	var wall_data: Dictionary = data.get("walls", {})
	var stamp_data: Array = data.get("stamps", [])
	var terrain_data: Dictionary = data.get("terrain", {})
	var wall_system: Node = _get_or_create_wall_system()
	if wall_system != null and wall_system.has_method("load_data"):
		wall_system.call("load_data", wall_data)
	_deserialize_stamp_instances(stamp_data)
	_deserialize_terrain_data(terrain_data)
	_set_status("Loaded map: %s" % path)
	return true

func _serialize_stamp_instances() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child in stamp_root.get_children():
		if child is not Node3D:
			continue
		var n: Node3D = child as Node3D
		var prefab_path: String = ""
		if n.has_meta("prefab_path"):
			prefab_path = String(n.get_meta("prefab_path"))
		if prefab_path == "":
			prefab_path = n.scene_file_path
		if prefab_path == "":
			continue
		out.append({
			"prefab_path": prefab_path,
			"position": [n.global_position.x, n.global_position.y, n.global_position.z],
			"rotation": [n.rotation.x, n.rotation.y, n.rotation.z],
			"scale": [n.scale.x, n.scale.y, n.scale.z]
		})
	return out

func _deserialize_stamp_instances(items: Array) -> void:
	for item in items:
		if item is not Dictionary:
			continue
		var d: Dictionary = item
		var prefab_path: String = String(d.get("prefab_path", ""))
		if prefab_path == "":
			continue
		var packed: PackedScene = load(prefab_path) as PackedScene
		if packed == null:
			continue
		var inst: Node = packed.instantiate()
		if inst is not Node3D:
			inst.queue_free()
			continue
		var n: Node3D = inst as Node3D
		n.set_meta("prefab_path", prefab_path)
		stamp_root.add_child(n)
		n.global_position = _arr_to_vec3(d.get("position", [0.0, 0.0, 0.0]))
		n.rotation = _arr_to_vec3(d.get("rotation", [0.0, 0.0, 0.0]))
		n.scale = _arr_to_vec3(d.get("scale", [1.0, 1.0, 1.0]))
		_apply_prefab_runtime_optimizations(n, prefab_path)
		_ensure_prefab_has_collision(n)

func _serialize_terrain_data() -> Dictionary:
	if _terrain_node != null and _terrain_node.has_method("serialize_state"):
		var state: Variant = _terrain_node.call("serialize_state")
		if state is Dictionary:
			return state
	return {}

func _deserialize_terrain_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	if _terrain_node != null and _terrain_node.has_method("load_state"):
		_terrain_node.call("load_state", data)

func _arr_to_vec3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO
