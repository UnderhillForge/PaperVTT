extends SceneTree

const MAIN_SCENE: PackedScene = preload("res://scenes/main/Main.tscn")

func _initialize() -> void:
	var main_instance: Node = MAIN_SCENE.instantiate()
	root.add_child(main_instance)

	await process_frame
	await process_frame
	await process_frame

	_capture("res://debug_audio_panel_1.png")

	var am: Node = root.get_node_or_null("AudioManager")
	if am != null:
		var demo_playlist: AudioPlaylist = am.call("create_playlist", "Demo GM Playlist")
		var demo_track := AudioTrack.new()
		demo_track.track_name = "Demo Cue"
		demo_track.artist = "PaperVTT"
		demo_track.duration = 95.0
		demo_playlist.tracks.append(demo_track)
		am.call("set_current_playlist", demo_playlist)
		am.call("set_master_volume_db", -6.0)
		am.call("set_playlist_volume_db", -2.0)
		am.call("set_shuffle_enabled", true)
		am.call("set_loop_enabled", true)
		am.call("set_playlist_metadata", "ambience", "forest, rain, calm", "Session 01/Exterior", "Ambient bed for travel scenes")
		am.call("set_crossfade_seconds", 2.5)
		am.call("seek", 24.0)
		am.call("next_track")

	var inspector: Node = main_instance.get_node_or_null("EditorCanvas/RootUI/WorldBrushInspector")
	if inspector != null:
		var panel: Node = inspector.find_child("GMAudioPanel", true, false)
		if panel != null and panel.has_method("_update_ui_from_manager"):
			panel.call("_update_ui_from_manager")

	await process_frame
	await process_frame
	_capture("res://debug_audio_panel_2.png")

	if am != null:
		am.call("set_master_volume_db", -10.0)
		am.call("set_master_volume_db", -4.0)
		am.call("set_shuffle_enabled", false)
	await process_frame
	await process_frame
	_capture("res://debug_audio_sync_3.png")

	quit(0)

func _capture(path: String) -> void:
	var image: Image = root.get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)
		print("[AudioCapture] Saved screenshot: %s" % path)
