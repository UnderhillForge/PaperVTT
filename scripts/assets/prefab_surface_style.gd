@tool
extends Node3D

@export var shared_material: Material

func _ready() -> void:
    _apply_materials()

func _apply_materials() -> void:
    var model: Node = get_node_or_null("Model")
    if model == null:
        return
    _apply_recursive(model)

func _apply_recursive(node: Node) -> void:
    if node is MeshInstance3D:
        var mesh_node: MeshInstance3D = node as MeshInstance3D
        if mesh_node.mesh != null:
            for i in range(mesh_node.mesh.get_surface_count()):
                var source_material: Material = mesh_node.get_surface_override_material(i)
                if source_material == null:
                    source_material = mesh_node.mesh.surface_get_material(i)
                mesh_node.set_surface_override_material(i, _build_styled_material(source_material))
    for child in node.get_children():
        _apply_recursive(child)

func _build_styled_material(source_material: Material) -> StandardMaterial3D:
    var styled: StandardMaterial3D
    if source_material is StandardMaterial3D:
        styled = (source_material as StandardMaterial3D).duplicate(true) as StandardMaterial3D
    else:
        styled = StandardMaterial3D.new()

    var profile: StandardMaterial3D = shared_material as StandardMaterial3D
    if profile != null:
        styled.roughness = profile.roughness
        styled.metallic = profile.metallic
        styled.emission_enabled = profile.emission_enabled
        styled.rim_enabled = profile.rim_enabled
        # Keep original texture if present; fallback to profile texture only when missing.
        if styled.albedo_texture == null and profile.albedo_texture != null:
            styled.albedo_texture = profile.albedo_texture
        if styled.albedo_color == Color(1, 1, 1, 1):
            styled.albedo_color = profile.albedo_color
    else:
        styled.roughness = 0.9
        styled.metallic = 0.0
        styled.emission_enabled = false
        styled.rim_enabled = false

    return styled
