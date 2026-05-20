# brush_preview.gd
extends MeshInstance3D
class_name BrushPreview

@export var base_color: Color = Color(0.1, 0.8, 1.0, 0.08)
@export var rim_color: Color = Color(0.6, 0.95, 1.0, 0.9)
@export var pulse_speed: float = 1.8
@export var center_height_factor: float = 0.08

var material: ShaderMaterial
var _current_radius: float = 1.0
var _terrain_height: float = 0.0

func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 36
	sphere.rings = 20
	mesh = sphere
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	material = ShaderMaterial.new()
	material.shader = preload("res://addons/worldbrush/shaders/brush_bubble.gdshader")
	material_override = material
	
	update_colors(base_color, rim_color)
	update_radius(_current_radius)
	if material != null:
		material.set_shader_parameter("pulse_speed", pulse_speed)

func update_radius(new_radius: float) -> void:
	_current_radius = maxf(new_radius, 0.05)
	scale = Vector3.ONE * _current_radius
	if material != null:
		material.set_shader_parameter("radius", _current_radius)

func update_colors(new_base: Color, new_rim: Color) -> void:
	base_color = new_base
	rim_color = new_rim
	if material != null:
		material.set_shader_parameter("base_color", base_color)
		material.set_shader_parameter("rim_color", new_rim)

func update_world_position(surface_world_pos: Vector3) -> void:
	_terrain_height = surface_world_pos.y
	var center_height: float = maxf(_current_radius * center_height_factor, 0.05)
	global_position = Vector3(surface_world_pos.x, surface_world_pos.y + center_height, surface_world_pos.z)
	if material != null:
		material.set_shader_parameter("terrain_height", _terrain_height)

func _process(delta: float) -> void:
	if material != null:
		material.set_shader_parameter("pulse_speed", pulse_speed)

func show_preview() -> void:
	visible = true

func hide_preview() -> void:
	visible = false
