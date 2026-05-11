# PaperVTT Asset Library

This directory is organized for fast Asset Browser use and pen-and-ink friendly rendering.

## Folder Layout

- `models/`
  - `walls/`
  - `floors/`
  - `furniture/`
  - `props/`
  - `nature/`
  - `characters/`
  - `dungeon/`
- `prefabs/`
  - `walls/`
  - `floors/`
  - `furniture/`
  - `props/`
  - `nature/`
  - `characters/`
- `materials/` shared `StandardMaterial3D` resources
- `textures/materials/` base texture maps
- `textures/foliage/` leaf/needle/grass alpha textures

## Completed In This Pass (Priority 1)

- Walls and floors were reorganized so floor-like corner/path assets no longer live under `models/walls/`.
- Walls and floors now have standardized prefab coverage in `prefabs/walls/` and `prefabs/floors/`.
- Added curated core prefabs for dungeon building:
  - `prefabs/walls/core/` (straight, corner, doorway, arch, T-split)
  - `prefabs/floors/core/` (stone tile, wood planks, dirt patch, stone paths)

## Completed In This Pass (Priority 2)

- Furniture and props are now organized with standardized prefab coverage:
  - `prefabs/furniture/`
  - `prefabs/props/`
- Added category matte presets:
  - `materials/furniture_matte.tres`
  - `materials/prop_matte.tres`
- Reclassified stool from props tools to furniture chairs:
  - `models/furniture/chairs/stool_wood.gltf`
- Added curated human-readable core prefabs:
  - `prefabs/furniture/core/` (bed, chair, stool, tables, shelf)
  - `prefabs/props/core/` (barrels, crate stack, torch, candles, rubble)

## Completed In This Pass (Priority 3)

- Nature category now has standardized prefab coverage under `prefabs/nature/`.
- Added curated core nature prefabs under `prefabs/nature/core/`:
  - trees (`tree_oak_a`, `tree_pine_tall_a`)
  - bushes (`bush_large_a`, `bush_small_a`)
  - rocks (`rock_large_a`, `rock_small_a`)
  - logs and plants (`log_large_a`, `mushroom_red_group_a`)
- Reclassified pine ground tree assets from floors to nature trees:
  - `models/nature/trees/tree_pine_ground_a.glb`
  - `models/nature/trees/tree_pine_ground_b.glb`

## Completed In This Pass (Priority 4)

- Character category now has standardized prefab coverage under `prefabs/characters/`.
- Generated wrappers for adventurers and skeletons (excluding rig helper assets).
- Added curated core character prefabs under `prefabs/characters/core/`:
  - adventurers (`adventurer_barbarian_a`, `adventurer_knight_a`, `adventurer_mage_a`, `adventurer_ranger_a`, `adventurer_rogue_a`)
  - skeletons (`skeleton_warrior_a`, `skeleton_mage_a`, `skeleton_rogue_a`, `skeleton_minion_a`)

## Material Standard

Shared matte presets live in `assets/materials/`:

- `wall_matte.tres`
- `floor_matte.tres`
- existing category presets (`base_matte.tres`, `nature_matte.tres`, `character_matte.tres`)

Target look:

- roughness around `0.9`
- metallic `0.0`
- no strong emission/rim unless required

## Prefab Standard

- One wrapper `.tscn` per major model
- Includes `StaticBody3D` + `CollisionShape3D`
- Uses shared matte material via `scripts/assets/prefab_surface_style.gd` to keep shading consistent for post-process outlines
