class_name ScatterSystem
extends Node3D

const ScatterAsset = preload("res://scripts/scatter/scatter_asset.gd")

@export var map_size: float = 256.0

var _terrain: Node = null
var _assets: Dictionary = {}
var _asset_meshes: Dictionary = {}
var _asset_materials: Dictionary = {}
var _records_by_asset: Dictionary = {}
var _pools_by_asset: Dictionary = {}
var _active_asset_id: String = ""
var _rng := RandomNumberGenerator.new()

func initialize(terrain: Node, map_size_m: float) -> void:
	_terrain = terrain
	map_size = maxf(32.0, map_size_m)
	_rng.randomize()

func set_active_prefab(prefab_path: String) -> void:
	if prefab_path == "":
		_active_asset_id = ""
		return
	_active_asset_id = _ensure_asset_for_prefab(prefab_path)

func apply_brush(mode: String, world_pos: Vector3, radius: float, strength: float, density_per_m2: float, scale_min: float, scale_max: float, rot_random_deg: float, tilt_max_deg: float) -> void:
	if _active_asset_id == "":
		return
	if not _assets.has(_active_asset_id):
		return
	var asset: ScatterAsset = _assets[_active_asset_id]
	if asset == null:
		return

	if mode == "scattererase":
		_erase_in_radius(_active_asset_id, world_pos, radius)
		_rebuild_pool(_active_asset_id)
		return

	var effective_density: float = maxf(0.0, density_per_m2) * maxf(0.01, asset.density_multiplier)
	var area: float = PI * radius * radius
	var target_count: int = int(round(area * effective_density * clampf(strength, 0.01, 1.0)))
	if target_count <= 0:
		return

	var min_s: float = maxf(0.05, scale_min * asset.scale_min)
	var max_s: float = maxf(min_s, scale_max * asset.scale_max)
	var yaw_rand: float = maxf(0.0, rot_random_deg + asset.rotation_range_deg)
	var tilt_max: float = maxf(0.0, tilt_max_deg + asset.tilt_max_angle_deg)

	if not _records_by_asset.has(_active_asset_id):
		_records_by_asset[_active_asset_id] = []
	var records: Array = _records_by_asset[_active_asset_id]

	for _i in range(target_count):
		var r: float = radius * sqrt(_rng.randf())
		var a: float = _rng.randf() * TAU
		var wx: float = world_pos.x + cos(a) * r
		var wz: float = world_pos.z + sin(a) * r
		var wy: float = _sample_height(wx, wz)
		var normal: Vector3 = _estimate_normal(wx, wz)
		var y_rot: float = deg_to_rad(_rng.randf_range(-yaw_rand, yaw_rand))
		var tilt_x: float = deg_to_rad(_rng.randf_range(-tilt_max, tilt_max))
		var tilt_z: float = deg_to_rad(_rng.randf_range(-tilt_max, tilt_max))
		var s: float = _rng.randf_range(min_s, max_s)
		records.append({
			"p": [wx, wy, wz],
			"n": [normal.x, normal.y, normal.z],
			"y": y_rot,
			"tx": tilt_x,
			"tz": tilt_z,
			"s": s
		})

	_records_by_asset[_active_asset_id] = records
	_rebuild_pool(_active_asset_id)

func clear_all() -> void:
	for key in _pools_by_asset.keys():
		var node: Node = _pools_by_asset[key]
		if is_instance_valid(node):
			node.queue_free()
	_pools_by_asset.clear()
	_records_by_asset.clear()
	_assets.clear()
	_asset_meshes.clear()
	_asset_materials.clear()
	_active_asset_id = ""

func serialize_state() -> Dictionary:
	var assets_data: Array[Dictionary] = []
	for asset_id in _records_by_asset.keys():
		var records: Array = _records_by_asset[asset_id]
		if records.is_empty():
			continue
		var asset: ScatterAsset = _assets.get(asset_id, null)
		if asset == null or asset.prefab_scene == null:
			continue
		assets_data.append({
			"asset_id": asset_id,
			"prefab_path": String(asset.prefab_scene.resource_path),
			"density_multiplier": asset.density_multiplier,
			"scale_min": asset.scale_min,
			"scale_max": asset.scale_max,
			"rotation_range_deg": asset.rotation_range_deg,
			"tilt_max_angle_deg": asset.tilt_max_angle_deg,
			"records": records
		})
	return {
		"assets": assets_data
	}

func load_state(data: Dictionary) -> void:
	clear_all()
	var assets_data: Array = data.get("assets", [])
	for item in assets_data:
		if item is not Dictionary:
			continue
		var d: Dictionary = item
		var prefab_path: String = String(d.get("prefab_path", ""))
		if prefab_path == "":
			continue
		var asset_id: String = _ensure_asset_for_prefab(prefab_path)
		if asset_id == "":
			continue
		var asset: ScatterAsset = _assets.get(asset_id, null)
		if asset == null:
			continue
		asset.density_multiplier = float(d.get("density_multiplier", asset.density_multiplier))
		asset.scale_min = float(d.get("scale_min", asset.scale_min))
		asset.scale_max = float(d.get("scale_max", asset.scale_max))
		asset.rotation_range_deg = float(d.get("rotation_range_deg", asset.rotation_range_deg))
		asset.tilt_max_angle_deg = float(d.get("tilt_max_angle_deg", asset.tilt_max_angle_deg))
		_records_by_asset[asset_id] = (d.get("records", []) as Array).duplicate(true)
		_rebuild_pool(asset_id)

func _ensure_asset_for_prefab(prefab_path: String) -> String:
	if prefab_path == "":
		return ""
	var key: String = prefab_path.to_lower()
	if _assets.has(key):
		return key
	var packed: PackedScene = load(prefab_path) as PackedScene
	if packed == null:
		return ""
	var asset := ScatterAsset.new()
	asset.prefab_scene = packed
	_assets[key] = asset
	_records_by_asset[key] = []
	_extract_mesh_for_asset(key)
	return key

func _extract_mesh_for_asset(asset_id: String) -> void:
	if not _assets.has(asset_id):
		return
	var asset: ScatterAsset = _assets[asset_id]
	if asset == null or asset.prefab_scene == null:
		return
	var inst: Node = asset.prefab_scene.instantiate()
	if inst == null:
		return
	var mesh_node: MeshInstance3D = _find_first_mesh_node(inst)
	if mesh_node != null and mesh_node.mesh != null:
		_asset_meshes[asset_id] = mesh_node.mesh
		_asset_materials[asset_id] = mesh_node.material_override
	inst.queue_free()

func _find_first_mesh_node(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found: MeshInstance3D = _find_first_mesh_node(child)
		if found != null:
			return found
	return null

func _rebuild_pool(asset_id: String) -> void:
	if not _asset_meshes.has(asset_id):
		_extract_mesh_for_asset(asset_id)
	if not _asset_meshes.has(asset_id):
		return

	var existing: MultiMeshInstance3D = _pools_by_asset.get(asset_id, null)
	if existing != null and is_instance_valid(existing):
		existing.queue_free()
		_pools_by_asset.erase(asset_id)

	var records: Array = _records_by_asset.get(asset_id, [])
	if records.is_empty():
		return

	var mm := MultiMesh.new()
	mm.mesh = _asset_meshes[asset_id]
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.use_custom_data = false
	mm.instance_count = records.size()

	for i in range(records.size()):
		var d: Dictionary = records[i]
		var p_arr: Array = d.get("p", [0.0, 0.0, 0.0])
		var n_arr: Array = d.get("n", [0.0, 1.0, 0.0])
		var pos := Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
		var normal := Vector3(float(n_arr[0]), float(n_arr[1]), float(n_arr[2])).normalized()
		var yaw: float = float(d.get("y", 0.0))
		var tilt_x: float = float(d.get("tx", 0.0))
		var tilt_z: float = float(d.get("tz", 0.0))
		var scale_v: float = float(d.get("s", 1.0))

		var basis := Basis.IDENTITY
		basis = _basis_from_normal(normal)
		basis = basis * Basis(Vector3.UP, yaw)
		basis = basis * Basis(Vector3.RIGHT, tilt_x)
		basis = basis * Basis(Vector3.BACK, tilt_z)
		basis = basis.scaled(Vector3.ONE * scale_v)
		mm.set_instance_transform(i, Transform3D(basis, pos))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ScatterPool_%s" % asset_id.get_file()
	mmi.multimesh = mm
	if _asset_materials.has(asset_id) and _asset_materials[asset_id] != null:
		mmi.material_override = _asset_materials[asset_id]
	add_child(mmi)
	_pools_by_asset[asset_id] = mmi

func _erase_in_radius(asset_id: String, world_pos: Vector3, radius: float) -> void:
	if not _records_by_asset.has(asset_id):
		return
	var rsq: float = radius * radius
	var records: Array = _records_by_asset[asset_id]
	var kept: Array = []
	for item in records:
		if item is not Dictionary:
			continue
		var d: Dictionary = item
		var p_arr: Array = d.get("p", [0.0, 0.0, 0.0])
		var px: float = float(p_arr[0])
		var pz: float = float(p_arr[2])
		var dx: float = px - world_pos.x
		var dz: float = pz - world_pos.z
		if dx * dx + dz * dz > rsq:
			kept.append(d)
	_records_by_asset[asset_id] = kept

func _sample_height(x: float, z: float) -> float:
	if _terrain != null and _terrain.has_method("sample_height"):
		return float(_terrain.call("sample_height", x, z))
	return 0.0

func _estimate_normal(x: float, z: float) -> Vector3:
	var eps: float = maxf(0.25, map_size / 1024.0)
	var h_l: float = _sample_height(x - eps, z)
	var h_r: float = _sample_height(x + eps, z)
	var h_d: float = _sample_height(x, z - eps)
	var h_u: float = _sample_height(x, z + eps)
	var n := Vector3(h_l - h_r, 2.0 * eps, h_d - h_u)
	if n.length_squared() <= 0.000001:
		return Vector3.UP
	return n.normalized()

func _basis_from_normal(normal: Vector3) -> Basis:
	var up: Vector3 = normal.normalized()
	var right: Vector3 = up.cross(Vector3.FORWARD)
	if right.length_squared() <= 0.00001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward: Vector3 = right.cross(up).normalized()
	return Basis(right, up, forward)
