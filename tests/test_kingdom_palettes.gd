extends SceneTree
const Catalog = preload("res://src/game/game_catalog.gd")
const Setup = preload("res://src/game/match_setup.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)
func unique(values: Array) -> Array:
	var result := []
	for value in values:
		if value not in result: result.append(value)
	return result
func run() -> void:
	expect(Catalog.FACTIONS.size() == 12 and unique(Catalog.FACTIONS).size() == 12, "Twelve different kingdoms are available")
	expect(unique(Catalog.TERRAIN_COLORS).size() == 12 and unique(Catalog.UI_COLORS).size() == 12, "Every kingdom has its own terrain and UI colors")
	for size_id in Sizes.IDS: expect(Sizes.MAX_KINGDOMS[size_id] == 6, "Map kingdom limits remain unchanged")
	for color in range(12):
		for count in [2,6]:
			var setup := Setup.quick_play("small",count,"hard",color,42,"modern")
			var colors: Array = setup.slots.map(func(seat): return seat.color)
			expect(colors.size() == count and unique(colors).size() == count and colors[0] == color, "A chosen kingdom is honored without duplicate opponents")
			expect(Setup.human_count(setup) == 1 and setup.slots[0].controller == "human", "Quick Play always keeps the human in seat zero")
			expect(setup.slots.all(func(seat): return seat.name == Catalog.FACTIONS[seat.color] and seat.difficulty == "hard"), "Names and opponent difficulty follow the resolved lineup")
	var random_choices := []
	for seed_value in range(128):
		var setup := Setup.quick_play("small",6,"normal",-1,seed_value,"modern")
		random_choices.append(setup.slots[0].color)
		expect(setup == Setup.quick_play("small",6,"normal",-1,seed_value,"modern"), "A seed reproduces the same random lineup")
	expect(unique(random_choices).size() == 12, "Random can choose every kingdom, including all six new ones")
	var normalized := Setup.normalize({"count":6,"slots":[{"color":11},{"color":10},{"color":11},{"color":99}]})
	expect(normalized.slots[0].color == 11 and normalized.slots[1].color == 10 and unique(normalized.slots.map(func(seat): return seat.color)).size() == 6, "Multiplayer accepts new colors and still repairs duplicates")
	var settings = root.get_node("Gameplay")
	var settings_before := {"path":settings.settings_path,"kingdom":settings.quick_play_kingdom,"rules":settings.rule_mode}
	settings.settings_path = "res://artifacts/kingdom-palette-settings.cfg"
	settings.set_quick_play_kingdom(11)
	settings.quick_play_kingdom = -1
	settings.load_settings(settings.settings_path)
	expect(settings.quick_play_kingdom == 11, "The selected kingdom survives a settings reload")
	var corrupt := ConfigFile.new()
	corrupt.set_value("gameplay","quick_play_kingdom",99)
	corrupt.save(settings.settings_path)
	settings.load_settings(settings.settings_path)
	expect(settings.quick_play_kingdom == -1, "Invalid saved kingdom choices recover to Random")
	settings.set_quick_play_kingdom(11,false)
	settings.set_rules("modern",false)
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	root.size = Vector2i(960,620)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.menus.show_screen(app.menus.Screen.SETUP)
	await process_frame
	expect(app.menus.player_kingdom_choice.item_count == 13 and app.menus.player_kingdom_choice.get_selected_metadata() == 11, "Quick Play shows Random and all twelve kingdoms, restoring the preference")
	expect(root.get_visible_rect().encloses(app.menus.setup_panel.get_global_rect()), "The Quick Play panel fits the minimum viewport")
	expect(app.menus.difficulty_choice.get_global_rect().position.x > app.menus.kingdom_choice.get_global_rect().end.x, "Kingdom count and difficulty controls do not overlap")
	expect(app.menus.multiplayer_panel.rows[0].color.item_count == 12 and app.menus.multiplayer_panel.rows.size() == 6, "Multiplayer offers twelve colors while retaining six seats")
	await app.start_new_game(42,"small","normal",6)
	var game = app.game
	var cells: Dictionary = game.cells.duplicate(true)
	var colors: Array = game.view.COLORS.duplicate()
	var names: Array = game.NAMES.duplicate()
	var initial_rng: int = game.rules.rng.state
	expect(game.rules.faction_count == 6 and game.player_faction == 0 and game.rules.human_factions == [0], "New palettes do not change faction count or turn ownership")
	expect(game.NAMES[0] == "Iris" and game.view.COLORS[0] == Catalog.TERRAIN_COLORS[11] and game.COLORS[0] == Catalog.UI_COLORS[11], "Chosen kingdom names and colors reach the game and renderer")
	expect(game.rules.replay_log.header.metadata.match.slots[0].color == 11 and game.rules.replay_log.header.names[0] == "Iris", "Replay metadata records the resolved kingdom")
	var recorded_factions: Array = game.rules.replay_log.header.metadata.factions
	expect(recorded_factions.size() == 12 and Color.html(recorded_factions[0].color) == game.COLORS[0] and Color.html(recorded_factions[0].terrain) == game.view.COLORS[0], "Replay records the exact live UI and terrain palette, including spare kingdom identities")
	var baseline = preload("res://src/game/kingdom_rules.gd").new()
	baseline.rule_mode = "modern"
	baseline.generate(42,"small",6)
	expect(game.cells == baseline.cells and game.rules.rng.state == baseline.rng.state, "Palette selection leaves map generation and gameplay randomness untouched")
	settings.set_quick_play_kingdom(6,false)
	await app.restart_current_level()
	expect(app.game.cells == cells and app.game.view.COLORS == colors and app.game.NAMES == names and app.game.rules.rng.state == initial_rng, "Restart preserves the island and resolved lineup even after preferences change")
	await app.return_to_main_menu()
	app.menus.show_screen(app.menus.Screen.SETUP)
	app.menus.player_kingdom_choice.select(7)
	app.menus.player_kingdom_choice.item_selected.emit(7)
	app.menus.kingdom_choice.select(0)
	app.menus.setup_start_button.pressed.emit()
	while app.transitioning: await process_frame
	expect(app.game.NAMES[0] == "Ruby" and app.game.rules.faction_count == 2 and settings.quick_play_kingdom == 6, "The Quick Play controls save and launch the selected kingdom")
	await app.return_to_main_menu()
	settings.set_quick_play_kingdom(-1,false)
	await app.start_new_game(44,"small","normal",2)
	expect(app.game.initial_match_config == Setup.quick_play("small",2,"normal",-1,44,"modern"), "Random resolves automatically for a fresh Quick Play match")
	await app.return_to_main_menu()
	var document = preload("res://src/editor/level_document.gd").new()
	document.cells = baseline.cells.duplicate(true)
	for cell in document.cells.values():
		cell["event"] = ""
		cell.erase("treasure")
	document.player_faction = 0
	document.factions[0] = {"name":"Authored kingdom", "color":"234567ff", "terrain":"8b4567ff"}
	await app.start_new_game(42, "small", "normal", 6, document.state())
	var authored_header: Dictionary = app.game.rules.replay_log.header
	expect(authored_header.metadata.mode == "editor" and authored_header.metadata.map_title == document.title, "Authored replays retain their custom-map mode and title")
	expect(authored_header.names[0] == "Authored kingdom" and authored_header.metadata.factions[0].color == "234567ff" and authored_header.metadata.factions[0].terrain == "8b4567ff", "Authored-map recordings capture their exact names, UI colors and terrain colors")
	expect(preload("res://src/game/replay_identity.gd").resolve(authored_header).terrain == app.game.view.COLORS, "The recorded authored palette reconstructs the live renderer exactly")
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	settings.settings_path = settings_before.path
	settings.set_quick_play_kingdom(settings_before.kingdom,false)
	settings.set_rules(settings_before.rules,false)
	root.get_node("Sound").stop_all()
	await create_timer(0.3).timeout
	print("Kingdom palette checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
