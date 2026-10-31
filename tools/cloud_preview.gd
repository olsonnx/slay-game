extends SceneTree
func _initialize() -> void: call_deferred("run")
func difference(a: Color,b: Color) -> float:
	return maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
func draw_frames(count := 3) -> void:
	for frame in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"reduced_motion",true,false)
	video.set_preference(&"depth_of_field",false,false)
	video.set_preference(&"vsync",false,false)
	video.set_preference(&"background_frame_limit",0,false)
	root.get_node("Sound").set_muted(true,false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_map_size = "very_large"
	game.initial_kingdom_count = 6
	root.add_child(game)
	game.set_process(false)
	game.hud.ui_root.hide()
	game.view.birds.set_loading(true)
	var board = game.view
	var clouds = board.clouds
	await clouds.prepare()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	RenderingServer.viewport_set_measure_render_time(clouds.viewport.get_viewport_rid(),true)
	var results := []
	var renderer := RenderingServer.get_current_rendering_method()
	for background in ["water","sky"]:
		video.set_preference(&"background",background,false)
		for pose in ["overview","overhead","oblique"]:
			board.focus = board.map_center
			board.zoom = 100.0
			board.yaw = 1.25 if pose == "oblique" else 0.0 if pose == "overhead" else 0.18
			board.pitch = 0.60 if pose == "oblique" else 1.569 if pose == "overhead" else 0.92
			board.update_camera()
			clouds.enabled = false
			await draw_frames()
			var before := root.get_texture().get_image()
			clouds.enabled = true
			await draw_frames(5)
			var after := root.get_texture().get_image()
			after.save_png("res://artifacts/clouds-%s-%s-%s.png" % [renderer,background,pose])
			var still_volume: Image = clouds.viewport.get_texture().get_image()
			video.set_preference(&"reduced_motion",false,false)
			clouds._process(20.0)
			video.set_preference(&"reduced_motion",true,false)
			await draw_frames(3)
			var moved_volume: Image = clouds.viewport.get_texture().get_image()
			var moved_pixels := 0
			for y in range(0,moved_volume.get_height(),8):
				for x in range(0,moved_volume.get_width(),8):
					if difference(still_volume.get_pixel(x,y),moved_volume.get_pixel(x,y)) > 0.03: moved_pixels += 1
			var checked := 0
			var obscured := 0
			var cloud_pixels := 0
			var total_pixels := 0
			for y in range(0,after.get_height(),8):
				for x in range(0,after.get_width(),8):
					total_pixels += 1
					if difference(before.get_pixel(x,y),after.get_pixel(x,y)) > 0.08: cloud_pixels += 1
			for coord in board.cells:
				var cell: Dictionary = board.cells[coord]
				if cell.unit > 0 or cell.tree or cell.mountain or cell.building != "" or cell.capital >= 0 or cell.event != "" or cell.get("animal","") != "": continue
				var point: Vector2 = board.camera.unproject_position(board.coord_position(coord)+Vector3(0,0.05,0))
				if not Rect2(Vector2(5,5),Vector2(after.get_size())-Vector2(10,10)).has_point(point): continue
				checked += 1
				if difference(before.get_pixelv(Vector2i(point)),after.get_pixelv(Vector2i(point))) > 0.02: obscured += 1
			await draw_frames(12)
			var gpu := []
			for frame in range(20):
				await draw_frames(1)
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())+RenderingServer.viewport_get_measured_render_time_gpu(clouds.viewport.get_viewport_rid()))
			gpu.sort()
			var enabled_gpu: float = gpu[gpu.size()/2]
			clouds.enabled = false
			await draw_frames(12)
			gpu.clear()
			for frame in range(20):
				await draw_frames(1)
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			gpu.sort()
			var baseline_gpu: float = gpu[gpu.size()/2]
			var cloud_fraction := float(cloud_pixels)/total_pixels
			var row := {"background":background,"pose":pose,"tiles_checked":checked,"tiles_obscured":obscured,"cloud_fraction":cloud_fraction,"drift_pixels_changed":moved_pixels,"gpu_with_clouds_ms":enabled_gpu,"gpu_without_clouds_ms":baseline_gpu,"volume_size":str(clouds.viewport.size)}
			results.append(row)
			print(row)
	FileAccess.open("res://artifacts/cloud-preview-%s-results.json" % renderer,FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	await process_frame
	var failures := results.filter(func(row): return row.tiles_obscured > 0 or row.cloud_fraction < 0.02 or row.drift_pixels_changed < 20).size()
	print("Cloud render checks: %d passed, %d failed" % [results.size()-failures,failures])
	quit(1 if failures else 0)
