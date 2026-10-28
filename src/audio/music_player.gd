extends Node
## One continuous playlist shared by menus, matches and the paused game.
signal changed
const TRACKS := [
	"res://assets/music/1. New frontiers.ogg",
	"res://assets/music/2. Crossing bridges.ogg",
	"res://assets/music/3. Southern front.ogg",
	"res://assets/music/4. Laidback.ogg",
	"res://assets/music/5. Town square.ogg",
	"res://assets/music/6. Prancing.ogg",
	"res://assets/music/7. Enroute.ogg",
	"res://assets/music/8. Hall of the hexian king.ogg",
]
var player: AudioStreamPlayer
var track_index := 0
var paused := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = AudioStreamPlayer.new()
	player.bus = &"Music"
	player.volume_db = -12.0
	add_child(player)
	player.finished.connect(next_track)
	play_track()

func track_title() -> String:
	return TRACKS[track_index].get_file().get_basename().split(". ", true, 1)[1]

func play_track() -> void:
	player.stream = load(TRACKS[track_index])
	player.play()
	player.stream_paused = paused
	changed.emit()

func toggle_pause() -> void:
	paused = not paused
	player.stream_paused = paused
	changed.emit()

func next_track() -> void:
	track_index = (track_index + 1) % TRACKS.size()
	play_track()

func _exit_tree() -> void:
	player.stop()
	player.stream = null
