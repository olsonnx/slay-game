extends SceneTree
const Lessons = preload("res://src/game/tutorial_lessons.gd")
var checks := 0
var failures := 0
var preview := false
var surface: Viewport

func _initialize() -> void:
	preview = "--preview" in OS.get_cmdline_user_args()
	if preview: root.hide()
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func capture(name: String) -> void:
	if not preview: return
	await create_timer(0.4).timeout
	for frame in range(4): await process_frame
	await RenderingServer.frame_post_draw
	surface.get_texture().get_image().save_png("res://artifacts/tutorial_" + name + ".png")

func run() -> void:
	root.size = Vector2i(960,620)
	surface = root
	if preview:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960,620)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		surface = viewport
	var gameplay = root.get_node("Gameplay")
	var original_rules: String = gameplay.rule_mode
	gameplay.set_rules("classic",false)
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	for category in Lessons.IDS:
		var document = load("res://src/editor/level_document.gd").new()
		expect(document.read_data(Lessons.map_data(category)) == "", "Valid authored match: " + category)
	var app = load("res://scenes/app.tscn").instantiate()
	surface.add_child(app)
	await process_frame
	for button in app.menus.main_panel.find_children("*","Button",true,false):
		if button.text == "Tutorial": button.pressed.emit()
	expect(app.game == null and app.menus.screen == app.menus.Screen.TUTORIAL,"Tutorial opens a category selector before creating a match")
	expect(app.menus.tutorial_panel.category_buttons.size() == 3,"All three categories are available without unlocking")
	await capture("categories")
	app.menus.tutorial_panel.category_buttons["basics"].pressed.emit()
	while app.transitioning: await process_frame
	var game = app.game
	expect(game.rules.is_modern() and gameplay.rule_mode == "classic","Tutorial uses authored Modern rules without changing saved rules")
	expect(app.menus.options_view.rules_choice.disabled,"Tutorial protects its authored rules")
	var original_cells: Dictionary = game.cells.duplicate(true)
	var gold: int = game.active_kingdom()["gold"]
	game.choose_unit(3)
	await game.click_hex(Vector2i(-2,0))
	await game.end_turn()
	expect(game.tutorial.index == 0 and game.cells == original_cells and game.active_kingdom()["gold"] == gold,"Wrong purchases and early turns cannot skip objectives or spend resources")
	game.toggle_view()
	game.toggle_value_heatmap()
	expect(game.tutorial.index == 0,"Camera and heatmap are optional, not mandatory lessons")
	app.pause_game()
	game.choose_unit(1)
	await game.click_hex(Vector2i(-2,0))
	expect(game.tutorial.index == 0 and game.cells == original_cells,"Paused input cannot advance the tutorial")
	app.continue_game()
	await app.restart_current_level()
	game = app.game
	expect(game.tutorial.index == 0 and game.tutorial.category == "basics" and game.cells == original_cells,"Pause restart recreates the selected course")
	for category in Lessons.IDS:
		game = app.game
		expect(game.tutorial.category == category,"Course navigation reaches: " + category)
		var model = game.rules
		var actions := 0
		var previous_round := 1
		while not game.tutorial.completed and actions < 40:
			var step: Dictionary = game.tutorial.current()
			var before: int = game.tutorial.index
			game.playback_speed.speed_held = true
			await process_frame
			expect(step["text"].split(" ",false).size() <= 24,"Prompt stays short: " + category + "/" + step["id"])
			expect(surface.get_visible_rect().encloses(game.tutorial.panel.get_global_rect()),"Coach card fits the minimum window")
			expect(game.tutorial.panel.size.y <= 280,"Coach card leaves the board visible")
			var marker_count: int = game.tutorial.marker_root.get_child_count()
			for refresh in range(3): game.refresh_overlays()
			expect(game.tutorial.marker_root.get_child_count() == marker_count,"Overlay refresh keeps only current targets")
			if before == 0 or step["id"] in ["battle","counter","blocked","victory"]:
				await capture(category + "_" + step["id"])
			if category == "basics" and step["id"] == "expand":
				await game.click_hex(step["details"]["source"],"unit")
				var saved: Dictionary = game.cells.duplicate(true)
				game.click_hex(step["target"])
				expect(game.busy and game.tutorial.index == before,"Movement must commit before advancing")
				game.cancel_action()
				await process_frame
				await process_frame
				expect(game.cells == saved and game.tutorial.index == before,"Cancelling movement restores the position and objective")
			if step["id"] == "victory":
				game.tutorial.observe("move",step["target"],{"source":step["details"]["source"],"kind":"attack"})
				expect(not game.tutorial.completed,"Victory requires an actual defeated opponent")
			await perform_step(game,step)
			actions += 1
			expect(game.tutorial.completed or game.tutorial.index == before + 1,"Committed action advances one objective: " + category + "/" + step["id"])
			expect(game.rules == model and game.round_number >= previous_round,"Same match evolves without chapter resets")
			previous_round = game.round_number
			if game.tutorial.index == before and not game.tutorial.completed: break
			if category == "basics" and step["id"] == "recruit":
				var saved: Dictionary = game.cells.duplicate(true)
				var saved_gold: int = game.active_kingdom()["gold"]
				game.tutorial.retry.pressed.emit()
				expect(game.cells == saved and game.active_kingdom()["gold"] == saved_gold,"Retry restores the current checkpoint without duplicating gold")
			if category == "intermediate" and step["id"] == "flank":
				var enemy: Dictionary = game.cells[Vector2i(0,1)]
				var moved: bool = enemy["moved"]
				enemy["moved"] = false
				expect(game.rules.defense(Vector2i(-1,1)) == 2 and not game.rules.can_move(Vector2i(0,1),Vector2i(-1,1)),"Tower actually blocks a ready enemy Soldier's border attack")
				enemy["moved"] = moved
			if category == "advanced" and step["id"] == "beachhead":
				expect(not game.cells[Vector2i(1,0)]["moved"],"Trailblaze grants a real second action")
			if category == "advanced" and step["id"] == "blocked":
				expect(game.cells[Vector2i(2,0)]["owner"] == 1 and game.cells[Vector2i(1,0)]["moved"],"Entrenchment absorbs the hit without faking a capture")
		expect(game.tutorial.completed and actions == Lessons.lessons(category).size(),"Whole course is playable: " + category)
		expect(game.rules.territory(1) == 0 and game.game_over and game.winner_faction == 0,"Every category ends in real opponent defeat")
		await capture(category + "_won")
		if not game.tutorial.completed:
			await app.return_to_main_menu()
			break
		if category != "advanced":
			expect(game.tutorial.next_button.visible,"Victory offers the next category")
			game.tutorial.next_button.pressed.emit()
		else:
			expect(not game.tutorial.next_button.visible,"Final category has no dead-end next button")
			game.tutorial.finish.pressed.emit()
		await process_frame
		while app.transitioning: await process_frame
	expect(app.game == null and app.menus.screen == app.menus.Screen.MAIN,"Final victory returns cleanly to the main menu")
	app.menus.show_screen(app.menus.Screen.TUTORIAL)
	app.menus.tutorial_panel.category_buttons["advanced"].pressed.emit()
	while app.transitioning: await process_frame
	expect(app.game.tutorial.category == "advanced" and app.game.tutorial.index == 0,"Experienced players can start directly with Advanced")
	await app.restart_current_level()
	expect(app.game.tutorial.category == "advanced" and app.game.tutorial.index == 0,"Restart retains the selected category")
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	gameplay.set_rules(original_rules,false)
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Tutorial checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)

func perform_step(game, step: Dictionary) -> void:
	var target: Vector2i = step["target"]
	match step["kind"]:
		"select": await game.click_hex(target,"unit")
		"recruit":
			game.choose_unit(step["details"]["tier"])
			await game.click_hex(target)
		"build":
			game.choose_building(step["details"]["building"])
			await game.click_hex(target)
		"spell":
			game.choose_spell(step["details"]["spell"])
			await game.click_hex(target)
		"move":
			await game.click_hex(step["details"]["source"],"unit")
			expect(game.valid_targets.has(target),"Objective is a legal move: " + step["id"])
			await game.click_hex(target)
		"end_turn": await game.end_turn()
