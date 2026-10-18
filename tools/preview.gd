extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	root.get_node("Gameplay").set_clear_indicators(not "--legacy-indicators" in OS.get_cmdline_user_args(), false)
	if "--small-window" in OS.get_cmdline_user_args():
		root.size = Vector2i(960, 620)
	for background in ["water", "sky"]:
		if "--" + background in OS.get_cmdline_user_args():
			root.get_node("Video").set_preference(&"background", background, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			game.initial_map_size = argument.trim_prefix("--size=")
	if "--modern" in OS.get_cmdline_user_args():
		game.initial_rule_mode = "modern"
	root.add_child(game)
	game.rules.generate(42, game.initial_map_size)
	for kingdom in game.rules.kingdoms.values():
		if kingdom["owner"] == 0:
			game.active_hex = kingdom["capital"]
	if "--barrier-showcase" in OS.get_cmdline_user_args():
		for coord in game.active_kingdom()["hexes"]:
			var cell: Dictionary = game.cells[coord]
			if cell["capital"] < 0 and cell["unit"] == 0:
				cell["tree"] = false
				cell["grave"] = false
				cell["barrier_by"] = 0
				game.view.focus = game.view.coord_position(coord)
				game.view.zoom = 7.0
				game.view.update_camera()
				break
	if "--bridge-showcase" in OS.get_cmdline_user_args():
		game.active_kingdom()["gold"] = 100
		for coord in game.active_kingdom()["hexes"]:
			game.cells[coord]["mana_source"] = true
		game.rules.set_mana(0, 6)
		var site := game.NONE as Vector2i
		var best_distance := 1000
		for coord in game.rules.bridge_targets(0, game.active_capital()):
			var distance: int = game.rules.distance(coord, Vector2i.ZERO)
			if distance < best_distance:
				site = coord
				best_distance = distance
		if site != game.NONE:
			game.rules.build_structure(site, 0, "bridge", game.active_capital())
			game.cells[site]["unit"] = 2
			game.cells[site]["unit_owner"] = 0
			game.cells[site]["unit_home"] = game.active_capital()
			game.rules.entrench(site, 0)
	if "--showcase" in OS.get_cmdline_user_args():
		var kingdom: Dictionary = game.active_kingdom()
		kingdom["gold"] = 100
		var kinds := ["tower", "house", "grave", "tree"]
		for coord in kingdom["hexes"]:
			if game.cells[coord]["unit"] > 0 or game.cells[coord]["capital"] >= 0:
				continue
			if kinds.is_empty():
				break
			var kind: String = kinds.pop_front()
			if kind in ["tower", "house"]:
				game.rules.build_structure(coord, 0, kind)
			else:
				game.cells[coord][kind] = true
		game.message = "Towers defend. Houses earn gold. Move a unit onto a tree or grave to clear it."
	game.refresh_ui()
	game.view.render_cells(game.cells)
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.view.set_process(false)
	game.view.controls_enabled = false
	if "--province" in OS.get_cmdline_user_args():
		game.inspect_province(game.active_hex)
		await create_timer(0.30).timeout
	if "--spells" in OS.get_cmdline_user_args():
		game.open_shop("spells")
	if "--top-down" in OS.get_cmdline_user_args():
		game.toggle_view()
	if "--shop" in OS.get_cmdline_user_args():
		game.open_shop("recruit")
	if "--gold-spend" in OS.get_cmdline_user_args():
		game.active_kingdom()["gold"] = 100
		game.reset_gold_feedback()
		game.refresh_ui()
		game.choose_unit(1)
		for coord in game.active_kingdom()["hexes"]:
			if game.cells[coord]["unit"] == 0 and game.cells[coord]["capital"] < 0:
				game.click_hex(coord)
				break
	if "--build" in OS.get_cmdline_user_args():
		game.open_shop("build")
	if "--stats" in OS.get_cmdline_user_args():
		game.toggle_stats()
	if "--sound" in OS.get_cmdline_user_args():
		var menus = load("res://src/ui/session_menus.gd").new()
		root.add_child(menus)
		menus.open_options(menus.Screen.MAIN)
	if "--tooltip" in OS.get_cmdline_user_args():
		for coord in game.cells:
			if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] > 0:
				game.hovered = coord
				break
		game.show_world_tip()
		game.world_tip.position = Vector2(620, 98)
	if "--intent-house" in OS.get_cmdline_user_args():
		game.active_kingdom()["gold"] = 100
		game.choose_building("house")
		for coord in game.active_kingdom()["hexes"]:
			if game.rules.can_build(coord, 0, "house"):
				game.hovered = coord
				break
		game.refresh_ui()
	if "--intent-upgrade" in OS.get_cmdline_user_args():
		game.active_kingdom()["gold"] = 100
		game.choose_unit(3)
		for coord in game.active_kingdom()["hexes"]:
			if game.cells[coord]["unit"] > 0:
				game.hovered = coord
				break
		game.refresh_ui()
	if "--intent-move" in OS.get_cmdline_user_args() or "--movement-range" in OS.get_cmdline_user_args():
		for coord in game.active_kingdom()["hexes"]:
			if game.cells[coord]["unit"] > 0:
				game.click_hex(coord)
				break
		if "--intent-move" in OS.get_cmdline_user_args():
			var longest := 0
			for coord in game.valid_targets:
				var route: Array = game.rules.movement_path(game.selected, coord, game.valid_targets)
				if game.cells[coord]["owner"] == -1 and route.size() > longest:
					game.hovered = coord
					longest = route.size()
		game.refresh_ui()
		if "--movement-focus" in OS.get_cmdline_user_args():
			game.view.focus = game.view.coord_position(game.selected)
			game.view.zoom = 11.0
			game.view.update_camera()
		if "--intent-invalid" in OS.get_cmdline_user_args():
			for coord in game.cells:
				if game.cells[coord].get("mountain", false):
					game.hovered = coord
					break
			game.refresh_ui()
		if "--intent-merge" in OS.get_cmdline_user_args():
			for coord in game.valid_targets:
				if game.cells[coord]["owner"] == 0:
					game.cells[coord]["unit"] = 1
					game.cells[coord]["moved"] = false
					game.hovered = coord
					break
			game.view.render_cells(game.cells)
			game.refresh_ui()
	if "--transition-in" in OS.get_cmdline_user_args():
		game.view.start_level_transition(true)
		await create_timer(0.28).timeout
	if "--transition-out" in OS.get_cmdline_user_args():
		game.view.start_level_transition(false)
		await create_timer(0.35).timeout
	if "--unit-hover" in OS.get_cmdline_user_args():
		for coord in game.cells:
			if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] > 0:
				game.hovered = coord
				game.refresh_overlays()
				game.view.set_unit_hover(coord)
				break
		await create_timer(0.16).timeout
	if game.shop_panel.visible:
		await create_timer(0.30).timeout
	if "--turn-busy" in OS.get_cmdline_user_args():
		game.busy = true
		game.active_faction = 1
		game.refresh_ui()
		if "--fast-turn" in OS.get_cmdline_user_args():
			game.playback_speed.begin_turn_press()
		await create_timer(0.12).timeout
	if "--view-hold" in OS.get_cmdline_user_args():
		game.begin_view_press()
		game.advance_view_press(0.33)
	if "--heatmap" in OS.get_cmdline_user_args():
		game.toggle_value_heatmap()
	await process_frame
	await process_frame
	if "--horizon" in OS.get_cmdline_user_args():
		game.view.zoom = game.view.max_zoom
		game.view.pitch = 0.44
		game.view.focus = Vector3(game.view.navigation_limits.x, 0, game.view.navigation_limits.y)
		game.view.update_camera()
		await process_frame
	if "--close" in OS.get_cmdline_user_args():
		game.view.zoom = 8.0
		game.view.update_camera()
		await process_frame
	await RenderingServer.frame_post_draw
	var name := "preview_features" if "--showcase" in OS.get_cmdline_user_args() else "preview"
	if "--legacy-indicators" in OS.get_cmdline_user_args():
		name += "_legacy"
	if "--movement-range" in OS.get_cmdline_user_args():
		name += "_range"
	if "--movement-focus" in OS.get_cmdline_user_args():
		name += "_focused"
	if "--intent-invalid" in OS.get_cmdline_user_args():
		name += "_invalid"
	if "--intent-merge" in OS.get_cmdline_user_args():
		name += "_merge"
	if "--heatmap" in OS.get_cmdline_user_args():
		name += "_heatmap"
	if "--small-window" in OS.get_cmdline_user_args():
		name += "_small"
	if "--fast-turn" in OS.get_cmdline_user_args():
		name += "_fast_turn"
	if "--horizon" in OS.get_cmdline_user_args():
		name += "_horizon"
	if "--close" in OS.get_cmdline_user_args():
		name += "_close"
	for background in ["water", "sky"]:
		if "--" + background in OS.get_cmdline_user_args():
			name += "_" + background
	if "--modern" in OS.get_cmdline_user_args():
		name += "_modern"
	if game.rules.map_size != "small":
		name += "_" + game.rules.map_size
	if "--turn-busy" in OS.get_cmdline_user_args():
		name += "_turn_busy"
	if "--view-hold" in OS.get_cmdline_user_args():
		name += "_view_hold"
	if "--unit-hover" in OS.get_cmdline_user_args():
		name += "_unit_hover"
	if "--province" in OS.get_cmdline_user_args():
		name += "_province"
	if "--spells" in OS.get_cmdline_user_args():
		name += "_spells"
	if "--bridge-showcase" in OS.get_cmdline_user_args():
		name += "_bridges"
	if "--barrier-showcase" in OS.get_cmdline_user_args():
		name += "_barrier"
	if "--transition-in" in OS.get_cmdline_user_args():
		name += "_arriving"
	if "--transition-out" in OS.get_cmdline_user_args():
		name += "_departing"
	if "--top-down" in OS.get_cmdline_user_args():
		name += "_top"
	if "--shop" in OS.get_cmdline_user_args():
		name += "_shop"
	if "--gold-spend" in OS.get_cmdline_user_args():
		name += "_gold_spend"
	if "--stats" in OS.get_cmdline_user_args():
		name += "_stats"
	if "--sound" in OS.get_cmdline_user_args():
		name += "_sound"
	if "--build" in OS.get_cmdline_user_args():
		name += "_build"
	if "--tooltip" in OS.get_cmdline_user_args():
		name += "_tooltip"
	if "--intent-house" in OS.get_cmdline_user_args():
		name += "_intent_house"
	if "--intent-upgrade" in OS.get_cmdline_user_args():
		name += "_intent_upgrade"
	if "--intent-move" in OS.get_cmdline_user_args():
		name += "_intent_move"
	root.get_texture().get_image().save_png("res://artifacts/%s.png" % name)
	game.view.cancel_level_transition()
	root.get_node("Sound").stop_all()
	quit()
