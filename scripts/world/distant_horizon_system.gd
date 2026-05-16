class_name DistantHorizonSystem
extends Node3D

## DistantHorizonSystem — renders distant landmarks (mountain ranges, etc.)
## at world distances of hundreds to tens-of-thousands of meters using
## procedurally-generated, extremely low-poly meshes that are cheap to render.
##
## Mountains are added via add_mountain() and removed via remove_landmark().
## The system serializes to / deserializes from plain Array[Dictionary] data
## for map save / load.
##
## Origin Shift integration:
##   OriginShiftSystem translates this Node3D's global_position by the shift
##   offset (so all landmark children follow automatically), then calls
##   apply_origin_shift() to keep the stored position data consistent with
##   the new world coordinates.

## Emitted whenever a landmark is added or removed.
signal landmarks_changed()

## Default distance at which the GM's click ray places a new mountain (meters).
const DEFAULT_PLACE_DISTANCE: float = 3000.0
## Default mountain base half-radius (meters).
const DEFAULT_RADIUS: float = 700.0
## Default mountain peak height (meters).
const DEFAULT_HEIGHT: float = 450.0
## Default number of individual peaks in a range.
const DEFAULT_PEAK_COUNT: int = 3

var _next_id: int = 1
## Array of landmark data dicts: {id, position (Vector3), radius, height, peak_count, seed}
var _landmarks: Array = []
var _mountain_material: StandardMaterial3D = null


func _ready() -> void:
	_mountain_material = _build_mountain_material()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Add a mountain range at the given world position and return its integer id.
## All parameters have sensible defaults so a single click is enough.
func add_mountain(
		world_pos: Vector3,
		radius: float = DEFAULT_RADIUS,
		height: float = DEFAULT_HEIGHT,
		peak_count: int = DEFAULT_PEAK_COUNT,
		rng_seed: int = -1) -> int:
	if rng_seed < 0:
		rng_seed = randi()
	var id: int = _next_id
	_next_id += 1
	var data: Dictionary = {
		"id": id,
		"position": world_pos,
		"radius": radius,
		"height": height,
		"peak_count": peak_count,
		"seed": rng_seed
	}
	_landmarks.append(data)
	_spawn_landmark(data)
	landmarks_changed.emit()
	return id


## Remove the landmark with the given id. Returns true if found.
func remove_landmark(id: int) -> bool:
	for i in range(_landmarks.size()):
		if int(_landmarks[i]["id"]) == id:
			var node: Node = find_child("Landmark_%d" % id, false, false)
			if node != null:
				node.queue_free()
			_landmarks.remove_at(i)
			landmarks_changed.emit()
			return true
	return false


## Remove all landmarks.
func clear_all() -> void:
	for child in get_children():
		child.queue_free()
	_landmarks.clear()
	landmarks_changed.emit()


## Called by OriginShiftSystem after this node's global_position has already
## been translated by offset. Patches stored world positions so that
## serialization round-trips produce correct results even after many shifts.
func apply_origin_shift(offset: Vector3) -> void:
	for data in _landmarks:
		data["position"] = (data["position"] as Vector3) + offset


## Serialize all landmarks to an Array of plain Dictionaries.
func serialize() -> Array:
	var out: Array = []
	for data in _landmarks:
		var p: Vector3 = data["position"] as Vector3
		out.append({
			"id": int(data["id"]),
			"position": [p.x, p.y, p.z],
			"radius": float(data["radius"]),
			"height": float(data["height"]),
			"peak_count": int(data["peak_count"]),
			"seed": int(data["seed"])
		})
	return out


## Restore landmarks from saved data (clears existing ones first).
func deserialize(items: Array) -> void:
	clear_all()
	var max_id: int = 0
	for item in items:
		if item is not Dictionary:
			continue
		var d: Dictionary = item
		var p_arr: Array = d.get("position", [0.0, 0.0, 0.0])
		var pos := Vector3(float(p_arr[0]), float(p_arr[1]), float(p_arr[2]))
		var id: int = int(d.get("id", _next_id))
		if id > max_id:
			max_id = id
		var data: Dictionary = {
			"id": id,
			"position": pos,
			"radius": float(d.get("radius", DEFAULT_RADIUS)),
			"height": float(d.get("height", DEFAULT_HEIGHT)),
			"peak_count": int(d.get("peak_count", DEFAULT_PEAK_COUNT)),
			"seed": int(d.get("seed", 0))
		}
		_landmarks.append(data)
		_spawn_landmark(data)
	if max_id >= _next_id:
		_next_id = max_id + 1
	if not _landmarks.is_empty():
		landmarks_changed.emit()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _spawn_landmark(data: Dictionary) -> void:
	var mesh: ArrayMesh = _build_mountain_mesh(
			float(data["radius"]),
			float(data["height"]),
			int(data["peak_count"]),
			int(data["seed"]))

	var mmi := MeshInstance3D.new()
	mmi.name = "Landmark_%d" % int(data["id"])
	mmi.mesh = mesh
	if _mountain_material != null:
		mmi.material_override = _mountain_material
	# Convert stored world position to local space of this Node3D.
	# When global_position == 0 (fresh load) this equals world pos.
	# After origin shifts this node has been translated so we subtract.
	mmi.position = (data["position"] as Vector3) - global_position
	# Disable shadow casting and occlusion culling — these are distant silhouettes.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.ignore_occlusion_culling = true
	add_child(mmi)


## Generate a low-poly mountain range mesh: a ridge of overlapping cone-peaks.
##   radius    — half-width of the entire range base (meters).
##   height    — maximum peak height (meters).
##   peaks     — number of distinct summits along the ridge.
##   seed      — RNG seed for reproducible randomisation.
static func _build_mountain_mesh(
		radius: float,
		height: float,
		peaks: int,
		rng_seed: int) -> ArrayMesh:

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	const SIDES: int = 14  # triangles per cone base ring
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()

	# Distribute peak apexes along a rough ridge line (X axis).
	var apex_list: Array[Vector3] = []
	for pk in range(peaks):
		var t: float = float(pk) / maxf(float(peaks - 1), 1.0)
		var px: float = lerp(-radius * 0.75, radius * 0.75, t)
		var pz: float = rng.randf_range(-radius * 0.08, radius * 0.08)
		var py: float = height * rng.randf_range(0.60, 1.0)
		apex_list.append(Vector3(px, py, pz))

	# Build a cone for each peak.
	for pk in range(peaks):
		var apex: Vector3 = apex_list[pk]
		# Cone radius tapers so adjacent mountains overlap naturally.
		var cone_r: float = (radius / maxf(float(peaks), 1.0)) * rng.randf_range(0.75, 1.15)

		for s in range(SIDES):
			var a0: float = TAU * float(s) / float(SIDES)
			var a1: float = TAU * float(s + 1) / float(SIDES)
			var b0 := Vector3(apex.x + cos(a0) * cone_r, 0.0, apex.z + sin(a0) * cone_r)
			var b1 := Vector3(apex.x + cos(a1) * cone_r, 0.0, apex.z + sin(a1) * cone_r)

			# Outward-facing side triangle.
			var side_n: Vector3 = (b1 - b0).cross(apex - b0).normalized()
			verts.append(b0)
			verts.append(b1)
			verts.append(apex)
			normals.append(side_n)
			normals.append(side_n)
			normals.append(side_n)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Create a muted blue-grey material that reads as a classic distant-mountain
## silhouette without competing with foreground detail.
static func _build_mountain_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.41, 0.52, 1.0)
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Per-vertex shading gives a crunchy low-poly silhouette — perfect for
	# distant mountains that should read as simple shapes.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return mat
