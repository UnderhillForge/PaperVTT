# PaperVTT Lua API Reference

**Version**: 1.0  
**Last Updated**: May 17, 2026  
**Scope**: Public API for Lua scripting and external tool integration  
**Language Binding**: GDScript→Lua via LuaScript addon

---

## Table of Contents

1. [Overview](#overview)
2. [Core Systems](#core-systems)
3. [Terrain API](#terrain-api)
4. [World API](#world-api)
5. [Character API](#character-api)
6. [Environment API](#environment-api)
7. [Constants](#constants)
8. [Signals & Events](#signals--events)
9. [Common Workflows](#common-workflows)

---

## Overview

PaperVTT exposes a comprehensive scripting API through the main controller and specialized subsystems. This document covers all functions available for Lua scripts integrated via the LuaScript addon.

### Access Pattern

All APIs are accessed through the main controller singleton:

```lua
-- Get reference to main controller (injected as global)
local controller = MainController  -- or access via get_node("/root/MainController")
```

### Type Conventions

- `int`: Integer (32-bit)
- `float`: Floating-point number
- `bool`: Boolean true/false
- `string`: UTF-8 string
- `Vector2`: 2D vector `{x, y}`
- `Vector3`: 3D vector `{x, y, z}`
- `Color`: RGBA color `{r, g, b, a}` (0.0-1.0 range)

---

## Core Systems

### 1. World Layer Management

#### `set_active_world_layer(layer: int) -> void`

Switch the active editing layer for terrain and decoration systems.

```lua
controller:set_active_world_layer(0)  -- Switch to layer 0
```

- **Parameters**:
  - `layer` (int): Layer index, 0-based. Typically 0-3 for multi-layer editing.
- **Returns**: Nothing
- **Notes**: All subsequent terrain edits affect this layer only.
- **Side Effects**: 
  - Terrain visualization updates
  - UI panels refresh to show layer-specific settings

#### `get_active_world_layer() -> int`

Query the currently active world layer.

```lua
local current_layer = controller:get_active_world_layer()
print("Active layer: " .. current_layer)
```

- **Returns**: Current layer index (int)

---

## Terrain API

**Primary File**: `addons/worldbrush/worldbrush.gd`

Terrain manipulation is performed through the `TerrainRuntimeEditor` subsystem. Access via:

```lua
local terrain = controller:_get_worldbrush_node()  -- Get terrain node
```

### Brush Tools

#### `apply_brush(tool_name: String, world_pos: Vector3, brush_size: float, brush_strength: float, flatten_height: float = 0.0) -> void`

Apply a sculpting brush at the specified world position.

```lua
local world_pos = Vector3.new(10.0, 5.0, 20.0)
terrain:apply_brush("raise", world_pos, 15.0, 0.7)
```

- **Parameters**:
  - `tool_name` (string): One of: `"raise"`, `"lower"`, `"smooth"`, `"flatten"`, `"texturepaint"`, `"waterpaint"`, `"watererase"`, `"snowpaint"`, `"snowerase"`
  - `world_pos` (Vector3): World-space coordinates where brush is applied
  - `brush_size` (float): Brush radius in world units (1.0-50.0 typical)
  - `brush_strength` (float): Intensity multiplier (0.0-1.0 typical)
  - `flatten_height` (float, optional): Target height for `"flatten"` tool. Default: 0.0

- **Returns**: Nothing
- **Side Effects**: 
  - Modifies height/paint/water/snow layers
  - Triggers mesh update (dirty rect or full rebuild)
  - Emits console diagnostics

#### `apply_procedural_snow(min_height: float, max_height: float, intensity: float) -> void`

Apply procedural snow coverage based on height ranges.

```lua
terrain:apply_procedural_snow(2.8, 10.0, 0.6)
```

- **Parameters**:
  - `min_height` (float): Minimum height threshold for snow
  - `max_height` (float): Maximum height threshold
  - `intensity` (float): Snow coverage intensity (0.0-1.0)

- **Returns**: Nothing
- **Notes**: Automatically recalculates terrain colors and mesh

### Height Queries

#### `sample_height(world_x: float, world_z: float) -> float`

Query terrain height at a specific world position.

```lua
local height = terrain:sample_height(10.0, 20.0)
print("Terrain height at (10, 20): " .. height)
```

- **Parameters**:
  - `world_x` (float): World X coordinate
  - `world_z` (float): World Z coordinate

- **Returns**: Height value (float) at the queried position
- **Notes**: 
  - Uses bilinear interpolation for smooth queries
  - Much faster than raycasts for simple height checks
  - Returns world Y value

#### `get_intersection(origin: Vector3, direction: Vector3, with_water: bool = true) -> Vector3 or nil`

Raycast against terrain and optionally water surface.

```lua
local origin = Vector3.new(0, 50, 0)
local direction = Vector3.DOWN  -- Or manually {x=0, y=-1, z=0}
local hit = terrain:get_intersection(origin, direction, false)

if hit then
    print("Hit terrain at: " .. hit.x .. ", " .. hit.y .. ", " .. hit.z)
else
    print("No intersection")
end
```

- **Parameters**:
  - `origin` (Vector3): Ray origin in world space
  - `direction` (Vector3): Ray direction (normalized recommended)
  - `with_water` (bool, optional): Include water surface in raycast. Default: true

- **Returns**: Vector3 hit position, or `nil` if no intersection
- **Notes**: 
  - Used for brush preview and UI interaction
  - Direction doesn't need normalization but results are more predictable if normalized

### Terrain Configuration

#### `set_brush_preview_enabled(enabled: bool) -> void`

Toggle brush preview ring visualization.

```lua
terrain:set_brush_preview_enabled(true)
```

#### `set_brush_preview_radius(radius: float) -> void`

Set the brush preview ring size.

```lua
terrain:set_brush_preview_radius(25.0)
```

### Rebuild Control

#### `set_full_rebuild_mode(enabled: bool) -> void`

Force terrain to fully rebuild mesh after each stroke (disable dirty rect optimization).

```lua
terrain:set_full_rebuild_mode(true)  -- Full rebuild (slower, stable)
terrain:set_full_rebuild_mode(false) -- Dirty rect optimization (faster)
```

- **Parameters**:
  - `enabled` (bool): True = full mesh rebuild, False = dirty rect partial update

- **Returns**: Nothing
- **Notes**: 
  - Full rebuild: ~15-16 ms per stroke
  - Dirty rect: 0.2-0.6 ms per stroke (30-100x faster)
  - Default: true (for stability)

#### `get_full_rebuild_mode() -> bool`

Query current rebuild mode.

---

## World API

### Distant Horizons (Landmark System)

**Primary File**: `scripts/environment/distant_horizon_manager.gd`

#### `add_landmark(landmark_data: Dictionary) -> int`

Add a distant landmark to the horizon system.

```lua
local landmark = {
    position = Vector3.new(500, 50, 1000),
    scale = Vector3.new(2.0, 2.0, 2.0),
    color = Color.new(0.5, 0.5, 0.5, 1.0),
    name = "Mountain Peak"
}

local landmark_id = horizon_manager:add_landmark(landmark)
print("Landmark created with ID: " .. landmark_id)
```

- **Parameters**:
  - `landmark_data` (Dictionary): 
    - `position` (Vector3): World position
    - `scale` (Vector3): Model scale
    - `color` (Color, optional): Tint color
    - `name` (string, optional): Display name

- **Returns**: Landmark ID (int) for future reference

#### `remove_landmark(landmark_id: int) -> void`

Remove a landmark by ID.

```lua
horizon_manager:remove_landmark(landmark_id)
```

### Large-World Origin Shifting

**Primary File**: `scripts/world/large_world_handler.gd`

#### `shift_world_origin(delta: Vector3) -> void`

Recenter the world to prevent floating-point precision loss.

```lua
-- Every 50km of travel, recenter the world
if distance_traveled > 50000 then
    local shift = Vector3.new(25000, 0, 25000)
    world_handler:shift_world_origin(shift)
end
```

- **Parameters**:
  - `delta` (Vector3): World-space translation to apply

- **Returns**: Nothing
- **Notes**: 
  - All objects maintain relative positions
  - Essential for large open-world maps
  - Emits `world_shifted` signal

---

## Character API

**Primary File**: `scripts/characters/character_manager.gd`

#### `set_active_character(character_id: int) -> void`

Select/activate a character for control.

```lua
char_manager:set_active_character(1)
```

#### `get_active_character_id() -> int`

Query the currently active character.

```lua
local active_id = char_manager:get_active_character_id()
```

#### `spawn_character(prefab_path: String, world_pos: Vector3) -> int`

Spawn a new character instance at a world position.

```lua
local char_id = char_manager:spawn_character("res://prefabs/hero.tscn", Vector3.new(0, 5, 0))
```

- **Parameters**:
  - `prefab_path` (string): Path to character scene file (usually under `assets/prefabs/`)
  - `world_pos` (Vector3): Spawn position

- **Returns**: Character ID (int) for future reference

#### `remove_character(character_id: int) -> void`

Despawn a character.

```lua
char_manager:remove_character(char_id)
```

### Character Signals

```lua
char_manager.selection_changed:connect(function(char_id)
    print("Character selected: " .. char_id)
end)
```

---

## Environment API

### Time & Lighting

**Primary File**: `scripts/main/main_controller.gd`

#### `_apply_time_of_day(hours: float) -> void`

Set time of day (0.0-23.999).

```lua
controller:_apply_time_of_day(14.5)  -- 2:30 PM
```

- **Parameters**:
  - `hours` (float): Hour of day (0.0=midnight, 12.0=noon, 23.999=11:59:59 PM)

- **Returns**: Nothing
- **Side Effects**: 
  - Updates sun light angle
  - Recalculates ambient lighting
  - Triggers sky shader updates

#### `_apply_day_length(minutes: float) -> void`

Set in-game day length duration.

```lua
controller:_apply_day_length(15.0)  -- 15 real minutes = 1 in-game day
```

- **Parameters**:
  - `minutes` (float): Real-world minutes for full 24-hour cycle

- **Returns**: Nothing

#### `_apply_weather_preset(weather_id: String, force: bool = false) -> void`

Activate a weather preset.

```lua
controller:_apply_weather_preset("rain", true)
```

- **Parameters**:
  - `weather_id` (string): One of `"normal"`, `"rain"`, `"snow"`, `"foggy"`, `"stormy"`
  - `force` (bool, optional): Force immediate transition. Default: false

- **Returns**: Nothing
- **Side Effects**: 
  - Updates particle effects
  - Adjusts ambient sound
  - Modifies fog and visibility

### Environment State Query

```lua
-- Example: Get current environment state
local state = {
    time_hours = controller._sky_time_hours,
    weather = controller._sky_weather,
    intensity = controller._weather_intensity_global
}
```

### Signals

```lua
controller.sky_state_changed:connect(function(hours, weather)
    print("Time: " .. hours .. " Weather: " .. weather)
end)
```

---

## Constants

### Weather Types

```lua
local WEATHER = {
    NORMAL = "normal",
    RAIN = "rain",
    SNOW = "snow",
    FOGGY = "foggy",
    STORMY = "stormy"
}
```

### Time Constants

```lua
local TIME = {
    DAY_START = 7.0,
    DAY_END = 19.0,
    AFTERNOON_START = 10.0,
    AFTERNOON_END = 16.0,
    DEFAULT_DAY_LENGTH = 15.0  -- minutes per cycle
}
```

### Terrain Constants

```lua
local TERRAIN = {
    DEFAULT_SIZE = 256.0,
    DEFAULT_RESOLUTION = 96,
    MAX_HEIGHT = 38.0,
    MIN_HEIGHT = -14.0,
    BRUSH_TOOLS = {
        "raise", "lower", "smooth", "flatten",
    "texturepaint",
        "waterpaint", "watererase",
        "snowpaint", "snowerase"
    }
}
```

### Performance Constants

```lua
local PERF = {
    PREFAB_VISIBILITY_END_NEAR = 170.0,
    PREFAB_VISIBILITY_END_FAR = 260.0,
    HORIZON_MOUNTAIN_PLACE_DISTANCE = 3000.0,
    DIRTY_RECT_BORDER = 4,  -- vertices
    DIRTY_REBUILD_TIME_MS = 0.5,
    FULL_REBUILD_TIME_MS = 15.0
}
```

---

## Signals & Events

### Main Controller Signals

#### `sky_state_changed(hours: float, weather: String)`

Emitted when time or weather changes.

```lua
controller.sky_state_changed:connect(function(hours, weather)
    print("New time: " .. hours .. " Weather: " .. weather)
    -- Update UI, sync networked state, trigger events, etc.
end)
```

#### `selection_changed(character_id: int)`

Emitted when active character changes.

```lua
char_manager.selection_changed:connect(function(char_id)
    print("Selected character: " .. char_id)
end)
```

#### `landmarks_changed()`

Emitted when distant horizons are modified.

```lua
horizon_manager.landmarks_changed:connect(function()
    print("Landmarks updated")
end)
```

#### `world_shifted(delta: Vector3)`

Emitted when large-world origin shifts.

```lua
world_handler.world_shifted:connect(function(delta)
    print("World shifted by: " .. delta.x .. ", " .. delta.y .. ", " .. delta.z)
end)
```

---

## Common Workflows

### Workflow 1: Create a Raised Mountain

```lua
-- Get terrain node
local terrain = controller:_get_worldbrush_node()

-- Paint a mountain shape
local mountain_center = Vector3.new(0, 0, 0)
local brush_size = 30.0
local strength = 0.8

-- Apply multiple overlapping strokes for smooth mountain
for i = 1, 5 do
    local offset_x = math.cos(i * 72 * math.pi / 180) * 20
    local offset_z = math.sin(i * 72 * math.pi / 180) * 20
    local pos = mountain_center + Vector3.new(offset_x, 0, offset_z)
    terrain:apply_brush("raise", pos, brush_size, strength)
end

print("Mountain created")
```

### Workflow 2: Query Terrain Height Grid

```lua
-- Sample terrain at regular intervals
local grid_size = 50.0
local spacing = 10.0

for x = -grid_size / 2, grid_size / 2, spacing do
    for z = -grid_size / 2, grid_size / 2, spacing do
        local height = terrain:sample_height(x, z)
        print(string.format("Height at (%.1f, %.1f): %.2f", x, z, height))
    end
end
```

### Workflow 3: Monitor Environment State

```lua
-- Set up continuous environment monitoring
controller.sky_state_changed:connect(function(hours, weather)
    if hours >= 20.0 or hours < 6.0 then
        print("Night time - enable lights")
    else
        print("Daytime - disable lights")
    end
    
    if weather == "rain" or weather == "stormy" then
        print("Wet conditions - adjust physics")
    end
end)

-- Set day to cycle every 10 real minutes
controller:_apply_day_length(10.0)
```

### Workflow 4: Place Landmarks Along Horizon

```lua
-- Add mountain peaks at various distances
local landmark_positions = {
    {x = 1000, y = 200, z = 500},
    {x = -1200, y = 180, z = 800},
    {x = 1500, y = 220, z = -600}
}

local horizon_mgr = controller:_get_horizon_manager()

for i, pos in ipairs(landmark_positions) do
    local lm = {
        position = Vector3.new(pos.x, pos.y, pos.z),
        scale = Vector3.new(1.5, 1.5, 1.5),
        color = Color.new(0.6, 0.6, 0.7, 1.0),
        name = "Peak " .. i
    }
    
    local id = horizon_mgr:add_landmark(lm)
    print("Added landmark " .. id)
end
```

### Workflow 5: Spawn and Control Characters

```lua
-- Spawn a hero character
local char_mgr = controller:_get_character_manager()
local hero_id = char_mgr:spawn_character(
    "res://assets/prefabs/hero.tscn",
    Vector3.new(0, 5, 0)
)

-- Select and control it
char_mgr:set_active_character(hero_id)

-- Monitor selection changes
char_mgr.selection_changed:connect(function(id)
    print("Active character: " .. id)
end)
```

---

## Best Practices

### Performance

- **Use `sample_height()` for simple queries**: Bilinear interpolation is very fast
- **Use `get_intersection()` for raycasts**: Only when direction precision matters
- **Batch terrain edits**: Group multiple `apply_brush()` calls to reduce mesh updates
- **Monitor dirty rect mode**: Enable for performance-critical scripts (0.2-0.6ms vs 15ms)

### Lua Scripting

- Always check for `nil` returns before using results
- Connect signals at script initialization, not every frame
- Use local variables to cache frequently accessed values
- Avoid deep nesting of cross-module calls; prefer direct references

### Terrain Editing

- Always verify active layer before applying edits
- Use `"smooth"` tool after major sculpting for visual polish
- Test procedural snow generation with varied min/max heights
- Rebuild full mesh if dirty rect artifacts appear (use debug visualization)

---

## File Reference Map

| System | Primary File | Secondary Files |
|--------|------|-----------------|
| Main Control | `scripts/main/main_controller.gd` | `scripts/main/game_state.gd` |
| Terrain | `addons/worldbrush/worldbrush.gd` | `scripts/terrain/terrain_runtime_editor.gd` |
| Characters | `scripts/characters/character_manager.gd` | `scripts/characters/character_base.gd` |
| Environment | `scripts/environment/time_weather_manager.gd` | `scripts/environment/distant_horizon_manager.gd` |
| World | `scripts/world/large_world_handler.gd` | `scripts/world/world_state.gd` |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-05-17 | Initial API reference for Lua integration |

---

## Support & Contributing

For questions, issues, or API additions:
1. Check `PUBLIC_API_REFERENCE.md` for detailed GDScript signatures
2. Review example scripts in `scripts/examples/` (if present)
3. Consult individual system documentation files
4. Report bugs or API improvements to the PaperVTT development team

---

**License**: Same as PaperVTT project  
**Status**: Active Development
