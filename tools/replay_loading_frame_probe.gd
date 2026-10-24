extends SceneTree
## Native rendering probe: menu entry, loading, hover and spectator disposal.
var gaps: Array[float] = []
var previous := 0
var sampling := false
func _initialize() -> void: call_deferred("run")
func sample() -> void:
	var now := Time.get_ticks_usec()
	if sampling and previous > 0: gaps.append((now - previous) / 1000.0)
	previous = now
func run() -> void:
	root.size = Vector2i(960, 620)
	process_frame.connect(sample)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await create_timer(0.5).timeout
	var started := Time.get_ticks_usec()
	app.open_replays()
	var entry_ms := (Time.get_ticks_usec() - started) / 1000.0
	var viewer = app.replay_viewer
	while viewer.library_loading: await process_frame
	if viewer.paths.is_empty():
		push_error("This probe needs saved recordings in the selected user directory")
		app.free()
		quit(1)
		return
	viewer.list.select(0)
	viewer.select_recording(0)
	while viewer.metadata_worker != null: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/replay-rebuilt-library.png")
	previous = 0
	sampling = true
	started = Time.get_ticks_usec()
	viewer.load_recording(viewer.paths[0])
	while viewer.worker != null or viewer.building: await process_frame
	var load_ms := (Time.get_ticks_usec() - started) / 1000.0
	await create_timer(0.3).timeout
	sampling = false
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/replay-rebuilt-viewer.png")
	var worst := 0.0
	for gap in gaps: worst = maxf(worst, gap)
	print(JSON.stringify({"entry_ms":entry_ms,"load_wall_ms":load_ms,"worst_loading_frame_ms":worst,"frames":gaps.size(),"steps":viewer.timeline.steps.size(),"tiles":viewer.view.cells.size(),"timings":viewer.loading_timings}))
	app.free()
	await process_frame
	quit()
