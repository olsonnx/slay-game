extends SceneTree
const Setup = preload("res://src/game/match_setup.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func run() -> void:
	expect(Setup.normalize({"size":"very_small"})["size"] == "small", "Retired generated lobbies migrate to Tiny")
	var initial_rules: String = root.get_node("Gameplay").rule_mode
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	root.get_node("Video").set_preference(&"follow_turn_camera",false,false)
	root.size = Vector2i(960,620)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await process_frame
	var panel = app.menus.multiplayer_panel
	expect(app.menus.main_panel.find_children("*","Button",true,false).any(func(node): return node.text == "Multiplayer"),"The main menu contains a separate Multiplayer option")
	panel.load_config({"size":"small","count":6})
	app.menus.show_screen(app.menus.Screen.MULTIPLAYER)
	await process_frame
	expect(panel.visible and not app.menus.setup_panel.visible,"Multiplayer opens its own setup")
	expect(panel.get_global_rect().end.y <= root.get_visible_rect().end.y and panel.get_global_rect().position.x >= 0,"Six-seat setup fits the minimum viewport")
	for row in panel.rows:
		row["controller"].select(0)
	panel.refresh_summary()
	for row in panel.rows:
		expect(not row["difficulty"].disabled,"All-human setup keeps every AI difficulty editable")
	panel.rows[4]["difficulty"].select(2)
	panel.rows[4]["controller"].select(1)
	panel.refresh_summary()
	expect(panel.config()["slots"][4]["difficulty"] == "hard","A difficulty set before switching a seat to AI is preserved")
	expect(panel.preset_choice.selected == 0,"Mixed difficulties display a Custom preset")
	panel.preset_choice.select(1)
	panel.preset_choice.item_selected.emit(1)
	expect(panel.rows.all(func(row): return row["difficulty"].selected == 0),"An AI preset updates every seat's difficulty")
	var old: int = panel.rows[0]["color"].selected
	var other: int = panel.rows[5]["color"].selected
	panel.rows[0]["color"].select(other)
	panel.select_color(0,other)
	expect(panel.rows[5]["color"].selected == old,"Picking an occupied colour swaps seats")
	var colors: Array = []
	for row in panel.rows: colors.append(row["color"].selected)
	expect(colors.duplicate().size() == 6 and unique(colors).size() == 6,"All six colours stay distinct")
	panel.shuffle_colors()
	colors.clear()
	for row in panel.rows: colors.append(row["color"].selected)
	expect(unique(colors).size() == 6,"Shuffle colours preserves a unique palette")
	panel.size_choice.select(0)
	panel.refresh_counts()
	expect(panel.count_choice.item_count == 5 and panel.count_choice.selected+2 == 6 and panel.rows[5]["name"].visible,"Small supports all six kingdoms")
	for row in panel.rows: row["controller"].select(1)
	panel.rows[1]["controller"].select(0)
	panel.refresh_summary()
	expect(panel.start_button.disabled and panel.summary.text.contains("at least two"),"Multiplayer requires at least two humans")
	panel.rows[3]["controller"].select(0)
	panel.seed_input.text = "not a seed"
	panel.refresh_summary()
	expect(panel.start_button.disabled,"Invalid seeds cannot start a match")
	panel.seed_input.text = "2147483648"
	panel.refresh_summary()
	expect(panel.start_button.disabled,"Out-of-range seeds cannot start a match")
	panel.seed_input.text = "123"
	panel.refresh_summary()
	expect(not panel.start_button.disabled,"Valid mixed multiplayer can start")
	var config := Setup.normalize({"size":"very_small","count":4,"seed":123,"rules":"modern","slots":[
		{"name":"CPU A","color":5,"controller":"ai","difficulty":"easy"},
		{"name":"Olek","color":4,"controller":"human"},
		{"name":"CPU B","color":0,"controller":"ai","difficulty":"hard"},
		{"name":"Alex","color":2,"controller":"human"}]})
	panel.load_config(config)
	expect(panel.config() == config,"Names, colours, controllers, seed, rules and AI difficulties round-trip through setup")
	panel.start_match()
	while app.transitioning: await process_frame
	var game = app.game
	expect(root.get_node("Gameplay").multiplayer_setup == config,"Starting from the lobby saves the complete chosen setup")
	expect(game.rules.human_factions == [1,3] and game.player_faction == 1,"Human seats can be placed anywhere in the roster")
	expect(game.turn_order == [1,2,3,0],"Seat order starts at the first human and includes all computer seats")
	expect(game.NAMES[1] == "Olek" and game.rules.faction_names[3] == "Alex","Custom names reach the HUD and province inspectors")
	expect(game.view.COLORS[1] == Catalog.TERRAIN_COLORS[4] and game.COLORS[1] == Catalog.UI_COLORS[4],"A player can use any colour even outside the selected faction count")
	expect(Catalog.TERRAIN_COLORS[1] != game.view.COLORS[1],"Session palettes do not mutate shared faction colours")
	expect(not game.commands_locked() and game.view.controls_enabled,"No Ready screen or input gate delays local play")
	var map_before: Dictionary = game.cells.duplicate(true)
	var kingdoms_before: Dictionary = game.rules.kingdoms.duplicate(true)
	var zoom: float = game.view.camera.size
	var angle: float = game.view.yaw
	await game.end_turn()
	expect(game.player_faction == 3 and game.active_kingdom()["owner"] == 3,"The interleaved computer runs before the next human")
	expect(game.rules.ai_difficulty == "hard","Each computer uses its own difficulty")
	await create_timer(0.65).timeout
	var center := Vector3.ZERO
	for coord in game.active_kingdom()["hexes"]: center += game.view.coord_position(coord)
	center /= game.active_kingdom()["hexes"].size()
	expect(game.view.focus.distance_to(center) < 0.01,"The camera pans to the next human even with AI camera-follow disabled")
	expect(game.view.camera.size == zoom and game.view.yaw == angle,"Turn panning preserves camera angle and zoom")
	expect(game.level_label.text == "Alex","The current player's chosen name identifies their turn")
	await game.end_turn()
	expect(game.player_faction == 1 and game.round_number == 2 and game.rules.ai_difficulty == "easy","The final computer uses its own difficulty and completes the round")
	await app.restart_current_level()
	game = app.game
	expect(game.initial_match_config == config and game.cells == map_before and game.rules.kingdoms == kingdoms_before,"Restart preserves the complete roster and exact initial island")
	expect(game.turn_order == [1,2,3,0] and game.view.COLORS[1] == Catalog.TERRAIN_COLORS[4],"Restart retains colours and turn order")
	await app.return_to_main_menu()
	config["order"] = "random"
	await app.start_multiplayer(config)
	var order: Array = app.game.turn_order.duplicate()
	expect(unique(order).size() == 4 and order[0] in [1,3],"Shuffled order contains every seat and starts with a human")
	await app.restart_current_level()
	expect(app.game.turn_order == order,"A shuffled match restarts with the same turn order")
	app.continue_game()
	await app.return_to_main_menu()
	app.menus.new_game_requested.emit("very_small",2)
	while app.transitioning: await process_frame
	expect(not app.game.is_hotseat() and app.game.rules.human_factions == [0],"Quick Play always starts solo regardless of multiplayer preferences")
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	var bad := Setup.normalize({"size":"missing","count":99,"slots":[{"color":5},{"color":5},{"color":-99},{"name":false,"difficulty":"impossible"}]})
	colors.clear()
	for seat in bad["slots"]: colors.append(seat["color"])
	expect(unique(colors).size() == 6 and bad["size"] == "small", "Invalid persisted configurations recover without duplicate colours")
	root.get_node("Gameplay").set_rules(initial_rules)
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Multiplayer setup checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)

func unique(values: Array) -> Array:
	var result: Array = []
	for value in values:
		if value not in result: result.append(value)
	return result
