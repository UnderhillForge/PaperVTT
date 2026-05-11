PaperVTT Design Guide
Version 0.1 — 3D Dungeon / World Builder + Future VTT
Core Philosophy

Speed and Flow First — You should be able to block out a beautiful map in minutes and refine it for hours.
Joyful to Use — Every tool should feel responsive and satisfying.
Stylized 3D — Target aesthetic: hand-drawn / graphic novel / pen-and-ink look (strong outlines + hatching via post-process).
GM-First — Built for world builders who want to create rich environments quickly, then run games in them.
Future-Proof — Start as a powerful 3D map editor, evolve into a full VTT.

1. Layout & UI (DungeonDraft Inspired)

Top Bar: Mac-style MenuBar
File | Map | Tools | GM Tools | View | Configuration | Help
Left Sidebar (Tools Panel) — Primary tools
Mode selection (Sculpt, Stamp, Paint, Path, etc.)
Brush settings (Radius, Strength, Falloff)
Tool-specific options

Center — Main 3D Viewport (the canvas)
Default angled top-down view (like DungeonDraft)
Easy toggle to free orbit camera

Right Sidebar — Asset Library
Search bar at top
Category tabs/chips (All, Walls, Floors, Furniture, Props, Nature, Characters, Dungeon…)
Icon grid with thumbnails (128–160px)
Right-click menu: Properties (Name, Scale, Category, Tags, Preview Rotation)

Bottom Bar (optional later) — Layers, status, coordinate display

2. Core Workflows
New Map

Starts mostly flat with very light noise (clean canvas)
Reasonable default size (512×512 units recommended)
Basic lighting + sky + post-process enabled
Small starter set of prefabs (optional)

Sculpting

Raise / Lower / Smooth / Flatten / Paint
Real-time brush preview circle on terrain
Hold + drag = continuous sculpting

Stamping (The Heart of the Tool)

Select asset in Library → Ghost preview follows mouse on terrain
LMB = Place
Hold LMB = Paint multiple (with spacing control)
RMB / Q / E = Rotate (±45°)
Grid Snap on by default (toggleable)
Scale can be adjusted per-asset in properties

Asset Browser

Visual icon grid (not just text list)
Search + category filtering
Right-click → Properties (Name, Scale X/Y/Z, Category, Tags)
Drag-and-drop support (future)

3. Visual & Styling Rules

Post-Process is the primary artistic style (pen outlines + hatching + paper tint)
Assets should have clean, relatively flat materials so post-process shines
Consistent unit scale: 1 Godot unit = 1 meter
Lighting should support dramatic, illustrative shadows

4. Scaling & Consistency

All prefabs should default to correct real-world scale
Right-click in Asset Browser allows per-asset scale override
System should warn or auto-correct wildly mis-scaled models

5. Future VTT Features (Phase 2)

Token system with character sheets
Dynamic lighting + LOS / Fog of War
Session / Multiplayer support
Import from DungeonDraft / WonderDraft / Foundry
Music & sound layers