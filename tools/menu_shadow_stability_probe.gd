extends SceneTree
## Track the same clear tile surfaces over an identical moving-camera trace.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var video = root.get_node("Video")
	var saved := {"shadows": video.shadows, "vsync": video.vsync}
	video.set_preference(&"shadows", true, false)
	video.set_preference(&"vsync", false, false)
	var reports: Array = []
	for legacy in [true, false]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 820)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		viewport.msaa_3d = video.antialiasing
		root.add_child(viewport)
		var map = load("res://src/rendering/decorative_map.gd").new()
		map.initial_seed = 42
		viewport.add_child(map)
		map.active = true
		map.layout_camera(1280.0 / 820.0)
		if legacy:
			map.sun.directional_shadow_pancake_size = 20.0
			map.sun.directional_shadow_fade_start = 0.8
			map.sun.shadow_bias = 0.1
			map.sun.shadow_normal_bias = 2.0
			map.sun.shadow_reverse_cull_face = false
			map.camera.near = 0.05
			map.camera.far = 4000.0
		var points: Array = []
		for slot in map.slots.values():
			var cell: Dictionary = slot["cell"]
			var at: Vector3 = slot["node"].global_position
			if absf(at.x) < 8 and at.z > -5 and at.z < 0 and cell["land"] and not cell["tree"] and not cell["mountain"] and cell["capital"] < 0:
				points.append(slot["node"])
		for frame in range(10):
			await process_frame
			await RenderingServer.frame_post_draw
		var previous: Array[float] = []
		var max_change := 0.0
		var changes := 0.0
		var count := 0
		for frame in range(121):
			await process_frame
			map.advance(0.05)
			await RenderingServer.frame_post_draw
			var picture: Image = viewport.get_texture().get_image()
			var values: Array[float] = []
			for tile in points:
				var pixel: Vector2 = map.camera.unproject_position(tile.global_position + Vector3(0, 0.015, -0.40))
				var color := picture.get_pixel(clampi(roundi(pixel.x), 0, 1279), clampi(roundi(pixel.y), 0, 819))
				values.append(color.get_luminance())
			if not previous.is_empty():
				for index in range(values.size()):
					var change := absf(values[index] - previous[index])
					max_change = maxf(max_change, change)
					changes += change
					count += 1
			previous = values
			if frame in [40, 80, 120]:
				picture.save_png("res://artifacts/menu_shadow_stability_%s_%d.png" % ["before" if legacy else "after", frame])
		reports.append({"legacy": legacy, "points": points.size(), "mean_luminance_step": changes / maxi(1, count), "max_luminance_step": max_change})
		viewport.queue_free()
		await process_frame
	for key in saved:
		video.set_preference(key, saved[key], false)
	FileAccess.open("res://artifacts/menu_shadow_stability.json", FileAccess.WRITE).store_string(JSON.stringify(reports, "\t"))
	print(JSON.stringify(reports))
	quit()
