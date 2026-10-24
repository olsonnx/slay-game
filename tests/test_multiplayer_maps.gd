extends SceneTree
const Document = preload("res://src/editor/level_document.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Setup = preload("res://src/game/match_setup.gd")
var checks := 0
var failures := 0
const MAP_PATH := "res://artifacts/multiplayer_editor_map_test.json"
const BAD_PATH := "res://artifacts/multiplayer_bad_map_test.json"

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func save_data(path: String, data: Variant) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func fixture(six := false):
	var document = Document.new()
	document.title = "Six kingdoms" if six else "Cove and Tide"
	document.map_size = "very_small"
	document.rule_mode = "modern"
	document.seed_value = 73
	document.starting_gold = 37
	var anchors := [Vector2i(-4,-2),Vector2i(0,-2),Vector2i(4,-2),Vector2i(-4,2),Vector2i(0,2),Vector2i(3,2)] if six else [Vector2i(0,0),Vector2i(4,0)]
	for index in range(anchors.size()):
		var owner: int = index if six else [2,5][index]
		for direction in [Vector2i.ZERO,Vector2i(1,0)]:
			var coord: Vector2i = anchors[index]+direction
			document.cells[coord] = Rules.new().make_cell(owner)
			document.cells[coord]["value"] = 2
		document.cells[anchors[index]]["capital"] = owner
		document.cells[anchors[index]]["unit"] = 1
		if not six: document.cells[anchors[index]]["mana_source"] = true
	if not six:
		var mountain := Vector2i(-2,0)
		document.cells[mountain] = Rules.new().make_cell(-1)
		document.cells[mountain]["mountain"] = true
		document.cells[mountain]["value"] = 0
		var bridge := Vector2i(2,0)
		document.cells[bridge] = Rules.new().make_cell(-1)
		document.cells[bridge]["building"] = "bridge"
		document.cells[bridge]["value"] = 0
	return document

func run() -> void:
	var gameplay = root.get_node("Gameplay")
	var original_rules: String = gameplay.rule_mode
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	var document = fixture()
	var original: Dictionary = document.state()
	save_data(MAP_PATH,original)
	var read := Setup.read_level(MAP_PATH)
	expect(read["error"] == "" and read["factions"] == [2,5],"Saved editor maps support sparse factions without Fern")
	expect(read["data"]["gold"] == 37 and read["data"]["seed"] == 73,"Authored starting gold and seed are retained")
	var remapped = Document.new()
	expect(remapped.read_data(read["data"]) == "","The compacted map remains a valid editor document")
	expect(remapped.cells[Vector2i.ZERO]["owner"] == 0 and remapped.cells[Vector2i(4,0)]["owner"] == 1,"Authored factions map to contiguous player seats")
	expect(document.state() == original,"Converting a multiplayer map does not modify the editor document")
	expect(Setup.read_level("res://artifacts/nonexistent_multiplayer_map.json")["error"] != "","Missing maps give a readable error")
	save_data(BAD_PATH,{"format":"bad"})
	expect(Setup.read_level(BAD_PATH)["error"] != "","Malformed maps are rejected")
	var singleton = fixture()
	singleton.cells.erase(Vector2i(5,0))
	save_data(BAD_PATH,singleton.state())
	expect(Setup.read_level(BAD_PATH)["error"].contains("connected provinces"),"Every starting faction needs a playable kingdom")
	var solo = fixture()
	solo.cells.erase(Vector2i(4,0))
	solo.cells.erase(Vector2i(5,0))
	save_data(BAD_PATH,solo.state())
	expect(Setup.read_level(BAD_PATH)["error"].contains("at least two"),"Maps with only one faction cannot start multiplayer")
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await process_frame
	var panel = app.menus.multiplayer_panel
	panel.load_config({"map_path":"res://artifacts/missing_multiplayer_map.json","count":2})
	expect(panel.source_choice.selected == 1 and panel.start_button.disabled,"A missing saved map is visibly unavailable instead of silently generating an island")
	panel.source_choice.select(0)
	panel.source_choice.item_selected.emit(0)
	expect(not panel.start_button.disabled and not panel.size_choice.disabled,"A missing saved map can be replaced with a generated island")
	panel.load_config({})
	panel.load_editor_map(ProjectSettings.globalize_path(MAP_PATH))
	app.menus.show_screen(app.menus.Screen.MULTIPLAYER)
	expect(panel.using_editor_map() and panel.seat_count() == 2,"Loading an editor map creates one seat per authored faction")
	expect(panel.source_choice.get_item_text(1).contains("Cove and Tide"),"The selected map is identified by its title")
	expect(panel.rows[0]["color"].selected == 2 and panel.rows[1]["color"].selected == 5,"Original map faction colours seed the lobby palette")
	expect(panel.size_choice.disabled and panel.count_choice.disabled and not panel.seed_input.editable,"Authored map settings are shown and fixed")
	expect(not panel.rows[0]["color"].disabled and not panel.rows[1]["difficulty"].disabled,"Player colours and AI preferences remain editable")
	expect(not panel.start_button.disabled and not panel.rows[2]["name"].visible,"A two-player editor map is ready to start")
	panel.rows[0]["name"].text = "Map player"
	panel.rows[0]["color"].select(4)
	panel.select_color(0,4)
	var settings: Dictionary = panel.config()
	expect(settings["map_path"].ends_with("multiplayer_editor_map_test.json"),"The chosen map path is included in match settings")
	panel.load_config(settings)
	expect(panel.using_editor_map() and panel.config() == settings,"Reopening setup restores the map and customised roster")
	panel.load_editor_map(BAD_PATH)
	expect(panel.selected_level["data"]["title"] == "Cove and Tide" and panel.start_button.disabled,"A failed load keeps the previous map and shows an error")
	panel.load_editor_map(settings["map_path"],true)
	panel.start_match()
	while app.transitioning: await process_frame
	var game = app.game
	expect(is_instance_valid(game) and game.is_hotseat(),"An editor map starts through the normal multiplayer button")
	expect(game.cells.size() == document.cells.size() and game.rules.level_seed == 73,"The match uses the exact authored island rather than generating a new one")
	expect(game.cells[Vector2i(-2,0)]["mountain"] and game.cells[Vector2i(2,0)]["building"] == "bridge","Authored mountains and bridges survive loading")
	expect(game.cells[Vector2i.ZERO]["unit"] == 1 and game.cells[Vector2i(4,0)]["unit"] == 1,"Authored armies survive loading")
	expect(game.rules.kingdom_at(Vector2i(4,0))["gold"] == 37,"Unstarted seats keep their authored treasury")
	expect(game.NAMES[0] == "Map player" and game.view.COLORS[0] == game.Catalog.TERRAIN_COLORS[4],"Custom multiplayer names and colours apply to authored factions")
	expect(app.menus.quit_menu_button.text == "Main menu","Authored rules are protected and quitting goes to the main menu")
	expect(not panel.seed_input.editable,"Completing navigation does not unlock authored setup settings")
	var cells: Dictionary = game.cells.duplicate(true)
	var kingdoms: Dictionary = game.rules.kingdoms.duplicate(true)
	await game.end_turn()
	expect(game.player_faction == 1 and not game.busy,"Editor maps support normal local turn rotation")
	save_data(MAP_PATH,{"format":"changed after start"})
	await app.restart_current_level()
	game = app.game
	expect(game.cells == cells and game.rules.kingdoms == kingdoms,"Restart uses the captured original map even after its file changes")
	expect(game.initial_match_config == settings,"Restart retains the selected map and player configuration")
	await app.return_to_main_menu()
	await app.start_multiplayer(settings)
	expect(app.game == null and panel.start_button.disabled,"A map changed before a new match is validated again")
	save_data(MAP_PATH,original)
	panel.load_editor_map(settings["map_path"],true)
	panel.source_choice.select(0)
	panel.source_choice.item_selected.emit(0)
	expect(not panel.using_editor_map() and not panel.size_choice.disabled and panel.seed_input.editable,"Switching back to generated maps restores editable settings")
	expect(not panel.config().has("map_path"),"Generated matches do not keep a stale editor-map selection")
	var six = fixture(true)
	save_data(MAP_PATH,six.state())
	panel.load_editor_map(settings["map_path"])
	expect(panel.seat_count() == 6 and panel.config()["count"] == 6 and panel.config()["size"] == "very_small","Authored maps retain retired size metadata and support six factions")
	panel.start_match()
	while app.transitioning: await process_frame
	game = app.game
	expect(game.rules.faction_count == 6 and game.rules.is_modern() and game.cells.size() == 12,"Authored size bypasses generated-map population limits")
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	gameplay.set_rules(original_rules)
	for path in [MAP_PATH,BAD_PATH]: DirAccess.remove_absolute(path)
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Multiplayer map checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
