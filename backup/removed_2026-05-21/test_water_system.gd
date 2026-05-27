# Test Water System - Simple river creation for verification
extends Node3D

@onready var water_system = %WaterSystem

func _ready() -> void:
	if water_system == null:
		print("Water system not found!")
		return
	
	# Create a test river
	create_test_river()


func create_test_river() -> void:
	# Create a simple river with a gentle curve
	var river_id_result = water_system.create_river("TestRiver")
	
	# Add control points to create a curved river
	var points = [
		Vector3(0.0, 1.0, 0.0),
		Vector3(5.0, 1.0, 5.0),
		Vector3(10.0, 1.0, 15.0),
		Vector3(15.0, 1.0, 20.0),
	]
	
	# Get the river and update its curve
	var rivers = water_system.get_rivers()
	if rivers.is_empty():
		print("No rivers created!")
		return
	
	var river_id = rivers.keys()[0]
	var river_data = water_system.get_river(river_id)
	
	if river_data.is_empty():
		print("River data not found!")
		return
	
	var curve = river_data["curve"]
	curve.clear_points()
	
	# Add points to curve
	for i in range(points.size()):
		var pos = points[i]
		var in_tangent = Vector3.ZERO
		var out_tangent = Vector3.ZERO
		
		if i > 0:
			in_tangent = (pos - points[i-1]) * -0.25
		if i < points.size() - 1:
			out_tangent = (points[i+1] - pos) * 0.25
		
		curve.add_point(pos, in_tangent, out_tangent)
	
	# Update river mesh
	if water_system.has_method("_regenerate_river_mesh"):
		water_system.call("_regenerate_river_mesh", river_id)
	
	print("Test river created: %s" % river_data.get("name", "Unknown"))
	print("River has %d control points" % curve.get_point_count())
