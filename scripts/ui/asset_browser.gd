extends PanelContainer

signal prefab_selected(prefab_path: String)
signal prefab_activated(prefab_path: String)
signal stamp_mode_requested()

@onready var _search: LineEdit = %SearchLineEdit
@onready var _category_buttons_root: HBoxContainer = %CategoryButtons
@onready var _grid: GridContainer = %AssetGrid
@onready var _asset_count_label: Label = %AssetCount
@onready var _selected_info: Label = %SelectedInfo
@onready var _properties_popup: PopupPanel = %AssetPropertiesPopup
@onready var _prop_name: LineEdit = %PropNameEdit
@onready var _prop_uniform_scale: CheckBox = %PropUniformScaleCheck
@onready var _prop_scale_x: SpinBox = %PropScaleX
@onready var _prop_scale_y: SpinBox = %PropScaleY
@onready var _prop_scale_z: SpinBox = %PropScaleZ
@onready var _prop_category: OptionButton = %PropCategoryOption
@onready var _prop_tags: LineEdit = %PropTagsEdit
@onready var _prop_rot_x: SpinBox = %PropPreviewRotX
@onready var _prop_rot_y: SpinBox = %PropPreviewRotY
@onready var _prop_rot_z: SpinBox = %PropPreviewRotZ
@onready var _prop_save_btn: Button = %PropSaveButton
@onready var _prop_cancel_btn: Button = %PropCancelButton
@onready var _prop_regen_btn: Button = %PropRegenPreviewButton
@onready var _preview_viewport: SubViewport = %PreviewViewport
@onready var _preview_stage: Node3D = %PreviewStage
@onready var _preview_camera: Camera3D = %PreviewCamera
@onready var _preview_light: DirectionalLight3D = %PreviewLight

var _prefab_paths: Array[String] = []
@onready var _browser_root: VBoxContainer = $Margin/Root
@onready var _header_row: HBoxContainer = $Margin/Root/HeaderRow
@onready var _header_label: Label = $Margin/Root/HeaderRow/Header

var _collapsed: bool = false

var _active_category: String = "all"
var _category_buttons: Dictionary = {}
var _categories: Array[String] = ["all", "walls", "floors", "furniture", "props", "nature", "characters", "dungeon", "scatter", "rocks", "foliage", "debris", "flowers", "mushrooms", "dirt"]
var _selected_prefab: String = ""
var _selected_property_prefab: String = ""

var _manifest: Dictionary = {}
var _card_by_path: Dictionary = {}
var _preview_cache: Dictionary = {}
var _preview_targets: Dictionary = {}
var _preview_queue: Array[String] = []
var _preview_queued_set: Dictionary = {}
var _preview_failed_paths: Dictionary = {}
var _preview_pending_capture_path: String = ""
var _preview_pending_frames: int = 0

const THUMB_SIZE: Vector2i = Vector2i(160, 160)
const MANIFEST_PATH: String = "res://assets/world/library_manifest.json"
const PREVIEW_ROOT_PATH: String = "user://asset_previews"

func _ready() -> void:
	_search.text_changed.connect(_refresh_list)
	_prop_uniform_scale.toggled.connect(_on_uniform_scale_toggled)
	_prop_scale_x.value_changed.connect(_on_scale_x_changed)
	_prop_save_btn.pressed.connect(_save_asset_properties)
	_prop_cancel_btn.pressed.connect(func() -> void: _properties_popup.hide())
	_prop_regen_btn.pressed.connect(_regenerate_selected_preview)
	set_process(true)

	# Ensure thumbnail viewport renders 3D content even when embedded in UI.
	# Collapsible header - double-click the title bar to collapse/expand
	_header_row.mouse_filter = Control.MOUSE_FILTER_STOP
	_header_row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_header_row.gui_input.connect(_on_header_gui_input)

	_preview_viewport.disable_3d = false
	_preview_viewport.own_world_3d = true
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.size = THUMB_SIZE

	_load_manifest()
	_ensure_preview_folder()
	_build_category_tabs()
	_scan_prefabs()
	_refresh_list()
	_setup_property_categories()

func _build_category_tabs() -> void:
	for child in _category_buttons_root.get_children():
		child.queue_free()
	_category_buttons.clear()

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click and mb.pressed:
			_set_collapsed(not _collapsed)
			get_viewport().set_input_as_handled()

func _set_collapsed(value: bool) -> void:
	_collapsed = value
	for child in _browser_root.get_children():
		if child == _header_row:
			continue
		child.visible = not _collapsed
	_header_label.text = "Library  ▶" if _collapsed else "Library  ▼"

	var group := ButtonGroup.new()
	for category in _categories:
		var button := Button.new()
		button.text = category.capitalize()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(74, 30)
		button.pressed.connect(_on_category_pressed.bind(category))
		_category_buttons_root.add_child(button)
		_category_buttons[category] = button

	if _category_buttons.has("all"):
		(_category_buttons["all"] as Button).button_pressed = true

func _setup_property_categories() -> void:
	_prop_category.clear()
	for category in _categories:
		if category == "all":
			continue
		_prop_category.add_item(category)

func _on_category_pressed(category: String) -> void:
	_active_category = category
	_refresh_list()

func _scan_prefabs() -> void:
	_prefab_paths.clear()
	_walk_prefabs("res://assets/world/models")
	_prefab_paths.sort()
	_ensure_manifest_entries()

func _walk_prefabs(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var entry_name := dir.get_next()
		if entry_name == "":
			break
		if entry_name.begins_with("."):
			continue
		var full := "%s/%s" % [path, entry_name]
		if dir.current_is_dir():
			_walk_prefabs(full)
		elif entry_name.ends_with(".tscn") or entry_name.ends_with(".glb") or entry_name.ends_with(".blend"):
			_prefab_paths.append(full)
	dir.list_dir_end()

func _refresh_list(_unused: String = "") -> void:
	for child in _grid.get_children():
		child.queue_free()
	_card_by_path.clear()
	_preview_targets.clear()
	_preview_queue.clear()
	_preview_queued_set.clear()
	_preview_pending_capture_path = ""
	_preview_pending_frames = 0

	var text_filter := _search.text.strip_edges().to_lower()
	var category_filter := _active_category
	var shown: int = 0

	for path in _prefab_paths:
		var entry: Dictionary = _get_asset_entry(path)
		var entry_category: String = String(entry.get("category", _derive_category_from_path(path))).to_lower()
		if category_filter != "all" and entry_category != category_filter:
			continue

		var display_name: String = String(entry.get("name", _default_display_name(path)))
		var tags: PackedStringArray = PackedStringArray(entry.get("tags", PackedStringArray()))
		var searchable: String = "%s %s %s" % [path.to_lower(), display_name.to_lower(), " ".join(tags).to_lower()]
		if text_filter != "" and not searchable.contains(text_filter):
			continue

		var card: PanelContainer = _build_asset_card(path, display_name)
		_grid.add_child(card)
		_card_by_path[path] = card
		_enqueue_preview(path, card.get_meta("thumb") as TextureRect)
		shown += 1

	_asset_count_label.text = "%d assets" % shown
	if shown > 0:
		if _selected_prefab == "" or not _card_by_path.has(_selected_prefab):
			_selected_prefab = String(_card_by_path.keys()[0])
		_select_prefab(_selected_prefab)
	else:
		_selected_info.text = "No prefabs match current filters"

func _build_asset_card(path: String, display_name: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(170, 210)
	card.tooltip_text = display_name
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_card_gui_input.bind(path))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)

	var thumb := TextureRect.new()
	thumb.custom_minimum_size = Vector2(160, 160)
	thumb.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb.texture = _placeholder_texture()
	vb.add_child(thumb)

	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(160, 40)
	label.text = display_name
	vb.add_child(label)

	card.set_meta("thumb", thumb)
	card.set_meta("label", label)
	return card

func _on_card_gui_input(event: InputEvent, path: String) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_select_prefab(path)
			if mb.double_click:
				prefab_activated.emit(path)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_open_properties_for(path)

func _select_prefab(path: String) -> void:
	_selected_prefab = path
	_selected_info.text = "Selected: %s" % String(_get_asset_entry(path).get("name", _default_display_name(path)))
	prefab_selected.emit(path)
	stamp_mode_requested.emit()
	_update_selection_visuals()

# Styles created once and reused to avoid per-frame allocation.
var _style_normal: StyleBoxFlat = null
var _style_selected: StyleBoxFlat = null

func _ensure_card_styles() -> void:
	if _style_normal != null:
		return
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.14, 0.16, 0.14, 1.0)
	_style_normal.border_width_left = 2
	_style_normal.border_width_right = 2
	_style_normal.border_width_top = 2
	_style_normal.border_width_bottom = 2
	_style_normal.border_color = Color(0.0, 0.0, 0.0, 0.0)
	_style_normal.corner_radius_top_left = 4
	_style_normal.corner_radius_top_right = 4
	_style_normal.corner_radius_bottom_left = 4
	_style_normal.corner_radius_bottom_right = 4

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0.14, 0.22, 0.28, 1.0)
	_style_selected.border_width_left = 2
	_style_selected.border_width_right = 2
	_style_selected.border_width_top = 2
	_style_selected.border_width_bottom = 2
	_style_selected.border_color = Color(0.35, 0.78, 1.0, 1.0)
	_style_selected.corner_radius_top_left = 4
	_style_selected.corner_radius_top_right = 4
	_style_selected.corner_radius_bottom_left = 4
	_style_selected.corner_radius_bottom_right = 4

func _update_selection_visuals() -> void:
	_ensure_card_styles()
	for path: String in _card_by_path.keys():
		var card: PanelContainer = _card_by_path[path]
		card.self_modulate = Color(1.0, 1.0, 1.0, 1.0)
		if path == _selected_prefab:
			card.add_theme_stylebox_override("panel", _style_selected)
			(card.get_meta("label") as Label).modulate = Color(0.6, 0.95, 1.0, 1.0)
		else:
			card.add_theme_stylebox_override("panel", _style_normal)
			(card.get_meta("label") as Label).modulate = Color(1.0, 1.0, 1.0, 1.0)

func _process(_delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _preview_pending_capture_path != "":
		if _preview_pending_frames > 0:
			_preview_pending_frames -= 1
			return
		_capture_pending_preview()
		return
	if _preview_queue.is_empty():
		return
	var next_path: String = _preview_queue.pop_front()
	_preview_queued_set.erase(next_path)
	if _setup_preview_scene(next_path):
		_preview_pending_capture_path = next_path
		_preview_pending_frames = 2
	else:
		_set_preview_result(next_path, _placeholder_texture())

func _enqueue_preview(path: String, target: TextureRect) -> void:
	if _preview_failed_paths.has(path):
		target.texture = _placeholder_texture()
		return

	if _preview_cache.has(path):
		target.texture = _preview_cache[path]
		return

	var cached: Texture2D = _load_cached_preview(path)
	if cached != null:
		_preview_cache[path] = cached
		target.texture = cached
		return

	if not _preview_targets.has(path):
		_preview_targets[path] = []
	(_preview_targets[path] as Array).append(target)
	if not _preview_queued_set.has(path):
		_preview_queue.append(path)
		_preview_queued_set[path] = true

func _set_preview_result(path: String, texture: Texture2D) -> void:
	_preview_cache[path] = texture
	if _preview_targets.has(path):
		var targets: Array = _preview_targets[path]
		for target_var in targets:
			if target_var is TextureRect and is_instance_valid(target_var):
				(target_var as TextureRect).texture = texture
		_preview_targets.erase(path)

func _setup_preview_scene(path: String) -> bool:
	for child in _preview_stage.get_children():
		child.queue_free()

	if _preview_failed_paths.has(path):
		return false

	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		_preview_failed_paths[path] = true
		return false
	var inst: Node = packed.instantiate()
	if inst == null:
		_preview_failed_paths[path] = true
		return false

	var holder := Node3D.new()
	holder.name = "PreviewHolder"
	_preview_stage.add_child(holder)
	holder.add_child(inst)

	var entry: Dictionary = _get_asset_entry(path)
	if inst is Node3D:
		(inst as Node3D).scale *= _scale_from_entry(entry)

	var aabb_data: Dictionary = _collect_scene_aabb(holder)
	if not bool(aabb_data.get("valid", false)):
		_preview_failed_paths[path] = true
		return false
	var aabb: AABB = aabb_data["aabb"]
	var center: Vector3 = aabb.position + aabb.size * 0.5
	var radius: float = maxf(aabb.size.length() * 0.45, 0.6)

	var rot: Vector3 = _preview_rotation_from_entry(entry)
	var pitch: float = deg_to_rad(rot.x)
	var yaw: float = deg_to_rad(rot.y)
	var dir := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * Vector3(0.0, 0.0, 1.0)
	var dist: float = radius * 2.4

	_preview_camera.position = center + dir.normalized() * dist
	_preview_camera.look_at(center, Vector3.UP)
	_preview_camera.near = 0.05
	_preview_camera.far = maxf(100.0, dist * 4.0)
	_preview_light.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	return true

func _capture_pending_preview() -> void:
	var path: String = _preview_pending_capture_path
	_preview_pending_capture_path = ""

	var image: Image = _preview_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_set_preview_result(path, _placeholder_texture())
		return

	image.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var tex: ImageTexture = ImageTexture.create_from_image(image)
	_save_preview_to_cache(path, image)
	_set_preview_result(path, tex)

func _collect_scene_aabb(root: Node3D) -> Dictionary:
	var has_any: bool = false
	var merged := AABB()
	var stack: Array[Node3D] = [root]

	while not stack.is_empty():
		var node: Node3D = stack.pop_back()
		if node is MeshInstance3D:
			var mesh_node: MeshInstance3D = node as MeshInstance3D
			if mesh_node.mesh != null:
				var local_aabb: AABB = mesh_node.mesh.get_aabb()
				var world_aabb: AABB = _transform_aabb(local_aabb, mesh_node.global_transform)
				if not has_any:
					merged = world_aabb
					has_any = true
				else:
					merged = merged.merge(world_aabb)

		for child in node.get_children():
			if child is Node3D:
				stack.append(child as Node3D)

	return {"valid": has_any, "aabb": merged}

func _transform_aabb(aabb: AABB, xform: Transform3D) -> AABB:
	var points := [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0.0, 0.0),
		aabb.position + Vector3(0.0, aabb.size.y, 0.0),
		aabb.position + Vector3(0.0, 0.0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0.0),
		aabb.position + Vector3(aabb.size.x, 0.0, aabb.size.z),
		aabb.position + Vector3(0.0, aabb.size.y, aabb.size.z),
		aabb.position + aabb.size
	]
	var first: Vector3 = xform * points[0]
	var result := AABB(first, Vector3.ZERO)
	for i in range(1, points.size()):
		result = result.expand(xform * points[i])
	return result

func _default_display_name(path: String) -> String:
	return path.trim_prefix("res://assets/world/models/").trim_suffix(".tscn").trim_suffix(".glb").trim_suffix(".blend")

func _derive_category_from_path(path: String) -> String:
	var lower: String = path.to_lower()
	if lower.contains("/scatter/"):
		if lower.contains("/rocks/"):
			return "rocks"
		if lower.contains("/foliage/"):
			return "foliage"
		if lower.contains("/debris/"):
			return "debris"
		if lower.contains("/flowers/"):
			return "flowers"
		if lower.contains("/mushrooms/"):
			return "mushrooms"
		if lower.contains("/dirt/"):
			return "dirt"
		return "scatter"
	for category in _categories:
		if category == "all":
			continue
		if lower.contains("/" + category + "/"):
			return category
	return "props"

func _get_asset_entry(path: String) -> Dictionary:
	var assets: Dictionary = _manifest.get("assets", {})
	if not assets.has(path):
		assets[path] = {
			"name": _default_display_name(path),
			"category": _derive_category_from_path(path),
			"scale": [1.0, 1.0, 1.0],
			"uniform_scale": true,
			"tags": PackedStringArray(),
			"preview_rotation": [18.0, 28.0, 0.0]
		}
		_manifest["assets"] = assets
	return assets[path]

func _ensure_manifest_entries() -> void:
	for path in _prefab_paths:
		_get_asset_entry(path)
	_save_manifest()

func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		_manifest = {"assets": {}}
		_save_manifest()
		return
	var f: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if f == null:
		_manifest = {"assets": {}}
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		_manifest = parsed
	else:
		_manifest = {"assets": {}}
	if not _manifest.has("assets"):
		_manifest["assets"] = {}

func _save_manifest() -> void:
	var f: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_manifest, "\t"))

func _open_properties_for(path: String) -> void:
	_selected_property_prefab = path
	var entry: Dictionary = _get_asset_entry(path)
	_prop_name.text = String(entry.get("name", _default_display_name(path)))
	_prop_uniform_scale.button_pressed = bool(entry.get("uniform_scale", true))
	var prop_scale: Vector3 = _scale_from_entry(entry)
	_prop_scale_x.value = prop_scale.x
	_prop_scale_y.value = prop_scale.y
	_prop_scale_z.value = prop_scale.z
	_set_category_option(String(entry.get("category", _derive_category_from_path(path))))
	_prop_tags.text = ",".join(PackedStringArray(entry.get("tags", PackedStringArray())))
	var rot: Vector3 = _preview_rotation_from_entry(entry)
	_prop_rot_x.value = rot.x
	_prop_rot_y.value = rot.y
	_prop_rot_z.value = rot.z
	_properties_popup.popup_centered(Vector2i(420, 420))

func _set_category_option(category: String) -> void:
	for i in range(_prop_category.item_count):
		if _prop_category.get_item_text(i).to_lower() == category.to_lower():
			_prop_category.select(i)
			return

func _save_asset_properties() -> void:
	if _selected_property_prefab == "":
		return
	var entry: Dictionary = _get_asset_entry(_selected_property_prefab)
	entry["name"] = _prop_name.text.strip_edges()
	entry["uniform_scale"] = _prop_uniform_scale.button_pressed
	entry["scale"] = [_prop_scale_x.value, _prop_scale_y.value, _prop_scale_z.value]
	entry["category"] = _prop_category.get_item_text(_prop_category.selected).to_lower()
	entry["tags"] = _parse_tags(_prop_tags.text)
	entry["preview_rotation"] = [_prop_rot_x.value, _prop_rot_y.value, _prop_rot_z.value]

	var assets: Dictionary = _manifest.get("assets", {})
	assets[_selected_property_prefab] = entry
	_manifest["assets"] = assets
	_save_manifest()

	# Invalidate preview and regenerate with new rotation/scale.
	_preview_cache.erase(_selected_property_prefab)
	_delete_cached_preview(_selected_property_prefab)
	_enqueue_preview(_selected_property_prefab, _card_by_path[_selected_property_prefab].get_meta("thumb") as TextureRect)

	_properties_popup.hide()
	_refresh_list()

func _parse_tags(text: String) -> PackedStringArray:
	var raw: PackedStringArray = text.split(",", false)
	var tags: PackedStringArray = PackedStringArray()
	for tag in raw:
		var t: String = tag.strip_edges().to_lower()
		if t != "":
			tags.append(t)
	return tags

func _on_uniform_scale_toggled(enabled: bool) -> void:
	if enabled:
		_prop_scale_y.value = _prop_scale_x.value
		_prop_scale_z.value = _prop_scale_x.value

func _on_scale_x_changed(value: float) -> void:
	if _prop_uniform_scale.button_pressed:
		_prop_scale_y.value = value
		_prop_scale_z.value = value

func _regenerate_selected_preview() -> void:
	if _selected_property_prefab == "":
		return
	_preview_cache.erase(_selected_property_prefab)
	_delete_cached_preview(_selected_property_prefab)
	if _card_by_path.has(_selected_property_prefab):
		_enqueue_preview(_selected_property_prefab, _card_by_path[_selected_property_prefab].get_meta("thumb") as TextureRect)

func _scale_from_entry(entry: Dictionary) -> Vector3:
	var data: Array = entry.get("scale", [1.0, 1.0, 1.0])
	if data.size() < 3:
		return Vector3.ONE
	return Vector3(float(data[0]), float(data[1]), float(data[2]))

func _preview_rotation_from_entry(entry: Dictionary) -> Vector3:
	var data: Array = entry.get("preview_rotation", [18.0, 28.0, 0.0])
	if data.size() < 3:
		return Vector3(18.0, 28.0, 0.0)
	return Vector3(float(data[0]), float(data[1]), float(data[2]))

func get_scale_for_prefab(prefab_path: String) -> Vector3:
	return _scale_from_entry(_get_asset_entry(prefab_path))

func _placeholder_texture() -> Texture2D:
	var img := Image.create(THUMB_SIZE.x, THUMB_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.12, 0.12, 0.13, 1.0))
	return ImageTexture.create_from_image(img)

func _preview_cache_path(prefab_path: String) -> String:
	var rel: String = prefab_path.trim_prefix("res://assets/world/models/").trim_suffix(".tscn").trim_suffix(".glb").trim_suffix(".blend")
	return "%s/%s.png" % [PREVIEW_ROOT_PATH, rel]

func _ensure_preview_folder() -> void:
	var abs_root: String = ProjectSettings.globalize_path(PREVIEW_ROOT_PATH)
	DirAccess.make_dir_recursive_absolute(abs_root)

func _load_cached_preview(prefab_path: String) -> Texture2D:
	if DisplayServer.get_name() == "headless":
		return null
	var cache_path: String = _preview_cache_path(prefab_path)
	var abs_path: String = ProjectSettings.globalize_path(cache_path)
	if not FileAccess.file_exists(abs_path):
		return null
	var img := Image.new()
	var err: Error = img.load(abs_path)
	if err != OK:
		return null
	if _is_likely_invalid_preview(img):
		return null
	return ImageTexture.create_from_image(img)

func _save_preview_to_cache(prefab_path: String, image: Image) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var cache_path: String = _preview_cache_path(prefab_path)
	var abs_path: String = ProjectSettings.globalize_path(cache_path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	image.save_png(abs_path)

func _delete_cached_preview(prefab_path: String) -> void:
	var cache_path: String = _preview_cache_path(prefab_path)
	var abs_path: String = ProjectSettings.globalize_path(cache_path)
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)

func _is_likely_invalid_preview(image: Image) -> bool:
	if image == null or image.is_empty():
		return true
	var w: int = image.get_width()
	var h: int = image.get_height()
	if w <= 0 or h <= 0:
		return true

	var sample_points := [
		Vector2i(w >> 2, h >> 2),
		Vector2i(w >> 1, h >> 2),
		Vector2i(w * 3 >> 2, h >> 2),
		Vector2i(w >> 2, h >> 1),
		Vector2i(w >> 1, h >> 1),
		Vector2i(w * 3 >> 2, h >> 1),
		Vector2i(w >> 2, h * 3 >> 2),
		Vector2i(w >> 1, h * 3 >> 2),
		Vector2i(w * 3 >> 2, h * 3 >> 2)
	]

	var total_luma: float = 0.0
	for p in sample_points:
		var c: Color = image.get_pixel(clampi(p.x, 0, w - 1), clampi(p.y, 0, h - 1))
		total_luma += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var avg_luma: float = total_luma / float(sample_points.size())
	return avg_luma < 0.02
