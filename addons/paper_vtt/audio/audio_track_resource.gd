extends Resource
class_name AudioTrack

@export var track_name: String = "New Track"
@export var artist: String = ""
@export_file("*.ogg", "*.mp3", "*.wav") var file_path: String = ""
@export var duration: float = 0.0
@export var loop: bool = false

func get_display_name() -> String:
	if artist.strip_edges() == "":
		return track_name
	return "%s - %s" % [artist, track_name]
