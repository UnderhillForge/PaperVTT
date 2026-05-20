extends VBoxContainer
class_name GMAudioPanel

const NOW_PLAYING_WINDOW_CHARS: int = 44
const NOW_PLAYING_SCROLL_STEP_SECONDS: float = 0.14
const NOW_PLAYING_SCROLL_GAP: String = "   •   "

var _playlist_option: OptionButton = null
var _playlist_name_edit: LineEdit = null
var _track_list: ItemList = null
var _now_playing_label: Label = null
var _play_pause_button: Button = null
var _seek_slider: HSlider = null
var _time_label: Label = null
var _master_volume_slider: HSlider = null
var _playlist_volume_slider: HSlider = null
var _loop_check: CheckBox = null
var _shuffle_check: CheckBox = null
var _category_option: OptionButton = null
var _tags_edit: LineEdit = null
var _folder_edit: LineEdit = null
var _crossfade_slider: HSlider = null
var _crossfade_label: Label = null
var _description_edit: TextEdit = null
var _authority_label: Label = null
var _sync_log: RichTextLabel = null
var _import_dialog: FileDialog = null
var _playlists: Array[Resource] = []
var _playlist_paths: Array[String] = []
var _is_updating_seek: bool = false
var _now_playing_full_text: String = "Now Playing: -"
var _now_playing_scroll_offset: int = 0
var _now_playing_scroll_accum: float = 0.0

func _ready() -> void:
	name = "GMAudioPanel"
	add_theme_constant_override("separation", 8)
	_build_ui()
	_bind_audio_signals()
	_refresh_playlists_from_disk()
	_update_ui_from_manager()
	set_process(true)

func _process(_delta: float) -> void:
	_update_now_playing_marquee(_delta)
	var am: Node = _am()
	if am == null:
		return
	if _seek_slider == null or _is_updating_seek:
		return
	var duration: float = float(am.call("get_track_duration"))
	duration = maxf(duration, 0.0)
	if duration <= 0.0:
		_seek_slider.max_value = 1.0
		_seek_slider.value = 0.0
		_time_label.text = "00:00 / 00:00"
		return
	_seek_slider.max_value = duration
	_seek_slider.value = clampf(float(am.call("get_track_position")), 0.0, duration)
	_time_label.text = "%s / %s" % [_format_time(_seek_slider.value), _format_time(duration)]

func _build_ui() -> void:
	var title := Label.new()
	title.text = "Audio (GM)"
	title.add_theme_font_size_override("font_size", 15)
	add_child(title)

	var playlist_row := HBoxContainer.new()
	playlist_row.add_theme_constant_override("separation", 6)
	add_child(playlist_row)

	_playlist_option = OptionButton.new()
	_playlist_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playlist_option.fit_to_longest_item = false
	_playlist_option.clip_text = true
	_playlist_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_playlist_option.custom_minimum_size = Vector2(140, 0)
	_playlist_option.item_selected.connect(_on_playlist_selected)
	playlist_row.add_child(_playlist_option)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.custom_minimum_size = Vector2(56, 0)
	load_button.pressed.connect(_on_load_playlist_pressed)
	playlist_row.add_child(load_button)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.custom_minimum_size = Vector2(56, 0)
	save_button.pressed.connect(_on_save_playlist_pressed)
	playlist_row.add_child(save_button)

	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override("separation", 6)
	add_child(create_row)

	_playlist_name_edit = LineEdit.new()
	_playlist_name_edit.placeholder_text = "New playlist name"
	_playlist_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_playlist_name_edit)

	var create_button := Button.new()
	create_button.text = "Create"
	create_button.pressed.connect(_on_create_playlist_pressed)
	create_row.add_child(create_button)

	var import_row := HBoxContainer.new()
	import_row.add_theme_constant_override("separation", 6)
	add_child(import_row)

	var import_button := Button.new()
	import_button.text = "Import Track (.ogg/.mp3)"
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.pressed.connect(_on_import_track_pressed)
	import_row.add_child(import_button)

	_authority_label = Label.new()
	_authority_label.text = "Role: Unknown"
	_authority_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_authority_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_authority_label)

	var metadata_title := Label.new()
	metadata_title.text = "Playlist Metadata"
	metadata_title.add_theme_font_size_override("font_size", 13)
	add_child(metadata_title)

	var category_row := HBoxContainer.new()
	category_row.add_theme_constant_override("separation", 6)
	add_child(category_row)
	var category_label := Label.new()
	category_label.text = "Category"
	category_row.add_child(category_label)
	_category_option = OptionButton.new()
	_category_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_option.add_item("Ambience")
	_category_option.set_item_metadata(0, "ambience")
	_category_option.add_item("Combat")
	_category_option.set_item_metadata(1, "combat")
	_category_option.add_item("Exploration")
	_category_option.set_item_metadata(2, "exploration")
	_category_option.add_item("Social")
	_category_option.set_item_metadata(3, "social")
	_category_option.add_item("Misc")
	_category_option.set_item_metadata(4, "misc")
	category_row.add_child(_category_option)

	_tags_edit = LineEdit.new()
	_tags_edit.placeholder_text = "Tags (comma separated)"
	add_child(_tags_edit)

	_folder_edit = LineEdit.new()
	_folder_edit.placeholder_text = "Folder (e.g. Session 01/Inn)"
	add_child(_folder_edit)

	var crossfade_row := HBoxContainer.new()
	crossfade_row.add_theme_constant_override("separation", 6)
	add_child(crossfade_row)
	var crossfade_title := Label.new()
	crossfade_title.text = "Crossfade"
	crossfade_row.add_child(crossfade_title)
	_crossfade_label = Label.new()
	_crossfade_label.text = "0.0s"
	crossfade_row.add_child(_crossfade_label)
	_crossfade_slider = HSlider.new()
	_crossfade_slider.min_value = 0.0
	_crossfade_slider.max_value = 12.0
	_crossfade_slider.step = 0.1
	_crossfade_slider.value_changed.connect(func(v: float) -> void:
		if _crossfade_label != null:
			_crossfade_label.text = "%.1fs" % v
	)
	add_child(_crossfade_slider)

	_description_edit = TextEdit.new()
	_description_edit.custom_minimum_size = Vector2(0, 56)
	_description_edit.placeholder_text = "Playlist notes / purpose"
	add_child(_description_edit)

	var apply_meta_button := Button.new()
	apply_meta_button.text = "Apply Metadata"
	apply_meta_button.pressed.connect(_on_apply_metadata_pressed)
	add_child(apply_meta_button)

	_track_list = ItemList.new()
	_track_list.custom_minimum_size = Vector2(0, 110)
	_track_list.select_mode = ItemList.SELECT_SINGLE
	_track_list.item_selected.connect(_on_track_selected)
	add_child(_track_list)

	_now_playing_label = Label.new()
	_now_playing_label.text = "Now Playing: -"
	_now_playing_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_playing_label.clip_text = true
	_now_playing_label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	_now_playing_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_now_playing_label)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 6)
	add_child(controls)

	var prev_button := Button.new()
	prev_button.text = "Prev"
	prev_button.pressed.connect(func() -> void:
		var am: Node = _am()
		if am != null:
			am.call("previous_track")
	)
	controls.add_child(prev_button)

	_play_pause_button = Button.new()
	_play_pause_button.text = "Play"
	_play_pause_button.pressed.connect(func() -> void:
		var am: Node = _am()
		if am != null:
			am.call("play_pause")
	)
	controls.add_child(_play_pause_button)

	var stop_button := Button.new()
	stop_button.text = "Stop"
	stop_button.pressed.connect(func() -> void:
		var am: Node = _am()
		if am != null:
			am.call("stop")
	)
	controls.add_child(stop_button)

	var next_button := Button.new()
	next_button.text = "Next"
	next_button.pressed.connect(func() -> void:
		var am: Node = _am()
		if am != null:
			am.call("next_track")
	)
	controls.add_child(next_button)

	_seek_slider = HSlider.new()
	_seek_slider.min_value = 0.0
	_seek_slider.max_value = 1.0
	_seek_slider.step = 0.01
	_seek_slider.drag_ended.connect(_on_seek_drag_ended)
	add_child(_seek_slider)

	_time_label = Label.new()
	_time_label.text = "00:00 / 00:00"
	add_child(_time_label)

	var master_row := HBoxContainer.new()
	master_row.add_theme_constant_override("separation", 6)
	add_child(master_row)

	var master_label := Label.new()
	master_label.text = "Master Vol"
	master_row.add_child(master_label)

	_master_volume_slider = HSlider.new()
	_master_volume_slider.min_value = -48.0
	_master_volume_slider.max_value = 6.0
	_master_volume_slider.step = 0.5
	_master_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_master_volume_slider.value_changed.connect(func(v: float) -> void:
		var am: Node = _am()
		if am != null:
			am.call("set_master_volume_db", v)
	)
	master_row.add_child(_master_volume_slider)

	var playlist_vol_row := HBoxContainer.new()
	playlist_vol_row.add_theme_constant_override("separation", 6)
	add_child(playlist_vol_row)

	var playlist_vol_label := Label.new()
	playlist_vol_label.text = "Playlist Vol"
	playlist_vol_row.add_child(playlist_vol_label)

	_playlist_volume_slider = HSlider.new()
	_playlist_volume_slider.min_value = -48.0
	_playlist_volume_slider.max_value = 6.0
	_playlist_volume_slider.step = 0.5
	_playlist_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playlist_volume_slider.value_changed.connect(func(v: float) -> void:
		var am: Node = _am()
		if am != null:
			am.call("set_playlist_volume_db", v)
	)
	playlist_vol_row.add_child(_playlist_volume_slider)

	var flags_row := HBoxContainer.new()
	flags_row.add_theme_constant_override("separation", 12)
	add_child(flags_row)

	_loop_check = CheckBox.new()
	_loop_check.text = "Loop Playlist"
	_loop_check.toggled.connect(func(v: bool) -> void:
		var am: Node = _am()
		if am != null:
			am.call("set_loop_enabled", v)
	)
	flags_row.add_child(_loop_check)

	_shuffle_check = CheckBox.new()
	_shuffle_check.text = "Shuffle"
	_shuffle_check.toggled.connect(func(v: bool) -> void:
		var am: Node = _am()
		if am != null:
			am.call("set_shuffle_enabled", v)
	)
	flags_row.add_child(_shuffle_check)

	_import_dialog = FileDialog.new()
	_import_dialog.title = "Import Audio Track"
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.add_filter("*.ogg ; Ogg Vorbis")
	_import_dialog.add_filter("*.mp3 ; MP3")
	_import_dialog.add_filter("*.wav ; Wave")
	_import_dialog.file_selected.connect(_on_track_file_selected)
	add_child(_import_dialog)

func _bind_audio_signals() -> void:
	var am: Node = _am()
	if am == null:
		_append_sync_message("[UI] AudioManager autoload not found")
		return
	if not am.is_connected("track_changed", Callable(self, "_on_track_changed")):
		am.connect("track_changed", Callable(self, "_on_track_changed"))
	if not am.is_connected("playback_state_changed", Callable(self, "_on_playback_state_changed")):
		am.connect("playback_state_changed", Callable(self, "_on_playback_state_changed"))
	if not am.is_connected("playlist_changed", Callable(self, "_on_playlist_changed")):
		am.connect("playlist_changed", Callable(self, "_on_playlist_changed"))
	if not am.is_connected("volume_changed", Callable(self, "_on_volume_changed")):
		am.connect("volume_changed", Callable(self, "_on_volume_changed"))
	if not am.is_connected("sync_message_logged", Callable(self, "_append_sync_message")):
		am.connect("sync_message_logged", Callable(self, "_append_sync_message"))

func _refresh_playlists_from_disk() -> void:
	_playlist_option.clear()
	_playlists.clear()
	_playlist_paths.clear()
	var am: Node = _am()
	if am == null:
		_playlist_option.add_item("AudioManager missing")
		return
	var paths: Array = am.call("list_playlists")
	for path_variant in paths:
		var path: String = String(path_variant)
		var playlist: Resource = am.call("load_playlist", path)
		if playlist == null:
			continue
		_playlist_paths.append(path)
		_playlists.append(playlist)
		_playlist_option.add_item(String(playlist.get("playlist_name")))
	if _playlist_option.item_count == 0:
		_playlist_option.add_item("No playlists")
		_playlist_option.disabled = true
	else:
		_playlist_option.disabled = false

func _on_create_playlist_pressed() -> void:
	var am: Node = _am()
	if am == null:
		return
	var name_text: String = _playlist_name_edit.text.strip_edges()
	var playlist: Resource = am.call("create_playlist", name_text)
	var save_path: String = String(am.call("save_playlist", playlist))
	if save_path == "":
		_append_sync_message("[UI] Failed to create playlist")
		return
	_refresh_playlists_from_disk()
	_select_playlist_by_path(save_path)
	am.call("set_current_playlist", playlist)
	_update_ui_from_manager()

func _on_save_playlist_pressed() -> void:
	var am: Node = _am()
	if am == null:
		return
	var current_playlist: Resource = am.get("current_playlist") as Resource
	if current_playlist == null:
		_append_sync_message("[UI] No active playlist to save")
		return
	var path: String = String(am.call("save_playlist", current_playlist))
	if path == "":
		_append_sync_message("[UI] Save failed")
		return
	_append_sync_message("[UI] Saved playlist: %s" % path)
	_refresh_playlists_from_disk()
	_select_playlist_by_path(path)

func _on_load_playlist_pressed() -> void:
	var am: Node = _am()
	if am == null:
		return
	var idx: int = _playlist_option.selected
	if idx < 0 or idx >= _playlists.size():
		return
	am.call("set_current_playlist", _playlists[idx])
	_update_ui_from_manager()

func _on_playlist_selected(_index: int) -> void:
	pass

func _on_apply_metadata_pressed() -> void:
	var am: Node = _am()
	if am == null:
		return
	var playlist: Resource = am.get("current_playlist") as Resource
	if playlist == null:
		_append_sync_message("[UI] Load a playlist before applying metadata")
		return
	var category_value: String = "misc"
	if _category_option != null and _category_option.item_count > 0:
		category_value = String(_category_option.get_item_metadata(_category_option.selected))
	am.call("set_playlist_metadata", category_value, _tags_edit.text, _folder_edit.text, _description_edit.text)
	am.call("set_crossfade_seconds", _crossfade_slider.value)
	am.call("save_playlist", playlist)
	_append_sync_message("[UI] Metadata updated")

func _on_import_track_pressed() -> void:
	if _import_dialog != null:
		_import_dialog.popup_centered_ratio(0.75)

func _on_track_file_selected(path: String) -> void:
	var am: Node = _am()
	if am == null:
		return
	var current_playlist: Resource = am.get("current_playlist") as Resource
	if current_playlist == null:
		_append_sync_message("[UI] Create or load a playlist first")
		return
	var track: Resource = am.call("import_audio_file", path)
	if track == null:
		_append_sync_message("[UI] Import failed: %s" % path)
		return
	am.call("add_track_to_playlist", current_playlist, track)
	am.call("save_playlist", current_playlist)
	_populate_track_list(current_playlist)
	_append_sync_message("[UI] Imported: %s" % String(track.get("track_name")))

func _on_track_selected(index: int) -> void:
	var am: Node = _am()
	if am == null:
		return
	var current_playlist: Resource = am.get("current_playlist") as Resource
	if current_playlist == null:
		return
	am.call("set_current_playlist", current_playlist, index)
	am.call("play")

func _on_seek_drag_ended(value_changed: bool) -> void:
	if not value_changed:
		return
	var am: Node = _am()
	if am == null:
		return
	_is_updating_seek = true
	am.call("seek", _seek_slider.value)
	_is_updating_seek = false

func _on_track_changed(track: Resource, index: int) -> void:
	if track == null:
		_set_now_playing_text("Now Playing: -")
	else:
		var artist: String = String(track.get("artist"))
		var name_text: String = String(track.get("track_name"))
		var display_name: String = name_text if artist.strip_edges() == "" else "%s - %s" % [artist, name_text]
		_set_now_playing_text("Now Playing: %s" % display_name)
	if _track_list != null and index >= 0 and index < _track_list.item_count:
		_track_list.select(index)
	_update_ui_from_manager()

func _on_playback_state_changed(playing: bool) -> void:
	_play_pause_button.text = "Pause" if playing else "Play"

func _on_playlist_changed(playlist: Resource) -> void:
	_populate_track_list(playlist)
	_update_ui_from_manager()

func _on_volume_changed(master_db: float, playlist_db: float) -> void:
	_master_volume_slider.value = master_db
	_playlist_volume_slider.value = playlist_db

func _populate_track_list(playlist: Resource) -> void:
	_track_list.clear()
	if playlist == null:
		return
	var tracks: Array = playlist.get("tracks") as Array
	for track_variant in tracks:
		if track_variant is Resource:
			var track_res: Resource = track_variant as Resource
			var artist: String = String(track_res.get("artist"))
			var name_text: String = String(track_res.get("track_name"))
			var display_name: String = name_text if artist.strip_edges() == "" else "%s - %s" % [artist, name_text]
			_track_list.add_item(display_name)

func _update_ui_from_manager() -> void:
	var am: Node = _am()
	if am == null:
		return
	var can_control: bool = bool(am.call("can_local_control"))
	if _authority_label != null:
		var role_text: String = String(am.get("local_role"))
		_authority_label.text = "Role: %s | Control: %s" % [role_text.capitalize(), "GM" if can_control else "Read-only"]
	_master_volume_slider.value = float(am.get("master_volume_db"))
	var playlist: Resource = am.get("current_playlist") as Resource
	_playlist_volume_slider.editable = playlist != null
	_loop_check.disabled = playlist == null
	_shuffle_check.disabled = playlist == null
	if playlist != null:
		_playlist_volume_slider.value = float(playlist.get("volume_db"))
		_loop_check.button_pressed = bool(playlist.get("repeat"))
		_shuffle_check.button_pressed = bool(playlist.get("shuffle"))
		if _category_option != null:
			var category_value: String = String(playlist.get("category"))
			for idx in range(_category_option.item_count):
				if String(_category_option.get_item_metadata(idx)) == category_value:
					_category_option.select(idx)
					break
		if _tags_edit != null:
			var tags_array: Array = playlist.get("tags") as Array
			var tags_list: Array[String] = []
			for tag in tags_array:
				tags_list.append(String(tag))
			_tags_edit.text = ", ".join(tags_list)
		if _folder_edit != null:
			_folder_edit.text = String(playlist.get("folder_path"))
		if _description_edit != null:
			_description_edit.text = String(playlist.get("description"))
		if _crossfade_slider != null:
			_crossfade_slider.value = float(playlist.get("crossfade_seconds"))
		if _crossfade_label != null:
			_crossfade_label.text = "%.1fs" % _crossfade_slider.value
		_populate_track_list(playlist)
		var current_track_index: int = int(am.get("current_track_index"))
		if current_track_index >= 0 and current_track_index < _track_list.item_count:
			_track_list.select(current_track_index)
	else:
		_track_list.clear()
	_refresh_control_lock(can_control)
	_on_playback_state_changed(bool(am.get("is_playing")))

func _refresh_control_lock(can_control: bool) -> void:
	var has_playlist: bool = false
	var am: Node = _am()
	if am != null:
		has_playlist = (am.get("current_playlist") != null)
	if _playlist_name_edit != null:
		_playlist_name_edit.editable = can_control
	if _playlist_volume_slider != null:
		_playlist_volume_slider.editable = can_control and has_playlist
	if _loop_check != null:
		_loop_check.disabled = not can_control or not has_playlist
	if _shuffle_check != null:
		_shuffle_check.disabled = not can_control or not has_playlist
	if _master_volume_slider != null:
		_master_volume_slider.editable = can_control
	if _tags_edit != null:
		_tags_edit.editable = can_control
	if _folder_edit != null:
		_folder_edit.editable = can_control
	if _description_edit != null:
		_description_edit.editable = can_control
	if _crossfade_slider != null:
		_crossfade_slider.editable = can_control
	if _category_option != null:
		_category_option.disabled = not can_control

func _append_sync_message(message: String) -> void:
	if _sync_log == null:
		return
	_sync_log.append_text(message + "\n")

func _set_now_playing_text(text_value: String) -> void:
	_now_playing_full_text = text_value
	_now_playing_scroll_offset = 0
	_now_playing_scroll_accum = 0.0
	if _now_playing_label != null:
		_now_playing_label.text = text_value

func _update_now_playing_marquee(delta: float) -> void:
	if _now_playing_label == null:
		return
	if _now_playing_full_text.length() <= NOW_PLAYING_WINDOW_CHARS:
		if _now_playing_label.text != _now_playing_full_text:
			_now_playing_label.text = _now_playing_full_text
		_now_playing_scroll_offset = 0
		_now_playing_scroll_accum = 0.0
		return
	_now_playing_scroll_accum += delta
	if _now_playing_scroll_accum < NOW_PLAYING_SCROLL_STEP_SECONDS:
		return
	_now_playing_scroll_accum = 0.0
	var base_text: String = _now_playing_full_text + NOW_PLAYING_SCROLL_GAP
	var doubled_text: String = base_text + base_text
	_now_playing_label.text = doubled_text.substr(_now_playing_scroll_offset, NOW_PLAYING_WINDOW_CHARS)
	_now_playing_scroll_offset = (_now_playing_scroll_offset + 1) % base_text.length()

func _select_playlist_by_path(path: String) -> void:
	var idx: int = _playlist_paths.find(path)
	if idx >= 0:
		_playlist_option.select(idx)

func _format_time(seconds: float) -> String:
	var total: int = maxi(int(round(seconds)), 0)
	var mins: int = total / 60
	var secs: int = total % 60
	return "%02d:%02d" % [mins, secs]

func _am() -> Node:
	return get_node_or_null("/root/AudioManager")
