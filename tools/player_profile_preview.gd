extends SceneTree
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/%s.png" % name)
func run() -> void:
	root.size = Vector2i(1280, 820)
	root.get_node("Sound").set_muted(true, false)
	var profile = root.get_node("PlayerProfile")
	profile.settings_path = "res://artifacts/profile-preview.cfg"
	profile.data.clear()
	profile.tutorial_prompt_seen = false
	for key in profile.statistics: profile.statistics[key] = 0
	profile.recorded_matches.clear()
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await app.startup_finished
	var editor = app.menus.profile_panel
	editor.name_input.text = "Kingdom of the Silver Oak"
	editor.motto_input.text = "Deep roots. Open horizons."
	editor.country_color.color = Color("83b7a8")
	editor.field_color.color = Color("263e48")
	editor.accent_color.color = Color("c4ad72")
	editor.symbol_color.color = Color("f0ead5")
	editor.pattern.select(2)
	editor.symbol.select(4)
	editor.symbol_scale.value = 0.55
	editor.refresh_preview()
	await capture("profile-create")
	editor.commit()
	await capture("profile-tutorial-prompt")
	app.menus.finish_welcome(false)
	await capture("profile-main-menu")
	for index in range(18):
		profile.record_match("preview-%d" % index, "victory" if index % 3 != 0 else "defeat", 600 + index * 20, 12 + index)
	app.menus.open_profile(false)
	await capture("profile-record")
	root.size = Vector2i(960, 620)
	await capture("profile-record-small")
	editor.edit_button.pressed.emit()
	await capture("profile-edit-small")
	editor.country_color.get_child(0).pressed.emit()
	await capture("profile-color-wheel")
	editor.country_color.popup.hide()
	editor.edit_tabs.current_tab = 1
	editor.placement.select(5)
	editor.refresh_preview()
	await capture("profile-flag-edit-small")
	editor.back()
	editor.delete_button.pressed.emit()
	await capture("profile-delete-confirmation")
	editor.back()
	app.menus.show_screen(app.menus.Screen.SETUP)
	app.menus.player_kingdom_choice.own_card.pressed.emit()
	app.menus.player_kingdom_choice.summary.pressed.emit()
	await capture("quickplay-country-cards")
	app.menus.player_kingdom_choice.popup.hide()
	app.menus.open_profile(false)
	var symbols = preload("res://src/settings/player_profile.gd").SYMBOLS
	var patterns = preload("res://src/settings/player_profile.gd").PATTERNS
	for index in range(symbols.size()):
		var design: Dictionary = editor.preview.design.duplicate(true)
		design.symbol = symbols[index]
		design.pattern = patterns[index % patterns.size()]
		editor.preview.set_design(design)
		await RenderingServer.frame_post_draw
	await app.start_new_game(51, "medium", "hard", 6)
	var game = app.game
	game.match_clock.pause()
	game.match_clock.accumulated_usec = 1200000000
	game.round_number = 25
	for cell in game.cells.values():
		if cell.owner != game.player_faction:
			cell.owner = -1
			cell.capital = -1
	game.rules.rebuild_kingdoms()
	game.check_winner()
	await create_timer(1.7, true).timeout
	await capture("profile-xp-results-small")
	paused = false
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	quit()
