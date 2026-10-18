extends Node
const Loc = preload("res://src/localization/text.gd")
## Owns session navigation; game state remains isolated in the gameplay scene.
const GameScene = preload("res://scenes/main.tscn")
const Menus = preload("res://src/ui/session_menus.gd")
var game
var menus
var retiring_games := 0
var transitioning := false
var fps_counter
var editor
var custom_level: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menus = Menus.new()
	add_child(menus)
	fps_counter = preload("res://src/ui/fps_counter.gd").new(menus.menu_background)
	fps_counter.binding_capture_active = func(): return menus.options_view.controls_page.pending != ""
	add_child(fps_counter)
	menus.new_game_requested.connect(func(size_id: String, kingdom_count: int): start_new_game(-1, size_id, "", kingdom_count))
	menus.multiplayer_requested.connect(start_multiplayer)
	menus.continue_requested.connect(continue_game)
	menus.main_menu_requested.connect(return_to_main_menu)
	menus.quit_requested.connect(quit_game)
	menus.restart_requested.connect(restart_current_level)
	menus.save_replay_requested.connect(save_replay)
	menus.show_map_requested.connect(show_finished_map)
	menus.results_requested.connect(pause_game)
	menus.rules_requested.connect(change_rules)
	menus.editor_requested.connect(open_editor)
	menus.tutorial_requested.connect(start_tutorial)
	get_tree().paused = false
	menus.show_screen(Menus.Screen.MAIN)

func start_tutorial(category := "basics") -> void:
	if transitioning or is_instance_valid(game) or is_instance_valid(editor): return
	var data := preload("res://src/game/tutorial_lessons.gd").map_data(category)
	await start_new_game(data["seed"],data["size"],"easy",2,data)

func start_next_tutorial(category: String) -> void:
	await return_to_main_menu()
	await start_tutorial(category)

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
	custom_level = level_data.duplicate(true)
	menus.lock_navigation(true)
	get_tree().paused = false
	menus.show_screen(Menus.Screen.HIDDEN)
	fps_counter.refresh()
	var preparation = preload("res://src/ui/preparation_screen.gd").new()
	add_child(preparation)
	# Present the cover and stop the decorative viewport before expensive work.
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
	game.animate_level_changes = true
	game.deferred_startup = true
	game.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(game)
	game.hud.ui_root.hide()
	game.view.controls_enabled = false
	await game.prepare_board()
	if custom_level.get("tutorial",false):
		game.tutorial = preload("res://src/game/tutorial.gd").new(game)
		game.tutorial.next_requested.connect(start_next_tutorial)
		game.add_child(game.tutorial)
		game.tutorial_exit_requested.connect(return_to_main_menu)
	game.pause_requested.connect(pause_game)
	game.defeat_requested.connect(pause_game)
	# Covered rendering warms the actual meshes, shaders and shadow passes.
	for frame in range(3):
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	await get_tree().process_frame
	game.play_level_entry()
	await preparation.reveal()
	game.match_clock.resume()
	game.process_mode = Node.PROCESS_MODE_PAUSABLE
	game.hud.ui_root.show()
	transitioning = false
	menus.lock_navigation(false)
	menus.options_view.authored_rules = game.rules.rule_mode if not custom_level.is_empty() else ""
	menus.options_view.refresh()
	menus.options_view.rules_choice.disabled = not custom_level.is_empty()
	menus.options_view.rules_choice.tooltip_text = Loc.text("This level uses its authored rules. Choose rules for a new island in the editor.") if not custom_level.is_empty() else ""
	menus.quit_menu_button.text = Loc.text("Return to editor") if is_instance_valid(editor) else "Main menu"
	menus.defeat_menu_button.text = menus.quit_menu_button.text

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
	game.match_clock.pause()
	game.inspecting_results_map = false
	if game.game_over:
		menus.show_results(game)
	game.view.overlay_root.hide()
	menus.show_screen(Menus.Screen.DEFEAT if game.defeat_notified else Menus.Screen.PAUSE)
	get_tree().paused = true

func continue_game() -> void:
	if transitioning or not is_instance_valid(game) or game.game_over:
		return
	menus.show_screen(Menus.Screen.HIDDEN)
	game.match_clock.resume()
	game.hud.ui_root.show()
	game.view.overlay_root.show()
	get_tree().paused = false

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
	transitioning = true
	menus.lock_navigation(true)
	retiring_games += 1
	await depart_current_game()
	await retire_current_game()
	retiring_games -= 1
	custom_level.clear()
	menus.options_view.rules_choice.disabled = false
	menus.options_view.authored_rules = ""
	if is_instance_valid(editor):
		menus.show_screen(Menus.Screen.HIDDEN)
		# Retirement is deferred; let its camera/environment leave before restoring.
		await get_tree().process_frame
		add_child(editor)
		editor.set_suspended(false)
		editor.refresh()
	else:
		menus.show_screen(Menus.Screen.MAIN)
	transitioning = false
	menus.lock_navigation(false)

func depart_current_game() -> void:
	menus.show_screen(Menus.Screen.HIDDEN)
	get_tree().paused = false
	if is_instance_valid(game):
		await game.play_level_departure()

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
	previous.queue_free()
	retiring_games -= 1

func restart_current_level() -> void:
	if transitioning or not is_instance_valid(game):
		return
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
	if is_instance_valid(game):
		game.shutdown()
	Sound.flush_settings()
	Video.flush_settings()
	Gameplay.flush_settings()
	Sound.stop_all()
	get_tree().paused = false
	get_tree().quit()

func change_rules(mode: String) -> void:
	if transitioning or mode == Gameplay.rule_mode or mode not in ["modern", "classic"]:
		return
	if not custom_level.is_empty():
		# An authored map fixes its rules; preserve its topology and terrain.
		menus.options_view.refresh()
		return
	Gameplay.set_rules(mode)
	menus.options_view.refresh()
	if not is_instance_valid(game):
		return
	var previous_seed: int = game.rules.level_seed
	var size_id: String = game.rules.map_size
	var difficulty: String = game.initial_difficulty
	var kingdom_count: int = game.rules.initial_kingdom_count
	var human_count: int = game.initial_human_count
	var match_config: Dictionary = game.initial_match_config.duplicate(true)
	transitioning = true
	menus.lock_navigation(true)
	await depart_current_game()
	await retire_current_game()
	transitioning = false
	menus.lock_navigation(false)
	# A rules change generates a fresh island; Restart keeps the current seed.
	if not match_config.is_empty():
		match_config["rules"] = mode
	var next_seed := int(Time.get_ticks_usec() % 2147483647)
	if next_seed == previous_seed:
		next_seed = (next_seed + 1) % 2147483647
	await start_new_game(next_seed, size_id, difficulty, kingdom_count, {}, human_count, match_config)
	pause_game()
	menus.open_options(Menus.Screen.PAUSE)

func _exit_tree() -> void:
	if is_instance_valid(editor) and editor.get_parent() == null:
		editor.free()
	get_tree().paused = false
