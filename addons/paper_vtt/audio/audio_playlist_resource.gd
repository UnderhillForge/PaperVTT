extends Resource
class_name AudioPlaylist

const CATEGORY_AMBIENCE: String = "ambience"
const CATEGORY_COMBAT: String = "combat"
const CATEGORY_EXPLORATION: String = "exploration"
const CATEGORY_SOCIAL: String = "social"
const CATEGORY_MISC: String = "misc"

@export var playlist_name: String = "New Playlist"
@export var tracks: Array[AudioTrack] = []
@export var shuffle: bool = false
@export var repeat: bool = true
@export var volume_db: float = 0.0
@export var category: String = CATEGORY_MISC
@export var tags: PackedStringArray = PackedStringArray()
@export var folder_path: String = "Default"
@export var description: String = ""
@export_range(0.0, 12.0, 0.1) var crossfade_seconds: float = 0.0

func is_valid_index(index: int) -> bool:
	return index >= 0 and index < tracks.size()

func set_tags_from_csv(csv: String) -> void:
	tags.clear()
	for token in csv.split(",", false):
		var cleaned: String = token.strip_edges().to_lower()
		if cleaned == "":
			continue
		if tags.has(cleaned):
			continue
		tags.append(cleaned)

func tags_as_csv() -> String:
	return ", ".join(tags)
