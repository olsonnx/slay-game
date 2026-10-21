extends SceneTree
## Render the viewer at the minimum supported window size.
func _initialize() -> void: call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(960, 620)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/replay_main_menu.png")
	app.open_replays()
	var viewer = app.replay_viewer
	while viewer.library_loading: await process_frame
	viewer.replay_directory = "res://artifacts/replay-viewer-tests"
	viewer.refresh_library()
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/replay_library.png")
	var data := preload("res://src/game/replay_log.gd").read_replay("res://artifacts/replay-viewer-tests/viewer-match.jsonl")
	if not viewer.finish_loading(data):
		push_error("Run test_replay_viewer.gd first to create the preview recording")
		quit(1)
		return
	while viewer.building: await process_frame
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/replay_viewer.png")
	app.free()
	await process_frame
	quit()
