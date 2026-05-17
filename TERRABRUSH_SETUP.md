# TerraBrush Editor Integration

## Overview
PaperVTT now launches with **TerraBrushTest.tscn** as the default scene, featuring:
- **TerraBrush Node**: The terrain system (GDExtension)
- **TerraBrushEditor Node**: Community-friendly terrain painting UI (replaces sidebar)
- **PostProcessCanvas**: Pen-and-ink shader for visual style
- **WorldEnvironment + DirectionalLight**: Lighting setup

## Current Status

### Scene Setup ✅
- Default launch scene: `res://scenes/terrain/TerraBrushTest.tscn`
- TerraBrushEditor configured with:
  - Default brush size: 50
  - Max brush size: 200
  - Default brush strength: 0.5
  - Built-in tool selectors enabled

### Missing: Terrain Initialization ⏳
The terrain mesh will not appear until you **initialize the terrain data**:

## Next Steps: Initialize Terrain

### Method 1: Editor UI (Recommended for one-time setup)
1. Launch Godot with PaperVTT
2. The scene should open automatically
3. In the editor viewport, select the **TerraBrush** node
4. Look for the TerraBrush inspector panel (usually at the bottom or docked right)
5. Find and click **"Create Terrain"** button
   - This will populate `terrain_data/test/` with heightmap PNGs
   - The terrain mesh will appear in the viewport
6. The TerraBrushEditor UI will now be live for painting

### Method 2: GDScript Runtime (In-game initialization)
If you want terrain to auto-initialize at game launch:
```gdscript
# Add this to TerraBrushTest.tscn as a script on the root node
extends Node3D

func _ready() -> void:
    var terrabrush = get_node("TerraBrush")
    if terrabrush:
        # This calls the internal onCreateTerrain() method
        # Note: May only work in editor; needs testing for runtime
        terrabrush.call_deferred("onCreateTerrain")
```

## TerraBrushEditor Controls
Once terrain is created, the editor UI provides:
- **Sculpting Tools**: Add/Remove/Smooth/Flatten terrain
- **Texture Painting**: Paint with Grass, Stone Ground, Cliff Rock
- **Foliage/Objects**: Add vegetation and props (if configured)
- **Undo/Redo**: Full undo stack for terrain modifications

## Community Integration
- Players can now paint terrain directly in-game
- No external tools required
- Data saved to `terrain_data/test/` directory
- All changes are reversible via undo

## Pen-and-Ink Shader
The PostProcessCanvas node automatically applies `pen_outline.gdshader` for visual polish:
- Sobel edge detection
- Hatching effect
- Can be toggled in-scene if needed

## File Locations
- Scene: `res://scenes/terrain/TerraBrushTest.tscn`
- Terrain data: `res://terrain_data/test/`
- Shader: `res://shaders/pen_outline.gdshader`
- Config: `project.godot` (run/main_scene)

## Troubleshooting

### Terrain doesn't appear after "Create Terrain"
- Check `terrain_data/test/` directory has .png files
- Verify TerraBrush node has dataPath set to `res://terrain_data/test`
- Check editor console for errors

### TerraBrushEditor UI doesn't show
- Verify `enableOnReady = true` in TerraBrushTest.tscn
- Check that TerraBrush node reference is valid
- May only work in non-headless mode

### Brush painting not working
- Verify camera is positioned over terrain
- Check mouse is over viewport when painting
- Verify TerraBrush mesh is visible
