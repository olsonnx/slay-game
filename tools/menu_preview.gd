extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var border_preview := -1
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--borders="):
			border_preview = clampi(int(argument.trim_prefix("--borders=")), 0, 100)
			root.get_node("Video").set_preference(&"internal_borders", border_preview / 100.0, false)
	for background in ["water", "sky"]:
		if "--" + background in OS.get_cmdline_user_args():
			root.get_node("Video").set_preference(&"background", background, false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	app.menus.set_process_unhandled_input(false)
	var args := OS.get_cmdline_user_args()
	if "--small-window" in args:
		root.size = Vector2i(960, 620)
	var name := "menu_main"
	if "--setup" in args:
		app.menus.show_screen(app.menus.Screen.SETUP)
		name = "menu_new_game"
	if "--pause" in args or "--options" in args or "--quit" in args or "--restart" in args or "--defeat" in args:
		await app.start_new_game()
		app.game.rules.generate(42)
		app.game.view.render_cells(app.game.cells)
		app.game.refresh_ui()
		app.pause_game()
		name = "menu_pause"
	if "--options" in args:
		app.menus.open_options(app.menus.Screen.PAUSE)
		name = "menu_options_audio"
		if "--video" in args:
			app.menus.options_view.get_child(0).current_tab = 1
			name = "menu_options_video"
		if "--gameplay" in args:
			app.menus.options_view.get_child(0).current_tab = 2
			name = "menu_options_gameplay"
		if "--controls" in args:
			app.menus.options_view.get_child(0).current_tab = 3
			name = "menu_options_controls"
	if "--quit" in args:
		app.menus.show_screen(app.menus.Screen.QUIT)
		name = "menu_quit"
	if "--restart" in args:
		app.menus.confirm_restart()
		name = "menu_restart_confirm"
	if "--defeat" in args:
		for cell in app.game.cells.values():
			if cell["owner"] == 0:
				cell["owner"] = 1
				if cell["capital"] == 0:
					cell["capital"] = 1
		app.game.rules.rebuild_kingdoms()
		app.game.view.render_cells(app.game.cells)
		app.game.check_winner()
		name = "menu_defeat"
	if "--evolving" in args:
		for tick in range(135):
			app.menus.menu_background.map.advance(1.0 / 30.0)
		app.menus.menu_background.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		name += "_evolving"
	if "--small-window" in args:
		name += "_small"
	for background in ["water", "sky"]:
		if "--" + background in args:
			name += "_" + background
	if border_preview >= 0:
		name += "_borders_%d" % border_preview
	# Let frame-rate readouts settle beyond loading/shader warmup.
	await create_timer(1.5).timeout
	await process_frame
	await process_frame
	if "--sizes-dropdown" in args:
		app.menus.size_choice.select(app.menus.size_choice.item_count - 1)
		app.menus.size_choice.item_selected.emit(app.menus.size_choice.selected)
		app.menus.size_choice.show_popup()
		name += "_sizes"
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/%s.png" % name)
	paused = false
	root.get_node("Sound").stop_all()
	quit()
