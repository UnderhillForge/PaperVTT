## BoundaryData — serializable resource describing a single cliff guide line.
## Stored inside BoundarySystem; not a Godot Resource subclass so it travels as plain Dictionary
## and survives hot-reload without import issues.
class_name BoundaryData
extends RefCounted

## Unique numeric id assigned by BoundarySystem.
var id: int = -1

## User-visible name for the line.
var label: String = "Cliff Line"

## Optional semantic material category (visual/profile preset metadata).
var boundary_type: String = "rock"

## World-layer index this boundary lives on (mirrors terrain layers).
var world_layer: int = 0

## Control points in world XZ space (Y stored but not required to be terrain-height).
## Array[Vector3]
var points: Array = []

## Always false for cliff lines; kept for save compatibility with old polygon data.
var is_closed: bool = false

## Cliff face angle in degrees: 0 = gentle slope, 90 = vertical face.
var steepness_deg: float = 80.0

## Height to raise the inner area above the boundary baseline (metres).
var raise_height: float = 4.0

## Brush width applied when painting the cliff wall along the boundary (metres).
var wall_brush_width: float = 3.5

## Which side of the line to raise.
##  1 => left side of segment direction
## -1 => right side of segment direction
var raise_side: int = 1

## Cliff face material/profile label.
var face_material: String = "rock"

## Texture ID to paint on the cliff face (empty = keep terrain as-is).
var wall_texture_id: String = ""

## Cave entrances attached to this boundary.
## Array[Dictionary] with keys: edge_index, edge_t, position(Array[3]), normal(Array[3]), marker_id
var cave_entrances: Array = []

## Whether the extrusion has been applied to the terrain.
var applied: bool = false


func serialize() -> Dictionary:
	var pts: Array = []
	for p in points:
		pts.append([p.x, p.y, p.z])
	return {
		"id": id,
		"label": label,
		"type": boundary_type,
		"layer": world_layer,
		"points": pts,
		"closed": is_closed,
		"steepness": steepness_deg,
		"raise_height": raise_height,
		"wall_brush_width": wall_brush_width,
		"raise_side": raise_side,
		"face_material": face_material,
		"wall_texture_id": wall_texture_id,
		"cave_entrances": cave_entrances.duplicate(true),
		"applied": applied,
	}


static func deserialize(d: Dictionary) -> BoundaryData:
	var b := BoundaryData.new()
	b.id = int(d.get("id", -1))
	b.label = String(d.get("label", "Cliff Line"))
	b.boundary_type = String(d.get("type", "rock"))
	b.world_layer = int(d.get("layer", 0))
	b.is_closed = bool(d.get("closed", false))
	b.steepness_deg = clampf(float(d.get("steepness", 80.0)), 0.0, 90.0)
	b.raise_height = clampf(float(d.get("raise_height", 8.0)), 0.0, 80.0)
	b.wall_brush_width = clampf(float(d.get("wall_brush_width", 3.5)), 0.5, 20.0)
	b.raise_side = 1 if int(d.get("raise_side", 1)) >= 0 else -1
	b.face_material = String(d.get("face_material", b.boundary_type if b.boundary_type != "" else "rock"))
	b.wall_texture_id = String(d.get("wall_texture_id", ""))
	b.cave_entrances = (d.get("cave_entrances", []) as Array).duplicate(true)
	b.applied = bool(d.get("applied", false))
	var raw_pts: Array = d.get("points", [])
	for rp in raw_pts:
		if rp is Array and (rp as Array).size() >= 3:
			var arr: Array = rp as Array
			b.points.append(Vector3(float(arr[0]), float(arr[1]), float(arr[2])))
	return b
