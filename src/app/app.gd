extends Node
const Loc = preload("res://src/localization/text.gd")
## Owns session navigation; game state remains isolated in the gameplay scene.
const GameScene = preload("res://scenes/main.tscn")
const Menus = preload("res://src/ui/session_menus.gd")
signal startup_finished
var startup_complete := false
var startup_warmup
var startup_viewport: SubViewport
var startup_warmup_ms := 0.0
var game
var menus
var retiring_games := 0
var transitioning := false
var departure_cover: CanvasLayer
var fps_counter
var music_controls
var editor
var replay_viewer
var custom_level: Dictionary = {}
var onboarding_enabled := true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and Gameplay.pause_on_focus_loss:
		if startup_complete and is_instance_valid(game) and game.network_match == null and not get_tree().paused:
			pause_game()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menus = Menus.new()
	add_child(menus)
	SteamOnline.match_requested.connect(start_online_match)
	SteamOnline.failed.connect(online_failed)
	SteamOnline.changed.connect(online_changed)
	SteamOnline.invitation_received.connect(accept_online_invitation)
	menus.online_panel.back_requested.connect(func():
		if is_instance_valid(game) and game.network_match != null: return_to_main_menu())
	fps_counter = preload("res://src/ui/fps_counter.gd").new(menus.menu_background)
	fps_counter.binding_capture_active = func(): return menus.options_view.controls_page.pending != ""
	add_child(fps_counter)
	music_controls = preload("res://src/ui/music_controls.gd").new()
	add_child(music_controls)
	menus.new_game_requested.connect(func(size_id: String, kingdom_count: int): start_new_game(-1, size_id, "", kingdom_count))
	menus.multiplayer_requested.connect(start_multiplayer)
	menus.continue_requested.connect(continue_game)
	menus.main_menu_requested.connect(return_to_main_menu)
	menus.quit_requested.connect(quit_game)
	menus.restart_requested.connect(restart_current_level)
	menus.save_replay_requested.connect(save_replay)
	menus.show_map_requested.connect(show_finished_map)
	menus.results_requested.connect(pause_game)
	menus.editor_requested.connect(open_editor)
	menus.replays_requested.connect(open_replays)
	menus.tutorial_requested.connect(start_tutorial)
	menus.onboarding_finished.connect(func(): accept_online_invitation.call_deferred())
	get_tree().paused = false
	menus.lock_navigation(true)
	menus.show_screen(Menus.Screen.HIDDEN)
	var preparation = await prepare_application()
	menus.show_screen(Menus.Screen.MAIN)
	await preparation.reveal()
	menus.lock_navigation(false)
	if onboarding_enabled: menus.begin_onboarding()
	startup_complete = true
	startup_finished.emit()
	accept_online_invitation()

func accept_online_invitation() -> void:
	if not startup_complete or SteamOnline.invited_lobby <= 0: return
	if onboarding_enabled and (not PlayerProfile.exists() or not PlayerProfile.tutorial_prompt_seen): return
	if transitioning or is_instance_valid(game) or is_instance_valid(editor) or is_instance_valid(replay_viewer):
		if is_instance_valid(game): game.announce(Loc.text("Return to the main menu to accept your Steam invitation."))
		return
	SteamOnline.join(SteamOnline.invited_lobby)
	SteamOnline.invited_lobby = 0

func start_online_match(config: Dictionary, roster: Array) -> void:
	if transitioning or is_instance_valid(game) or is_instance_valid(editor) or is_instance_valid(replay_viewer):
		SteamOnline.abort(Loc.text("Return to the main menu before starting an online match."))
		return
	await start_new_game(config.seed, config.size, "normal", config.count, {}, roster.size(), config)
	if SteamOnline.phase != "match":
		await return_to_main_menu()
		menus.show_screen(Menus.Screen.ONLINE)
		return
	var online_match = preload("res://src/network/network_match.gd").new(SteamOnline, game, roster)
	game.add_child(online_match)
	# Only the host records authoritative actions; clients render its snapshots.
	if not SteamOnline.is_host(): game.rules.replay_log = null
	menus.restart_button.disabled = true
	menus.defeat_restart_button.disabled = true

func online_changed() -> void:
	if not startup_complete or SteamOnline.phase != "lobby" or is_instance_valid(game) or is_instance_valid(editor) or is_instance_valid(replay_viewer): return
	menus.show_screen(Menus.Screen.ONLINE)

func online_failed(_message: String) -> void:
	if not startup_complete or transitioning: return
	if is_instance_valid(game) and game.network_match != null:
		game.network_match.terminate()
		game.hud.ui_root.hide()
		game.view.overlay_root.hide()
		game.match_clock.pause()
	elif is_instance_valid(game) or is_instance_valid(editor) or is_instance_valid(replay_viewer): return
	menus.show_screen(Menus.Screen.ONLINE)

func prepare_application() -> CanvasLayer:
	var preparation = preload("res://src/ui/preparation_screen.gd").new()
	add_child(preparation)
	preparation.caption.text = Loc.text("Loading...")
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	var started := Time.get_ticks_usec()
	# Separate world: retain the warmed resources without a live match or camera
	# competing with the menu, editor, replay viewer or subsequent matches.
	startup_viewport = SubViewport.new()
	startup_viewport.name = "StartupGraphics"
	startup_viewport.size = Vector2i(960, 620)
	startup_viewport.own_world_3d = true
	startup_viewport.msaa_3d = get_viewport().msaa_3d
	startup_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(startup_viewport)
	var board = preload("res://src/rendering/board_view.gd").new()
	board.process_mode = Node.PROCESS_MODE_DISABLED
	board.active = false
	board.controls_enabled = false
	startup_viewport.add_child(board)
	board.land_ambience.set_process(false)
	board.zoom = 10.0
	board.update_camera()
	startup_warmup = preload("res://src/rendering/graphics_warmup.gd").new()
	board.add_child(startup_warmup)
	preparation.set_progress(0.05)
	await startup_warmup.prepare(board, range(board.COLORS.size()), func(value: float):
		preparation.set_progress(0.05 + 0.95 * value))
	board.hide()
	startup_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	startup_warmup_ms = (Time.get_ticks_usec() - started) / 1000.0
	preparation.set_progress(1.0)
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	return preparation

func open_replays() -> void:
	if transitioning or is_instance_valid(game) or is_instance_valid(editor) or is_instance_valid(replay_viewer): return
	menus.show_screen(Menus.Screen.HIDDEN)
	replay_viewer = preload("res://src/ui/replay_viewer.gd").new()
	# Reuse the last menu image while its decorative 3D viewport stays stopped.
	replay_viewer.library_backdrop = menus.menu_background.viewport.get_texture()
	add_child(replay_viewer)
	replay_viewer.ui_visibility_changed.connect(func(shown: bool):
		if is_instance_valid(fps_counter): fps_counter.visible = shown)
	replay_viewer.closed.connect(func():
		var previous = replay_viewer
		replay_viewer = null
		remove_child(previous)
		previous.queue_free()
		menus.show_screen(Menus.Screen.MAIN))

func start_tutorial(category := "armies") -> void:
	if transitioning or is_instance_valid(game) or is_instance_valid(editor): return
	var data := preload("res://src/game/tutorial_lessons.gd").map_data(category)
	await start_new_game(data["seed"],data["size"],"easy",2,data)

func start_next_tutorial(category: String) -> void:
	await return_to_main_menu()
	await start_tutorial(category)

func return_to_tutorials() -> void:
	await return_to_main_menu()
	menus.show_screen(Menus.Screen.TUTORIAL)

func start_multiplayer(config: Dictionary) -> void:
	if transitioning or is_instance_valid(game): return
	var setup := preload("res://src/game/match_setup.gd").normalize(config)
	var level_data: Dictionary = {}
	if setup.has("map_path"):
		var loaded := preload("res://src/game/match_setup.gd").read_level(setup["map_path"])
		if loaded["error"] != "":
			menus.multiplayer_panel.show_map_error(loaded["error"])
			return
		if setup["count"] != loaded["factions"].size():
			menus.multiplayer_panel.show_map_error(Loc.text("This map changed. Load it again to update the player seats."))
			return
		level_data = loaded["data"]
		for key in ["size", "rules", "seed"]: setup[key] = level_data[key]
		setup["count"] = loaded["factions"].size()
		setup = preload("res://src/game/match_setup.gd").normalize(setup)
	if preload("res://src/game/match_setup.gd").human_count(setup) < 2: return
	Gameplay.set_rules(setup["rules"])
	await start_new_game(setup["seed"], setup["size"], "normal", setup["count"], level_data, 2, setup)

func start_new_game(seed_value := -1, size_id := "small", difficulty := "", kingdom_count := 0, level_data: Dictionary = {}, human_count := 1, match_config: Dictionary = {}) -> void:
	if transitioning or is_instance_valid(game):
		return
	transitioning = true
	if not startup_complete: await startup_finished
	custom_level = level_data.duplicate(true)
	menus.lock_navigation(true)
	get_tree().paused = false
	menus.show_screen(Menus.Screen.HIDDEN)
	fps_counter.refresh()
	var preparation = preload("res://src/ui/preparation_screen.gd").new()
	add_child(preparation)
	# Present the cover and stop the decorative viewport before expensive work.
	clear_departure_cover()
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	game = GameScene.instantiate()
	game.initial_human_count = human_count
	game.initial_match_config = match_config.duplicate(true)
	if match_config.is_empty() and level_data.is_empty() and human_count == 1:
		game.initial_quick_play_kingdom = Gameplay.quick_play_kingdom
	game.initial_seed = seed_value
	game.initial_rule_mode = match_config.get("rules", Gameplay.rule_mode)
	game.initial_map_size = size_id
	game.initial_kingdom_count = kingdom_count
	game.initial_difficulty = Gameplay.difficulty if difficulty == "" else difficulty
	game.initial_level_data = custom_level.duplicate(true)
	if human_count == 1 and custom_level.is_empty() and PlayerProfile.exists() and Gameplay.quick_play_use_profile:
		game.initial_profile = PlayerProfile.data.duplicate(true)
	game.profile_match_id = Crypto.new().generate_random_bytes(16).hex_encode()
	game.profile_owner_id = PlayerProfile.data.get("id", "")
	game.animate_level_changes = true
	game.deferred_startup = true
	game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game)
	game.hud.ui_root.hide()
	game.view.controls_enabled = false
	game.view.birds.set_loading(true)
	var loading_camera_mask: int = game.view.camera.cull_mask
	game.view.camera.cull_mask = 0
	preparation.set_progress(0.05)
	await game.prepare_board(func(value: float): preparation.set_progress(0.05 + 0.85 * value))
	if custom_level.get("tutorial",false):
		game.tutorial = preload("res://src/game/tutorial.gd").new(game)
		game.tutorial.next_requested.connect(start_next_tutorial)
		game.add_child(game.tutorial)
		game.tutorial_exit_requested.connect(return_to_tutorials)
	game.pause_requested.connect(pause_game)
	game.defeat_requested.connect(pause_game)
	game.match_completed.connect(record_profile_result.bind(game))
	game.view.camera.cull_mask = loading_camera_mask
	await game.view.lighting.warmup()
	var value_view_started := Time.get_ticks_usec()
	await game.view.value_heatmap.prepare()
	game.startup_timings["value_view_prepare_ms"] = (Time.get_ticks_usec() - value_view_started) / 1000.0
	preparation.set_progress(0.94)
	# Covered rendering warms the actual meshes, shaders and shadow passes.
	for frame in range(3):
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		preparation.set_progress(0.94 + 0.02 * (frame + 1))
	await get_tree().process_frame
	game.play_level_entry()
	game.view.birds.set_loading(false)
	await preparation.reveal()
	game.match_clock.resume()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.hud.ui_root.show()
	transitioning = false
	menus.lock_navigation(false)
	menus.options_view.refresh()
	menus.restart_button.disabled = false
	menus.defeat_restart_button.disabled = false
	menus.quit_menu_button.text = Loc.text("Return to editor") if is_instance_valid(editor) else "Main menu"
	menus.defeat_menu_button.text = menus.quit_menu_button.text

func record_profile_result(completed_game) -> void:
	if not PlayerProfile.exists() or completed_game.profile_owner_id != PlayerProfile.data.get("id", ""): return
	if completed_game.profile_match_id in PlayerProfile.recorded_matches: return
	if not completed_game.initial_level_data.is_empty(): return
	if completed_game.is_hotseat() and completed_game.network_match == null: return
	var owner: int = completed_game.network_match.local_faction if completed_game.network_match != null else completed_game.player_faction
	var result := "victory" if completed_game.rules.has_capital(owner) else "defeat"
	if completed_game.network_match != null:
		result = "victory" if completed_game.winner_faction == owner else "defeat"
	if not completed_game.cells.values().any(func(cell): return cell["capital"] >= 0): result = "draw"
	var settings := {"difficulty":completed_game.initial_difficulty, "size":completed_game.rules.map_size,
		"opponents":completed_game.initial_match_config.get("count", completed_game.initial_kingdom_count) - 1,
		"slots":completed_game.initial_match_config.get("slots", []), "owner":owner}
	var before: int = PlayerProfile.statistics.xp
	var error: Error = PlayerProfile.record_match(completed_game.profile_match_id, result, completed_game.match_clock.seconds(), completed_game.round_number, settings)
	if error != OK: completed_game.announce(Loc.text("Your match record could not be saved."))
	else: completed_game.profile_xp_award = {"before":before, "after":PlayerProfile.statistics.xp, "earned":PlayerProfile.statistics.xp - before}

func open_editor() -> void:
	if transitioning or is_instance_valid(game) or is_instance_valid(editor): return
	menus.show_screen(Menus.Screen.HIDDEN)
	editor = preload("res://src/editor/level_editor.gd").new()
	add_child(editor)
	editor.back_requested.connect(close_editor)
	editor.play_requested.connect(play_editor_level)

func close_editor() -> void:
	if transitioning or not is_instance_valid(editor): return
	editor.set_suspended(true)
	editor.queue_free()
	editor = null
	custom_level.clear()
	menus.show_screen(Menus.Screen.MAIN)

func play_editor_level(data: Dictionary) -> void:
	if transitioning or is_instance_valid(game): return
	editor.set_suspended(true)
	# Remove the editor's camera/environment from the shared 3D world during play.
	remove_child(editor)
	await start_new_game(int(data["seed"]), data["size"], Gameplay.difficulty, 0, data)

func pause_game() -> void:
	if transitioning or not is_instance_valid(game):
		return
	game.reset_camera_gesture()
	game.view.clear_unit_hover()
	game.hud.ui_root.hide()
	if game.network_match == null: game.match_clock.pause()
	menus.set_pause_details(game.match_clock, game.rules.level_seed)
	game.inspecting_results_map = false
	if game.game_over:
		menus.show_results(game)
	game.view.overlay_root.hide()
	menus.show_screen(Menus.Screen.DEFEAT if game.defeat_notified else Menus.Screen.PAUSE)
	if game.network_match != null:
		game.network_match.local_paused = true
		menus.restart_button.disabled = true
		get_tree().paused = false
	else: get_tree().paused = true

func continue_game() -> void:
	if transitioning or not is_instance_valid(game) or game.game_over:
		return
	menus.show_screen(Menus.Screen.HIDDEN)
	game.match_clock.resume()
	game.hud.ui_root.show()
	game.view.overlay_root.show()
	get_tree().paused = false
	if game.network_match != null:
		game.network_match.local_paused = false
		game.show_next_event()
		game.refresh_ui()

func save_replay() -> void:
	if not is_instance_valid(game) or not game.game_over or game.rules.replay_log == null: return
	game.rules.replay_log.save_completed(game.rules)
	menus.replay_saved(game.rules.replay_log)

func show_finished_map() -> void:
	if transitioning or not is_instance_valid(game) or not game.game_over: return
	game.reset_camera_gesture()
	game.inspecting_results_map = true
	game.view.controls_enabled = true
	menus.show_screen(Menus.Screen.MAP)
	get_tree().paused = false

func return_to_main_menu() -> void:
	if transitioning:
		return
	if is_instance_valid(game) and game.network_match != null:
		game.network_match.terminate()
		SteamOnline.leave()
	transitioning = true
	menus.lock_navigation(true)
	retiring_games += 1
	await depart_current_game()
	await retire_current_game()
	custom_level.clear()
	if is_instance_valid(editor):
		menus.show_screen(Menus.Screen.HIDDEN)
		# Retirement is deferred; let its camera/environment leave before restoring.
		await get_tree().process_frame
		add_child(editor)
		editor.set_suspended(false)
		editor.refresh()
	else:
		menus.show_screen(Menus.Screen.MAIN)
	# Keep the last match image until the destination has actually rendered.
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	clear_departure_cover()
	retiring_games -= 1
	transitioning = false
	menus.lock_navigation(false)
	accept_online_invitation()

func depart_current_game() -> void:
	menus.show_screen(Menus.Screen.HIDDEN)
	get_tree().paused = false
	if is_instance_valid(game):
		await game.play_level_departure()
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		cover_departed_game()

func cover_departed_game() -> void:
	clear_departure_cover()
	departure_cover = CanvasLayer.new()
	departure_cover.name = "DepartureCover"
	departure_cover.layer = 65
	departure_cover.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(departure_cover)
	var backdrop := ColorRect.new()
	backdrop.color = Color("172c33")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	departure_cover.add_child(backdrop)
	if DisplayServer.get_name() != "headless":
		var image := TextureRect.new()
		image.texture = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		departure_cover.add_child(image)

func clear_departure_cover() -> void:
	if is_instance_valid(departure_cover):
		departure_cover.hide()
		departure_cover.queue_free()
	departure_cover = null

func retire_current_game() -> void:
	get_tree().paused = false
	var previous = game
	game = null
	if not is_instance_valid(previous):
		return
	retiring_games += 1
	previous.hide()
	previous.ui_root.hide()
	previous.shutdown()
	# Cancellation unwinds existing coroutines before their scene is freed.
	while previous.busy:
		await get_tree().process_frame
	await previous.view.retire_cells()
	previous.queue_free()
	retiring_games -= 1

func restart_current_level() -> void:
	if transitioning or not is_instance_valid(game):
		return
	if game.network_match != null: return
	var seed_value: int = game.rules.level_seed
	var size_id: String = game.rules.map_size
	var difficulty: String = game.initial_difficulty
	var kingdom_count: int = game.rules.initial_kingdom_count
	var human_count: int = game.initial_human_count
	var match_config: Dictionary = game.initial_match_config.duplicate(true)
	var level_data := custom_level.duplicate(true)
	transitioning = true
	menus.lock_navigation(true)
	await depart_current_game()
	await retire_current_game()
	transitioning = false
	menus.lock_navigation(false)
	await start_new_game(seed_value, size_id, difficulty, kingdom_count, level_data, human_count, match_config)

func quit_game() -> void:
	SteamOnline.leave()
	if is_instance_valid(game):
		game.shutdown()
	Sound.flush_settings()
	Video.flush_settings()
	Gameplay.flush_settings()
	Sound.stop_all()
	get_tree().paused = false
	get_tree().quit()

func _exit_tree() -> void:
	if is_instance_valid(editor) and editor.get_parent() == null:
		editor.free()
	get_tree().paused = false
