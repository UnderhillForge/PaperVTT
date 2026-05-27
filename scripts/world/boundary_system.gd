## BoundarySystem — runtime node that manages Boundary drawing, preview, selection,
## and terrain cliff extrusion.  Add as a child of the main scene; wire via MainController.
##
## Usage:
##   activate(terrain_node, camera, world_layer)  — enter drawing mode
##   deactivate()                                  — exit / cancel all state
##   handle_input(event, mouse_pos)                — call from _input or _unhandled_input
##   apply_selected()                              — trigger extrusion for selected boundary
##   serialize() / deserialize(arr)                — save / load with map

class_name BoundarySystem
extends Node3D

# ---------- signals -------------------------------------------------------
signal boundary_selected(boundary: BoundaryData)
signal boundary_deselected()
signal drawing_started()
signal drawing_finished(boundary: BoundaryData)

# ---------- constants ------------------------------------------------------
const PREVIEW_POINT_RADIUS: float    = 0.20
const PREVIEW_LINE_THICKNESS: float  = 0.05  # half-width for line quads
const CLOSED_LINE_COLOR: Color       = Color(0.20, 0.78, 0.64, 0.78)
const PREVIEW_LINE_COLOR: Color      = Color(0.62, 0.86, 0.93, 0.46)
const GHOST_LINE_COLOR: Color        = Color(0.74, 0.84, 0.90, 0.28)
const SELECTED_LINE_COLOR: Color     = Color(0.96, 0.83, 0.33, 0.88)
const HANDLE_COLOR: Color            = Color(0.18, 0.92, 0.68, 0.9)
const SELECTED_HANDLE_COLOR: Color   = Color(1.00, 0.85, 0.22, 0.95)
const HANDLE_HOVER_COLOR: Color      = Color(1.00, 1.00, 1.00, 1.0)
const LINE_LIFT: float               = 0.22   # raise above terrain so lines are visible
const EXTRUDE_BRUSH_STEPS_PER_M: float = 0.55  # brush passes per metre along boundary
const INNER_RAISE_BRUSH_STEPS: int   = 5
const INNER_RAISE_RADIUS_FACTOR: float = 0.65  # relative to raise_height
const DEFAULT_CLIFF_TEXTURE_PATH: String = "res://assets/world/textures/ground/cliff_brush.png"
const ALT_CLIFF_TEXTURE_PATH: String = "res://assets/world/textures/ground/cliff2_brush.png"
const VERTICAL_STEEPNESS_MIN: float = 85.0
const GUIDE_DASH_METERS: float = 1.8
const CAVE_DEPTH: float = 2.8
const CAVE_RADIUS: float = 1.2
const CAVE_HEIGHT: float = 2.1
const UNDO_MAX_DEPTH: int = 20

# ---------- state ----------------------------------------------------------
enum State { IDLE, DRAWING, SELECTED }

var _state: State = State.IDLE

## All stored boundaries (Array[BoundaryData])
var _boundaries: Array = []

## ID counter for new boundaries
var _next_id: int = 1

## Points accumulated during DRAWING
var _draw_points: Array = []  # Array[Vector3]
var _draw_closed: bool = false
var _draw_result: BoundaryData = null
var _finalize_pending: bool = false
var _apply_in_progress: bool = false
var _pending_apply_id: int = -1
var _extrude_ops: Array = []
var _extrude_op_cursor: int = 0

## Currently selected boundary
var _selected_id: int = -1
var _cave_place_mode: bool = false

## For drag-editing a selected boundary point
var _drag_point_index: int = -1
var _hover_handle_index: int = -1

## External references supplied via activate()
var _terrain_node: Node = null
var _camera: Camera3D = null
var _world_layer: int = 0

# ---------- preview visuals -----------------------------------------------
var _preview_mesh_inst: MeshInstance3D = null  # live preview while drawing (ImmediateMesh)
var _boundary_mesh_insts: Dictionary = {}       # id -> MeshInstance3D for closed boundaries
var _applied_cliff_mesh_insts: Dictionary = {}  # id -> MeshInstance3D for generated cliff wall
var _applied_contour_mesh_insts: Dictionary = {} # id -> MeshInstance3D for ink contour accents
var _cave_nodes_by_boundary: Dictionary = {}    # id -> Array[Node3D]
var _undo_stack: Array = []                     # Array of boundary snapshots for Ctrl+Z
var _handle_nodes: Array = []                   # handle spheres for selected boundary

# ---------- material cache -----------------------------------------------
var _mat_preview: StandardMaterial3D = null
var _mat_closed: StandardMaterial3D = null
var _mat_selected: StandardMaterial3D = null
var _mat_ghost: StandardMaterial3D = null
var _mat_contour: StandardMaterial3D = null

# ==========================================================================
func _ready() -> void:
	_build_materials()
	_preview_mesh_inst = _make_mesh_inst(ImmediateMesh.new(), _mat_preview)
	_preview_mesh_inst.name = "BoundaryPreview"
	add_child(_preview_mesh_inst)

# ---------- public API ----------------------------------------------------

func activate(terrain_node: Node, camera: Camera3D, world_layer: int) -> void:
	_terrain_node = terrain_node
	_camera = camera
	_world_layer = world_layer
	_state = State.DRAWING
	_draw_points.clear()
	_draw_closed = false
	_draw_result = null
	_deselect()
	_refresh_preview_mesh()
	drawing_started.emit()

func deactivate() -> void:
	if _state == State.DRAWING and _draw_points.size() >= 2:
		print("[Boundary] deactivate: discarding in-progress draw with %d points" % _draw_points.size())
	_state = State.IDLE
	_draw_points.clear()
	_draw_closed = false
	_draw_result = null
	_finalize_pending = false
	_cave_place_mode = false
	_deselect()
	_refresh_preview_mesh()

## Cancel in-progress drawing without saving (discard current points).
func cancel_drawing() -> void:
	if _state == State.DRAWING:
		_draw_points.clear()
		_state = State.IDLE
		_cave_place_mode = false
		_refresh_preview_mesh()

## Finish current cliff line in-progress (same as double-click).
func close_drawing() -> void:
	if _state == State.DRAWING and _draw_points.size() >= 2:
		print("[Boundary] close requested via Enter with %d points" % _draw_points.size())
		_request_finalize_draw(false)

func set_active_layer(layer: int) -> void:
	_world_layer = layer

func get_boundaries() -> Array:
	return _boundaries

func get_selected() -> BoundaryData:
	if _selected_id < 0:
		return null
	return _find_boundary(_selected_id)

func begin_cave_placement() -> void:
	if get_selected() == null:
		return
	_cave_place_mode = true

## Main input handler.  Call from _unhandled_input.  Returns true if consumed.
func handle_input(event: InputEvent, mouse_screen_pos: Vector2) -> bool:
	match _state:
		State.DRAWING:
			return _handle_draw_input(event, mouse_screen_pos)
		State.SELECTED:
			return _handle_select_input(event, mouse_screen_pos)
	return false

## Apply terrain extrusion for the currently selected boundary.
func apply_selected() -> void:
	var b: BoundaryData = get_selected()
	if b == null or _terrain_node == null or _apply_in_progress:
		return
	print("[Boundary] apply requested for id=%d label=%s" % [b.id, b.label])
	_push_undo_snapshot()
	_apply_in_progress = true
	_pending_apply_id = b.id
	call_deferred("_begin_apply_pipeline_deferred")

## Delete the currently selected boundary.
func delete_selected() -> void:
	if _selected_id < 0:
		return
	_push_undo_snapshot()
	_remove_boundary_visual(_selected_id)
	_boundaries = _boundaries.filter(func(x: BoundaryData) -> bool: return x.id != _selected_id)
	_selected_id = -1
	_clear_handles()
	_state = State.DRAWING
	boundary_deselected.emit()

## Update a property on the selected boundary (called from inspector).
func set_selected_property(prop: String, value: Variant) -> void:
	var b: BoundaryData = get_selected()
	if b == null:
		return
	match prop:
		"label":
			b.label = String(value)
		"type":
			b.boundary_type = String(value)
			b.face_material = String(value)
		"material":
			b.face_material = String(value)
		"direction":
			b.raise_side = 1 if int(value) >= 0 else -1
		"steepness":
			b.steepness_deg = clampf(float(value), 0.0, 90.0)
		"raise_height":
			b.raise_height = clampf(float(value), 0.0, 80.0)
		"wall_brush_width":
			b.wall_brush_width = clampf(float(value), 0.5, 20.0)
		"wall_texture_id":
			b.wall_texture_id = String(value)
		"closed":
			b.is_closed = bool(value)
	if b.applied:
		_refresh_applied_boundary_visuals(b)
	else:
		_rebuild_boundary_visual(b.id)

## Serialise all boundaries for map saving.
func serialize() -> Array:
	var out: Array = []
	for b in _boundaries:
		out.append((b as BoundaryData).serialize())
	return out

## Restore from saved data.
func deserialize(arr: Array) -> void:
	_clear_all_visuals()
	_boundaries.clear()
	_next_id = 1
	for d in arr:
		if not (d is Dictionary):
			continue
		var b: BoundaryData = BoundaryData.deserialize(d as Dictionary)
		if b.points.size() < 2:
			continue
		if b.id >= _next_id:
			_next_id = b.id + 1
		_boundaries.append(b)
		if b.applied:
			_rebuild_applied_cliff_visual(b)
			_rebuild_cave_entrances_visuals(b)
		else:
			_rebuild_boundary_visual(b.id)

## Undo the last boundary data mutation (Ctrl+Z).  Does not undo terrain sculpting.
func undo_last() -> void:
	if _undo_stack.is_empty():
		print("[Boundary] undo: nothing to undo")
		return
	var snapshot: Array = _undo_stack.pop_back() as Array
	_deselect()
	_clear_all_visuals()
	_boundaries.clear()
	_next_id = 1
	for d in snapshot:
		if not (d is Dictionary):
			continue
		var b: BoundaryData = BoundaryData.deserialize(d as Dictionary)
		if b.points.size() < 2:
			continue
		if b.id >= _next_id:
			_next_id = b.id + 1
		_boundaries.append(b)
		if b.applied:
			_rebuild_applied_cliff_visual(b)
			_rebuild_cave_entrances_visuals(b)
		else:
			_rebuild_boundary_visual(b.id)
	_state = State.DRAWING
	boundary_deselected.emit()
	print("[Boundary] undo: restored %d boundaries" % _boundaries.size())

## Delete a cave entrance by index from the selected boundary.
func delete_cave_entrance(entrance_index: int) -> void:
	var b: BoundaryData = get_selected()
	if b == null or entrance_index < 0 or entrance_index >= b.cave_entrances.size():
		return
	_push_undo_snapshot()
	b.cave_entrances.remove_at(entrance_index)
	_rebuild_cave_entrances_visuals(b)
	boundary_selected.emit(b)

# ==========================================================================
# DRAWING STATE
# ==========================================================================

func _handle_draw_input(event: InputEvent, mouse_screen_pos: Vector2) -> bool:
	if not event is InputEventMouseButton:
		if event is InputEventMouseMotion:
			_refresh_preview_mesh()
		return false

	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed:
		return false

	if mb.button_index == MOUSE_BUTTON_RIGHT:
		# Right-click: cancel current line
		_draw_points.clear()
		_state = State.DRAWING
		_refresh_preview_mesh()
		return true

	if mb.button_index == MOUSE_BUTTON_LEFT:
		if _draw_points.is_empty() and not mb.double_click and try_select_at(mouse_screen_pos):
			return true
		var hit: Variant = _raycast_terrain(mouse_screen_pos)
		if not (hit is Vector3):
			return false
		var world_pos: Vector3 = hit as Vector3
		world_pos.y = _sample_height(world_pos.x, world_pos.z) + LINE_LIFT

		if mb.double_click:
			# Double-click: finish line
			if _draw_points.size() >= 2:
				print("[Boundary] close requested via double-click with %d points" % _draw_points.size())
				_request_finalize_draw(false)
			return true

		# Single click: add point
		_draw_points.append(world_pos)
		_refresh_preview_mesh()
		return true

	return false

func _request_finalize_draw(closed: bool) -> void:
	if _finalize_pending:
		return
	_finalize_pending = true
	call_deferred("_finalize_draw_deferred", closed)


func _finalize_draw_deferred(closed: bool) -> void:
	_finalize_pending = false
	print("[Boundary] finalize begin closed=%s points=%d" % [str(closed), _draw_points.size()])
	if _draw_points.size() < 2:
		_state = State.DRAWING
		_refresh_preview_mesh()
		print("[Boundary] finalize aborted: not enough points")
		return
	var b := BoundaryData.new()
	b.id = _next_id
	_next_id += 1
	b.label = "Cliff Line %d" % b.id
	b.world_layer = _world_layer
	b.points = _draw_points.duplicate()
	b.is_closed = false
	b.raise_height = 8.0
	b.steepness_deg = 75.0
	b.raise_side = 1
	b.face_material = "rock"
	# Snap Y values to current terrain height
	for i in range(b.points.size()):
		var p: Vector3 = b.points[i]
		p.y = _sample_height(p.x, p.z) + LINE_LIFT
		b.points[i] = p
	_boundaries.append(b)
	_draw_result = b
	_push_undo_snapshot()
	_draw_points.clear()
	_state = State.SELECTED
	_refresh_preview_mesh()
	# Defer visual rebuild + selection + signal to keep input path responsive.
	call_deferred("_complete_finalize_visuals", b.id)


func _complete_finalize_visuals(boundary_id: int) -> void:
	var b: BoundaryData = _find_boundary(boundary_id)
	if b == null:
		print("[Boundary] finalize end: boundary disappeared before visualization")
		return
	_rebuild_boundary_visual(boundary_id)
	_select_boundary(boundary_id)
	print("[Boundary] finalize end id=%d total=%d" % [boundary_id, _boundaries.size()])
	drawing_finished.emit(b)


func _begin_apply_pipeline_deferred() -> void:
	var boundary_id: int = _pending_apply_id
	_pending_apply_id = -1
	var b: BoundaryData = _find_boundary(boundary_id)
	if b == null or _terrain_node == null:
		_apply_in_progress = false
		return
	print("[Boundary] extrusion begin id=%d points=%d" % [boundary_id, b.points.size()])
	_extrude_ops = _build_extrude_ops(b)
	_extrude_op_cursor = 0
	await _run_extrude_ops_async()
	b.applied = true
	_remove_boundary_visual(b.id)
	_rebuild_applied_cliff_visual(b)
	_rebuild_cave_entrances_visuals(b)
	if _selected_id == b.id:
		_rebuild_handles()
		boundary_selected.emit(b)
	print("[Boundary] extrusion end id=%d" % boundary_id)
	_apply_in_progress = false

# ==========================================================================
# SELECTION / HANDLE DRAG
# ==========================================================================

func _handle_select_input(event: InputEvent, mouse_screen_pos: Vector2) -> bool:
	var b: BoundaryData = get_selected()
	if b == null:
		return false
	if _cave_place_mode:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var cave_mb: InputEventMouseButton = event as InputEventMouseButton
			if cave_mb.button_index == MOUSE_BUTTON_RIGHT:
				_cave_place_mode = false
				return true
			if cave_mb.button_index == MOUSE_BUTTON_LEFT:
				var cave_hit: Variant = _raycast_terrain(mouse_screen_pos)
				if cave_hit is Vector3:
					_try_place_cave_entrance(b, cave_hit as Vector3)
					_cave_place_mode = false
					return true
		return false

	if event is InputEventMouseMotion:
		# Drag an existing point
		if _drag_point_index >= 0 and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			var hit: Variant = _raycast_terrain(mouse_screen_pos)
			if hit is Vector3:
				var world_pos: Vector3 = hit as Vector3
				world_pos.y = _sample_height(world_pos.x, world_pos.z) + LINE_LIFT
				b.points[_drag_point_index] = world_pos
				if b.applied:
					_refresh_applied_boundary_visuals(b)
				else:
					_rebuild_boundary_visual(b.id)
				_rebuild_handles()
		# Hover nearest handle
		_update_hover_handle(mouse_screen_pos)
		return _drag_point_index >= 0

	if not event is InputEventMouseButton:
		return false
	var mb: InputEventMouseButton = event as InputEventMouseButton

	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_drag_point_index = _pick_handle(mouse_screen_pos)
			if _drag_point_index < 0:
				# Click on terrain outside handles → deselect
				var hit: Variant = _raycast_terrain(mouse_screen_pos)
				if hit is Vector3:
					_deselect()
					_state = State.DRAWING
					boundary_deselected.emit()
					return true
		else:
			_drag_point_index = -1
		return true

	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_deselect()
		_state = State.DRAWING
		_cave_place_mode = false
		boundary_deselected.emit()
		return true

	return false

## Try to pick a boundary by clicking near one of its line segments.
## Returns the id of the picked boundary, or -1.
func pick_boundary(mouse_screen_pos: Vector2) -> int:
	if _camera == null:
		return -1
	for b_variant in _boundaries:
		var b: BoundaryData = b_variant as BoundaryData
		if b == null or b.points.size() < 2:
			continue
		for i in range(b.points.size()):
			var p: Vector3 = b.points[i]
			if _camera.is_position_behind(p):
				continue
			var sp: Vector2 = _camera.unproject_position(p)
			if mouse_screen_pos.distance_to(sp) < 16.0:
				return b.id
	return -1

func try_select_at(mouse_screen_pos: Vector2) -> bool:
	var id: int = pick_boundary(mouse_screen_pos)
	if id >= 0:
		_select_boundary(id)
		_state = State.SELECTED
		return true
	return false

func _select_boundary(id: int) -> void:
	_selected_id = id
	_rebuild_handles()
	_rebuild_boundary_visual(id)  # re-draw with selected colour
	var b: BoundaryData = _find_boundary(id)
	if b != null:
		boundary_selected.emit(b)
	# Re-draw others as unselected
	for b_var in _boundaries:
		var bx: BoundaryData = b_var as BoundaryData
		if bx != null and bx.id != id:
			_rebuild_boundary_visual(bx.id)

func _deselect() -> void:
	var prev_id: int = _selected_id
	_selected_id = -1
	_drag_point_index = -1
	_cave_place_mode = false
	_clear_handles()
	if prev_id >= 0:
		_rebuild_boundary_visual(prev_id)

# ==========================================================================
# TERRAIN EXTRUSION
# ==========================================================================

func _build_extrude_ops(b: BoundaryData) -> Array:
	var ops: Array = []
	if _terrain_node == null or b.points.size() < 2:
		return ops
	if not _terrain_node.has_method("apply_brush"):
		return ops

	var pts: Array = b.points
	var wall_brush: float = b.wall_brush_width
	var height_delta: float = maxf(b.raise_height, 2.0)
	var side_sign: float = 1.0 if b.raise_side >= 0 else -1.0
	var steepness_clamped: float = clampf(b.steepness_deg, 0.0, 90.0)
	var is_vertical_case: bool = steepness_clamped >= VERTICAL_STEEPNESS_MIN
	var ramp_factor: float = inverse_lerp(VERTICAL_STEEPNESS_MIN, 90.0, steepness_clamped) if is_vertical_case else 0.0
	var step_dist: float = 1.0 / maxf(0.01, EXTRUDE_BRUSH_STEPS_PER_M)
	# Use significantly higher step density for vertical cliffs so the brush
	# stamps cover the face without gaps at the aggressive radius sizes needed.
	if is_vertical_case:
		var vert_density: float = lerpf(1.6, 3.2, ramp_factor)
		step_dist = 1.0 / maxf(0.01, EXTRUDE_BRUSH_STEPS_PER_M * vert_density)
	var cliff_texture_id: String = _resolve_cliff_texture_id(b.wall_texture_id)

	for edge_idx in range(pts.size() - 1):
		var pa: Vector3 = pts[edge_idx]
		var pb: Vector3 = pts[edge_idx + 1]
		var edge: Vector3 = pb - pa
		edge.y = 0.0
		var edge_len: float = edge.length()
		if edge_len < 0.05:
			continue
		var edge_dir: Vector3 = edge / edge_len
		var outward_normal: Vector3 = Vector3(-edge_dir.z, 0.0, edge_dir.x) * side_sign
		var steps: int = maxi(1, int(ceil(edge_len / step_dist)))

		for s in range(steps + 1):
			var t: float = float(s) / float(steps)
			var base_pos: Vector3 = pa.lerp(pb, t)
			base_pos.y = _sample_height(base_pos.x, base_pos.z)

			if is_vertical_case:
				# ---- TRUE VERTICAL CLIFF (85-90°) --------------------------------
				# Tight primary raise: positioned close to the edge, narrow radius,
				# very hard edge — produces the steep near-vertical face.
				var edge_off: float = lerpf(0.08, 0.04, ramp_factor) * wall_brush
				var raise_pos: Vector3 = base_pos - outward_normal * edge_off
				raise_pos.y = _sample_height(raise_pos.x, raise_pos.z)
				ops.append({
					"tool": "raise",
					"pos": raise_pos,
					"radius": wall_brush * lerpf(0.52, 0.28, ramp_factor),
					"strength": height_delta * lerpf(0.85, 1.15, ramp_factor),
					"flatten": raise_pos.y + height_delta,
					"softness": lerpf(0.16, 0.03, ramp_factor),
					"mode": "sharp",
				})
				# Secondary narrow wall-face raise: pushes the cliff steeper.
				var wall_pos: Vector3 = base_pos - outward_normal * (lerpf(0.05, 0.02, ramp_factor) * wall_brush)
				wall_pos.y = _sample_height(wall_pos.x, wall_pos.z)
				ops.append({
					"tool": "raise",
					"pos": wall_pos,
					"radius": wall_brush * lerpf(0.26, 0.15, ramp_factor),
					"strength": height_delta * lerpf(0.70, 1.0, ramp_factor),
					"flatten": wall_pos.y + (height_delta * lerpf(0.95, 1.0, ramp_factor)),
					"softness": lerpf(0.08, 0.01, ramp_factor),
					"mode": "sharp",
				})
				# Top-cap flatten: locks the cliff top to the exact target height.
				var cap_pos: Vector3 = base_pos - outward_normal * (lerpf(0.10, 0.04, ramp_factor) * wall_brush)
				cap_pos.y = _sample_height(cap_pos.x, cap_pos.z)
				ops.append({
					"tool": "flatten",
					"pos": cap_pos,
					"radius": wall_brush * lerpf(0.40, 0.22, ramp_factor),
					"strength": 1.0,
					"flatten": cap_pos.y + height_delta,
					"softness": lerpf(0.06, 0.01, ramp_factor),
					"mode": "sharp",
				})
				# Outer base flatten: keeps the ground at the foot level — prevents
				# the slope from spreading outward.
				var base_outer: Vector3 = base_pos + outward_normal * (lerpf(0.40, 0.58, ramp_factor) * wall_brush)
				base_outer.y = _sample_height(base_outer.x, base_outer.z)
				ops.append({
					"tool": "flatten",
					"pos": base_outer,
					"radius": wall_brush * lerpf(0.58, 0.50, ramp_factor),
					"strength": lerpf(0.75, 0.95, ramp_factor),
					"flatten": base_outer.y,
					"softness": 0.42,
					"mode": "smooth",
				})
			if is_vertical_case:
				# ---- TRUE VERTICAL CLIFF (85-90°) --------------------------------
				# Op 1: Wide plateau raise — establishes the full raised inner area.
				var plateau_pos: Vector3 = base_pos - outward_normal * (lerpf(0.50, 0.60, ramp_factor) * wall_brush)
				plateau_pos.y = _sample_height(plateau_pos.x, plateau_pos.z)
				ops.append({
					"tool": "raise",
					"pos": plateau_pos,
					"radius": wall_brush * lerpf(0.72, 0.85, ramp_factor),
					"strength": height_delta * lerpf(1.6, 2.4, ramp_factor),
					"flatten": plateau_pos.y + height_delta,
					"softness": lerpf(0.10, 0.04, ramp_factor),
					"mode": "sharp",
				})
				# Op 2: Narrow edge raise — stamps the full height to the cliff face.
				if is_vertical_case:
					# ---- TRUE VERTICAL CLIFF (85-90°) --------------------------------
					# Op 1: Wide plateau raise — establishes the full raised inner area.
					var plateau_pos_inner: Vector3 = base_pos - outward_normal * (lerpf(0.50, 0.60, ramp_factor) * wall_brush)
					plateau_pos_inner.y = _sample_height(plateau_pos_inner.x, plateau_pos_inner.z)
					ops.append({
						"tool": "raise",
						"pos": plateau_pos_inner,
						"radius": wall_brush * lerpf(0.72, 0.85, ramp_factor),
						"strength": height_delta * lerpf(1.6, 2.4, ramp_factor),
						"flatten": plateau_pos_inner.y + height_delta,
						"softness": lerpf(0.10, 0.04, ramp_factor),
						"mode": "sharp",
					})
					# Op 2: Narrow edge raise — stamps the full height to the cliff face.
					var edge_raise_pos_inner: Vector3 = base_pos - outward_normal * (lerpf(0.07, 0.04, ramp_factor) * wall_brush)
					edge_raise_pos_inner.y = _sample_height(edge_raise_pos_inner.x, edge_raise_pos_inner.z)
					ops.append({
						"tool": "raise",
						"pos": edge_raise_pos_inner,
						"radius": wall_brush * lerpf(0.22, 0.14, ramp_factor),
						"strength": height_delta * lerpf(1.6, 2.2, ramp_factor),
						"flatten": edge_raise_pos_inner.y + height_delta,
						"softness": lerpf(0.04, 0.01, ramp_factor),
						"mode": "sharp",
					})
					# Op 3: Top-cap precision flatten — locks the plateau top perfectly flat.
					var cap_pos_inner: Vector3 = base_pos - outward_normal * (lerpf(0.28, 0.32, ramp_factor) * wall_brush)
					cap_pos_inner.y = _sample_height(cap_pos_inner.x, cap_pos_inner.z)
					ops.append({
						"tool": "flatten",
						"pos": cap_pos_inner,
						"radius": wall_brush * lerpf(0.55, 0.65, ramp_factor),
						"strength": 1.0,
						"flatten": cap_pos_inner.y + height_delta,
						"softness": lerpf(0.04, 0.01, ramp_factor),
						"mode": "sharp",
					})
					# Op 4: Foot-of-cliff hard lock — clamps ground at the cliff base.
					# This is the key op that eliminates slope bleed.
					var foot_pos_inner: Vector3 = base_pos + outward_normal * (lerpf(0.05, 0.04, ramp_factor) * wall_brush)
					foot_pos_inner.y = _sample_height(foot_pos_inner.x, foot_pos_inner.z)
					ops.append({
						"tool": "flatten",
						"pos": foot_pos_inner,
						"radius": wall_brush * lerpf(0.16, 0.10, ramp_factor),
						"strength": 1.0,
						"flatten": foot_pos_inner.y,
						"softness": lerpf(0.04, 0.01, ramp_factor),
						"mode": "sharp",
					})
					# Op 5: Wide outer bleed guard — smoothly restores ground level
					# beyond the cliff foot to prevent a raised shoulder effect.
					var outer_pos_inner: Vector3 = base_pos + outward_normal * (lerpf(0.48, 0.58, ramp_factor) * wall_brush)
					outer_pos_inner.y = _sample_height(outer_pos_inner.x, outer_pos_inner.z)
					ops.append({
						"tool": "flatten",
						"pos": outer_pos_inner,
						"radius": wall_brush * lerpf(0.65, 0.72, ramp_factor),
						"strength": lerpf(0.82, 0.95, ramp_factor),
						"flatten": outer_pos_inner.y,
						"softness": 0.38,
						"mode": "smooth",
					})
				var edge_raise_pos: Vector3 = base_pos - outward_normal * (lerpf(0.07, 0.04, ramp_factor) * wall_brush)
				edge_raise_pos.y = _sample_height(edge_raise_pos.x, edge_raise_pos.z)
				ops.append({
					"tool": "raise",
					"pos": edge_raise_pos,
					"radius": wall_brush * lerpf(0.22, 0.14, ramp_factor),
					"strength": height_delta * lerpf(1.6, 2.2, ramp_factor),
					"flatten": edge_raise_pos.y + height_delta,
					"softness": lerpf(0.04, 0.01, ramp_factor),
					"mode": "sharp",
				})
				# Op 3: Top-cap precision flatten — locks the plateau top perfectly flat.
				var cap_pos: Vector3 = base_pos - outward_normal * (lerpf(0.28, 0.32, ramp_factor) * wall_brush)
				cap_pos.y = _sample_height(cap_pos.x, cap_pos.z)
				ops.append({
					"tool": "flatten",
					"pos": cap_pos,
					"radius": wall_brush * lerpf(0.55, 0.65, ramp_factor),
					"strength": 1.0,
					"flatten": cap_pos.y + height_delta,
					"softness": lerpf(0.04, 0.01, ramp_factor),
					"mode": "sharp",
				})
				# Op 4: Foot-of-cliff hard lock — clamps ground at the cliff base.
				# This is the key op that eliminates slope bleed.
				var foot_pos: Vector3 = base_pos + outward_normal * (lerpf(0.05, 0.04, ramp_factor) * wall_brush)
				foot_pos.y = _sample_height(foot_pos.x, foot_pos.z)
				ops.append({
					"tool": "flatten",
					"pos": foot_pos,
					"radius": wall_brush * lerpf(0.16, 0.10, ramp_factor),
					"strength": 1.0,
					"flatten": foot_pos.y,
					"softness": lerpf(0.04, 0.01, ramp_factor),
					"mode": "sharp",
				})
				# Op 5: Wide outer bleed guard — smoothly restores ground level
				# beyond the cliff foot to prevent a raised shoulder effect.
				var outer_pos: Vector3 = base_pos + outward_normal * (lerpf(0.48, 0.58, ramp_factor) * wall_brush)
				outer_pos.y = _sample_height(outer_pos.x, outer_pos.z)
				ops.append({
					"tool": "flatten",
					"pos": outer_pos,
					"radius": wall_brush * lerpf(0.65, 0.72, ramp_factor),
					"strength": lerpf(0.82, 0.95, ramp_factor),
					"flatten": outer_pos.y,
					"softness": 0.38,
					"mode": "smooth",
				})
			else:  # sloped
				# ---- SLOPED CLIFF (< 85°) ----------------------------------------
				var slope_factor: float = sin(deg_to_rad(steepness_clamped))
				var inner_offset: float = wall_brush * 0.65 * slope_factor
				var raise_pos: Vector3 = base_pos - outward_normal * inner_offset
				raise_pos.y = _sample_height(raise_pos.x, raise_pos.z)
				ops.append({
					"tool": "raise",
					"pos": raise_pos,
					"radius": wall_brush * 0.84,
					"strength": height_delta * 0.45,
					"flatten": raise_pos.y + height_delta,
					"softness": 0.35,
					"mode": "sharp",
				})
				var outer_pos: Vector3 = base_pos + outward_normal * (wall_brush * 0.4)
				outer_pos.y = _sample_height(outer_pos.x, outer_pos.z)
				ops.append({
					"tool": "flatten",
					"pos": outer_pos,
					"radius": wall_brush * 0.62,
					"strength": 0.68,
					"flatten": outer_pos.y,
					"softness": 0.58,
					"mode": "smooth",
				})
				# Subtle contour for pen-and-ink readability.
				if (s % 2) == 0:
					var contour_pos: Vector3 = base_pos - outward_normal * (inner_offset * 0.45)
					contour_pos.y = _sample_height(contour_pos.x, contour_pos.z)
					ops.append({
						"tool": "smooth",
						"pos": contour_pos,
						"radius": wall_brush * 0.35,
						"strength": 0.12,
						"flatten": contour_pos.y,
						"softness": 0.30,
						"mode": "smooth",
					})

			if cliff_texture_id != "":
				var paint_ref_off: float = (lerpf(0.06, 0.03, ramp_factor) if is_vertical_case else 0.30) * wall_brush
				var paint_pos: Vector3 = base_pos - outward_normal * paint_ref_off
				paint_pos.y = _sample_height(paint_pos.x, paint_pos.z)
				ops.append({
					"tool": "texturepaint",
					"pos": paint_pos,
					"radius": wall_brush * 0.65,
					"strength": 0.42,
					"texture_id": cliff_texture_id,
				})
	return ops


func _run_extrude_ops_async() -> void:
	if _terrain_node == null:
		return
	var chunk_size: int = 56
	while _extrude_op_cursor < _extrude_ops.size():
		var chunk_end: int = mini(_extrude_op_cursor + chunk_size, _extrude_ops.size())
		for i in range(_extrude_op_cursor, chunk_end):
			var op: Dictionary = _extrude_ops[i] as Dictionary
			var tool_name: String = String(op.get("tool", "raise"))
			var pos: Vector3 = op.get("pos", Vector3.ZERO)
			if tool_name == "texturepaint":
				_apply_texture_op(op)
				continue
			_terrain_node.call(
				"apply_brush",
				tool_name,
				pos,
				float(op.get("radius", 2.0)),
				float(op.get("strength", 0.25)),
				float(op.get("flatten", pos.y)),
				false,
				0.3,
				float(op.get("softness", 0.35)),
				String(op.get("mode", "smooth")),
				0,
				true
			)
		_extrude_op_cursor = chunk_end
		await get_tree().process_frame
	if _terrain_node.has_method("flush_deferred_rebuild"):
		_terrain_node.call("flush_deferred_rebuild")
	elif _terrain_node.has_method("rebuild_mesh"):
		_terrain_node.call("rebuild_mesh")


func _apply_texture_op(op: Dictionary) -> void:
	if _terrain_node == null or not _terrain_node.has_method("apply_texture_brush"):
		return
	var tex_id: String = String(op.get("texture_id", ""))
	if tex_id == "":
		return
	if not ResourceLoader.exists(tex_id):
		return
	var texture_res: Resource = load(tex_id)
	if not (texture_res is Texture2D):
		return
	_terrain_node.call(
		"apply_texture_brush",
		op.get("pos", Vector3.ZERO),
		texture_res as Texture2D,
		null,       # normal
		null,       # roughness
		null,       # height
		null,       # ao
		float(op.get("radius", 2.0)),
		maxf(float(op.get("strength", 0.3)), 0.01),
		4.0,        # tile_size
		1.0,        # density
		0.40,       # softness
		0.92,       # coverage
		Vector2.ZERO,
		0.0,        # rot
		1.0,        # scale
		1.0,        # exposure
		"circle",
		0.0,        # variation
		0.0,        # seed
		0,          # variant
		"sharp",
		tex_id,
		true        # defer_rebuild
	)


func _resolve_cliff_texture_id(texture_id: String) -> String:
	var id_trim: String = texture_id.strip_edges()
	if id_trim == "":
		return DEFAULT_CLIFF_TEXTURE_PATH
	if id_trim == ALT_CLIFF_TEXTURE_PATH or id_trim == DEFAULT_CLIFF_TEXTURE_PATH:
		return id_trim
	if ResourceLoader.exists(id_trim):
		return id_trim
	return DEFAULT_CLIFF_TEXTURE_PATH


func _polygon_centroid(pts: Array) -> Vector3:
	var s: Vector3 = Vector3.ZERO
	for p in pts:
		s += p as Vector3
	return s / float(pts.size())

func _polygon_avg_radius(pts: Array, centroid: Vector3) -> float:
	if pts.is_empty():
		return 1.0
	var total: float = 0.0
	for p in pts:
		var d: Vector3 = (p as Vector3) - centroid
		d.y = 0.0
		total += d.length()
	return total / float(pts.size())

# ==========================================================================
# VISUAL PREVIEW MESH
# ==========================================================================

func _process(_delta: float) -> void:
	# Only update live drawing preview — completed boundaries have static meshes.
	if _state == State.DRAWING:
		_refresh_preview_mesh()

func _refresh_preview_mesh() -> void:
	if _preview_mesh_inst == null:
		return
	var im: ImmediateMesh = _preview_mesh_inst.mesh as ImmediateMesh
	if im == null:
		return
	im.clear_surfaces()

	if _state != State.DRAWING or _draw_points.is_empty():
		return

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	# Draw placed segments as subtle dashed guide lines.
	for i in range(_draw_points.size() - 1):
		var pa: Vector3 = _draw_points[i] as Vector3
		var pb: Vector3 = _draw_points[i + 1] as Vector3
		var seg: Vector3 = pb - pa
		var seg_len: float = seg.length()
		if seg_len < 0.01:
			continue
		var dir: Vector3 = seg / seg_len
		var cursor: float = 0.0
		while cursor < seg_len:
			var dash_start: Vector3 = pa + dir * cursor
			var dash_end_dist: float = cursor + GUIDE_DASH_METERS * 0.45
			if dash_end_dist > seg_len:
				dash_end_dist = seg_len
			var dash_end: Vector3 = pa + dir * dash_end_dist
			im.surface_set_color(PREVIEW_LINE_COLOR)
			im.surface_add_vertex(dash_start)
			im.surface_add_vertex(dash_end)
			cursor += GUIDE_DASH_METERS
	# Ghost line from last point to cursor
	if _camera != null and _draw_points.size() > 0:
		var last: Vector3 = _draw_points[_draw_points.size() - 1] as Vector3
		var mouse_pos: Vector2 = _camera.get_viewport().get_mouse_position()
		var hit: Variant = _raycast_terrain(mouse_pos)
		if hit is Vector3:
			var ghost: Vector3 = hit as Vector3
			ghost.y = _sample_height(ghost.x, ghost.z) + LINE_LIFT
			im.surface_set_color(GHOST_LINE_COLOR)
			im.surface_add_vertex(last)
			im.surface_set_color(GHOST_LINE_COLOR)
			im.surface_add_vertex(ghost)
	im.surface_end()

	# Draw point marks as small X accents.
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for p_var in _draw_points:
		var p: Vector3 = p_var as Vector3
		im.surface_set_color(PREVIEW_LINE_COLOR)
		im.surface_add_vertex(p + Vector3(-0.18, 0.0, -0.18))
		im.surface_add_vertex(p + Vector3(0.18, 0.0, 0.18))
		im.surface_add_vertex(p + Vector3(-0.18, 0.0, 0.18))
		im.surface_add_vertex(p + Vector3(0.18, 0.0, -0.18))
	im.surface_end()

func _rebuild_boundary_visual(id: int) -> void:
	_remove_guide_visual(id)
	var b: BoundaryData = _find_boundary(id)
	if b == null or b.points.size() < 2:
		return

	var is_sel: bool = (id == _selected_id)
	if b.applied and not is_sel:
		return
	var line_color: Color = SELECTED_LINE_COLOR if is_sel else CLOSED_LINE_COLOR

	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(line_color)
	var pts: Array = b.points
	for i in range(pts.size() - 1):
		im.surface_add_vertex(pts[i] as Vector3)
		im.surface_add_vertex(pts[i + 1] as Vector3)
	# Direction indicator (shows the raised side of the line).
	if pts.size() >= 2:
		var mid_idx: int = maxi(0, int((pts.size() - 2) * 0.5))
		var m0: Vector3 = pts[mid_idx] as Vector3
		var m1: Vector3 = pts[mid_idx + 1] as Vector3
		var seg: Vector3 = m1 - m0
		seg.y = 0.0
		if seg.length() > 0.01:
			var dir: Vector3 = seg.normalized()
			var nrm: Vector3 = Vector3(-dir.z, 0.0, dir.x) * (1.0 if b.raise_side >= 0 else -1.0)
			var center: Vector3 = (m0 + m1) * 0.5
			var arrow_tip: Vector3 = center + nrm * maxf(1.0, b.wall_brush_width * 0.6)
			im.surface_add_vertex(center)
			im.surface_add_vertex(arrow_tip)
	im.surface_end()

	var mat: StandardMaterial3D = _mat_selected if is_sel else _mat_closed
	var inst: MeshInstance3D = _make_mesh_inst(im, mat)
	inst.name = "Boundary_%d" % id
	add_child(inst)
	_boundary_mesh_insts[id] = inst


func _rebuild_applied_cliff_visual(b: BoundaryData) -> void:
	if b == null or b.points.size() < 2:  # keeps its own full-remove logic
		return
	if _boundary_mesh_insts.has(b.id):
		var preview_node: Node = _boundary_mesh_insts[b.id] as Node
		if preview_node != null and is_instance_valid(preview_node):
			preview_node.queue_free()
		_boundary_mesh_insts.erase(b.id)
	if _applied_cliff_mesh_insts.has(b.id):
		var old_cliff_node: Node = _applied_cliff_mesh_insts[b.id] as Node
		if old_cliff_node != null and is_instance_valid(old_cliff_node):
			old_cliff_node.queue_free()
		_applied_cliff_mesh_insts.erase(b.id)
	if _applied_contour_mesh_insts.has(b.id):
		var old_contour_node: Node = _applied_contour_mesh_insts[b.id] as Node
		if old_contour_node != null and is_instance_valid(old_contour_node):
			old_contour_node.queue_free()
		_applied_contour_mesh_insts.erase(b.id)
	var mesh: ArrayMesh = _build_cliff_face_mesh(b)
	if mesh == null:
		return
	var cliff_mat: StandardMaterial3D = _build_cliff_face_material(b)
	var cliff_inst := MeshInstance3D.new()
	cliff_inst.name = "AppliedCliff_%d" % b.id
	cliff_inst.mesh = mesh
	cliff_inst.material_override = cliff_mat
	cliff_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(cliff_inst)
	_applied_cliff_mesh_insts[b.id] = cliff_inst
	var contour_inst: MeshInstance3D = _build_cliff_contour_mesh(b)
	if contour_inst != null:
		add_child(contour_inst)
		_applied_contour_mesh_insts[b.id] = contour_inst


func _refresh_applied_boundary_visuals(b: BoundaryData) -> void:
	if b == null or not b.applied:
		return
	_rebuild_applied_cliff_visual(b)
	_rebuild_cave_entrances_visuals(b)


func _build_cliff_face_mesh(b: BoundaryData) -> ArrayMesh:
	var pts: Array = b.points
	if pts.size() < 2:
		return null
	var mesh := ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var total_len: float = _polyline_length(pts)
	if total_len <= 0.001:
		return null
	var steepness: float = clampf(b.steepness_deg, 0.0, 90.0)
	var verticalness: float = inverse_lerp(VERTICAL_STEEPNESS_MIN, 90.0, steepness) if steepness >= VERTICAL_STEEPNESS_MIN else 0.0
	var side_sign: float = 1.0 if b.raise_side >= 0 else -1.0
	var max_offset: float = maxf(0.02, b.wall_brush_width * (1.0 - (steepness / 90.0)) * 0.34)
	var run_len: float = 0.0
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[i + 1]
		var seg: Vector3 = c - a
		var seg_h: Vector3 = seg
		seg_h.y = 0.0
		var seg_len: float = seg_h.length()
		if seg_len < 0.05:
			continue
		var dir: Vector3 = seg_h / seg_len
		var face_normal: Vector3 = (Vector3(-dir.z, 0.0, dir.x) * side_sign).normalized()
		var offset_dist: float = lerpf(max_offset, 0.015, verticalness)
		var top_a_h: float = _sample_height(a.x, a.z) + b.raise_height
		var top_c_h: float = _sample_height(c.x, c.z) + b.raise_height
		if verticalness > 0.0:
			var top_h: float = maxf(top_a_h, top_c_h)
			var mid: Vector3 = (a + c) * 0.5
			top_h = maxf(top_h, _sample_height(mid.x, mid.z) + b.raise_height)
			top_a_h = top_h
			top_c_h = top_h
		var bot_a_h: float = _sample_height(a.x, a.z)
		var bot_c_h: float = _sample_height(c.x, c.z)
		var top_a: Vector3 = Vector3(a.x, top_a_h, a.z) - face_normal * offset_dist
		var top_c: Vector3 = Vector3(c.x, top_c_h, c.z) - face_normal * offset_dist
		var bot_a: Vector3 = Vector3(a.x, bot_a_h, a.z) + face_normal * (offset_dist * 0.25)
		var bot_c: Vector3 = Vector3(c.x, bot_c_h, c.z) + face_normal * (offset_dist * 0.25)
		# World-scale UV tiling so texture repeats properly regardless of cliff length.
		var UV_TILE: float = lerpf(2.2, 1.05, verticalness)
		var u0: float = run_len / UV_TILE
		var u1: float = (run_len + seg_len) / UV_TILE
		var v0: float = 0.0
		var v1: float = maxf(b.raise_height / UV_TILE, 0.35)

		st.set_normal(face_normal)
		st.set_uv(Vector2(u0, v0))
		st.add_vertex(bot_a)
		st.set_normal(face_normal)
		st.set_uv(Vector2(u0, v1))
		st.add_vertex(top_a)
		st.set_normal(face_normal)
		st.set_uv(Vector2(u1, v0))
		st.add_vertex(bot_c)

		st.set_normal(face_normal)
		st.set_uv(Vector2(u0, v1))
		st.add_vertex(top_a)
		st.set_normal(face_normal)
		st.set_uv(Vector2(u1, v1))
		st.add_vertex(top_c)
		st.set_normal(face_normal)
		st.set_uv(Vector2(u1, v0))
		st.add_vertex(bot_c)
		run_len += seg_len
	st.generate_normals(false)
	st.commit(mesh)
	return mesh


func _build_cliff_face_material(b: BoundaryData) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = false
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.albedo_color = Color(0.88, 0.87, 0.83, 1.0)
	mat.normal_enabled = true
	mat.normal_scale = 0.55
	mat.ao_enabled = true
	mat.ao_light_affect = 0.65
	mat.clearcoat_enabled = false
	var texture_path: String = _resolve_cliff_texture_id(b.wall_texture_id)
	if ResourceLoader.exists(texture_path):
		var texture_res: Resource = load(texture_path)
		if texture_res is Texture2D:
			mat.albedo_texture = texture_res as Texture2D
			mat.uv1_scale = Vector3(1.0, 1.0, 1.0)
	return mat


func _build_cliff_contour_mesh(b: BoundaryData) -> MeshInstance3D:
	if b.points.size() < 2 or b.raise_height <= 0.2:
		return null
	var contour_mesh := ImmediateMesh.new()
	contour_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var levels: int = clampi(int(floor(b.raise_height / 1.2)), 2, 7)
	var side_sign: float = 1.0 if b.raise_side >= 0 else -1.0
	for i in range(b.points.size() - 1):
		var a: Vector3 = b.points[i]
		var c: Vector3 = b.points[i + 1]
		var seg: Vector3 = c - a
		seg.y = 0.0
		if seg.length() < 0.05:
			continue
		var dir: Vector3 = seg.normalized()
		var nrm: Vector3 = Vector3(-dir.z, 0.0, dir.x) * side_sign
		for l in range(1, levels + 1):
			var h_t: float = float(l) / float(levels + 1)
			var line_a: Vector3 = Vector3(a.x, _sample_height(a.x, a.z) + b.raise_height * h_t, a.z) - nrm * 0.05
			var line_c: Vector3 = Vector3(c.x, _sample_height(c.x, c.z) + b.raise_height * h_t, c.z) - nrm * 0.05
			contour_mesh.surface_set_color(Color(0.08, 0.08, 0.08, 0.22 + (0.09 * h_t)))
			contour_mesh.surface_add_vertex(line_a)
			contour_mesh.surface_add_vertex(line_c)
	contour_mesh.surface_end()
	var inst := MeshInstance3D.new()
	inst.name = "CliffContours_%d" % b.id
	inst.mesh = contour_mesh
	inst.material_override = _mat_contour
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


func _try_place_cave_entrance(b: BoundaryData, click_pos: Vector3) -> void:
	if b == null or b.points.size() < 2:
		return
	var pick: Dictionary = _nearest_boundary_edge_point(b, click_pos)
	if pick.is_empty():
		return
	var edge_idx: int = int(pick.get("edge_index", -1))
	var edge_t: float = float(pick.get("edge_t", 0.0))
	if edge_idx < 0:
		return
	_push_undo_snapshot()
	var cave_pos: Vector3 = pick.get("point", click_pos)
	var cave_normal: Vector3 = pick.get("normal", Vector3.FORWARD)
	_carve_cave_entrance(cave_pos, cave_normal)
	var marker_id: String = "cave_%d_%d" % [b.id, b.cave_entrances.size() + 1]
	b.cave_entrances.append({
		"edge_index": edge_idx,
		"edge_t": edge_t,
		"position": [cave_pos.x, cave_pos.y, cave_pos.z],
		"normal": [cave_normal.x, cave_normal.y, cave_normal.z],
		"marker_id": marker_id,
	})
	_rebuild_cave_entrances_visuals(b)
	boundary_selected.emit(b)  # refresh inspector to show new cave in list


func _carve_cave_entrance(cave_pos: Vector3, cave_normal: Vector3) -> void:
	if _terrain_node == null or not _terrain_node.has_method("apply_brush"):
		return
	for depth_step in range(3):
		var t: float = float(depth_step) / 2.0
		var center: Vector3 = cave_pos - cave_normal * (t * CAVE_DEPTH)
		center.y = _sample_height(center.x, center.z) + (CAVE_HEIGHT * 0.15)
		_terrain_node.call("apply_brush", "lower", center, CAVE_RADIUS * lerpf(1.0, 0.7, t), 0.92, center.y - CAVE_HEIGHT, false, 0.3, 0.2, "sharp", 0, true)
		_terrain_node.call("apply_brush", "smooth", center, CAVE_RADIUS * 1.1, 0.28, center.y, false, 0.3, 0.45, "smooth", 0, true)
	if _terrain_node.has_method("flush_deferred_rebuild"):
		_terrain_node.call("flush_deferred_rebuild")
	elif _terrain_node.has_method("rebuild_mesh"):
		_terrain_node.call("rebuild_mesh")


func _rebuild_cave_entrances_visuals(b: BoundaryData) -> void:
	if b == null:
		return
	_clear_cave_nodes(b.id)
	if b.cave_entrances.is_empty():
		return
	var nodes: Array = []
	for entry_var in b.cave_entrances:
		if not (entry_var is Dictionary):
			continue
		var entry: Dictionary = entry_var as Dictionary
		var cave_state: Dictionary = _compute_cave_entry_transform(b, entry)
		if cave_state.is_empty():
			continue
		var pos: Vector3 = cave_state.get("position", Vector3.ZERO)
		var nrm: Vector3 = cave_state.get("normal", Vector3.FORWARD)
		var mouth := _build_cave_mouth_visual(pos, nrm)
		if mouth != null:
			add_child(mouth)
			nodes.append(mouth)
		var marker := Marker3D.new()
		marker.name = String(entry.get("marker_id", "CaveMarker"))
		marker.global_position = pos - nrm * (CAVE_DEPTH * 0.5)
		marker.add_to_group("cave_transition_marker")
		marker.set_meta("boundary_id", b.id)
		marker.set_meta("marker_type", "cave_entrance")
		add_child(marker)
		nodes.append(marker)
	if not nodes.is_empty():
		_cave_nodes_by_boundary[b.id] = nodes


func _compute_cave_entry_transform(b: BoundaryData, entry: Dictionary) -> Dictionary:
	if b == null or entry.is_empty():
		return {}
	var edge_index: int = int(entry.get("edge_index", -1))
	var edge_t: float = clampf(float(entry.get("edge_t", 0.0)), 0.0, 1.0)
	if edge_index >= 0 and edge_index < b.points.size() - 1:
		var a: Vector3 = b.points[edge_index]
		var c: Vector3 = b.points[edge_index + 1]
		var pos: Vector3 = a.lerp(c, edge_t)
		pos.y = _sample_height(pos.x, pos.z)
		var seg: Vector3 = c - a
		seg.y = 0.0
		if seg.length_squared() > 0.0001:
			var dir: Vector3 = seg.normalized()
			var nrm: Vector3 = Vector3(-dir.z, 0.0, dir.x) * (1.0 if b.raise_side >= 0 else -1.0)
			return {"position": pos, "normal": nrm.normalized()}
	var pos_arr: Array = entry.get("position", []) as Array
	var nrm_arr: Array = entry.get("normal", []) as Array
	if pos_arr.size() < 3 or nrm_arr.size() < 3:
		return {}
	return {
		"position": Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])),
		"normal": Vector3(float(nrm_arr[0]), float(nrm_arr[1]), float(nrm_arr[2])).normalized(),
	}


func _build_cave_mouth_visual(pos: Vector3, normal: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "CaveMouth"
	root.global_position = pos
	var forward: Vector3 = -normal.normalized()
	var face_basis := Basis.looking_at(forward, Vector3.UP)
	root.global_basis = face_basis

	var arch_mesh := CylinderMesh.new()
	arch_mesh.top_radius = CAVE_RADIUS
	arch_mesh.bottom_radius = CAVE_RADIUS * 0.96
	arch_mesh.height = 0.55
	arch_mesh.radial_segments = 20
	var arch_inst := MeshInstance3D.new()
	arch_inst.mesh = arch_mesh
	arch_inst.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	arch_inst.position = Vector3(0.0, CAVE_HEIGHT * 0.42, -0.18)
	var arch_mat := StandardMaterial3D.new()
	arch_mat.albedo_color = Color(0.19, 0.18, 0.17, 1.0)
	arch_mat.roughness = 1.0
	arch_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arch_inst.material_override = arch_mat
	root.add_child(arch_inst)

	var shadow_disc := MeshInstance3D.new()
	var disc := QuadMesh.new()
	disc.size = Vector2(CAVE_RADIUS * 1.55, CAVE_HEIGHT * 1.25)
	shadow_disc.mesh = disc
	shadow_disc.position = Vector3(0.0, CAVE_HEIGHT * 0.45, -0.42)
	shadow_disc.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0.02, 0.02, 0.03, 0.62)
	shadow_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow_disc.material_override = shadow_mat
	root.add_child(shadow_disc)
	return root


func _nearest_boundary_edge_point(b: BoundaryData, sample: Vector3) -> Dictionary:
	var best_dist: float = INF
	var best: Dictionary = {}
	for i in range(b.points.size() - 1):
		var a: Vector3 = b.points[i]
		var c: Vector3 = b.points[i + 1]
		var seg: Vector3 = c - a
		seg.y = 0.0
		var seg_len2: float = seg.length_squared()
		if seg_len2 < 0.01:
			continue
		var sample_flat := Vector3(sample.x, 0.0, sample.z)
		var a_flat := Vector3(a.x, 0.0, a.z)
		var t: float = clampf((sample_flat - a_flat).dot(seg) / seg_len2, 0.0, 1.0)
		var point: Vector3 = a.lerp(c, t)
		point.y = _sample_height(point.x, point.z)
		var dist: float = Vector2(point.x - sample.x, point.z - sample.z).length()
		if dist < best_dist:
			var dir: Vector3 = seg.normalized()
			var normal: Vector3 = Vector3(-dir.z, 0.0, dir.x) * (1.0 if b.raise_side >= 0 else -1.0)
			best_dist = dist
			best = {
				"edge_index": i,
				"edge_t": t,
				"point": point,
				"normal": normal.normalized(),
			}
	return best


func _clear_cave_nodes(boundary_id: int) -> void:
	if not _cave_nodes_by_boundary.has(boundary_id):
		return
	var nodes: Array = _cave_nodes_by_boundary[boundary_id] as Array
	for n in nodes:
		if n is Node and is_instance_valid(n as Node):
			(n as Node).queue_free()
	_cave_nodes_by_boundary.erase(boundary_id)


func _push_undo_snapshot() -> void:
	var snapshot: Array = []
	for b in _boundaries:
		snapshot.append((b as BoundaryData).serialize())
	_undo_stack.append(snapshot)
	if _undo_stack.size() > UNDO_MAX_DEPTH:
		_undo_stack.pop_front()


func _polyline_length(pts: Array) -> float:
	var total: float = 0.0
	for i in range(pts.size() - 1):
		total += (pts[i + 1] as Vector3).distance_to(pts[i] as Vector3)
	return total

## Removes only the guide-line overlay for id, leaving cliff/contour meshes intact.
func _remove_guide_visual(id: int) -> void:
	if _boundary_mesh_insts.has(id):
		var node: Node = _boundary_mesh_insts[id] as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
		_boundary_mesh_insts.erase(id)

## Removes all visuals for id: guide line, cliff mesh, contour mesh, caves.
func _remove_boundary_visual(id: int) -> void:
	if _boundary_mesh_insts.has(id):
		var node: Node = _boundary_mesh_insts[id] as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
		_boundary_mesh_insts.erase(id)
	if _applied_cliff_mesh_insts.has(id):
		var cliff_node: Node = _applied_cliff_mesh_insts[id] as Node
		if cliff_node != null and is_instance_valid(cliff_node):
			cliff_node.queue_free()
		_applied_cliff_mesh_insts.erase(id)
	if _applied_contour_mesh_insts.has(id):
		var contour_node: Node = _applied_contour_mesh_insts[id] as Node
		if contour_node != null and is_instance_valid(contour_node):
			contour_node.queue_free()
		_applied_contour_mesh_insts.erase(id)
	_clear_cave_nodes(id)

func _clear_all_visuals() -> void:
	for id in _boundary_mesh_insts.keys():
		var node: Node = _boundary_mesh_insts[id] as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	_boundary_mesh_insts.clear()
	for id in _applied_cliff_mesh_insts.keys():
		var cliff_node: Node = _applied_cliff_mesh_insts[id] as Node
		if cliff_node != null and is_instance_valid(cliff_node):
			cliff_node.queue_free()
	_applied_cliff_mesh_insts.clear()
	for id in _applied_contour_mesh_insts.keys():
		var contour_node: Node = _applied_contour_mesh_insts[id] as Node
		if contour_node != null and is_instance_valid(contour_node):
			contour_node.queue_free()
	_applied_contour_mesh_insts.clear()
	for id in _cave_nodes_by_boundary.keys():
		_clear_cave_nodes(int(id))
	_cave_nodes_by_boundary.clear()
	_clear_handles()

# ---------- handles for selected boundary ---------------------------------

func _rebuild_handles() -> void:
	_clear_handles()
	var b: BoundaryData = get_selected()
	if b == null:
		return
	for i in range(b.points.size()):
		var handle: MeshInstance3D = _make_handle_sphere(b.points[i] as Vector3, HANDLE_COLOR)
		handle.name = "Handle_%d" % i
		handle.set_meta("point_index", i)
		add_child(handle)
		_handle_nodes.append(handle)

func _clear_handles() -> void:
	for n in _handle_nodes:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	_handle_nodes.clear()
	_hover_handle_index = -1

func _pick_handle(mouse_screen_pos: Vector2) -> int:
	if _camera == null or _handle_nodes.is_empty():
		return -1
	var best_dist: float = 20.0
	var best_idx: int = -1
	for i in range(_handle_nodes.size()):
		var node: MeshInstance3D = _handle_nodes[i] as MeshInstance3D
		if node == null or not is_instance_valid(node):
			continue
		if _camera.is_position_behind(node.global_position):
			continue
		var sp: Vector2 = _camera.unproject_position(node.global_position)
		var d: float = mouse_screen_pos.distance_to(sp)
		if d < best_dist:
			best_dist = d
			best_idx = i
	return best_idx

func _update_hover_handle(mouse_screen_pos: Vector2) -> void:
	var idx: int = _pick_handle(mouse_screen_pos)
	if idx == _hover_handle_index:
		return
	# Reset old
	if _hover_handle_index >= 0 and _hover_handle_index < _handle_nodes.size():
		_set_handle_color(_handle_nodes[_hover_handle_index] as MeshInstance3D, HANDLE_COLOR)
	_hover_handle_index = idx
	if idx >= 0 and idx < _handle_nodes.size():
		_set_handle_color(_handle_nodes[idx] as MeshInstance3D, HANDLE_HOVER_COLOR)

func _set_handle_color(node: MeshInstance3D, color: Color) -> void:
	if node == null:
		return
	if node.material_override is StandardMaterial3D:
		(node.material_override as StandardMaterial3D).albedo_color = color
		(node.material_override as StandardMaterial3D).emission = color * 0.6

# ==========================================================================
# HELPERS
# ==========================================================================

func _find_boundary(id: int) -> BoundaryData:
	for b_var in _boundaries:
		var b: BoundaryData = b_var as BoundaryData
		if b != null and b.id == id:
			return b
	return null

func _sample_height(x: float, z: float) -> float:
	if _terrain_node != null and _terrain_node.has_method("sample_height"):
		return float(_terrain_node.call("sample_height", x, z))
	return 0.0

func _raycast_terrain(mouse_screen_pos: Vector2) -> Variant:
	if _camera == null:
		return null
	if _terrain_node != null and _terrain_node.has_method("get_intersection"):
		var ray_origin: Vector3 = _camera.project_ray_origin(mouse_screen_pos)
		var ray_dir: Vector3 = _camera.project_ray_normal(mouse_screen_pos)
		var hit: Variant = _terrain_node.call("get_intersection", ray_origin, ray_dir)
		if hit is Vector3:
			return hit
	# Fallback: project onto Y=0 plane
	var from: Vector3 = _camera.project_ray_origin(mouse_screen_pos)
	var dir: Vector3 = _camera.project_ray_normal(mouse_screen_pos)
	if absf(dir.y) < 0.001:
		return null
	var t: float = -from.y / dir.y
	if t < 0.0:
		return null
	return from + dir * t

func _build_materials() -> void:
	_mat_preview = _make_emissive_mat(PREVIEW_LINE_COLOR, true)
	_mat_closed  = _make_emissive_mat(CLOSED_LINE_COLOR,  true)
	_mat_selected = _make_emissive_mat(SELECTED_LINE_COLOR, true)
	_mat_ghost   = _make_emissive_mat(GHOST_LINE_COLOR,   true)
	_mat_contour = _make_emissive_mat(Color(0.06, 0.06, 0.07, 0.36), false)
	_mat_contour.no_depth_test = false
	_mat_contour.emission_energy_multiplier = 0.9

func _make_emissive_mat(color: Color, no_depth_test: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.75
	mat.emission_energy_multiplier = 1.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if no_depth_test:
		mat.no_depth_test = true
	return mat

func _make_mesh_inst(mesh: Mesh, mat: StandardMaterial3D) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.mesh = mesh
	inst.material_override = mat
	return inst

func _make_handle_sphere(pos: Vector3, color: Color) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = PREVIEW_POINT_RADIUS
	sphere.height = PREVIEW_POINT_RADIUS * 2.0
	var inst: MeshInstance3D = _make_mesh_inst(sphere, null)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.65
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	inst.material_override = mat
	inst.global_position = pos
	return inst
