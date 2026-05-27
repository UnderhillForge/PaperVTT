@tool
extends EditorPlugin

const CAMERA_SCRIPT: Script = preload("res://addons/post_process_outlines/pp_outlines_camera.gd")

func _enter_tree() -> void:
	var icon: Texture2D = get_editor_interface().get_base_control().get_theme_icon("Camera3D", "EditorIcons")
	add_custom_type("PPOutlinesCamera", "Camera3D", CAMERA_SCRIPT, icon)

func _exit_tree() -> void:
	remove_custom_type("PPOutlinesCamera")
