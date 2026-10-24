extends SceneTree
## Reproducible animation frames for the scrolling menu; no saved preferences.

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(960, 620)
	root.get_node("Video").set_preference(&"background", "water", false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	var background = app.menus.menu_background
	background.set_process(false)
	app.menus.set_process_unhandled_input(false)
	DirAccess.make_dir_recursive_absolute("res://artifacts/menu_scroll_frames")
	for frame in range(144):
		background.map.advance(1.0 / 12.0)
		background.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		picture.save_png("res://artifacts/menu_scroll_frames/frame_%04d.png" % frame)
		if frame == 60:
			picture.save_png("res://artifacts/menu_scroll_preview.png")
	root.get_node("Sound").stop_all()
	quit()
