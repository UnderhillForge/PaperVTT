@tool
extends Camera3D
class_name PPOutlinesCamera

@export var outlines_enabled: bool = true
@export_range(0.0, 8.0, 0.01) var color_outline_scale: float = 2.0
@export_range(0.0, 8.0, 0.01) var depth_outline_scale: float = 2.0
@export_range(0.0, 10.0, 0.01) var depth_threshold: float = 2.5
@export_range(0.0, 8.0, 0.01) var normal_sensitivity: float = 1.2
@export_range(0.0, 1.0, 0.01) var edge_threshold: float = 0.04
@export_range(0.0, 1.0, 0.01) var edge_alpha: float = 0.9
@export var edge_color: Color = Color(0.0, 0.0, 0.0, 1.0)

func get_outlines_profile() -> Dictionary:
	return {
		"enabled": outlines_enabled,
		"color_outline_scale": color_outline_scale,
		"depth_outline_scale": depth_outline_scale,
		"depth_threshold": depth_threshold,
		"normal_sensitivity": normal_sensitivity,
		"edge_threshold": edge_threshold,
		"edge_alpha": edge_alpha,
		"edge_color": edge_color,
	}
