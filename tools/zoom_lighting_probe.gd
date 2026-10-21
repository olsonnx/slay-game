extends SceneTree
const Snapshot = preload("res://src/game/state_snapshot.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	if not ok: failures += 1; push_error(message)
func percentile(values: Array, fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size()-1,int(sorted.size()*fraction))]
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	var video = root.get_node("Video")
	video.set_preference(&"level_transitions",false,false)
	video.set_preference(&"atmospheric_lighting",true,false)
	video.set_preference(&"vsync",false,false)
	Engine.max_fps = 0
	root.get_node("Sound").set_muted(true,false)
	var cover = preload("res://src/ui/preparation_screen.gd").new()
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 71
	root.add_child(game)
	root.add_child(cover)
	game.set_process(false)
	await process_frame
	await RenderingServer.frame_post_draw
	game.view.birds.set_process(false)
	game.view.unit_presentation.set_process(false)
	game.view.wildlife.set_process(false)
	game.view.focus = game.view.coord_position(game.rules.kingdoms.keys()[0])
	game.view.zoom = 34
	game.view.update_camera()
	var saved := Snapshot.capture(game.rules)
	var focus: Vector3 = game.view.focus
	var zoom: float = game.view.zoom
	var rebuilds: int = game.view.static_batches.rebuild_count
	var uploads: int = game.view.unit_batches.upload_count
	var started := Time.get_ticks_usec()
	await game.view.lighting.warmup()
	var warmup_ms := (Time.get_ticks_usec()-started)/1000.0
	var expected_passes := 3 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0
	expect(game.view.lighting.warmup_passes == expected_passes,"Only Compatibility needs the covered manual light-variant warm-up")
	expect(game.view.focus == focus and game.view.zoom == zoom,"Warm-up restores the camera exactly")
	await cover.reveal()
	var samples: Array = []
	var prefix := "zoom-lighting" if RenderingServer.get_current_rendering_method() == "gl_compatibility" else "forward-zoom-lighting"
	for repetition in range(2):
		var frames: Array = []
		var previous := Time.get_ticks_usec()
		for index in range(180):
			var amount := float(index%90)/89.0
			game.view.zoom = lerpf(34,12,amount) if index < 90 else lerpf(12,64,amount)
			game.view.update_camera()
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			frames.append((now-previous)/1000.0)
			previous = now
			if repetition == 0 and index in [89,179]:
				root.get_texture().get_image().save_png("res://artifacts/%s-%s.png" % [prefix,"close" if index == 89 else "overview"])
				previous = Time.get_ticks_usec()
				expect(game.view.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,"Native zoom keeps one shadow projection")
		var peak_index := frames.find(frames.max())
		var row := {"pass":repetition,"median_ms":percentile(frames,0.5),"p95_ms":percentile(frames,0.95),"maximum_ms":frames.max(),"peak_frame":peak_index,"frames_ms":frames}
		samples.append(row)
		print("Zoom pass %d: median %.3f ms, p95 %.3f ms, maximum %.3f ms (frame %d)" % [repetition,row.median_ms,row.p95_ms,row.maximum_ms,peak_index])
	expect(Snapshot.capture(game.rules) == saved,"Native warm-up and zoom preserve gameplay and RNG")
	expect(game.view.static_batches.rebuild_count == rebuilds and game.view.unit_batches.upload_count == uploads,"Warm-up and zoom keep retained buffers intact")
	var file := FileAccess.open("res://artifacts/%s.json" % prefix,FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"warmup_ms":warmup_ms,"samples":samples,"failures":failures},"\t"))
	print("Native zoom checks: %s" % ("passed" if failures == 0 else "failed"))
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit(1 if failures else 0)
