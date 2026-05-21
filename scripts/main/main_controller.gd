extends Node3D

signal sky_state_changed(time_hours: float, weather_id: String)

const OriginShiftSystemScript: Script = preload("res://scripts/world/origin_shift_system.gd")
const DistantHorizonSystemScript: Script = preload("res://scripts/world/distant_horizon_system.gd")
# TerrainTexturePainterClass — removed (legacy terrain migration)
# WaterSystemScript — removed (legacy water migration)

@onready var terrain_placeholder: Node3D = $Terrain
@onready var camera: Camera3D = $Camera3D
@onready var camera_manager: Node = %CameraManager
@onready var stamp_root: Node3D = $StampRoot
@onready var menu_bar: MenuBar = %MainMenuBar
@onready var world_tools: PanelContainer = %WorldToolsToolbar
@onready var asset_browser: PanelContainer = %AssetBrowser
@onready var status_label: Label = %StatusLabel
@onready var postfx_canvas: CanvasLayer = get_node_or_null("PostProcessCanvas") as CanvasLayer
@onready var perf_label: Label = %PerfLabel
@onready var viewport_hint: Label = $EditorCanvas/RootUI/Layout/Body/CenterSpacer/ViewportHint
@onready var optimize_button: Button = %OptimizeButton
@onready var sky_3d: Node = get_node_or_null("Sky3D")
@onready var sun_light: DirectionalLight3D = get_node_or_null("Sky3D/SunLight") as DirectionalLight3D
@onready var time_weather_panel: Control = %TimeWeatherPanel
@onready var time_of_day_lighting: Node = get_node_or_null("LightingManager")

@export var use_chunked_terrain: bool = true
@export var debug_draw_chunk_borders: bool = false
@export var debug_draw_chunk_borders_red: bool = false
@export var debug_highlight_problem_borders: bool = false

var _runtime_terrain_editor = TerrainRuntimeEditor.new()
var _selected_prefab: String = ""
var _current_tool: String = "stamp"
var _brush_size: float = 10.0
var _brush_strength: float = 0.25
var _brush_softness: float = 0.42
var _brush_mode: String = "smooth"  # "smooth" or "sharp" - controlled by Shift+LMB
var _smooth_post_pass_enabled: bool = true
var _smooth_post_pass_strength: float = 0.12
var _flatten_height: float = 0.0
var _grid_snap: bool = true
var _is_tool_dragging: bool = false
var _terrain_node: Node = null
var _grass_system: Node3D = null
var _scatter_system: Node3D = null
var _water_system: Node = null
var _active_river_id: int = -1
var _river_width: float = 5.0
var _river_flow_speed: float = 0.24
var _river_average_depth: float = 15.0
var _water_color: Color = Color(0.14, 0.50, 0.56, 1.0)
var _water_mode: String = "river"
var _active_world_layer: int = 0
var _river_handle_root: Node3D = null
var _river_point_handles: Array[Dictionary] = []
var _dragging_river_handle: bool = false
var _drag_river_id: int = -1
var _drag_point_index: int = -1
var _selected_river_id: int = -1
var _selected_river_point_index: int = -1
var _river_preview_node: MeshInstance3D = null
var _texture_painter: RefCounted = null
var _selected_texture_id: String = ""
var _texture_tile_size: float = 4.0
var _texture_density: float = 0.75
var _texture_perf_mode: bool = true
var _texture_brush_shape_mode: String = "circle"
var _texture_shape_variation: float = 0.35
var _texture_edge_softness: float = 0.78
var _texture_coverage_limit: float = 0.75
var _texture_random_rotation: float = 30.0
var _texture_scale_variation: float = 0.15
var _texture_exposure: float = 0.95
var _texture_stroke_offset: Vector2 = Vector2.ZERO
var _texture_stroke_rotation: float = 0.0
var _texture_stroke_scale: float = 1.0
var _texture_stroke_seed: float = 0.0
var _texture_stroke_shape_variant: int = 0
var _cliff_mode: bool = false
var _overhang_amount: float = 0.3
var _scatter_density: float = 1.2
var _scatter_scale_min: float = 0.85
var _scatter_scale_max: float = 1.35
var _scatter_rotation_randomness: float = 180.0
var _scatter_tilt: float = 8.0
var _stamp_rotation_deg: float = 0.0
var _stamp_preview: Node3D = null
var _brush_preview: BrushPreview = null
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

const STROKE_INTERVAL_SEC: float = 1.0 / 70.0
const TEXTURE_STROKE_INTERVAL_SEC: float = 1.0 / 55.0
const TEXTURE_STROKE_INTERVAL_PERF_SEC: float = 1.0 / 34.0
const STAMP_DRAG_INTERVAL_SEC: float = 1.0 / 16.0
## Distance (meters) in front of the camera at which Distant Mountains are placed.
const HORIZON_MOUNTAIN_PLACE_DISTANCE: float = 3000.0
const MENU_BAR_SCRIPT: Script = preload("res://scripts/ui/main_menu_bar.gd")
const TOOLBAR_SCENE: PackedScene = preload("res://scenes/ui/WorldToolsToolbar.tscn")
const ASSET_BROWSER_SCENE: PackedScene = preload("res://scenes/ui/AssetBrowser.tscn")
const WORLDBRUSH_RUNTIME_ROOT_SCENE: PackedScene = preload("res://scenes/terrain/WorldBrushRuntimeRoot.tscn")
const WORLDBRUSH_RADIAL_MENU_SCRIPT: Script = preload("res://addons/worldbrush/ui/worldbrush_radial_menu.gd")
const WORLDBRUSH_INSPECTOR_SCRIPT: Script = preload("res://addons/worldbrush/ui/worldbrush_inspector.gd")
const CHUNKED_WORLDBRUSH_SCRIPT: Script = preload("res://addons/worldbrush/chunked_worldbrush.gd")
# CUSTOM_TERRAIN_SCENE — removed (legacy terrain migration)
const DUNGEONDRAFT_IMPORTER_SCRIPT: Script = preload("res://scripts/import/dungeondraft_importer.gd")
# GRASS_SYSTEM_SCRIPT — removed (legacy terrain migration)
# SCATTER_SYSTEM_SCRIPT — removed (legacy scatter migration)
const PLAYER_CHARACTER_SCENE: PackedScene = preload("res://scenes/characters/PlayerCharacter.tscn")
# WALL_TOOL_SCRIPT — removed (legacy wall migration)
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
const ENABLE_TERRABRUSH_EDITOR_RUNTIME: bool = false
const DEFAULT_DUNGEONDRAFT_MAP_PATH: String = "res://dd_testing/test1.dungeondraft_map"
const IMPORT_WALL_TEXTURE_PATH: String = "res://assets/world/textures/materials/kenney_nature-kit/cliff_block_stone_NW.png"
const IMPORT_FLOOR_TEXTURE_PATH: String = "res://assets/world/textures/materials/kenney_nature-kit/stone_smallFlatC.png"
const IMPORT_LIGHT_HEIGHT_OFFSET: float = 1.9
const DEFAULT_MAP_SAVE_PATH: String = "user://maps/papervtt_map.pvt"
const WEATHER_NORMAL: String = "normal"
const WEATHER_RAIN: String = "rain"
const WEATHER_SNOW: String = "snow"
const WEATHER_FOGGY: String = "foggy"
const WEATHER_STORMY: String = "stormy"
const DEFAULT_SUNRISE_HOUR: float = 7.0
const DEFAULT_SUNSET_HOUR: float = 19.0
const BASELINE_SUNRISE_HOUR: float = 6.0
const BASELINE_SUNSET_HOUR: float = 18.0
const SKY_TIME_OFFSET_HOURS: float = (((DEFAULT_SUNRISE_HOUR - BASELINE_SUNRISE_HOUR) + (DEFAULT_SUNSET_HOUR - BASELINE_SUNSET_HOUR)) * 0.5)
const DAY_START_HOUR: float = 7.0
const DAY_END_HOUR: float = 19.0
const AFTERNOON_START_HOUR: float = 10.0
const AFTERNOON_END_HOUR: float = 16.0
const DAY_SUN_ENERGY_MIN: float = 1.8
const DAY_SUN_ENERGY_MAX: float = 2.5
const NIGHT_MOON_ENERGY_MIN: float = 0.15
const NIGHT_MOON_ENERGY_MAX: float = 0.4
const AMBIENT_ENERGY_DAY_MAX: float = 0.58
const AMBIENT_ENERGY_NIGHT_MIN: float = 0.34
const AMBIENT_WARM_DAY: Color = Color(1.0, 0.9098, 0.7529, 1.0)
const AMBIENT_COOL_NIGHT: Color = Color(0.50, 0.56, 0.70, 1.0)
const BRUSH_RADIUS_MIN: float = 1.0
const BRUSH_RADIUS_MAX: float = 80.0
const BRUSH_RADIUS_WHEEL_STEP_MIN: float = 0.5
const BRUSH_RADIUS_WHEEL_STEP_SCALE: float = 0.08
const RADIUS_INDICATOR_DURATION_SEC: float = 0.85

var _dungeondraft_importer: RefCounted = null
var _dd_import_dialog: FileDialog = null
var _import_prefab_paths: Array[String] = []
var _wall_tool = null  # wall tool stub — legacy wall_tool.gd moved to legacy/
var _import_prefab_key_to_path: Dictionary = {}
var _import_wall_material: StandardMaterial3D = null
var _import_floor_material: StandardMaterial3D = null
var _worldbrush_menu: Control = null
var _worldbrush_hold_active: bool = false
var _worldbrush_inspector: Control = null
var _tool_name_display: Label = null
var _radius_indicator_label: Label = null
var _radius_indicator_ttl: float = 0.0
var _brush_mode_label: Label = null
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

## Large-world systems
var _origin_shift_system: Node = null
var _horizon_system: Node3D = null

## Sky + weather state (network-ready and persisted with map data)
var _sky_time_hours: float = 12.0
var _sky_weather: String = "normal"
var _sky_minutes_per_day: float = 15.0
var _weather_tween: Tween = null
var _weather_fx_root: Node3D = null
var _rain_particles: GPUParticles3D = null
var _snow_particles: GPUParticles3D = null

## Environment inspector runtime state
var _time_paused: bool = true
var _time_scale: float = 1.0
var _lighting_override_enabled: bool = false
var _lighting_override_color: Color = Color(1.0, 0.95, 0.86, 1.0)
var _lighting_override_energy: float = 2.2
var _lighting_override_saturation: float = 1.0
var _lighting_override_tint_strength: float = 0.65
var _weather_intensity_global: float = 1.0
var _weather_stacking_enabled: bool = false
var _weather_channel_intensity: Dictionary = {
	"rain": 0.0,
	"snow": 0.0,
	"foggy": 0.0,
	"stormy": 0.0,
}
var _terrain_full_rebuild_mode: bool = false
var _debug_visualize_dirty_rect: bool = false
var _sculpt_mode_active: bool = false
var _lightning_enabled: bool = false
var _lightning_interval: float = 18.0
var _lightning_intensity: float = 2.2
var _lightning_random_variation: bool = true
var _lightning_timer: float = 0.0
var _lightning_flash_timer: float = 0.0
var _lightning_flash_duration: float = 0.22

func _ready() -> void:
	# Fail-safe: keep post-process disabled until full startup completes.
	if postfx_canvas != null and postfx_canvas.has_method("set_enabled"):
		postfx_canvas.call("set_enabled", false)
	_post_process_disabled = true
	if camera != null:
		camera.make_current()

	_setup_sky3d()
	_setup_time_weather_panel()

	_ensure_editor_ui_layout()
	_ensure_worldbrush_menu()
	_ensure_worldbrush_inspector()
	if postfx_canvas != null and postfx_canvas.has_signal("ppf_import_completed"):
		postfx_canvas.connect("ppf_import_completed", Callable(self, "_on_postfx_ppf_import_completed"))
	_ensure_radius_indicator()
	_update_tool_name_display()
	if menu_bar != null:
		menu_bar.action_requested.connect(_on_menu_action_requested)
		_sync_configuration_menu_state()
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
	elif ENABLE_TERRABRUSH_EDITOR_RUNTIME and _get_terrabrush_editor_node() != null:
		_set_status("TerraBrushEditor ready (press V to toggle)")
	else:
		_set_status("Heightmap terrain unavailable; stamping remains active")

	# Grass, scatter, and water systems moved to legacy/ — stubs remain in variables
	
	# Texture Painter — removed (legacy terrain migration)
	
	_ensure_character_setup()

	# --- Large-world systems --------------------------------------------------
	# Extend the camera far plane so distant mountains (thousands of meters
	# away) are always visible.
	camera.far = 100000.0

	# Distant Horizon System — holds procedural low-poly mountain landmarks.
	_horizon_system = Node3D.new()
	_horizon_system.name = "DistantHorizonSystem"
	_horizon_system.set_script(DistantHorizonSystemScript)
	add_child(_horizon_system)

	# Origin Shift System — recenters the world when the camera drifts far.
	_origin_shift_system = Node.new()
	_origin_shift_system.name = "OriginShiftSystem"
	_origin_shift_system.set_script(OriginShiftSystemScript)
	add_child(_origin_shift_system)
	_origin_shift_system.call("setup",
		camera,
		terrain_placeholder,
		stamp_root,
		_scatter_system,
		Callable(self, "_get_or_create_wall_system"),
		_horizon_system)
	# -------------------------------------------------------------------------

	if AUTO_DEBUG_SCREENSHOTS:
		call_deferred("_capture_full_editor_screenshot", "startup")
	if not _load_map_from_path(_current_map_path):
		_create_new_flat_map()
	if DISABLE_CUSTOM_POSTFX_DEFAULT:
		_set_post_process_disabled(true)

func _setup_sky3d() -> void:
	if sky_3d == null:
		_set_status("Sky3D node missing in main scene")
		return
	if sky_3d.has_method("set"):
		sky_3d.set("editor_time_enabled", false)
		sky_3d.set("game_time_enabled", false)
		sky_3d.set("update_interval", 0.05)

	if sky_3d.has_signal("environment_changed") and not sky_3d.environment_changed.is_connected(_on_sky_environment_changed):
		sky_3d.environment_changed.connect(_on_sky_environment_changed)

	if camera != null:
		_refresh_sky_camera_links()

	var dome: Object = sky_3d.get("sky") as Object
	if dome != null:
		if _object_has_property(dome, "sun_disk_size"):
			dome.set("sun_disk_size", 0.0025)
		if _object_has_property(dome, "sun_disk_intensity"):
			dome.set("sun_disk_intensity", 4.0)
		if _object_has_property(dome, "moon_size"):
			dome.set("moon_size", 0.006)
	_apply_time_of_day(_sky_time_hours)
	_apply_day_length(_sky_minutes_per_day)
	_apply_weather_preset(_sky_weather, false)

	sun_light = get_node_or_null("Sky3D/SunLight") as DirectionalLight3D


func _setup_time_weather_panel() -> void:
	if time_weather_panel == null:
		return
	_update_time_weather_visibility()
	if time_weather_panel.has_signal("time_changed") and not time_weather_panel.time_changed.is_connected(_on_time_panel_changed):
		time_weather_panel.time_changed.connect(_on_time_panel_changed)
	if time_weather_panel.has_signal("weather_changed") and not time_weather_panel.weather_changed.is_connected(_on_weather_panel_changed):
		time_weather_panel.weather_changed.connect(_on_weather_panel_changed)
	if time_weather_panel.has_signal("day_length_changed") and not time_weather_panel.day_length_changed.is_connected(_on_day_length_panel_changed):
		time_weather_panel.day_length_changed.connect(_on_day_length_panel_changed)
	if time_weather_panel.has_method("set_time_hours"):
		time_weather_panel.call("set_time_hours", _sky_time_hours)
	if time_weather_panel.has_method("set_weather"):
		time_weather_panel.call("set_weather", _sky_weather)
	if time_weather_panel.has_method("set_day_length_minutes"):
		time_weather_panel.call("set_day_length_minutes", _sky_minutes_per_day)


func _update_time_weather_visibility() -> void:
	if time_weather_panel == null:
		return
	time_weather_panel.visible = true


func _on_time_panel_changed(time_hours: float) -> void:
	_apply_time_of_day(time_hours)
	emit_signal("sky_state_changed", _sky_time_hours, _sky_weather)


func _on_weather_panel_changed(weather_id: String) -> void:
	_apply_weather_preset(weather_id, true)


func _on_day_length_panel_changed(minutes_per_day: float) -> void:
	_apply_day_length(minutes_per_day)


func _on_sky_environment_changed(_env: Environment) -> void:
	_refresh_sky_camera_links()


func _refresh_sky_camera_links() -> void:
	if camera == null or sky_3d == null:
		return
	var env: Environment = sky_3d.get("environment") as Environment
	if env != null:
		camera.environment = env
	var attributes: CameraAttributes = sky_3d.get("camera_attributes") as CameraAttributes
	if attributes != null:
		camera.attributes = attributes


func _time_window_factor(time_hours: float, start_hour: float, end_hour: float) -> float:
	var t: float = fposmod(time_hours, 24.0)
	if t < start_hour or t > end_hour:
		return 0.0
	var mid: float = (start_hour + end_hour) * 0.5
	var half_span: float = maxf((end_hour - start_hour) * 0.5, 0.001)
	return clampf(1.0 - (absf(t - mid) / half_span), 0.0, 1.0)


func _weather_light_multiplier(weather_id: String) -> float:
	match weather_id:
		WEATHER_RAIN:
			return 0.82
		WEATHER_SNOW:
			return 0.86
		WEATHER_FOGGY:
			return 0.74
		WEATHER_STORMY:
			return 0.62
		_:
			return 1.0


func _set_property_if_exists(obj: Object, property_name: String, value: Variant) -> void:
	if obj == null:
		return
	if _object_has_property(obj, property_name):
		obj.set(property_name, value)


func _apply_environment_manager_overrides() -> void:
	if time_of_day_lighting == null:
		return
	if time_of_day_lighting.has_method("set_lighting_override"):
		time_of_day_lighting.call(
			"set_lighting_override",
			_lighting_override_enabled,
			_lighting_override_color,
			_lighting_override_energy,
			_lighting_override_saturation,
			_lighting_override_tint_strength
		)
	if time_of_day_lighting.has_method("set_weather_runtime"):
		time_of_day_lighting.call(
			"set_weather_runtime",
			_weather_intensity_global,
			_weather_stacking_enabled,
			_weather_channel_intensity,
			_sky_weather
		)


func _get_active_weather_ids() -> Array[String]:
	if _weather_stacking_enabled:
		var ids: Array[String] = []
		for key_variant in _weather_channel_intensity.keys():
			var key: String = String(key_variant)
			if float(_weather_channel_intensity.get(key, 0.0)) > 0.01:
				ids.append(key)
		if ids.is_empty():
			ids.append(_sky_weather)
		return ids
	return [_sky_weather]


func _sync_environment_inspector() -> void:
	if _worldbrush_inspector == null:
		return
	var env_state: Dictionary = {
		"time_hours": _sky_time_hours,
		"day_length_minutes": _sky_minutes_per_day,
		"time_paused": _time_paused,
		"time_scale": _time_scale,
		"lighting_override_enabled": _lighting_override_enabled,
		"lighting_override_color": _lighting_override_color,
		"lighting_override_energy": _lighting_override_energy,
		"lighting_override_saturation": _lighting_override_saturation,
		"lighting_override_tint_strength": _lighting_override_tint_strength,
		"weather_intensity_global": _weather_intensity_global,
		"weather_stacking_enabled": _weather_stacking_enabled,
		"weather_channels": _weather_channel_intensity,
		"weather": _sky_weather,
		"full_rebuild_mode": _terrain_full_rebuild_mode,
		"debug_visualize_dirty_rect": _debug_visualize_dirty_rect,
		"lightning_enabled": _lightning_enabled,
		"lightning_interval": _lightning_interval,
		"lightning_intensity": _lightning_intensity,
		"lightning_random_variation": _lightning_random_variation,
		"postfx": postfx_canvas.call("get_live_postfx_state") if postfx_canvas != null and postfx_canvas.has_method("get_live_postfx_state") else {},
	}
	if _worldbrush_inspector.has_method("set_environment_state"):
		_worldbrush_inspector.call("set_environment_state", env_state)
	if _worldbrush_inspector.has_method("set_postfx_state") and postfx_canvas != null and postfx_canvas.has_method("get_live_postfx_state"):
		_worldbrush_inspector.call("set_postfx_state", postfx_canvas.call("get_live_postfx_state"))
	if _worldbrush_inspector.has_method("set_environment_active_weather"):
		_worldbrush_inspector.call("set_environment_active_weather", _get_active_weather_ids())
	if _worldbrush_inspector.has_method("set_postfx_preview_texture") and postfx_canvas != null and postfx_canvas.has_method("get_preview_texture"):
		_worldbrush_inspector.call("set_postfx_preview_texture", postfx_canvas.call("get_preview_texture"))


func _tick_time_of_day(delta: float) -> void:
	if _time_paused:
		return
	var day_seconds: float = maxf(_sky_minutes_per_day, 1.0) * 60.0
	var hours_per_second: float = 24.0 / day_seconds
	_apply_time_of_day(_sky_time_hours + delta * hours_per_second * _time_scale)


func _trigger_lightning_flash() -> void:
	_lightning_flash_duration = randf_range(0.14, 0.30) if _lightning_random_variation else 0.22
	_lightning_flash_timer = _lightning_flash_duration


func _tick_lightning(delta: float) -> void:
	if not _lightning_enabled:
		_lightning_flash_timer = 0.0
		return

	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_trigger_lightning_flash()
		var next_interval: float = _lightning_interval
		if _lightning_random_variation:
			next_interval *= randf_range(0.75, 1.35)
		_lightning_timer = maxf(next_interval, 0.25)

	if _lightning_flash_timer <= 0.0:
		return

	_lightning_flash_timer = maxf(0.0, _lightning_flash_timer - delta)
	var p: float = _lightning_flash_timer / maxf(_lightning_flash_duration, 0.001)
	var envelope: float = sin(p * PI)
	if envelope <= 0.0:
		return

	var flash_energy: float = _lightning_intensity * envelope
	if sun_light != null:
		sun_light.light_energy += flash_energy

	if sky_3d != null and sky_3d.has_method("get") and sky_3d.has_method("set"):
		var base_exposure: float = float(sky_3d.get("tonemap_exposure"))
		sky_3d.set("tonemap_exposure", base_exposure + (0.32 * flash_energy))


func _apply_dynamic_lighting(time_hours: float) -> void:
	_apply_environment_manager_overrides()
	if time_of_day_lighting != null and time_of_day_lighting.has_method("update_lighting"):
		time_of_day_lighting.call("update_lighting", time_hours)
		return

	if sky_3d == null:
		return

	var t: float = fposmod(time_hours, 24.0)
	var day_factor: float = _time_window_factor(time_hours, DAY_START_HOUR, DAY_END_HOUR)
	var afternoon_factor: float = _time_window_factor(time_hours, AFTERNOON_START_HOUR, AFTERNOON_END_HOUR)
	var weather_mult: float = _weather_light_multiplier(_sky_weather)

	var sun_energy: float = lerpf(NIGHT_MOON_ENERGY_MIN, 1.7, day_factor)
	if t >= AFTERNOON_START_HOUR and t <= AFTERNOON_END_HOUR:
		sun_energy = DAY_SUN_ENERGY_MIN + ((DAY_SUN_ENERGY_MAX - DAY_SUN_ENERGY_MIN) * afternoon_factor)
	sun_energy = clampf(sun_energy * weather_mult, NIGHT_MOON_ENERGY_MIN, DAY_SUN_ENERGY_MAX)

	var moon_energy: float = lerpf(NIGHT_MOON_ENERGY_MAX, NIGHT_MOON_ENERGY_MIN, day_factor)
	var tonemap_exposure: float = 0.95 + (0.12 * day_factor) + (0.09 * afternoon_factor)
	tonemap_exposure = lerpf(0.9, tonemap_exposure, weather_mult)

	var ambient_energy: float = lerpf(AMBIENT_ENERGY_NIGHT_MIN, AMBIENT_ENERGY_DAY_MAX, day_factor)
	ambient_energy += 0.03 * afternoon_factor
	ambient_energy = clampf(ambient_energy, 0.25, 0.6)

	_set_property_if_exists(sky_3d, "sun_energy", sun_energy)
	_set_property_if_exists(sky_3d, "moon_energy", moon_energy)
	_set_property_if_exists(sky_3d, "tonemap_exposure", tonemap_exposure)
	_set_property_if_exists(sky_3d, "camera_exposure", 1.0 + (0.18 * day_factor) + (0.12 * afternoon_factor))
	_set_property_if_exists(sky_3d, "skydome_energy", 1.0 + (0.22 * day_factor) + (0.2 * afternoon_factor))
	_set_property_if_exists(sky_3d, "ambient_energy", ambient_energy)
	_set_property_if_exists(sky_3d, "sky_contribution", lerpf(0.62, 0.78, day_factor))

	var dome: Object = sky_3d.get("sky") as Object
	_set_property_if_exists(dome, "sun_disk_intensity", lerpf(5.5, 10.5, day_factor) + (2.2 * afternoon_factor))

	var env: Environment = sky_3d.get("environment") as Environment
	if env != null:
		env.ambient_light_color = AMBIENT_COOL_NIGHT.lerp(AMBIENT_WARM_DAY, day_factor)
		env.ssao_enabled = true
		env.ssao_intensity = lerpf(0.3, 0.42, day_factor)
		env.ssao_radius = 1.2
		env.ssao_power = 1.05

	if postfx_canvas != null and postfx_canvas.has_method("set_daylight_factor"):
		postfx_canvas.call("set_daylight_factor", clampf((day_factor * 0.6) + (afternoon_factor * 0.4), 0.0, 1.0))


func _normalize_character_materials(root: Node) -> void:
	if root == null:
		return
	for child in root.get_children():
		_normalize_character_materials(child)
	if root is not MeshInstance3D:
		return

	var mesh_node: MeshInstance3D = root as MeshInstance3D
	var surface_count: int = mesh_node.get_surface_override_material_count()
	for i in range(surface_count):
		var src_mat: Material = mesh_node.get_active_material(i)
		if not (src_mat is BaseMaterial3D):
			continue
		var tuned: BaseMaterial3D = src_mat as BaseMaterial3D
		if not tuned.resource_local_to_scene:
			tuned = tuned.duplicate() as BaseMaterial3D
			tuned.resource_local_to_scene = true
		tuned.metallic = 0.0
		tuned.roughness = maxf(tuned.roughness, 0.8)
		tuned.disable_receive_shadows = false
		mesh_node.set_surface_override_material(i, tuned)


func _apply_time_of_day(time_hours: float) -> void:
	_sky_time_hours = fposmod(time_hours, 24.0)
	if sky_3d != null and sky_3d.has_method("set"):
		var sky_internal_time: float = fposmod(_sky_time_hours - SKY_TIME_OFFSET_HOURS, 24.0)
		sky_3d.set("current_time", sky_internal_time)
	_apply_dynamic_lighting(_sky_time_hours)
	if time_weather_panel != null and time_weather_panel.has_method("set_time_hours"):
		time_weather_panel.call("set_time_hours", _sky_time_hours)
	_sync_environment_inspector()


func _apply_day_length(minutes_per_day: float) -> void:
	_sky_minutes_per_day = clampf(minutes_per_day, 1.0, 1440.0)
	if sky_3d != null and sky_3d.has_method("set"):
		sky_3d.set("minutes_per_day", _sky_minutes_per_day)
	if time_weather_panel != null and time_weather_panel.has_method("set_day_length_minutes"):
		time_weather_panel.call("set_day_length_minutes", _sky_minutes_per_day)
	_sync_environment_inspector()


func _build_weather_targets(weather_id: String) -> Dictionary:
	match weather_id:
		WEATHER_RAIN:
			return {
				"sky3d": {
					"wind_speed": 5.0,
					"cloud_intensity": 0.75,
				},
				"dome": {
					"cumulus_coverage": 0.86,
					"cirrus_coverage": 0.68,
					"fog_density": 0.0034,
					"fog_falloff": 2.0,
				},
			}
		WEATHER_SNOW:
			return {
				"sky3d": {
					"wind_speed": 2.8,
					"cloud_intensity": 0.8,
				},
				"dome": {
					"cumulus_coverage": 0.8,
					"cirrus_coverage": 0.64,
					"fog_density": 0.0048,
					"fog_falloff": 1.7,
				},
			}
		WEATHER_FOGGY:
			return {
				"sky3d": {
					"wind_speed": 0.8,
					"cloud_intensity": 0.7,
				},
				"dome": {
					"cumulus_coverage": 0.58,
					"cirrus_coverage": 0.35,
					"fog_density": 0.0088,
					"fog_falloff": 1.3,
				},
			}
		WEATHER_STORMY:
			return {
				"sky3d": {
					"wind_speed": 9.0,
					"cloud_intensity": 0.68,
				},
				"dome": {
					"cumulus_coverage": 0.97,
					"cirrus_coverage": 0.9,
					"fog_density": 0.0065,
					"fog_falloff": 1.6,
				},
			}
		_:
			return {
				"sky3d": {
					"wind_speed": 1.2,
					"cloud_intensity": 0.9,
				},
				"dome": {
					"cumulus_coverage": 0.34,
					"cirrus_coverage": 0.22,
					"fog_density": 0.0008,
					"fog_falloff": 3.0,
				},
			}


func _apply_weather_targets(targets: Dictionary, animated: bool) -> void:
	if _weather_tween != null:
		_weather_tween.kill()
	_weather_tween = null

	var duration: float = 0.8 if animated else 0.0
	if animated:
		_weather_tween = get_tree().create_tween()
		_weather_tween.set_parallel(true)

	_apply_weather_property_group(sky_3d, targets.get("sky3d", {}), duration)
	var dome: Object = null
	if sky_3d != null:
		dome = sky_3d.get("sky") as Object
	_apply_weather_property_group(dome, targets.get("dome", {}), duration)


func _apply_weather_property_group(target: Object, properties: Dictionary, duration: float) -> void:
	if target == null or properties.is_empty():
		return
	for key_variant in properties.keys():
		var key: String = String(key_variant)
		var value: Variant = properties[key]
		if not _object_has_property(target, key):
			continue
		if _weather_tween != null and duration > 0.0:
			_weather_tween.tween_property(target, key, value, duration)
		else:
			target.set(key, value)


func _object_has_property(obj: Object, property_name: String) -> bool:
	for prop in obj.get_property_list():
		if String(prop.get("name", "")) == property_name:
			return true
	return false


func _apply_weather_preset(weather_id: String, animated: bool = true) -> void:
	var normalized: String = weather_id.to_lower()
	if normalized not in [WEATHER_NORMAL, WEATHER_RAIN, WEATHER_SNOW, WEATHER_FOGGY, WEATHER_STORMY]:
		normalized = WEATHER_NORMAL
	_sky_weather = normalized
	if not _weather_stacking_enabled:
		_weather_channel_intensity["rain"] = 1.0 if normalized == WEATHER_RAIN else 0.0
		_weather_channel_intensity["snow"] = 1.0 if normalized == WEATHER_SNOW else 0.0
		_weather_channel_intensity["foggy"] = 1.0 if normalized == WEATHER_FOGGY else 0.0
		_weather_channel_intensity["stormy"] = 1.0 if normalized == WEATHER_STORMY else 0.0
	elif normalized != WEATHER_NORMAL and float(_weather_channel_intensity.get(normalized, 0.0)) <= 0.01:
		_weather_channel_intensity[normalized] = 1.0

	var targets: Dictionary = _build_weather_targets(normalized)
	_apply_weather_targets(targets, animated)
	_apply_precipitation_fx(normalized)
	_apply_dynamic_lighting(_sky_time_hours)

	if time_weather_panel != null and time_weather_panel.has_method("set_weather"):
		time_weather_panel.call("set_weather", _sky_weather)
	_sync_environment_inspector()
	emit_signal("sky_state_changed", _sky_time_hours, _sky_weather)


func _ensure_weather_particles() -> void:
	if _weather_fx_root == null:
		_weather_fx_root = get_node_or_null("WeatherFX") as Node3D
	if _weather_fx_root == null:
		_weather_fx_root = Node3D.new()
		_weather_fx_root.name = "WeatherFX"
		add_child(_weather_fx_root)

	if _rain_particles == null:
		_rain_particles = _create_precip_particles("RainParticles", Color(0.75, 0.84, 0.95, 0.75), 6000, 1.7, 24.0, 34.0, 0.05, 0.1)
		_weather_fx_root.add_child(_rain_particles)
	if _snow_particles == null:
		_snow_particles = _create_precip_particles("SnowParticles", Color(0.95, 0.98, 1.0, 0.9), 2200, 3.2, 2.8, 5.2, 0.08, 0.2)
		_weather_fx_root.add_child(_snow_particles)


func _create_precip_particles(particle_name: String, color: Color, amount: int, lifetime: float, velocity_min: float, velocity_max: float, scale_min: float, scale_max: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = particle_name
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = false
	particles.emitting = false
	particles.position = Vector3(0.0, 45.0, 0.0)
	particles.visibility_aabb = AABB(Vector3(-180.0, -60.0, -180.0), Vector3(360.0, 120.0, 360.0))

	var process := ParticleProcessMaterial.new()
	process.gravity = Vector3(0.0, -24.0, 0.0)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 4.0
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(170.0, 1.0, 170.0)
	process.initial_velocity_min = velocity_min
	process.initial_velocity_max = velocity_max
	process.scale_min = scale_min
	process.scale_max = scale_max
	particles.process_material = process

	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.28)
	particles.draw_pass_1 = quad

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	particles.material_override = mat

	return particles


func _apply_precipitation_fx(weather_id: String) -> void:
	_ensure_weather_particles()
	if _rain_particles == null or _snow_particles == null:
		return
	var rain_intensity: float = _weather_intensity_global * float(_weather_channel_intensity.get("rain", 0.0))
	var snow_intensity: float = _weather_intensity_global * float(_weather_channel_intensity.get("snow", 0.0))
	var storm_intensity: float = _weather_intensity_global * float(_weather_channel_intensity.get("stormy", 0.0))

	if not _weather_stacking_enabled:
		rain_intensity = _weather_intensity_global if weather_id in [WEATHER_RAIN, WEATHER_STORMY] else 0.0
		snow_intensity = _weather_intensity_global if weather_id == WEATHER_SNOW else 0.0
		storm_intensity = _weather_intensity_global if weather_id == WEATHER_STORMY else 0.0

	var rain_total: float = clampf(rain_intensity + storm_intensity, 0.0, 3.0)
	var snow_total: float = clampf(snow_intensity, 0.0, 3.0)

	_rain_particles.emitting = rain_total > 0.01
	_snow_particles.emitting = snow_total > 0.01
	_rain_particles.amount_ratio = clampf(rain_total / 3.0, 0.0, 1.0)
	_snow_particles.amount_ratio = clampf(snow_total / 3.0, 0.0, 1.0)


func _export_sky_state() -> Dictionary:
	return {
		"time_hours": _sky_time_hours,
		"weather": _sky_weather,
		"minutes_per_day": _sky_minutes_per_day,
		"time_paused": _time_paused,
		"time_scale": _time_scale,
		"lighting_override_enabled": _lighting_override_enabled,
		"lighting_override_color": _lighting_override_color,
		"lighting_override_energy": _lighting_override_energy,
		"lighting_override_saturation": _lighting_override_saturation,
		"lighting_override_tint_strength": _lighting_override_tint_strength,
		"weather_intensity_global": _weather_intensity_global,
		"weather_stacking_enabled": _weather_stacking_enabled,
		"weather_channels": _weather_channel_intensity,
		"lightning_enabled": _lightning_enabled,
		"lightning_interval": _lightning_interval,
		"lightning_intensity": _lightning_intensity,
		"lightning_random_variation": _lightning_random_variation,
		"full_rebuild_mode": _terrain_full_rebuild_mode,
	}


func _import_sky_state(data: Dictionary) -> void:
	_sky_time_hours = float(data.get("time_hours", _sky_time_hours))
	_sky_weather = String(data.get("weather", _sky_weather))
	_sky_minutes_per_day = float(data.get("minutes_per_day", _sky_minutes_per_day))
	_time_paused = bool(data.get("time_paused", _time_paused))
	_time_scale = clampf(float(data.get("time_scale", _time_scale)), 0.5, 10.0)
	_lighting_override_enabled = bool(data.get("lighting_override_enabled", _lighting_override_enabled))
	_lighting_override_color = data.get("lighting_override_color", _lighting_override_color)
	_lighting_override_energy = clampf(float(data.get("lighting_override_energy", _lighting_override_energy)), 0.0, 5.0)
	_lighting_override_saturation = clampf(float(data.get("lighting_override_saturation", _lighting_override_saturation)), -1.0, 2.0)
	_lighting_override_tint_strength = clampf(float(data.get("lighting_override_tint_strength", _lighting_override_tint_strength)), 0.0, 1.0)
	_weather_intensity_global = clampf(float(data.get("weather_intensity_global", _weather_intensity_global)), 0.0, 3.0)
	_weather_stacking_enabled = bool(data.get("weather_stacking_enabled", _weather_stacking_enabled))
	var loaded_channels: Dictionary = data.get("weather_channels", _weather_channel_intensity)
	if loaded_channels is Dictionary:
		_weather_channel_intensity = loaded_channels.duplicate(true)
	_lightning_enabled = bool(data.get("lightning_enabled", _lightning_enabled))
	_lightning_interval = clampf(float(data.get("lightning_interval", _lightning_interval)), 8.0, 60.0)
	_lightning_intensity = clampf(float(data.get("lightning_intensity", _lightning_intensity)), 0.0, 5.0)
	_lightning_random_variation = bool(data.get("lightning_random_variation", _lightning_random_variation))
	_terrain_full_rebuild_mode = bool(data.get("full_rebuild_mode", _terrain_full_rebuild_mode))
	_debug_visualize_dirty_rect = bool(data.get("debug_visualize_dirty_rect", _debug_visualize_dirty_rect))
	_lightning_timer = 0.01
	_apply_time_of_day(_sky_time_hours)
	_apply_day_length(_sky_minutes_per_day)
	_apply_weather_preset(_sky_weather, false)
	_sync_environment_inspector()
	if _terrain_node != null and _terrain_node.has_method("set_full_rebuild_mode"):
		_terrain_node.call("set_full_rebuild_mode", _terrain_full_rebuild_mode)
	emit_signal("sky_state_changed", _sky_time_hours, _sky_weather)

func _exit_tree() -> void:
	_runtime_terrain_editor.end_stroke()
	_runtime_terrain_editor.dispose()
	_deactivate_wall_tool()
	if _stamp_preview != null:
		_stamp_preview.queue_free()
	if _brush_preview != null:
		_brush_preview.queue_free()
	if _river_preview_node != null:
		_river_preview_node.queue_free()

func _process(delta: float) -> void:
	_tick_time_of_day(delta)
	if _time_paused:
		_apply_dynamic_lighting(_sky_time_hours)
	_tick_lightning(delta)
	_update_time_weather_visibility()
	_perf_overlay_accum += delta
	if _perf_overlay_accum >= PERF_OVERLAY_INTERVAL_SEC:
		_perf_overlay_accum = 0.0
		_update_performance_overlay()
	_update_live_previews()
	_tick_radius_indicator(delta)

	# Keep Shift->sharp switching responsive even if key events are missed while dragging.
	if _is_tool_dragging and (_current_tool == "raise" or _current_tool == "lower"):
		var target_mode: String = "sharp" if Input.is_key_pressed(KEY_SHIFT) else "smooth"
		if target_mode != _brush_mode:
			_update_brush_mode_visual_feedback()
	
	# Update brush mode indicator for raise/lower tools
	if (_current_tool == "raise" or _current_tool == "lower") and _is_tool_dragging:
		_show_brush_mode_indicator()
	elif _brush_mode_label != null and _brush_mode_label.visible:
		_hide_brush_mode_indicator()
	
	if _is_tool_dragging and _current_tool != "stamp":
		_stroke_interval_accum += delta
		var stroke_interval: float = _get_active_stroke_interval()
		if _current_tool == "texturepaint" or _current_tool == "textureerase":
			stroke_interval = TEXTURE_STROKE_INTERVAL_PERF_SEC if _texture_perf_mode else TEXTURE_STROKE_INTERVAL_SEC
		while _stroke_interval_accum >= stroke_interval:
			_stroke_interval_accum -= stroke_interval
			_continue_tool_stroke()
	if _is_stamp_dragging and _current_tool == "stamp":
		_stamp_drag_interval_accum += delta
		while _stamp_drag_interval_accum >= STAMP_DRAG_INTERVAL_SEC:
			_stamp_drag_interval_accum -= STAMP_DRAG_INTERVAL_SEC
			_stamp_at_mouse(true)
	if _current_tool == "wall" and _wall_tool != null and _wall_tool.has_method("update_preview"):
		_wall_tool.call("update_preview")
	if _current_tool == "riverdraw":
		_update_river_handle_positions()
		_update_river_live_preview()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_V:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo:
			_worldbrush_hold_active = true
			_open_worldbrush_radial_hold()
			get_viewport().set_input_as_handled()
			return
		if not key_event.pressed and _worldbrush_hold_active:
			_worldbrush_hold_active = false
			_confirm_worldbrush_radial_hold()
			get_viewport().set_input_as_handled()
			return

	if _worldbrush_menu != null and _worldbrush_menu.has_method("is_open") and bool(_worldbrush_menu.call("is_open")):
		if event is InputEventMouseMotion:
			_worldbrush_menu.call("update_pointer", (event as InputEventMouseMotion).position)
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var wheel_event: InputEventMouseButton = event as InputEventMouseButton
		if wheel_event != null and wheel_event.pressed and wheel_event.ctrl_pressed and _handle_ctrl_wheel_radius(wheel_event):
			get_viewport().set_input_as_handled()
			return

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
			KEY_R:
				if _has_active_character():
					_deselect_all_characters()
				_switch_tool("select")
				_set_status("Released character control; back to editing mode")
				get_viewport().set_input_as_handled()
				return
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

	# Shift key press/release for brush mode preview feedback
	if event is InputEventKey and event.keycode == KEY_SHIFT:
		_update_brush_mode_visual_feedback()
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

	if _current_tool == "riverdraw":
		if event is InputEventMouseButton:
			var mb_event: InputEventMouseButton = event as InputEventMouseButton
			if mb_event.button_index == MOUSE_BUTTON_LEFT and mb_event.pressed:
				var picked: Dictionary = _pick_river_handle(get_viewport().get_mouse_position())
				if not picked.is_empty():
					_dragging_river_handle = true
					_drag_river_id = int(picked.get("river_id", -1))
					_drag_point_index = int(picked.get("point_index", -1))
					_selected_river_id = _drag_river_id
					_selected_river_point_index = _drag_point_index
					_active_river_id = _selected_river_id
					_update_river_handle_visuals()
					_set_status("Dragging river point %d" % _drag_point_index)
				else:
					_handle_river_draw_click()
				get_viewport().set_input_as_handled()
				return
			if mb_event.button_index == MOUSE_BUTTON_LEFT and not mb_event.pressed:
				if _dragging_river_handle:
					_dragging_river_handle = false
					_drag_river_id = -1
					_drag_point_index = -1
					_refresh_river_handles()
					get_viewport().set_input_as_handled()
					return
			if mb_event.button_index == MOUSE_BUTTON_RIGHT and mb_event.pressed:
				_finish_river_draw()
				get_viewport().set_input_as_handled()
				return
		if event is InputEventMouseMotion and _dragging_river_handle:
			_drag_active_river_handle_to_mouse()
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
			if _current_tool == "horizonmountain":
				_place_horizon_mountain_at_mouse()
				get_viewport().set_input_as_handled()
				return
			if _current_tool == "stamp":
				_stamp_at_mouse(false)
				_is_stamp_dragging = true
				_stamp_drag_interval_accum = 0.0
			else:
				# Set brush mode based on Shift key for raise/lower tools
				if event.shift_pressed and (_current_tool == "raise" or _current_tool == "lower"):
					_brush_mode = "sharp"
				else:
					_brush_mode = "smooth"
				_begin_tool_stroke()
		else:
			_is_stamp_dragging = false
			if _is_tool_dragging:
				_is_tool_dragging = false
				if _terrain_node != null and (_current_tool == "texturepaint" or _current_tool == "textureerase") and _terrain_node.has_method("end_texture_stroke"):
					_terrain_node.call("end_texture_stroke")
				if not _current_tool.begins_with("grass") and not _current_tool.begins_with("scatter"):
					_runtime_terrain_editor.end_stroke()

	if event is InputEventMouseMotion and _is_tool_dragging:
		# Timed stroke stepping in _process keeps sculpting smooth while avoiding over-updating.
		pass
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

	if event is InputEventKey and event.pressed and not event.echo and _current_tool == "riverdraw":
		if event.keycode == KEY_ESCAPE:
			_finish_river_draw()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selected_river_point()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_1:
			_water_mode = "river"
			if _water_system != null and _water_system.has_method("set_water_mode"):
				_water_system.call("set_water_mode", _water_mode)
			_set_status("Water mode: River path")
			_update_active_tool_feedback()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_2:
			_finish_river_draw()
			_water_mode = "lake"
			if _water_system != null and _water_system.has_method("set_water_mode"):
				_water_system.call("set_water_mode", _water_mode)
			_set_status("Water mode: Lake / Pond")
			_update_active_tool_feedback()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_3:
			_finish_river_draw()
			_water_mode = "fill"
			if _water_system != null and _water_system.has_method("set_water_mode"):
				_water_system.call("set_water_mode", _water_mode)
			_set_status("Water mode: Sculpt / Fill")
			_update_active_tool_feedback()
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
		"config_toggle_chunked_terrain":
			_set_use_chunked_terrain(not use_chunked_terrain)
		"config_toggle_chunk_borders":
			_set_debug_draw_chunk_borders(not debug_draw_chunk_borders)
		"config_toggle_chunk_borders_red":
			_set_debug_draw_chunk_borders_red(not debug_draw_chunk_borders_red)
		"config_toggle_chunk_borders_highlight":
			_set_debug_highlight_problem_borders(not debug_highlight_problem_borders)
		"file_quit":
			get_tree().quit()
		"help_about", "app_about":
			_show_about_dialog()

func _apply_sculpt_mode_boost(enabled: bool) -> void:
	if _sculpt_mode_active == enabled:
		return
	_sculpt_mode_active = enabled
	if time_of_day_lighting != null and time_of_day_lighting.has_method("set_sculpt_boost"):
		time_of_day_lighting.call("set_sculpt_boost", enabled)
	if postfx_canvas != null and postfx_canvas.has_method("set_sculpt_mode"):
		postfx_canvas.call("set_sculpt_mode", enabled)


func _on_tool_changed(tool_name: String) -> void:
	if _current_tool == "riverdraw" and tool_name != "riverdraw":
		_finish_river_draw()
	if _current_tool != tool_name:
		_cancel_active_interactions()
	_current_tool = tool_name
	if _current_tool == "riverdraw":
		_refresh_river_handles()
		_set_river_handles_visible(true)
		_set_river_preview_visible(_active_river_id >= 0)
	else:
		_set_river_handles_visible(false)
		_set_river_preview_visible(false)
	if _current_tool == "wall":
		_activate_wall_tool()
	else:
		_deactivate_wall_tool()
	_apply_sculpt_mode_boost(tool_name in ["raise", "lower", "smooth", "flatten"])
	_update_active_tool_feedback()
	_update_worldbrush_inspector_for_tool(tool_name)
	_update_tool_name_display()
	_set_status("Active tool: %s" % _format_tool_name(tool_name))
	if tool_name in ["raise", "lower", "smooth", "flatten", "paint"] and not _runtime_terrain_editor.is_available() and _get_terrabrush_editor_node() != null:
		_set_status("Use V to enable TerraBrushEditor for terrain sculpting")

func _on_tool_clear_requested() -> void:
	_clear_active_tool("Cleared active tool")

func _on_tool_setting_changed(setting_name: String, value: Variant) -> void:
	match setting_name:
		"brush_size":
			_set_brush_radius(float(value), false, false)
		"brush_strength":
			_brush_strength = float(value)
		"brush_mode":
			_brush_mode = String(value)
			_update_brush_mode_visual_feedback()
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
		"grass_sway":
			if _grass_system != null and _grass_system.has_method("set_sway_amount"):
				_grass_system.call("set_sway_amount", float(value))
		"grass_base_color":
			if _grass_system != null and _grass_system.has_method("set_base_color"):
				_grass_system.call("set_base_color", value as Color)
		"grass_tip_color":
			if _grass_system != null and _grass_system.has_method("set_tip_color"):
				_grass_system.call("set_tip_color", value as Color)
		"grass_stroke_color":
			if _grass_system != null and _grass_system.has_method("set_stroke_color"):
				_grass_system.call("set_stroke_color", value as Color)
		"grass_noise_strength":
			if _grass_system != null and _grass_system.has_method("set_noise_strength"):
				_grass_system.call("set_noise_strength", float(value))
		"scatter_density":
			_scatter_density = float(value)
		"scatter_scale_min":
			_scatter_scale_min = float(value)
		"scatter_scale_max":
			_scatter_scale_max = float(value)
		"scatter_rotation_randomness":
			_scatter_rotation_randomness = float(value)
		"scatter_tilt":
			_scatter_tilt = float(value)
		"texture_tile_size":
			_texture_tile_size = float(value)
		"texture_density":
			_texture_density = float(value)
		"texture_perf_mode":
			_texture_perf_mode = bool(value)
			if _terrain_node != null and _terrain_node.has_method("set_texture_paint_performance_mode"):
				_terrain_node.call("set_texture_paint_performance_mode", _texture_perf_mode)
		"texture_brush_shape_mode":
			_texture_brush_shape_mode = String(value)
		"texture_shape_variation":
			_texture_shape_variation = float(value)
		"texture_edge_softness":
			_texture_edge_softness = float(value)
		"texture_coverage_limit":
			_texture_coverage_limit = float(value)
		"texture_random_rotation":
			_texture_random_rotation = float(value)
		"texture_scale_variation":
			_texture_scale_variation = float(value)
		"texture_exposure":
			_texture_exposure = float(value)
		"selected_texture_id":
			_selected_texture_id = String(value)
			if _texture_painter != null:
				_texture_painter.selected_texture_id = String(value)
		"brush_softness":
			_brush_softness = clampf(float(value), 0.0, 1.0)
		"smooth_post_pass_enabled":
			_smooth_post_pass_enabled = bool(value)
			if _terrain_node != null and _terrain_node.has_method("set_smooth_mode_options"):
				_terrain_node.call("set_smooth_mode_options", _smooth_post_pass_enabled, _smooth_post_pass_strength)
		"smooth_post_pass_strength":
			_smooth_post_pass_strength = clampf(float(value), 0.0, 0.35)
			if _terrain_node != null and _terrain_node.has_method("set_smooth_mode_options"):
				_terrain_node.call("set_smooth_mode_options", _smooth_post_pass_enabled, _smooth_post_pass_strength)
		"cliff_mode":
			_cliff_mode = bool(value)
		"overhang_amount":
			_overhang_amount = float(value)
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
		"river_width":
			_river_width = float(value)
			var target_river_id: int = _selected_river_id if _selected_river_id >= 0 else _active_river_id
			if target_river_id >= 0 and _water_system != null and _water_system.has_method("set_river_width_all"):
				_water_system.call("set_river_width_all", target_river_id, _river_width)
		"river_flow_speed":
			if _water_system != null:
				_river_flow_speed = float(value)
				if _water_system.has_method("set_flow_speed"):
					_water_system.call("set_flow_speed", _river_flow_speed)
		"river_average_depth":
			_river_average_depth = float(value)
			var target_depth_river_id: int = _selected_river_id if _selected_river_id >= 0 else _active_river_id
			if target_depth_river_id >= 0 and _water_system != null and _water_system.has_method("set_river_average_depth"):
				_water_system.call("set_river_average_depth", target_depth_river_id, _river_average_depth)
		"water_color":
			if _water_system != null:
				_water_color = value as Color
				if _water_system.has_method("set_water_color"):
					_water_system.call("set_water_color", _water_color)
		"water_mode":
			_water_mode = String(value)
			if _water_system != null and _water_system.has_method("set_water_mode"):
				_water_system.call("set_water_mode", _water_mode)
		"time_hours":
			_apply_time_of_day(float(value))
		"day_length_minutes":
			_apply_day_length(float(value))
		"time_paused":
			_time_paused = bool(value)
		"time_scale":
			_time_scale = clampf(float(value), 0.5, 10.0)
		"lighting_override_enabled":
			_lighting_override_enabled = bool(value)
			_apply_dynamic_lighting(_sky_time_hours)
		"lighting_override_color":
			_lighting_override_color = value as Color
			_apply_dynamic_lighting(_sky_time_hours)
		"lighting_override_energy":
			_lighting_override_energy = clampf(float(value), 0.0, 5.0)
			_apply_dynamic_lighting(_sky_time_hours)
		"lighting_override_saturation":
			_lighting_override_saturation = clampf(float(value), -1.0, 2.0)
			_apply_dynamic_lighting(_sky_time_hours)
		"lighting_override_tint_strength":
			_lighting_override_tint_strength = clampf(float(value), 0.0, 1.0)
			_apply_dynamic_lighting(_sky_time_hours)
		"weather_intensity_global":
			_weather_intensity_global = clampf(float(value), 0.0, 3.0)
			_apply_weather_preset(_sky_weather, false)
		"weather_stacking_enabled":
			_weather_stacking_enabled = bool(value)
			_apply_weather_preset(_sky_weather, false)
		"weather_channel_rain":
			_weather_channel_intensity["rain"] = clampf(float(value), 0.0, 3.0)
			_apply_weather_preset(_sky_weather, false)
		"weather_channel_snow":
			_weather_channel_intensity["snow"] = clampf(float(value), 0.0, 3.0)
			_apply_weather_preset(_sky_weather, false)
		"weather_channel_foggy":
			_weather_channel_intensity["foggy"] = clampf(float(value), 0.0, 3.0)
			_apply_weather_preset(_sky_weather, false)
		"weather_channel_stormy":
			_weather_channel_intensity["stormy"] = clampf(float(value), 0.0, 3.0)
			_apply_weather_preset(_sky_weather, false)
		"lightning_enabled":
			_lightning_enabled = bool(value)
			_lightning_timer = 0.01
		"lightning_interval":
			_lightning_interval = clampf(float(value), 8.0, 60.0)
		"lightning_intensity":
			_lightning_intensity = clampf(float(value), 0.0, 5.0)
		"lightning_random_variation":
			_lightning_random_variation = bool(value)
		"full_rebuild_mode":
			_terrain_full_rebuild_mode = bool(value)
			if _terrain_node != null and _terrain_node.has_method("set_full_rebuild_mode"):
				_terrain_node.call("set_full_rebuild_mode", _terrain_full_rebuild_mode)
		"debug_visualize_dirty_rect":
			_debug_visualize_dirty_rect = bool(value)
			if _terrain_node != null and _terrain_node.has_method("set") and _terrain_node.has_property("debug_visualize_dirty_rect"):
				_terrain_node.debug_visualize_dirty_rect = _debug_visualize_dirty_rect
		"postfx_effect":
			if postfx_canvas != null and postfx_canvas.has_method("set_effect_value") and value is Dictionary:
				var effect_data: Dictionary = value
				var effect_name: String = String(effect_data.get("name", ""))
				if effect_name != "":
					_ensure_postfx_live_preview_mode()
					postfx_canvas.call("set_effect_value", effect_name, effect_data.get("value"))
		"postfx_apply_preset":
			if postfx_canvas != null and postfx_canvas.has_method("apply_builtin_preset"):
				_ensure_postfx_live_preview_mode()
				var preset_ok: bool = bool(postfx_canvas.call("apply_builtin_preset", String(value)))
				_set_status("PostFX preset: %s" % ("Applied" if preset_ok else "Unknown"))
		"postfx_apply_custom_shader":
			if postfx_canvas != null and postfx_canvas.has_method("apply_custom_shader_code"):
				_ensure_postfx_live_preview_mode()
				var shader_ok: bool = bool(postfx_canvas.call("apply_custom_shader_code", String(value)))
				_set_status("Custom PostFX shader: %s" % ("Applied" if shader_ok else "Rejected"))
		"postfx_save_local", "postfx_export_local":
			if postfx_canvas != null and postfx_canvas.has_method("save_ppf") and value is Dictionary:
				var save_data: Dictionary = value
				var save_ok: bool = bool(postfx_canvas.call(
					"save_ppf",
					String(save_data.get("path", "")),
					String(save_data.get("name", "Untitled PostFX")),
					String(save_data.get("author", "")),
					String(save_data.get("description", "")),
					String(save_data.get("custom_shader_code", ""))
				))
				_set_status(".ppf %s" % ("saved" if save_ok else "save failed"))
		"postfx_load_local":
			if postfx_canvas != null and postfx_canvas.has_method("load_ppf"):
				var load_ok: bool = bool(postfx_canvas.call("load_ppf", String(value)))
				if load_ok and _post_process_disabled:
					_set_post_process_disabled(false)
				_set_status(".ppf %s" % ("loaded" if load_ok else "load failed"))
		"postfx_import_url":
			if postfx_canvas != null and postfx_canvas.has_method("import_ppf_from_url"):
				postfx_canvas.call("import_ppf_from_url", String(value))
				_set_status("Importing .ppf from URL...")
	_sync_environment_inspector()


func _on_postfx_ppf_import_completed(success: bool, message: String) -> void:
	if success and _post_process_disabled:
		_set_post_process_disabled(false)
	_set_status("PostFX import: %s" % message)


func _ensure_postfx_live_preview_mode() -> void:
	if _post_process_disabled:
		_set_post_process_disabled(false)
	# Leave optimization mode for postfx authoring so slider changes are clearly visible.
	if _ultra_performance_mode:
		_set_ultra_performance_mode(false, false)
	if _performance_mode:
		_set_performance_mode(false)
	if _lightweight_postfx:
		_set_lightweight_postfx(false, false)

func _on_prefab_selected(prefab_path: String) -> void:
	_selected_prefab = prefab_path
	if _scatter_system != null and _scatter_system.has_method("set_active_prefab"):
		_scatter_system.call("set_active_prefab", prefab_path)
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

func _create_new_flat_map(_include_seed_content: bool = true) -> void:
	_terrain_node = _ensure_terrain_node()
	var terrain_editor_ready: bool = _runtime_terrain_editor.initialize(_terrain_node)
	for child in stamp_root.get_children():
		child.queue_free()
	var wall_system: Node = get_node_or_null("WallSystem")
	if wall_system != null and wall_system.has_method("clear_segments"):
		wall_system.call("clear_segments")
	if _scatter_system != null and _scatter_system.has_method("clear_all"):
		_scatter_system.call("clear_all")
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

	if terrain_editor_ready:
		if _terrain_node != null and _terrain_node.has_method("initialize_new_map"):
			_terrain_node.call("initialize_new_map", Time.get_ticks_usec())

	if _grass_system != null and _grass_system.has_method("clear_all"):
		_grass_system.call("clear_all")
	if _water_system != null and _water_system.has_method("clear_all"):
		_water_system.call("clear_all")
	_active_river_id = -1
	if _horizon_system != null and is_instance_valid(_horizon_system) and _horizon_system.has_method("clear_all"):
		_horizon_system.call("clear_all")
	_reset_characters_on_new_map()

	if camera_manager != null and camera_manager.has_method("recenter"):
		camera_manager.call("recenter")
	if camera_manager != null and camera_manager.has_method("set_top_down_default"):
		camera_manager.call("set_top_down_default")

	_apply_time_of_day(_sky_time_hours)
	_apply_weather_preset(WEATHER_NORMAL, false)
	_set_status("New map ready: blank flat terrain. Add terrain and assets with tools.")
	if AUTO_DEBUG_SCREENSHOTS:
		call_deferred("_capture_full_editor_screenshot", "new_map")


func _handle_river_draw_click() -> void:
	if _water_system == null:
		_set_status("Water system unavailable")
		return

	var hit: Variant = _get_mouse_world_position()
	if not (hit is Vector3):
		return

	var world_pos: Vector3 = hit as Vector3
	if _water_mode == "lake":
		if _water_system.has_method("create_lake"):
			var lake_radius: float = maxf(4.0, _river_width * 1.9)
			var lake_node: Variant = _water_system.call("create_lake", "", world_pos, lake_radius, _active_world_layer, "lake", _river_average_depth, true)
			if lake_node is MeshInstance3D:
				_set_status("Lake created on layer %d" % _active_world_layer)
			return
	if _water_mode == "fill":
		if _water_system.has_method("create_fill_water"):
			var fill_radius: float = maxf(5.0, _river_width * 2.2)
			var fill_node: Variant = _water_system.call("create_fill_water", "", world_pos, fill_radius, _active_world_layer, _river_average_depth)
			if fill_node is MeshInstance3D:
				_set_status("Fill water created on layer %d" % _active_world_layer)
			return

	if _active_river_id < 0:
		if _selected_river_id >= 0 and _water_system.has_method("get_river"):
			var selected_river_var: Variant = _water_system.call("get_river", _selected_river_id)
			if selected_river_var is Dictionary and not (selected_river_var as Dictionary).is_empty():
				_active_river_id = _selected_river_id
				if _water_system.has_method("add_river_point"):
					_water_system.call("add_river_point", _active_river_id, world_pos)
				if _water_system.has_method("set_river_width_all"):
					_water_system.call("set_river_width_all", _active_river_id, _river_width)
				_refresh_river_handles()
				_set_status("River #%d: extended" % _active_river_id)
				return

		if not _water_system.has_method("create_river"):
			_set_status("Water system missing create_river")
			return
		var river_node: Variant = _water_system.call("create_river", "")
		if river_node is MeshInstance3D and (river_node as MeshInstance3D).has_meta("river_id"):
			_active_river_id = int((river_node as MeshInstance3D).get_meta("river_id"))
		if _active_river_id < 0:
			_set_status("Failed to start river")
			return
		_selected_river_id = _active_river_id
		_selected_river_point_index = 1
		if _water_system.has_method("set_river_point_position"):
			_water_system.call("set_river_point_position", _active_river_id, 0, world_pos)
			_water_system.call("set_river_point_position", _active_river_id, 1, world_pos + Vector3(0.2, 0.0, 0.2))
		if _water_system.has_method("set_river_width_all"):
			_water_system.call("set_river_width_all", _active_river_id, _river_width)
		if _water_system.has_method("set_river_average_depth"):
			_water_system.call("set_river_average_depth", _active_river_id, _river_average_depth)
		_set_river_preview_visible(true)
		_set_status("Started river #%d (LMB add points, RMB/Esc finish)" % _active_river_id)
		return

	if _water_system.has_method("add_river_point"):
		_water_system.call("add_river_point", _active_river_id, world_pos)
	if _water_system.has_method("set_river_width_all"):
		_water_system.call("set_river_width_all", _active_river_id, _river_width)
	if _water_system.has_method("set_river_average_depth"):
		_water_system.call("set_river_average_depth", _active_river_id, _river_average_depth)
	if _water_system.has_method("get_river"):
		var river_var: Variant = _water_system.call("get_river", _active_river_id)
		if river_var is Dictionary:
			var curve: Curve3D = (river_var as Dictionary).get("curve", null)
			if curve != null:
				_selected_river_point_index = max(0, curve.get_point_count() - 1)
	_selected_river_id = _active_river_id
	_refresh_river_handles()
	_set_status("River #%d: point added" % _active_river_id)


func _finish_river_draw() -> void:
	var finished_river_id: int = _active_river_id
	if _active_river_id >= 0:
		_set_status("River #%d finished" % _active_river_id)
	_active_river_id = -1
	if finished_river_id >= 0 and _water_system != null and _water_system.has_method("shape_riverbed_for_river"):
		_water_system.call("shape_riverbed_for_river", finished_river_id)
	_selected_river_point_index = -1
	_refresh_river_handles()
	_set_river_preview_visible(false)
	_update_river_handle_visuals()


func _ensure_river_handle_root() -> void:
	if _river_handle_root != null and is_instance_valid(_river_handle_root):
		return
	_river_handle_root = Node3D.new()
	_river_handle_root.name = "RiverHandles"
	add_child(_river_handle_root)


func _set_river_handles_visible(show_handles: bool) -> void:
	_ensure_river_handle_root()
	_river_handle_root.visible = show_handles


func _ensure_river_preview_node() -> void:
	if _river_preview_node != null and is_instance_valid(_river_preview_node):
		return
	_river_preview_node = MeshInstance3D.new()
	_river_preview_node.name = "RiverPreviewSegment"
	_river_preview_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.04, 1.0)
	_river_preview_node.mesh = box
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.15, 0.9, 1.0, 0.38)
	mat.emission_enabled = true
	mat.emission = Color(0.08, 0.55, 0.65)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_river_preview_node.material_override = mat
	add_child(_river_preview_node)
	_river_preview_node.visible = false


func _set_river_preview_visible(show_preview: bool) -> void:
	if not show_preview:
		if _river_preview_node != null and is_instance_valid(_river_preview_node):
			_river_preview_node.visible = false
		return
	_ensure_river_preview_node()
	_river_preview_node.visible = true


func _update_river_live_preview() -> void:
	if _current_tool != "riverdraw" or _active_river_id < 0 or _dragging_river_handle:
		_set_river_preview_visible(false)
		return
	if _water_system == null or not _water_system.has_method("get_river"):
		_set_river_preview_visible(false)
		return
	var hit: Variant = _get_mouse_world_position()
	if not (hit is Vector3):
		_set_river_preview_visible(false)
		return
	var river_var: Variant = _water_system.call("get_river", _active_river_id)
	if not (river_var is Dictionary):
		_set_river_preview_visible(false)
		return
	var river: Dictionary = river_var as Dictionary
	var curve: Curve3D = river.get("curve", null)
	if curve == null or curve.get_point_count() <= 0:
		_set_river_preview_visible(false)
		return

	var last_point: Vector3 = curve.get_point_position(curve.get_point_count() - 1)
	var mouse_point: Vector3 = hit as Vector3
	var segment: Vector3 = mouse_point - last_point
	var segment_length: float = segment.length()
	if segment_length < 0.05:
		_set_river_preview_visible(false)
		return

	_ensure_river_preview_node()
	_set_river_preview_visible(true)
	var box_mesh: BoxMesh = _river_preview_node.mesh as BoxMesh
	if box_mesh != null:
		box_mesh.size = Vector3(maxf(0.1, _river_width * 2.0), 0.04, maxf(0.1, segment_length))

	var mid_point: Vector3 = (last_point + mouse_point) * 0.5 + Vector3(0.0, 0.03, 0.0)
	var dir: Vector3 = segment.normalized()
	var preview_basis: Basis = Basis.looking_at(dir, Vector3.UP)
	_river_preview_node.global_transform = Transform3D(preview_basis, mid_point)


func _clear_river_handles() -> void:
	_ensure_river_handle_root()
	for child in _river_handle_root.get_children():
		child.queue_free()
	_river_point_handles.clear()


func _create_river_handle_node() -> MeshInstance3D:
	var handle := MeshInstance3D.new()
	handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := SphereMesh.new()
	mesh.radius = 0.2
	mesh.height = 0.4
	handle.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 1.0, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.85, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	handle.material_override = mat
	return handle


func _update_river_handle_visuals() -> void:
	for item in _river_point_handles:
		var node: MeshInstance3D = item.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		if not (node.material_override is StandardMaterial3D):
			continue
		var mat: StandardMaterial3D = node.material_override as StandardMaterial3D
		var river_id: int = int(item.get("river_id", -1))
		var point_index: int = int(item.get("point_index", -1))
		var is_selected_river: bool = river_id == _selected_river_id
		var is_selected_point: bool = is_selected_river and point_index == _selected_river_point_index
		if is_selected_point:
			mat.albedo_color = Color(1.0, 0.82, 0.2, 0.95)
			mat.emission = Color(0.95, 0.62, 0.08)
		elif is_selected_river:
			mat.albedo_color = Color(0.2, 1.0, 0.55, 0.9)
			mat.emission = Color(0.1, 0.8, 0.35)
		else:
			mat.albedo_color = Color(0.1, 0.9, 1.0, 0.9)
			mat.emission = Color(0.12, 0.85, 1.0)


func _refresh_river_handles() -> void:
	if _water_system == null or not _water_system.has_method("get_rivers"):
		return
	_clear_river_handles()
	var rivers_variant: Variant = _water_system.call("get_rivers")
	if not (rivers_variant is Dictionary):
		return
	var rivers: Dictionary = rivers_variant as Dictionary
	for river_id_variant in rivers.keys():
		var river_id: int = int(river_id_variant)
		var river: Dictionary = rivers[river_id]
		var curve: Curve3D = river.get("curve", null)
		if curve == null:
			continue
		for i in range(curve.get_point_count()):
			var handle: MeshInstance3D = _create_river_handle_node()
			_river_handle_root.add_child(handle)
			handle.position = curve.get_point_position(i) + Vector3(0.0, 0.08, 0.0)
			_river_point_handles.append({
				"river_id": river_id,
				"point_index": i,
				"node": handle,
			})
	_update_river_handle_visuals()


func _delete_selected_river_point() -> void:
	if _selected_river_id < 0 or _selected_river_point_index < 0:
		return
	if _water_system == null or not _water_system.has_method("remove_river_point"):
		return
	_water_system.call("remove_river_point", _selected_river_id, _selected_river_point_index)
	_selected_river_point_index = -1
	_refresh_river_handles()
	_set_status("Deleted selected river point")


func _update_river_handle_positions() -> void:
	if _water_system == null or _river_point_handles.is_empty():
		return
	for item in _river_point_handles:
		var river_id: int = int(item.get("river_id", -1))
		var point_index: int = int(item.get("point_index", -1))
		var node: MeshInstance3D = item.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		if not node.is_inside_tree():
			continue
		if not _water_system.has_method("get_river"):
			continue
		var river_var: Variant = _water_system.call("get_river", river_id)
		if not (river_var is Dictionary):
			continue
		var river: Dictionary = river_var as Dictionary
		var curve: Curve3D = river.get("curve", null)
		if curve == null or point_index < 0 or point_index >= curve.get_point_count():
			continue
		node.position = curve.get_point_position(point_index) + Vector3(0.0, 0.08, 0.0)


func _pick_river_handle(mouse_pos: Vector2) -> Dictionary:
	if _river_point_handles.is_empty() or camera == null:
		return {}
	var best_distance: float = 16.0
	var best: Dictionary = {}
	for item in _river_point_handles:
		var node: MeshInstance3D = item.get("node", null)
		if node == null or not is_instance_valid(node):
			continue
		if not node.is_inside_tree():
			continue
		if camera.is_position_behind(node.global_position):
			continue
		var screen_pos: Vector2 = camera.unproject_position(node.global_position)
		var d: float = mouse_pos.distance_to(screen_pos)
		if d < best_distance:
			best_distance = d
			best = item
	return best


func _drag_active_river_handle_to_mouse() -> void:
	if _drag_river_id < 0 or _drag_point_index < 0:
		return
	if _water_system == null or not _water_system.has_method("set_river_point_position"):
		return
	var hit: Variant = _get_mouse_world_position()
	if not (hit is Vector3):
		return
	var world_pos: Vector3 = hit as Vector3
	_water_system.call("set_river_point_position", _drag_river_id, _drag_point_index, world_pos)

func _setup_dungeondraft_import() -> void:
	_dungeondraft_importer = DUNGEONDRAFT_IMPORTER_SCRIPT.new()
	_import_prefab_paths.clear()
	_import_prefab_key_to_path.clear()
	_collect_prefabs("res://assets/world/models", _import_prefab_paths)
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
	var tex: Texture2D = _load_texture2d_or_null(texture_path)
	if tex != null:
		mat.albedo_texture = tex
		mat.uv1_scale = Vector3(2.2, 2.2, 1.0)
	return mat

func _load_texture2d_or_null(path: String) -> Texture2D:
	var ext: String = path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg", "webp", "bmp", "tga", "hdr", "exr"]:
		var image := Image.new()
		var err: Error = image.load(path)
		if err == OK and not image.is_empty():
			return ImageTexture.create_from_image(image)

	var tex: Texture2D = ResourceLoader.load(path, "Texture2D") as Texture2D
	if tex != null:
		return tex

	return null

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
	_runtime_terrain_editor.set_tool("flatten", cell_size * 1.1, 1.0, raise_height, false, _overhang_amount)
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

		var object_position: Vector3 = object_data.get("position", Vector3.ZERO)
		var rotation_deg: float = rad_to_deg(float(object_data.get("rotation_rad", 0.0)))
		var object_scale: Vector3 = object_data.get("scale", Vector3.ONE)
		var placed_node: Node3D = _place_prefab_direct(prefab_path, object_position, rotation_deg, root, object_scale)
		if placed_node == null:
			skipped += 1
			continue
		placed += 1

	return {"placed": placed, "skipped": skipped}

func _match_prefab_for_dd_object(texture_path: String) -> String:
	var key: String = texture_path.get_file().get_basename().to_lower()
	if key.contains("wall_torch"):
		var preferred := [
			"res://assets/world/models/props/core/torch_wall_mounted.tscn",
			"res://assets/world/models/props/torches/torch_mounted.tscn",
			"res://assets/world/models/props/torches/torch_lit.tscn"
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
		_normalize_character_materials(child)

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
	var toolbar_supported: Dictionary = {
		"select": true,
		"raise": true,
		"lower": true,
		"smooth": true,
		"flatten": true,
		"paint": true,
		"stamp": true,
		"grasspaint": true,
		"grasserase": true,
		"wall": true,
		"texturepaint": true,
		"textureerase": true,
		"riverdraw": true,
		"horizonmountain": true,
	}
	if world_tools != null and world_tools.has_method("set_tool_from_action") and toolbar_supported.has(tool_name):
		world_tools.call("set_tool_from_action", "tool_" + tool_name)
		return
	_on_tool_changed(tool_name)

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
	_dragging_river_handle = false
	_drag_river_id = -1
	_drag_point_index = -1
	_stroke_interval_accum = 0.0
	_stamp_drag_interval_accum = 0.0
	_last_stamp_grid_key = Vector2i(999999, 999999)
	_runtime_terrain_editor.end_stroke()
	_set_river_handles_visible(false)
	_set_river_preview_visible(false)

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
		world_tools.visible = false

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
		asset_browser.visible = false
	
	# Hide FPS debug box and viewport hints
	var perf_panel: Control = get_node_or_null("EditorCanvas/RootUI/Layout/Body/CenterSpacer/PerfPanel")
	if perf_panel != null:
		perf_panel.visible = false
	var hint_label: Control = get_node_or_null("EditorCanvas/RootUI/Layout/Body/CenterSpacer/ViewportHint")
	if hint_label != null:
		hint_label.visible = false

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
	if postfx_canvas != null and postfx_canvas.has_method("set_enabled"):
		postfx_canvas.call("set_enabled", not bool(postfx_canvas.get("enabled")))
		_set_status("PostFX: %s" % ("On" if bool(postfx_canvas.get("enabled")) else "Off"))
	elif postfx_canvas != null:
		postfx_canvas.visible = not postfx_canvas.visible
		_set_status("PostFX visibility toggled")
	else:
		_set_status("PostFX unavailable in this build")

func _set_performance_mode(enabled: bool) -> void:
	_performance_mode = enabled
	if postfx_canvas != null and postfx_canvas.has_method("set_performance_mode"):
		postfx_canvas.call("set_performance_mode", _performance_mode)
	if _performance_mode:
		_set_lightweight_postfx(true, false)
	if not _performance_mode:
		_set_ultra_performance_mode(false, false)
	if not _post_process_disabled and postfx_canvas != null and postfx_canvas.has_method("set_enabled"):
		postfx_canvas.call("set_enabled", true)
	_apply_editor_render_budget()
	_set_status("Performance Mode: %s" % ("On" if _performance_mode else "Off"))

func _set_ultra_performance_mode(enabled: bool, announce: bool = true) -> void:
	_ultra_performance_mode = enabled
	if postfx_canvas != null and postfx_canvas.has_method("set_ultra_performance_mode"):
		postfx_canvas.call("set_ultra_performance_mode", _ultra_performance_mode)
	if _ultra_performance_mode:
		_performance_mode = true
		if postfx_canvas != null and postfx_canvas.has_method("set_performance_mode"):
			postfx_canvas.call("set_performance_mode", true)
		_set_lightweight_postfx(true, false)
	_apply_editor_render_budget()
	if announce:
		_set_status("Ultra Performance: %s" % ("On" if _ultra_performance_mode else "Off"))

func _set_lightweight_postfx(enabled: bool, announce: bool = true) -> void:
	_lightweight_postfx = enabled
	if postfx_canvas != null and postfx_canvas.has_method("set_lightweight_mode"):
		postfx_canvas.call("set_lightweight_mode", _lightweight_postfx)
	if announce:
		_set_status("Lightweight PostFX: %s" % ("On" if _lightweight_postfx else "Off"))

func _set_post_process_disabled(disabled: bool) -> void:
	_post_process_disabled = disabled
	if postfx_canvas != null and postfx_canvas.has_method("set_enabled"):
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
		"scatterpaint", "scattererase":
			viewport_hint.text = "Mode: %s | Hold LMB to spray/erase | Radius %.1f | Density %.2f | Scale %.2f-%.2f" % [_format_tool_name(_current_tool), _brush_size, _scatter_density, _scatter_scale_min, _scatter_scale_max]
		"texturepaint":
			viewport_hint.text = "Mode: Texture Paint | Radius %.1f | Strength %.2f | Density %.2f | Shape %s | Var %d%% | Soft %.2f" % [_brush_size, _brush_strength, _texture_density, _texture_brush_shape_mode.capitalize(), int(round(_texture_shape_variation * 100.0)), _texture_edge_softness]
		"textureerase":
			viewport_hint.text = "Mode: Texture Erase | Radius %.1f | Strength %.2f" % [_brush_size, _brush_strength]
		"horizonmountain":
			viewport_hint.text = "Mode: Distant Mountain | LMB: click to place %dm away in that direction | Esc clears tool" % [int(HORIZON_MOUNTAIN_PLACE_DISTANCE)]
		"riverdraw":
			viewport_hint.text = "Mode: Water (%s) | [1]River [2]Lake [3]Fill | LMB place/edit | RMB/Esc finish river path | Width %.1f | Flow %.2f | Depth %.1f | Layer %d" % [_water_mode.capitalize(), _river_width, _river_flow_speed, _river_average_depth, _active_world_layer]
		"waterpaint":
			viewport_hint.text = "Mode: WorldBrush Water Paint | Hold LMB to carve + wet terrain | Brush %.1f | Strength %.2f | Layer %d" % [_brush_size, _brush_strength, _active_world_layer]
		"snowpaint":
			viewport_hint.text = "Mode: WorldBrush Snow Paint | Hold LMB to add snow | Brush %.1f | Strength %.2f | Layer %d" % [_brush_size, _brush_strength, _active_world_layer]
		"snowerase":
			viewport_hint.text = "Mode: WorldBrush Snow Erase | Hold LMB to remove snow | Brush %.1f | Strength %.2f | Layer %d" % [_brush_size, _brush_strength, _active_world_layer]
		_:
			viewport_hint.text = "Mode: %s" % _format_tool_name(_current_tool)


func set_active_world_layer(layer: int) -> void:
	_active_world_layer = layer
	if _terrain_node != null and _terrain_node.has_method("set_world_layer"):
		_terrain_node.call("set_world_layer", layer)
	if _water_system != null and _water_system.has_method("set_current_layer"):
		_water_system.call("set_current_layer", layer)
	_update_active_tool_feedback()


func get_active_world_layer() -> int:
	return _active_world_layer

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
		"wall":
			return "Smart Wall"
		"riverdraw":
			return "Draw River"
		"select":
			return "Select / None"
		_:
			return tool_name.capitalize()

## Place a distant mountain landmark in the direction the camera is pointing.
## The mountain is always placed DEFAULT_PLACE_DISTANCE meters along the
## mouse-ray direction so the GM can aim at the horizon and click.
func _place_horizon_mountain_at_mouse() -> void:
	if _horizon_system == null or not is_instance_valid(_horizon_system):
		_set_status("Horizon system not initialised")
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)
	var dist: float = HORIZON_MOUNTAIN_PLACE_DISTANCE
	var world_pos: Vector3 = ray_origin + ray_dir * dist
	world_pos.y = 0.0  # anchor mountains at ground level
	var id: int = _horizon_system.call("add_mountain", world_pos)
	var range_m: int = int(Vector2(world_pos.x, world_pos.z).length())
	_set_status("Placed distant mountain #%d at (%.0f, %.0f) — %dm from origin" % [
		id, world_pos.x, world_pos.z, range_m])

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
	if _current_tool.begins_with("scatter"):
		if _scatter_system != null and _scatter_system.has_method("apply_brush"):
			_scatter_system.call("apply_brush", _current_tool, hit as Vector3, _brush_size, _brush_strength, _scatter_density, _scatter_scale_min, _scatter_scale_max, _scatter_rotation_randomness, _scatter_tilt)
		return
	if _current_tool.begins_with("grass"):
		if _grass_system != null and _grass_system.has_method("apply_brush"):
			_grass_system.call("apply_brush", _current_tool, hit as Vector3, _brush_size, _brush_strength)
		return
	if _current_tool == "texturepaint":
		if _terrain_node != null:
			if _terrain_node.has_method("begin_texture_stroke"):
				_terrain_node.call("begin_texture_stroke", _texture_perf_mode, _brush_size)
			var max_off: float = _texture_tile_size * 0.65
			_texture_stroke_offset = Vector2(randf_range(-max_off, max_off), randf_range(-max_off, max_off))
			_texture_stroke_rotation = randf_range(-_texture_random_rotation, _texture_random_rotation)
			_texture_stroke_scale = 1.0 + randf_range(-_texture_scale_variation, _texture_scale_variation)
			_texture_stroke_seed = randf() * 4096.0
			if _texture_brush_shape_mode == "varied":
				_texture_stroke_shape_variant = randi_range(0, 2)
			else:
				_texture_stroke_shape_variant = 0
			var maps: Dictionary = _get_texture_maps(_selected_texture_id, 1024)
			if not maps.is_empty() and maps.has("albedo"):
				_terrain_node.call("apply_texture_brush", hit as Vector3, maps.get("albedo", null), maps.get("normal", null), maps.get("roughness", null), maps.get("height", null), maps.get("ao", null), _brush_size, _brush_strength, _texture_tile_size, _texture_density, _texture_edge_softness, _texture_coverage_limit, _texture_stroke_offset, _texture_stroke_rotation, _texture_stroke_scale, _texture_exposure, _texture_brush_shape_mode, _texture_shape_variation, _texture_stroke_seed, _texture_stroke_shape_variant)
		return
	if _current_tool == "textureerase":
		if _terrain_node != null:
			_terrain_node.call("apply_texture_erase_brush", hit as Vector3, _brush_size, _brush_strength, _texture_edge_softness)
		return
	_runtime_terrain_editor.set_tool(_current_tool, _brush_size, _brush_strength, _flatten_height, _cliff_mode, _overhang_amount)
	if _runtime_terrain_editor.has_method("set_brush_falloff"):
		_runtime_terrain_editor.call("set_brush_falloff", _brush_softness, _brush_mode)
	if _terrain_node != null and _terrain_node.has_method("set_smooth_mode_options"):
		_terrain_node.call("set_smooth_mode_options", _smooth_post_pass_enabled, _smooth_post_pass_strength)
	_runtime_terrain_editor.begin_stroke(hit as Vector3)

func _continue_tool_stroke() -> void:
	var hit: Variant = _get_mouse_world_position()
	if hit == null:
		return
	if _current_tool.begins_with("scatter"):
		if _scatter_system != null and _scatter_system.has_method("apply_brush"):
			_scatter_system.call("apply_brush", _current_tool, hit as Vector3, _brush_size, _brush_strength, _scatter_density, _scatter_scale_min, _scatter_scale_max, _scatter_rotation_randomness, _scatter_tilt)
		return
	if _current_tool.begins_with("grass"):
		if _grass_system != null and _water_system != null:
			var is_over_water: bool = _check_position_over_water(hit as Vector3)
			if not is_over_water and _grass_system.has_method("apply_brush"):
				_grass_system.call("apply_brush", _current_tool, hit as Vector3, _brush_size, _brush_strength)
		return
	if _current_tool == "texturepaint":
		if _terrain_node != null:
			var maps: Dictionary = _get_texture_maps(_selected_texture_id, 1024)
			if not maps.is_empty() and maps.has("albedo"):
				_terrain_node.call("apply_texture_brush", hit as Vector3, maps.get("albedo", null), maps.get("normal", null), maps.get("roughness", null), maps.get("height", null), maps.get("ao", null), _brush_size, _brush_strength, _texture_tile_size, _texture_density, _texture_edge_softness, _texture_coverage_limit, _texture_stroke_offset, _texture_stroke_rotation, _texture_stroke_scale, _texture_exposure, _texture_brush_shape_mode, _texture_shape_variation, _texture_stroke_seed, _texture_stroke_shape_variant)
		return
	if _current_tool == "textureerase":
		if _terrain_node != null:
			_terrain_node.call("apply_texture_erase_brush", hit as Vector3, _brush_size, _brush_strength, _texture_edge_softness)
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


func _check_position_over_water(world_pos: Vector3) -> bool:
	"""Check if a world position is over any active water surface using AABB collision."""
	if _water_system == null or not _water_system.has_method("get_rivers"):
		return false
	
	var rivers_variant: Variant = _water_system.call("get_rivers")
	if not (rivers_variant is Dictionary):
		return false
	var lakes: Dictionary = {}
	if _water_system.has_method("get_lakes"):
		var lakes_variant: Variant = _water_system.call("get_lakes")
		if lakes_variant is Dictionary:
			lakes = lakes_variant as Dictionary
	
	var rivers: Dictionary = rivers_variant as Dictionary
	var water_bodies: Array[Dictionary] = []
	for river_id in rivers:
		water_bodies.append(rivers[river_id])
	for lake_id in lakes:
		water_bodies.append(lakes[lake_id])
	var check_radius: float = _brush_size + 0.5
	var check_height: float = 1.0
	var check_aabb: AABB = AABB(
		world_pos - Vector3(check_radius, check_height, check_radius),
		Vector3(check_radius * 2.0, check_height * 2.0, check_radius * 2.0)
	)
	
	for water_body in water_bodies:
		var mesh_instance: MeshInstance3D = water_body.get("mesh_instance", null)
		if mesh_instance == null or not is_instance_valid(mesh_instance):
			continue
		
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		
		var mesh_aabb: AABB = mesh.get_aabb()
		var global_aabb: AABB = AABB(
			mesh_instance.global_position + mesh_aabb.position,
			mesh_aabb.size
		)
		
		if check_aabb.intersects(global_aabb):
			return true
	
	return false


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

	_brush_preview = BrushPreview.new()
	_brush_preview.name = "BrushPreview"
	add_child(_brush_preview)
	_brush_preview.visible = false

func _tool_uses_radius_preview(tool_name: String) -> bool:
	match tool_name:
		"raise", "lower", "smooth", "flatten", "paint", "grasspaint", "grasserase", "scatterpaint", "scattererase", "texturepaint", "textureerase", "waterpaint", "snowpaint":
			return true
		_:
			return false

func _is_character_control_active() -> bool:
	if _has_active_character():
		return true
	if camera_manager != null and camera_manager.has_method("has_follow_target"):
		return bool(camera_manager.call("has_follow_target"))
	return false

func _should_show_radius_preview() -> bool:
	return _tool_uses_radius_preview(_current_tool) and not _is_character_control_active()

func _handle_ctrl_wheel_radius(event: InputEventMouseButton) -> bool:
	if not _tool_uses_radius_preview(_current_tool):
		return false
	if _is_character_control_active():
		return false
	if get_viewport().gui_get_hovered_control() != null:
		return false
	var direction: float = 0.0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = 1.0
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = -1.0
	else:
		return false
	var step: float = maxf(BRUSH_RADIUS_WHEEL_STEP_MIN, _brush_size * BRUSH_RADIUS_WHEEL_STEP_SCALE)
	_set_brush_radius(_brush_size + (direction * step), true, true)
	return true

func _set_brush_radius(new_radius: float, show_status: bool = true, show_indicator: bool = true) -> void:
	var clamped_radius: float = clampf(new_radius, BRUSH_RADIUS_MIN, BRUSH_RADIUS_MAX)
	if is_equal_approx(clamped_radius, _brush_size):
		return
	_brush_size = clamped_radius
	if _terrain_node != null and _terrain_node.has_method("set_brush_preview_radius"):
		_terrain_node.call("set_brush_preview_radius", _brush_size)
	if _worldbrush_inspector != null and _worldbrush_inspector.has_method("set_brush_size"):
		_worldbrush_inspector.call("set_brush_size", _brush_size)
	_update_active_tool_feedback()
	if show_status:
		_set_status("Brush radius: %.1f" % _brush_size)
	if show_indicator:
		_show_radius_indicator()
	_refresh_brush_preview_at_mouse()

func _refresh_brush_preview_at_mouse() -> void:
	var hit: Variant = _get_mouse_world_position()
	if hit != null:
		_update_brush_preview(hit as Vector3)

func _ensure_radius_indicator() -> void:
	if _radius_indicator_label != null:
		return
	var root_ui: Control = get_node_or_null("EditorCanvas/RootUI") as Control
	if root_ui == null:
		return
	_radius_indicator_label = Label.new()
	_radius_indicator_label.name = "BrushRadiusIndicator"
	_radius_indicator_label.visible = false
	_radius_indicator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_radius_indicator_label.z_index = 300
	_radius_indicator_label.add_theme_font_size_override("font_size", 14)
	_radius_indicator_label.add_theme_color_override("font_color", Color(0.84, 0.97, 1.0, 0.98))
	_radius_indicator_label.add_theme_color_override("font_outline_color", Color(0.03, 0.09, 0.12, 0.95))
	_radius_indicator_label.add_theme_constant_override("outline_size", 2)
	root_ui.add_child(_radius_indicator_label)

func _show_radius_indicator() -> void:
	if _radius_indicator_label == null:
		return
	_radius_indicator_ttl = RADIUS_INDICATOR_DURATION_SEC
	_radius_indicator_label.text = "Radius %.1f" % _brush_size
	_radius_indicator_label.visible = true
	_update_radius_indicator_position()

func _tick_radius_indicator(delta: float) -> void:
	if _radius_indicator_label == null:
		return
	if _radius_indicator_ttl <= 0.0:
		if _radius_indicator_label.visible:
			_radius_indicator_label.visible = false
		return
	if not _should_show_radius_preview():
		_radius_indicator_ttl = 0.0
		_radius_indicator_label.visible = false
		return
	_radius_indicator_ttl = maxf(0.0, _radius_indicator_ttl - delta)
	if _radius_indicator_ttl > 0.0:
		_update_radius_indicator_position()

func _update_radius_indicator_position() -> void:
	if _radius_indicator_label == null:
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var target: Vector2 = mouse_pos + Vector2(18.0, 20.0)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var label_size: Vector2 = _radius_indicator_label.size
	target.x = clampf(target.x, 8.0, maxf(8.0, viewport_size.x - label_size.x - 8.0))
	target.y = clampf(target.y, 8.0, maxf(8.0, viewport_size.y - label_size.y - 8.0))
	_radius_indicator_label.position = target

func _update_brush_mode_visual_feedback() -> void:
	# Update brush preview colors based on current Shift key state
	if _current_tool == "raise" or _current_tool == "lower":
		if Input.is_key_pressed(KEY_SHIFT):
			_brush_mode = "sharp"
		else:
			_brush_mode = "smooth"
		if _worldbrush_inspector != null and _worldbrush_inspector.has_method("set_tool_state"):
			_worldbrush_inspector.call("set_tool_state", {
				"brush_mode": _brush_mode,
				"brush_softness": _brush_softness,
				"smooth_post_pass_enabled": _smooth_post_pass_enabled,
				"smooth_post_pass_strength": _smooth_post_pass_strength,
			})
		_refresh_brush_preview_at_mouse()

func _get_active_stroke_interval() -> float:
	if _current_tool in ["raise", "lower", "smooth", "flatten"]:
		if _brush_size >= 26.0:
			return 1.0 / 36.0
		if _brush_size >= 16.0:
			return 1.0 / 48.0
		if _brush_size >= 9.0:
			return 1.0 / 58.0
	return STROKE_INTERVAL_SEC

func _ensure_brush_mode_label() -> void:
	if _brush_mode_label != null:
		return
	
	var root_ui: Control = get_node_or_null("EditorCanvas/RootUI")
	if root_ui == null:
		return
	
	_brush_mode_label = Label.new()
	_brush_mode_label.name = "BrushModeIndicator"
	_brush_mode_label.visible = false
	_brush_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_brush_mode_label.z_index = 299  # Just below radius indicator
	_brush_mode_label.add_theme_font_size_override("font_size", 12)
	_brush_mode_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3, 0.95))
	_brush_mode_label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.0, 0.95))
	_brush_mode_label.add_theme_constant_override("outline_size", 2)
	root_ui.add_child(_brush_mode_label)

func _show_brush_mode_indicator() -> void:
	_ensure_brush_mode_label()
	if _brush_mode_label == null:
		return
	
	var mode_text: String = "SHARP" if _brush_mode == "sharp" else "SMOOTH"
	_brush_mode_label.text = mode_text
	_brush_mode_label.visible = true
	_update_brush_mode_indicator_position()

func _hide_brush_mode_indicator() -> void:
	if _brush_mode_label != null:
		_brush_mode_label.visible = false

func _update_brush_mode_indicator_position() -> void:
	if _brush_mode_label == null:
		return
	
	var root_ui: Control = get_node_or_null("EditorCanvas/RootUI")
	if root_ui == null:
		return
	
	if _radius_indicator_label == null or not _radius_indicator_label.visible:
		_brush_mode_label.position = Vector2(20.0, get_viewport().get_visible_rect().size.y - 60.0)
	else:
		# Position below the radius indicator
		var radius_pos: Vector2 = _radius_indicator_label.position
		var radius_size: Vector2 = _radius_indicator_label.size
		_brush_mode_label.position = radius_pos + Vector2(0.0, radius_size.y + 8.0)

func _update_live_previews() -> void:
	# Update terrain brush preview through terrain node if available
	if _terrain_node != null and _terrain_node.has_method("update_brush_preview"):
		_terrain_node.call("update_brush_preview", camera, get_viewport().get_mouse_position())
		if _terrain_node.has_method("set_brush_preview_enabled"):
			# Keep the built-in terrain decal preview disabled in favor of the volumetric sphere.
			_terrain_node.call("set_brush_preview_enabled", false)

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

	# Determine preview colors for tools that use a radius overlay.
	var base_color: Color = Color(0.28, 0.82, 0.72, 0.07)
	var rim_color: Color = Color(0.70, 0.98, 0.88, 0.88)
	
	match _current_tool:
		"raise", "lower", "smooth", "paint":
			base_color = Color(0.26, 0.84, 0.70, 0.07)
			rim_color = Color(0.64, 0.99, 0.86, 0.88)
		"flatten":
			base_color = Color(0.34, 0.86, 0.64, 0.07)
			rim_color = Color(0.76, 1.0, 0.82, 0.86)
		"waterpaint":
			base_color = Color(0.16, 0.78, 1.0, 0.08)
			rim_color = Color(0.54, 0.92, 1.0, 0.92)
		"snowpaint":
			base_color = Color(0.88, 0.95, 1.0, 0.09)
			rim_color = Color(0.96, 1.0, 1.0, 0.90)
		"texturepaint":
			base_color = Color(0.66, 0.52, 0.96, 0.08)
			rim_color = Color(0.86, 0.76, 1.0, 0.90)
		"textureerase":
			base_color = Color(0.56, 0.62, 0.92, 0.07)
			rim_color = Color(0.76, 0.84, 0.98, 0.84)
		"grasspaint", "grasserase":
			base_color = Color(0.36, 0.82, 0.38, 0.07)
			rim_color = Color(0.66, 0.97, 0.58, 0.84)
		"scatterpaint", "scattererase":
			base_color = Color(0.89, 0.76, 0.38, 0.07)
			rim_color = Color(0.99, 0.90, 0.62, 0.84)
	
	# Apply sharp mode visual feedback (warm red/orange tone)
	if _brush_mode == "sharp" and (_current_tool == "raise" or _current_tool == "lower"):
		rim_color = Color(1.0, 0.65, 0.35, 0.95)  # Orange/red for sharp mode
	
	if not _should_show_radius_preview():
		_brush_preview.hide_preview()
		return
	
	# Show and position the volumetric radius bubble.
	_brush_preview.show_preview()
	_brush_preview.update_colors(base_color, rim_color)
	_brush_preview.update_radius(_brush_size)
	_brush_preview.update_world_position(world_pos)

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
	_collect_prefabs("res://assets/world/models", all)
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
		var entry_name := dir.get_next()
		if entry_name == "":
			break
		if entry_name.begins_with("."):
			continue
		var full := "%s/%s" % [path, entry_name]
		if dir.current_is_dir():
			_collect_prefabs(full, out)
		elif entry_name.ends_with(".tscn"):
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
	if _terrain_node != null and _terrain_node.has_method("getHeightAtPosition"):
		return float(_terrain_node.call("getHeightAtPosition", x, z, true))
	if _terrain_node != null and _terrain_node.has_method("get_data"):
		var data: Variant = _terrain_node.call("get_data")
		if data != null and data is Object and (data as Object).has_method("get_height"):
			var h: Variant = (data as Object).call("get_height", Vector3(x, 0.0, z))
			if h is float:
				return h
			if h is int:
				return float(h)
	return 0.0

func _get_worldbrush_node() -> Node:
	if terrain_placeholder == null:
		return null
	return terrain_placeholder.find_child("WorldBrush", true, false)

func _get_chunked_worldbrush_node() -> Node:
	if terrain_placeholder == null:
		return null
	return terrain_placeholder.find_child("ChunkedWorldBrush", true, false)

func _get_terrabrush_node() -> Node:
	if terrain_placeholder == null:
		return null
	return terrain_placeholder.find_child("TerraBrush", true, false)

func _get_terrabrush_editor_node() -> Node:
	if terrain_placeholder == null:
		return null
	return terrain_placeholder.find_child("TerraBrushEditor", true, false)

func _get_texture_maps(texture_id: String, target_size: int = 1024) -> Dictionary:
	if _texture_painter != null and _texture_painter.has_method("get_pbr_maps"):
		var painter_texture_id: String = texture_id
		if painter_texture_id.is_empty() and _texture_painter.has_method("get"):
			painter_texture_id = String(_texture_painter.get("selected_texture_id"))
		if painter_texture_id != "":
			var painter_maps: Variant = _texture_painter.call("get_pbr_maps", painter_texture_id, target_size)
			if painter_maps is Dictionary and not (painter_maps as Dictionary).is_empty():
				return painter_maps
	if texture_id.is_empty():
		return {}

	var texture_folder: String = texture_id
	if not texture_folder.begins_with("res://"):
		texture_folder = "res://assets/world/textures/world/%s" % texture_id
	var texture_dir: DirAccess = DirAccess.open(texture_folder)
	if texture_dir == null:
		return {}

	var maps: Dictionary = {}
	texture_dir.list_dir_begin()
	var file_name: String = texture_dir.get_next()
	while file_name != "":
		if texture_dir.current_is_dir() or file_name.begins_with("."):
			file_name = texture_dir.get_next()
			continue
		var lower_name: String = file_name.to_lower()
		var resource_path: String = "%s/%s" % [texture_folder, file_name]
		if not lower_name.ends_with(".png") and not lower_name.ends_with(".jpg") and not lower_name.ends_with(".jpeg") and not lower_name.ends_with(".webp"):
			file_name = texture_dir.get_next()
			continue
		if lower_name.find("color") != -1 or lower_name.find("basecolor") != -1 or lower_name.find("base_color") != -1 or lower_name.find("albedo") != -1:
			maps["albedo"] = load(resource_path)
		elif lower_name.find("normal") != -1:
			maps["normal"] = load(resource_path)
		elif lower_name.find("roughness") != -1:
			maps["roughness"] = load(resource_path)
		elif lower_name.find("height") != -1:
			maps["height"] = load(resource_path)
		elif lower_name.find("ambientocclusion") != -1 or lower_name.find("ambient_occlusion") != -1 or lower_name.find("ao") != -1:
			maps["ao"] = load(resource_path)
		file_name = texture_dir.get_next()
	texture_dir.list_dir_end()

	if not maps.has("albedo"):
		texture_dir = DirAccess.open(texture_folder)
		if texture_dir != null:
			texture_dir.list_dir_begin()
			file_name = texture_dir.get_next()
			while file_name != "":
				if not texture_dir.current_is_dir() and file_name.to_lower().ends_with(".png"):
					maps["albedo"] = load("%s/%s" % [texture_folder, file_name])
					break
				file_name = texture_dir.get_next()
			texture_dir.list_dir_end()
	return maps

func _ensure_worldbrush_menu() -> void:
	if _worldbrush_menu != null:
		return
	var root_ui: Control = get_node_or_null("EditorCanvas/RootUI") as Control
	if root_ui == null:
		return
	var instance: Variant = WORLDBRUSH_RADIAL_MENU_SCRIPT.new()
	if not (instance is Control):
		return
	_worldbrush_menu = instance as Control
	_worldbrush_menu.name = "WorldBrushRadialMenu"
	root_ui.add_child(_worldbrush_menu)
	if _worldbrush_menu.has_signal("tool_selected"):
		_worldbrush_menu.connect("tool_selected", Callable(self, "_on_worldbrush_tool_selected"))
	if _worldbrush_menu.has_signal("radius_changed"):
		_worldbrush_menu.connect("radius_changed", Callable(self, "_on_worldbrush_radius_changed"))
	if _worldbrush_menu.has_signal("strength_changed"):
		_worldbrush_menu.connect("strength_changed", Callable(self, "_on_worldbrush_strength_changed"))

func _ensure_worldbrush_inspector() -> void:
	if _worldbrush_inspector != null:
		return
	var layout: VBoxContainer = get_node_or_null("EditorCanvas/RootUI/Layout") as VBoxContainer
	if layout == null:
		return
	var instance: Variant = WORLDBRUSH_INSPECTOR_SCRIPT.new()
	if not (instance is Control):
		return
	_worldbrush_inspector = instance as Control
	_worldbrush_inspector.name = "WorldBrushInspector"
	# Add inspector directly to root for absolute positioning at far right
	var root_ui: Control = get_node_or_null("EditorCanvas/RootUI")
	if root_ui != null:
		root_ui.add_child(_worldbrush_inspector)
		_worldbrush_inspector.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		_worldbrush_inspector.offset_right = 0
		var panel_width: float = 420.0
		if _worldbrush_inspector.has_method("get_panel_width"):
			panel_width = float(_worldbrush_inspector.call("get_panel_width"))
		_worldbrush_inspector.offset_left = -panel_width
		_worldbrush_inspector.offset_top = 44  # Below menu bar
		_worldbrush_inspector.offset_bottom = 0
	if _worldbrush_inspector.has_signal("brush_size_changed"):
		_worldbrush_inspector.connect("brush_size_changed", Callable(self, "_on_inspector_brush_size_changed"))
	if _worldbrush_inspector.has_signal("brush_strength_changed"):
		_worldbrush_inspector.connect("brush_strength_changed", Callable(self, "_on_inspector_brush_strength_changed"))
	if _worldbrush_inspector.has_signal("layer_changed"):
		_worldbrush_inspector.connect("layer_changed", Callable(self, "_on_inspector_layer_changed"))
	if _worldbrush_inspector.has_signal("tool_setting_changed"):
		_worldbrush_inspector.connect("tool_setting_changed", Callable(self, "_on_inspector_tool_setting_changed"))
	if _worldbrush_inspector.has_signal("environment_setting_changed"):
		_worldbrush_inspector.connect("environment_setting_changed", Callable(self, "_on_inspector_environment_setting_changed"))
	_sync_environment_inspector()

func _on_inspector_brush_size_changed(size: float) -> void:
	_set_brush_radius(size, false, false)

func _on_inspector_brush_strength_changed(strength: float) -> void:
	_brush_strength = strength

func _on_inspector_layer_changed(layer: int) -> void:
	set_active_world_layer(layer)

func _on_inspector_tool_setting_changed(setting: String, value: Variant) -> void:
	_on_tool_setting_changed(setting, value)


func _on_inspector_environment_setting_changed(setting: String, value: Variant) -> void:
	_on_tool_setting_changed(setting, value)

func _open_worldbrush_radial_hold() -> void:
	_ensure_worldbrush_menu()
	if _worldbrush_menu == null:
		return
	_worldbrush_menu.call("open_hold", get_viewport().get_mouse_position(), _current_tool, _brush_size, _brush_strength)

func _confirm_worldbrush_radial_hold() -> void:
	if _worldbrush_menu == null:
		return
	if _worldbrush_menu.has_method("confirm_current"):
		_worldbrush_menu.call("confirm_current")

func _on_worldbrush_tool_selected(tool_name: String) -> void:
	_switch_tool(tool_name)
	_update_worldbrush_inspector_for_tool(tool_name)
	_update_tool_name_display()
	_set_status("WorldBrush tool: %s" % _format_tool_name(tool_name))

func _update_worldbrush_inspector_for_tool(tool_name: String) -> void:
	if _worldbrush_inspector == null:
		return
	var icon_path: String = ""
	match tool_name:
		"raise":        icon_path = "res://addons/worldbrush/Assets/Icons/map_add.png"
		"lower":        icon_path = "res://addons/worldbrush/Assets/Icons/map_remove.png"
		"smooth":       icon_path = "res://addons/worldbrush/Assets/Icons/map_smooth.png"
		"flatten":      icon_path = "res://addons/worldbrush/Assets/Icons/map_set_height.png"
		"paint":        icon_path = "res://addons/worldbrush/Assets/Icons/paint.png"
		"texturepaint": icon_path = "res://addons/worldbrush/Assets/Icons/paint_withdot.png"
		"grasspaint":   icon_path = "res://addons/worldbrush/Assets/Icons/foliage_add.png"
		"waterpaint":   icon_path = "res://addons/worldbrush/Assets/Icons/water_add.png"
		"snowpaint":    icon_path = "res://addons/worldbrush/Assets/Icons/snow_add.png"
		"riverdraw":    icon_path = "res://addons/worldbrush/Assets/Icons/flow_add.png"
		"wall":         icon_path = "res://addons/worldbrush/Assets/Icons/lock_add.png"
		"stamp":        icon_path = "res://addons/worldbrush/Assets/Icons/object_add.png"
	if _worldbrush_inspector.has_method("set_tool"):
		_worldbrush_inspector.call("set_tool", tool_name, icon_path)
	# Sync current brush values into the inspector
	if _worldbrush_inspector.has_method("set_brush_size"):
		_worldbrush_inspector.call("set_brush_size", _brush_size)
	if _worldbrush_inspector.has_method("set_brush_strength"):
		_worldbrush_inspector.call("set_brush_strength", _brush_strength)
	if _worldbrush_inspector.has_method("set_active_layer"):
		_worldbrush_inspector.call("set_active_layer", _active_world_layer)
	if _worldbrush_inspector.has_method("set_tool_state"):
		var toolbar_settings: Dictionary = world_tools.call("get_settings") if world_tools != null and world_tools.has_method("get_settings") else {}
		_worldbrush_inspector.call("set_tool_state", {
			"brush_mode": _brush_mode,
			"brush_softness": _brush_softness,
			"smooth_post_pass_enabled": _smooth_post_pass_enabled,
			"smooth_post_pass_strength": _smooth_post_pass_strength,
			"selected_texture_id": _selected_texture_id,
			"world_layer": _active_world_layer,
			"wall_type": String(toolbar_settings.get("wall_type", "stone")),
			"wall_height": float(toolbar_settings.get("wall_height", 3.4)),
			"wall_rect_mode": bool(toolbar_settings.get("wall_rect_mode", false)),
			"wall_match_connected_heights": bool(toolbar_settings.get("wall_match_connected_heights", true)),
			"wall_add_foundation": bool(toolbar_settings.get("wall_add_foundation", true)),
			"wall_opening_height_snap": bool(toolbar_settings.get("wall_opening_height_snap", true)),
			"wall_jitter": bool(toolbar_settings.get("wall_jitter", true)),
			"river_width": float(toolbar_settings.get("river_width", _river_width)),
			"river_flow_speed": float(toolbar_settings.get("river_flow_speed", _river_flow_speed)),
			"river_average_depth": float(toolbar_settings.get("river_average_depth", _river_average_depth)),
			"water_mode": String(toolbar_settings.get("water_mode", _water_mode)),
		})
	if _texture_painter != null and _worldbrush_inspector.has_method("set_texture_painter"):
		_worldbrush_inspector.call("set_texture_painter", _texture_painter)

func _update_tool_name_display() -> void:
	if _tool_name_display == null:
		var menu_panel: Panel = get_node_or_null("EditorCanvas/RootUI/Layout/TopBar/MenuPanel") as Panel
		if menu_panel == null:
			return
		_tool_name_display = Label.new()
		_tool_name_display.name = "ToolNameDisplay"
		_tool_name_display.custom_minimum_size = Vector2(280, 0)
		_tool_name_display.add_theme_font_size_override("font_size", 13)
		var bold_font = ThemeDB.fallback_font
		if bold_font != null:
			_tool_name_display.add_theme_font_override("font", bold_font)
		_tool_name_display.add_theme_font_size_override("font_size", 14)
		_tool_name_display.add_theme_color_override("font_color", Color(0.88, 0.92, 0.96, 1.0))
		menu_panel.add_child(_tool_name_display)
		menu_panel.move_child(_tool_name_display, 1)
	if _tool_name_display != null:
		var mode_text: String = "GM Mode" if not get_tree().paused else "Player Mode"
		var tool_display_name: String = _format_tool_name(_current_tool)
		var display_text: String = tool_display_name if tool_display_name != "None" else mode_text
		_tool_name_display.text = "  ▸  " + display_text

func _on_worldbrush_radius_changed(radius: float) -> void:
	_set_brush_radius(radius, true, true)

func _on_worldbrush_strength_changed(strength: float) -> void:
	_brush_strength = clampf(strength, 0.05, 1.0)
	_set_status("Brush strength: %.2f" % _brush_strength)

func _ensure_terrain_node() -> Node:
	if use_chunked_terrain:
		var chunked_node: Node = _get_chunked_worldbrush_node()
		if chunked_node == null:
			for child in terrain_placeholder.get_children():
				child.queue_free()
			var chunked_root := Node3D.new()
			chunked_root.name = "ChunkedWorldBrush"
			chunked_root.set_script(CHUNKED_WORLDBRUSH_SCRIPT)
			terrain_placeholder.add_child(chunked_root)
			chunked_node = chunked_root
		if chunked_node != null and chunked_node.has_method("set_world_layer"):
			chunked_node.call("set_world_layer", _active_world_layer)
		if chunked_node != null and chunked_node.has_method("set_full_rebuild_mode"):
			chunked_node.call("set_full_rebuild_mode", _terrain_full_rebuild_mode)
		if chunked_node != null and chunked_node.has_method("set_debug_draw_chunk_borders"):
			chunked_node.call("set_debug_draw_chunk_borders", debug_draw_chunk_borders)
		if chunked_node != null and chunked_node.has_method("set_debug_draw_chunk_borders_red"):
			chunked_node.call("set_debug_draw_chunk_borders_red", debug_draw_chunk_borders_red)
		return chunked_node

	var worldbrush_node: Node = _get_worldbrush_node()
	if worldbrush_node == null and WORLDBRUSH_RUNTIME_ROOT_SCENE != null and terrain_placeholder != null:
		for child in terrain_placeholder.get_children():
			child.queue_free()
		var runtime_root: Node = WORLDBRUSH_RUNTIME_ROOT_SCENE.instantiate()
		terrain_placeholder.add_child(runtime_root)
		worldbrush_node = _get_worldbrush_node()
	if worldbrush_node != null:
		if worldbrush_node.has_method("set_world_layer"):
			worldbrush_node.call("set_world_layer", _active_world_layer)
		if worldbrush_node.has_method("set_full_rebuild_mode"):
			worldbrush_node.call("set_full_rebuild_mode", _terrain_full_rebuild_mode)
		return worldbrush_node

	var terrabrush_node: Node = _get_terrabrush_node()
	if terrabrush_node != null:
		return terrabrush_node

	for child in terrain_placeholder.get_children():
		child.queue_free()

	# Runtime safe mode: TerraBrush native init currently crashes in libterrabrush.macos.debug.
	# Keep editor stable with a simple fallback ground until the extension-side crash is resolved.
	var ground := MeshInstance3D.new()
	ground.name = "FallbackGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(256, 256)
	ground.mesh = plane
	var fallback_mat := StandardMaterial3D.new()
	fallback_mat.albedo_color = Color(0.26, 0.30, 0.24, 1.0)
	fallback_mat.roughness = 0.92
	fallback_mat.metallic = 0.0
	fallback_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ground.material_override = fallback_mat
	terrain_placeholder.add_child(ground)
	return terrain_placeholder

func _set_use_chunked_terrain(enabled: bool) -> void:
	use_chunked_terrain = enabled
	_sync_configuration_menu_state()
	_set_status("Chunked Terrain: %s. Create a new map to test this backend safely." % ("On" if use_chunked_terrain else "Off"))

func _set_debug_draw_chunk_borders(enabled: bool) -> void:
	debug_draw_chunk_borders = enabled
	if _terrain_node != null and _terrain_node.has_method("set_debug_draw_chunk_borders"):
		_terrain_node.call("set_debug_draw_chunk_borders", debug_draw_chunk_borders)
	_sync_configuration_menu_state()
	_set_status("Chunk Border Debug: %s" % ("On" if debug_draw_chunk_borders else "Off"))

func _set_debug_draw_chunk_borders_red(enabled: bool) -> void:
	debug_draw_chunk_borders_red = enabled
	if _terrain_node != null and _terrain_node.has_method("set_debug_draw_chunk_borders_red"):
		_terrain_node.call("set_debug_draw_chunk_borders_red", debug_draw_chunk_borders_red)
	_sync_configuration_menu_state()
	_set_status("Chunk Border Debug Red: %s" % ("On" if debug_draw_chunk_borders_red else "Off"))

func _set_debug_highlight_problem_borders(enabled: bool) -> void:
	debug_highlight_problem_borders = enabled
	if _terrain_node != null and _terrain_node.has_method("set_debug_highlight_problem_borders"):
		_terrain_node.call("set_debug_highlight_problem_borders", debug_highlight_problem_borders)
	_sync_configuration_menu_state()
	_set_status("Highlight Problem Borders: %s" % ("On" if debug_highlight_problem_borders else "Off"))

func _sync_configuration_menu_state() -> void:
	if menu_bar != null and menu_bar.has_method("set_action_checked"):
		menu_bar.call("set_action_checked", "config_toggle_chunked_terrain", use_chunked_terrain)
		menu_bar.call("set_action_checked", "config_toggle_chunk_borders", debug_draw_chunk_borders)
		menu_bar.call("set_action_checked", "config_toggle_chunk_borders_red", debug_draw_chunk_borders_red)
		menu_bar.call("set_action_checked", "config_toggle_chunk_borders_highlight", debug_highlight_problem_borders)

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
		"version": 3,
		"saved_at": Time.get_datetime_string_from_system(true, true),
		"walls": {},
		"scatter": {},
		"stamps": [],
		"terrain": {},
		"horizon_mountains": [],
		"sky3d": {}
	}
	var wall_system: Node = _get_or_create_wall_system()
	if wall_system != null and wall_system.has_method("save_data"):
		data["walls"] = wall_system.call("save_data")
	if _scatter_system != null and _scatter_system.has_method("serialize_state"):
		data["scatter"] = _scatter_system.call("serialize_state")
	data["stamps"] = _serialize_stamp_instances()
	data["terrain"] = _serialize_terrain_data()
	data["sky3d"] = _export_sky_state()
	if _horizon_system != null and is_instance_valid(_horizon_system) and _horizon_system.has_method("serialize"):
		data["horizon_mountains"] = _horizon_system.call("serialize")
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
	var scatter_data: Dictionary = data.get("scatter", {})
	var stamp_data: Array = data.get("stamps", [])
	var terrain_data: Dictionary = data.get("terrain", {})
	var horizon_data: Array = data.get("horizon_mountains", [])
	var sky_data: Dictionary = data.get("sky3d", {})
	var wall_system: Node = _get_or_create_wall_system()
	if wall_system != null and wall_system.has_method("load_data"):
		wall_system.call("load_data", wall_data)
	if _scatter_system != null and _scatter_system.has_method("load_state"):
		_scatter_system.call("load_state", scatter_data)
	_deserialize_stamp_instances(stamp_data)
	_deserialize_terrain_data(terrain_data)
	_import_sky_state(sky_data)
	if _horizon_system != null and is_instance_valid(_horizon_system) and _horizon_system.has_method("deserialize"):
		_horizon_system.call("deserialize", horizon_data)
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
