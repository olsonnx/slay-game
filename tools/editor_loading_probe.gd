extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1200, 800)
	var editor = load("res://src/editor/level_editor.gd").new()
	root.add_child(editor)
	await process_frame
	editor.ui.size_choice.select(editor.Document.Sizes.IDS.find("huge"))
	for blank in [false, true, false]:
		var start := Time.get_ticks_usec()
		var last := start
		var worst := 0
		var frames := 0
		editor.new_island(blank)
		while editor.loading_map:
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxi(worst, now - last)
			last = now
			frames += 1
			if frames == 3:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://artifacts/editor-loading-cover.png")
		print("EDITOR_RELOAD blank=",blank," total_ms=",(last-start)/1000.0," frames=",frames," max_frame_ms=",worst/1000.0)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/editor-loading-finished.png")
	editor.queue_free()
	await process_frame
	quit()
