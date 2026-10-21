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
	var floating_birds := false
	var publishing_frames := 0
	while app.transitioning:
		responsive_frames += 1
		if is_instance_valid(app.game):
			var published: int = app.game.view.static_batches.tile_records.size()
			if published > 0 and published < app.game.cells.size(): publishing_frames += 1
		if is_instance_valid(app.game) and app.game.view.level_transitioning:
			floating_birds = floating_birds or app.game.view.birds.visible
		await process_frame
	expect(not floating_birds and not app.game.view.birds.visible, "Birds stay hidden during covered preparation and island entrance")
	var game = app.game
	var expected = load("res://src/game/kingdom_rules.gd").new()
	expected.rule_mode = game.initial_rule_mode
	expected.generate(42, "large")
	expect(game.cells == expected.cells and game.rules.rng.state == expected.rng.state and game.rules.kingdoms == expected.kingdoms, "Worker preparation reproduces all seeded rules and ignores duplicate starts")
	expect(publishing_frames > 1, "Normal startup spreads scenery collection across frames")
	expect(responsive_frames > 5 and game.startup_timings["batches"] > 1, "Large preparation yields between construction batches")
	expect(game.view.level_transitioning and not game.view.controls_enabled, "Entrance starts after preparation with controls locked")
	while game.view.level_transitioning:
		await process_frame
	expect(game.view.birds.visible, "Birds appear after the island settles")
	expect(game.view.controls_enabled and game.view.tile_nodes.size() == game.cells.size(), "Prepared board settles completely and unlocks")
	await app.return_to_main_menu()
	var document = load("res://src/editor/level_document.gd").new()
	document.cells = expected.cells.duplicate(true)
	for cell in document.cells.values():
		cell["event"] = ""
		cell.erase("treasure")
	document.map_size = "large"
	document.rule_mode = expected.rule_mode
	document.seed_value = 42
	document.player_faction = 1
	document.starting_gold = 73
	document.factions[1]["name"] = "Restart kingdom"
	document.factions[1]["color"] = "ff6644"
	document.factions[1]["terrain"] = "44aa66"
	var draft: Dictionary = document.state()
	var untouched: Dictionary = draft.duplicate(true)
	# Compare against the same serialized authored format the loader receives.
	var reloaded = load("res://src/editor/level_document.gd").new()
	expect(reloaded.read_data(draft.duplicate(true)).is_empty(), "Authored startup fixture validates")
	var authored_expected = reloaded.build_rules()
	await app.start_new_game(42, "large", "", 0, draft)
	while app.game.view.level_transitioning: await process_frame
	expect(app.game.cells == authored_expected.cells and app.game.rules.kingdoms == authored_expected.kingdoms, "Worker-loaded authored rules preserve cells and starting resources")
	expect(app.game.player_faction == 1 and app.game.session.names[1] == "Restart kingdom" and app.game.session.colors[1] == Color("ff6644") and app.game.view.COLORS[1] == Color("44aa66"), "Prepared document supplies authored player and kingdom palettes")
	app.pause_game()
	await app.restart_current_level()
	while app.game.view.level_transitioning: await process_frame
	expect(app.game.cells == authored_expected.cells and app.game.rules.kingdoms == authored_expected.kingdoms, "Playtest restart restores the exact authored map through background preparation")
	expect(draft == untouched and app.custom_level == untouched, "Background validation and restart leave the original editor snapshot untouched")
	expect(app.game.view.static_batches.tile_records.size() == app.game.cells.size() and not app.game.view.bulk_rebuilding, "Restart finishes publishing every tile before enabling play")
	await app.return_to_main_menu()
	video.set_preference(&"level_transitions", previous, false)
	app.queue_free()
	await process_frame
	print("Startup checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
