# Post Process Outlines

This folder contains the Godot-Post-Process-Outlines integration files used by PaperVTT.

- `pp_outlines_camera.gd`: custom `PPOutlinesCamera` type for editor/runtime profiles.
- `plugin.gd` / `plugin.cfg`: editor plugin registration.

Original addon inspiration:
- https://github.com/jocamar/Godot-Post-Process-Outlines

PaperVTT integrates outlines as a composable layer inside `shaders/pen_outline.gdshader`
so it can stack with contrast, saturation, vignette, bloom, and tint controls.
