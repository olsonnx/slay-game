extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	var video = root.get_node("Video")
	video.set_preference(&"level_transitions", true, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_map_size = "large"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var view = game.view
	var before: Dictionary = game.cells.duplicate(true)
	for arriving in [true, false]:
		var retained_rebuilds: int = view.static_batches.terrain_rebuild_count
		view.start_level_transition(arriving)
		var batches = view.island_transition.moving_batches
		expect(batches != null and batches.source_count > 100, "Island animation batches the original moving scenery")
		expect(batches.groups.size() < batches.source_count / 2, "Moving scenery shares substantially fewer rendering groups than source meshes")
		var hidden := true
		for saved in batches.sources:
			hidden = hidden and saved[0].get_ref().layers == 0
		expect(hidden, "Source meshes are suppressed while their moving copies render")
		var tile: Node3D = batches.tile_slots.keys()[0]
		var start: Vector3 = tile.position
		await create_timer(0.3).timeout
		batches.update_transforms()
		expect(tile.position != start, "Each source tile keeps its individual animated position")
		expect(batches.previous_transforms[tile] == tile.transform and batches.transform_updates > 0, "Moving tile transforms are uploaded after each pose change")
		# The dummy headless renderer does not retain GPU buffers for readback.
		if DisplayServer.get_name() != "headless":
			var aligned := true
			for slot in batches.tile_slots[tile]:
				var actual: Transform3D = view.board_root.global_transform * slot[0].get_instance_transform(slot[1])
				var expected: Transform3D = tile.global_transform * slot[2]
				aligned = aligned and actual.is_equal_approx(expected)
			expect(aligned, "GPU instances follow the tile's exact post-tween transform")

		if "--preview" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/transition-batched-%s.png" % ("entrance" if arriving else "departure"))
		paused = true
		var frozen: Transform3D = tile.transform
		var updates: int = batches.transform_updates
		await create_timer(0.1, true).timeout
		batches.update_transforms()
		expect(tile.transform == frozen and batches.transform_updates == updates, "Pausing freezes tile motion and avoids redundant instance uploads")
		paused = false
		view.cancel_level_transition()
		expect(view.island_transition.moving_batches == null and not view.static_batches.suspended and view.static_batches.visible, "Cancelling releases transient batches and restores settled batching")
		expect(view.static_batches.terrain_rebuild_count == retained_rebuilds and view.static_batches.instance_count > 100, "Completion retains merged terrain uploads and suppresses their original meshes")
		var at_home := true
		for coord in view.tile_nodes: at_home = at_home and view.tile_nodes[coord].position == view.coord_position(coord)
		expect(at_home and game.cells == before, "Cancellation restores exact tile positions without changing gameplay")
		await process_frame
		expect(not is_instance_valid(batches), "Transient scenery and frame callbacks retire cleanly")
	var before_finish: int = view.static_batches.terrain_rebuild_count
	view.start_level_transition(true)
	while view.level_transitioning: await process_frame
	expect(view.static_batches.terrain_rebuild_count == before_finish and view.static_batches.instance_count > 100, "Normal animation completion reuses settled uploads and leaves source meshes suppressed")
	var old_borders: float = video.internal_borders
	view.start_level_transition(true)
	video.set_preference(&"internal_borders", 0.5 if old_borders != 0.5 else 0.25, false)
	view.cancel_level_transition()
	expect(view.static_batches.terrain_rebuild_count > before_finish, "A border-setting change during animation still rebuilds the affected settled geometry")
	video.set_preference(&"internal_borders", old_borders, false)
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Transition batching checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
