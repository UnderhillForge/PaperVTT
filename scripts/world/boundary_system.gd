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
const PREVIEW_POINT_RADIUS: float    = 0.28
const PREVIEW_LINE_THICKNESS: float  = 0.08  # half-width for line quads
const CLOSED_LINE_COLOR: Color       = Color(0.18, 0.92, 0.68, 0.92)
const PREVIEW_LINE_COLOR: Color      = Color(0.55, 0.95, 1.00, 0.72)
const GHOST_LINE_COLOR: Color        = Color(0.80, 0.90, 1.00, 0.42)
const SELECTED_LINE_COLOR: Color     = Color(1.00, 0.85, 0.22, 0.96)
const HANDLE_COLOR: Color            = Color(0.18, 0.92, 0.68, 0.9)
const SELECTED_HANDLE_COLOR: Color   = Color(1.00, 0.85, 0.22, 0.95)
const HANDLE_HOVER_COLOR: Color      = Color(1.00, 1.00, 1.00, 1.0)
const LINE_LIFT: float               = 0.22   # raise above terrain so lines are visible
const EXTRUDE_BRUSH_STEPS_PER_M: float = 0.55  # brush passes per metre along boundary
const INNER_RAISE_BRUSH_STEPS: int   = 5
const INNER_RAISE_RADIUS_FACTOR: float = 0.65  # relative to raise_height

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

## Currently selected boundary
var _selected_id: int = -1

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
var _handle_nodes: Array = []                   # handle spheres for selected boundary

# ---------- material cache -----------------------------------------------
var _mat_preview: StandardMaterial3D = null
var _mat_closed: StandardMaterial3D = null
var _mat_selected: StandardMaterial3D = null
var _mat_ghost: StandardMaterial3D = null

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
	_deselect()
	_refresh_preview_mesh()

## Cancel in-progress drawing without saving (discard current points).
func cancel_drawing() -> void:
	if _state == State.DRAWING:
		_draw_points.clear()
		_state = State.IDLE
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
	_apply_in_progress = true
	call_deferred("_apply_selected_deferred", b.id)

## Delete the currently selected boundary.
func delete_selected() -> void:
	if _selected_id < 0:
		return
	_remove_boundary_visual(_selected_id)
	_boundaries = _boundaries.filter(func(x: BoundaryData) -> bool: return x.id != _selected_id)
	_selected_id = -1
	_clear_handles()
	_state = State.IDLE
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
		if not b.applied:
			_rebuild_boundary_visual(b.id)

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
		_state = State.IDLE
		_refresh_preview_mesh()
		return true

	if mb.button_index == MOUSE_BUTTON_LEFT:
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
		_state = State.IDLE
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


func _apply_selected_deferred(boundary_id: int) -> void:
	await get_tree().create_timer(0.05).timeout
	var b: BoundaryData = _find_boundary(boundary_id)
	if b == null or _terrain_node == null:
		_apply_in_progress = false
		print("[Boundary] apply aborted id=%d" % boundary_id)
		return
	print("[Boundary] extrusion begin id=%d points=%d" % [boundary_id, b.points.size()])
	_extrude_boundary(b)
	b.applied = true
	_remove_boundary_visual(b.id)
	if _selected_id == b.id:
		_deselect()
		_state = State.IDLE
		boundary_deselected.emit()
	print("[Boundary] extrusion end id=%d" % boundary_id)
	_apply_in_progress = false

# ==========================================================================
# SELECTION / HANDLE DRAG
# ==========================================================================

func _handle_select_input(event: InputEvent, mouse_screen_pos: Vector2) -> bool:
	var b: BoundaryData = get_selected()
	if b == null:
		return false

	if event is InputEventMouseMotion:
		# Drag an existing point
		if _drag_point_index >= 0 and (event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT:
			var hit: Variant = _raycast_terrain(mouse_screen_pos)
			if hit is Vector3:
				var world_pos: Vector3 = hit as Vector3
				world_pos.y = _sample_height(world_pos.x, world_pos.z) + LINE_LIFT
				b.points[_drag_point_index] = world_pos
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
					_state = State.IDLE
					boundary_deselected.emit()
					return true
		else:
			_drag_point_index = -1
		return true

	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_deselect()
		_state = State.IDLE
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
		if b == null or b.points.size() < 2 or b.applied:
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
	_clear_handles()
	if prev_id >= 0:
		_rebuild_boundary_visual(prev_id)

# ==========================================================================
# TERRAIN EXTRUSION
# ==========================================================================

func _extrude_boundary(b: BoundaryData) -> void:
	if _terrain_node == null or b.points.size() < 2:
		return
	if not _terrain_node.has_method("apply_brush"):
		return

	var pts: Array = b.points
	var count: int = pts.size()
	var edge_count: int = count - 1

	# --- 2. CLIFF WALL along each edge ------------------------------------
	var wall_brush: float = b.wall_brush_width
	var angle_rad: float = deg_to_rad(b.steepness_deg)
	var inner_offset: float = wall_brush * sin(angle_rad) * 0.65
	var height_delta: float = b.raise_height if b.raise_height > 0.1 else 3.0
	var raise_per_pass: float = height_delta * 0.45
	var side_sign: float = 1.0 if b.raise_side >= 0 else -1.0

	for edge_idx in range(edge_count):
		var pa: Vector3 = pts[edge_idx % count]
		var pb: Vector3 = pts[(edge_idx + 1) % count]
		var edge: Vector3 = pb - pa
		edge.y = 0.0
		var edge_len: float = edge.length()
		if edge_len < 0.05:
			continue

		var edge_dir: Vector3 = edge / edge_len
		# Line-left normal, then flipped by side selector.
		var outward_normal: Vector3 = Vector3(-edge_dir.z, 0.0, edge_dir.x) * side_sign

		# Sample pass positions along edge
		var step_dist: float = 1.0 / maxf(0.01, EXTRUDE_BRUSH_STEPS_PER_M)
		var steps: int = maxi(1, int(ceil(edge_len / step_dist)))
		for s in range(steps + 1):
			var t: float = float(s) / float(steps)
			var base_pos: Vector3 = pa.lerp(pb, t)
			base_pos.y = _sample_height(base_pos.x, base_pos.z)

			# Inner-edge steep raise
			var inner_pos: Vector3 = base_pos - outward_normal * inner_offset
			inner_pos.y = _sample_height(inner_pos.x, inner_pos.z)
			_terrain_node.call("apply_brush",
				"raise", inner_pos,
				wall_brush * 0.85, raise_per_pass,
				inner_pos.y + height_delta,
				false, 0.3, 0.38, "sharp")

			# Outer-edge flatten/slope
			var outer_pos: Vector3 = base_pos + outward_normal * (inner_offset * 0.4)
			outer_pos.y = _sample_height(outer_pos.x, outer_pos.z)
			_terrain_node.call("apply_brush",
				"flatten", outer_pos,
				wall_brush * 0.60, 0.72,
				outer_pos.y,
				false, 0.3, 0.55, "smooth")

	# --- 3. Rebuild terrain mesh ------------------------------------------
	if _terrain_node.has_method("rebuild_mesh"):
		_terrain_node.call("rebuild_mesh")


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
	# Draw placed segments
	for i in range(_draw_points.size() - 1):
		var pa: Vector3 = _draw_points[i] as Vector3
		var pb: Vector3 = _draw_points[i + 1] as Vector3
		im.surface_set_color(PREVIEW_LINE_COLOR)
		im.surface_add_vertex(pa)
		im.surface_set_color(PREVIEW_LINE_COLOR)
		im.surface_add_vertex(pb)
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

	# Draw point dots (small cross)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for p_var in _draw_points:
		var p: Vector3 = p_var as Vector3
		im.surface_set_color(PREVIEW_LINE_COLOR)
		im.surface_add_vertex(p + Vector3(-0.3, 0.0, 0.0))
		im.surface_add_vertex(p + Vector3( 0.3, 0.0, 0.0))
		im.surface_add_vertex(p + Vector3(0.0, 0.0, -0.3))
		im.surface_add_vertex(p + Vector3(0.0, 0.0,  0.3))
	im.surface_end()

func _rebuild_boundary_visual(id: int) -> void:
	_remove_boundary_visual(id)
	var b: BoundaryData = _find_boundary(id)
	if b == null or b.points.size() < 2:
		return
	if b.applied:
		return

	var is_sel: bool = (id == _selected_id)
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

func _remove_boundary_visual(id: int) -> void:
	if _boundary_mesh_insts.has(id):
		var node: Node = _boundary_mesh_insts[id] as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
		_boundary_mesh_insts.erase(id)

func _clear_all_visuals() -> void:
	for id in _boundary_mesh_insts.keys():
		var node: Node = _boundary_mesh_insts[id] as Node
		if node != null and is_instance_valid(node):
			node.queue_free()
	_boundary_mesh_insts.clear()
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
