Two-Tier Layer Architecture for PaperVTT
1. World Layers (Geometry & Visual)
These contain everything you can see and build:

Layer 0 — Ground / Foundation
Layer 1 — Main floor (current walls)
Layer 2+ — Upper floors, balconies, mezzanines
Negative layers — Basements, dungeons, sewers, caverns
Special layers: Roof layer, Ceiling layer

Per World Layer features:

Independent WallSystem, RoofSystem, terrain patch
Vertical offset (height above base)
Visibility + ghost mode
Material/theme override
Painted textures + scatter

2. Systems Layers (Functional / Invisible)
These handle gameplay, atmosphere, and data:

Lighting Layer
Sound Layer (ambient emitters, music, reverb zones)
Effects Layer (particles, spell effects, fog volumes)
Encounters Layer (monsters, traps, NPCs, treasure, scripted events)
FoW / Vision Layer (for VTT play mode)
GM Notes Layer (hidden notes, arrows, region labels)
Automation Layer (solo quest zones, AI behaviors)

Per Systems Layer features:

Can be toggled independently
Can be tied to specific World Layers
Non-destructive (doesn’t affect geometry)

World Layers
├─ -1  Cavern Level
├─  0  Ground Floor          ← Active
├─  1  Main Floor
└─  2  Upper Floor           [ghost]

Systems Layers
├─ Lighting
├─ Sound
├─ Encounters
├─ Effects
└─ GM Notes