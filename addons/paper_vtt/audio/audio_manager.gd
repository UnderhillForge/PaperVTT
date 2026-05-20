extends Node

signal playlist_changed(playlist: AudioPlaylist)
signal track_changed(track: AudioTrack, index: int)
signal playback_state_changed(is_playing: bool)
signal volume_changed(master_volume_db: float, playlist_volume_db: float)
signal sync_message_logged(message: String)
signal authority_changed(local_role: String, gm_peer_id: int)
signal control_denied(action: String, reason: String)

const CACHE_DIR: String = "user://audio/cache"
const PLAYLIST_DIR: String = "user://audio/playlists"
const SUPPORTED_EXTENSIONS: Array[String] = ["ogg", "mp3", "wav"]
const SYNC_INTERVAL_SEC: float = 1.0
const ROLE_AUTO: String = "auto"
const ROLE_GM: String = "gm"
const ROLE_PLAYER: String = "player"

var current_playlist: AudioPlaylist = null
var current_track_index: int = -1
var is_playing: bool = false
var master_volume_db: float = 0.0
var local_role: String = ROLE_AUTO
var gm_peer_id: int = 1
var enforce_server_authority: bool = true

var _player: AudioStreamPlayer = null
var _crossfade_player: AudioStreamPlayer = null
var _sync_accum: float = 0.0
var _paused_position: float = 0.0
var _crossfade_tween: Tween = null
var _target_player_volume_db: float = 0.0

func _ready() -> void:
	_ensure_storage_dirs()
	_player = AudioStreamPlayer.new()
	_player.name = "GMBackgroundAudio"
	add_child(_player)
	_crossfade_player = AudioStreamPlayer.new()
	_crossfade_player.name = "GMBackgroundAudioCrossfade"
	add_child(_crossfade_player)
	_player.finished.connect(_on_track_finished)
	if multiplayer != null:
		if not multiplayer.peer_connected.is_connected(_on_peer_connected):
			multiplayer.peer_connected.connect(_on_peer_connected)
	_apply_volume()

func _process(delta: float) -> void:
	if not is_playing:
		return
	if not _is_server_authority():
		return
	_sync_accum += delta
	if _sync_accum >= SYNC_INTERVAL_SEC:
		_sync_accum = 0.0
		_broadcast_sync("tick")

func configure_authority_hooks(role: String = ROLE_AUTO, gm_id: int = 1, require_server_control: bool = true) -> void:
	if role in [ROLE_AUTO, ROLE_GM, ROLE_PLAYER]:
		local_role = role
	gm_peer_id = max(1, gm_id)
	enforce_server_authority = require_server_control
	authority_changed.emit(local_role, gm_peer_id)

func set_local_role(role: String) -> void:
	configure_authority_hooks(role, gm_peer_id, enforce_server_authority)

func set_gm_peer_id(peer_id: int) -> void:
	configure_authority_hooks(local_role, peer_id, enforce_server_authority)

func can_local_control() -> bool:
	return _can_control_playback(false)

func request_sync_from_server() -> void:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	if _is_server_authority():
		return
	rpc_id(1, "server_request_full_sync")

@rpc("any_peer", "call_local", "reliable")
func server_request_full_sync() -> void:
	if not _is_server_authority():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	rpc_id(sender_id, "client_apply_sync", get_sync_snapshot())

func create_playlist(playlist_name: String) -> AudioPlaylist:
	if not _guard_control("create_playlist"):
		return null
	var playlist := AudioPlaylist.new()
	playlist.playlist_name = playlist_name.strip_edges() if playlist_name.strip_edges() != "" else "New Playlist"
	playlist.repeat = true
	playlist.shuffle = false
	playlist.volume_db = 0.0
	playlist.category = AudioPlaylist.CATEGORY_MISC
	playlist.folder_path = "Default"
	playlist.crossfade_seconds = 0.0
	return playlist

func save_playlist(playlist: AudioPlaylist) -> String:
	if not _guard_control("save_playlist"):
		return ""
	if playlist == null:
		return ""
	var safe_name: String = _sanitize_name(playlist.playlist_name)
	var path: String = "%s/%s.tres" % [PLAYLIST_DIR, safe_name]
	var err: int = ResourceSaver.save(playlist, path)
	if err != OK:
		_log_sync("[AudioManager] Failed to save playlist '%s' (error %d)" % [playlist.playlist_name, err])
		return ""
	return path

func list_playlists() -> Array[String]:
	var results: Array[String] = []
	var abs_dir: String = ProjectSettings.globalize_path(PLAYLIST_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return results
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir():
			continue
		if file_name.get_extension().to_lower() != "tres":
			continue
		results.append("%s/%s" % [PLAYLIST_DIR, file_name])
	dir.list_dir_end()
	results.sort()
	return results

func load_playlist(path: String) -> AudioPlaylist:
	var playlist: AudioPlaylist = load(path) as AudioPlaylist
	if playlist == null:
		return null
	return playlist

func import_audio_file(source_path: String) -> AudioTrack:
	if not _guard_control("import_audio_file"):
		return null
	if source_path.strip_edges() == "":
		return null
	var ext: String = source_path.get_extension().to_lower()
	if not SUPPORTED_EXTENSIONS.has(ext):
		_log_sync("[AudioManager] Unsupported import format: %s" % source_path)
		return null
	var source_abs: String = source_path
	if source_path.begins_with("res://") or source_path.begins_with("user://"):
		source_abs = ProjectSettings.globalize_path(source_path)
	if not FileAccess.file_exists(source_abs):
		_log_sync("[AudioManager] Import source does not exist: %s" % source_abs)
		return null
	var file_name: String = source_abs.get_file().get_basename().to_snake_case()
	var stamp: String = str(Time.get_unix_time_from_system())
	var dest_path: String = "%s/%s_%s.%s" % [CACHE_DIR, file_name, stamp, ext]
	if not _copy_file(source_abs, ProjectSettings.globalize_path(dest_path)):
		_log_sync("[AudioManager] Failed to copy imported audio: %s" % source_abs)
		return null

	var track := AudioTrack.new()
	track.track_name = source_abs.get_file().get_basename().capitalize()
	track.file_path = dest_path
	track.duration = _estimate_duration(dest_path)
	track.artist = ""
	track.loop = false
	return track

func add_track_to_playlist(playlist: AudioPlaylist, track: AudioTrack) -> bool:
	if not _guard_control("add_track_to_playlist"):
		return false
	if playlist == null or track == null:
		return false
	playlist.tracks.append(track)
	return true

func set_current_playlist(playlist: AudioPlaylist, start_index: int = 0) -> void:
	if not _guard_control("set_current_playlist"):
		return
	current_playlist = playlist
	if current_playlist == null or current_playlist.tracks.is_empty():
		current_track_index = -1
		stop()
		playlist_changed.emit(current_playlist)
		_broadcast_sync("set_playlist_empty")
		return
	current_track_index = clampi(start_index, 0, current_playlist.tracks.size() - 1)
	_paused_position = 0.0
	_load_current_track_stream(0.0, is_playing)
	playlist_changed.emit(current_playlist)
	track_changed.emit(get_current_track(), current_track_index)
	_broadcast_sync("set_playlist")

func play() -> void:
	if not _guard_control("play"):
		return
	if current_playlist == null or current_playlist.tracks.is_empty():
		return
	if _player.stream == null:
		_load_current_track_stream()
	if _player.stream == null:
		return
	if is_playing:
		return
	var start_pos: float = _paused_position
	if _player.get_playback_position() > 0.0:
		start_pos = _player.get_playback_position()
	_player.play(start_pos)
	is_playing = true
	playback_state_changed.emit(true)
	_broadcast_sync("play")

func pause() -> void:
	if not _guard_control("pause"):
		return
	if not is_playing:
		return
	_paused_position = _player.get_playback_position()
	_player.stop()
	is_playing = false
	playback_state_changed.emit(false)
	_broadcast_sync("pause")

func stop() -> void:
	if not _guard_control("stop"):
		return
	_player.stop()
	if _crossfade_player != null:
		_crossfade_player.stop()
	_paused_position = 0.0
	is_playing = false
	playback_state_changed.emit(false)
	_broadcast_sync("stop")

func play_pause() -> void:
	if is_playing:
		pause()
	else:
		play()

func next_track() -> void:
	if not _guard_control("next_track"):
		return
	if current_playlist == null or current_playlist.tracks.is_empty():
		return
	var next_index: int = _compute_next_track_index()
	if next_index < 0:
		stop()
		return
	current_track_index = next_index
	_load_current_track_stream(0.0, is_playing)
	track_changed.emit(get_current_track(), current_track_index)
	_broadcast_sync("next")

func previous_track() -> void:
	if not _guard_control("previous_track"):
		return
	if current_playlist == null or current_playlist.tracks.is_empty():
		return
	if _player.get_playback_position() > 2.0:
		seek(0.0)
		return
	current_track_index -= 1
	if current_track_index < 0:
		if current_playlist.repeat:
			current_track_index = current_playlist.tracks.size() - 1
		else:
			current_track_index = 0
	_load_current_track_stream(0.0, is_playing)
	track_changed.emit(get_current_track(), current_track_index)
	_broadcast_sync("previous")

func seek(seconds: float) -> void:
	if not _guard_control("seek"):
		return
	if _player.stream == null:
		return
	var clamped: float = maxf(seconds, 0.0)
	var was_playing: bool = is_playing
	_player.stop()
	_player.play(clamped)
	_paused_position = clamped
	if not was_playing:
		_player.stop()
	_broadcast_sync("seek")

func set_master_volume_db(value: float) -> void:
	if not _guard_control("set_master_volume_db"):
		return
	master_volume_db = clampf(value, -48.0, 6.0)
	_apply_volume()
	_broadcast_sync("master_volume")

func set_playlist_volume_db(value: float) -> void:
	if not _guard_control("set_playlist_volume_db"):
		return
	if current_playlist == null:
		return
	current_playlist.volume_db = clampf(value, -48.0, 6.0)
	_apply_volume()
	_broadcast_sync("playlist_volume")

func set_loop_enabled(enabled: bool) -> void:
	if not _guard_control("set_loop_enabled"):
		return
	if current_playlist == null:
		return
	current_playlist.repeat = enabled
	_broadcast_sync("loop")

func set_shuffle_enabled(enabled: bool) -> void:
	if not _guard_control("set_shuffle_enabled"):
		return
	if current_playlist == null:
		return
	current_playlist.shuffle = enabled
	_broadcast_sync("shuffle")

func set_crossfade_seconds(value: float) -> void:
	if not _guard_control("set_crossfade_seconds"):
		return
	if current_playlist == null:
		return
	current_playlist.crossfade_seconds = clampf(value, 0.0, 12.0)
	_broadcast_sync("crossfade_seconds")

func set_playlist_metadata(category: String, tags_csv: String, folder_path: String, description: String) -> void:
	if not _guard_control("set_playlist_metadata"):
		return
	if current_playlist == null:
		return
	current_playlist.category = category.to_lower().strip_edges()
	current_playlist.folder_path = folder_path.strip_edges()
	current_playlist.description = description.strip_edges()
	current_playlist.set_tags_from_csv(tags_csv)
	_broadcast_sync("playlist_metadata")

func get_current_track() -> AudioTrack:
	if current_playlist == null:
		return null
	if not current_playlist.is_valid_index(current_track_index):
		return null
	return current_playlist.tracks[current_track_index]

func get_track_position() -> float:
	if _player == null:
		return 0.0
	if is_playing:
		return _player.get_playback_position()
	return _paused_position

func get_track_duration() -> float:
	var track: AudioTrack = get_current_track()
	if track == null:
		return 0.0
	if track.duration > 0.0:
		return track.duration
	if _player != null and _player.stream != null:
		return _player.stream.get_length()
	return 0.0

func get_sync_snapshot() -> Dictionary:
	var playlist_path: String = ""
	if current_playlist != null and current_playlist.resource_path != "":
		playlist_path = current_playlist.resource_path
	var tags_payload: Array[String] = []
	if current_playlist != null:
		for tag in current_playlist.tags:
			tags_payload.append(String(tag))
	return {
		"playlist_path": playlist_path,
		"playlist_name": current_playlist.playlist_name if current_playlist != null else "",
		"track_index": current_track_index,
		"position": get_track_position(),
		"is_playing": is_playing,
		"master_volume_db": master_volume_db,
		"playlist_volume_db": current_playlist.volume_db if current_playlist != null else 0.0,
		"shuffle": current_playlist.shuffle if current_playlist != null else false,
		"repeat": current_playlist.repeat if current_playlist != null else true,
		"crossfade_seconds": current_playlist.crossfade_seconds if current_playlist != null else 0.0,
		"category": current_playlist.category if current_playlist != null else AudioPlaylist.CATEGORY_MISC,
		"folder_path": current_playlist.folder_path if current_playlist != null else "Default",
		"description": current_playlist.description if current_playlist != null else "",
		"tags": tags_payload,
		"gm_peer_id": gm_peer_id,
		"local_role": local_role,
	}

@rpc("authority", "call_remote", "reliable")
func client_apply_sync(state: Dictionary) -> void:
	if _is_server_authority():
		return
	_apply_sync_state(state)
	_log_sync("[AudioManager][SYNC][CLIENT] Applied state track=%d pos=%.2f playing=%s" % [
		int(state.get("track_index", -1)),
		float(state.get("position", 0.0)),
		str(bool(state.get("is_playing", false)))
	])

func _on_track_finished() -> void:
	if current_playlist == null:
		return
	var current_track: AudioTrack = get_current_track()
	if current_track != null and current_track.loop:
		seek(0.0)
		if is_playing:
			play()
		return
	_paused_position = 0.0
	next_track()

func _load_current_track_stream(start_position: float = 0.0, autoplay: bool = false) -> void:
	var track: AudioTrack = get_current_track()
	if track == null:
		_player.stream = null
		return
	var stream: AudioStream = _resolve_stream_for_track(track.file_path)
	if stream == null:
		_log_sync("[AudioManager] Could not load stream: %s" % track.file_path)
		_player.stream = null
		return
	var crossfade_seconds: float = _get_current_crossfade_seconds()
	if autoplay and _player.stream != null and _player.playing and crossfade_seconds > 0.0:
		if _crossfade_player != null:
			_crossfade_player.stop()
			_crossfade_player.stream = _player.stream
			_crossfade_player.volume_db = _player.volume_db
			_crossfade_player.play(_player.get_playback_position())
		_player.stop()
		_player.stream = stream
		_player.volume_db = -60.0
		_player.play(start_position)
		if _crossfade_tween != null:
			_crossfade_tween.kill()
		_crossfade_tween = create_tween()
		_crossfade_tween.tween_property(_crossfade_player, "volume_db", -60.0, crossfade_seconds)
		_crossfade_tween.parallel().tween_property(_player, "volume_db", _target_player_volume_db, crossfade_seconds)
		_crossfade_tween.finished.connect(func() -> void:
			if _crossfade_player != null:
				_crossfade_player.stop()
			_player.volume_db = _target_player_volume_db
		)
	else:
		_player.stream = stream
		if autoplay:
			_player.play(start_position)
		else:
			_player.stop()
			_paused_position = start_position
	track.duration = stream.get_length()
	_apply_volume()

func _resolve_stream_for_track(path: String) -> AudioStream:
	if path.strip_edges() == "":
		return null

	# Try ResourceLoader first for imported res:// resources.
	var stream: AudioStream = load(path) as AudioStream
	if stream != null:
		return stream

	var absolute_path: String = path
	if path.begins_with("res://") or path.begins_with("user://"):
		absolute_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return null

	var ext: String = absolute_path.get_extension().to_lower()
	match ext:
		"ogg":
			return AudioStreamOggVorbis.load_from_file(absolute_path)
		"mp3":
			return AudioStreamMP3.load_from_file(absolute_path)
		"wav":
			return AudioStreamWAV.load_from_file(absolute_path)
		_:
			return null

func _apply_volume() -> void:
	var playlist_volume: float = current_playlist.volume_db if current_playlist != null else 0.0
	_target_player_volume_db = master_volume_db + playlist_volume
	if _player != null:
		_player.volume_db = _target_player_volume_db
	volume_changed.emit(master_volume_db, playlist_volume)

func _compute_next_track_index() -> int:
	if current_playlist == null or current_playlist.tracks.is_empty():
		return -1
	if current_playlist.shuffle and current_playlist.tracks.size() > 1:
		var next_index: int = randi_range(0, current_playlist.tracks.size() - 1)
		if next_index == current_track_index:
			next_index = (next_index + 1) % current_playlist.tracks.size()
		return next_index
	var next_linear: int = current_track_index + 1
	if next_linear >= current_playlist.tracks.size():
		return 0 if current_playlist.repeat else -1
	return next_linear

func _can_control_playback(emit_denial: bool = true) -> bool:
	if local_role == ROLE_PLAYER:
		if emit_denial:
			_control_denied("role_forced_player")
		return false
	if enforce_server_authority and multiplayer != null and multiplayer.has_multiplayer_peer() and not _is_server_authority():
		if emit_denial:
			_control_denied("server_authority_required")
		return false
	if local_role == ROLE_GM:
		return true
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return true
	if _is_server_authority():
		return true
	return multiplayer.get_unique_id() == gm_peer_id

func _is_server_authority() -> bool:
	if multiplayer == null or not multiplayer.has_multiplayer_peer():
		return true
	return multiplayer.is_server()

func _guard_control(action: String) -> bool:
	if _can_control_playback(true):
		return true
	_log_sync("[AudioManager][CONTROL DENIED] %s" % action)
	return false

func _control_denied(reason: String) -> void:
	control_denied.emit("playback_control", reason)

func _get_current_crossfade_seconds() -> float:
	if current_playlist == null:
		return 0.0
	return clampf(current_playlist.crossfade_seconds, 0.0, 12.0)

func _on_peer_connected(peer_id: int) -> void:
	if not _is_server_authority():
		return
	rpc_id(peer_id, "client_apply_sync", get_sync_snapshot())

func _broadcast_sync(reason: String) -> void:
	if not _is_server_authority():
		return
	var state: Dictionary = get_sync_snapshot()
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		rpc("client_apply_sync", state)
	_log_sync("[AudioManager][SYNC][SERVER] %s -> track=%d pos=%.2f playing=%s master=%.1f" % [
		reason,
		current_track_index,
		float(state.get("position", 0.0)),
		str(bool(state.get("is_playing", false))),
		master_volume_db
	])

func _apply_sync_state(state: Dictionary) -> void:
	master_volume_db = clampf(float(state.get("master_volume_db", master_volume_db)), -48.0, 6.0)
	var incoming_playlist_path: String = String(state.get("playlist_path", ""))
	if incoming_playlist_path != "" and ResourceLoader.exists(incoming_playlist_path):
		var loaded_playlist: AudioPlaylist = load(incoming_playlist_path) as AudioPlaylist
		if loaded_playlist != null:
			current_playlist = loaded_playlist
	if current_playlist == null:
		return
	current_playlist.shuffle = bool(state.get("shuffle", current_playlist.shuffle))
	current_playlist.repeat = bool(state.get("repeat", current_playlist.repeat))
	current_playlist.volume_db = clampf(float(state.get("playlist_volume_db", current_playlist.volume_db)), -48.0, 6.0)
	current_playlist.crossfade_seconds = clampf(float(state.get("crossfade_seconds", current_playlist.crossfade_seconds)), 0.0, 12.0)
	current_playlist.category = String(state.get("category", current_playlist.category))
	current_playlist.folder_path = String(state.get("folder_path", current_playlist.folder_path))
	current_playlist.description = String(state.get("description", current_playlist.description))
	var incoming_tags: Array = state.get("tags", []) as Array
	current_playlist.tags.clear()
	for tag_variant in incoming_tags:
		current_playlist.tags.append(String(tag_variant))
	gm_peer_id = int(state.get("gm_peer_id", gm_peer_id))
	current_track_index = clampi(int(state.get("track_index", current_track_index)), 0, max(current_playlist.tracks.size() - 1, 0))
	_load_current_track_stream()
	_apply_volume()
	var target_pos: float = maxf(float(state.get("position", 0.0)), 0.0)
	var should_play: bool = bool(state.get("is_playing", false))
	if _player.stream != null:
		_player.stop()
		_player.play(target_pos)
		if not should_play:
			_player.stop()
	_paused_position = target_pos
	is_playing = should_play
	track_changed.emit(get_current_track(), current_track_index)
	playback_state_changed.emit(is_playing)

func _estimate_duration(path: String) -> float:
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return 0.0
	return stream.get_length()

func _copy_file(source_abs: String, dest_abs: String) -> bool:
	var src: FileAccess = FileAccess.open(source_abs, FileAccess.READ)
	if src == null:
		return false
	var data: PackedByteArray = src.get_buffer(src.get_length())
	src.close()
	var dest: FileAccess = FileAccess.open(dest_abs, FileAccess.WRITE)
	if dest == null:
		return false
	dest.store_buffer(data)
	dest.close()
	return true

func _ensure_storage_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PLAYLIST_DIR))

func _sanitize_name(value: String) -> String:
	var sanitized: String = value.strip_edges().to_snake_case()
	if sanitized == "":
		sanitized = "playlist"
	return sanitized

func _log_sync(message: String) -> void:
	print(message)
	sync_message_logged.emit(message)
