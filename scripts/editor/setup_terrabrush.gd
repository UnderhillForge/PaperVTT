@tool
extends EditorScript

func _run():
	var scene_root = EditorInterface.get_edited_scene_root()
	if not scene_root:
		push_error("No scene open")
		return
	
	var tb_node = scene_root.find_child("TerraBrush", true, false)
	if not tb_node:
		push_error("No TerraBrush node found in scene")
		return
	
	print("Found TerraBrush node: ", tb_node)
	print("Node class: ", tb_node.get_class())
	print("Data path: ", tb_node.get("dataPath"))
	
	# Create a TextureSetResource for grass
	var texture_set = ClassDB.instantiate("TextureSetResource")
	if not texture_set:
		push_error("Could not instantiate TextureSetResource")
		return
	
	# Load grass texture (albedo)
	var albedo = load("res://assets/world/textures/world/grass_02_2k/grass_02_base_2k.png")
	var normal = load("res://assets/world/textures/world/grass_02_2k/grass_02_normal_gl_2k.png")
	var roughness = load("res://assets/world/textures/world/grass_02_2k/grass_02_roughness_2k.png")
	var height = load("res://assets/world/textures/world/grass_02_2k/grass_02_height_2k.png")
	
	if not albedo:
		push_error("Could not load grass albedo texture")
		return
	
	texture_set.set("name", "Grass")
	texture_set.set("albedoTexture", albedo)
	if normal: texture_set.set("normalTexture", normal)
	if roughness: texture_set.set("roughnessTexture", roughness)
	if height: texture_set.set("heightTexture", height)
	
	# Create a second texture set for cliff/rock
	var texture_set2 = ClassDB.instantiate("TextureSetResource")
	var albedo2 = load("res://assets/world/textures/world/cliff_rocks_02_2k/cliff_rocks_02_baseColor_2k.png")
	var normal2 = load("res://assets/world/textures/world/cliff_rocks_02_2k/cliff_rocks_02_normal_gl_2k.png")
	var roughness2 = load("res://assets/world/textures/world/cliff_rocks_02_2k/cliff_rocks_02_roughness_2k.png")
	var height2 = load("res://assets/world/textures/world/cliff_rocks_02_2k/cliff_rocks_02_height_2k.png")
	
	if texture_set2:
		texture_set2.set("name", "Cliff Rock")
		if albedo2: texture_set2.set("albedoTexture", albedo2)
		if normal2: texture_set2.set("normalTexture", normal2)
		if roughness2: texture_set2.set("roughnessTexture", roughness2)
		if height2: texture_set2.set("heightTexture", height2)
	
	# Create a TextureSetsResource containing both sets
	var texture_sets_resource = ClassDB.instantiate("TextureSetsResource")
	if not texture_sets_resource:
		push_error("Could not instantiate TextureSetsResource")
		return
	
	var sets_array = [texture_set]
	if texture_set2:
		sets_array.append(texture_set2)
	texture_sets_resource.set("textureSets", sets_array)
	
	# Assign to TerraBrush node
	tb_node.set("textureSets", texture_sets_resource)
	
	print("Assigned texture sets. Calling onUpdateTerrainSettings...")
	
	# Create terrain data directory
	DirAccess.make_dir_recursive_absolute("res://terrain_data/test")
	
	# Trigger terrain creation
	tb_node.call("onUpdateTerrainSettings")
	
	print("Setup complete! Terrain should now be visible.")
	
	# Save the scene
	EditorInterface.save_scene()
	print("Scene saved.")
