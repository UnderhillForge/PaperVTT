@tool
class_name WallPieceGenerator
extends Node

const OUTPUT_DIR: String = "res://assets/prefabs/walls/modular"
const WALL_HEIGHT_M: float = 3.4
const WALL_THICKNESS_M: float = 0.22
const GRID_SNAP_M: float = 0.5

const PIECES: Array[Dictionary] = [
	{"name": "wall_straight_1m", "kind": "straight", "length": 1.0},
	{"name": "wall_straight_2m", "kind": "straight", "length": 2.0},
	{"name": "wall_straight_4m", "kind": "straight", "length": 4.0},
	{"name": "wall_straight_8m", "kind": "straight", "length": 8.0},
	{"name": "corner_outer_90", "kind": "corner_outer", "length": 4.0},
	{"name": "corner_inner_90", "kind": "corner_inner", "length": 4.0},
	{"name": "junction_t", "kind": "junction_t", "length": 4.0},
	{"name": "junction_x", "kind": "junction_x", "length": 4.0},
	{"name": "wall_window_2m", "kind": "window", "length": 2.0, "opening_width": 1.2, "opening_height": 1.7, "sill": 0.8},
	{"name": "wall_window_4m", "kind": "window", "length": 4.0, "opening_width": 1.5, "opening_height": 1.8, "sill": 0.8},
	{"name": "wall_door_2m", "kind": "door", "length": 2.0, "opening_width": 1.2, "opening_height": 2.2},
	{"name": "wall_door_4m", "kind": "door", "length": 4.0, "opening_width": 1.6, "opening_height": 2.4},
	{"name": "wall_arch_4m", "kind": "arch", "length": 4.0, "opening_width": 1.8, "opening_height": 2.5},
	{"name": "wall_end_cap", "kind": "end_cap", "length": 0.5},
	{"name": "wall_header", "kind": "header", "length": 1.5, "header_height": 0.6},
	{"name": "foundation_straight_4m", "kind": "foundation_straight", "length": 4.0},
	{"name": "foundation_straight_8m", "kind": "foundation_straight", "length": 8.0},
	{"name": "foundation_corner_outer", "kind": "foundation_corner_outer", "length": 4.0},
	{"name": "foundation_corner_inner", "kind": "foundation_corner_inner", "length": 4.0}
]

@export var auto_generate_on_ready: bool = false
@export var generate_stone_variant: bool = true
@export var tudor_material_path: String = "res://assets/materials/wall_material.tres"
@export var stone_material_path: String = "res://assets/materials/foundation_material.tres"
@export var window_prefab_path: String = "res://assets/prefabs/walls/tudor/tudor_window.tscn"

func _ready() -> void:
	if Engine.is_editor_hint() and auto_generate_on_ready:
		generate_library()

func generate_library() -> void:
	_ensure_output_dir()
	var variants: Array[String] = ["tudor"]
	if generate_stone_variant:
		variants.append("stone")
	for variant in variants:
		for piece in PIECES:
			_generate_piece(piece, variant)
	print("[WallPieceGenerator] Generated modular wall library in %s" % OUTPUT_DIR)

func _generate_piece(piece: Dictionary, variant: String) -> void:
	var root := Node3D.new()
	root.name = "%s_%s" % [variant, String(piece.get("name", "piece"))]
	root.set_meta("piece_name", String(piece.get("name", "")))
	root.set_meta("piece_kind", String(piece.get("kind", "")))
	root.set_meta("wall_variant", variant)
	root.set_meta("grid_snap_m", GRID_SNAP_M)
	root.set_meta("wall_height_m", WALL_HEIGHT_M)

	var kind: String = String(piece.get("kind", ""))
	match kind:
		"straight":
			_add_prism(root, float(piece.get("length", 1.0)), WALL_HEIGHT_M, WALL_THICKNESS_M, Vector3.ZERO, _pick_material(variant))
		"window", "door", "arch":
			_build_opening_piece(root, piece, variant)
		"corner_outer":
			_build_corner_piece(root, float(piece.get("length", 4.0)), false, _pick_material(variant), WALL_HEIGHT_M, WALL_THICKNESS_M)
		"corner_inner":
			_build_corner_piece(root, float(piece.get("length", 4.0)), true, _pick_material(variant), WALL_HEIGHT_M, WALL_THICKNESS_M)
		"junction_t":
			_build_junction_t(root, float(piece.get("length", 4.0)), _pick_material(variant), WALL_HEIGHT_M, WALL_THICKNESS_M)
		"junction_x":
			_build_junction_x(root, float(piece.get("length", 4.0)), _pick_material(variant), WALL_HEIGHT_M, WALL_THICKNESS_M)
		"end_cap":
			_add_prism(root, float(piece.get("length", 0.5)), WALL_HEIGHT_M, WALL_THICKNESS_M, Vector3.ZERO, _pick_material(variant))
		"header":
			var hh: float = maxf(0.2, float(piece.get("header_height", 0.6)))
			_add_prism(root, float(piece.get("length", 1.5)), hh, WALL_THICKNESS_M, Vector3(0.0, (WALL_HEIGHT_M - hh) * 0.5, 0.0), _pick_material(variant))
		"foundation_straight":
			_add_prism(root, float(piece.get("length", 4.0)), 0.4, 0.35, Vector3.ZERO, _pick_foundation_material(variant))
		"foundation_corner_outer":
			_build_corner_piece(root, float(piece.get("length", 4.0)), false, _pick_foundation_material(variant), 0.4, 0.35)
		"foundation_corner_inner":
			_build_corner_piece(root, float(piece.get("length", 4.0)), true, _pick_foundation_material(variant), 0.4, 0.35)
		_:
			_add_prism(root, 1.0, WALL_HEIGHT_M, WALL_THICKNESS_M, Vector3.ZERO, _pick_material(variant))

	if kind == "window" and ResourceLoader.exists(window_prefab_path):
		var window_scene: PackedScene = load(window_prefab_path) as PackedScene
		if window_scene != null:
			var inst: Node = window_scene.instantiate()
			if inst is Node3D:
				var opening_h: float = maxf(0.8, float(piece.get("opening_height", 1.7)))
				var sill_h: float = maxf(0.0, float(piece.get("sill", 0.8)))
				var center_y: float = (-WALL_HEIGHT_M * 0.5) + sill_h + (opening_h * 0.5)
				(inst as Node3D).position = Vector3(0.0, center_y, 0.0)
				root.add_child(inst)

	var local_name: String = String(piece.get("name", "piece"))
	var tscn_path: String = "%s/%s_%s.tscn" % [OUTPUT_DIR, variant, local_name]
	var packed := PackedScene.new()
	var pack_err: int = packed.pack(root)
	if pack_err == OK:
		ResourceSaver.save(packed, tscn_path)
	_export_glb(root, "%s/%s_%s.glb" % [OUTPUT_DIR, variant, local_name])
	root.free()

func _build_opening_piece(root: Node3D, piece: Dictionary, variant: String) -> void:
	var length_m: float = maxf(1.0, float(piece.get("length", 2.0)))
	var opening_width: float = maxf(0.8, float(piece.get("opening_width", 1.2)))
	var opening_height: float = maxf(1.0, float(piece.get("opening_height", 2.0)))
	var sill: float = maxf(0.0, float(piece.get("sill", 0.0)))
	var side_len: float = maxf(0.25, (length_m - opening_width) * 0.5)
	var wall_mat: Material = _pick_material(variant)

	_add_prism(root, side_len, WALL_HEIGHT_M, WALL_THICKNESS_M, Vector3(-(opening_width * 0.5 + side_len * 0.5), 0.0, 0.0), wall_mat)
	_add_prism(root, side_len, WALL_HEIGHT_M, WALL_THICKNESS_M, Vector3((opening_width * 0.5 + side_len * 0.5), 0.0, 0.0), wall_mat)

	var header_h: float = maxf(0.25, WALL_HEIGHT_M - sill - opening_height)
	if header_h > 0.05:
		var header_center_y: float = (-WALL_HEIGHT_M * 0.5) + sill + opening_height + (header_h * 0.5)
		_add_prism(root, opening_width, header_h, WALL_THICKNESS_M, Vector3(0.0, header_center_y, 0.0), wall_mat)

	if String(piece.get("kind", "")) == "window" and sill > 0.05:
		var sill_h: float = sill
		var sill_center_y: float = (-WALL_HEIGHT_M * 0.5) + (sill_h * 0.5)
		_add_prism(root, opening_width, sill_h, WALL_THICKNESS_M, Vector3(0.0, sill_center_y, 0.0), wall_mat)

func _build_corner_piece(root: Node3D, leg_length: float, inner: bool, material: Material, height_m: float, thickness_m: float) -> void:
	var leg: float = maxf(1.0, leg_length)
	var half_leg: float = leg * 0.5
	if inner:
		_add_prism(root, leg, height_m, thickness_m, Vector3(0.0, 0.0, -half_leg + thickness_m * 0.5), material)
		_add_prism(root, thickness_m, height_m, leg, Vector3(-half_leg + thickness_m * 0.5, 0.0, 0.0), material)
	else:
		_add_prism(root, leg, height_m, thickness_m, Vector3(0.0, 0.0, half_leg - thickness_m * 0.5), material)
		_add_prism(root, thickness_m, height_m, leg, Vector3(half_leg - thickness_m * 0.5, 0.0, 0.0), material)

func _build_junction_t(root: Node3D, length_m: float, material: Material, height_m: float, thickness_m: float) -> void:
	var run: float = maxf(1.0, length_m)
	_add_prism(root, run, height_m, thickness_m, Vector3.ZERO, material)
	_add_prism(root, thickness_m, height_m, run * 0.5, Vector3(0.0, 0.0, run * 0.25), material)

func _build_junction_x(root: Node3D, length_m: float, material: Material, height_m: float, thickness_m: float) -> void:
	var run: float = maxf(1.0, length_m)
	_add_prism(root, run, height_m, thickness_m, Vector3.ZERO, material)
	_add_prism(root, thickness_m, height_m, run, Vector3.ZERO, material)

func _add_prism(root: Node3D, length_m: float, height_m: float, thickness_m: float, offset: Vector3, material: Material) -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(length_m, height_m, thickness_m)
	mesh_inst.mesh = box
	mesh_inst.material_override = material
	mesh_inst.position = offset
	root.add_child(mesh_inst)

	var body := StaticBody3D.new()
	body.name = "Collision"
	body.position = offset
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = box.size
	shape.shape = collider
	body.add_child(shape)
	root.add_child(body)

func _pick_material(variant: String) -> Material:
	if variant == "stone":
		if ResourceLoader.exists(stone_material_path):
			var m_stone: Material = load(stone_material_path) as Material
			if m_stone != null:
				return m_stone
	if ResourceLoader.exists(tudor_material_path):
		var m_tudor: Material = load(tudor_material_path) as Material
		if m_tudor != null:
			return m_tudor
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.77, 0.74, 0.7, 1.0)
	fallback.roughness = 0.9
	return fallback

func _pick_foundation_material(variant: String) -> Material:
	if ResourceLoader.exists(stone_material_path):
		var m_foundation: Material = load(stone_material_path) as Material
		if m_foundation != null:
			return m_foundation
	return _pick_material(variant)

func _ensure_output_dir() -> void:
	var abs_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)

func _export_glb(root: Node3D, path: String) -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var append_err: int = doc.append_from_scene(root, state)
	if append_err != OK:
		push_warning("GLB append failed for %s (err %d)" % [path, append_err])
		return
	var save_err: int = doc.write_to_filesystem(state, path)
	if save_err != OK:
		push_warning("GLB export failed for %s (err %d)" % [path, save_err])
