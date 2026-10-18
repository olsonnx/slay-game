extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const Fixtures = preload("res://tests/test_fixtures.gd")
var checks := 0
var failures := 0
class SearchHost extends Node:
	var closing := false

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func line_board():
	var rules = Rules.new()
	for q in range(7):
		rules.cells[Vector2i(q, 0)] = rules.make_cell(0 if q <= 2 else 1 if q >= 4 else -1)
	rules.rebuild_kingdoms()
	return rules

func tactics() -> void:
	var rules = line_board()
	rules.cells[Vector2i(2, 0)]["unit"] = 2
	rules.cells[Vector2i(6, 0)]["unit"] = 1
	rules.cells[Vector2i(3, 0)]["owner"] = 1
	rules.rebuild_kingdoms()
	var danger: Dictionary = Analysis.threats(rules, 0)
	expect(danger.has(Vector2i(2, 0)), "Threat map follows a remote army across its kingdom")
	var before: Dictionary = rules.cells.duplicate(true)
	var banks: Dictionary = rules.kingdoms.duplicate(true)
	var random_state: int = rules.rng.state
	var planner = Planner.new(rules, 0)
	var first: Dictionary = planner.run()
	expect(rules.cells == before and rules.kingdoms == banks and rules.rng.state == random_state, "Search leaves live cells, treasuries and RNG untouched")
	var again: Dictionary = Planner.new(rules, 0).run()
	expect(first == again, "Fixed board produces deterministic policy decisions")
	var copy = Analysis.snapshot(rules)
	copy.cells[Vector2i(0, 0)]["tree"] = true
	copy.kingdoms.values()[0]["gold"] = 999
	expect(rules.cells == before and rules.kingdoms == banks, "Simulation dictionaries have no shared mutable contents")
	rules.cells[Vector2i(3, 0)]["event"] = "gold"
	var gold: Dictionary = Planner.new(rules, 0).run()
	rules.cells[Vector2i(3, 0)]["event"] = "pit"
	expect(Planner.new(rules, 0).run() == gold, "Hidden event identity cannot influence search")
	# Sole Soldier protects a capital; all available captures would expose it.
	rules = line_board()
	rules.cells[Vector2i(0, 0)]["unit"] = 2
	rules.cells[Vector2i(1, -1)] = rules.make_cell(1)
	rules.cells[Vector2i(2, -1)] = rules.make_cell(1)
	rules.cells[Vector2i(2, -1)]["unit"] = 2
	rules.rebuild_kingdoms()
	expect(Planner.new(rules, 0).run().is_empty(), "AI holds its sole defender instead of exposing its capital")
	# Wage guard checks the eighteen-gold Modern Soldier-to-Knight increase.
	rules = line_board()
	rules.rule_mode = "modern"
	rules.cells[Vector2i(1, 0)]["unit"] = 2
	rules.rebuild_kingdoms()
	var bank: Dictionary = rules.kingdom_at(Vector2i(1, 0))
	bank["gold"] = 20
	for coord in bank["hexes"]:
		rules.cells[coord]["value"] = 3
	expect(not Analysis.sustainable(rules, bank, 18, 20), "Normal rejects an upgrade whose true wages exceed income")
	rules.ai_difficulty = "hard"
	expect(not Analysis.sustainable(rules, bank, 18, 20), "Hard also rejects an immediate post-purchase bankruptcy")
	bank["gold"] = 100
	expect(Analysis.sustainable(rules, bank, 18, 20), "Hard permits a deficit backed by several turns of reserves")
	# Two Scouts must merge before the defended frontier can be captured.
	rules = line_board()
	rules.cells[Vector2i(1, 0)]["unit"] = 1
	rules.cells[Vector2i(2, 0)]["unit"] = 1
	rules.cells[Vector2i(3, 0)]["owner"] = 1
	rules.rebuild_kingdoms()
	var action: Dictionary = Planner.new(rules, 0).run()
	expect(not action.is_empty() and rules.cells[action["coord"]]["unit"] == 1, "Normal coordinates a merge to unlock an enemy attack")
	# An isolated Knight trade opens no follow-up and sacrifices the defender.
	rules = line_board()
	rules.cells[Vector2i(2, 0)]["unit"] = 3
	rules.cells[Vector2i(3, 0)]["owner"] = 1
	rules.cells[Vector2i(3, 0)]["unit"] = 3
	rules.cells[Vector2i(0, 1)] = rules.make_cell(0)
	rules.rebuild_kingdoms()
	rules.kingdom_at(Vector2i(2, 0))["gold"] = 100
	action = Planner.new(rules, 0).run()
	expect(action.is_empty() or action["coord"] != Vector2i(3, 0), "AI avoids an unsupported Knight sacrifice")
	var event := {"id": "duel", "coord": Vector2i(2, 0), "faction": 0}
	expect(Analysis.event_choice(rules, event) == 1, "AI refuses to gamble an essential capital defender")
	rules = line_board()
	rules.cells[Vector2i(1, 0)]["unit"] = 1
	rules.cells[Vector2i(3, 0)]["event"] = "pit"
	var movements: Array = rules.ai_movements(0)
	expect(not movements.is_empty() and movements[0]["after_target"]["unit"] == 0 and rules.pending_events.is_empty(), "AI simulation of faction zero resolves encounters on arrival without changing player command behavior")

func generated_checks() -> void:
	var times: Dictionary = {}
	for difficulty in Analysis.PROFILES:
		var started := Time.get_ticks_usec()
		for mode in ["classic", "modern"]:
			for size_id in ["very_small", "small", "medium", "large"]:
				var rules = Rules.new()
				rules.rule_mode = mode
				rules.ai_difficulty = difficulty
				rules.generate(42, size_id)
				var repeat = Rules.new()
				repeat.rule_mode = mode
				repeat.ai_difficulty = difficulty
				repeat.generate(42, size_id)
				var actions: Array = rules.ai_turn(1)
				repeat.ai_turn(1)
				expect(rules.cells == repeat.cells and rules.kingdoms == repeat.kingdoms and rules.rng.state == repeat.rng.state, "AI turns reproduce on " + difficulty + "/" + mode + "/" + size_id)
				expect(not actions.is_empty(), "AI can act on every size and difficulty")
				for kingdom in rules.kingdoms.values():
					if kingdom["owner"] == 1:
						expect(kingdom["gold"] >= 0 and kingdom["gold"] + rules.income(kingdom) - rules.upkeep(kingdom) >= 0, "Generated AI leaves affordable reserves")
				for action in actions:
					if action.has("source"):
						expect(action["before_source"]["unit"] > 0 and not action["path"].is_empty(), "Committed movements carry valid playback records")
			times[difficulty] = (Time.get_ticks_usec() - started) / 1000.0
	print("AI generated turn checks (16 turns per difficulty), ms: ", times)

func spell_checks() -> void:
	for spell in ["summon", "shatter", "trailblaze"]:
		var rules = line_board()
		rules.rule_mode = "modern"
		for bank in rules.kingdoms.values():
			bank["gold"] = 0
		match spell:
			"summon":
				# A useful mana-funded Scout still needs its new four-gold wage.
				rules.cells[Vector2i.ZERO]["value"] = 2
			"shatter":
				rules.cells[Vector2i(3, 0)]["building"] = "bridge"
				rules.cells[Vector2i(3, 0)]["unit"] = 3
				rules.cells[Vector2i(3, 0)]["unit_owner"] = 1
				rules.cells[Vector2i(3, 0)]["unit_home"] = Vector2i(4, 0)
				rules.cells[Vector2i(1, 0)]["unit"] = 1
			"trailblaze":
				rules.cells[Vector2i(1, 0)]["unit"] = 1
				rules.cells[Vector2i(2, 1)] = rules.make_cell()
		rules.rebuild_kingdoms()
		Fixtures.fund_mana(rules, 0, 3)
		var action: Dictionary = Planner.new(rules, 0, true).run()
		expect(action.get("spell", "") == spell, "AI selects " + spell + " when it is the useful tactical choice")
		if action.get("spell", "") == spell:
			expect(Candidates.apply(rules, action, 0), "Selected " + spell + " executes through shared validation")

func settings_checks() -> void:
	var preferences = root.get_node("Gameplay")
	var old_path: String = preferences.settings_path
	var old_difficulty: String = preferences.difficulty
	preferences.settings_path = "res://artifacts/ai_settings_test.cfg"
	preferences.set_difficulty("hard")
	preferences.set_difficulty("easy", false)
	preferences.load_settings(preferences.settings_path)
	expect(preferences.difficulty == "hard", "Difficulty survives saved preference reload")
	preferences.set_difficulty("invalid", false)
	expect(preferences.difficulty == "hard", "Invalid difficulty is ignored")
	var config := ConfigFile.new()
	config.set_value("gameplay", "rules", "modern")
	config.save("res://artifacts/ai_legacy_test.cfg")
	preferences.load_settings("res://artifacts/ai_legacy_test.cfg")
	expect(preferences.difficulty == "normal", "Legacy preference defaults to Normal")
	preferences.settings_path = old_path
	preferences.set_difficulty(old_difficulty, false)

func scene_checks() -> void:
	var preferences = root.get_node("Gameplay")
	var old_path: String = preferences.settings_path
	var old_mode: String = preferences.rule_mode
	var old_difficulty: String = preferences.difficulty
	preferences.settings_path = "res://artifacts/ai_scene_test.cfg"
	preferences.set_difficulty("normal", false)
	var video = root.get_node("Video")
	var transitions: bool = video.level_transitions
	video.set_preference(&"level_transitions", false, false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	expect(app.menus.difficulty_choice.get_selected_metadata() == "normal", "New Game initially selects Normal")
	app.menus.difficulty_choice.select(2)
	app.menus.setup_start_button.pressed.emit()
	while app.transitioning:
		await process_frame
	expect(app.game.rules.ai_difficulty == "hard" and preferences.difficulty == "hard", "New Game applies and remembers the selected difficulty")
	preferences.set_difficulty("easy", false)
	var seed_value: int = app.game.rules.level_seed
	await app.restart_current_level()
	expect(app.game.rules.ai_difficulty == "hard" and app.game.rules.level_seed == seed_value, "Restart keeps match difficulty despite a changed preference")
	await app.change_rules("classic" if old_mode == "modern" else "modern")
	expect(app.game.rules.ai_difficulty == "hard", "A rules change retains match difficulty")
	app.continue_game()
	var game = app.game
	game.end_turn()
	await process_frame
	app.pause_game()
	var frozen: Dictionary = game.cells.duplicate(true)
	var frozen_banks: Dictionary = game.rules.kingdoms.duplicate(true)
	await create_timer(0.12, true).timeout
	expect(game.cells == frozen and game.rules.kingdoms == frozen_banks, "Pause freezes planner commits as well as animation")
	await app.return_to_main_menu()
	expect(app.game == null and not paused and not game.busy, "Leaving during planning cancels and unwinds the turn")
	app.queue_free()
	await process_frame
	video.set_preference(&"level_transitions", transitions, false)
	preferences.set_rules(old_mode, false)
	preferences.set_difficulty(old_difficulty, false)
	preferences.settings_path = old_path
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout

func run() -> void:
	tactics()
	spell_checks()
	generated_checks()
	settings_checks()
	await worker_checks()
	await scene_checks()
	print("AI checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func worker_checks() -> void:
	var model = line_board()
	model.cells[Vector2i(2, 0)]["unit"] = 2
	model.cells[Vector2i(6, 0)]["unit"] = 1
	var cells_before: Dictionary = model.cells.duplicate(true)
	var banks_before: Dictionary = model.kingdoms.duplicate(true)
	var random_before: int = model.rng.state
	var host := SearchHost.new()
	root.add_child(host)
	host.closing = true
	var cancelled_moves: Array[Dictionary] = await model.KingdomAI.new(model).movements_async(host, 0)
	expect(cancelled_moves.is_empty(), "Cancelled movement search returns a typed empty action list")
	host.closing = false
	for difficulty in ["easy", "normal", "hard"]:
		model.ai_difficulty = difficulty
		var expected = Planner.new(model, 0)
		expected.run()
		var opponent = model.KingdomAI.new(model)
		var actual = await opponent.search_async(host, 0)
		expect(actual.best_sequence == expected.best_sequence and is_equal_approx(actual.best_score, expected.best_score), "Worker search retains deterministic difficulty decisions")
		expect(model.cells == cells_before and model.kingdoms == banks_before and model.rng.state == random_before, "Worker search leaves live rules and RNG untouched")
	var job = load("res://src/game/ai_search_job.gd").new(Analysis.snapshot(model), 0, false)
	job.cancel()
	var task := WorkerThreadPool.add_task(job.run)
	while not WorkerThreadPool.is_task_completed(task):
		await process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	expect(job.planner == null, "Cancelled queued search exits without creating a planner")
	host.queue_free()
