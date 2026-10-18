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
	var map = load("res://src/rendering/decorative_map.gd").new()
	map.initial_seed = 42
	root.add_child(map)
	map.active = true
	expect(map.water.material_override.get_shader_parameter("backdrop_depth") == true, "Menu water stays behind departing tiles instead of swallowing their fall")
	# Departure must go below/behind foreground land, never slide toward it.
	var falling_id: int = -1
	for id in map.slots:
		if map.slots[id]["state"] == "settled" and map.slots[id]["cell"]["land"]:
			falling_id = id
			break
	var falling: Dictionary = map.slots[falling_id]
	var base: Vector3 = falling["base"]
	for camera_time in [0.0, 10.0, 30.0]:
		map.camera_time = camera_time
		map.update_cinematic_camera()
		falling["state"] = "leaving"
		falling["time"] = 0.0
		falling["node"].position = base
		var depth_before: float = -map.camera.to_local(falling["node"].global_position).z
		map.advance_tile(falling_id, 22.0, falling["exit_duration"] * 0.25)
		var position: Vector3 = falling["node"].position
		expect(is_equal_approx(position.x, base.x) and is_equal_approx(position.z, base.z) and position.y < base.y, "Departing tile falls vertically without crossing a neighbour's footprint")
		expect(-map.camera.to_local(falling["node"].global_position).z > depth_before, "Departing tile moves deeper into the scene throughout the menu orbit")
		# Sample just before completion; hiding/resetting must happen offscreen.
		falling["state"] = "leaving"
		falling["time"] = falling["exit_duration"] * 0.99
		map.advance_tile(falling_id, 22.0, 0.0)
		var highest_point: Vector3 = falling["node"].global_position + Vector3.UP * 3.0
		expect(map.camera.global_basis.y.dot(highest_point - map.camera.global_position) < -map.camera.size * 0.5, "Departing tile and tall props clear the bottom before the source is hidden")
	falling["state"] = "settled"
	falling["node"].position = base
	map.motions.erase(falling_id)
	map.visible_kingdom_joins = true
	map.sync_menu_batches()
	var manager = map.static_batches
	expect(manager.cache_sources and manager.mute_source_notifications, "Menu enables retained source records and suppresses duplicate notifications")
	var instances := 0
	for chunk in manager.chunks.values():
		for render in chunk["root"].get_children():
			instances += render.multimesh.instance_count
	expect(instances == manager.instance_count, "Each settled menu source has exactly one batch instance")
	var selected: Dictionary = {}
	var neighbor: Dictionary = {}
	var join_edge := -1
	var grid = load("res://src/game/hex_grid.gd")
	for slot in map.slots.values():
		if slot["state"] != "settled" or slot["joined_mask"] == 0:
			continue
		for edge in range(6):
			if slot["joined_mask"] & (1 << edge):
				for other in map.slots.values():
					if other["coord"] == slot["coord"] + grid.DIRECTIONS[edge]:
						selected = slot
						neighbor = other
						join_edge = edge
						break
		if join_edge >= 0:
			break
	expect(join_edge >= 0, "Seeded fixture contains joined kingdom tiles")
	neighbor["state"] = "leaving"
	map.sync_menu_batches()
	expect(selected["joined_mask"] & (1 << join_edge) == 0, "A departing neighbor immediately restores the exposed kingdom rim")
	expect(neighbor["joined_mask"] == 0, "Detached animated tile receives an outer rim on every edge")
	neighbor["state"] = "settled"
	map.sync_menu_batches()
	expect(selected["joined_mask"] & (1 << join_edge) != 0, "Returning settled neighbor restores the shared kingdom edge")
	for step in range(310):
		map.advance(0.75)
		if step % 10 == 0:
			for data in manager.tile_records.values():
				if data["records"].is_empty():
					continue
				var record: Array = data["records"][0]
				expect((manager.global_transform * record[3]).is_equal_approx(record[0].global_transform), "Batched geometry follows the same position as its logical source through scrolling/recycling")
			for record in manager.suppressed.values():
				expect(not record[0].is_transform_notification_enabled() and record[0].layers == 0, "Suppressed opaque parts do not submit redundant scrolling transforms")
			for slot in map.slots.values():
				if slot["state"] in ["entering", "leaving"] and slot["cell"]["land"]:
					expect(slot["node"].get_meta("surface").layers == 1 and slot["node"].get_meta("surface").is_transform_notification_enabled(), "Entering/leaving tiles restore their original animated renderer")
			await process_frame
	expect(map.batch_origin_step > 0 and manager.position.z < 180, "Long-running scrolling rebases before coordinates lose precision")
	expect(map.slots.size() == map.ROW_COUNT * (map.HALF_COLUMNS * 2 + 1), "Recycling keeps a fixed tile pool")
	var before: int = manager.rebuild_count
	map.sync_menu_batches(false)
	expect(manager.rebuild_count == before, "Unchanged membership keeps chunk resources")
	var video = root.get_node("Video")
	var original: float = video.internal_borders
	for value in [0.0, 1.0, 0.5]:
		video.set_preference(&"internal_borders", value, false)
		map.apply_background()
		expect(is_equal_approx(map.internal_border_visibility, value) and manager.instance_count > 0, "Live border changes refresh shared geometry and cached source parts")
	video.set_preference(&"internal_borders", original, false)
	map.queue_free()
	await process_frame
	print("Menu rendering checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
