extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1200, 800)
	root.get_node("Video").set_preference(&"vsync", false, false)
	Engine.max_fps = 120
	var editor = load("res://src/editor/level_editor.gd").new()
	root.add_child(editor)
	await process_frame
	for size_id in ["small", "huge"]:
		editor.ui.size_choice.select(editor.Document.Sizes.IDS.find(size_id))
		await editor.new_island(true)
		editor.select_tool("Land")
		editor.close_context()
		editor.set_random_values(false)
		if "--no-birds" in OS.get_cmdline_user_args():
			editor.view.birds.set_loading(true)
		if "--no-details" in OS.get_cmdline_user_args():
			editor.view.static_batches.set_detail_visible(false)
			await create_timer(0.3).timeout
		editor.view.profile_capture = true
		editor.view.static_batches.profile_sync = true
		var coords: Array[Vector2i] = []
		for r in range(-5, 6):
			for q in range(-5, 6): coords.append(Vector2i(q, r))
		var samples: Array[float] = []
		var cpu: Array[float] = []
		var last := Time.get_ticks_usec()
		for coord in coords:
			var screen: Vector2 = editor.view.camera.unproject_position(editor.Document.Rules.Grid.to_world(coord))
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = screen
			var before := Time.get_ticks_usec()
			editor._input(press)
			editor._unhandled_input(press)
			press.pressed = false
			editor._input(press)
			cpu.append((Time.get_ticks_usec()-before)/1000.0)
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-last)/1000.0)
			last = now
			if samples.size() <= 4: print("FIRST ",size_id," ",samples.size()," click_ms=",cpu[-1]," frame_ms=",samples[-1])
		samples.sort()
		cpu.sort()
		print(JSON.stringify({"size":size_id,"tiles":editor.document.cells.size(),"p50_frame_ms":samples[samples.size()/2],"p99_frame_ms":samples[-2],"max_frame_ms":samples[-1],"p50_click_ms":cpu[cpu.size()/2],"p99_click_ms":cpu[-2],"terrain_rebuilds":editor.view.static_batches.terrain_rebuild_count,"source_scans":editor.view.static_batches.material_scan_count}))
		var totals := {}
		for record in editor.view.capture_samples:
			var stage: String = record["stage"]
			totals[stage] = float(totals.get(stage, 0.0)) + float(record.get("ms",0.0))
		print("PROFILE ",totals)
		editor.view.capture_samples.clear()
	editor.queue_free()
	await process_frame
	quit()
