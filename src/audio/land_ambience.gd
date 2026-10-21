extends Node
## A board-owned loop, mixed independently of the bounded one-shot voices.
const Grid = preload("res://src/game/hex_grid.gd")
const RECORDING = preload("res://assets/sfx/ambient/nature_closeup_ambience.ogg")
const OVERVIEW_RECORDING = preload("res://assets/sfx/ambient/nature_zoomedout_ambience.ogg")
const SILENT_ZOOM := 14.0
const FULL_ZOOM := 8.0
const OVERVIEW_START_ZOOM := 14.0
const VOLUME_DB := -26.0
const OVERVIEW_VOLUME_DB := -34.0
const FADE_SECONDS := 1.5

var board
var player: AudioStreamPlayer
var gain := 0.0
var overview_player: AudioStreamPlayer
var overview_gain := 0.0

func _init(view) -> void:
	board = view
	name = "LandAmbience"
	# Keep the soundscape and its fades running while the pause menu is open.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	player = create_loop(RECORDING, "NatureLoop")
	overview_player = create_loop(OVERVIEW_RECORDING, "OverviewLoop")

func create_loop(source: AudioStreamOggVorbis, loop_name: String) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.name = loop_name
	var recording := source.duplicate() as AudioStreamOggVorbis
	recording.loop = true
	voice.stream = recording
	voice.bus = &"Ambience"
	voice.volume_db = -80.0
	add_child(voice)
	return voice

func board_audible() -> bool:
	return board.active and board.is_visible_in_tree() and board.camera.is_current() and not board.level_transitioning

func close_mix() -> float:
	return smoothstep(SILENT_ZOOM, FULL_ZOOM, board.zoom)

func overview_target_gain() -> float:
	# High-altitude ambience follows zoom, including over the ocean.
	var start := maxf(OVERVIEW_START_ZOOM, board.max_zoom * 0.35)
	return smoothstep(start, board.max_zoom, board.zoom) if board_audible() else 0.0

func target_gain() -> float:
	if not board_audible():
		return 0.0
	var zoom_gain := close_mix()
	if zoom_gain <= 0.0:
		return 0.0
	# Sample the central view on the terrain plane. Axial rounding deliberately
	# ignores narrow cosmetic tile gaps; bridges do not count as nature.
	var rect: Rect2 = board.get_viewport().get_visible_rect()
	var land := 0.0
	for y in [-0.2, 0.0, 0.2]:
		for x in [-0.2, 0.0, 0.2]:
			var screen := rect.get_center() + rect.size * Vector2(x, y)
			var origin: Vector3 = board.camera.project_ray_origin(screen)
			var direction: Vector3 = board.camera.project_ray_normal(screen)
			if direction.y >= -0.001:
				continue
			var coord := Grid.from_world(origin - direction * origin.y / direction.y)
			if board.cells.has(coord) and board.cells[coord].get("building", "") != "bridge":
				land += 1.0
	return zoom_gain * land / 9.0

func _process(delta: float) -> void:
	var sound = get_node("/root/Sound")
	var audible: bool = not sound.is_muted() and sound.get_volume(&"Master") > 0.0001 and sound.get_volume(&"Ambience") > 0.0001
	audible = audible and not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Ambience"))
	if not audible:
		gain = 0.0
		overview_gain = 0.0
		player.stop()
		overview_player.stop()
		return
	gain = move_toward(gain, target_gain(), delta / FADE_SECONDS)
	overview_gain = move_toward(overview_gain, overview_target_gain(), delta / FADE_SECONDS)
	update_loop(player, gain, VOLUME_DB)
	update_loop(overview_player, overview_gain, OVERVIEW_VOLUME_DB)

func update_loop(voice: AudioStreamPlayer, level: float, volume_db: float) -> void:
	voice.volume_db = volume_db + linear_to_db(level) if level > 0.0001 else -80.0
	if level > 0.0001:
		if not voice.playing:
			voice.play()
	else:
		voice.stop()

func _exit_tree() -> void:
	for voice in [player, overview_player]:
		if is_instance_valid(voice):
			voice.stop()
			voice.stream = null
