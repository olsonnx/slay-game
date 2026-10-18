extends Node
## Action sprites tick locally. Ready idle poses follow the presentation clock.
const Library = preload("res://src/rendering/unit_sprite_library.gd")
var board
var sprite: Sprite3D
var tier := 1
var faction_id := 0
var animation := "idle"
var frame_index := 0
var elapsed := 0.0
var looping := false
var hold_last := false

func _init(view, image: Sprite3D, rank: int, faction: int) -> void:
	board = view
	sprite = image
	tier = rank
	faction_id = faction
	set_process(false)

func configure(rank: int, faction: int) -> void:
	tier = rank
	faction_id = faction
	play("idle")

func play(name: String, loop := false, hold := false) -> void:
	animation = name
	frame_index = 0
	if name == "idle" and sprite.get_meta("unit_ready", false):
		frame_index = board.unit_presentation.idle_tick % int(Library.clip(tier,"idle")[1])
	elapsed = 0.0
	looping = loop
	hold_last = hold
	get_parent().set_meta("sprite_action_active",name != "idle")
	update_frame()
	set_process(name != "idle")

func show_idle_frame(index: int) -> void:
	if animation != "idle": return
	frame_index = index
	update_frame()

func face(target: Vector3) -> void:
	var side: float = board.camera.global_basis.x.dot(target-get_parent().global_position)
	if absf(side) > 0.01:
		sprite.flip_h = side < 0
		sprite.get_node("HoverOutline").flip_h = sprite.flip_h

func _process(delta: float) -> void:
	advance(delta*board.playback.speed_scale)

func advance(seconds: float) -> void:
	elapsed += seconds
	var sequence := Library.clip(tier,animation)
	var next := floori(elapsed*sequence[2])
	if not looping and next >= sequence[1]:
		if hold_last:
			frame_index = int(sequence[1])-1
			update_frame()
			set_process(false)
		else:
			play("idle")
			board.unit_batches.queue_sync({get_parent().get_meta("hex"):true},false)
		return
	next = posmod(next,int(sequence[1]))
	if next != frame_index:
		frame_index = next
		update_frame()

func update_frame() -> void:
	var frame: Dictionary = board.unit_sprites.frame(tier,board.COLORS[faction_id],animation,frame_index)
	sprite.texture = frame.texture
	sprite.set_meta("image",frame.image)
	sprite.pixel_size = Library.pixel_size(tier)
	sprite.position.y = Library.height(tier)
	sprite.set_meta("animation",animation)
	sprite.set_meta("animation_frame",frame_index)

