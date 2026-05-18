# brush_preview.gd
extends MeshInstance3D
class_name BrushPreview

@export var base_color: Color = Color(0.1, 0.7, 1.0, 0.18)
@export var rim_color: Color = Color(0.6, 0.9, 1.0, 0.7)
@export var pulse_speed: float = 3.0

var material: ShaderMaterial

func _ready() -> void:
	mesh = SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 0.25          # flattened dome shape
	
	material = ShaderMaterial.new()
	material.shader = preload("res://addons/worldbrush/shaders/brush_bubble.gdshader")
	print("BrushPreview._ready() - Shader loaded: %s" % (material.shader != null))
	material_override = material
	
	update_colors(base_color, rim_color)

func update_radius(new_radius: float) -> void:
	print("BrushPreview.update_radius(%f)" % new_radius)
	scale = Vector3(new_radius, new_radius * 0.25, new_radius)  # flattened

func update_colors(new_base: Color, new_rim: Color) -> void:
	print("BrushPreview.update_colors(base=%s, rim=%s)" % [new_base, new_rim])
	base_color = new_base
	rim_color = new_rim
	if material:
		material.set_shader_parameter("base_color", base_color)
		material.set_shader_parameter("rim_color", new_rim)

func _process(delta: float) -> void:
	if material:
		var pulse = 1.0 + sin(Time.get_ticks_msec() * 0.006 * pulse_speed) * 0.08
		material.set_shader_parameter("pulse", pulse)

func show_preview() -> void:
	print("BrushPreview.show_preview()")
	visible = true

func hide_preview() -> void:
	visible = false
