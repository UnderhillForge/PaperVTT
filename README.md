# PaperVTT

PaperVTT is a stylized 3D map editor for tabletop worldbuilding, with a long-term direction toward a full virtual tabletop workflow.

Built in Godot, it focuses on fast terrain shaping, prefab stamping, smart wall authoring, and paint-style biome dressing (grass + scatter) with a pen-and-ink inspired look.

## Highlights

- Terrain editing: raise, lower, smooth, flatten, and paint.
- Prefab stamping: place assets quickly with grid snapping and rotation shortcuts.
- Smart wall tool: chain walls, rectangle mode, wall types, opening controls, and foundations.
- Grass painter: density and wind-aware painted vegetation zones.
- Scatter brush (spray style): paint and erase instanced props with density, scale, rotation randomness, and tilt.
- Character scene support and camera handoff for editor + in-world navigation workflows.
- Map save/load flow from the main menu.
- DungeonDraft import pipeline for floor tiles, walls, objects, and lights.

## Tech Stack

- Engine: Godot 4.7 feature profile
- Language: GDScript
- Key addons:
  - `addons/terrain_3d`
  - `addons/phantom_camera`

## Project Layout

- `scenes/main/Main.tscn`: main editor scene
- `scripts/main/main_controller.gd`: runtime orchestration and tool routing
- `scenes/ui/`: editor UI scenes (toolbar, asset browser, post process canvas)
- `scripts/ui/`: toolbars, menu bar, asset browser behavior
- `scripts/terrain/`: terrain and grass systems
- `scripts/scatter/`: scatter asset and scatter runtime system
- `scripts/tools/`: smart wall tooling
- `scripts/import/`: DungeonDraft importer
- `assets/`: models, prefabs, materials, textures, and previews

## Getting Started

### 1. Clone

```bash
git clone <your-repo-url>
cd PaperVTT
```

### 2. Open in Godot

- Open Godot 4.x.
- Import/open `project.godot`.
- Run the project (main scene is `scenes/main/Main.tscn`).

### 3. Basic Workflow

- Pick a tool from the left toolbar.
- Select an asset from the right asset browser for stamp/scatter tools.
- Edit terrain and place prefabs in the center viewport.
- Save maps from the top menu (`File -> Save` / `Save As`).

## Controls (Default)

- `1` Raise
- `2` Lower
- `3` Smooth
- `4` Flatten
- `5` Paint
- `6` Stamp
- `7` Grass Paint
- `8` Grass Erase
- `9` Smart Wall
- `0` Scatter Paint
- `Esc` Return to Select / clear active tool state
- Stamp mode:
  - `LMB` place
  - `RMB` or `Q` / `E` rotate by 45 degrees

## Asset Library Notes

The asset library is organized for fast browsing and stylized rendering.

See `assets/README.md` for category structure, prefab standards, and material conventions.

## Importing DungeonDraft Maps

The importer normalizes map JSON into floor tiles, wall segments, objects, and lights.

- Importer script: `scripts/import/dungeondraft_importer.gd`
- Example test files: `dd_testing/`

## Current Scope

PaperVTT currently prioritizes world-building and map-authoring speed. Planned future work includes deeper VTT systems such as token gameplay, lighting/LOS, and session tooling.

## Development Notes

If you use repository mirrors on external volumes (for example local bare remotes), avoid committing filesystem metadata files such as `._*` AppleDouble sidecars into Git storage.

## License

Project license is currently not declared in a root license file.
Add one before public distribution.
