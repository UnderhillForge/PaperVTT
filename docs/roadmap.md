PaperVTT Feature Roadmap

### Vision
A unified 3D world with seamless perspective switching: DungeonDraft-style top-down 2D editing when you want speed and clarity, and full 3D orbit / character follow when you want immersion and verticality — all in the **same scene**, with no duplicated data.

---

### Phase 1 – Foundation (Next 2–4 Weeks)
**Goal**: A polished, joyful map editor that already feels better than most existing tools.

- Mac-style top menu + left tools panel + right visual asset browser
- Phantom Camera system with two modes:
  - **TopDown2DView** (orthographic, locked top-down, DungeonDraft-like feel)
  - **Free3DView** (orbit + third-person character follow)
- Smooth Tab (or button) switching between 2D and 3D views with nice transitions
- Reliable terrain system (Terrain3D or custom heightmap) with sculpting brushes
- **Smart Wall Tool** – drag to draw, automatic corners, T-junctions, doors, end caps using modular prefabs
- Drag-and-drop stamping with real-time ghost preview + grid snapping
- Character controller (camera-relative movement, point-and-click, third-person follow)
- Ground shadow / selection indicator under tokens
- Strong pen-and-ink post-process as core visual identity
- Performance Mode + optimization
- Save / Load maps (.pvtt format)

**Success Metric**: A GM can create a good-looking dungeon in TopDown2DView in under 10 minutes, hit Tab, and immediately have a beautiful 3D version ready for play.

---

### Phase 2 – Creative Power (Next 1–2 Months)
**Goal**: Make map building fast, addictive, and deeply customizable.

- Full bidirectional editing — changes in 2D view instantly appear in 3D and vice versa
- Layer system (terrain, walls, objects, effects, tokens, lighting)
- Advanced stamping tools (scatter brush, path tool, paint objects)
- Smart object tools (auto-align to walls, stack on tables, etc.)
- Lighting & atmosphere tools (with real-time preview in both modes)
- Asset properties panel (scale, tint, rotation, height offset, tags)
- Robust undo/redo + action history
- 2D Reference Layer (import DungeonDraft maps as a toggleable guide)
- Basic export (images, Universal VTT, glTF, Foundry-ready)

---

### Phase 3 – Full VTT Experience (2–4 Months)
**Goal**: One tool for both creation and play.

- Token system with integrated character sheets
- Dynamic lighting + Line of Sight / Fog of War (works in both 2D and 3D views)
- Player View vs GM View toggle
- Initiative tracker, dice rolling, chat, emotes
- Session hosting / basic multiplayer
- Music, ambient sound, and sound effect layers
- Import from DungeonDraft, Foundry, Roll20, etc.

---

### Phase 4 – Killer Differentiators (Ongoing)

- AI-assisted 2D → 3D conversion & enhancement
- Procedural room / building generation (still in pen-and-ink style)
- Strong modding system + community asset & style ecosystem
- Multiple art style packs (different ink styles, watercolor, cel-shaded, etc.)
- Narrative tools (story timelines, relationship maps, quest tracking)
- Advanced VTT features (dynamic weather, day/night cycles, scripted events)

---

**Current Focus (as of now)**:  
Finish Phase 1 with strong emphasis on the **TopDown2DView + Smart Wall Tool** and buttery-smooth camera switching.
