# Asset Scale and Texel Density Standard

PaperVTT baseline:
- Target texel density: 256 px/m
- Terrain UV baseline: 8.0 for the current 2K terrain reference set
- Recommended chunk size: 64 x 64 meters
- Recommended texture resolution: 1024 x 1024 for most assets

Authoring and import rules:
- Build models at real scale: 1 Godot unit = 1 meter
- Author or resize new textures to align with 256 px/m
- Prefer 1024 x 1024 for most new textures; use 2048 x 2048 only when the asset needs extra detail
- Keep material tiling consistent with the 256 px/m baseline before doing per-asset overrides

Quick checks before committing new asset packs:
- Terrain/base materials still read clearly at default UV scale 4.0
- Texture paint tile size is set near 4.0 for baseline coverage
- Chunked terrain remains at 64m chunk size unless there is a specific profiling reason to change it
