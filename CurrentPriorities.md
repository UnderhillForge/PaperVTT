Areas That Need Attention
5/14/26

1. Wall System (Current Pain Point)

The recent move to a pre-baked modular GLTF system was the correct strategic decision. However, the implementation is still incomplete and unstable in practice.
Current Issues (Based on Recent Screenshots & Behavior):

Foundation misalignment / skewing — The foundation often becomes jagged, offset, or partially missing after adding windows or editing walls. The base Y values are not being consistently preserved across connected segments.
Window insertion problems — Adding a window frequently causes:
Large sections of wall to disappear without being properly replaced.
The real Tudor window prefab either not appearing or appearing incorrectly.
Secondary geometry artifacts (white boxes, floating pieces, etc.).

Rebuild fragility — rebuild_all() appears to be destroying or misplacing pieces (especially foundation and corner pieces) rather than cleanly swapping modular prefabs.
Edge case instability — Rectangles look good initially, but any modification (especially adding openings) destabilizes the structure.

Root Causes Likely Include:

Inconsistent handling of base Y coordinates during segment replacement.
Window prefabs not being properly parented to a persistent node (getting deleted on rebuild).
The modular piece selection/placement logic not fully accounting for junctions, headers, and foundation pieces.
Missing cleanup pass after structural changes.

Impact:
This is currently the biggest blocker to declaring Phase 1 complete. Until the Wall System is rock-solid, adding roofs, layers, or multiplayer will be risky.
Recommended Next Steps:

Stabilize foundation alignment (single shared base Y for all rectangle walls).
Ensure window insertion uses true modular replacement (wall_window_4m + separate window prefab) without side effects.
Add a post-rebuild validation pass that enforces consistent base heights and removes stray geometry.
Create a focused test scene (simple rectangle + various window/door placements) for regression testing.

This area needs a concentrated push — once it's reliable, the rest of the editor will feel much more solid.

2. This is the 2D pattern painting tool (like DungeonDraft) that lays down soft, scattered patterns (rocks, cobblestones, sand, grass patches, cliff textures, dirt paths, etc.) with nice blending.
Summary: What Needs to Be Built
Here’s the complete, prioritized list of what must be implemented to finish this feature properly:

- Texture Paint Tool
- Pattern System
- Brush Engine (radios, strength, density, soft edge fall off, random offsets + slight rotation per stroke, seemless blending)
- Terrain Painting Layer
- UI Panel
- Persistence
- Erase Mode

Recommended Technical Approach (Godot 4.7 + Terrain3D)

Use a secondary texture layer or decal projector system on the terrain for painting.
Patterns are stored as 512×512 PNGs with alpha.
Each brush stroke creates a small temporary mesh/decal with the pattern, then bakes it down efficiently.
Use your existing brush radius/strength system as the base.

3. Code Organization & Maturity

Some scripts are quite long (wall_tool.gd especially).
There's still a mix of runtime tools and editor-style logic.
Missing consistent documentation/comments in several key files.

4. Save/Load & Persistence

Basic foundation exists, but not battle-tested for complex maps (walls + scatter + terrain deltas).

5. Performance & Polish

Dense scenes (lots of scatter + grass + walls) will need optimization soon.
Camera transitions still need that "buttery" feel you want.