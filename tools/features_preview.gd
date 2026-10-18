extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(960, 620)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	root.add_child(game)
	game.rules.set_effect(0, "trailblaze", true)
	game.rules.set_effect(0, "free_spell", true)
	for coord in game.active_kingdom()["hexes"]:
		if game.rules.can_entrench(coord, 0):
			game.rules.entrench(coord, 0)
			break
	game.rules.set_effect(0, "free_spell", true)
	game.rules.set_effect(0, "trailblaze", true)
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.set_process(false)
	game.open_shop("spells")
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/features_spells.png")
	game.close_menus()
	game.rules.pending_events.append({"id": "altar", "coord": game.active_capital(), "faction": 0})
	game.show_next_event()
	game.refresh_ui()
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/features_event.png")
	game.close_event_ui()
	game.rules.pending_events.clear()
	game.rules.pending_events.append({"id": "wizard", "coord": game.active_capital(), "faction": 0})
	game.show_next_event()
	game.refresh_ui()
	await create_timer(0.30).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/features_event_one_choice.png")
	root.get_node("Sound").stop_all()
	quit()
