extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Results = preload("res://src/game/match_results.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func statistics() -> void:
	var model = Rules.new()
	model.faction_count = 2
	for x in range(7): model.cells[Vector2i(x, 0)] = model.make_cell(0 if x < 3 else 1)
	model.cells[Vector2i.ZERO]["unit"] = 2
	model.cells[Vector2i(3, 0)]["unit"] = 1
	model.cells[Vector2i(3, 0)]["capital"] = 1
	model.cells[Vector2i(4, 0)]["unit"] = 3
	var replay := Replay.new()
	replay.start(model)
	# Capturing a castle also surrenders a neighbouring unit and province.
	model.cells[Vector2i.ZERO]["unit"] = 0
	for x in [3, 4]:
		model.cells[Vector2i(x, 0)]["owner"] = 0
		model.cells[Vector2i(x, 0)]["capital"] = -1
		model.cells[Vector2i(x, 0)]["unit"] = 2 if x == 3 else 0
	replay.record(model, "move", 0, {"outcome":"attack"})
	var totals := Results.summarize(replay)
	expect(totals[0] == {"slain":2,"lost":0,"tiles":2,"capitals":1}, "Castle capture counts its defender, surrendered unit and both captured provinces")
	expect(totals[1]["lost"] == 2, "Victim casualties include all tiers")
	# A friendly merge changes the army count, but causes no casualty.
	model.cells[Vector2i(1, 0)]["unit"] = 1
	model.cells[Vector2i(2, 0)]["unit"] = 1
	replay.record(model, "recruit", 0)
	model.cells[Vector2i(1, 0)]["unit"] = 0
	model.cells[Vector2i(2, 0)]["unit"] = 2
	replay.record(model, "move", 0, {"outcome":"merge"})
	expect(Results.summarize(replay)[0]["lost"] == 0, "Friendly merges and recruitment do not inflate losses")
	model.cells[Vector2i(2, 0)]["unit"] = 0
	replay.record(model, "turn_start", 0, {"starved":1})
	totals = Results.summarize(replay)
	expect(totals[0]["lost"] == 1 and totals[1]["slain"] == 0, "Starvation counts as a loss without inventing an attacking killer")
	model.cells[Vector2i(3, 0)]["owner"] = 1
	model.cells[Vector2i(3, 0)]["unit"] = 3
	replay.record(model, "move", 1, {"outcome":"attack"})
	totals = Results.summarize(replay)
	expect(totals[1]["slain"] == 1 and totals[1]["tiles"] == 1, "Opponent kills and recaptures belong to their faction")
	model.cells[Vector2i(4, 0)]["unit"] = 3
	replay.record(model, "recruit", 0)
	model.cells[Vector2i(3, 0)]["unit"] = 0
	model.cells[Vector2i(4, 0)]["unit"] = 0
	replay.record(model, "move", 0, {"outcome":"knight_duel"})
	totals = Results.summarize(replay)
	expect(totals[0]["lost"] == 3 and totals[0]["slain"] == 3 and totals[1]["lost"] == 3 and totals[1]["slain"] == 2, "A knight duel credits each knight with the opposing casualty")
	# A bridge carries an army belonging to unit_owner rather than tile owner.
	var bridge: Dictionary = model.make_cell(-1)
	bridge["building"] = "bridge"
	bridge["unit"] = 1
	bridge["unit_owner"] = 0
	model.cells[Vector2i(8, 0)] = bridge
	replay.record(model, "build", 0)
	model.cells.erase(Vector2i(8, 0))
	replay.record(model, "spell", 1)
	totals = Results.summarize(replay)
	expect(totals[0]["lost"] == 4 and totals[1]["slain"] == 3, "Destroying a bridge counts its occupant for the correct faction")
	expect(totals[0]["tiles"] == 2, "Constructing a bridge does not inflate conquered land")
	var before: Dictionary = model.cells.duplicate(true)
	replay.begin_transaction()
	model.cells[Vector2i(5, 0)]["owner"] = 0
	replay.record(model, "move", 0)
	model.cells = before
	replay.cancel_transaction()
	expect(Results.summarize(replay) == totals, "Cancelled commands cannot affect results")

func capture(name_value: String) -> void:
	if "--preview" not in OS.get_cmdline_user_args(): return
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/results-%s.png" % name_value)

func run() -> void:
	statistics()
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.size = Vector2i(960, 620)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await process_frame
	for victory in [true, false]:
		await app.start_new_game(42, "very_small", "easy", 2)
		var game = app.game
		expect(game.match_clock.running_since >= 0, "Playing starts the invisible clock after preparation")
		app.pause_game()
		var paused_elapsed: int = game.match_clock.accumulated_usec
		await create_timer(0.12, true).timeout
		expect(game.match_clock.accumulated_usec == paused_elapsed and game.match_clock.running_since == -1, "Pause time never enters the playing clock")
		app.continue_game()
		expect(game.match_clock.running_since >= 0, "Continuing resumes the clock")
		game.match_clock.pause()
		game.match_clock.accumulated_usec = 125000000
		game.round_number = 17
		for cell in game.cells.values():
			if cell["owner"] > 0 if victory else cell["owner"] == 0:
				cell["owner"] = -1
				cell["capital"] = -1
				cell["unit"] = 0
		game.rules.rebuild_kingdoms()
		game.check_winner()
		expect(app.menus.defeat_panel.slide.is_running() and app.menus.results_dim_tween.is_running(), "Results panel and blur fade animate together while the tree is paused")
		expect(app.menus.backdrop.material != null and game.event_dialog.material != null, "Results and events share a blurred backdrop")
		expect(paused and app.menus.defeat_panel.visible, "Both victory and defeat open results and pause gameplay")
		expect(app.menus.defeat_title.text == ("Victory" if victory else "Defeat"), "Result title matches the outcome")
		expect(app.menus.result_values["turns"].text == "17" and app.menus.result_values["time"].text == "00:02:05", "Results show the final round and unscaled playing duration")
		var replay = game.rules.replay_log
		expect(replay.completed and replay.path == "", "Finishing a game never writes a replay automatically")
		app.continue_game()
		expect(paused, "A finished match cannot resume behind the results screen")
		await create_timer(0.3, true).timeout
		expect(is_equal_approx(app.menus.defeat_panel.reveal, 1.0) and is_equal_approx(app.menus.backdrop.color.a, 0.78), "Results entrance and dimming reach the same settled state as events")
		var restart: Button = app.menus.defeat_restart_button
		var save: Button = app.menus.save_replay_button
		expect(restart.text == "" and save.text == "" and restart.icon != null and save.icon != null, "Restart and replay saving use icons with descriptive tooltips")
		expect(restart.position.y == save.position.y and restart.get_rect().end.x < save.position.x, "Icon actions share one row without overlapping")
		await capture("victory" if victory else "defeat")
		var final_position := Replay.position(game.rules)
		var final_sequence: int = replay.sequence
		app.menus.show_map_button.pressed.emit()
		expect(not paused and game.game_over and game.inspecting_results_map and app.menus.return_results_button.visible and not app.menus.backdrop.visible, "Show map reveals the finished board and a return control")
		var yaw: float = game.view.yaw
		var right := InputEventMouseButton.new()
		right.button_index = MOUSE_BUTTON_RIGHT
		right.pressed = true
		game._input(right)
		game._unhandled_input(right)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(30, 10)
		game._input(motion)
		right.pressed = false
		game._input(right)
		expect(game.view.yaw != yaw, "Finished maps retain right-drag camera rotation")
		var focus: Vector3 = game.view.focus
		var middle := InputEventMouseButton.new()
		middle.button_index = MOUSE_BUTTON_MIDDLE
		middle.pressed = true
		game._unhandled_input(middle)
		game._input(motion)
		middle.pressed = false
		game._input(middle)
		expect(game.view.focus != focus, "Finished maps retain middle-drag camera movement")
		focus = game.view.focus
		game.view.pan(Vector2.RIGHT, 0.1)
		expect(game.view.focus != focus, "Finished maps retain the camera's directional pan controls")
		var zoom: float = game.view.zoom
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_UP
		wheel.pressed = true
		game._unhandled_input(wheel)
		game.view.navigation._process(0.1)
		expect(game.view.zoom != zoom, "Finished maps retain scroll zoom")
		var left := InputEventMouseButton.new()
		left.button_index = MOUSE_BUTTON_LEFT
		left.pressed = true
		game._unhandled_input(left)
		game.choose_unit(3)
		await game.end_turn()
		expect(Replay.position(game.rules) == final_position and replay.sequence == final_sequence and game.match_clock.seconds() == 125, "Map inspection cannot change the board, replay, turns or final playing time")
		await capture("map")
		if victory:
			app.menus.return_results_button.pressed.emit()
		else:
			var escape := InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			game._unhandled_input(escape)
		expect(paused and not game.inspecting_results_map and app.menus.defeat_panel.visible, "The return button and Escape restore results with gameplay paused")
		var target := "res://artifacts/results-%s.jsonl" % str(victory)
		if FileAccess.file_exists(target): DirAccess.remove_absolute(target)
		replay.destination = "res://project.godot/impossible.jsonl"
		app.save_replay()
		expect(replay.error != "" and not app.menus.save_replay_button.disabled, "Failed saves leave the recording available for retry")
		replay.destination = target
		app.menus.save_replay_button.pressed.emit()
		expect(FileAccess.file_exists(target) and app.menus.save_replay_button.disabled, "The Save replay button saves exactly once")
		var commands: int = replay.sequence
		app.save_replay()
		game.check_winner()
		expect(replay.sequence == commands and replay.path == target, "Repeated result checks or saves cannot duplicate the result or file")
		expect(Replay.read_replay(target)["error"] == "", "Manually saved replay remains fully reconstructable")
		var summary := preload("res://src/game/replay_summary.gd").read_preview(target)
		expect(summary.duration_seconds == 125 and summary.mode == "quick_play" and summary.result == ("victory" if victory else "defeat"), "Saved replay summary preserves the paused match clock, game mode and displayed result")
		await app.return_to_main_menu()
	await app.start_new_game(42, "very_small", "easy", 2, {}, 2)
	var hotseat = app.game
	expect(hotseat.rules.replay_log.header.metadata.mode == "hotseat", "Replay metadata distinguishes local multiplayer from Quick Play")
	var unsaved_path := "res://artifacts/results-unsaved.jsonl"
	if FileAccess.file_exists(unsaved_path): DirAccess.remove_absolute(unsaved_path)
	hotseat.rules.replay_log.destination = unsaved_path
	for cell in hotseat.cells.values():
		if cell["owner"] == 1: cell["capital"] = -1
	hotseat.check_winner()
	hotseat.match_results = {0:{"slain":3,"lost":1}, 1:{"slain":1,"lost":3}}
	app.menus.show_results(hotseat)
	expect(app.menus.defeat_description.visible and app.menus.defeat_description.text == "Victory for Fern!", "Hotseat results show the winning faction")
	expect(app.menus.defeat_description.get_rect().end.y <= app.menus.results_faction.position.y and app.menus.results_faction.get_rect().end.y <= 143, "Hotseat outcome and statistics selector occupy separate rows")
	expect(app.menus.results_faction.visible and app.menus.result_values["slain"].text == "3", "Hotseat results initially show the first local player's statistics")
	app.menus.results_faction.select(1)
	app.menus.results_faction.item_selected.emit(1)
	expect(app.menus.result_values["slain"].text == "1" and app.menus.result_values["lost"].text == "3", "Each local player can select their own results")
	await app.return_to_main_menu()
	expect(not FileAccess.file_exists(unsaved_path), "Leaving results without saving creates no replay file")
	app.menus.open_options(app.menus.Screen.MAIN)
	var tabs = app.menus.options_view.get_child(0)
	expect(tabs.tab_count == 4, "Options only contains audio, video, gameplay and controls")
	tabs.current_tab = 3
	await process_frame
	expect(app.menus.options_view.controls_page.visible and not app.menus.options_view.audio_page.visible, "The final options tab still opens Controls after removing Replays")
	for button in app.menus.pause_panel.find_children("*", "Button", true, false):
		expect(not button.text.contains("Replay"), "Pause menu has no replay folder shortcut")
	await capture("options")
	app.queue_free()
	await process_frame
	print("Results checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
