class_name WallSegment
extends Resource

@export var start: Vector3 = Vector3.ZERO
@export var end: Vector3 = Vector3.ZERO
@export var height: float = 3.0
@export var wall_type: String = "stone"
@export var openings: Array[Dictionary] = []

func get_length() -> float:
	return start.distance_to(end)

func get_midpoint() -> Vector3:
	return (start + end) * 0.5

func get_direction() -> Vector3:
	var delta: Vector3 = end - start
	if delta.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return delta.normalized()
