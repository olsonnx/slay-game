extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1200, 800)
	root.get_node("Video").set_preference(&"vsync", false, false)
	Engine.max_fps = 120
	var editor
	var app
	if "--app" in OS.get_cmdline_user_args():
		Engine.max_fps = 0
		app = load("res://scenes/app.tscn").instantiate()
		app.onboarding_enabled = false
		root.add_child(app)
		await app.startup_finished
		await process_frame
		app.open_editor()
		editor = app.editor
	else:
		editor = load("res://src/editor/level_editor.gd").new()
		root.add_child(editor)
	await process_frame
	editor.ui.size_choice.select(editor.Document.Sizes.IDS.find("huge"))
	await editor.new_island("--blank" in OS.get_cmdline_user_args())
	editor.close_context()
	await create_timer(0.5).timeout
	for stage in ["idle", "hover", "mouse_burst", "pan", "paint"]:
		var samples: Array[float] = []
		var event_usec := 0
		var started := Time.get_ticks_usec()
		var last := started
		if stage == "paint":
			editor.select_tool("Value")
			editor.ui.value_choice.value = 3
			editor.stroke.begin(editor.document)
		for tick in range(90):
			var screen := Vector2(680 + sin(tick * 0.13) * 130, 330 + cos(tick * 0.09) * 130)
			var before := Time.get_ticks_usec()
			if stage in ["hover", "mouse_burst", "paint"]:
				for burst in range(8 if stage == "mouse_burst" else 1):
					var motion := InputEventMouseMotion.new()
					motion.position = screen + Vector2(burst * 0.25, 0)
					motion.relative = Vector2(1, 0)
					if "--native-input" in OS.get_cmdline_user_args(): root.push_input(motion)
					else:
						editor._input(motion)
						editor._unhandled_input(motion)
			elif stage == "pan": editor.view.pan(Vector2.RIGHT, 0.001)
			event_usec += Time.get_ticks_usec() - before
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-last)/1000.0)
			last = now
		if stage == "paint": editor.end_stroke()
		samples.sort()
		print(JSON.stringify({"stage":stage,"fps":90000000.0/(last-started),"p99_ms":samples[88],"event_ms_per_frame":event_usec/90000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"batches":editor.view.static_batches.instance_count,"dirty":editor.view.batch_update_pending}))
	if app != null: app.queue_free()
	else: editor.queue_free()
	await process_frame
	quit()
