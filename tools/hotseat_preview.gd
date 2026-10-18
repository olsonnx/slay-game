extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.size = Vector2i(960, 620)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	app.menus.show_screen(app.menus.Screen.MAIN)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/multiplayer_main.png")
	var panel = app.menus.multiplayer_panel
	panel.count_choice.select(4)
	panel.refresh_rows()
	panel.rows[0]["name"].text = "Olek"
	panel.rows[0]["color"].select(4)
	panel.select_color(0,4)
	panel.rows[1]["name"].text = "Alex"
	panel.refresh_summary()
	app.menus.show_screen(app.menus.Screen.MULTIPLAYER)
	panel.show_page("players")
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/multiplayer_setup.png")
	panel.show_page("map")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/multiplayer_map_tab.png")
	panel.toggle_advanced()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/multiplayer_advanced.png")
	panel.toggle_advanced()
	panel.show_page("players")
	panel.player_tools.popup_centered(Vector2i(352,208))
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/multiplayer_player_options.png")
	panel.player_tools.hide()
	if "--editor-map" in OS.get_cmdline_user_args():
		var document = preload("res://src/editor/level_document.gd").new()
		document.generate("small","modern")
		document.title = "Coastal watch"
		document.starting_gold = 37
		var file := FileAccess.open("res://artifacts/multiplayer_preview_map.json",FileAccess.WRITE)
		file.store_string(JSON.stringify(document.state()))
		file.close()
		panel.load_editor_map(ProjectSettings.globalize_path("res://artifacts/multiplayer_preview_map.json"))
		panel.show_page("map")
		await create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/multiplayer_editor_setup.png")
	await app.start_multiplayer(panel.config())
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/multiplayer_board.png")
	root.get_node("Sound").stop_all()
	quit()
