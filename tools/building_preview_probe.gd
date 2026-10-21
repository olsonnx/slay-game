extends SceneTree
var game
func _initialize() -> void: call_deferred("run")
func pipelines() -> Array:
	var result := []
	for counter in [Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW]: result.append(Performance.get_monitor(counter))
	return result
func run() -> void:
	var label := "check"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	root.size = Vector2i(1100,760)
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Video").set_preference(&"vsync", false, false)
	Engine.max_fps = 0
	game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	game.view.controls_enabled = false
	game.view.cancel_level_transition()
	var sites := []
	for coord in game.cells:
		if game.cells[coord]["owner"] == 0 and game.cells[coord]["capital"] < 0: sites.append(coord)
	game.view.zoom = 9
	game.view.focus = game.view.coord_position(sites[0])
	game.view.update_camera()
	await create_timer(0.8).timeout
	var records := []
	for kind in ["tower","house","bridge"]:
		for step in range(8):
			var before := pipelines()
			var start := Time.get_ticks_usec()
			var coord: Vector2i = sites[step % sites.size()]
			game.view.show_overlays(game.NONE,coord,{},[],game.NONE,{"kind":kind,"valid":true})
			var cpu_ms := (Time.get_ticks_usec()-start)/1000.0
			await RenderingServer.frame_post_draw
			var row := {"kind":kind,"step":step,"cpu_ms":cpu_ms,"frame_ms":(Time.get_ticks_usec()-start)/1000.0,"pipelines_before":before,"pipelines_after":pipelines()}
			records.append(row)
	game.view.show_overlays(game.NONE,game.NONE,{},[],game.NONE)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/building-preview-%s.png" % label)
	var file := FileAccess.open("res://artifacts/building-preview-%s.json" % label,FileAccess.WRITE)
	file.store_string(JSON.stringify(records,"\t"))
	print(JSON.stringify(records))
	game.shutdown()
	game.queue_free()
	await process_frame
	quit()
