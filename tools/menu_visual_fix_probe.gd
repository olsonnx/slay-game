extends SceneTree
## Seeded close-ups of a joined rim and a tile dropping behind foreground land.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"vsync", false, false)
	video.set_preference(&"internal_borders", 0.0, false)
	for background in ["sky", "water"]:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 720)
		viewport.own_world_3d = true
		viewport.msaa_3d = video.antialiasing
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var map = load("res://src/rendering/decorative_map.gd").new()
		map.initial_seed = 42
		viewport.add_child(map)
		map.water.visible = background == "water"
		map.environment.background_color = Color("213b45") if map.water.visible else Color("172e39")
		var selected_id := -1
		for id in map.slots:
			var slot: Dictionary = map.slots[id]
			if slot["state"] == "settled" and slot["joined_mask"] & (1 << 5) and absf(slot["node"].global_position.z) < 6:
				selected_id = id
				break
		assert(selected_id >= 0)
		var selected: Dictionary = map.slots[selected_id]
		var focus: Vector3 = selected["node"].global_position + Vector3(0.3, 0, 0.6)
		map.camera.size = 6.0
		var direction := Vector3(sin(0.33) * cos(0.55), sin(0.55), cos(0.33) * cos(0.55))
		map.camera.position = focus + direction * 52
		map.camera.look_at(focus, Vector3.UP)
		for tick in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://artifacts/menu_rim_fixed_%s.png" % background)
		selected["state"] = "leaving"
		selected["time"] = 0.0
		map.sync_menu_batches()
		for frame in range(61):
			map.advance_tile(selected_id, 22.0, selected["exit_duration"] / 60.0)
			await process_frame
			await RenderingServer.frame_post_draw
			if frame in [5, 15, 30]:
				viewport.get_texture().get_image().save_png("res://artifacts/menu_drop_fixed_%s_%d.png" % [background, frame])
		# Isolate the same departure to check that water is not a depth barrier.
		map.static_batches.set_suspended(true)
		for slot in map.slots.values():
			slot["node"].hide()
		selected["state"] = "leaving"
		selected["time"] = 0.0
		selected["node"].position = selected["base"]
		for frame in range(21):
			map.advance_tile(selected_id, 22.0, selected["exit_duration"] / 60.0)
			await process_frame
			await RenderingServer.frame_post_draw
		var point: Vector2 = map.camera.unproject_position(selected["node"].global_position + Vector3(0, 0.0105, 0))
		var picture: Image = viewport.get_texture().get_image()
		picture.save_png("res://artifacts/menu_drop_unobstructed_%s.png" % background)
		var tile_color := picture.get_pixel(roundi(point.x), roundi(point.y))
		selected["node"].hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var backdrop_color := viewport.get_texture().get_image().get_pixel(roundi(point.x), roundi(point.y))
		assert(selected["node"].position.y < map.water.position.y)
		assert(Vector3(tile_color.r, tile_color.g, tile_color.b).distance_to(Vector3(backdrop_color.r, backdrop_color.g, backdrop_color.b)) > 0.1)
		print("%s: below-water departure remains visibly rendered until screen exit" % background)
		viewport.queue_free()
		await process_frame
	print("Menu close-ups captured for Water and Sky")
	quit()
