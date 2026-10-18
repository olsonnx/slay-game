extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var video = root.get_node("Video")
	var previous: bool = video.level_transitions
	video.set_preference(&"level_transitions", true, false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	app.start_new_game(42, "large")
	expect(app.transitioning and app.game == null and not app.menus.menu_background.active, "Preparation is covered and the menu stops before scene creation")
	app.start_new_game(99, "very_small")
	var responsive_frames := 0
	while app.transitioning:
		responsive_frames += 1
		await process_frame
	var game = app.game
	var expected = load("res://src/game/kingdom_rules.gd").new()
	expected.rule_mode = game.initial_rule_mode
	expected.generate(42, "large")
	expect(game.cells == expected.cells and game.rules.rng.state == expected.rng.state and game.rules.kingdoms == expected.kingdoms, "Worker preparation reproduces all seeded rules and ignores duplicate starts")
	expect(responsive_frames > 5 and game.startup_timings["batches"] > 1, "Large preparation yields between construction batches")
	expect(game.view.level_transitioning and not game.view.controls_enabled, "Entrance starts after preparation with controls locked")
	while game.view.level_transitioning:
		await process_frame
	expect(game.view.controls_enabled and game.view.tile_nodes.size() == game.cells.size(), "Prepared board settles completely and unlocks")
	await app.return_to_main_menu()
	video.set_preference(&"level_transitions", previous, false)
	app.queue_free()
	await process_frame
	print("Startup checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
