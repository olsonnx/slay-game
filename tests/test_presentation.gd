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

func click(game, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	game._unhandled_input(event)

func run() -> void:
	check_water_materials()
	await check_kingdom_edges()
	await check_departure_depth()
	var video = root.get_node("Video")
	var original_transitions: bool = video.level_transitions
	var original_video_path: String = video.settings_path
	video.settings_path = "res://artifacts/presentation_video_test.cfg"
	var gameplay = root.get_node("Gameplay")
	var original_mode: String = gameplay.rule_mode
	gameplay.set_rules("modern", false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	var capital: Vector2i = game.active_kingdom()["capital"]
	game.cells[capital]["unit"] = 2
	game.view.render_cells(game.cells)
	game.cells[capital]["moved"] = true
	game.message = ""
	game.click_hex(capital, "terrain")
	expect(game.province_view.visible and game.message == "", "Inspecting terrain under a spent unit does not announce that it has moved")
	game.click_hex(capital, "unit")
	expect(not game.province_view.visible and game.message == "This unit has already moved.", "Clicking the spent unit itself still explains its unavailable action")
	game.cells[capital]["moved"] = false
	game.cancel_action()
	await process_frame
	await process_frame
	for kind in ["recruit", "build", "spells", "province"]:
		if kind == "province":
			game.inspect_province(capital)
		else:
			game.open_shop(kind)
		var contextual = game.province_view if kind == "province" else game.shop_panel
		expect(contextual.visible and contextual.modulate.a == 0 and contextual.offset_bottom < game.economy_dock.offset_top, "Every contextual panel begins faded above the resource dock without overlapping it")
		contextual.slide.pause()
		contextual.slide.custom_step(0.10)
		expect(contextual.modulate.a > 0 and contextual.modulate.a < 1 and contextual.offset_top > contextual.rest_top and contextual.offset_bottom < game.economy_dock.offset_top, "Every contextual panel fades and slides gently without overlapping the dock")
		contextual.slide.play()
		await create_timer(0.20).timeout
		expect(is_equal_approx(contextual.modulate.a, 1) and is_equal_approx(contextual.offset_top, contextual.rest_top), "Every contextual panel arrives at its intended position")
		game.cancel_action()
	for angle in [Vector2(0.18, 0.92), Vector2(1.3, 0.76), Vector2(0, 1.569)]:
		game.view.yaw = angle.x
		game.view.pitch = angle.y
		game.view.update_camera()
		game.cancel_action()
		game.inspect_province(capital)
		var actor: Node3D = game.view.unit_actors[capital]
		var sprite: Sprite3D
		for node in actor.get_children():
			if node is Sprite3D:
				sprite = node
		var point: Vector2 = game.view.camera.unproject_position(sprite.global_position)
		var hit: Dictionary = game.view.pick_at_screen(point)
		expect(hit["coord"] == capital and hit["kind"] == "unit", "Picking distinguishes a soldier on a castle from the province beneath it")
		click(game, point)
		expect(game.selected == capital and not game.province_view.visible and game.inspected_hex == game.NONE, "Clicking a unit selects it and closes province details")
		var terrain_point := Vector2.ZERO
		for index in range(12):
			var direction := Vector2.from_angle(index * TAU / 12) * 0.76
			var location: Vector3 = game.view.coord_position(capital) + Vector3(direction.x, 0, direction.y)
			var candidate: Vector2 = game.view.camera.unproject_position(location)
			var terrain_hit: Dictionary = game.view.pick_at_screen(candidate)
			if terrain_hit["coord"] == capital and terrain_hit["kind"] == "terrain":
				terrain_point = candidate
				break
		expect(terrain_point != Vector2.ZERO, "Exposed terrain on an occupied province remains separately pickable")
		click(game, terrain_point)
		expect(game.province_view.visible and game.selected == game.NONE, "Clicking exposed ground opens province details without selecting the unit")
	game.open_shop("spells")
	expect(not game.province_view.visible and game.shop_panel.visible, "Province and purchase panels never stack")
	game.cancel_action()
	game.click_hex(capital, "unit")
	game.choose_unit(3)
	game.active_kingdom()["gold"] = 100
	game.refresh_ui()
	game.click_hex(capital, "unit")
	expect(game.cells[capital]["unit"] == 3 and not game.province_view.visible, "Recruitment upgrades do not open a province window")
	expect(game.economy_dock.size.x == 418 and game.economy_dock.size.y == 120, "Modern resources and actions fit in a compact dock")
	expect(game.mana_label.position.y == game.money_label.position.y and game.mana_control.position.y == game.gold_control.position.y, "Gold and mana values share a row")
	expect(game.recruit_button.position.y == game.build_button.position.y and game.build_button.position.y == game.spell_button.position.y, "Recruit, Build and Spells share their own action row")
	expect(is_equal_approx(game.province_view.size.y, game.province_view.panel_height) and game.province_view.offset_bottom < game.economy_dock.offset_top, "Province details fit their content above the resource dock")
	game.shutdown()
	game.queue_free()
	await process_frame
	video.set_preference(&"level_transitions", true, false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await app.start_new_game(42)
	game = app.game
	game.set_process(false)
	var before_cells: Dictionary = game.cells.duplicate(true)
	var before_kingdoms: Dictionary = game.rules.kingdoms.duplicate(true)
	expect(game.view.level_transitioning and game.end_button.disabled and not game.view.controls_enabled, "Loading a level starts a transition and temporarily locks gameplay and camera navigation")
	var height: float = root.get_visible_rect().size.y
	for tile in game.view.tile_nodes.values():
		expect(game.view.camera.unproject_position(tile.global_position).y < 0, "All entering tiles start above the screen")
	var tile: Node3D = game.view.tile_nodes.values()[0]
	var initial: Vector3 = tile.position
	game.choose_unit(1)
	game.end_turn()
	expect(game.action_mode == "" and not game.busy and game.round_number == 1, "Gameplay commands cannot execute while tiles arrive")
	while tile.position == initial and game.view.level_transitioning:
		await process_frame
	expect(tile.position != initial and tile.position != game.view.coord_position(tile.get_meta("hex")), "Entrance has visible intermediate positions")
	app.pause_game()
	var paused_position: Vector3 = tile.position
	await create_timer(0.18, true).timeout
	expect(tile.position == paused_position and game.view.level_transitioning, "Pause freezes the island entrance")
	app.continue_game()
	while game.view.level_transitioning:
		await process_frame
	for settled in game.view.tile_nodes.values():
		expect(settled.position.is_equal_approx(game.view.coord_position(settled.get_meta("hex"))), "Entering tiles settle at their exact map positions")
	expect(not game.end_button.disabled and game.view.controls_enabled and game.view.overlay_root.visible, "Entrance unlocks gameplay and restores overlays")
	expect(game.cells == before_cells and game.rules.kingdoms == before_kingdoms, "Transition does not mutate ownership, resources or units")
	for cell in game.cells.values():
		if cell["owner"] > 0:
			cell["owner"] = 0
	game.rules.rebuild_kingdoms()
	game.view.render_cells(game.cells)
	game.check_winner()
	expect(game.game_over and paused and app.menus.defeat_panel.visible, "Completing a level opens results before departure")
	expect(not game.view.level_transitioning and not game.completion_started, "Victory leaves the island in place behind results")
	app.continue_game()
	expect(paused and app.menus.defeat_panel.visible, "Victory cannot resume a completed match")
	app.menus.open_options(app.menus.Screen.DEFEAT)
	app.menus.options_view.level_transition_toggle.toggled.emit(false)
	expect(not game.view.level_transitioning and paused, "Changing transitions on results preserves the completed board")
	video.settings_path = "res://artifacts/presentation_video_test.cfg"
	expect(video.flush_settings() == OK, "Transition preference saves")
	video.set_preference(&"level_transitions", true, false)
	expect(video.load_settings(video.settings_path) == OK and not video.level_transitions, "Transition preference reloads")
	app.menus.options_view.refresh()
	expect(not app.menus.options_view.level_transition_toggle.button_pressed, "Video checkbox reflects the saved preference")
	app.return_to_main_menu()
	while app.retiring_games > 0:
		await process_frame
	await app.start_new_game(10)
	game = app.game
	expect(not game.view.level_transitioning and not game.end_button.disabled, "Disabled transitions start levels immediately")
	video.set_preference(&"level_transitions", true, false)
	app.restart_current_level()
	while app.transitioning:
		await process_frame
	expect(app.game.view.level_transitioning and app.game.rules.level_seed == 10, "Restart replays entrance with the same seed")
	app.return_to_main_menu()
	while app.retiring_games > 0:
		await process_frame
	await process_frame
	expect(app.game == null and not paused, "Leaving during entrance safely cancels its tweens")
	await check_defeat_and_restart(app)
	video.set_preference(&"level_transitions", original_transitions, false)
	video.settings_path = original_video_path
	gameplay.set_rules(original_mode, false)
	root.get_node("Sound").stop_all()
	await create_timer(1.2, true).timeout
	print("Presentation checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func check_departure_depth() -> void:
	var video = root.get_node("Video")
	var original_transitions: bool = video.level_transitions
	var original_background: String = video.background
	video.set_preference(&"level_transitions", true, false)
	var rules = preload("res://src/game/kingdom_rules.gd").new()
	for q in range(-2, 3):
		for r in range(-2, 3): rules.cells[Vector2i(q, r)] = rules.make_cell(0)
	rules.cells[Vector2i.ZERO]["capital"] = 0
	rules.cells[Vector2i(1, 0)]["building"] = "tower"
	rules.rebuild_kingdoms()
	var before: Dictionary = rules.cells.duplicate(true)
	var view = load("res://src/rendering/board_view.gd").new()
	root.add_child(view)
	view.set_process(false)
	view.render_cells(rules.cells)
	for background in ["water", "sky"]:
		video.set_preference(&"background", background, false)
		for pitch in [0.44, 0.92, 1.37, deg_to_rad(89.9)]:
			for yaw in [0.0, 1.7, 3.8]:
				view.pitch = pitch
				view.yaw = yaw
				view.update_camera()
				var normal_far: float = view.camera.far
				view.start_level_transition(false)
				view.island_transition.tween.pause()
				expect(view.water.material_override.get_shader_parameter("backdrop_depth") == true, "Departure water stays behind falling gameplay tiles")
				for tile in view.tile_nodes.values():
					var home: Vector3 = view.coord_position(tile.get_meta("hex"))
					var depth: float = -view.camera.to_local(tile.get_parent().global_transform * home).z
					var destination: Vector3 = view.island_transition.destinations[tile]
					var first_tile: Node3D = view.island_transition.destinations.keys()[0]
					var common_offset: Vector3 = view.island_transition.destinations[first_tile] - view.coord_position(first_tile.get_meta("hex"))
					expect((destination - home).is_equal_approx(common_offset), "Departing tiles share one travel distance instead of compressing together at the screen edge")
					for amount in [0.1, 0.5, 1.0]:
						view.island_transition._departing_position(amount, tile, destination)
						if pitch <= deg_to_rad(65.0):
							expect(is_equal_approx(tile.position.x, home.x) and is_equal_approx(tile.position.z, home.z) and tile.position.y < home.y, "Angled gameplay departure falls vertically without crossing a neighbour's footprint")
						else:
							expect(view.camera.unproject_position(tile.global_position).y > view.camera.unproject_position(tile.get_parent().global_transform * home).y, "Overhead departure visibly moves down the screen")
						expect(-view.camera.to_local(tile.global_position).z > depth, "A departing gameplay tile moves farther from the camera at every supported angle")
						expect(-view.camera.to_local(tile.global_position + Vector3.DOWN).z < view.camera.far, "The whole falling tile stays inside the camera depth range")
					var highest_point: Vector3 = tile.global_position + Vector3.UP * 3.0
					expect(view.camera.unproject_position(highest_point).y > root.get_visible_rect().size.y, "Tile and tall props clear the screen before departure ends without far-plane clipping")
				view.cancel_level_transition()
				expect(is_equal_approx(view.camera.far, normal_far), "Cancelling departure restores the normal camera depth range")
				expect(view.water.material_override.get_shader_parameter("backdrop_depth") == false and view.controls_enabled, "Cancelling departure restores physical water and controls")
				for tile in view.tile_nodes.values():
					expect(tile.position == view.coord_position(tile.get_meta("hex")), "Cancellation restores every tile to its map position")
	view.pitch = 0.92
	view.update_camera()
	var finished_far: float = view.camera.far
	view.start_level_transition(false)
	view.update_camera()
	expect(view.camera.far > finished_far and is_equal_approx(view.island_transition.departure_far, finished_far), "A camera refresh retains enough departure depth and remembers the normal range")
	view.island_transition.finish()
	expect(is_equal_approx(view.camera.far, finished_far), "Finished departure restores the normal camera depth range")
	expect(view.water.material_override.get_shader_parameter("backdrop_depth") == false, "Finished departure restores the physical water depth")
	view.start_level_transition(true)
	expect(view.water.material_override.get_shader_parameter("backdrop_depth") == false, "Arrival retains physical water depth")
	view.cancel_level_transition()
	expect(rules.cells == before, "Departure and cancellation never change the authoritative map")
	view.queue_free()
	await process_frame
	video.set_preference(&"background", original_background, false)
	video.set_preference(&"level_transitions", original_transitions, false)

func check_kingdom_edges() -> void:
	var video = root.get_node("Video")
	var original_visibility: float = video.internal_borders
	# Exercise joined topology at a known midpoint before endpoint checks.
	video.set_preference(&"internal_borders", 0.5, false)
	var terrain = preload("res://src/rendering/terrain_tile.gd")
	var rules = preload("res://src/game/kingdom_rules.gd").new()
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var d := Vector2i(3, 0)
	for coord in [a, b, c, d]:
		rules.cells[coord] = rules.make_cell(0 if coord in [a, b] else 1)
	rules.rebuild_kingdoms()
	var view = load("res://src/rendering/board_view.gd").new()
	root.add_child(view)
	view.set_process(false)
	view.render_cells(rules.cells)
	expect(terrain.joined_mask(rules.cells, a) == 1 and terrain.joined_mask(rules.cells, b) == 8, "Only edges within a kingdom close their earth rims")
	var tile: Node3D = view.tile_nodes[b]
	var features: Node3D = tile.get_node("Features")
	var before: Mesh = tile.get_meta("surface").mesh
	rules.cells[c]["owner"] = 0
	rules.rebuild_kingdoms()
	view.render_cells(rules.cells)
	expect(view.tile_nodes[b] == tile and tile.get_node("Features") == features, "Capture updates the neighboring surface while retaining props and tile identity")
	expect(tile.get_meta("joined_mask") == 9 and tile.get_meta("surface").mesh != before, "A captured neighbor removes the newly internal border")
	var built: int = view.tiles_built
	var joined: Mesh = tile.get_meta("surface").mesh
	view.render_cells(rules.cells)
	expect(view.tiles_built == built and tile.get_meta("surface").mesh == joined, "Unchanged borders retain cached meshes")
	rules.cells[c]["owner"] = 1
	rules.rebuild_kingdoms()
	view.render_cells(rules.cells)
	expect(tile.get_meta("surface").mesh == before, "Losing a neighboring tile restores the territory rim")
	rules.cells[c]["owner"] = -1
	rules.cells[c]["building"] = "bridge"
	rules.rebuild_kingdoms()
	view.render_cells(rules.cells)
	expect(view.tile_nodes[c].get_meta("joined_mask") == 0 and tile.get_meta("joined_mask") == 8, "Bridges keep their separate deck and the adjoining land rim")
	for mask in range(1, 64):
		var mesh: Mesh = terrain.cap_mesh(view, mask)
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index in range(3):
			expect(normals[index].dot(Vector3.UP) > 0.999, "Kingdom surfaces retain flat upward lighting")
		for vertex in vertices:
			expect(Vector2(vertex.x, vertex.z).length() <= 1.001, "Joined caps remain inside their logical hex")
		var lowest := INF
		var highest := -INF
		for vertex in vertices:
			lowest = minf(lowest, vertex.y + terrain.CAP_CENTER)
			highest = maxf(highest, vertex.y + terrain.CAP_CENTER)
		var expected_lowest: float = preload("res://src/rendering/terrain_chunks.gd").SHOULDER
		expect(is_equal_approx(lowest, expected_lowest) and is_equal_approx(highest, 0.0105), "Molded cap bevels meet the base while preserving the original top height")
	expect(terrain.cap_mesh(view, 9) == joined, "Neighbor-mask mesh cache is shared")
	var retained_tile: Node3D = view.tile_nodes[a]
	var retained_features: Node3D = retained_tile.get_node("Features")
	var state_before: Dictionary = rules.cells.duplicate(true)
	for visibility in [0.0, 0.5, 1.0]:
		video.set_preference(&"internal_borders", visibility, false)
		var mesh: Mesh = retained_tile.get_meta("surface").mesh
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var right := -INF
		var left := INF
		for vertex in vertices:
			right = maxf(right, vertex.x)
			left = minf(left, vertex.x)
		expect(is_equal_approx(right, sqrt(3.0) * 0.5 * lerpf(1.0, 0.968, visibility)), "Shared border width follows zero, half and full visibility")
		expect(is_equal_approx(left, -sqrt(3.0) * 0.5 * 0.968), "Exterior border width stays unchanged at every visibility")
		expect(view.tile_nodes[a] == retained_tile and retained_tile.get_node("Features") == retained_features and rules.cells == state_before, "Live slider updates keep tiles, props and game state intact")
	for percent in range(101):
		video.set_preference(&"internal_borders", percent / 100.0, false)
	expect(view.mesh_cache.keys().filter(func(key): return str(key).begins_with("kingdom_cap:")).size() <= 63, "Dragging through the slider range cannot accumulate mesh variants")
	video.set_preference(&"internal_borders", original_visibility, false)
	view.queue_free()
	await process_frame

func lose_level(game) -> void:
	for cell in game.cells.values():
		if cell["owner"] == 0:
			cell["owner"] = 1
			if cell["capital"] == 0:
				cell["capital"] = 1
	game.rules.rebuild_kingdoms()
	game.view.render_cells(game.cells)
	game.check_winner()

func check_defeat_and_restart(app) -> void:
	var video = root.get_node("Video")
	video.set_preference(&"level_transitions", true, false)
	await app.start_new_game(42)
	var game = app.game
	while game.view.level_transitioning:
		await process_frame
	var starting_cells: Dictionary = game.cells.duplicate(true)
	var starting_kingdoms: Dictionary = game.rules.kingdoms.duplicate(true)
	var tile: Node3D = game.view.tile_nodes.values()[0]
	game.busy = true
	lose_level(game)
	expect(game.game_over and not game.defeat_notified and not paused, "Defeat waits for opponent playback to finish before opening its popup")
	game.busy = false
	game.begin_completion_exit()
	expect(paused and app.menus.screen == app.menus.Screen.DEFEAT and app.menus.defeat_panel.visible, "Defeat opens a modal Restart/Main Menu popup")
	expect(not game.completion_started and not game.view.level_transitioning, "Losing does not automatically drop the island")
	# The fixture may replace tiles when ownership changes; inspect the new node.
	tile = game.view.tile_nodes.values()[0]
	var home: Vector3 = tile.position
	await create_timer(0.25, true).timeout
	expect(tile.position == home and game.view.island_transition.entering, "Defeat island stays in place while awaiting the player's choice")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app.menus._unhandled_input(escape)
	app.continue_game()
	expect(paused and app.menus.screen == app.menus.Screen.DEFEAT, "Escape and Continue cannot dismiss defeat without a destination")
	app.menus.defeat_restart_button.pressed.emit()
	expect(app.transitioning and not paused and app.menus.screen == app.menus.Screen.HIDDEN and app.game == game, "Defeat Restart dismisses the popup and starts departure on the existing island")
	expect(game.view.level_transitioning and not game.view.island_transition.entering, "Defeat Restart plays tile exit before replacing the session")
	while tile.position == home and game.view.level_transitioning:
		await process_frame
	expect(app.game == game and tile.position != home, "Old island remains visible during its exit rather than disappearing immediately")
	while app.transitioning:
		await process_frame
	game = app.game
	expect(game.rules.level_seed == 42 and game.view.level_transitioning and game.view.island_transition.entering, "Replacement level begins entrance only after the old island departs")
	while game.view.level_transitioning:
		await process_frame
	expect(game.cells == starting_cells and game.rules.kingdoms == starting_kingdoms and game.round_number == 1, "Defeat Restart restores the same level, starting resources and turn")
	app.pause_game()
	app.menus.confirm_restart()
	tile = game.view.tile_nodes.values()[0]
	home = tile.position
	await create_timer(0.12, true).timeout
	expect(paused and not game.view.level_transitioning and tile.position == home, "Normal restart confirmation leaves the island still")
	var exit_finished := [false]
	game.view.level_transition_finished.connect(func():
		if not game.view.island_transition.entering:
			exit_finished[0] = true)
	app.menus.confirm_action_button.pressed.emit()
	expect(app.transitioning and app.game == game and game.view.level_transitioning and not game.view.island_transition.entering, "Confirmed normal Restart starts the same departure sequence")
	app.restart_current_level()
	while app.transitioning:
		await process_frame
	expect(exit_finished[0] and app.game.rules.level_seed == 42 and app.game.view.island_transition.entering, "Restart serializes exit before entry and ignores repeated requests")
	game = app.game
	while game.view.level_transitioning:
		await process_frame
	lose_level(game)
	expect(app.menus.screen == app.menus.Screen.DEFEAT and paused, "A second defeat opens the popup again in a fresh session")
	app.menus.defeat_menu_button.pressed.emit()
	expect(app.transitioning and app.game == game and game.view.level_transitioning and app.menus.screen == app.menus.Screen.HIDDEN, "Defeat Main Menu starts exit before showing the main menu")
	while app.transitioning:
		await process_frame
	expect(app.game == null and app.menus.screen == app.menus.Screen.MAIN and not paused, "Main menu appears after the defeated island exits and is disposed")
	video.set_preference(&"level_transitions", false, false)
	await app.start_new_game(42)
	game = app.game
	lose_level(game)
	expect(paused and app.menus.screen == app.menus.Screen.DEFEAT and not game.view.level_transitioning, "Defeat popup still works when tile animations are disabled")
	app.menus.defeat_restart_button.pressed.emit()
	while app.transitioning:
		await process_frame
	expect(not paused and app.game.rules.level_seed == 42 and not app.game.view.level_transitioning, "Disabled animations restart immediately after the defeat choice")
	app.return_to_main_menu()
	while app.transitioning:
		await process_frame

func check_water_materials() -> void:
	var factory = load("res://src/rendering/water_surface.gd")
	var board: ShaderMaterial = factory.material(false, true)
	var menu: ShaderMaterial = factory.material(true, true)
	expect(board != menu and board.shader == menu.shader, "Water shares shader code but keeps surface state independent")
	expect(board.get_shader_parameter("backdrop_depth") == false and menu.get_shader_parameter("backdrop_depth") == true, "Board water uses scene depth while menu water stays behind falling tiles")
	board.set_shader_parameter("backdrop_depth", true)
	menu.set_shader_parameter("backdrop_depth", false)
	expect(board.get_shader_parameter("backdrop_depth") == true and factory.material().get_shader_parameter("backdrop_depth") == false, "Transition depth changes do not leak into other surfaces or future games")
	for parameter in ["noise1", "noise2", "normalmap"]:
		var texture: NoiseTexture2D = board.get_shader_parameter(parameter)
		expect(texture != null and texture == menu.get_shader_parameter(parameter) and texture.seamless and texture.noise != null, "Water supplies shared seamless procedural texture: " + parameter)
	expect(board.get_shader_parameter("normalmap").as_normal_map, "Wave normals use a generated normal map")

	expect(factory.material().shader == factory.OriginalShader, "Original water is the default")
	factory.set_style(board, false)
	expect(board.shader == factory.OriginalShader and board.get_shader_parameter("backdrop_depth") == true, "Switching to original water preserves transition depth")
	factory.set_style(board, true)
	expect(board.shader == factory.ShaderSource and board.get_shader_parameter("backdrop_depth") == true, "Switching back restores stylized textures without resetting transition depth")
