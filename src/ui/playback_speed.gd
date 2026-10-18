extends Node
## Hold controls affect presentation tweens, never the simulation clock.
const FAST_SCALE := 6.0
var game
var speed_held := false
var turn_held := false
var turn_press_consumed := false

func _init(controller) -> void:
	game = controller
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	Keys.changed.connect(reset)
	game.hud.end_button.button_down.connect(begin_turn_press)
	game.hud.end_button.button_up.connect(end_turn_press)
	game.hud.end_button.mouse_exited.connect(end_turn_press)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and Keys.matches(event, "speed"):
		if not event.pressed or not game.get_tree().paused:
			speed_held = event.pressed
		update()
	# Receive releases over other controls and during pause too.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		end_turn_press()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		reset()

func _process(_delta: float) -> void:
	if game.get_tree().paused or game.closing:
		reset()
	else:
		update()

func begin_turn_press() -> void:
	turn_press_consumed = game.busy
	turn_held = game.busy and game.active_faction != game.player_faction
	update()

func end_turn_press() -> void:
	turn_held = false
	update()

func reset() -> void:
	speed_held = false
	turn_held = false
	# Retain consumed until the next press: a release after pause/completion
	# must not accidentally start a second round.
	update()

func update() -> void:
	if not game.busy:
		turn_held = false
	var allowed: bool = not game.closing and not game.get_tree().paused and not game.view.level_transitioning and not game.event_shade.visible and not game.completion_started
	var fast: bool = allowed and (game.busy or game.view.is_animating) and (speed_held or (turn_held and game.busy and game.active_faction != game.player_faction))
	game.view.playback.set_speed_scale(FAST_SCALE if fast else 1.0)
	if game.busy and game.active_faction != game.player_faction:
		var text_value: String = game.NAMES[game.active_faction] + ("  »" if fast else "…")
		if game.hud.end_button.text != text_value:
			game.hud.end_button.text = text_value
