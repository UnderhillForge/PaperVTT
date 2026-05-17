class_name WallTool
extends RefCounted

const MENU_ADD_DOOR: int = 100
const MENU_ADD_WINDOW: int = 101
const MENU_REMOVE_OPENING: int = 102

var _host: Node3D = null
var _wall_system: Variant = null
var _mouse_world_provider: Callable = Callable()
var _mouse_ray_provider: Callable = Callable()
var _terrain_height_provider: Callable = Callable()
var _status_sink: Callable = Callable()

var _is_active: bool = false
var _is_drawing: bool = false
var _is_edit_mode: bool = false
var _current_start: Vector3 = Vector3.ZERO
var _last_mouse_world: Vector3 = Vector3.ZERO
var _last_mouse_screen: Vector2 = Vector2.ZERO

var _snap_grid: float = 0.5
var _segment_height: float = 3.4
var _segment_type: String = "stone"
var _rect_mode_toggle: bool = false
var _rect_add_foundation: bool = true
var _match_connected_heights: bool = true
var _opening_height_snap_enabled: bool = true
var _ctrl_rect_held: bool = false
var _is_rect_dragging: bool = false
var _square_drag_lock: bool = false

var _preview_root: Node3D = null
var _edit_root: Node3D = null
var _context_menu: PopupMenu = null
var _selected_segment_idx: int = -1
var _selected_opening_idx: int = -1
var _drag_mode: String = ""
var _context_segment_idx: int = -1
var _context_opening_idx: int = -1
var _context_ratio: float = 0.5
var _undo_history: Array[Dictionary] = []
var _wall_segment_class: Script = null

func activate(
	host: Node3D,
	mouse_world_provider: Callable,
	mouse_ray_provider: Callable,
	terrain_height_provider: Callable,
	status_sink: Callable
) -> void:
	_host = host
	_mouse_world_provider = mouse_world_provider
	_mouse_ray_provider = mouse_ray_provider
	_terrain_height_provider = terrain_height_provider
	_status_sink = status_sink
	_ensure_wall_system()
	_ensure_preview_nodes()
	_ensure_context_menu()
	_is_active = true
	if _wall_system != null and _wall_system.has_method("auto_register_prefabs"):
		_wall_system.call("auto_register_prefabs")
	_emit_status("Smart Wall: LMB click chain (A->B->C), Ctrl rectangle drag, RMB/Esc end chain, Shift edit")

func deactivate() -> void:
	_is_active = false
	_is_drawing = false
	_is_rect_dragging = false
	_square_drag_lock = false
	_ctrl_rect_held = false
	_is_edit_mode = false
	_drag_mode = ""
	_selected_segment_idx = -1
	_selected_opening_idx = -1
	_clear_all_temporary_nodes()

func set_snap_grid(step_m: float) -> void:
	_snap_grid = maxf(0.1, step_m)

func set_segment_height(height_m: float) -> void:
	_segment_height = maxf(0.2, height_m)
	if _wall_system != null:
		_wall_system.default_wall_height = _segment_height
		if _is_edit_mode and _selected_segment_idx >= 0 and _wall_system.has_method("set_segment_height"):
			if _match_connected_heights and _wall_system.has_method("set_component_height_from_segment"):
				_wall_system.call("set_component_height_from_segment", _selected_segment_idx, _segment_height)
				_emit_status("Smart Wall: applied %.1fm to connected structure" % _segment_height)
			else:
				_wall_system.call("set_segment_height", _selected_segment_idx, _segment_height)
				_emit_status("Smart Wall: applied %.1fm to selected segment" % _segment_height)
			_refresh_edit_handles()

func set_segment_type(wall_type: String) -> void:
	var wt: String = wall_type.strip_edges().to_lower()
	if wt == "":
		return
	_segment_type = wt

func set_rect_mode_enabled(enabled: bool) -> void:
	_rect_mode_toggle = enabled

func set_rect_foundation_enabled(enabled: bool) -> void:
	_rect_add_foundation = enabled

func set_match_connected_heights_enabled(enabled: bool) -> void:
	_match_connected_heights = enabled

func set_opening_height_snap_enabled(enabled: bool) -> void:
	_opening_height_snap_enabled = enabled

func set_jitter_enabled(enabled: bool) -> void:
	if _wall_system != null:
		_wall_system.set("enable_hand_drawn_jitter", enabled)

func get_segment_height() -> float:
	return _segment_height

func handle_input_event(event: InputEvent) -> bool:
	if not _is_active:
		return false

	if event is InputEventKey:
		var kk := event as InputEventKey
		if kk.keycode == KEY_CTRL:
			_ctrl_rect_held = kk.pressed
			if _is_rect_dragging:
				_refresh_preview_from_mouse()
			return false
		if kk.keycode == KEY_SHIFT:
			if _is_rect_dragging and _is_rectangle_mode_active():
				_square_drag_lock = kk.pressed
				_refresh_preview_from_mouse()
				return true
			if _is_drawing or _is_rect_dragging:
				return false
			_is_edit_mode = kk.pressed
			_refresh_edit_handles()
			if _is_edit_mode:
				_emit_status("Smart Wall Edit: LMB select/drag handles, RMB wall for door/window")
			return false

	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_last_mouse_screen = mm.position
		_refresh_preview_from_mouse()
		if _is_edit_mode:
			if _drag_mode != "":
				_handle_drag_update(mm)
				return true
			return false
		return _is_drawing or _is_rect_dragging

	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_Z and ke.ctrl_pressed:
			return undo_last_segment()
		if ke.pressed and not ke.echo and ke.keycode == KEY_DELETE and _selected_segment_idx >= 0:
			if _wall_system != null and _wall_system.has_method("remove_segment"):
				_push_undo_state()
				if bool(_wall_system.call("remove_segment", _selected_segment_idx)):
					_selected_segment_idx = -1
					_selected_opening_idx = -1
					_refresh_edit_handles()
					_emit_status("Smart Wall: deleted selected segment")
					return true

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_ctrl_rect_held = mb.ctrl_pressed
		_last_mouse_screen = mb.position
		var mouse_world: Variant = _get_mouse_world()
		if mouse_world is Vector3:
			_last_mouse_world = mouse_world as Vector3

		if _is_edit_mode:
			return _handle_edit_mouse_button(mb)

		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if not _is_drawing and not _is_rect_dragging and not _raycast_wall().is_empty():
				_open_opening_context_menu()
				return true
			if _is_drawing or _is_rect_dragging:
				return cancel_chain()
			return false

		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false

		if _is_rectangle_mode_active():
			if mb.pressed:
				var rect_world: Variant = _get_mouse_world()
				if rect_world == null:
					return false
				_start_rectangle_drag(rect_world as Vector3)
				return true
			if _is_rect_dragging:
				var release_world: Variant = _get_mouse_world()
				if release_world != null:
					_finish_rectangle_drag(release_world as Vector3)
				else:
					_is_rect_dragging = false
					_square_drag_lock = false
				return true
			return false

		if not mb.pressed:
			return false

		var world: Variant = _get_mouse_world()
		if world == null:
			return false

		if not _is_drawing:
			_start_drawing(world as Vector3)
		else:
			_finish_segment(world as Vector3)
		return true

	return false

func update_preview() -> void:
	if not _is_active:
		return
	_refresh_preview_from_mouse()
	if not _is_drawing and not _is_rect_dragging and not _is_edit_mode:
		_clear_all_temporary_nodes()

func cancel_chain() -> bool:
	if not _is_drawing and not _is_rect_dragging:
		return false
	_is_drawing = false
	_is_rect_dragging = false
	_square_drag_lock = false
	_clear_all_temporary_nodes()
	_emit_status("Smart Wall: chain ended")
	return true

func _clear_all_temporary_nodes() -> void:
	if _preview_root != null:
		_preview_root.visible = false
		for child in _preview_root.get_children():
			child.queue_free()
	if _edit_root != null:
		for child in _edit_root.get_children():
			child.queue_free()

func undo_last_segment() -> bool:
	if _wall_system == null:
		return false
	if not _undo_history.is_empty() and _wall_system.has_method("load_data"):
		var snapshot: Dictionary = _undo_history.pop_back()
		_wall_system.call("load_data", snapshot)
		_selected_segment_idx = -1
		_selected_opening_idx = -1
		_drag_mode = ""
		_refresh_preview_from_mouse()
		_refresh_edit_handles()
		_emit_status("Smart Wall: undo")
		return true
	if not _wall_system.has_method("undo_last_segment"):
		return false
	var ok: bool = bool(_wall_system.call("undo_last_segment"))
	if not ok:
		_emit_status("Smart Wall: nothing to undo")
		return false
	if _wall_system.segments.is_empty():
		_is_drawing = false
	else:
		var last: Variant = _wall_system.segments[_wall_system.segments.size() - 1]
		if last != null and last.has_method("end"):
			_current_start = last.end
		_is_drawing = true
	_refresh_preview_from_mouse()
	_refresh_edit_handles()
	_emit_status("Smart Wall: removed last segment")
	return true

func get_wall_system() -> Variant:
	return _wall_system

func _create_wall_segment() -> Variant:
	if _wall_segment_class == null:
		_wall_segment_class = load("res://map/walls/wall_segment.gd")
	if _wall_segment_class == null:
		return null
	return _wall_segment_class.new()

func _ensure_wall_system() -> void:
	if _host == null:
		return
	var existing := _host.get_node_or_null("WallSystem")
	if existing != null:
		_wall_system = existing
		return
	var wall_system_class: Script = load("res://map/walls/wall_system.gd")
	if wall_system_class == null:
		return
	_wall_system = wall_system_class.new()
	_wall_system.name = "WallSystem"
	_host.add_child(_wall_system)

func _ensure_preview_nodes() -> void:
	if _host == null:
		return
	if _preview_root == null:
		_preview_root = Node3D.new()
		_preview_root.name = "WallPreview"
		_host.add_child(_preview_root)
	if _edit_root == null:
		_edit_root = Node3D.new()
		_edit_root.name = "WallEditHandles"
		_host.add_child(_edit_root)
	_preview_root.visible = false

func _ensure_context_menu() -> void:
	if _host == null or _context_menu != null:
		return
	_context_menu = PopupMenu.new()
	_context_menu.name = "WallContextMenu"
	_context_menu.add_item("Add Door", MENU_ADD_DOOR)
	_context_menu.add_item("Add Window", MENU_ADD_WINDOW)
	_context_menu.add_separator()
	_context_menu.add_item("Remove Opening", MENU_REMOVE_OPENING)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_host.add_child(_context_menu)

func _start_drawing(pos: Vector3) -> void:
	_is_drawing = true
	_current_start = _snap(pos)
	_emit_status("Smart Wall: choose segment end")

func _start_rectangle_drag(pos: Vector3) -> void:
	_is_drawing = false
	_is_rect_dragging = true
	_current_start = _snap(pos)
	_square_drag_lock = false
	_emit_status("Smart Wall: rectangle mode drag (Shift = square)")

func _finish_segment(end_pos: Vector3) -> void:
	if _wall_system == null:
		return
	var snapped_end: Vector3 = _snap(end_pos)
	if _current_start.distance_to(snapped_end) < 0.2:
		_emit_status("Smart Wall: segment too short")
		return

	var seg: Variant = _create_wall_segment()
	if seg == null:
		_emit_status("Smart Wall: failed to create segment")
		return
	seg.start = _current_start
	seg.end = snapped_end
	var matched: Dictionary = _resolve_matched_height(_current_start, snapped_end)
	seg.height = float(matched.get("height", _segment_height))
	seg.wall_type = _segment_type
	_push_undo_state()
	_wall_system.segments.append(seg)
	_wall_system.rebuild_all()

	_current_start = snapped_end
	_is_drawing = true
	_selected_segment_idx = _wall_system.segments.size() - 1
	_selected_opening_idx = -1
	_refresh_edit_handles()
	if bool(matched.get("matched", false)):
		_emit_status("Smart Wall: auto-matched connected height %.1fm" % seg.height)
	else:
		_emit_status("Smart Wall: segment added, click to continue chain")
	_refresh_preview_from_mouse()
	if not _is_edit_mode:
		_clear_all_temporary_nodes()

func _finish_rectangle_drag(end_pos: Vector3) -> void:
	if _wall_system == null:
		return
	var snapped_end: Vector3 = _snap(end_pos)
	var corners: Array[Vector3] = _rectangle_corners(_current_start, snapped_end, _square_drag_lock)
	print("[WallTool] Rectangle corners: %s" % [corners])
	var resolved_h: float = _segment_height
	var matched: bool = false
	if _match_connected_heights and corners.size() >= 2:
		var h_match: Dictionary = _resolve_matched_height(corners[0], corners[1])
		resolved_h = float(h_match.get("height", _segment_height))
		matched = bool(h_match.get("matched", false))
	var rect_segments: Array = _build_rectangle_segments(_current_start, snapped_end, _square_drag_lock, resolved_h)
	_is_rect_dragging = false
	_square_drag_lock = false
	if rect_segments.is_empty():
		if _preview_root != null:
			_preview_root.visible = false
		_emit_status("Smart Wall: rectangle too small")
		return
	_push_undo_state()
	for seg in rect_segments:
		_wall_system.segments.append(seg)
	if _rect_add_foundation and _wall_system.has_method("add_rect_foundation"):
		# Rectangle walls are flattened to a shared base Y in _build_rectangle_segments.
		# Use that exact base for foundation top to guarantee flush alignment on all sides.
		var foundation_top_y: float = _current_start.y
		if not rect_segments.is_empty() and rect_segments[0] != null:
			foundation_top_y = float(rect_segments[0].start.y)
		elif not corners.is_empty():
			foundation_top_y = float(corners[0].y)
		_wall_system.call("add_rect_foundation", corners, _segment_type, foundation_top_y)
	else:
		_wall_system.rebuild_all()
	_selected_segment_idx = _wall_system.segments.size() - 1
	_selected_opening_idx = -1
	_refresh_edit_handles()
	_refresh_preview_from_mouse()
	if not _is_edit_mode:
		_clear_all_temporary_nodes()
	if matched:
		_emit_status("Smart Wall: auto-matched connected height %.1fm for rectangle" % resolved_h)
	elif _rect_add_foundation:
		_emit_status("Smart Wall: rectangle + foundation created")
	else:
		_emit_status("Smart Wall: rectangle created (%d segments)" % rect_segments.size())

func _is_rectangle_mode_active() -> bool:
	return _rect_mode_toggle or _ctrl_rect_held

func _build_preview_segments(base_segments: Array) -> Array:
	var out: Array = []
	for seg in _wall_system.segments:
		if seg != null:
			out.append(seg)
	for seg in base_segments:
		if seg != null:
			out.append(seg)
	return out

func _rectangle_corners(start_pos: Vector3, end_pos: Vector3, force_square: bool) -> Array[Vector3]:
	var start_snap: Vector3 = _snap(start_pos)
	var end_snap: Vector3 = _snap(end_pos)
	var dx: float = end_snap.x - start_snap.x
	var dz: float = end_snap.z - start_snap.z
	if force_square:
		var side: float = maxf(absf(dx), absf(dz))
		if side > 0.0:
			end_snap.x = start_snap.x + (side if dx >= 0.0 else -side)
			end_snap.z = start_snap.z + (side if dz >= 0.0 else -side)

	var min_x: float = minf(start_snap.x, end_snap.x)
	var max_x: float = maxf(start_snap.x, end_snap.x)
	var min_z: float = minf(start_snap.z, end_snap.z)
	var max_z: float = maxf(start_snap.z, end_snap.z)

	# Use one shared base so all rectangle walls/foundation stay perfectly aligned.
	# Choose the lowest sampled corner to keep walls/foundation flush across the footprint.
	var base_y: float = minf(start_snap.y, end_snap.y)
	if _terrain_height_provider.is_valid():
		for x in [min_x, max_x]:
			for z in [min_z, max_z]:
				var h: Variant = _terrain_height_provider.call(x, z)
				if h is float:
					base_y = minf(base_y, float(h))
				elif h is int:
					base_y = minf(base_y, float(h))

	return [
		Vector3(min_x, base_y, min_z),
		Vector3(max_x, base_y, min_z),
		Vector3(max_x, base_y, max_z),
		Vector3(min_x, base_y, max_z)
	]

func _build_rectangle_segments(start_pos: Vector3, end_pos: Vector3, force_square: bool, forced_height: float = -1.0) -> Array:
	var corners: Array[Vector3] = _rectangle_corners(start_pos, end_pos, force_square)
	var h: float = maxf(0.2, forced_height if forced_height > 0.0 else _segment_height)
	var results: Array = []
	for i in range(corners.size()):
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % corners.size()]
		if a.distance_to(b) < 0.2:
			continue
		var seg: Variant = _create_wall_segment()
		if seg == null:
			continue
		seg.start = a
		seg.end = b
		seg.height = h
		seg.wall_type = _segment_type
		results.append(seg)
	return results

func _refresh_preview_from_mouse() -> void:
	if _preview_root == null:
		return
	if not _is_drawing and not _is_rect_dragging:
		_clear_all_temporary_nodes()
		return
	var world: Variant = _get_mouse_world()
	if world == null:
		_clear_all_temporary_nodes()
		return
	if _wall_system == null or not _wall_system.has_method("build_preview_into"):
		return
	var end: Vector3 = _snap(world as Vector3)
	var local_preview_segments: Array = []
	var feedback: Dictionary = {}

	if _is_rect_dragging and _is_rectangle_mode_active():
		local_preview_segments = _build_rectangle_segments(_current_start, end, _square_drag_lock)
		if local_preview_segments.is_empty():
			_preview_root.visible = true
			for child in _preview_root.get_children():
				child.queue_free()
			_add_chain_anchor_marker(_preview_root, _current_start, true)
			return
	else:
		var delta: Vector3 = end - _current_start
		delta.y = 0.0
		var length: float = delta.length()
		if length < 0.05:
			_preview_root.visible = true
			for child in _preview_root.get_children():
				child.queue_free()
			_add_chain_anchor_marker(_preview_root, _current_start, false)
			return
		var preview_segment: Variant = _create_wall_segment()
		if preview_segment == null:
			return
		preview_segment.start = _current_start
		preview_segment.end = end
		var matched: Dictionary = _resolve_matched_height(_current_start, end)
		preview_segment.height = float(matched.get("height", _segment_height))
		preview_segment.wall_type = _segment_type
		local_preview_segments = [preview_segment]
		if _wall_system.has_method("get_connection_feedback"):
			feedback = _wall_system.call("get_connection_feedback", preview_segment)

	_wall_system.call("build_preview_into", _preview_root, _build_preview_segments(local_preview_segments), feedback)
	if _is_rect_dragging and _is_rectangle_mode_active() and _rect_add_foundation:
		_add_rectangle_foundation_preview(_preview_root, _current_start, end, _square_drag_lock)
	_add_chain_anchor_marker(_preview_root, _current_start, _is_rect_dragging)
	_preview_root.visible = true
	if _is_edit_mode:
		_refresh_edit_handles()

func _add_rectangle_foundation_preview(parent: Node3D, start_pos: Vector3, end_pos: Vector3, force_square: bool) -> void:
	# Disabled to avoid detached preview artifacts; final foundation is built by WallSystem on confirm.
	return

func _resolve_matched_height(start_pos: Vector3, end_pos: Vector3) -> Dictionary:
	if not _match_connected_heights or _wall_system == null:
		return {"matched": false, "height": _segment_height}
	if _wall_system.has_method("get_matching_height_for_connection"):
		var result: Variant = _wall_system.call("get_matching_height_for_connection", start_pos, end_pos, _segment_height)
		if result is Dictionary:
			return result
	return {"matched": false, "height": _segment_height}

func _add_chain_anchor_marker(parent: Node3D, anchor_pos: Vector3, rect_mode: bool) -> void:
	# Disabled to prevent stray marker artifacts in gameplay/top-down view.
	return

func _handle_edit_mouse_button(mb: InputEventMouseButton) -> bool:
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			return _begin_edit_drag_or_select()
		if _drag_mode != "":
			_drag_mode = ""
			return true
		return false

	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_open_opening_context_menu()
		return true

	return false

func _begin_edit_drag_or_select() -> bool:
	var hit: Dictionary = _raycast_wall()
	if hit.is_empty():
		_selected_segment_idx = -1
		_selected_opening_idx = -1
		_refresh_edit_handles()
		return false

	var collider: Object = hit.get("collider", null)
	if collider != null and collider is Node and (collider as Node).has_meta("wall_handle_type"):
		var htype: String = String((collider as Node).get_meta("wall_handle_type"))
		_selected_segment_idx = int((collider as Node).get_meta("wall_segment_idx"))
		if htype == "start" or htype == "end":
			_push_undo_state()
			_drag_mode = htype
			_selected_opening_idx = -1
			return true
		if htype == "opening":
			_push_undo_state()
			_selected_opening_idx = int((collider as Node).get_meta("wall_opening_idx"))
			_drag_mode = "opening"
			return true

	if collider != null and collider is Node and (collider as Node).has_meta("wall_segment_idx"):
		_selected_segment_idx = int((collider as Node).get_meta("wall_segment_idx"))
		_selected_opening_idx = -1
		_refresh_edit_handles()
		_emit_status("Smart Wall: selected segment %d" % _selected_segment_idx)
		return true

	return false

func _handle_drag_update(mm: InputEventMouseMotion) -> void:
	if _selected_segment_idx < 0 or _wall_system == null:
		return
	var seg: Variant = _wall_system.get_segment(_selected_segment_idx)
	if seg == null:
		return
	var world: Variant = _get_mouse_world()
	if world == null:
		return
	var p: Vector3 = _snap(world as Vector3)

	if _drag_mode == "start":
		_wall_system.update_segment_endpoints(_selected_segment_idx, p, seg.end)
	elif _drag_mode == "end":
		_wall_system.update_segment_endpoints(_selected_segment_idx, seg.start, p)
	elif _drag_mode == "opening":
		if _selected_opening_idx >= 0:
			var opening: Dictionary = seg.openings[_selected_opening_idx]
			var opening_type: String = String(opening.get("type", "door")).to_lower()
			var ratio: float = _project_ratio_onto_segment(seg, p)
			var width: float = float(opening.get("width", 1.2))
			var height: float = float(opening.get("height", 1.2))
			var sill_height: float = float(opening.get("sill_height", 0.8))
			if mm.alt_pressed:
				width = clampf(width + (mm.relative.x + mm.relative.y) * 0.01, 0.35, maxf(0.5, seg.get_length() - 0.2))
			if opening_type == "window" and mm.ctrl_pressed:
				height = clampf(height + (-mm.relative.y * 0.01), 0.4, maxf(0.75, seg.height - 0.2))
				if _opening_height_snap_enabled:
					height = _snap_opening_height(height)
			width = _snap_opening_width(width, seg.get_length())
			_wall_system.update_opening(_selected_segment_idx, _selected_opening_idx, ratio, width, height, sill_height, String(opening.get("variant", "")))

	_refresh_edit_handles()

func _open_opening_context_menu() -> void:
	if _context_menu == null or _wall_system == null:
		return
	var hit: Dictionary = _raycast_wall()
	if hit.is_empty():
		return
	var collider: Object = hit.get("collider", null)
	if collider == null or not (collider is Node) or not (collider as Node).has_meta("wall_segment_idx"):
		return
	_context_segment_idx = int((collider as Node).get_meta("wall_segment_idx"))
	_context_opening_idx = -1
	if (collider as Node).has_meta("wall_handle_type") and String((collider as Node).get_meta("wall_handle_type")) == "opening":
		_context_opening_idx = int((collider as Node).get_meta("wall_opening_idx"))
	var seg: Variant = _wall_system.get_segment(_context_segment_idx)
	if seg == null:
		return
	var hit_pos: Vector3 = hit.get("position", seg.get_midpoint())
	_context_ratio = _project_ratio_onto_segment(seg, hit_pos)
	if _context_menu != null:
		var remove_idx: int = _context_menu.get_item_index(MENU_REMOVE_OPENING)
		if remove_idx >= 0:
			_context_menu.set_item_disabled(remove_idx, _context_opening_idx < 0)
	_context_menu.position = _last_mouse_screen
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	if _wall_system == null or _context_segment_idx < 0:
		return
	match id:
		MENU_ADD_DOOR:
			_push_undo_state()
			_wall_system.add_opening(_context_segment_idx, "door", _context_ratio, 1.2)
		MENU_ADD_WINDOW:
			_push_undo_state()
			var window_height: float = _snap_opening_height(1.7) if _opening_height_snap_enabled else 1.7
			var window_sill: float = _snap_opening_sill_height(0.75)
			var variant: String = ""
			var window_ratio: float = _context_ratio
			if _wall_system != null and _wall_system.has_method("_pick_window_variant"):
				variant = String(_wall_system.call("_pick_window_variant", _wall_system.get_segment(_context_segment_idx), window_ratio))
			if _wall_system.has_method("insert_opening"):
				_wall_system.insert_opening(_context_segment_idx, "window", window_ratio, 1.2, window_height, window_sill, variant)
			else:
				_wall_system.add_opening(_context_segment_idx, "window", window_ratio, 1.2, window_height, window_sill, variant)
		MENU_REMOVE_OPENING:
			if _context_opening_idx >= 0 and _wall_system.has_method("remove_opening"):
				_push_undo_state()
				_wall_system.call("remove_opening", _context_segment_idx, _context_opening_idx)
				_selected_opening_idx = -1
		_:
			return
	_selected_segment_idx = _context_segment_idx
	_selected_opening_idx = -1
	_refresh_edit_handles()

func _refresh_edit_handles() -> void:
	if _edit_root == null:
		return
	for child in _edit_root.get_children():
		child.queue_free()
	if not _is_edit_mode or _selected_segment_idx < 0 or _wall_system == null:
		return
	var seg: Variant = _wall_system.get_segment(_selected_segment_idx)
	if seg == null:
		return
	_create_handle(seg.start + Vector3(0.0, 0.35, 0.0), "start", _selected_segment_idx, -1, Color(0.2, 1.0, 0.45, 0.95))
	_create_handle(seg.end + Vector3(0.0, 0.35, 0.0), "end", _selected_segment_idx, -1, Color(0.2, 1.0, 0.45, 0.95))

	for i in range(seg.openings.size()):
		var op: Dictionary = seg.openings[i]
		var ratio: float = clampf(float(op.get("position", 0.5)), 0.0, 1.0)
		var p: Vector3 = seg.start.lerp(seg.end, ratio) + Vector3(0.0, 0.45, 0.0)
		var opening_tint: Color = Color(0.35, 0.75, 1.0, 0.72) if String(op.get("type", "door")).to_lower() == "window" else Color(1.0, 0.8, 0.2, 0.72)
		_create_handle(p, "opening", _selected_segment_idx, i, opening_tint)

func _create_handle(pos: Vector3, handle_type: String, seg_idx: int, opening_idx: int, tint: Color) -> void:
	var body := StaticBody3D.new()
	body.set_meta("wall_handle_type", handle_type)
	body.set_meta("wall_segment_idx", seg_idx)
	body.set_meta("wall_opening_idx", opening_idx)
	body.global_position = pos
	_edit_root.add_child(body)

	var cs := CollisionShape3D.new()
	if handle_type == "opening":
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(0.24, 0.24, 0.24)
		cs.shape = box_shape
	else:
		var sphere := SphereShape3D.new()
		sphere.radius = 0.26
		cs.shape = sphere
	body.add_child(cs)
	if handle_type == "opening":
		return

	var outer := MeshInstance3D.new()
	if handle_type == "opening":
		var outer_box := BoxMesh.new()
		outer_box.size = Vector3(0.3, 0.3, 0.3)
		outer.mesh = outer_box
	else:
		var outer_sphere := SphereMesh.new()
		outer_sphere.radius = 0.29
		outer_sphere.height = 0.58
		outer.mesh = outer_sphere
	var outer_mat := StandardMaterial3D.new()
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.albedo_color = Color(0.03, 0.03, 0.03, 0.68)
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer.material_override = outer_mat
	body.add_child(outer)

	var inner := MeshInstance3D.new()
	if handle_type == "opening":
		var inner_box := BoxMesh.new()
		inner_box.size = Vector3(0.16, 0.16, 0.16)
		inner.mesh = inner_box
	else:
		var inner_sphere := SphereMesh.new()
		inner_sphere.radius = 0.2
		inner_sphere.height = 0.4
		inner.mesh = inner_sphere
	var inner_mat := StandardMaterial3D.new()
	inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inner_mat.albedo_color = tint
	inner_mat.emission_enabled = true
	inner_mat.emission = Color(tint.r, tint.g, tint.b, 1.0)
	inner_mat.emission_energy_multiplier = 0.55
	inner.material_override = inner_mat
	body.add_child(inner)

func _raycast_wall() -> Dictionary:
	if not _mouse_ray_provider.is_valid() or _host == null:
		return {}
	var ray: Variant = _mouse_ray_provider.call()
	if ray is not Dictionary:
		return {}
	var r: Dictionary = ray
	var origin: Vector3 = r.get("origin", Vector3.ZERO)
	var direction: Vector3 = r.get("direction", Vector3.FORWARD)
	if direction.length_squared() <= 0.000001:
		return {}
	var state: PhysicsDirectSpaceState3D = _host.get_world_3d().direct_space_state
	if state == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * 1000.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit.get("collider", null)
	if collider == null or not (collider is Node):
		return {}
	var n: Node = collider as Node
	if n.has_meta("wall_segment_idx") or n.has_meta("wall_handle_type"):
		return hit
	return {}

func _project_ratio_onto_segment(seg: Variant, p: Vector3) -> float:
	var a: Vector3 = seg.start
	var b: Vector3 = seg.end
	var ab: Vector3 = b - a
	ab.y = 0.0
	var ap: Vector3 = p - a
	ap.y = 0.0
	var d: float = ab.length_squared()
	if d <= 0.000001:
		return 0.5
	return clampf(ap.dot(ab) / d, 0.0, 1.0)

func _snap_opening_width(width: float, seg_length: float) -> float:
	var max_width: float = maxf(0.5, seg_length - 0.2)
	var targets: Array[float] = [1.0, 1.5, 2.0]
	var nearest: float = clampf(width, 0.35, max_width)
	var best: float = 1e20
	for t in targets:
		if t > max_width:
			continue
		var d: float = absf(width - t)
		if d < best:
			best = d
			nearest = t
	if best <= 0.28:
		return nearest
	return clampf(round(width * 2.0) / 2.0, 0.35, max_width)

func _snap_opening_height(height: float) -> float:
	var targets: Array[float] = [0.8, 1.0, 1.2, 1.5, 1.7, 1.8, 2.0]
	var nearest: float = clampf(height, 0.4, 3.0)
	var best: float = 1e20
	for t in targets:
		var d: float = absf(height - t)
		if d < best:
			best = d
			nearest = t
	return nearest

func _snap_opening_sill_height(height: float) -> float:
	var targets: Array[float] = [0.4, 0.5, 0.6, 0.7, 0.75, 0.8, 1.0, 1.2]
	var nearest: float = clampf(height, 0.0, 2.0)
	var best: float = 1e20
	for t in targets:
		var d: float = absf(height - t)
		if d < best:
			best = d
			nearest = t
	return nearest

func _push_undo_state() -> void:
	if _wall_system == null or not _wall_system.has_method("save_data"):
		return
	_undo_history.append(_wall_system.call("save_data"))
	if _undo_history.size() > 80:
		_undo_history.remove_at(0)

func _snap(pos: Vector3) -> Vector3:
	var sx: float = round(pos.x / _snap_grid) * _snap_grid
	var sz: float = round(pos.z / _snap_grid) * _snap_grid
	var sy: float = pos.y
	if _terrain_height_provider.is_valid():
		var h: Variant = _terrain_height_provider.call(sx, sz)
		if h is float:
			sy = h as float
		elif h is int:
			sy = float(h)
	return Vector3(sx, sy, sz)

func _get_mouse_world() -> Variant:
	if not _mouse_world_provider.is_valid():
		return null
	return _mouse_world_provider.call()

func _emit_status(message: String) -> void:
	if _status_sink.is_valid():
		_status_sink.call(message)
