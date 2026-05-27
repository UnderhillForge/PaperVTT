extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TexturePaintTest] Start")
	var chunked_script: Script = load("res://addons/worldbrush/chunked_worldbrush.gd") as Script
	var worldbrush_script: Script = load("res://addons/worldbrush/worldbrush.gd") as Script
	if chunked_script == null or worldbrush_script == null:
		push_error("[TexturePaintTest] Missing terrain scripts")
		quit(2)
		return

	var tex_a: Texture2D = _make_solid_texture(Color(1.0, 0.15, 0.15, 1.0))
	var tex_b: Texture2D = _make_solid_texture(Color(0.15, 0.7, 1.0, 1.0))
	var ok_chunked: bool = await _run_backend_test(chunked_script, "chunked", tex_a, tex_b)
	var ok_worldbrush: bool = await _run_backend_test(worldbrush_script, "worldbrush", tex_a, tex_b)

	print("[TexturePaintTest] Chunked=", ok_chunked, " WorldBrush=", ok_worldbrush)
	quit(0 if ok_chunked and ok_worldbrush else 1)

func _make_solid_texture(c: Color) -> Texture2D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _run_backend_test(script_res: Script, label: String, tex_a: Texture2D, tex_b: Texture2D) -> bool:
	var terrain: Node3D = script_res.new() as Node3D
	if terrain == null:
		push_error("[TexturePaintTest] Could not instantiate backend: " + label)
		return false
	terrain.name = "Test_" + label
	root.add_child(terrain)
	terrain.call_deferred("set", "auto_test_snow", false)
	terrain.call_deferred("set", "seed_initial_terrain", true)
	await process_frame
	await process_frame

	var texture_calls: Array = [
		{"pos": Vector3(0.0, 0.0, 0.0), "tex": tex_a, "id": "test_tex_a"},
		{"pos": Vector3(8.0, 0.0, 8.0), "tex": _make_solid_texture(Color(0.95, 0.85, 0.15, 1.0)), "id": "test_tex_b"},
		{"pos": Vector3(-8.0, 0.0, 8.0), "tex": _make_solid_texture(Color(0.75, 0.25, 0.75, 1.0)), "id": "test_tex_c"},
		{"pos": Vector3(8.0, 0.0, -8.0), "tex": _make_solid_texture(Color(0.2, 0.8, 0.45, 1.0)), "id": "test_tex_d"},
		{"pos": Vector3(-8.0, 0.0, -8.0), "tex": _make_solid_texture(Color(0.2, 0.5, 0.95, 1.0)), "id": "test_tex_e"},
		{"pos": Vector3(16.0, 0.0, 0.0), "tex": _make_solid_texture(Color(0.95, 0.45, 0.2, 1.0)), "id": "test_tex_f"},
		{"pos": Vector3(-16.0, 0.0, 0.0), "tex": _make_solid_texture(Color(0.35, 0.85, 0.35, 1.0)), "id": "test_tex_g"},
		{"pos": Vector3(0.0, 0.0, 16.0), "tex": _make_solid_texture(Color(0.55, 0.55, 0.95, 1.0)), "id": "test_tex_h"},
		{"pos": Vector3(0.0, 0.0, -16.0), "tex": _make_solid_texture(Color(0.95, 0.55, 0.55, 1.0)), "id": "test_tex_i"},
		{"pos": Vector3(24.0, 0.0, 8.0), "tex": _make_solid_texture(Color(0.55, 0.95, 0.75, 1.0)), "id": "test_tex_j"},
		{"pos": Vector3(-24.0, 0.0, 8.0), "tex": _make_solid_texture(Color(0.85, 0.75, 0.25, 1.0)), "id": "test_tex_k"},
		{"pos": Vector3(24.0, 0.0, -8.0), "tex": _make_solid_texture(Color(0.4, 0.25, 0.85, 1.0)), "id": "test_tex_l"},
		{"pos": Vector3(-24.0, 0.0, -8.0), "tex": _make_solid_texture(Color(0.95, 0.95, 0.35, 1.0)), "id": "test_tex_m"}
	]
	for call_data in texture_calls:
		terrain.call("apply_texture_brush", call_data["pos"], call_data["tex"], null, null, null, null, 7.0, 0.75, 8.0, 1.0, 0.7, 1.0, Vector2.ZERO, 0.0, 1.0, 1.0, "circle", 0.0, 0.0, 0, "smooth", call_data["id"])

	var control_maps_before: Array = terrain.get("_control_map_images") as Array
	var control_0_before: Image = control_maps_before[0] as Image
	var red_before: int = 0
	for y in range(control_0_before.get_height()):
		for x in range(control_0_before.get_width()):
			if control_0_before.get_pixel(x, y).r > 0.01:
				red_before += 1

	terrain.call("apply_texture_brush", Vector3(38.0, 0.0, 42.0), tex_b, null, null, null, null, 12.0, 0.85, 8.0, 1.0, 0.7, 1.0, Vector2.ZERO, 0.0, 1.0, 1.0, "circle", 0.0, 0.0, 0, "sharp", "test_tex_b")

	var texture_layers_by_world: Dictionary = terrain.get("_layer_texture_weights") as Dictionary
	var active_layer: int = int(terrain.get("_active_world_layer"))
	var texture_layers: Array = texture_layers_by_world.get(active_layer, []) as Array
	var layer0_nonzero: int = 0
	var layer1_nonzero: int = 0
	if texture_layers.size() >= 2:
		var layer0: PackedFloat32Array = texture_layers[0] as PackedFloat32Array
		var layer1: PackedFloat32Array = texture_layers[1] as PackedFloat32Array
		for i in range(layer0.size()):
			if layer0[i] > 0.01:
				layer0_nonzero += 1
			if i < layer1.size() and layer1[i] > 0.01:
				layer1_nonzero += 1

	var control_maps_after: Array = terrain.get("_control_map_images") as Array
	var control_0_after: Image = control_maps_after[0] as Image
	var red_after: int = 0
	var green_after: int = 0
	for y in range(control_0_after.get_height()):
		for x in range(control_0_after.get_width()):
			var px: Color = control_0_after.get_pixel(x, y)
			if px.r > 0.01:
				red_after += 1
			if px.g > 0.01:
				green_after += 1

	var material_ok: bool = false
	var slot_count: int = 0
	var slot_ids: PackedStringArray = terrain.get("_texture_slot_ids") as PackedStringArray
	for i in range(slot_ids.size()):
		if slot_ids[i] != "":
			slot_count += 1
	var mat_variant: Variant = terrain.get("_material")
	if mat_variant is ShaderMaterial:
		var smat: ShaderMaterial = mat_variant as ShaderMaterial
		var paint_albedo_array: Variant = smat.get_shader_parameter("paint_albedo_array")
		var paint_normal_array: Variant = smat.get_shader_parameter("paint_normal_array")
		var paint_roughness_array: Variant = smat.get_shader_parameter("paint_roughness_array")
		material_ok = (paint_albedo_array is Texture2DArray) and (paint_normal_array is Texture2DArray) and (paint_roughness_array is Texture2DArray)
	elif mat_variant is StandardMaterial3D:
		material_ok = true

	print("[TexturePaintTest] ", label, " red_before=", red_before, " red_after=", red_after, " green_after=", green_after, " layer0_nonzero=", layer0_nonzero, " layer1_nonzero=", layer1_nonzero, " slot_count=", slot_count, " material_ok=", material_ok)
	terrain.queue_free()
	return layer0_nonzero > 0 and layer1_nonzero > 0 and slot_count >= 13 and material_ok
