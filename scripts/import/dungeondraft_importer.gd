class_name DungeondraftImporter
extends RefCounted

const DEFAULT_SETTINGS := {
	"floor_raise_height": 0.15,
	"wall_thickness_m": 0.2,
	"wall_height_m": 2.5,
	"dd_pixels_per_cell": 256.0,
	"world_units_per_cell": 1.524,
	"light_range_scale": 1.524,
	"light_energy_scale": 1.0
}

func import_from_file(file_path: String, settings: Dictionary = {}) -> Dictionary:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return {
			"ok": false,
			"error": "Failed to open file: %s" % file_path
		}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return {
			"ok": false,
			"error": "Invalid JSON in map file"
		}

	var map_data := parsed as Dictionary
	return _normalize_map_data(map_data, settings)

func _normalize_map_data(map_data: Dictionary, settings: Dictionary) -> Dictionary:
	var merged_settings: Dictionary = DEFAULT_SETTINGS.duplicate()
	for key in settings.keys():
		merged_settings[key] = settings[key]

	var world: Dictionary = map_data.get("world", {})
	if world.is_empty():
		return {"ok": false, "error": "Map is missing world section"}

	var width: int = int(world.get("width", 0))
	var height: int = int(world.get("height", 0))
	if width <= 0 or height <= 0:
		return {"ok": false, "error": "Invalid world width/height"}

	var levels: Dictionary = world.get("levels", {})
	var level0: Dictionary = levels.get("0", {})
	if level0.is_empty():
		return {"ok": false, "error": "Level 0 data missing"}

	var warnings: Array[String] = []
	var tiles: Dictionary = level0.get("tiles", {})
	var floor_tiles: Array[Dictionary] = _extract_floor_tiles(tiles, width, height, merged_settings, warnings)
	var wall_segments: Array[Dictionary] = _extract_wall_segments(level0, width, height, merged_settings, warnings)
	var objects: Array[Dictionary] = _extract_objects(level0, width, height, merged_settings, warnings)
	var lights: Array[Dictionary] = _extract_lights(level0, width, height, merged_settings, warnings)

	return {
		"ok": true,
		"width_cells": width,
		"height_cells": height,
		"settings": merged_settings,
		"floor_tiles": floor_tiles,
		"wall_segments": wall_segments,
		"objects": objects,
		"lights": lights,
		"warnings": warnings
	}

func _extract_floor_tiles(tiles: Dictionary, width: int, height: int, settings: Dictionary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var raw_cells: String = String(tiles.get("cells", ""))
	if raw_cells == "":
		warnings.append("No tile cell data found")
		return out

	var values: Array[int] = _parse_pool_int_array(raw_cells)
	if values.size() < width * height:
		warnings.append("Tile cell array smaller than expected grid")

	var cell_size: float = float(settings.get("world_units_per_cell", 1.0))
	var floor_raise: float = float(settings.get("floor_raise_height", 0.15))

	for row in range(height):
		for col in range(width):
			var idx: int = row * width + col
			if idx >= values.size():
				continue
			if values[idx] < 0:
				continue
			out.append({
				"center": _cell_center_to_world(col, row, width, height, cell_size),
				"cell_size": cell_size,
				"raise_height": floor_raise,
				"tile_id": values[idx]
			})

	return out

func _extract_wall_segments(level0: Dictionary, width: int, height: int, settings: Dictionary, warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var shapes: Dictionary = level0.get("shapes", {})
	if shapes.is_empty():
		warnings.append("No shapes section found")
		return out

	var polygons: Array = shapes.get("polygons", [])
	var walls: Array = shapes.get("walls", [])
	if polygons.is_empty() or walls.is_empty():
		warnings.append("No wall polygons found")
		return out

	var thickness: float = float(settings.get("wall_thickness_m", 0.2))
	var wall_height: float = float(settings.get("wall_height_m", 2.5))

	for wall_idx_variant in walls:
		var wall_idx: int = int(wall_idx_variant)
		if wall_idx < 0 or wall_idx >= polygons.size():
			continue
		var poly_text: String = String(polygons[wall_idx])
		var points: Array[Vector2] = _parse_pool_vector2_array(poly_text)
		if points.size() < 2:
			continue

		for i in range(points.size()):
			var from_2d: Vector2 = points[i]
			var to_2d: Vector2 = points[(i + 1) % points.size()]
			if from_2d.distance_to(to_2d) < 0.01:
				continue
			out.append({
				"from": _dd_point_to_world_xz(from_2d, width, height, settings),
				"to": _dd_point_to_world_xz(to_2d, width, height, settings),
				"thickness": thickness,
				"height": wall_height
			})

	return out

func _extract_objects(level0: Dictionary, width: int, height: int, settings: Dictionary, _warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var objects: Array = level0.get("objects", [])
	for obj_variant in objects:
		if not (obj_variant is Dictionary):
			continue
		var obj := obj_variant as Dictionary
		var pos := _parse_vector2_string(String(obj.get("position", "")))
		var scale_2d := _parse_vector2_string(String(obj.get("scale", "Vector2( 1, 1 )")))
		out.append({
			"position": _dd_point_to_world_xz(pos, width, height, settings),
			"rotation_rad": float(obj.get("rotation", 0.0)),
			"scale": Vector3(scale_2d.x, 1.0, scale_2d.y),
			"texture": String(obj.get("texture", "")),
			"node_id": String(obj.get("node_id", ""))
		})
	return out

func _extract_lights(level0: Dictionary, width: int, height: int, settings: Dictionary, _warnings: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var lights: Array = level0.get("lights", [])
	var range_scale: float = float(settings.get("light_range_scale", 1.0))
	var energy_scale: float = float(settings.get("light_energy_scale", 1.0))
	for light_variant in lights:
		if not (light_variant is Dictionary):
			continue
		var light := light_variant as Dictionary
		var pos := _parse_vector2_string(String(light.get("position", "")))
		out.append({
			"position": _dd_point_to_world_xz(pos, width, height, settings),
			"range": float(light.get("range", 5.0)) * range_scale,
			"intensity": float(light.get("intensity", 1.0)) * energy_scale,
			"color": _parse_argb_hex(String(light.get("color", "ffffffff"))),
			"shadows": bool(light.get("shadows", true)),
			"node_id": String(light.get("node_id", ""))
		})
	return out

func _cell_center_to_world(cell_x: int, cell_z: int, width: int, height: int, cell_size: float) -> Vector3:
	var map_w: float = float(width) * cell_size
	var map_h: float = float(height) * cell_size
	var world_x: float = -map_w * 0.5 + (float(cell_x) + 0.5) * cell_size
	var world_z: float = -map_h * 0.5 + (float(cell_z) + 0.5) * cell_size
	return Vector3(world_x, 0.0, world_z)

func _dd_point_to_world_xz(dd_point: Vector2, width: int, height: int, settings: Dictionary) -> Vector3:
	var px_per_cell: float = float(settings.get("dd_pixels_per_cell", 256.0))
	var cell_size: float = float(settings.get("world_units_per_cell", 1.0))
	var map_w: float = float(width) * cell_size
	var map_h: float = float(height) * cell_size
	var world_x: float = ((dd_point.x / px_per_cell) * cell_size) - map_w * 0.5
	var world_z: float = ((dd_point.y / px_per_cell) * cell_size) - map_h * 0.5
	return Vector3(world_x, 0.0, world_z)

func _parse_pool_int_array(text: String) -> Array[int]:
	var values: Array[int] = []
	var regex := RegEx.new()
	regex.compile("-?\\d+")
	for m in regex.search_all(text):
		values.append(int(m.get_string()))
	return values

func _parse_pool_vector2_array(text: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var nums: Array[float] = _parse_float_list(text)
	for i in range(0, nums.size(), 2):
		if i + 1 >= nums.size():
			break
		out.append(Vector2(nums[i], nums[i + 1]))
	return out

func _parse_vector2_string(text: String) -> Vector2:
	var nums: Array[float] = _parse_float_list(text)
	if nums.size() >= 2:
		return Vector2(nums[0], nums[1])
	return Vector2.ZERO

func _parse_float_list(text: String) -> Array[float]:
	var out: Array[float] = []
	var regex := RegEx.new()
	regex.compile("-?\\d+(?:\\.\\d+)?")
	for m in regex.search_all(text):
		out.append(float(m.get_string()))
	return out

func _parse_argb_hex(hex_text: String) -> Color:
	var h: String = hex_text.strip_edges().to_lower()
	if h.begins_with("#"):
		h = h.substr(1)
	if h.length() != 8:
		return Color(1, 1, 1, 1)
	var a: int = int("0x" + h.substr(0, 2))
	var r: int = int("0x" + h.substr(2, 2))
	var g: int = int("0x" + h.substr(4, 2))
	var b: int = int("0x" + h.substr(6, 2))
	return Color8(r, g, b, a)
