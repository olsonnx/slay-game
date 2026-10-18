extends SceneTree
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func ctrl(held: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_CTRL
	event.pressed = held
	game.playback_speed._input(event)

func fixture() -> void:
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for column in range(8):
		game.cells[Vector2i(column, 0)] = game.rules.make_cell(0 if column < 7 else -1)
	for column in [9, 10]:
		game.cells[Vector2i(column, 0)] = game.rules.make_cell(1)
	game.rules.rebuild_kingdoms()
	game.cells[Vector2i.ZERO]["unit"] = 1
	game.active_hex = Vector2i.ZERO
	game.view.render_cells(game.cells)
	game.refresh_ui()

func run() -> void:
	var sound = root.get_node("Sound")
	var muted: bool = sound.is_muted()
	sound.set_muted(true, false)
	game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	fixture()
	await process_frame
	game.click_hex(Vector2i.ZERO)
	game.click_hex(Vector2i(7, 0))
	expect(game.busy and game.view.is_animating, "Long player move starts playback")
	var motion: Dictionary = game.view.active_motions[Vector2i.ZERO]
	var tween: Tween = motion["tween"]
	var actor: Node3D = motion["actor"]
	tween.pause()
	var start: Vector3 = actor.global_position
	tween.custom_step(0.01)
	var normal_distance := start.distance_to(actor.global_position)
	start = actor.global_position
	ctrl(true)
	tween.custom_step(0.01)
	var fast_distance := start.distance_to(actor.global_position)
	expect(is_equal_approx(fast_distance / normal_distance, 6), "Ctrl changes an already moving actor to six times its previous speed")
	start = actor.global_position
	ctrl(false)
	tween.custom_step(0.01)
	expect(is_equal_approx(start.distance_to(actor.global_position), normal_distance), "Ctrl release restores normal speed during the same move")
	ctrl(true)
	tween.play()
	while game.busy:
		await process_frame
	expect(game.cells[Vector2i(7, 0)]["unit"] == 1 and game.view.cells == game.cells, "Fast arrival commits the same final board")
	expect(game.view.playback.speed_scale == 1, "Completion restores normal playback even with Ctrl held")
	ctrl(false)
	fixture()
	var before: Dictionary = game.cells.duplicate(true)
	var rng_before: int = game.rules.rng.state
	ctrl(true)
	game.click_hex(Vector2i.ZERO)
	game.click_hex(Vector2i(7, 0))
	expect(game.view.playback.speed_scale == 6, "Ctrl held before a move accelerates its first tween")
	await create_timer(0.04).timeout
	game.cancel_action()
	await process_frame
	expect(not game.busy and not game.view.is_animating and game.cells == before, "Accelerated player movement can still be cancelled and fully restored")
	expect(game.rules.rng.state == rng_before, "Fast cancellation restores the original random state")
	ctrl(false)

	game.busy = true
	game.active_faction = 1
	game.refresh_ui()
	expect(not game.end_button.disabled and game.turn_spinner.visible, "Loading button accepts a speed hold while commands remain locked")
	expect(game.commands_locked() and game.recruit_button.disabled, "Speed hold does not unlock gameplay commands")
	game.end_button.button_down.emit()
	expect(game.view.playback.speed_scale == 6 and game.end_button.text.ends_with("»"), "Holding loading button accelerates and shows fast feedback")
	var phase_tween: Tween = game.view.playback.scaled_tween(game)
	phase_tween.tween_interval(1)
	phase_tween.pause()
	phase_tween.custom_step(0.02)
	expect(is_equal_approx(phase_tween.get_total_elapsed_time(), 0.12), "New phase tweens inherit speed while the button is held")
	ctrl(true)
	game.end_button.button_up.emit()
	expect(game.view.playback.speed_scale == 6, "Ctrl keeps acceleration after button release")
	ctrl(false)
	expect(game.view.playback.speed_scale == 1, "Releasing both controls restores normal speed")
	phase_tween.kill()
	game.end_button.button_down.emit()
	paused = true
	game.playback_speed._process(0)
	expect(game.view.playback.speed_scale == 1 and not game.playback_speed.turn_held and not game.playback_speed.speed_held, "Pause clears speed holds")
	paused = false
	game.end_button.button_up.emit()
	ctrl(true)
	game.playback_speed._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect(game.view.playback.speed_scale == 1 and not game.playback_speed.speed_held, "Focus loss clears Ctrl and restores playback speed")
	game.end_button.button_down.emit()
	game.end_button.mouse_exited.emit()
	expect(game.view.playback.speed_scale == 1, "Dragging away from the loading button ends acceleration")
	game.end_button.button_down.emit()
	game.busy = false
	game.active_faction = 0
	game.refresh_ui()
	var round_before: int = game.round_number
	game.end_button.button_up.emit()
	game.end_button.pressed.emit()
	expect(not game.busy and game.round_number == round_before, "Release after turn completion cannot start an extra round")
	expect(game.view.playback.speed_scale == 1 and not game.playback_speed.turn_held, "Turn completion clears the held loading state")
	game.end_button.button_down.emit()
	expect(not game.playback_speed.turn_press_consumed, "A fresh player-turn click clears the consumed hold")
	game.end_button.button_up.emit()

	fixture()
	game.cells[Vector2i.ZERO]["unit"] = 3
	game.cells[Vector2i(7, 0)]["owner"] = 1
	game.cells[Vector2i(7, 0)]["capital"] = 1
	game.cells[Vector2i(7, 0)]["unit"] = 1
	game.cells[Vector2i(8, 0)] = game.rules.make_cell(1)
	game.cells[Vector2i(9, 0)]["capital"] = -1
	game.rules.rebuild_kingdoms()
	game.view.render_cells(game.cells)
	game.busy = true
	game.active_faction = 0
	ctrl(true)
	var stages: Array[String] = []
	var observe := func(_action: Dictionary, stage: String): stages.append(stage)
	game.view.motion_stage.connect(observe)
	var attack: Dictionary = game.rules.perform_move(Vector2i.ZERO, Vector2i(7, 0))
	expect(not attack.get("annexed", {}).is_empty(), "Castle fixture includes adjacent surrendering land")
	await game.view.animate_moves([attack], game.cells)
	game.view.motion_stage.disconnect(observe)
	expect(stages == ["travel", "jab", "impact", "occupy", "surrender"], "Fast castle capture preserves combat and surrender stage ordering")
	expect(game.view.cells == game.cells and game.cells[Vector2i(8, 0)]["owner"] == 0, "Accelerated surrender finishes at the authoritative final board")
	game.busy = false
	ctrl(false)
	game.refresh_ui()

	# Preparation/annex/ripple tweens share the scoped speed; pause freezes them.
	game.busy = true
	game.active_faction = 1
	ctrl(true)
	game.view.play_preparation([{"kind": "spell", "coord": Vector2i(7, 0)}], game.cells)
	expect(game.view.playback.preparation_tween != null, "Preparation starts a scaled tween")
	paused = true
	var preparation: Tween = game.view.playback.preparation_tween
	var elapsed := preparation.get_total_elapsed_time()
	await create_timer(0.08, true).timeout
	expect(preparation.get_total_elapsed_time() == elapsed, "Fast preparation still freezes during pause")
	paused = false
	ctrl(false)
	while game.view.is_animating:
		await process_frame
	game.busy = false
	game.active_faction = 0
	game.refresh_ui()
	# Exercise the normal button callback and the real async opponent loop.
	game.initial_kingdom_count = 2
	game.new_game(42)
	game.end_button.button_down.emit()
	game.end_button.button_up.emit()
	game.end_button.pressed.emit()
	expect(game.busy and game.active_faction == 1, "A fresh button click starts exactly one real opponent turn")
	game.end_button.button_down.emit()
	expect(game.view.playback.speed_scale == 6, "Loading hold accelerates the real opponent loop")
	while game.busy:
		await process_frame
	expect(game.round_number == 2 and game.active_faction == 0 and not game.end_button.disabled, "Accelerated opponent loop completes and returns player control")
	game.end_button.button_up.emit()
	game.end_button.pressed.emit()
	expect(game.round_number == 2 and not game.busy, "Release after real opponent completion does not queue another turn")
	game.shutdown()
	expect(game.view.playback.speed_scale == 1, "Shutdown restores playback rate")
	game.queue_free()
	sound.stop_all()
	await create_timer(0.1).timeout
	sound.set_muted(muted, false)
	print("Playback speed checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
