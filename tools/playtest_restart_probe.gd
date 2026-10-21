extends SceneTree
var samples: Dictionary = {}
var last := 0
var app
var sampling := false
func _initialize() -> void: call_deferred("run")
func sample() -> void:
	var now := Time.get_ticks_usec()
	if sampling:
		var stage := "preparing"
		if is_instance_valid(app.game):
			if app.game.view.level_transitioning: stage = "entrance" if app.game.view.island_transition.entering else "departure"
			elif not app.transitioning: stage = "settled"
		if not samples.has(stage): samples[stage] = []
		samples[stage].append([(now-last)/1000.0,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	last = now
func run() -> void:
	root.size = Vector2i(1200,800)
	root.get_node("Video").set_preference(&"vsync",false,false)
	root.get_node("Video").set_preference(&"level_transitions",true,false)
	Engine.max_fps = 0 if "--uncapped" in OS.get_cmdline_user_args() else 120
	app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var size_id := "huge" if "--huge" in OS.get_cmdline_user_args() else "large"
	root.get_node("Gameplay").set_rules("modern", false)
	if "--normal" in OS.get_cmdline_user_args():
		await app.start_new_game(4242, size_id)
	else:
		app.open_editor()
		var doc = app.editor.document
		doc.generate(size_id, "modern")
		# A fixed island makes future comparisons repeatable.
		var rules = load("res://src/game/kingdom_rules.gd").new()
		rules.rule_mode = "modern"
		rules.generate(4242, size_id, 4)
		doc.cells = rules.cells.duplicate(true)
		for cell in doc.cells.values():
			cell["event"] = ""
			cell.erase("treasure")
		doc.seed_value = 4242
		doc.player_faction = 0
		await app.play_editor_level(doc.state())
	while app.game.view.level_transitioning: await process_frame
	await create_timer(0.4).timeout
	process_frame.connect(sample)
	app.pause_game()
	last = Time.get_ticks_usec()
	sampling = true
	await app.restart_current_level()
	while app.game.view.level_transitioning: await process_frame
	await create_timer(0.6).timeout
	sampling = false
	print(JSON.stringify(app.game.startup_timings))
	for stage in samples:
		var rows: Array = samples[stage]
		var gaps: Array = rows.map(func(row): return row[0])
		var calls: Array = rows.map(func(row): return row[1])
		gaps.sort()
		calls.sort()
		var total := 0.0
		for gap in gaps: total += gap
		print(JSON.stringify({"stage":stage,"frames":rows.size(),"avg_fps":rows.size()*1000.0/total,"p99_ms":gaps[mini(gaps.size()-1,int(gaps.size()*0.99))],"max_draw_calls":calls[-1]}))
	app.queue_free()
	await process_frame
	quit()
