class_name WallSystem
extends Node3D

const WallSegment = preload("res://map/walls/wall_segment.gd")
const DEFAULT_WALL_MATERIAL_PATH: String = "res://assets/materials/wall_material.tres"
const DEFAULT_FOUNDATION_MATERIAL_PATH: String = "res://assets/materials/foundation_material.tres"
const DEFAULT_TUDOR_TEXTURE_DIR: String = "res://assets/textures/walls/tudor"
const DEFAULT_TUDOR_WINDOW_TEXTURE_DIR: String = "res://assets/textures/walls/tudor_window"
const DEFAULT_TUDOR_WINDOW_FRAME_TEXTURE_PATH: String = "res://assets/textures/walls/tudor_window/textures/tex_u1_v1_baseColor.jpeg"
const DEFAULT_TUDOR_CORNER_TEXTURE_PATH: String = "res://assets/textures/walls/stylized_low-poly_wooden_beam/textures/Material_baseColor.png"
const HEIGHT_NORMALIZE_EPSILON: float = 0.01

@export var segments: Array[WallSegment] = []
@export var foundations: Array[Dictionary] = []
@export var wall_prefabs: Dictionary = {}
@export var default_wall_thickness: float = 0.22
@export var default_wall_height: float = 3.4
@export var endpoint_tolerance: float = 0.3
@export var junction_setback: float = 0.45
@export var random_height_jitter: float = 0.0
@export var enable_hand_drawn_jitter: bool = false
@export var hand_drawn_jitter_degrees: float = 2.0
@export var hand_drawn_jitter_offset: float = 0.045
@export var wall_material: Material
@export var modular_piece_base_path: String = "res://assets/prefabs/walls/modular"
@export var tudor_texture_dir: String = DEFAULT_TUDOR_TEXTURE_DIR
@export var tudor_texture_paths: Array[String] = []
@export var tudor_window_texture_dir: String = DEFAULT_TUDOR_WINDOW_TEXTURE_DIR
@export var tudor_window_texture_paths: Array[String] = []
@export var tudor_panel_repeat_m: float = 2.0
@export var tudor_vertical_repeat_m: float = 2.2
@export var tudor_corner_setback: float = 0.16
@export var tudor_corner_texture_path: String = DEFAULT_TUDOR_CORNER_TEXTURE_PATH
@export var foundation_height: float = 0.4
@export var foundation_overhang: float = 0.2
@export var foundation_top_overlap: float = 0.06
@export var foundation_texture_repeat_m: float = 1.0
@export var foundation_material: Material

var _instances: Dictionary = {}
var _cluster_data: Array[Dictionary] = []
var _endpoint_cluster_map: Dictionary = {}
var _cluster_source_segments: Array = []
var _prefab_cache: Dictionary = {}
var _preview_material_cache: Dictionary = {}
var _runtime_wall_material: Material = null
var _runtime_foundation_material: Material = null
var _tudor_textures: Array[Texture2D] = []
var _tudor_window_textures: Array[Texture2D] = []
var _tudor_material_cache: Dictionary = {}
var _tudor_window_material_cache: Dictionary = {}
var _tudor_window_frame_texture: Texture2D = null
var _tudor_corner_material: Material = null
var _openings_root: Node3D = null

func _ready() -> void:
	_load_tudor_textures()
	_load_tudor_window_textures()
	_ensure_wall_material()
	_ensure_openings_root()
	_ensure_modular_library_generated()
	auto_register_prefabs()

func rebuild_all() -> void:
	normalize_connected_heights()
	_rebuild_geometry_only()

func _rebuild_geometry_only() -> void:
	for child in get_children():
		if child == _openings_root:
			continue
		child.queue_free()
	_instances.clear()
	_ensure_wall_material()
	_ensure_openings_root()
	_rebuild_into(self, segments, false, {})
	_reposition_openings()

func build_preview_into(parent: Node3D, preview_segments: Array, feedback: Dictionary = {}) -> void:
	if parent == null:
		return
	for child in parent.get_children():
		child.queue_free()
	_ensure_wall_material()
	_rebuild_into(parent, preview_segments, true, feedback)

func _ensure_openings_root() -> void:
	if _openings_root != null and is_instance_valid(_openings_root):
		if _openings_root.get_parent() != self:
			add_child(_openings_root)
		return
	_openings_root = Node3D.new()
	_openings_root.name = "Openings"
	add_child(_openings_root)

func _clear_openings_root() -> void:
	if _openings_root == null or not is_instance_valid(_openings_root):
		return
	for child in _openings_root.get_children():
		child.queue_free()

func _reposition_openings() -> void:
	# Openings are stored as live nodes under the persistent Openings root.
	# Repositioning is handled when they are created; rebuilds preserve them.
	return

func clear_segments() -> void:
	segments.clear()
	foundations.clear()
	rebuild_all()

func undo_last_segment() -> bool:
	if segments.is_empty():
		return false
	segments.remove_at(segments.size() - 1)
	rebuild_all()
	return true

func auto_register_prefabs(base_path: String = "res://assets/prefabs/walls") -> void:
	_prefab_cache.clear()
	var modular_abs: String = ProjectSettings.globalize_path(modular_piece_base_path)
	if DirAccess.dir_exists_absolute(modular_abs):
		base_path = modular_piece_base_path
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(base_path)):
		return
	var paths: Array[String] = []
	_collect_prefab_paths(base_path, paths)
	for path in paths:
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			continue
		var key: String = path.get_file().get_basename().to_lower()
		if not wall_prefabs.has(key):
			wall_prefabs[key] = packed
		var rel: String = path.trim_prefix(base_path + "/")
		var tokens: PackedStringArray = rel.split("/", false)
		if tokens.size() >= 2:
			var wall_type: String = tokens[0].to_lower()
			var typed_key: String = "%s_%s" % [wall_type, key]
			if not wall_prefabs.has(typed_key):
				wall_prefabs[typed_key] = packed

func _ensure_modular_library_generated() -> void:
	if _modular_prefab_count() > 0:
		return
	
	var gen_script: Script = load("res://scripts/tools/wall_piece_generator.gd") as Script
	if gen_script == null:
		push_warning("WallPieceGenerator script missing; modular wall generation skipped")
		return
	
	var gen_node := gen_script.new() as Node
	if gen_node == null:
		return
	
	# Ensure auto_generate_on_ready is true so it runs
	gen_node.set("auto_generate_on_ready", true)
	add_child(gen_node)
	gen_node.queue_free()

func _modular_prefab_count() -> int:
	var abs_dir: String = ProjectSettings.globalize_path(modular_piece_base_path)
	var dir := DirAccess.open(modular_piece_base_path)
	if dir == null:
		if not DirAccess.dir_exists_absolute(abs_dir):
			return 0
		dir = DirAccess.open(modular_piece_base_path)
		if dir == null:
			return 0
	var count: int = 0
	dir.list_dir_begin()
	while true:
		var name: String = dir.get_next()
		if name == "":
			break
		if dir.current_is_dir():
			continue
		if name.ends_with(".tscn"):
			count += 1
	dir.list_dir_end()
	return count

func get_connection_feedback(new_segment: WallSegment) -> Dictionary:
	var highlight_indices: Array[int] = []
	var junction_points: Array[Vector3] = []
	if new_segment == null:
		return {
			"highlight_indices": highlight_indices,
			"junction_points": junction_points,
			"has_connection": false
		}

	for i in range(segments.size()):
		var seg: WallSegment = segments[i]
		if seg == null:
			continue
		var endpoints := [seg.start, seg.end]
		for ep in endpoints:
			if ep.distance_to(new_segment.start) <= endpoint_tolerance or ep.distance_to(new_segment.end) <= endpoint_tolerance:
				if not highlight_indices.has(i):
					highlight_indices.append(i)
				junction_points.append(ep)

	return {
		"highlight_indices": highlight_indices,
		"junction_points": junction_points,
		"has_connection": not highlight_indices.is_empty()
	}

func get_segment(idx: int) -> WallSegment:
	if idx < 0 or idx >= segments.size():
		return null
	return segments[idx]

func update_segment_endpoints(idx: int, new_start: Vector3, new_end: Vector3) -> bool:
	if idx < 0 or idx >= segments.size():
		return false
	var seg: WallSegment = segments[idx]
	if seg == null:
		return false
	if new_start.distance_to(new_end) < 0.2:
		return false
	seg.start = new_start
	seg.end = new_end
	rebuild_all()
	return true

func remove_segment(idx: int) -> bool:
	if idx < 0 or idx >= segments.size():
		return false
	segments.remove_at(idx)
	rebuild_all()
	return true

func insert_opening(segment_idx: int, opening_type: String, ratio: float, width: float = 1.2, height: float = 1.7, sill_height: float = 0.75, variant: String = "") -> bool:
	if segment_idx < 0 or segment_idx >= segments.size():
		return false
	var seg: WallSegment = segments[segment_idx]
	if seg == null:
		return false

	var ot: String = opening_type.strip_edges().to_lower()
	var opening_height: float = maxf(0.2, height if height > 0.0 else (1.7 if ot == "window" else 2.2))
	var opening_sill: float = maxf(0.0, sill_height if sill_height >= 0.0 else (0.75 if ot == "window" else 0.0))
	if ot == "window":
		opening_height = minf(opening_height, maxf(0.35, seg.height - opening_sill - 0.1))
		opening_sill = clampf(opening_sill, 0.0, maxf(0.0, seg.height - opening_height - 0.1))

	seg.openings.append({
		"type": ot,
		"position": clampf(ratio, 0.0, 1.0),
		"width": clampf(width, 0.35, maxf(0.5, seg.get_length() - 0.2)),
		"height": opening_height,
		"sill_height": opening_sill,
		"variant": variant.strip_edges()
	})
	_rebuild_geometry_only()
	return true

func add_opening(idx: int, opening_type: String, ratio: float, width: float = 1.2, height: float = -1.0, sill_height: float = -1.0, variant: String = "") -> bool:
	# DEPRECATED: Use insert_opening() instead
	# This is kept for backward compatibility but delegates to the new method
	var ot: String = opening_type.strip_edges().to_lower()
	var opening_height: float = maxf(0.2, height if height > 0.0 else (1.7 if ot == "window" else 2.2))
	var opening_sill: float = maxf(0.0, sill_height if sill_height >= 0.0 else (0.75 if ot == "window" else 0.0))
	return insert_opening(idx, opening_type, ratio, width, opening_height, opening_sill, variant)

func remove_opening(idx: int, opening_idx: int) -> bool:
	if idx < 0 or idx >= segments.size():
		return false
	var seg: WallSegment = segments[idx]
	if seg == null:
		return false
	if opening_idx < 0 or opening_idx >= seg.openings.size():
		return false
	seg.openings.remove_at(opening_idx)
	var endpoint_snapshot: Array = _capture_segment_endpoints()
	normalize_connected_heights()
	_restore_segment_endpoints(endpoint_snapshot)
	_rebuild_geometry_only()
	return true

func set_segment_height(idx: int, new_height: float) -> bool:
	if idx < 0 or idx >= segments.size():
		return false
	var seg: WallSegment = segments[idx]
	if seg == null:
		return false
	seg.height = maxf(0.2, new_height)
	rebuild_all()
	return true

func set_component_height_from_segment(idx: int, new_height: float) -> int:
	if idx < 0 or idx >= segments.size():
		return 0
	var target_h: float = maxf(0.2, new_height)
	var connected: Array[int] = _collect_connected_segment_indices([idx])
	if connected.is_empty():
		return 0
	for seg_idx in connected:
		if seg_idx >= 0 and seg_idx < segments.size() and segments[seg_idx] != null:
			segments[seg_idx].height = target_h
	rebuild_all()
	return connected.size()

func normalize_connected_heights() -> int:
	if segments.is_empty():
		return 0
	var changed: int = 0
	var visited: Dictionary = {}
	for i in range(segments.size()):
		if visited.has(i) or segments[i] == null:
			continue
		var component: Array[int] = _collect_connected_segment_indices([i])
		if component.is_empty():
			continue
		for idx in component:
			visited[idx] = true
		var master_height: float = _component_master_height(component)
		for seg_idx in component:
			if seg_idx < 0 or seg_idx >= segments.size() or segments[seg_idx] == null:
				continue
			if absf(segments[seg_idx].height - master_height) > HEIGHT_NORMALIZE_EPSILON:
				segments[seg_idx].height = master_height
				changed += 1
	return changed

func get_matching_height_for_connection(start_pos: Vector3, end_pos: Vector3, fallback_height: float) -> Dictionary:
	var connected_seed: Array[int] = []
	for i in range(segments.size()):
		var seg: WallSegment = segments[i]
		if seg == null:
			continue
		if _segment_touches_point(seg, start_pos) or _segment_touches_point(seg, end_pos):
			connected_seed.append(i)
	if connected_seed.is_empty():
		return {
			"matched": false,
			"height": maxf(0.2, fallback_height),
			"source": "fallback"
		}

	var component: Array[int] = _collect_connected_segment_indices(connected_seed)
	if component.is_empty():
		return {
			"matched": true,
			"height": maxf(0.2, fallback_height),
			"source": "seed"
		}
	var result_h: float = _component_master_height(component)

	return {
		"matched": true,
		"height": maxf(0.2, result_h),
		"source": "connected_master"
	}

func _pick_window_variant(seg: WallSegment, ratio: float) -> String:
	if _tudor_window_textures.is_empty():
		return ""
	var idx: int = _get_window_variant_index(seg, ratio)
	if idx < 0 or idx >= _tudor_window_textures.size():
		return ""
	var tex: Texture2D = _tudor_window_textures[idx]
	if tex == null:
		return ""
	return tex.resource_path.get_file().get_basename()

func _get_window_variant_index(seg: WallSegment, ratio: float) -> int:
	if _tudor_window_textures.is_empty():
		return 0
	var h: float = absf(seg.start.x * 19.11 + seg.start.z * 73.29 + seg.end.x * 11.77 + seg.end.z * 57.41 + ratio * 101.3)
	return int(floor(h * 10.0)) % _tudor_window_textures.size()

func _load_tudor_window_textures() -> void:
	_tudor_window_textures.clear()
	_tudor_window_material_cache.clear()
	_tudor_window_frame_texture = null
	var paths: Array[String] = []
	if not tudor_window_texture_paths.is_empty():
		for p in tudor_window_texture_paths:
			if p.strip_edges() != "":
				paths.append(p)
	else:
		var dir_path: String = tudor_window_texture_dir if tudor_window_texture_dir.strip_edges() != "" else DEFAULT_TUDOR_WINDOW_TEXTURE_DIR
		_collect_texture_paths(dir_path, paths)
	paths.sort()
	for p in paths:
		var tex: Texture2D = load(p) as Texture2D
		if tex != null:
			_tudor_window_textures.append(tex)
	if ResourceLoader.exists(DEFAULT_TUDOR_WINDOW_FRAME_TEXTURE_PATH):
		_tudor_window_frame_texture = load(DEFAULT_TUDOR_WINDOW_FRAME_TEXTURE_PATH) as Texture2D

func _segment_base_height(seg: WallSegment) -> float:
	return maxf(seg.start.y, seg.end.y)

func _opening_center_height(seg: WallSegment, opening: Dictionary, sample_pos: Vector3) -> float:
	var base_y: float = _sample_segment_height(seg, sample_pos) - (_resolved_height(seg) * 0.5)
	var opening_type: String = String(opening.get("type", "door")).strip_edges().to_lower()
	if opening_type == "window":
		var sill_h: float = maxf(0.0, float(opening.get("sill_height", 0.8)))
		var opening_h: float = maxf(0.2, float(opening.get("height", 1.2)))
		return base_y + sill_h + (opening_h * 0.5)
	return base_y + (_resolved_height(seg) * 0.5)

func _get_window_material(seg: WallSegment, opening: Dictionary, is_preview: bool, tint: Color) -> Material:
	var variant: String = String(opening.get("variant", "")).strip_edges()
	var idx: int = _get_window_variant_index(seg, float(opening.get("position", 0.5)))
	if variant != "":
		var var_key: String = variant.to_lower()
		for i in range(_tudor_window_textures.size()):
			var tex: Texture2D = _tudor_window_textures[i]
			if tex != null and tex.resource_path.get_file().get_basename().to_lower() == var_key:
				idx = i
				break
	var key: String = "glass_%d_%d" % [idx, 1 if is_preview else 0]
	if _tudor_window_material_cache.has(key):
		return _tudor_window_material_cache[key] as Material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if not is_preview else BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.82, 0.9, 1.0, 0.18 if not is_preview else 0.36)
	mat.roughness = 0.08
	mat.metallic = 0.0
	_tudor_window_material_cache[key] = mat
	return mat

func _get_window_frame_material(seg: WallSegment, opening: Dictionary, is_preview: bool, tint: Color) -> Material:
	var key: String = "frame_%s_%d" % [seg.wall_type, 1 if is_preview else 0]
	if _tudor_window_material_cache.has(key):
		return _tudor_window_material_cache[key] as Material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if not is_preview else BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color = Color(0.33, 0.24, 0.17, 1.0 if not is_preview else 0.72)
	mat.roughness = 0.9
	mat.metallic = 0.0
	# Use a stable wood tint for frames; imported texture set is too noisy for small window pieces.
	_tudor_window_material_cache[key] = mat
	return mat

func _apply_window_materials(node: Node, seg: WallSegment, opening: Dictionary, is_preview: bool, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var lower_name: String = String(mesh_node.name).to_lower()
		if lower_name.contains("pane") or lower_name.contains("glass"):
			mesh_node.material_override = _get_window_material(seg, opening, is_preview, tint)
		elif lower_name.contains("frame") or lower_name.contains("mullion") or _mesh_instance_has_no_material(mesh_node):
			mesh_node.material_override = _get_window_frame_material(seg, opening, is_preview, tint)
		mesh_node.material_overlay = null
	for child in node.get_children():
		_apply_window_materials(child, seg, opening, is_preview, tint)

func _mesh_instance_has_no_material(mesh_node: MeshInstance3D) -> bool:
	if mesh_node == null:
		return true
	if mesh_node.material_override != null:
		return false
	if mesh_node.mesh == null:
		return true
	for i in range(mesh_node.mesh.get_surface_count()):
		if mesh_node.mesh.surface_get_material(i) != null:
			return false
	return true

func add_rect_foundation(corners: Array, wall_type: String = "stone", top_y: float = 0.0, height_m: float = -1.0, overhang_m: float = -1.0) -> bool:
	if corners.size() < 4:
		return false
	var min_x: float = 1e20
	var max_x: float = -1e20
	var min_z: float = 1e20
	var max_z: float = -1e20
	var max_y: float = top_y
	for v in corners:
		if v is not Vector3:
			continue
		var p: Vector3 = v
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
		max_y = maxf(max_y, p.y)
	if min_x > max_x or min_z > max_z:
		return false
	var fh: float = maxf(0.05, height_m if height_m > 0.0 else foundation_height)
	var ov: float = maxf(0.0, overhang_m if overhang_m >= 0.0 else foundation_overhang)
	foundations.append({
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
		"top_y": max_y,
		"height": fh,
		"overhang": ov,
		"wall_type": wall_type
	})
	rebuild_all()
	return true

func update_opening(idx: int, opening_idx: int, ratio: float, width: float, height: float = -1.0, sill_height: float = -1.0, variant: String = "") -> bool:
	if idx < 0 or idx >= segments.size():
		return false
	var seg: WallSegment = segments[idx]
	if seg == null:
		return false
	if opening_idx < 0 or opening_idx >= seg.openings.size():
		return false
	var opening: Dictionary = seg.openings[opening_idx]
	var opening_type: String = String(opening.get("type", "door")).strip_edges().to_lower()
	opening["position"] = clampf(ratio, 0.0, 1.0)
	opening["width"] = clampf(width, 0.35, maxf(0.5, seg.get_length() - 0.2))
	if opening_type == "window":
		opening["height"] = maxf(0.2, height if height > 0.0 else float(opening.get("height", 1.2)))
		opening["sill_height"] = maxf(0.0, sill_height if sill_height >= 0.0 else float(opening.get("sill_height", 0.75)))
		opening["height"] = minf(float(opening["height"]), maxf(0.35, seg.height - float(opening["sill_height"]) - 0.1))
		opening["sill_height"] = clampf(float(opening["sill_height"]), 0.0, maxf(0.0, seg.height - float(opening["height"]) - 0.1))
		var chosen_variant: String = variant.strip_edges()
		if chosen_variant == "":
			chosen_variant = String(opening.get("variant", ""))
		if chosen_variant == "":
			chosen_variant = _pick_window_variant(seg, ratio)
		opening["variant"] = chosen_variant
	seg.openings[opening_idx] = opening
	var endpoint_snapshot: Array = _capture_segment_endpoints()
	if opening_type == "window":
		_debug_print_structure_bounds("before_update_window")
	normalize_connected_heights()
	_restore_segment_endpoints(endpoint_snapshot)
	_rebuild_geometry_only()
	if opening_type == "window":
		_debug_print_structure_bounds("after_update_window")
	return true

func _capture_segment_endpoints() -> Array:
	var snapshot: Array = []
	for seg in segments:
		if seg == null:
			snapshot.append(null)
			continue
		snapshot.append({
			"start": seg.start,
			"end": seg.end
		})
	return snapshot

func _restore_segment_endpoints(snapshot: Array) -> void:
	if snapshot.is_empty():
		return
	for i in range(mini(snapshot.size(), segments.size())):
		if segments[i] == null:
			continue
		var s: Variant = snapshot[i]
		if s is Dictionary:
			var d: Dictionary = s
			if d.has("start") and d["start"] is Vector3:
				segments[i].start = d["start"] as Vector3
			if d.has("end") and d["end"] is Vector3:
				segments[i].end = d["end"] as Vector3

func _debug_print_structure_bounds(tag: String) -> void:
	if segments.is_empty():
		print("[WallSystem] %s: no segments" % tag)
		return
	var min_x: float = 1e20
	var max_x: float = -1e20
	var min_z: float = 1e20
	var max_z: float = -1e20
	var base_y: float = 1e20
	for seg in segments:
		if seg == null:
			continue
		min_x = minf(min_x, minf(seg.start.x, seg.end.x))
		max_x = maxf(max_x, maxf(seg.start.x, seg.end.x))
		min_z = minf(min_z, minf(seg.start.z, seg.end.z))
		max_z = maxf(max_z, maxf(seg.start.z, seg.end.z))
		base_y = minf(base_y, minf(seg.start.y, seg.end.y))
	if min_x > max_x or min_z > max_z:
		print("[WallSystem] %s: invalid bounds" % tag)
		return
	var c0: Vector3 = Vector3(min_x, base_y, min_z)
	var c1: Vector3 = Vector3(max_x, base_y, min_z)
	var c2: Vector3 = Vector3(max_x, base_y, max_z)
	var c3: Vector3 = Vector3(min_x, base_y, max_z)
	print("[WallSystem] %s corners: %s %s %s %s" % [tag, c0, c1, c2, c3])


func _apply_window_materials_to_prefab(node: Node) -> void:
	# Apply frame and glass materials to window prefab recursively
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var lower_name: String = String(mesh_node.name).to_lower()
		if lower_name.contains("pane") or lower_name.contains("glass"):
			# Apply transparent glass material
			var glass_mat := StandardMaterial3D.new()
			glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass_mat.albedo_color = Color(0.82, 0.9, 1.0, 0.2)
			glass_mat.roughness = 0.08
			glass_mat.metallic = 0.0
			mesh_node.material_override = glass_mat
		elif lower_name.contains("frame") or lower_name.contains("mullion") or _mesh_instance_has_no_material(mesh_node):
			# Apply frame material
			var frame_mat := StandardMaterial3D.new()
			frame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
			frame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			frame_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			frame_mat.albedo_color = Color(0.33, 0.24, 0.17, 1.0)
			frame_mat.roughness = 0.9
			frame_mat.metallic = 0.0
			mesh_node.material_override = frame_mat
	for child in node.get_children():
		_apply_window_materials_to_prefab(child)
func save_data() -> Dictionary:
	var items: Array[Dictionary] = []
	for seg in segments:
		if seg == null:
			continue
		items.append({
			"start": [seg.start.x, seg.start.y, seg.start.z],
			"end": [seg.end.x, seg.end.y, seg.end.z],
			"height": seg.height,
			"wall_type": seg.wall_type,
			"openings": seg.openings.duplicate(true)
		})
	var foundation_items: Array[Dictionary] = []
	for f in foundations:
		if f is Dictionary:
			foundation_items.append((f as Dictionary).duplicate(true))
	return {
		"default_wall_height": default_wall_height,
		"default_wall_thickness": default_wall_thickness,
		"segments": items,
		"foundations": foundation_items
	}

func load_data(data: Dictionary) -> void:
	segments.clear()
	foundations.clear()
	if data.has("default_wall_height"):
		default_wall_height = float(data["default_wall_height"])
	if data.has("default_wall_thickness"):
		default_wall_thickness = float(data["default_wall_thickness"])
	var items: Array = data.get("segments", [])
	for item in items:
		if item is not Dictionary:
			continue
		var d: Dictionary = item
		var seg := WallSegment.new()
		seg.start = _arr_to_vec3(d.get("start", [0.0, 0.0, 0.0]))
		seg.end = _arr_to_vec3(d.get("end", [0.0, 0.0, 1.0]))
		seg.height = float(d.get("height", default_wall_height))
		seg.wall_type = String(d.get("wall_type", "stone"))
		seg.openings = (d.get("openings", []) as Array).duplicate(true)
		segments.append(seg)
	var loaded_foundations: Array = data.get("foundations", [])
	for f in loaded_foundations:
		if f is Dictionary:
			foundations.append((f as Dictionary).duplicate(true))
	rebuild_all()

func _rebuild_into(target_parent: Node3D, source_segments: Array, is_preview: bool, feedback: Dictionary) -> void:
	_build_foundations(target_parent, is_preview)
	_build_endpoint_clusters(source_segments)
	var segment_root := Node3D.new()
	segment_root.name = "Segments"
	target_parent.add_child(segment_root)

	var highlight_indices: Array[int] = []
	if feedback.has("highlight_indices") and feedback["highlight_indices"] is Array:
		for v in feedback["highlight_indices"]:
			if v is int:
				highlight_indices.append(v)

	for i in range(source_segments.size()):
		_build_segment(segment_root, source_segments, i, is_preview, highlight_indices)

	_build_junctions(target_parent, source_segments, is_preview)
	if is_preview:
		_build_junction_markers(target_parent, feedback)

func _build_foundations(target_parent: Node3D, is_preview: bool) -> void:
	if foundations.is_empty():
		return
	var root := Node3D.new()
	root.name = "Foundations"
	target_parent.add_child(root)
	
	# Temporarily use simple box fallback instead of modular pieces
	# This simplifies debugging and lets us validate wall + window system first
	for f in foundations:
		if f is not Dictionary:
			continue
		var d: Dictionary = f
		var min_x: float = float(d.get("min_x", 0.0))
		var max_x: float = float(d.get("max_x", 0.0))
		var min_z: float = float(d.get("min_z", 0.0))
		var max_z: float = float(d.get("max_z", 0.0))
		var top_y: float = float(d.get("top_y", 0.0))
		var fh: float = maxf(0.05, float(d.get("height", foundation_height)))
		var ov: float = maxf(0.0, float(d.get("overhang", foundation_overhang)))
		var width_x: float = maxf(0.1, (max_x - min_x) + (ov * 2.0))
		var width_z: float = maxf(0.1, (max_z - min_z) + (ov * 2.0))
		var center_x: float = (min_x + max_x) * 0.5
		var center_z: float = (min_z + max_z) * 0.5
		var top_overlap: float = clampf(foundation_top_overlap, 0.0, 0.15)
		var center_y: float = top_y - (fh * 0.5) + top_overlap

		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(width_x, fh, width_z)
		mesh_instance.mesh = box
		mesh_instance.material_override = _get_foundation_material(is_preview, String(d.get("wall_type", "stone")), width_x, width_z)
		mesh_instance.position = Vector3(center_x, center_y, center_z)
		root.add_child(mesh_instance)

		if not is_preview:
			var body := StaticBody3D.new()
			body.name = "FoundationCollision"
			var col := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = box.size
			col.shape = shape
			body.add_child(col)
			body.position = mesh_instance.position
			root.add_child(body)

func _build_segment(target_parent: Node3D, source_segments: Array, idx: int, is_preview: bool, highlight_indices: Array[int]) -> void:
	if idx < 0 or idx >= source_segments.size():
		return
	var seg: WallSegment = source_segments[idx]
	if seg == null:
		return

	var delta: Vector3 = seg.end - seg.start
	delta.y = 0.0
	var length: float = delta.length()
	if length < 0.05:
		return

	var direction: Vector3 = delta.normalized()
	var yaw: float = atan2(direction.z, direction.x)

	var segment_root := Node3D.new()
	segment_root.name = "WallSegment_%d" % idx
	target_parent.add_child(segment_root)

	var start_info: Dictionary = _get_endpoint_info(idx, true)
	var end_info: Dictionary = _get_endpoint_info(idx, false)
	var start_connections: int = int(start_info.get("count", 1))
	var end_connections: int = int(end_info.get("count", 1))
	var corner_setback: float = _segment_corner_setback(seg)

	var start_setback: float = corner_setback if start_connections > 1 else 0.0
	var end_setback: float = corner_setback if end_connections > 1 else 0.0
	var trim_total: float = start_setback + end_setback
	if trim_total > length - 0.1:
		var max_trim: float = maxf(0.0, (length - 0.1) * 0.5)
		start_setback = minf(start_setback, max_trim)
		end_setback = minf(end_setback, max_trim)

	var trimmed_start: Vector3 = seg.start + (direction * start_setback)
	var trimmed_end: Vector3 = seg.end - (direction * end_setback)
	var trimmed_length: float = trimmed_start.distance_to(trimmed_end)
	if trimmed_length < 0.05:
		return

	var piece_tint: Color = _resolve_base_tint_color(is_preview)
	if is_preview and highlight_indices.has(idx):
		piece_tint.a = minf(0.52, piece_tint.a + 0.08)
	if is_preview and idx == source_segments.size() - 1:
		piece_tint.a = minf(0.58, piece_tint.a + 0.12)

	var straight_key_1m: String = "%s_wall_straight_1m" % seg.wall_type
	var straight_key_2m: String = "%s_wall_straight_2m" % seg.wall_type
	var straight_key_4m: String = "%s_wall_straight_4m" % seg.wall_type
	var straight_key_8m: String = "%s_wall_straight_8m" % seg.wall_type
	var straight_key_any: String = "%s_straight" % seg.wall_type
	var opening_instances: Array[Dictionary] = []
	var window_instances: Array[Dictionary] = []
	var intervals: Array[Dictionary] = _compute_straight_intervals(trimmed_length, seg.openings, opening_instances, window_instances)

	for interval in intervals:
		var seg_from: float = float(interval.get("from", 0.0))
		var seg_to: float = float(interval.get("to", 0.0))
		if seg_to - seg_from < 0.08:
			continue
		var interval_start: Vector3 = trimmed_start + (direction * seg_from)
		var interval_end: Vector3 = trimmed_start + (direction * seg_to)
		_place_straight_pieces(
			segment_root,
			interval_start,
			interval_end,
			yaw,
			seg,
			straight_key_1m,
			straight_key_2m,
			straight_key_4m,
			straight_key_8m,
			straight_key_any,
			is_preview,
			piece_tint,
			window_instances
		)

	for opening in opening_instances:
		_place_opening_piece(segment_root, seg, trimmed_start, direction, yaw, opening, is_preview, piece_tint)

	# Safety fallback: if no wall geometry was produced, create one straight fallback piece.
	# This prevents empty rectangles when modular key resolution or interval planning fails.
	if segment_root.get_child_count() == 0 and trimmed_length >= 0.05:
		var fallback_node: Node3D = _instantiate_prefab_or_box(segment_root, seg, "", trimmed_length, is_preview, piece_tint)
		var fallback_center: Vector3 = (trimmed_start + trimmed_end) * 0.5
		fallback_node.position = Vector3(fallback_center.x, _sample_segment_height(seg, fallback_center), fallback_center.z)
		fallback_node.rotation = Vector3(0.0, yaw, 0.0)

	if start_connections <= 1:
		_place_cap(segment_root, seg, seg.start, yaw + PI, true, is_preview, piece_tint)
	if end_connections <= 1:
		_place_cap(segment_root, seg, seg.end, yaw, false, is_preview, piece_tint)

	if not is_preview:
		_add_segment_collision(segment_root, idx, seg)

func _place_straight_pieces(
	parent: Node3D,
	segment_start: Vector3,
	segment_end: Vector3,
	yaw: float,
	seg: WallSegment,
	straight_key_1m: String,
	straight_key_2m: String,
	straight_key_4m: String,
	straight_key_8m: String,
	straight_key_any: String,
	is_preview: bool,
	tint: Color,
	window_instances: Array[Dictionary]
) -> void:
	var delta: Vector3 = segment_end - segment_start
	var run: float = delta.length()
	if run < 0.05:
		return
	var direction: Vector3 = delta.normalized()
	var plan: Array[Dictionary] = _make_piece_plan(
		run,
		_has_prefab(straight_key_1m),
		_has_prefab(straight_key_2m),
		_has_prefab(straight_key_4m),
		_has_prefab(straight_key_8m),
		_has_prefab(straight_key_any)
	)
	var cursor: float = 0.0
	for piece in plan:
		var piece_len: float = float(piece.get("len", 1.0))
		var piece_key: String = String(piece.get("key", ""))
		var resolved_key: String = piece_key
		if piece_key == "straight_4m":
			resolved_key = straight_key_4m
		elif piece_key == "straight_8m":
			resolved_key = straight_key_8m
		elif piece_key == "straight_2m":
			resolved_key = straight_key_2m
		elif piece_key == "straight_1m":
			resolved_key = straight_key_1m
		elif piece_key == "straight_any":
			resolved_key = straight_key_any
		elif piece_key == "fallback":
			resolved_key = ""
		var piece_center: Vector3 = segment_start + (direction * (cursor + piece_len * 0.5))
		var node: Node3D = _instantiate_prefab_or_box(parent, seg, resolved_key, piece_len, is_preview, tint)
		var final_center: Vector3 = piece_center
		var final_yaw: float = yaw
		var window_opening: Dictionary = _find_window_opening_for_piece(window_instances, cursor, piece_len)
		if enable_hand_drawn_jitter and not is_preview:
			var jitter_seed: float = _jitter_hash(piece_center)
			var yaw_jitter_rad: float = deg_to_rad(hand_drawn_jitter_degrees) * ((jitter_seed * 2.0) - 1.0)
			final_yaw += yaw_jitter_rad
			var side: Vector3 = Vector3(-direction.z, 0.0, direction.x)
			var offset_amount: float = hand_drawn_jitter_offset * (((1.0 - jitter_seed) * 2.0) - 1.0)
			final_center += side * offset_amount
		node.position = Vector3(final_center.x, _sample_segment_height(seg, final_center), final_center.z)
		node.rotation = Vector3(0.0, final_yaw, 0.0)
		if not window_opening.is_empty():
			_apply_window_cutout(node, seg, piece_len, cursor, window_opening, is_preview)
		cursor += piece_len

func _make_piece_plan(length: float, has_1m: bool, has_2m: bool, has_4m: bool, has_8m: bool, has_any: bool) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var best_n8: int = 0
	var best_n4: int = 0
	var best_n2: int = 0
	var best_n1: int = 0
	var best_error: float = 1e20
	if has_1m or has_2m or has_4m or has_8m:
		var max_n8: int = int(floor(length / 8.0)) + 1
		for n8 in range(max_n8 + 1):
			var rem8: float = length - (float(n8) * 8.0)
			if rem8 < -0.01:
				continue
			var max_n4: int = int(floor(rem8 / 4.0)) + 1
			for n4 in range(max_n4 + 1):
				var rem4: float = rem8 - (float(n4) * 4.0)
				if rem4 < -0.01:
					continue
				var max_n2: int = int(floor(rem4 / 2.0)) + 1
				for n2 in range(max_n2 + 1):
					var rem2: float = rem4 - (float(n2) * 2.0)
					if rem2 < -0.01:
						continue
					var n1: int = 0
					if has_1m:
						n1 = maxi(0, int(round(rem2 / 1.0)))
					var built: float = float(n8) * 8.0 + float(n4) * 4.0 + float(n2) * 2.0 + float(n1)
					var err: float = absf(length - built)
					if err < best_error:
						best_error = err
						best_n8 = n8 if has_8m else 0
						best_n4 = n4 if has_4m else 0
						best_n2 = n2 if has_2m else 0
						best_n1 = n1 if has_1m else 0

	for i in range(best_n8):
		plan.append({"len": 8.0, "key": "straight_8m"})
	for i in range(best_n4):
		plan.append({"len": 4.0, "key": "straight_4m"})
	for i in range(best_n2):
		plan.append({"len": 2.0, "key": "straight_2m"})
	for i in range(best_n1):
		plan.append({"len": 1.0, "key": "straight_1m"})

	var covered: float = 0.0
	for p in plan:
		covered += float(p.get("len", 0.0))
	var residual: float = length - covered
	if residual > 0.12:
		if has_any:
			plan.append({"len": residual, "key": "straight_any"})
		elif not plan.is_empty():
			plan[plan.size() - 1]["len"] = float(plan[plan.size() - 1].get("len", 0.0)) + residual
		else:
			plan.append({"len": length, "key": "fallback"})

	if plan.is_empty():
		plan.append({"len": length, "key": "fallback"})
	return plan

func _compute_straight_intervals(total_length: float, openings: Array[Dictionary], opening_instances: Array[Dictionary], window_instances: Array[Dictionary]) -> Array[Dictionary]:
	var gaps: Array[Dictionary] = []
	for opening in openings:
		var opening_type: String = String(opening.get("type", "door")).strip_edges().to_lower()
		var position_ratio: float = clampf(float(opening.get("position", 0.5)), 0.0, 1.0)
		var width: float = maxf(0.25, float(opening.get("width", 1.2)))
		var center_dist: float = position_ratio * total_length
		var gap_start: float = clampf(center_dist - (width * 0.5), 0.0, total_length)
		var gap_end: float = clampf(center_dist + (width * 0.5), 0.0, total_length)
		if gap_end - gap_start < 0.08:
			continue
		# NEW: Windows now create mesh gaps (like doors) instead of shader overlays
		if opening_type == "window":
			var window_height: float = maxf(0.2, float(opening.get("height", 1.2)))
			var sill_height: float = maxf(0.0, float(opening.get("sill_height", 0.8)))
			var window_entry: Dictionary = {
				"center": center_dist,
				"width": width,
				"height": window_height,
				"sill_height": sill_height,
				"type": "window"
			}
			var variant: String = String(opening.get("variant", "")).strip_edges()
			if variant != "":
				window_entry["variant"] = variant
			window_instances.append(window_entry)
		gaps.append({
			"from": gap_start,
			"to": gap_end,
			"type": opening_type,
			"center": center_dist,
			"width": width,
			"height": float(opening.get("height", 1.2)),
			"sill_height": float(opening.get("sill_height", 0.0)),
			"variant": String(opening.get("variant", ""))
		})

	gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("from", 0.0)) < float(b.get("from", 0.0)))
	var intervals: Array[Dictionary] = []
	var cursor: float = 0.0
	for gap in gaps:
		var gap_from: float = float(gap.get("from", 0.0))
		var gap_to: float = float(gap.get("to", 0.0))
		if gap_from > cursor:
			intervals.append({"from": cursor, "to": gap_from})
		cursor = maxf(cursor, gap_to)
		opening_instances.append({
			"center": float(gap.get("center", 0.0)),
			"width": float(gap.get("width", 0.0)),
			"type": String(gap.get("type", "door")),
			"height": float(gap.get("height", 1.2)),
			"sill_height": float(gap.get("sill_height", 0.0)),
			"variant": String(gap.get("variant", ""))
		})
	if cursor < total_length:
		intervals.append({"from": cursor, "to": total_length})

	if intervals.is_empty() and opening_instances.is_empty():
		intervals.append({"from": 0.0, "to": total_length})
	return intervals

func _find_window_opening_for_piece(window_instances: Array[Dictionary], piece_start: float, piece_length: float) -> Dictionary:
	if window_instances.is_empty():
		return {}
	var piece_end: float = piece_start + piece_length
	for opening in window_instances:
		var center: float = float(opening.get("center", 0.0))
		if center >= piece_start - 0.001 and center <= piece_end + 0.001:
			return opening
	return {}

func _apply_window_cutout(node: Node, seg: WallSegment, piece_length: float, piece_start: float, opening: Dictionary, is_preview: bool) -> void:
	# PREVIEW-ONLY: Window cutout shader is now only used for preview visualization
	# In final build, windows use actual mesh gaps instead of shader cutout
	if not is_preview or node == null or opening.is_empty():
		return
	var opening_width: float = maxf(0.25, float(opening.get("width", 1.2)))
	var opening_height: float = maxf(0.2, float(opening.get("height", 1.2)))
	var sill_height: float = maxf(0.0, float(opening.get("sill_height", 0.8)))
	var wall_height: float = maxf(0.2, seg.height if seg.height > 0.0 else default_wall_height)
	var cutout_width: float = minf(opening_width, maxf(0.2, piece_length - 0.02))
	var cutout_height: float = minf(opening_height, maxf(0.2, wall_height - sill_height - 0.02))
	if cutout_width <= 0.0 or cutout_height <= 0.0:
		return
	var cutout_center: Vector2 = Vector2(
		float(opening.get("center", 0.0)) - (piece_start + (piece_length * 0.5)),
		(sill_height + (cutout_height * 0.5)) - (wall_height * 0.5)
	)
	_apply_window_cutout_recursive(node, cutout_center, Vector2(cutout_width, cutout_height), is_preview)

func _apply_window_cutout_recursive(node: Node, cutout_center: Vector2, cutout_size: Vector2, is_preview: bool) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mat: Material = mesh_node.material_override
		# Apply cutout if material is a shader (Tudor walls and other shader-based walls)
		if mat is ShaderMaterial:
			var shader_mat := (mat as ShaderMaterial).duplicate(true)
			shader_mat.set_shader_parameter("use_window_cutout", true)
			shader_mat.set_shader_parameter("window_cutout_center", cutout_center)
			shader_mat.set_shader_parameter("window_cutout_size", cutout_size)
			mesh_node.material_override = shader_mat
			mesh_node.material_overlay = null
		# For non-shader materials, window cutout won't work (future: implement alternative method)
	for child in node.get_children():
		_apply_window_cutout_recursive(child, cutout_center, cutout_size, is_preview)

func _place_opening_piece(
	parent: Node3D,
	seg: WallSegment,
	base_start: Vector3,
	direction: Vector3,
	yaw: float,
	opening: Dictionary,
	is_preview: bool,
	tint: Color
) -> void:
	var center_dist: float = float(opening.get("center", 0.0))
	var opening_type: String = String(opening.get("type", "door")).to_lower()
	var opening_width: float = maxf(0.25, float(opening.get("width", 1.2)))
	var opening_height: float = maxf(0.2, float(opening.get("height", 1.2)))
	var sill_height: float = maxf(0.0, float(opening.get("sill_height", 0.8)))
	
	# Calculate the position in world space where the opening is
	var opening_pos: Vector3 = base_start + (direction * center_dist)
	var opening_base_y: float = _sample_segment_height(seg, opening_pos)
	var wall_height: float = maxf(0.2, seg.height if seg.height > 0.0 else default_wall_height)
	
	var snapped_len: int = 4 if opening_width >= 3.0 else 2
	var key: String = "%s_wall_%s_%dm" % [seg.wall_type, opening_type, snapped_len]
	if not _has_prefab(key):
		key = "%s_wall_%s_4m" % [seg.wall_type, opening_type]
	if not _has_prefab(key):
		key = "%s_wall_%s_2m" % [seg.wall_type, opening_type]
	if not _has_prefab(key):
		return

	var piece_len: float = 4.0 if key.ends_with("_4m") else 2.0
	var node: Node3D = _instantiate_prefab_or_box(parent, seg, key, piece_len, is_preview, tint, opening)
	node.position = Vector3(opening_pos.x, opening_base_y, opening_pos.z)
	node.rotation = Vector3(0.0, yaw, 0.0)

	if opening_type == "window":
		_place_window_in_gap(parent, seg, opening_pos, opening_base_y, direction, yaw, opening_width, opening_height, sill_height, wall_height, opening, is_preview, tint)

func _place_window_in_gap(
	parent: Node3D,
	seg: WallSegment,
	gap_pos: Vector3,
	gap_base_y: float,
	direction: Vector3,
	yaw: float,
	opening_width: float,
	opening_height: float,
	sill_height: float,
	wall_height: float,
	opening: Dictionary,
	is_preview: bool,
	tint: Color
) -> void:
	# Try to load the Tudor window prefab
	var tudor_window_scene_path: String = "res://assets/prefabs/walls/tudor/tudor_window.tscn"
	var tudor_window_open_scene_path: String = "res://assets/prefabs/walls/tudor/tudor_window_open.tscn"
	var tudor_window_gltf_path: String = "res://assets/textures/walls/tudor_window/scene.gltf"
	
	var node: Node3D = null
	var packed_scene: PackedScene = null
	
	# Try tudor_window.tscn first (main prefab)
	if ResourceLoader.exists(tudor_window_scene_path):
		packed_scene = load(tudor_window_scene_path) as PackedScene
		if packed_scene != null:
			var inst: Node = packed_scene.instantiate()
			if inst is Node3D:
				node = inst as Node3D
	
	# Fallback to tudor_window_open.tscn
	if node == null and ResourceLoader.exists(tudor_window_open_scene_path):
		packed_scene = load(tudor_window_open_scene_path) as PackedScene
		if packed_scene != null:
			var inst: Node = packed_scene.instantiate()
			if inst is Node3D:
				node = inst as Node3D
	
	# Fallback to GLTF
	if node == null and ResourceLoader.exists(tudor_window_gltf_path):
		packed_scene = load(tudor_window_gltf_path) as PackedScene
		if packed_scene != null:
			var inst: Node = packed_scene.instantiate()
			if inst is Node3D:
				node = inst as Node3D
	
	# If still no node, create a simple placeholder box to show the gap
	if node == null:
		node = _create_window_placeholder(opening_width, opening_height, is_preview)
	
	if node == null:
		return
	
	parent.add_child(node)
	
	# Position the window in the gap
	# Window should be centered horizontally in the gap
	# Vertically: base_y - half_wall_height + sill_height + half_opening_height
	var window_center_y: float = gap_base_y - (wall_height * 0.5) + sill_height + (opening_height * 0.5)
	node.position = Vector3(gap_pos.x, window_center_y, gap_pos.z)
	node.rotation = Vector3(0.0, yaw, 0.0)
	
	# Scale the window to fit the opening
	_fit_window_instance_to_opening(node, opening_width * 0.95, opening_height * 0.95)
	
	# Apply materials (frame + glass)
	_apply_window_materials(node, seg, opening, is_preview, tint)

func _create_window_placeholder(width: float, height: float, is_preview: bool) -> Node3D:
	# Create a simple box as a placeholder if no prefab is found
	var node := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(width, height, 0.05)
	mesh_instance.mesh = box_mesh
	
	# Apply transparent glass material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if not is_preview else BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.82, 0.9, 1.0, 0.25)
	mat.roughness = 0.08
	mat.metallic = 0.0
	mesh_instance.material_override = mat
	
	node.add_child(mesh_instance)
	return node

func _fit_window_instance_to_opening(node: Node3D, target_width: float, target_height: float) -> void:
	if node == null:
		return
	var local_aabb: AABB = _compute_local_aabb(node, Transform3D.IDENTITY)
	if local_aabb.size.x <= 0.0001 or local_aabb.size.y <= 0.0001:
		node.scale = Vector3(target_width, target_height, 1.0)
		return
	var sx: float = target_width / local_aabb.size.x
	var sy: float = target_height / local_aabb.size.y
	var sz: float = minf(sx, sy)
	node.scale = Vector3(sx, sy, sz)
	var local_center: Vector3 = local_aabb.position + (local_aabb.size * 0.5)
	node.translate_object_local(Vector3(-local_center.x * sx, -local_center.y * sy, 0.0))

func _compute_local_aabb(node: Node, to_root: Transform3D) -> AABB:
	var has_box: bool = false
	var result: AABB = AABB(Vector3.ZERO, Vector3.ZERO)
	if node is Node3D:
		var n3d := node as Node3D
		var current_xf: Transform3D = to_root * n3d.transform
		if n3d is MeshInstance3D:
			var mesh_node := n3d as MeshInstance3D
			if mesh_node.mesh != null:
				var laabb: AABB = mesh_node.mesh.get_aabb()
				var pts: Array[Vector3] = [
					laabb.position,
					laabb.position + Vector3(laabb.size.x, 0.0, 0.0),
					laabb.position + Vector3(0.0, laabb.size.y, 0.0),
					laabb.position + Vector3(0.0, 0.0, laabb.size.z),
					laabb.position + Vector3(laabb.size.x, laabb.size.y, 0.0),
					laabb.position + Vector3(laabb.size.x, 0.0, laabb.size.z),
					laabb.position + Vector3(0.0, laabb.size.y, laabb.size.z),
					laabb.position + laabb.size
				]
				for p in pts:
					var wp: Vector3 = current_xf * p
					if not has_box:
						result = AABB(wp, Vector3.ZERO)
						has_box = true
					else:
						result = result.expand(wp)
		for child in n3d.get_children():
			var child_box: AABB = _compute_local_aabb(child, current_xf)
			if child_box.size.length_squared() > 0.0:
				if not has_box:
					result = child_box
					has_box = true
				else:
					result = result.merge(child_box)
	if not has_box:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	return result

func _instantiate_tudor_window(window_pos: Vector3, center_y: float, yaw: float, width: float, height: float, sill: float, variant: String = "") -> void:
	# Load and instantiate the Tudor window prefab in the gap
	var tudor_window_scene_path: String = "res://assets/prefabs/walls/tudor/tudor_window.tscn"
	var tudor_window_open_scene_path: String = "res://assets/prefabs/walls/tudor/tudor_window_open.tscn"
	var tudor_window_gltf_path: String = "res://assets/textures/walls/tudor_window/scene.gltf"
	
	var window_node: Node3D = null
	
	# Try tudor_window.tscn first (primary)
	if ResourceLoader.exists(tudor_window_scene_path):
		var packed: PackedScene = load(tudor_window_scene_path) as PackedScene
		if packed != null:
			var inst: Node = packed.instantiate()
			if inst is Node3D:
				window_node = inst as Node3D
	
	# Fallback to tudor_window_open.tscn
	if window_node == null and ResourceLoader.exists(tudor_window_open_scene_path):
		var packed: PackedScene = load(tudor_window_open_scene_path) as PackedScene
		if packed != null:
			var inst: Node = packed.instantiate()
			if inst is Node3D:
				window_node = inst as Node3D
	
	# Fallback to GLTF
	if window_node == null and ResourceLoader.exists(tudor_window_gltf_path):
		var packed: PackedScene = load(tudor_window_gltf_path) as PackedScene
		if packed != null:
			var inst: Node = packed.instantiate()
			if inst is Node3D:
				window_node = inst as Node3D
	
	# If still no node, create simple placeholder box
	if window_node == null:
		window_node = Node3D.new()
		var mesh_inst := MeshInstance3D.new()
		var box_mesh := BoxMesh.new()
		box_mesh.size = Vector3(width, height, 0.05)
		mesh_inst.mesh = box_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.82, 0.9, 1.0, 0.3)
		mesh_inst.material_override = mat
		window_node.add_child(mesh_inst)
	
	if window_node == null:
		return
	
	# Add to persistent openings root so rebuilds do not delete it
	_ensure_openings_root()
	_openings_root.add_child(window_node)
	
	# Position window in the gap
	window_node.position = Vector3(window_pos.x, center_y, window_pos.z)
	window_node.rotation = Vector3(0.0, yaw, 0.0)
	
	# Scale window to fit opening
	_fit_window_instance_to_opening(window_node, width * 0.95, height * 0.95)
	
	# Apply materials (frame + glass)
	_apply_window_materials_to_prefab(window_node)

func _place_cap(parent: Node3D, seg: WallSegment, point: Vector3, yaw: float, is_start: bool, is_preview: bool, tint: Color) -> void:
	var key: String = "%s_wall_end_cap" % seg.wall_type
	if not _has_prefab(key):
		return
	var node: Node3D = _instantiate_prefab_or_box(parent, seg, key, 0.6, is_preview, tint)
	node.position = Vector3(point.x, _sample_segment_height(seg, point), point.z)
	node.rotation = Vector3(0.0, yaw, 0.0)

func _build_junctions(target_parent: Node3D, source_segments: Array, is_preview: bool) -> void:
	var junction_root := Node3D.new()
	junction_root.name = "Junctions"
	target_parent.add_child(junction_root)
	for cluster in _cluster_data:
		var count: int = int(cluster.get("count", 0))
		if count < 2:
			continue
		var junction_type: String = String(cluster.get("junction", ""))
		if junction_type == "":
			continue
		var position: Vector3 = cluster.get("position", Vector3.ZERO)
		var wall_type: String = _cluster_wall_type(cluster, source_segments)
		var tint: Color = Color(0.35, 0.95, 1.0, 0.28) if is_preview else Color.WHITE
		_place_junction_piece(junction_root, wall_type, position, junction_type, cluster, is_preview, tint)

func _place_junction_piece(parent: Node3D, wall_type: String, position: Vector3, junction_type: String, cluster: Dictionary, is_preview: bool, tint: Color) -> void:
	var key: String = ""
	var is_tudor_cardinal: bool = false
	if key == "":
		match junction_type:
			"l_corner":
				var inner: String = "%s_corner_inner_90" % wall_type
				var outer: String = "%s_corner_outer_90" % wall_type
				key = inner if _has_prefab(inner) else outer
			"t_junction":
				key = "%s_junction_t" % wall_type
			"x_junction":
				key = "%s_junction_x" % wall_type

	if key == "":
		return
	var seg := WallSegment.new()
	seg.wall_type = wall_type
	seg.height = default_wall_height
	var node: Node3D = _instantiate_prefab_or_box(parent, seg, key, 1.0, is_preview, tint)
	
	if wall_type == "tudor":
		_apply_tudor_corner_material(node, is_preview)
		# Get actual segment heights from cluster endpoints and use the maximum
		var max_height: float = default_wall_height
		var base_y: float = position.y
		var endpoints: Array = cluster.get("endpoints", [])
		var has_base_sample: bool = false
		
		# Find maximum height and base Y from connecting segments
		for endpoint in endpoints:
			var seg_idx: int = int((endpoint as Dictionary).get("seg_idx", -1))
			if seg_idx >= 0 and seg_idx < _cluster_source_segments.size() and _cluster_source_segments[seg_idx] != null:
				var src_seg: Variant = _cluster_source_segments[seg_idx]
				var seg_height: float = src_seg.height if src_seg.height > 0.0 else default_wall_height
				max_height = maxf(max_height, seg_height)
				# Use the lowest connected base so the corner beam always spans full height.
				if not has_base_sample:
					base_y = minf(src_seg.start.y, src_seg.end.y)
					has_base_sample = true
				else:
					base_y = minf(base_y, minf(src_seg.start.y, src_seg.end.y))
		
		# Position beam at center height and scale vertically
		# The BoxMesh is centered at origin, so positioning at base + height/2 ensures
		# the beam extends from base_y to base_y + max_height
		var scale_factor: float = max_height / 3.4
		var centered_y: float = base_y + (max_height * 0.5)
		node.position = Vector3(position.x, centered_y, position.z)
		node.scale.y = scale_factor
	else:
		node.position = position
	# Cardinal corner stays aligned to cardinal axes (no Y rotation)
	# Non-cardinal corners get rotated to face the junction bisector
	if not is_tudor_cardinal:
		node.rotation = Vector3(0.0, _cluster_rotation(cluster), 0.0)
	if not is_preview:
		for endpoint in cluster.get("endpoints", []):
			if endpoint is Dictionary:
				node.set_meta("wall_segment_idx", int((endpoint as Dictionary).get("seg_idx", -1)))

func _build_junction_markers(parent: Node3D, feedback: Dictionary) -> void:
	if not feedback.has("junction_points"):
		return
	var points: Array = feedback.get("junction_points", [])
	if points.is_empty():
		return
	var marker_root := Node3D.new()
	marker_root.name = "JunctionMarkers"
	parent.add_child(marker_root)
	for p in points:
		if p is not Vector3:
			continue
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.18
		sphere.height = 0.36
		marker.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.35, 1.0, 0.42, 0.55)
		mat.emission_enabled = true
		mat.emission = Color(0.35, 1.0, 0.42, 1.0)
		mat.emission_energy_multiplier = 1.0
		marker.material_override = mat
		marker_root.add_child(marker)
		marker.position = (p as Vector3) + Vector3(0.06, 0.12, 0.06)

func _instantiate_prefab_or_box(parent: Node3D, seg: WallSegment, key: String, piece_length: float, is_preview: bool, tint: Color, opening: Dictionary = {}) -> Node3D:
	var packed: PackedScene = _resolve_prefab(key)
	if packed != null:
		var instance := packed.instantiate()
		if instance is Node3D:
			var node := instance as Node3D
			parent.add_child(node)
			if opening.is_empty():
				_apply_piece_materials(node, seg, piece_length, is_preview, tint)
			else:
				_apply_opening_materials(node, seg, piece_length, is_preview, tint, opening)
			_apply_shadow_tuning(node)
			return node
		instance.queue_free()

	var node_box := Node3D.new()
	parent.add_child(node_box)
	var wall := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(maxf(piece_length, 0.05), maxf(0.2, seg.height if seg.height > 0.0 else default_wall_height), maxf(0.05, default_wall_thickness))
	wall.mesh = mesh
	node_box.add_child(wall)

	if seg.wall_type == "tudor":
		wall.material_override = _get_tudor_material(seg, piece_length, is_preview, tint)
		if not is_preview:
			wall.material_overlay = _build_ink_edge_overlay(false)
	else:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if is_preview else BaseMaterial3D.SHADING_MODE_PER_PIXEL
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if is_preview else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.albedo_color = tint if is_preview else Color(0.76, 0.76, 0.78, 1.0)
		mat.roughness = 0.92
		if is_preview:
			mat.emission_enabled = true
			mat.emission = Color(tint.r, tint.g, tint.b, 1.0)
			mat.emission_energy_multiplier = 0.7
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		else:
			mat.next_pass = _build_outline_shell_pass()
		wall.material_override = mat

	if not is_preview:
		var static_body := StaticBody3D.new()
		static_body.name = "WallCollision"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		static_body.add_child(shape)
		static_body.set_meta("wall_segment_idx", -1)
		static_body.set_meta("wall_hit_type", "piece")
		node_box.add_child(static_body)
	return node_box

func _apply_piece_materials(node: Node, seg: WallSegment, piece_length: float, is_preview: bool, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if seg != null and seg.wall_type == "tudor":
			mesh_node.material_override = _get_tudor_material(seg, piece_length, is_preview, tint)
			mesh_node.material_overlay = _build_ink_edge_overlay(is_preview)
		elif is_preview:
			mesh_node.material_override = _get_preview_material(tint)
			mesh_node.material_overlay = _build_ink_edge_overlay(true)
		else:
			mesh_node.material_override = _runtime_wall_material if _runtime_wall_material != null else wall_material
			mesh_node.material_overlay = _build_ink_edge_overlay(false)
	for child in node.get_children():
		_apply_piece_materials(child, seg, piece_length, is_preview, tint)

func _apply_opening_materials(node: Node, seg: WallSegment, piece_length: float, is_preview: bool, tint: Color, opening: Dictionary) -> void:
	_apply_window_materials(node, seg, opening, is_preview, tint)

func _apply_shadow_tuning(node: Node) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		gi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	for child in node.get_children():
		_apply_shadow_tuning(child)

func _has_prefab(key: String) -> bool:
	return _resolve_prefab(key) != null

func _resolve_prefab(key: String) -> PackedScene:
	if key == "":
		return null
	if _prefab_cache.has(key):
		return _prefab_cache[key] as PackedScene
	if not wall_prefabs.has(key):
		_prefab_cache[key] = null
		return null
	var value: Variant = wall_prefabs[key]
	if value is PackedScene:
		_prefab_cache[key] = value as PackedScene
		return _prefab_cache[key] as PackedScene
	if value is String:
		var loaded: PackedScene = load(value as String) as PackedScene
		_prefab_cache[key] = loaded
		return loaded
	_prefab_cache[key] = null
	return null

func _add_segment_collision(parent: Node3D, idx: int, seg: WallSegment) -> void:
	var delta: Vector3 = seg.end - seg.start
	delta.y = 0.0
	var length: float = delta.length()
	if length < 0.1:
		return
	var body := StaticBody3D.new()
	body.name = "SegmentHit_%d" % idx
	body.set_meta("wall_segment_idx", idx)
	body.set_meta("wall_hit_type", "segment")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, maxf(0.45, seg.height), maxf(0.4, default_wall_thickness * 2.2))
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	body.position = Vector3(seg.get_midpoint().x, _sample_segment_height(seg, seg.get_midpoint()), seg.get_midpoint().z)
	body.rotation = Vector3(0.0, atan2(delta.z, delta.x), 0.0)

func _build_endpoint_clusters(source_segments: Array) -> void:
	_cluster_data.clear()
	_endpoint_cluster_map.clear()
	_cluster_source_segments = source_segments
	for i in range(source_segments.size()):
		var seg: WallSegment = source_segments[i]
		if seg == null:
			continue
		var dir: Vector3 = seg.get_direction()
		dir.y = 0.0
		if dir.length_squared() <= 0.000001:
			continue
		dir = dir.normalized()
		_register_endpoint(seg.start, i, true, dir)
		_register_endpoint(seg.end, i, false, -dir)

	for cluster in _cluster_data:
		var count: int = int(cluster.get("count", 0))
		cluster["junction"] = _classify_cluster(cluster)

func _register_endpoint(pos: Vector3, seg_idx: int, is_start: bool, outward_dir: Vector3) -> void:
	var cluster_idx: int = -1
	for i in range(_cluster_data.size()):
		var cluster_pos: Vector3 = _cluster_data[i].get("position", Vector3.ZERO)
		if cluster_pos.distance_to(pos) <= endpoint_tolerance:
			cluster_idx = i
			break
	if cluster_idx < 0:
		cluster_idx = _cluster_data.size()
		_cluster_data.append({
			"position": pos,
			"endpoints": [],
			"count": 0,
			"junction": ""
		})

	var endpoints: Array = _cluster_data[cluster_idx].get("endpoints", [])
	endpoints.append({
		"seg_idx": seg_idx,
		"is_start": is_start,
		"dir": outward_dir
	})
	_cluster_data[cluster_idx]["endpoints"] = endpoints
	_cluster_data[cluster_idx]["count"] = endpoints.size()

	var summed: Vector3 = Vector3.ZERO
	for endpoint in endpoints:
		var ref_seg: int = int(endpoint.get("seg_idx", -1))
		var ref_start: bool = bool(endpoint.get("is_start", true))
		if ref_seg >= 0 and ref_seg < _cluster_source_segments.size() and _cluster_source_segments[ref_seg] != null:
			var ref_pos: Vector3 = _cluster_source_segments[ref_seg].start if ref_start else _cluster_source_segments[ref_seg].end
			summed += ref_pos
	if endpoints.size() > 0:
		_cluster_data[cluster_idx]["position"] = summed / float(endpoints.size())

	_endpoint_cluster_map[_endpoint_key(seg_idx, is_start)] = cluster_idx

func _endpoint_key(seg_idx: int, is_start: bool) -> String:
	return "%d:%d" % [seg_idx, 1 if is_start else 0]

func _get_endpoint_info(seg_idx: int, is_start: bool) -> Dictionary:
	var key: String = _endpoint_key(seg_idx, is_start)
	if not _endpoint_cluster_map.has(key):
		return {"count": 1, "junction": ""}
	var cluster_idx: int = int(_endpoint_cluster_map[key])
	if cluster_idx < 0 or cluster_idx >= _cluster_data.size():
		return {"count": 1, "junction": ""}
	return {
		"count": int(_cluster_data[cluster_idx].get("count", 1)),
		"junction": String(_cluster_data[cluster_idx].get("junction", ""))
	}

func _classify_cluster(cluster: Dictionary) -> String:
	var count: int = int(cluster.get("count", 0))
	if count < 2:
		return ""
	if count >= 4:
		return "x_junction"
	if count == 3:
		return "t_junction"

	var endpoints: Array = cluster.get("endpoints", [])
	if endpoints.size() != 2:
		return ""
	var a: Vector3 = (endpoints[0] as Dictionary).get("dir", Vector3.FORWARD)
	var b: Vector3 = (endpoints[1] as Dictionary).get("dir", Vector3.BACK)
	a.y = 0.0
	b.y = 0.0
	if a.length_squared() <= 0.000001 or b.length_squared() <= 0.000001:
		return ""
	var angle: float = rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))
	if angle > 40.0 and angle < 140.0:
		return "l_corner"
	return ""

func _cluster_wall_type(cluster: Dictionary, source_segments: Array) -> String:
	var endpoints: Array = cluster.get("endpoints", [])
	if endpoints.is_empty():
		return "stone"
	var idx: int = int((endpoints[0] as Dictionary).get("seg_idx", -1))
	if idx >= 0 and idx < source_segments.size() and source_segments[idx] != null:
		return source_segments[idx].wall_type
	return "stone"

func _cluster_rotation(cluster: Dictionary) -> float:
	var endpoints: Array = cluster.get("endpoints", [])
	if endpoints.is_empty():
		return 0.0
	var avg: Vector3 = Vector3.ZERO
	for endpoint in endpoints:
		var dir: Vector3 = (endpoint as Dictionary).get("dir", Vector3.FORWARD)
		dir.y = 0.0
		if dir.length_squared() > 0.000001:
			avg += dir.normalized()
	if avg.length_squared() <= 0.000001:
		var fallback: Vector3 = (endpoints[0] as Dictionary).get("dir", Vector3.FORWARD)
		return atan2(fallback.z, fallback.x)
	return atan2(avg.z, avg.x)

func _sample_segment_height(seg: WallSegment, sample_pos: Vector3) -> float:
	var wall_height: float = maxf(0.2, _resolved_height(seg))
	var base_y: float = maxf(seg.start.y, seg.end.y)
	return base_y + (wall_height * 0.5)

func _resolved_height(seg: WallSegment) -> float:
	var base: float = seg.height if seg.height > 0.0 else default_wall_height
	if random_height_jitter <= 0.0:
		return base
	var h: int = int(absf(seg.start.x * 73.11 + seg.start.z * 41.97 + seg.end.x * 19.37 + seg.end.z * 61.63) * 1000.0)
	var n: float = float((h % 1000)) / 1000.0
	return base + ((n - 0.5) * 2.0 * random_height_jitter)

func _ensure_wall_material() -> void:
	_preview_material_cache.clear()
	_tudor_material_cache.clear()
	if wall_material == null and ResourceLoader.exists(DEFAULT_WALL_MATERIAL_PATH):
		wall_material = load(DEFAULT_WALL_MATERIAL_PATH) as Material
	if foundation_material == null and ResourceLoader.exists(DEFAULT_FOUNDATION_MATERIAL_PATH):
		foundation_material = load(DEFAULT_FOUNDATION_MATERIAL_PATH) as Material
	if wall_material is ShaderMaterial:
		_runtime_wall_material = (wall_material as ShaderMaterial).duplicate(true)
	elif wall_material is BaseMaterial3D:
		_runtime_wall_material = (wall_material as BaseMaterial3D).duplicate(true)
	else:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.76, 0.75, 0.73, 1.0)
		fallback.roughness = 0.92
		fallback.metallic = 0.0
		_runtime_wall_material = fallback
	if foundation_material != null:
		if foundation_material is ShaderMaterial:
			_runtime_foundation_material = (foundation_material as ShaderMaterial).duplicate(true)
		elif foundation_material is BaseMaterial3D:
			_runtime_foundation_material = (foundation_material as BaseMaterial3D).duplicate(true)
		else:
			_runtime_foundation_material = foundation_material
	else:
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color(0.43, 0.42, 0.4, 1.0)
		fmat.roughness = 0.95
		fmat.metallic = 0.0
		_runtime_foundation_material = fmat

func _get_foundation_material(is_preview: bool, wall_type: String, width_x: float = 1.0, width_z: float = 1.0) -> Material:
	var base_mat: Material = _runtime_foundation_material
	if base_mat == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.43, 0.42, 0.4, 1.0)
		base_mat = fallback
	if base_mat is ShaderMaterial:
		var sm := (base_mat as ShaderMaterial).duplicate(true)
		sm.set_shader_parameter("is_preview", is_preview)
		sm.set_shader_parameter("preview_alpha", 0.35 if is_preview else 0.0)
		return sm
	var bm: BaseMaterial3D
	if base_mat is BaseMaterial3D:
		bm = (base_mat as BaseMaterial3D).duplicate(true)
	else:
		bm = StandardMaterial3D.new()
		(bm as StandardMaterial3D).albedo_color = Color(0.43, 0.42, 0.4, 1.0)
	if foundation_material == null:
		if wall_type == "tudor":
			bm.albedo_color = Color(0.44, 0.38, 0.31, 1.0)
		else:
			bm.albedo_color = Color(0.46, 0.46, 0.44, 1.0)
	var repeat_m: float = maxf(0.1, foundation_texture_repeat_m)
	var repeat_x: float = maxf(1.0, width_x / repeat_m)
	var repeat_z: float = maxf(1.0, width_z / repeat_m)
	bm.uv1_scale = Vector3(repeat_x, repeat_z, 1.0)
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if is_preview else BaseMaterial3D.TRANSPARENCY_DISABLED
	if is_preview:
		bm.albedo_color.a = 0.38
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	return bm

func _segment_touches_point(seg: WallSegment, p: Vector3) -> bool:
	if seg == null:
		return false
	return seg.start.distance_to(p) <= endpoint_tolerance or seg.end.distance_to(p) <= endpoint_tolerance

func _segments_connected(a: WallSegment, b: WallSegment) -> bool:
	if a == null or b == null:
		return false
	return (
		a.start.distance_to(b.start) <= endpoint_tolerance
		or a.start.distance_to(b.end) <= endpoint_tolerance
		or a.end.distance_to(b.start) <= endpoint_tolerance
		or a.end.distance_to(b.end) <= endpoint_tolerance
	)

func _collect_connected_segment_indices(seed_indices: Array[int]) -> Array[int]:
	if seed_indices.is_empty():
		return []
	var out: Array[int] = []
	var visited: Dictionary = {}
	var queue: Array[int] = []
	for idx in seed_indices:
		if idx >= 0 and idx < segments.size() and segments[idx] != null and not visited.has(idx):
			visited[idx] = true
			queue.append(idx)
	while not queue.is_empty():
		var current: int = int(queue.pop_front())
		out.append(current)
		var current_seg: WallSegment = segments[current]
		for i in range(segments.size()):
			if visited.has(i):
				continue
			var other: WallSegment = segments[i]
			if other == null:
				continue
			if _segments_connected(current_seg, other):
				visited[i] = true
				queue.append(i)
	return out

func _component_master_height(component: Array[int]) -> float:
	if component.is_empty():
		return maxf(0.2, default_wall_height)
	var highest: float = 0.2
	for idx in component:
		if idx >= 0 and idx < segments.size() and segments[idx] != null:
			highest = maxf(highest, segments[idx].height)
	if highest <= 0.2:
		return maxf(0.2, default_wall_height)
	return highest

func _get_preview_material(tint: Color) -> Material:
	var preview_tint: Color = _resolve_base_tint_color(true)
	if tint.a > 0.0:
		preview_tint.a = tint.a
	var key: String = "%.3f_%.3f_%.3f_%.3f" % [preview_tint.r, preview_tint.g, preview_tint.b, preview_tint.a]
	if _preview_material_cache.has(key):
		return _preview_material_cache[key] as Material
	var mat: Material = null
	if _runtime_wall_material is ShaderMaterial:
		var sm := (_runtime_wall_material as ShaderMaterial).duplicate(true)
		sm.set_shader_parameter("tint_color", preview_tint)
		sm.set_shader_parameter("preview_alpha", preview_tint.a)
		sm.set_shader_parameter("is_preview", true)
		mat = sm
	elif _runtime_wall_material is BaseMaterial3D:
		var bm := (_runtime_wall_material as BaseMaterial3D).duplicate(true)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.albedo_color = preview_tint
		bm.emission_enabled = true
		bm.emission = Color(preview_tint.r, preview_tint.g, preview_tint.b, 1.0)
		bm.emission_energy_multiplier = 0.6
		bm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = bm
	else:
		var fb := StandardMaterial3D.new()
		fb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fb.albedo_color = preview_tint
		fb.emission_enabled = true
		fb.emission = Color(preview_tint.r, preview_tint.g, preview_tint.b, 1.0)
		fb.emission_energy_multiplier = 0.6
		mat = fb
	_preview_material_cache[key] = mat
	return mat

func _get_tudor_material(seg: WallSegment, piece_length: float, is_preview: bool, tint: Color) -> Material:
	if _tudor_textures.is_empty():
		return _get_preview_material(tint) if is_preview else (_runtime_wall_material if _runtime_wall_material != null else wall_material)
	var idx: int = _get_tudor_variant_index(seg)
	var alpha_v: float = clampf(tint.a if is_preview else 1.0, 0.0, 1.0)
	var tile_x: float = maxf(0.25, piece_length / maxf(0.2, tudor_panel_repeat_m))
	var tile_y: float = maxf(0.25, maxf(seg.height, 0.5) / maxf(0.2, tudor_vertical_repeat_m))
	var key: String = "%d_%d_%.3f_%.3f_%.3f" % [idx, 1 if is_preview else 0, alpha_v, tile_x, tile_y]
	if _tudor_material_cache.has(key):
		return _tudor_material_cache[key] as Material

	var tex: Texture2D = _tudor_textures[idx]
	var mat: Material = null
	if _runtime_wall_material is ShaderMaterial:
		var sm := (_runtime_wall_material as ShaderMaterial).duplicate(true)
		sm.set_shader_parameter("use_albedo_tex", true)
		sm.set_shader_parameter("albedo_tex", tex)
		sm.set_shader_parameter("uv_tiling", Vector2(tile_x, tile_y))
		sm.set_shader_parameter("tint_color", Color(1.0, 1.0, 1.0, 1.0))
		sm.set_shader_parameter("is_preview", is_preview)
		sm.set_shader_parameter("preview_alpha", alpha_v if is_preview else 0.0)
		mat = sm
	elif _runtime_wall_material is BaseMaterial3D:
		var bm := (_runtime_wall_material as BaseMaterial3D).duplicate(true)
		bm.albedo_texture = tex
		bm.uv1_scale = Vector3(tile_x, tile_y, 1.0)
		bm.albedo_color = Color(1.0, 1.0, 1.0, alpha_v if is_preview else 1.0)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if is_preview else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat = bm
	else:
		var fb := StandardMaterial3D.new()
		fb.albedo_texture = tex
		fb.uv1_scale = Vector3(tile_x, tile_y, 1.0)
		fb.albedo_color = Color(1.0, 1.0, 1.0, alpha_v if is_preview else 1.0)
		fb.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if is_preview else BaseMaterial3D.TRANSPARENCY_DISABLED
		mat = fb

	_tudor_material_cache[key] = mat
	return mat

func _get_tudor_variant_index(seg: WallSegment) -> int:
	if _tudor_textures.is_empty():
		return 0
	var h: float = absf(seg.start.x * 13.31 + seg.start.z * 71.77 + seg.end.x * 29.17 + seg.end.z * 91.93)
	return int(floor(h * 10.0)) % _tudor_textures.size()

func _load_tudor_textures() -> void:
	_tudor_textures.clear()
	_tudor_material_cache.clear()
	_tudor_corner_material = null
	var paths: Array[String] = []
	if not tudor_texture_paths.is_empty():
		for p in tudor_texture_paths:
			if p.strip_edges() != "":
				paths.append(p)
	else:
		var dir_path: String = tudor_texture_dir if tudor_texture_dir.strip_edges() != "" else DEFAULT_TUDOR_TEXTURE_DIR
		var dir := DirAccess.open(dir_path)
		if dir != null:
			dir.list_dir_begin()
			while true:
				var name := dir.get_next()
				if name == "":
					break
				if dir.current_is_dir() or name.begins_with("."):
					continue
				if name.to_lower().begins_with("tudor") and name.to_lower().ends_with(".png"):
					paths.append("%s/%s" % [dir_path, name])
			dir.list_dir_end()
	paths.sort()
	for p in paths:
		var tex: Texture2D = load(p) as Texture2D
		if tex != null:
			_tudor_textures.append(tex)

func _segment_corner_setback(seg: WallSegment) -> float:
	if seg == null:
		return junction_setback
	if seg.wall_type == "tudor":
		return clampf(tudor_corner_setback, 0.05, 0.5)
	return junction_setback

func _get_tudor_corner_material(is_preview: bool) -> Material:
	if _tudor_corner_material == null:
		if _runtime_wall_material is ShaderMaterial:
			var sm := (_runtime_wall_material as ShaderMaterial).duplicate(true)
			sm.set_shader_parameter("use_albedo_tex", true)
			sm.set_shader_parameter("uv_tiling", Vector2(1.0, 1.0))
			var beam_tex: Texture2D = load(tudor_corner_texture_path) as Texture2D
			if beam_tex != null:
				sm.set_shader_parameter("albedo_tex", beam_tex)
			sm.set_shader_parameter("tint_color", Color(1.0, 1.0, 1.0, 1.0))
			_tudor_corner_material = sm
		else:
			var bm := StandardMaterial3D.new()
			bm.albedo_texture = load(tudor_corner_texture_path) as Texture2D
			bm.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			_tudor_corner_material = bm
	if _tudor_corner_material is ShaderMaterial:
		var shader_mat := (_tudor_corner_material as ShaderMaterial).duplicate(true)
		shader_mat.set_shader_parameter("is_preview", is_preview)
		shader_mat.set_shader_parameter("preview_alpha", 0.55 if is_preview else 0.0)
		return shader_mat
	if _tudor_corner_material is BaseMaterial3D:
		var base_mat := (_tudor_corner_material as BaseMaterial3D).duplicate(true)
		base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if is_preview else BaseMaterial3D.TRANSPARENCY_DISABLED
		base_mat.albedo_color.a = 0.55 if is_preview else 1.0
		return base_mat
	return _tudor_corner_material

func _apply_tudor_corner_material(node: Node, is_preview: bool) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		mesh_node.material_override = _get_tudor_corner_material(is_preview)
		mesh_node.material_overlay = _build_ink_edge_overlay(is_preview)
	for child in node.get_children():
		_apply_tudor_corner_material(child, is_preview)

func _resolve_base_tint_color(is_preview: bool) -> Color:
	var c: Color = Color(0.76, 0.75, 0.73, 0.34 if is_preview else 1.0)
	if _runtime_wall_material is ShaderMaterial:
		var sm := _runtime_wall_material as ShaderMaterial
		var shader_tint: Variant = sm.get_shader_parameter("tint_color")
		if shader_tint is Color:
			c = shader_tint
	elif _runtime_wall_material is BaseMaterial3D:
		c = (_runtime_wall_material as BaseMaterial3D).albedo_color
	if is_preview:
		c.a = clampf(c.a, 0.42, 0.68)
	else:
		c.a = 1.0
	return c

func _jitter_hash(v: Vector3) -> float:
	var h: float = absf(v.x * 12.9898 + v.z * 78.233 + v.y * 3.111)
	var n: float = sin(h) * 43758.5453
	return n - floor(n)

func _build_outline_shell_pass() -> Material:
	var shell_pass := StandardMaterial3D.new()
	shell_pass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shell_pass.albedo_color = Color(0.03, 0.03, 0.03, 1.0)
	shell_pass.cull_mode = BaseMaterial3D.CULL_FRONT
	shell_pass.grow_amount = 0.03
	shell_pass.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	return shell_pass

func _build_ink_edge_overlay(is_preview: bool) -> Material:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if is_preview else BaseMaterial3D.TRANSPARENCY_DISABLED
	overlay.albedo_color = Color(0.05, 0.05, 0.05, 0.58 if is_preview else 0.24)
	overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
	overlay.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	return overlay

func _arr_to_vec3(v: Variant) -> Vector3:
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO

func _collect_prefab_paths(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full: String = "%s/%s" % [path, name]
		if dir.current_is_dir():
			_collect_prefab_paths(full, out)
		elif name.ends_with(".tscn"):
			out.append(full)
	dir.list_dir_end()

func _collect_texture_paths(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var name := dir.get_next()
		if name == "":
			break
		if name.begins_with("."):
			continue
		var full: String = "%s/%s" % [path, name]
		if dir.current_is_dir():
			_collect_texture_paths(full, out)
			continue
		var lower_name: String = name.to_lower()
		if lower_name.ends_with(".png") or lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg"):
			out.append(full)
	dir.list_dir_end()
