extends SceneTree
const Store = preload("res://src/settings/player_profile.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var profile = root.get_node("PlayerProfile")
	profile.settings_path = "res://artifacts/test-player-profile.cfg"
	profile.data.clear()
	profile.tutorial_prompt_seen = false
	for key in profile.statistics: profile.statistics[key] = 0
	profile.recorded_matches.clear()
	for suffix in ["", ".tmp", ".bak"]:
		if FileAccess.file_exists(profile.settings_path + suffix): DirAccess.remove_absolute(profile.settings_path + suffix)
	var identity := Store.default_identity()
	expect(profile.save_identity(identity) == ERR_INVALID_PARAMETER and not profile.exists(), "Empty kingdom names cannot create a profile")
	var video = root.get_node("Video")
	var preferences = root.get_node("Gameplay")
	var original_preferences_path: String = preferences.settings_path
	preferences.settings_path = "res://artifacts/test-profile-preferences.cfg"
	preferences.set_quick_play_country(-2, false)
	video.set_preference(&"level_transitions", false, false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await app.startup_finished
	expect(app.menus.screen == app.menus.Screen.PROFILE and app.menus.profile_panel.required, "First launch asks for the one local kingdom before gameplay")
	var panel = app.menus.profile_panel
	var shared_library = preload("res://src/rendering/board_assets.gd").shared_unit_sprites
	var shared_counts := [shared_library.sheets.size(), shared_library.frames.size(), preload("res://src/rendering/board_assets.gd").hover_outline_cache.size()]
	var bounded_preview := true
	for index in range(100):
		panel.game_preview.set_color(Color.from_hsv(index / 100.0, 0.7, 0.8))
		await process_frame
		bounded_preview = bounded_preview and panel.game_preview.board.unit_sprites.sheets.size() <= 3 and panel.game_preview.board.unit_sprites.frames.size() <= 16 and panel.game_preview.board.outline_cache.size() <= 16 and panel.game_preview.board.unit_batches.sprite_materials.size() <= 4
	expect(shared_counts == [shared_library.sheets.size(), shared_library.frames.size(), preload("res://src/rendering/board_assets.gd").hover_outline_cache.size()], "Picker previews never add transient colors to warmed gameplay caches")
	expect(bounded_preview, "Continued color editing keeps rendered sprite and material caches bounded")
	expect(panel.save_button.disabled, "Profile creation requires a name")
	panel.name_input.text = "Silver Oak"
	panel.name_input.text_changed.emit(panel.name_input.text)
	panel.motto_input.text = "Stand together"
	panel.country_color.color = Color("778ac7")
	panel.pattern.select(Store.PATTERNS.find("diagonal"))
	panel.symbol.select(Store.SYMBOLS.find("tree"))
	panel.refresh_preview()
	expect(panel.preview.design.symbol == "tree" and panel.preview.design.pattern == "diagonal", "Flag preview responds to editable shapes and symbols")
	panel.commit()
	expect(profile.exists() and profile.data.name == "Silver Oak" and profile.data.color == "778ac7", "Profile creation persists kingdom identity")
	expect(app.menus.screen == app.menus.Screen.WELCOME, "Creating a kingdom presents the strongly recommended tutorial")
	var original_id: String = profile.data.id
	app.menus.finish_welcome(false)
	expect(profile.tutorial_prompt_seen and app.menus.screen == app.menus.Screen.MAIN, "Tutorial can be deferred and the choice is remembered")
	expect(app.menus.campaign_button.disabled and app.menus.profile_button.visible, "Main menu shows a disabled Campaign and the profile badge")
	app.menus.show_screen(app.menus.Screen.SETUP)
	app.menus.player_kingdom_choice.own_card.pressed.emit()
	expect(preferences.quick_play_use_profile and app.menus.player_kingdom_choice.get_selected_metadata() == -2, "Country cards can explicitly select the player's saved country")
	app.menus.lock_navigation(true)
	app.menus.lock_navigation(false)
	expect(app.menus.campaign_button.disabled, "Unlocking menus never enables the unfinished Campaign")
	app.menus.open_profile(false)
	expect(not panel.editing and not panel.game_preview.visible and panel.stats_view.visible and not panel.edit_view.visible, "Existing profiles open to statistics rather than the editor")
	var steam = root.get_node("SteamOnline")
	var prior_api = steam.api
	var prior_available: bool = steam.available
	var prior_id: int = steam.local_id
	steam.api = preload("res://tests/fixtures/fake_steam_api.gd").new()
	steam.available = true
	steam.local_id = 42
	steam.changed.emit()
	expect(panel.title.text == "Player 42" and app.menus.profile_caption.text == "Player 42", "Profile header and menu badge use the Steam persona name")
	steam.api = prior_api
	steam.available = prior_available
	steam.local_id = prior_id
	panel.edit_button.pressed.emit()
	expect(panel.editing and panel.edit_view.visible, "The brush button enters customization")
	panel.country_color.parse_hex("#223344")
	expect(panel.game_preview.board.COLORS[0].is_equal_approx(Color("223344").darkened(0.06)), "Hex edits update a miniature rendered with the actual game tint")
	expect(is_equal_approx(panel.preview.size.x / panel.preview.size.y, 1.5), "Flags use the original 3:2 proportions")
	expect(panel.game_preview.visible, "The country preview is visible in country editing")
	expect(panel.country_color.wheel.picker_shape == ColorPicker.SHAPE_HSV_WHEEL and not panel.country_color.wheel.sliders_visible, "Color editing provides a wheel without advanced sliders")
	panel.country_color.wheel.color_changed.emit(Color("997755"))
	expect(panel.country_color.color == Color("997755") and panel.country_color.hex_input.text == "#997755", "The wheel updates the hex field and country color")
	panel.country_color.parse_hex("#6699AA", panel.country_color.wheel_hex)
	expect(panel.country_color.hex_input.text == "#6699AA" and panel.country_color.wheel.color == Color("6699aa"), "The wheel popup hex field updates the shared color")
	panel.country_color.parse_hex("#GG", panel.country_color.wheel_hex)
	expect(not panel.country_color.valid(), "Incomplete popup hex edits cannot save a stale color")
	panel.country_color.parse_hex("#6699AA", panel.country_color.wheel_hex)
	panel.edit_tabs.current_tab = 1
	expect(panel.preview.visible and not panel.game_preview.visible and panel.flag_view.visible, "Flag editing gets its own preview and controls")
	for side in ["left", "right"]:
		panel.placement.select(Store.PLACEMENTS.find(side))
		panel.refresh_preview()
		expect(panel.preview.design.placement == side and Store.normalize_identity(panel.draft()).flag.placement == side, "Side-centered emblems survive profile normalization")
	panel.name_input.text = "Changed without saving"
	panel.back()
	expect(not panel.editing and panel.country_color.color == Color("778ac7"), "Cancel returns to statistics and discards unsaved cosmetic edits")
	panel.back()
	expect(profile.data.name == "Silver Oak", "Backing out of customization preserves the saved identity")
	var reloaded = Store.new()
	expect(reloaded.load_settings(profile.settings_path) == OK and reloaded.data.flag.symbol == "tree" and reloaded.tutorial_prompt_seen, "Identity, flag and onboarding survive a reload")
	reloaded.free()
	await app.start_new_game(42)
	var game = app.game
	var owner: int = game.player_faction
	expect(game.session.names[owner] == "Silver Oak" and game.session.colors[owner] == Color("778ac7"), "Generated solo games use the profile name and country color")
	expect(game.hud.country_flag.design == profile.data.flag and game.level_label.text == "Silver Oak" and game.round_label.text.contains("Quick Play"), "Gameplay heading shows the saved flag and name above match details")
	game.match_clock.pause()
	game.match_clock.accumulated_usec = 120 * 1000000
	game.round_number = 5
	for cell in game.cells.values():
		if cell.owner != owner:
			cell.owner = -1
			cell.capital = -1
	game.rules.rebuild_kingdoms()
	game.check_winner()
	expect(profile.statistics.matches == 1 and profile.statistics.wins == 1 and profile.statistics.seconds == 120, "Completed match updates wins, completed matches and active play time")
	var awarded_xp: int = profile.statistics.xp
	expect(awarded_xp > 0 and game.profile_xp_award.earned == awarded_xp and app.menus.results_xp.visible, "Completed matches award XP and show it on the game-over screen")
	expect(app.menus.profile_xp.visible and app.menus.profile_xp.bar.value == Store.Progress.progress(awarded_xp).current and app.menus.profile_xp.level_label.text == "Level %d" % Store.Progress.progress(awarded_xp).level, "Main menu profile updates its level and progress when a match awards XP")
	var menu_style: StyleBoxFlat = app.menus.main_panel.get_theme_stylebox("panel")
	var profile_style: StyleBoxFlat = app.menus.profile_button.get_theme_stylebox("normal")
	expect(profile_style.bg_color == menu_style.bg_color and profile_style.border_color == menu_style.border_color and profile_style.border_width_left == menu_style.border_width_left and profile_style.corner_radius_top_left == menu_style.corner_radius_top_left, "Main menu profile matches the menu panel color, outline and corners")
	app.menus.show_results(game)
	expect(app.menus.results_xp.bar.value == Store.Progress.progress(awarded_xp).current and app.menus.results_xp.level_label.text == "Level %d" % Store.Progress.progress(awarded_xp).level, "Reopening results shows the final XP progress")
	game.begin_completion_exit()
	expect(profile.statistics.xp == awarded_xp, "Repeated completion leaves XP unchanged")
	expect(profile.statistics.matches == 1, "Repeated result notifications never count a match twice")
	var changed: Dictionary = profile.data.duplicate(true)
	changed.name = "Silver Oak Realm"
	expect(profile.save_identity(changed) == OK and profile.data.id == original_id and profile.statistics.matches == 1, "Editing the sole profile preserves its identity and statistics")
	expect(profile.record_match("loss-fixture", "defeat", 60, 3) == OK, "Loss result saves")
	expect(profile.statistics.losses == 1 and profile.statistics.matches == 2 and profile.average_seconds() == 90, "Average duration uses the completed match count")
	profile.record_match("loss-fixture", "defeat", 60, 3)
	expect(profile.statistics.matches == 2, "Persisted match IDs prevent duplicate statistics")
	game.initial_level_data = {"tutorial":true}
	game.profile_match_id = "excluded-tutorial"
	app.record_profile_result(game)
	expect(profile.statistics.matches == 2, "Tutorial and authored editor sessions do not affect the match record")
	game.initial_level_data.clear()
	game.rules.human_factions = [0, 1]
	game.profile_match_id = "excluded-local"
	app.record_profile_result(game)
	expect(profile.statistics.matches == 2, "Shared local hotseat results are not attributed to one player")
	var saved_stats = Store.new()
	expect(saved_stats.load_settings(profile.settings_path) == OK and saved_stats.statistics.matches == 2 and saved_stats.statistics.wins == 1 and saved_stats.statistics.xp == profile.statistics.xp, "Match record and XP survive disk reload")
	saved_stats.free()
	var original := ConfigFile.new()
	original.load(profile.settings_path)
	var damaged := ConfigFile.new()
	damaged.set_value("profile", "identity", {})
	damaged.save(profile.settings_path)
	var recovered = Store.new()
	expect(recovered.load_settings(profile.settings_path) == OK and recovered.data.id == original_id, "An invalid primary profile recovers the previous saved identity from its backup")
	recovered.free()
	original.save(profile.settings_path)
	app.menus.begin_onboarding()
	expect(app.menus.screen == app.menus.Screen.MAIN, "Subsequent launches do not repeat onboarding")
	var requested: Array = []
	app.menus.tutorial_requested.connect(func(category): requested.append(category))
	app.menus.finish_welcome(true)
	expect(requested == ["armies"] and profile.tutorial_prompt_seen, "The recommended action selects the first playable tutorial")
	await app.return_to_main_menu()
	app.menus.show_screen(app.menus.Screen.SETUP)
	app.menus.player_kingdom_choice.cards[6].pressed.emit()
	expect(not preferences.quick_play_use_profile and preferences.quick_play_kingdom == 6, "Default-country cards disable the profile country override")
	await app.start_new_game(43)
	expect(app.game.initial_profile.is_empty() and app.game.session.names[0] == "Ruby", "Quick Play can launch a default country while keeping the profile and its record")
	await app.return_to_main_menu()
	app.menus.open_profile(false)
	expect(panel.size.x == 560 and panel.xp_progress.level_label.text == "Level %d" % Store.Progress.progress(profile.statistics.xp).level, "The narrow profile card shows saved level progress")
	panel.delete_button.pressed.emit()
	expect(panel.delete_confirmation.visible and profile.exists(), "Deleting requires the explicit in-game confirmation")
	panel.back()
	expect(not panel.delete_confirmation.visible and profile.exists(), "Cancelling deletion keeps the save intact")
	preferences.completed_tutorials["armies"] = true
	panel.delete_button.pressed.emit()
	panel.confirm_delete_button.pressed.emit()
	expect(not profile.exists() and profile.statistics.matches == 0 and profile.statistics.xp == 0 and preferences.completed_tutorials.is_empty(), "Confirmed deletion clears identity, statistics and tutorial progress")
	for suffix in ["", ".tmp", ".bak"]:
		expect(not FileAccess.file_exists(profile.settings_path + suffix), "Deleted profile and its recovery files cannot reload")
	expect(app.menus.screen == app.menus.Screen.PROFILE and panel.required and panel.editing, "Deletion returns to fresh profile creation")
	panel.name_input.text = "A new realm"
	panel.commit()
	expect(profile.exists() and profile.data.id != original_id and profile.statistics.matches == 0, "Starting fresh creates a new save identity with an empty history")
	preferences.settings_path = original_preferences_path
	paused = false
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Player profile checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
