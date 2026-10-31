extends SceneTree
const Setup = preload("res://src/game/match_setup.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	Engine.max_fps = 120
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	root.get_node("Video").set_preference(&"follow_turn_camera",false,false)
	root.get_node("Sound").set_muted(true,false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_map_size = "very_large"
	game.initial_kingdom_count = 10
	game.initial_match_config = Setup.quick_play("very_large",10,"easy",11,42,"modern")
	root.add_child(game)
	await process_frame
	game.view.playback.set_speed_scale(16.0)
	expect(game.rules.faction_count == 10 and game.turn_order.size() == 10,"A live match creates all ten nations")
	expect(game.rules.human_factions == [0] and game.NAMES[9] == game.initial_match_config.slots[9].name,"The tenth seat has its own identity and controller")
	game.toggle_stats()
	expect(game.stats_rows.get_child_count() == 11,"Statistics show ten nations and neutral land")
	game.toggle_stats()
	var turns := []
	game.faction_started.connect(func(faction): turns.append(faction))
	await game.end_turn()
	expect(turns == range(1,10) and game.round_number == 2 and game.player_faction == 0,"All nine AI nations finish their turns and return control to the human")
	game.shutdown()
	game.queue_free()
	await process_frame
	print("Ten-nation match checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
