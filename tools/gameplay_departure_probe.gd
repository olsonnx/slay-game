extends SceneTree
## Native rendering proof: rear gameplay land is occluded by foreground land,
## but remains visible below the physical water plane when unobstructed.
func _initialize() -> void: call_deferred("run")

func frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"level_transitions", true, false)
	video.set_preference(&"vsync", false, false)
	for background in ["water", "sky"]:
		video.set_preference(&"background", background, false)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960, 720)
		viewport.own_world_3d = true
		viewport.msaa_3d = video.antialiasing
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var view = load("res://src/rendering/board_view.gd").new()
		viewport.add_child(view)
		view.set_process(false)
		var rules = load("res://src/game/kingdom_rules.gd").new()
		var rear := Vector2i(0, -1)
		var front := Vector2i.ZERO
		rules.cells[rear] = rules.make_cell(1)
		rules.cells[front] = rules.make_cell(0)
		view.render_cells(rules.cells)
		view.pitch = 0.55
		view.yaw = 0.33
		view.zoom = 7.0
		view.focus = Vector3(0, 0, -0.3)
		view.update_camera()
		await frame()
		await frame()
		view.start_level_transition(false)
		view.island_transition.tween.pause()
		var tile: Node3D = view.tile_nodes[rear]
		var foreground: Node3D = view.tile_nodes[front]
		var home: Vector3 = view.coord_position(rear)
		view.island_transition._departing_position(1.0, tile, home + Vector3.DOWN * 0.8)
		await frame()
		await frame()
		var picture := viewport.get_texture().get_image()
		picture.save_png("res://artifacts/gameplay_drop_occluded_%s.png" % background)
		var point: Vector2 = view.camera.unproject_position(tile.global_position + Vector3.UP * 0.0105)
		var pixel := Vector2i(roundi(point.x), roundi(point.y))
		var covered := picture.get_pixelv(pixel)
		tile.hide()
		await frame()
		var without_rear := viewport.get_texture().get_image().get_pixelv(pixel)
		assert(Vector3(covered.r, covered.g, covered.b).distance_to(Vector3(without_rear.r, without_rear.g, without_rear.b)) < 0.02, "Rear tile must not draw through foreground land")
		foreground.hide()
		tile.show()
		await frame()
		picture = viewport.get_texture().get_image()
		picture.save_png("res://artifacts/gameplay_drop_unobstructed_%s.png" % background)
		var below_water := picture.get_pixelv(pixel)
		tile.hide()
		await frame()
		var backdrop := viewport.get_texture().get_image().get_pixelv(pixel)
		assert(tile.position.y < view.water.position.y)
		assert(Vector3(below_water.r, below_water.g, below_water.b).distance_to(Vector3(backdrop.r, backdrop.g, backdrop.b)) > 0.1, "Water must not swallow unobstructed falling land")
		print("%s: foreground occludes rear gameplay tile; below-water fall remains visible" % background)
		view.cancel_level_transition()
		viewport.queue_free()
		await process_frame
	print("Gameplay departure native checks passed")
	quit()
