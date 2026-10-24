extends SceneTree
## Native replay-menu pacing with VSync disabled and an uncapped application.
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
	var video = root.get_node("Video")
	video.set_preference(&"vsync", false, false)
	Engine.max_fps = 0
	process_frame.connect(sample)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await create_timer(0.5).timeout
	app.open_replays()
	var viewer = app.replay_viewer
	while viewer.library_loading: await process_frame
	if "--uncapped" in OS.get_cmdline_user_args(): Engine.max_fps = 0
	await create_timer(0.5).timeout
	previous = 0
	sampling = true
	var started := Time.get_ticks_usec()
	for tick in range(15):
		if viewer.list.item_count > 0:
			var index: int = tick % viewer.list.item_count
			viewer.list.select(index)
			viewer.select_recording(index)
			var motion := InputEventMouseMotion.new()
			motion.position = viewer.list.global_position + viewer.list.get_item_rect(index).get_center()
			root.push_input(motion)
		await create_timer(0.2).timeout
	sampling = false
	var wall_sec := (Time.get_ticks_usec() - started) / 1000000.0
	gaps.sort()
	print(JSON.stringify({"max_fps":Engine.max_fps,"vsync":video.vsync,"frames":gaps.size(),"average_fps":gaps.size()/wall_sec,"p99_frame_ms":gaps[mini(gaps.size()-1,int(gaps.size()*0.99))],"max_frame_ms":gaps[-1],"loaded_replay_on_selection":viewer.view != null}))
	app.free()
	print("Restored application FPS limit: ", Engine.max_fps)
	await process_frame
	quit()
