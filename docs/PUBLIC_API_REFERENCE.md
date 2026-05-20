# PaperVTT Public API Reference

**Version**: Comprehensive API Documentation  
**Last Updated**: 2026-05-17  
**Scope**: External developer-facing APIs for PaperVTT game engine

---

## Table of Contents

1. [Main Game Controller](#main-game-controller)
2. [Terrain System](#terrain-system--worldbrush)
3. [Character System](#character-system)
4. [World Systems](#world-systems)
5. [Environment & Lighting](#environment--lighting-system)
6. [Signals](#signals)
7. [Constants](#constants)
8. [Usage Notes](#usage-notes)

---

## Main Game Controller

**File**: `scripts/main/main_controller.gd`  
**Type**: `extends Node3D`  
**Description**: Central game controller managing all editor tools, terrain, characters, environment, and save/load systems.

### Properties (Exported Variables)

- `terrain_placeholder: Node3D` — Reference to the terrain root node
- `camera: Camera3D` — Main viewport camera
- `camera_manager: Node` — PhantomCamera3D manager for camera control
- `stamp_root: Node3D` — Root node for stamped prefabs
- `menu_bar: MenuBar` — Main menu bar UI component
- `world_tools: PanelContainer` — World tools toolbar panel
- `asset_browser: PanelContainer` — Asset browser UI
- `status_label: Label` — Status/feedback label
- `time_weather_panel: Control` — Time and weather control panel
- `sky_3d: Node` — Sky3D addon integration
- `sun_light: DirectionalLight3D` — Directional light for sun

### Public Signals

```gdscript
signal sky_state_changed(time_hours: float, weather_id: String)
```
Emitted when time of day or weather changes. Use this to synchronize networked or external systems with environment state.

### Public Functions

#### World Layer Management

```gdscript
func set_active_world_layer(layer: int) -> void
```
- **Parameters**: 
  - `layer: int` — Layer index (0-based)
- **Returns**: `void`
- **Description**: Switch the active world editing layer. Terrain, water, and scatter systems respond to layer changes.
- **Usage**: Call when switching editing context or when user selects a different layer.

```gdscript
func get_active_world_layer() -> int
```
- **Parameters**: None
- **Returns**: `int` — Current active layer index
- **Description**: Query the currently active world layer.
- **Usage**: Use before applying terrain modifications to ensure correct layer targeting.

#### Terrain System Access

**Note**: Terrain manipulation is primarily handled via `TerrainRuntimeEditor` (see below), but the main controller provides high-level access.

- `_terrain_node: Node` — Internal reference (private, but accessible via `get_node_or_null` pattern)
- `_runtime_terrain_editor: TerrainRuntimeEditor` — Terrain editor instance (private)

### Public Exported Constants

Weather/Time Constants:
```gdscript
const WEATHER_NORMAL: String = "normal"
const WEATHER_RAIN: String = "rain"
const WEATHER_SNOW: String = "snow"
const WEATHER_FOGGY: String = "foggy"
const WEATHER_STORMY: String = "stormy"

const DAY_START_HOUR: float = 7.0
const DAY_END_HOUR: float = 19.0
const AFTERNOON_START_HOUR: float = 10.0
const AFTERNOON_END_HOUR: float = 16.0
const DEFAULT_SUNRISE_HOUR: float = 7.0
const DEFAULT_SUNSET_HOUR: float = 19.0
```

Performance & Rendering:
```gdscript
const PREFAB_VISIBILITY_END_NEAR: float = 170.0
const PREFAB_VISIBILITY_END_FAR: float = 260.0
const HORIZON_MOUNTAIN_PLACE_DISTANCE: float = 3000.0
```

---

## Terrain System (WorldBrush)

**File**: `addons/worldbrush/worldbrush.gd`  
**Type**: `extends Node3D, class_name WorldBrush`  
**Description**: Multi-layer heightmap terrain with support for painting, snow, water, and sculpting.

### Exported Properties

```gdscript
@export var terrain_size: float = 256.0              # World-space terrain dimensions (meters)
@export var terrain_resolution: int = 96             # Heightmap resolution (grid points per edge)
@export var max_terrain_height: float = 38.0         # Maximum heightmap value
@export var min_terrain_height: float = -14.0        # Minimum heightmap value
@export var seed_initial_terrain: bool = true        # Auto-seed with procedural noise on init
@export var auto_test_snow: bool = true              # Apply procedural snow at startup
@export var dirty_rect_border: int = 4               # Dirty region expansion for mesh updates
@export var debug_visualize_dirty_rect: bool = false # Show dirty regions for performance tuning
```

### Public Properties

```gdscript
var dirty_min: Vector2i = Vector2i.ZERO         # Dirty rectangle bounds (min corner)
var dirty_max: Vector2i = Vector2i.ZERO         # Dirty rectangle bounds (max corner)
var is_dirty: bool = false                      # Whether mesh rebuild is needed
```

### Public Functions

#### Layer Management

```gdscript
func set_world_layer(layer: int) -> void
```
- **Parameters**: `layer: int` — Layer index
- **Returns**: `void`
- **Description**: Switch active editing layer and rebuild mesh for new layer data.
- **Usage**: Call when user selects a different terrain layer.

```gdscript
func get_world_layer() -> int
```
- **Parameters**: None
- **Returns**: `int` — Current active layer
- **Description**: Query the currently active layer.

#### Build Mode Control

```gdscript
func set_full_rebuild_mode(enabled: bool) -> void
```
- **Parameters**: `enabled: bool` — Enable full rebuild vs. dirty-rect-based optimization
- **Returns**: `void`
- **Description**: Toggle between full mesh rebuild (slower, highest quality) and dirty-rectangle partial updates (faster).
- **Usage**: Set to `false` for performance; `true` for critical edits where artifacts must be avoided.

```gdscript
func get_full_rebuild_mode() -> bool
```
- **Parameters**: None
- **Returns**: `bool` — Current rebuild mode
- **Description**: Check if full rebuild mode is active.

#### Brush Preview

```gdscript
func set_brush_preview_enabled(enabled: bool) -> void
```
- **Parameters**: `enabled: bool` — Show/hide brush outline
- **Returns**: `void`
- **Description**: Toggle the brush radius preview ring.
- **Usage**: Disable for cleaner screenshots or when user preference is set.

```gdscript
func set_brush_preview_radius(radius: float) -> void
```
- **Parameters**: `radius: float` — Brush radius in meters (clamped to ≥0.5)
- **Returns**: `void`
- **Description**: Update the brush preview size.
- **Usage**: Call when user adjusts brush size slider.

```gdscript
func update_brush_preview(camera: Camera3D, mouse_pos: Vector2) -> void
```
- **Parameters**:
  - `camera: Camera3D` — Camera for ray projection
  - `mouse_pos: Vector2` — Screen-space mouse position
- **Returns**: `void`
- **Description**: Update brush preview position via ray-cast from camera.
- **Usage**: Call each frame in `_process()` to track mouse; pass viewport mouse position.

#### Height Queries

```gdscript
func sample_height(world_x: float, world_z: float) -> float
```
- **Parameters**:
  - `world_x: float` — World X coordinate
  - `world_z: float` — World Z coordinate
- **Returns**: `float` — Interpolated heightmap value at (world_x, world_z)
- **Description**: Bilinear interpolated height query. Returns `global_position.y + heightmap_sample`.
- **Usage**: Sample terrain height before placing objects or characters.
- **Important**: Pass scalars, not Vector3. Incorrect call: `sample_height(pos_vector3)` ❌ Correct: `sample_height(pos.x, pos.z)` ✓

```gdscript
func get_intersection(origin: Vector3, direction: Vector3, _with_water: bool = true) -> Variant
```
- **Parameters**:
  - `origin: Vector3` — Ray origin (world space)
  - `direction: Vector3` — Ray direction (normalized or unit length recommended)
  - `_with_water: bool = true` — [Unused] Reserved for future water raycast
- **Returns**: `Variant` — Either `Vector3` intersection point or `null` if no hit
- **Description**: Ray-terrain intersection using horizontal plane projection.
- **Usage**: Use for click-to-place operations.
- **Note**: Returns adjusted Y from heightmap; raycast is against the flat terrain plane at global_position.y.

#### Terrain Sculpting

```gdscript
func apply_brush(
    tool_name: String,
    world_pos: Vector3,
    brush_size: float,
    brush_strength: float,
    flatten_height: float = 0.0,
    _cliff_mode: bool = false,
    _overhang_amount: float = 0.3
) -> void
```
- **Parameters**:
  - `tool_name: String` — Tool identifier
  - `world_pos: Vector3` — Center of brush in world space
  - `brush_size: float` — Brush radius (≥0.5)
  - `brush_strength: float` — Effect magnitude (typically 0.01–1.0)
  - `flatten_height: float = 0.0` — Target height for flatten tool
  - `_cliff_mode: bool = false` — [Unused] Reserved
  - `_overhang_amount: float = 0.3` — [Unused] Reserved
- **Returns**: `void`
- **Description**: Apply a brush stroke to the active layer.

**Supported Tool Names**:
- `"raise"` — Raise terrain
- `"lower"` — Lower terrain
- `"smooth"` — Smooth with neighbor average
- `"flatten"` — Flatten to target height
- `"paint"` — Paint color (0–1 grayscale)
- `"texturepaint"` — Paint texture with strength modulation
- `"textureerase"` — Erase texture (reduce paint value)
- `"waterpaint"` — Carve water basin (lowers, wets, paints)
- `"watererase"` — Remove water (raise, dry, unpaint)
- `"snowpaint"` — Add snow coverage (0–1)
- `"snowerase"` — Remove snow

**Usage**:
```gdscript
terrain.apply_brush("raise", mouse_world_pos, 10.0, 0.5)
```

#### Texture Painting

```gdscript
func begin_texture_stroke(_perf_mode: bool = true, _brush_radius: float = 8.0) -> void
```
- **Parameters**:
  - `_perf_mode: bool = true` — [Placeholder] Reserved
  - `_brush_radius: float = 8.0` — [Placeholder] Reserved
- **Returns**: `void`
- **Description**: Begin a texture stroke session (currently a no-op; included for API consistency).

```gdscript
func apply_texture_brush(
    world_pos: Vector3,
    _albedo: Texture2D = null,
    _normal: Texture2D = null,
    _roughness: Texture2D = null,
    _height: Texture2D = null,
    _ao: Texture2D = null,
    brush_size: float = 8.0,
    brush_strength: float = 0.3,
    _tile_size: float = 4.0,
    density: float = 0.75,
    _softness: float = 0.7,
    _coverage: float = 0.75,
    _offset: Vector2 = Vector2.ZERO,
    _rot: float = 0.0,
    _scale: float = 1.0,
    _exposure: float = 1.0,
    _shape: String = "circle",
    _variation: float = 0.0,
    _seed: float = 0.0,
    _variant: int = 0
) -> void
```
- **Parameters**: (Most are placeholders; only used ones are below)
  - `world_pos: Vector3` — Brush center
  - `brush_size: float = 8.0` — Brush radius
  - `brush_strength: float = 0.3` — Effect magnitude
  - `density: float = 0.75` — Paint coverage factor (0–1)
- **Returns**: `void`
- **Description**: Apply texture paint; internally calls `apply_brush("texturepaint", ...)`.
- **Note**: Texture asset references are currently unused; the function applies paint layer only.

```gdscript
func apply_texture_erase_brush(
    world_pos: Vector3,
    brush_size: float = 8.0,
    brush_strength: float = 0.3,
    _softness: float = 0.7
) -> void
```
- **Parameters**: (See `apply_texture_brush`)
- **Returns**: `void`
- **Description**: Erase texture paint; calls `apply_brush("textureerase", ...)`.

```gdscript
func end_texture_stroke() -> void
```
- **Parameters**: None
- **Returns**: `void`
- **Description**: End a texture stroke session (currently a no-op).

#### Snow & Procedural Effects

```gdscript
func apply_procedural_snow(
    min_height: float = 2.0,
    max_height: float = 22.0,
    intensity: float = 0.8
) -> void
```
- **Parameters**:
  - `min_height: float = 2.0` — Height threshold where snow starts
  - `max_height: float = 22.0` — Height where snow reaches full intensity
  - `intensity: float = 0.8` — Peak snow coverage (0–1)
- **Returns**: `void`
- **Description**: Procedurally paint snow based on elevation using inverse lerp.
- **Usage**: Call at map start or as environment effect.
- **Example**:
```gdscript
terrain.apply_procedural_snow(5.0, 20.0, 0.9)  # Heavy snow above 5m, full above 20m
```

### Mesh & Performance

```gdscript
func rebuild_mesh() -> void
```
- **Parameters**: None
- **Returns**: `void` (private, but documented for completeness)
- **Description**: Rebuild terrain mesh (queued internally; not typically called directly).

---

## Character System

**File**: `scripts/characters/character_controller.gd`  
**Type**: `extends CharacterBody3D, class_name CharacterController`  
**Description**: Player-controlled character with animation, movement, and selection state.

### Exported Properties

```gdscript
@export var walk_speed: float = 5.0                          # Walking speed (m/s)
@export var run_speed: float = 8.0                           # Running speed when Shift held (m/s)
@export var acceleration: float = 20.0                       # Ground acceleration (m/s²)
@export var air_acceleration: float = 7.0                    # Air acceleration during jump (m/s²)
@export var jump_velocity: float = 5.8                       # Jump height (m/s, converted to velocity)
@export var gravity_multiplier: float = 1.0                  # Multiplier for world gravity
@export var click_stop_distance: float = 0.2                 # Distance to target before stopping (m)
@export var rotate_speed: float = 10.0                       # Rotation speed for facing direction
@export var move_mode: int = 0                               # 0=camera_relative, 1=world_axes
@export var extra_animation_scenes: Array[PackedScene] = [] # Additional animation assets
@export var preferred_idle_animation: String = ""           # Animation name for idle state
@export var preferred_walk_animation: String = ""           # Animation name for walk state
@export var preferred_run_animation: String = ""            # Animation name for run state
@export var preferred_jump_animation: String = ""           # Animation name for jump state

@export_node_path("NavigationAgent3D") var navigation_agent_path: NodePath
@export_node_path("Node3D") var model_root_path: NodePath
```

### Signals

```gdscript
signal selection_changed(character: CharacterController, selected: bool)
```
Emitted when character selection state changes. Use to update UI or gameplay state.

### Static Properties

```gdscript
static var active_controller: CharacterController = null  # Currently selected character (singleton)
```

### Public Functions

```gdscript
func initialize_controller(cam: Camera3D, terrain: Node) -> void
```
- **Parameters**:
  - `cam: Camera3D` — Viewport camera for movement direction
  - `terrain: Node` — Terrain node for height queries
- **Returns**: `void`
- **Description**: Initialize controller with camera and terrain references. Must be called before input handling.
- **Usage**: Called by main_controller during character setup.
- **Note**: Initializing twice with different terrain will change height-snapping behavior.

```gdscript
func handle_input_event(event: InputEvent, hovered_ui: bool) -> bool
```
- **Parameters**:
  - `event: InputEvent` — Input event (mouse, keyboard, etc.)
  - `hovered_ui: bool` — Whether a UI control is hovered (blocks input)
- **Returns**: `bool` — `true` if event was consumed
- **Description**: Route input to character. Returns `true` if this character handled the event, preventing other characters from processing it.
- **Input Handling**:
  - Right-click on character → select
  - Left-click (when selected) on terrain → move to position
  - Spacebar (when selected) → jump
  - WASD or arrow keys → manual movement
- **Usage**: Call from main input handling loop.

```gdscript
func is_selected() -> bool
```
- **Parameters**: None
- **Returns**: `bool` — Whether this character is currently active
- **Description**: Query selection state.

```gdscript
func deselect() -> void
```
- **Parameters**: None
- **Returns**: `void`
- **Description**: Deselect this character. Emits `selection_changed` signal with `selected=false`.
- **Usage**: Call when user switches to another character or clears selection.

---

## World Systems

### Terrain Runtime Editor

**File**: `scripts/services/terrain_runtime_editor.gd`  
**Type**: `extends RefCounted, class_name TerrainRuntimeEditor`  
**Description**: High-level terrain editor interface. Wraps WorldBrush for in-editor and runtime sculpting.

#### Public Functions

```gdscript
func initialize(terrain: Node) -> bool
```
- **Parameters**: `terrain: Node` — Terrain node (WorldBrush instance)
- **Returns**: `bool` — `true` if terrain has `apply_brush` method
- **Description**: Initialize the editor with a terrain reference.
- **Usage**: Call once at startup; returns `false` if terrain doesn't support the required API.

```gdscript
func is_available() -> bool
```
- **Parameters**: None
- **Returns**: `bool` — Whether terrain is initialized and available
- **Description**: Check if the editor is ready for sculpting.

```gdscript
func set_tool(
    tool_name: String,
    brush_size: float,
    brush_strength: float,
    flatten_height: float = 0.0,
    cliff_mode: bool = false,
    overhang_amount: float = 0.3
) -> void
```
- **Parameters**: (Same as `WorldBrush.apply_brush`)
- **Returns**: `void`
- **Description**: Configure the current brush tool and parameters.
- **Usage**: Call before `begin_stroke()` to set tool settings.

```gdscript
func bootstrap_new_map(seed: int = 1337) -> bool
```
- **Parameters**: `seed: int = 1337` — RNG seed for procedural terrain
- **Returns**: `bool` — Success status
- **Description**: Initialize a new procedurally-seeded terrain map.
- **Usage**: Call when creating a new map or resetting terrain.

```gdscript
func begin_stroke(world_position: Vector3) -> void
```
- **Parameters**: `world_position: Vector3` — Center of first brush stroke
- **Returns**: `void`
- **Description**: Begin a new sculpting stroke.
- **Usage**: Call on mouse down or LMB press.

```gdscript
func continue_stroke(world_position: Vector3, _camera_rotation_y: float) -> void
```
- **Parameters**:
  - `world_position: Vector3` — Current brush position
  - `_camera_rotation_y: float = 0.0` — [Unused] Camera Y rotation (reserved)
- **Returns**: `void`
- **Description**: Continue sculpting stroke at new position.
- **Usage**: Call on mouse motion while dragging.

```gdscript
func end_stroke() -> void
```
- **Parameters**: None
- **Returns**: `void`
- **Description**: Finalize current stroke (internal state cleanup).
- **Usage**: Call on mouse up or LMB release.

```gdscript
func dispose() -> void
```
- **Parameters**: None
- **Returns**: `void`
- **Description**: Clean up references and clear editor state.
- **Usage**: Call when editor is being shut down or terrain unloaded.

---

### Distant Horizon System

**File**: `scripts/world/distant_horizon_system.gd`  
**Type**: `extends Node3D, class_name DistantHorizonSystem`  
**Description**: Procedurally-generated distant mountains and landmarks at thousands of meters. Handles serialization for save/load.

#### Signals

```gdscript
signal landmarks_changed()
```
Emitted whenever a landmark is added or removed.

#### Constants

```gdscript
const DEFAULT_PLACE_DISTANCE: float = 3000.0  # Default distance for new mountains (meters)
const DEFAULT_RADIUS: float = 700.0            # Default base radius
const DEFAULT_HEIGHT: float = 450.0            # Default peak height
const DEFAULT_PEAK_COUNT: int = 3              # Number of peaks per range
```

#### Public Functions

```gdscript
func add_mountain(
    world_pos: Vector3,
    radius: float = DEFAULT_RADIUS,
    height: float = DEFAULT_HEIGHT,
    peak_count: int = DEFAULT_PEAK_COUNT,
    rng_seed: int = -1
) -> int
```
- **Parameters**:
  - `world_pos: Vector3` — Position in world space (Y is typically 0 for ground level)
  - `radius: float = 700.0` — Base radius of mountain range
  - `height: float = 450.0` — Peak height above ground
  - `peak_count: int = 3` — Number of individual peaks
  - `rng_seed: int = -1` — Random seed; if <0, auto-generates
- **Returns**: `int` — Unique mountain ID
- **Description**: Add a distant mountain landmark.
- **Emits**: `landmarks_changed` signal
- **Usage**: Call to place mountains at the horizon.
- **Example**:
```gdscript
var mountain_id = horizon_system.add_mountain(
    Vector3(3000, 0, 3000),
    radius=800.0,
    height=500.0,
    peak_count=5
)
```

```gdscript
func remove_landmark(id: int) -> bool
```
- **Parameters**: `id: int` — Landmark ID returned by `add_mountain()`
- **Returns**: `bool` — `true` if found and removed
- **Description**: Remove a specific landmark by ID.
- **Emits**: `landmarks_changed` if found

```gdscript
func clear_all() -> void
```
- **Parameters**: None
- **Returns**: `void`
- **Description**: Remove all landmarks.
- **Emits**: `landmarks_changed`

#### Serialization

```gdscript
func serialize() -> Array
```
- **Parameters**: None
- **Returns**: `Array` — Array of landmark dictionaries
- **Description**: Export all landmarks to serializable format.
- **Format**:
```gdscript
[
    {
        "id": int,
        "position": [x, y, z],
        "radius": float,
        "height": float,
        "peak_count": int,
        "seed": int
    },
    ...
]
```

```gdscript
func deserialize(items: Array) -> void
```
- **Parameters**: `items: Array` — Array of landmark dictionaries (from `serialize()`)
- **Returns**: `void`
- **Description**: Restore landmarks from saved data. Clears existing ones first.
- **Usage**: Call on map load to restore distant mountains.

#### Origin Shift Integration

```gdscript
func apply_origin_shift(offset: Vector3) -> void
```
- **Parameters**: `offset: Vector3` — Translation offset applied to world
- **Returns**: `void`
- **Description**: Update stored landmark positions after large-world recentering. Called automatically by `OriginShiftSystem`.
- **Note**: Do not call manually unless implementing custom large-world handling.

---

### Origin Shift System

**File**: `scripts/world/origin_shift_system.gd`  
**Type**: `extends Node, class_name OriginShiftSystem`  
**Description**: Prevents floating-point precision loss in large worlds by recentering all tracked nodes toward the origin when camera drifts too far.

#### Signals

```gdscript
signal world_shifted(offset: Vector3)
```
Emitted after recentering with the applied offset.

#### Exported Properties

```gdscript
@export var shift_threshold: float = 200.0  # Distance from origin that triggers recentering (meters)
```

#### Public Functions

```gdscript
func setup(
    camera: Camera3D,
    terrain_root: Node3D,
    stamp_root: Node3D,
    scatter_system: Node,
    wall_system_getter: Callable,
    horizon_system: Node3D
) -> void
```
- **Parameters**:
  - `camera: Camera3D` — Viewport camera
  - `terrain_root: Node3D` — Terrain node (translates entire tree)
  - `stamp_root: Node3D` — Stamped prefabs root
  - `scatter_system: Node` — Scatter system (if available)
  - `wall_system_getter: Callable` — Callable that returns wall system
  - `horizon_system: Node3D` — Distant horizon system
- **Returns**: `void`
- **Description**: Register all scene systems for tracking. Call once in `_ready()`.
- **Usage**: Called by main_controller during initialization.

```gdscript
func register_node(n: Node3D) -> void
```
- **Parameters**: `n: Node3D` — Node to track (e.g., character controller)
- **Returns**: `void`
- **Description**: Register an additional Node3D for world shifting.
- **Usage**: Call for dynamic objects (characters, temporary effects, etc.) that should follow recentering.

```gdscript
func unregister_node(n: Node3D) -> void
```
- **Parameters**: `n: Node3D` — Node to untrack
- **Returns**: `void`
- **Description**: Stop tracking a node (e.g., when it's destroyed).
- **Usage**: Call in `_exit_tree()` or when node is freed.

---

## Environment & Lighting System

### Time of Day Lighting

**File**: `scripts/environment/TimeOfDayLighting.gd`  
**Type**: `extends Node, class_name TimeOfDayLighting`  
**Description**: Dynamic lighting system synchronized with time of day. Updates sun energy, ambient light, and post-process based on weather and time.

#### Exported Node Paths

```gdscript
@export var sky_3d: NodePath                      # Path to Sky3D addon node
@export var directional_light: NodePath           # Path to DirectionalLight3D (sun)
@export var world_environment: NodePath           # Path to WorldEnvironment
@export var post_process_canvas: NodePath         # Path to PostProcessCanvas CanvasLayer
```

#### Exported Lighting Parameters

```gdscript
@export var afternoon_start_hour: float = 10.0
@export var afternoon_end_hour: float = 16.0
@export var day_start_hour: float = 7.0
@export var day_end_hour: float = 19.0

@export var afternoon_sun_energy_min: float = 1.8
@export var afternoon_sun_energy_max: float = 2.5
@export var night_moon_energy_min: float = 0.15
@export var night_moon_energy_max: float = 0.4

@export var ambient_energy_night: float = 0.35
@export var ambient_energy_day: float = 0.58
@export var ambient_day_color: Color = Color(1.0, 0.95, 0.85, 1.0)
@export var ambient_night_color: Color = Color(0.50, 0.56, 0.70, 1.0)
```

#### Public Functions

```gdscript
func set_lighting_override(
    enabled: bool,
    color: Color,
    energy: float,
    saturation: float,
    tint_strength: float
) -> void
```
- **Parameters**:
  - `enabled: bool` — Enable lighting override
  - `color: Color` — Override light color
  - `energy: float` — Override light energy (clamped 0–5)
  - `saturation: float` — Color saturation (-1 to 2)
  - `tint_strength: float` — Blend strength toward override (0–1)
- **Returns**: `void`
- **Description**: Override automatic time-based lighting with manual values.
- **Usage**: Call when user adjusts environment inspector settings.

```gdscript
func set_weather_runtime(
    global_intensity: float,
    stacking_enabled: bool,
    channels: Dictionary,
    current_weather: String
) -> void
```
- **Parameters**:
  - `global_intensity: float` — Overall weather effect intensity (0–3)
  - `stacking_enabled: bool` — Allow multiple weather effects simultaneously
  - `channels: Dictionary` — Per-weather intensities: `{"rain": 0–1, "snow": 0–1, "foggy": 0–1, "stormy": 0–1}`
  - `current_weather: String` — Active weather ("normal", "rain", "snow", "foggy", "stormy")
- **Returns**: `void`
- **Description**: Update weather state and intensity factors.
- **Usage**: Call when weather changes or weather UI is adjusted.

```gdscript
func update_lighting(time_of_day: float) -> void
```
- **Parameters**: `time_of_day: float` — Current time in hours (0–24)
- **Returns**: `void`
- **Description**: Update all lighting (sun, ambient, tonemap, SSAO) based on time and weather.
- **Usage**: Call every frame or when time changes (called automatically by main_controller).
- **Side Effects**: Modifies properties on:
  - DirectionalLight3D (energy, color)
  - WorldEnvironment ambient lighting and SSAO
  - Sky3D exposure and skydome energy
  - PostProcessCanvas daylight factor (if available)

---

## Signals

### Main Controller Signals

```gdscript
signal sky_state_changed(time_hours: float, weather_id: String)
```
- **Emitted When**: Time of day or weather changes
- **Parameters**:
  - `time_hours: float` — New time (0–24 hours)
  - `weather_id: String` — New weather ("normal", "rain", "snow", "foggy", "stormy")
- **Usage**: Listen to synchronize networked or external systems, UI updates, or event triggers.

### Character Controller Signals

```gdscript
signal selection_changed(character: CharacterController, selected: bool)
```
- **Emitted When**: Character is selected or deselected
- **Parameters**:
  - `character: CharacterController` — The character instance
  - `selected: bool` — `true` if selected, `false` if deselected

### Distant Horizon System Signals

```gdscript
signal landmarks_changed()
```
- **Emitted When**: A landmark is added, removed, or system is cleared
- **Parameters**: None

### Origin Shift System Signals

```gdscript
signal world_shifted(offset: Vector3)
```
- **Emitted When**: World recentering occurs
- **Parameters**:
  - `offset: Vector3` — Translation applied to all tracked nodes

---

## Constants

### Weather Identifiers

```gdscript
const WEATHER_NORMAL: String = "normal"
const WEATHER_RAIN: String = "rain"
const WEATHER_SNOW: String = "snow"
const WEATHER_FOGGY: String = "foggy"
const WEATHER_STORMY: String = "stormy"
```

### Time Constants (Hours)

```gdscript
const DAY_START_HOUR: float = 7.0
const DAY_END_HOUR: float = 19.0
const AFTERNOON_START_HOUR: float = 10.0
const AFTERNOON_END_HOUR: float = 16.0
const DEFAULT_SUNRISE_HOUR: float = 7.0
const DEFAULT_SUNSET_HOUR: float = 19.0
```

### Energy & Lighting

```gdscript
const DAY_SUN_ENERGY_MIN: float = 1.8
const DAY_SUN_ENERGY_MAX: float = 2.5
const NIGHT_MOON_ENERGY_MIN: float = 0.15
const NIGHT_MOON_ENERGY_MAX: float = 0.4
const AMBIENT_ENERGY_DAY_MAX: float = 0.58
const AMBIENT_ENERGY_NIGHT_MIN: float = 0.34
const AMBIENT_WARM_DAY: Color = Color(1.0, 0.9098, 0.7529, 1.0)
const AMBIENT_COOL_NIGHT: Color = Color(0.50, 0.56, 0.70, 1.0)
```

### World & Terrain

```gdscript
const HORIZON_MOUNTAIN_PLACE_DISTANCE: float = 3000.0
const PREFAB_VISIBILITY_END_NEAR: float = 170.0
const PREFAB_VISIBILITY_END_FAR: float = 260.0
```

---

## Usage Notes

### Common Workflows

#### 1. Creating a New Map Programmatically

```gdscript
# Access the main controller
var controller = get_node("/root/Main")

# Create a blank map
controller._create_new_flat_map()

# Access terrain and sculpt
var terrain = controller._terrain_node
terrain.apply_brush("raise", Vector3(0, 0, 0), 20.0, 0.5)

# Set environment
controller._apply_time_of_day(14.0)  # 2 PM
controller._apply_weather_preset("rain", true)
```

#### 2. Querying Terrain Height

```gdscript
var terrain = controller._terrain_node
var height = terrain.sample_height(100.0, 50.0)  # At world (100, ?, 50)
var pos_on_terrain = Vector3(100, height, 50)
```

#### 3. Monitoring Environment State

```gdscript
var controller = get_node("/root/Main")
controller.sky_state_changed.connect(func(time_hours, weather_id):
    print("Time: %.1f, Weather: %s" % [time_hours, weather_id])
)
```

#### 4. Adding Distant Landmarks

```gdscript
var horizon = controller._horizon_system
var mountain_id = horizon.add_mountain(
    Vector3(5000, 0, 5000),
    radius=900,
    height=600,
    peak_count=7
)
```

#### 5. Exporting & Loading Maps

```gdscript
# Export state
var sky_state = controller._export_sky_state()
var landmarks = controller._horizon_system.serialize()

# Save to file
var save_data = {
    "sky": sky_state,
    "landmarks": landmarks
}

# Load state
controller._import_sky_state(save_data["sky"])
controller._horizon_system.deserialize(save_data["landmarks"])
```

### Performance Considerations

- **Terrain Edits**: Use `set_full_rebuild_mode(false)` for performance; only set `true` when precision is critical.
- **Brush Preview**: Disable with `set_brush_preview_enabled(false)` in ultra-performance mode.
- **Character Count**: Limit to <50 active characters for smooth performance.
- **Large Worlds**: The OriginShiftSystem automatically recenters; configure `shift_threshold` based on gameplay needs.

### API Stability Notes

- **Private Members** (prefixed with `_`): Subject to change without notice. Use public API when possible.
- **Placeholder Parameters**: Some function parameters are reserved for future use (e.g., `_cliff_mode` in `apply_brush`). Pass default values or `null`.
- **Third-Party Addons**: PhantomCamera3D and Sky3D APIs are external; refer to their respective documentation.

---

## File Reference Map

| System | Main File | Key Classes |
|--------|-----------|------------|
| Game Controller | `scripts/main/main_controller.gd` | `MainController` (implicit) |
| Terrain | `addons/worldbrush/worldbrush.gd` | `WorldBrush` |
| Terrain Editor | `scripts/services/terrain_runtime_editor.gd` | `TerrainRuntimeEditor` |
| Characters | `scripts/characters/character_controller.gd` | `CharacterController` |
| Distant Landmarks | `scripts/world/distant_horizon_system.gd` | `DistantHorizonSystem` |
| Large-World Origin | `scripts/world/origin_shift_system.gd` | `OriginShiftSystem` |
| Lighting | `scripts/environment/TimeOfDayLighting.gd` | `TimeOfDayLighting` |

---

**End of Public API Reference**

For integration questions or to report missing APIs, contact the PaperVTT development team.
