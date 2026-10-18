extends SceneTree
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(960, 620)
	if "--4k" in OS.get_cmdline_user_args(): root.size = Vector2i(3840, 2160)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	var original_cells: Dictionary = game.rules.cells.duplicate(true)
	for id in game.rules.Events.EVENTS:
		var requested_event := ""
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--event="): requested_event = argument.trim_prefix("--event=")
		if not requested_event.is_empty() and id != requested_event: continue
		if "--fallback" in OS.get_cmdline_user_args() and id not in ["comet", "economist"]: continue
		var choice_index := 1 if "--second-choice" in OS.get_cmdline_user_args() else 0
		if game.rules.Events.EVENTS[id]["choices"].size() <= choice_index: continue
		if "--paintings" in OS.get_cmdline_user_args() and not game.rules.Events.EVENTS[id].has("painting"): continue
		for coord in game.rules.cells: game.rules.cells[coord]["tree"] = original_cells[coord]["tree"]
		if id == "lumberjack":
			var planted := 0
			for coord in game.rules.kingdom_at(game.active_capital()).get("hexes", []):
				if coord == game.active_capital() or game.rules.cells[coord]["unit"] > 0: continue
				game.rules.cells[coord]["tree"] = true
				planted += 1
				if "--overgrown" not in OS.get_cmdline_user_args() and planted == 1: break
		var event := {"id": id, "coord": game.active_capital(), "faction": 0}
		var leave := InputEventMouseMotion.new()
		leave.position = Vector2(8, 8)
		leave.global_position = leave.position
		root.push_input(leave, true)
		await process_frame
		game.rules.pending_events.append(event)
		game.event_dialog.present(game.rules.event_definition(event), func(_choice): pass)
		await create_timer(0.3).timeout
		var choice: Button = game.event_panel.get_children().filter(func(child): return child is Button)[choice_index]
		var motion := InputEventMouseMotion.new()
		motion.position = game.event_panel.get_node("EventPainting").get_global_rect().get_center() if "--painting-tooltip" in OS.get_cmdline_user_args() else choice.get_global_rect().get_center()
		motion.global_position = motion.position
		if "--clean" not in OS.get_cmdline_user_args(): root.push_input(motion, true)
		await create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var artwork: TextureRect = game.event_panel.get_node("EventPainting")
		var rectangle := artwork.get_global_rect()
		var scale := Vector2(frame.get_width(), frame.get_height()) / root.get_visible_rect().size
		var darkest := 1.0
		var lightest := 0.0
		for x in [0.2, 0.5, 0.8]:
			for y in [0.2, 0.5, 0.8]:
				var pixel := frame.get_pixelv(Vector2i((rectangle.position + rectangle.size * Vector2(x, y)) * scale))
				darkest = minf(darkest, pixel.r)
				lightest = maxf(lightest, pixel.r)
		if lightest - darkest < 0.02: push_error("Painting did not render in preview: " + id)
		var suffix := "_4k" if "--4k" in OS.get_cmdline_user_args() else "_tooltip" if "--painting-tooltip" in OS.get_cmdline_user_args() else "_overgrown" if "--overgrown" in OS.get_cmdline_user_args() else ""
		if "--second-choice" in OS.get_cmdline_user_args(): suffix += "_choice2"
		frame.save_png("res://artifacts/event_%s%s.png" % [id, suffix])
		game.event_dialog.close_dialog()
		game.rules.pending_events.clear()
	game.shutdown()
	game.queue_free()
	await process_frame
	quit()
