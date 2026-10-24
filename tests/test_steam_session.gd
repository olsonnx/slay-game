extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	var connection = root.get_node("SteamOnline")
	var api = load("res://tests/fixtures/fake_steam_api.gd").new()
	connection.api = api
	connection.available = true
	connection.local_id = 101
	connection.phase = "creating"
	connection._created(1, 777)
	expect(app.menus.screen == app.menus.Screen.ONLINE and app.menus.online_panel.visible, "Joining a Steam lobby opens its dedicated screen")
	api.ready[202] = "1"
	connection.refresh_members()
	expect(not app.menus.online_panel.start_button.disabled, "Ready lobby members enable the host's start button")
	connection.start({"size":"small","count":2})
	while app.transitioning: await process_frame
	expect(is_instance_valid(app.game) and app.game.network_match != null and app.game.rules.human_factions == [0,1], "Steam start signal creates a match with network-owned human seats")
	var game = app.game
	expect(game.commands_locked(), "Host waits for every Steam peer to finish loading")
	connection.loaded_peers[202] = true
	connection.peer_loaded.emit()
	expect(not game.commands_locked(), "Loaded peers unlock the host's first turn")
	app.pause_game()
	expect(not paused and game.network_match.local_paused and game.commands_locked(), "Online pause locks local commands without pausing the network or world")
	expect(game.match_clock.running_since >= 0, "Online pause does not stop the authoritative match clock")
	expect(app.menus.restart_button.disabled and app.menus.defeat_restart_button.disabled, "Online sessions disable both restart controls")
	await app.restart_current_level()
	expect(app.game == game, "Programmatic restart requests cannot replace an online match")
	app.continue_game()
	expect(not game.network_match.local_paused and not game.commands_locked() and app.menus.screen == app.menus.Screen.HIDDEN, "Continue restores the player's online controls")
	connection.abort("Disconnected for test")
	expect(game.network_match.terminated and game.commands_locked() and app.menus.screen == app.menus.Screen.ONLINE, "Connection failure locks the match and shows the lobby error screen")
	expect(connection.status == "Disconnected for test", "Disconnect reason survives lobby cleanup")
	await app.return_to_main_menu()
	expect(app.game == null and connection.phase == "idle" and not paused and app.menus.screen == app.menus.Screen.MAIN, "Leaving an ended online session retires the match and restores the main menu")
	app.queue_free()
	await process_frame
	print("Steam session checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
