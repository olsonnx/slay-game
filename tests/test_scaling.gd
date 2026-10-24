extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Picker = preload("res://src/rendering/board_picker.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func digest(rules) -> String:
	var coords: Array = rules.cells.keys()
	coords.sort_custom(func(a, b): return a.x < b.x if a.x != b.x else a.y < b.y)
	var state: Array = []
	for coord in coords:
		state.append([str(coord), rules.cells[coord]])
	state.append(rules.kingdoms)
	state.append(str(rules.rng.state))
	return JSON.stringify(state).sha256_text()

func run() -> void:
	# Pin the event lottery that produced these v13 generator baselines.
	# The editable event pack has separate distribution/runtime coverage.
	var event_weights: Dictionary = Rules.Events.WEIGHTS.duplicate()
	Rules.Events.WEIGHTS.assign(Rules.Events.BUILTIN_WEIGHTS)
	var golden: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/generation_golden.json"))
	for sample in golden:
		var rules = Rules.new()
		rules.rule_mode = sample["mode"]
		rules.generate(int(sample["seed"]), sample["size"], int(sample["count"]))
		expect(sample.get("generation_version") == Rules.MapGenerator.GENERATION_VERSION and digest(rules) == sample["digest"], "Current generation preserves its recorded seeded state and RNG")
	Rules.Events.WEIGHTS.assign(event_weights)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_rule_mode = "modern"
	game.initial_map_size = "large"
	game.initial_kingdom_count = 6
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var board = game.view
	for pitch_value in [0.44, 0.92, 1.56]:
		for yaw_value in [0.0, 1.2, 3.0]:
			board.pitch = pitch_value
			board.yaw = yaw_value
			board.update_camera()
			for x in range(150, 1150, 80):
				for y in range(100, 740, 80):
					var screen := Vector2(x, y)
					expect(Picker.pick_at_screen(board, screen) == Picker.pick_at_screen(board, screen, false, true), "Local broad phase agrees with exhaustive ray and sprite picking")
	var triangles := 0
	var bottom_vertices := 0
	for chunk in board.static_batches.chunks.values():
		for key in chunk["batches"]:
			if not key.begins_with("terrain:"):
				continue
			var render: MultiMeshInstance3D = chunk["batches"][key]
			var vertices: PackedVector3Array = render.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			triangles += vertices.size() / 3
			for vertex in vertices:
				bottom_vertices += int(is_equal_approx(vertex.y, -0.56))
	var exposed := 0
	for coord in board.cells:
		for direction in Rules.DIRECTIONS:
			if not board.cells.has(coord + direction):
				exposed += 1
	expect(triangles < board.cells.size() * 48, "Merged terrain removes redundant triangle work")
	expect(bottom_vertices == exposed * 3, "Only exposed cliff sides reach the soil bottom, including across chunks")
	board.zoom = 22
	board.update_camera()
	board.lighting.advance(1.0)
	await process_frame
	expect(board.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "Close view uses a stable shadow projection")
	var near_instances: int = board.static_batches.visible_instance_count
	for tile in board.tile_nodes.values():
		expect(not tile.has_node("Features/GrassDetail"), "Grass and pebbles are no longer generated")
	board.zoom = 64
	board.update_camera()
	var original_opacity: float = board.sun.shadow_opacity
	board.lighting.advance(0.025)
	expect(board.sun.shadow_opacity < original_opacity and board.sun.shadow_opacity > board.lighting.shadow_target, "Distant shadows ease toward their reduced strength")
	expect(board.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL and board.static_batches.visible_instance_count == near_instances, "Zoom never switches shadow projection or prop visibility")
	var opacity: float = board.sun.shadow_opacity
	board.zoom = 22
	board.update_camera()
	expect(board.sun.shadow_opacity == opacity, "Reversing zoom does not jump shadow strength")
	board.lighting.advance(1.0)
	expect(is_equal_approx(board.sun.shadow_opacity,1.0), "Close shadows regain full strength")
	board.value_heatmap.set_active(true)
	board.value_heatmap.set_active(false)
	await process_frame
	expect(board.static_batches.visible_instance_count == near_instances, "Heatmap restores the retained props")
	var rebuilds: int = board.static_batches.rebuild_count
	var syncs: int = board.static_batches.sync_count
	var terrain_meshes: Array = []
	for chunk in board.static_batches.chunks.values():
		for key in chunk["batches"]:
			if key.begins_with("terrain:"):
				terrain_meshes.append(chunk["batches"][key].multimesh.mesh)
	for cycle in range(100):
		for camera_zoom in [22, 40, 64, 34, 30]:
			board.zoom = camera_zoom
			board.update_camera()
	board.static_batches.advance_detail_fade(1.0)
	await process_frame
	expect(board.static_batches.rebuild_count == rebuilds and board.static_batches.sync_count == syncs, "Repeated zoom thresholds never synchronize or rebuild static chunks")
	var meshes_after: Array = []
	for chunk in board.static_batches.chunks.values():
		for key in chunk["batches"]:
			if key.begins_with("terrain:"):
				meshes_after.append(chunk["batches"][key].multimesh.mesh)
	expect(terrain_meshes == meshes_after, "Zoom spam retains the exact terrain mesh resources")
	expect(board.static_batches.visible_instance_count == near_instances, "Zoom spam restores every visible source without duplicates")
	board.zoom = 64
	board.update_camera()
	board.static_batches.advance_detail_fade(1.0)
	board.static_batches.set_enabled(false)
	for entry in board.static_batches.detail_sources.values():
		var detail: MeshInstance3D = entry[0].get_ref()
		expect(detail.layers == 0, "Fallback keeps distant grass hidden")
	board.zoom = 22
	board.update_camera()
	board.static_batches.advance_detail_fade(0.055)
	for entry in board.static_batches.detail_sources.values():
		var detail: MeshInstance3D = entry[0].get_ref()
		expect(is_equal_approx(detail.material_override.albedo_color.a, board.static_batches.detail_alpha), "Fallback sources share the current intermediate fade opacity")
	board.static_batches.advance_detail_fade(1.0)
	for entry in board.static_batches.detail_sources.values():
		var detail: MeshInstance3D = entry[0].get_ref()
		expect(detail.layers == entry[1], "Fallback restores grass layers when zooming close")
	board.static_batches.set_enabled(true)
	board.refresh_static_batches()
	expect(board.static_batches.visible_instance_count == near_instances, "Reenabled batches preserve LOD and restore every visible detail exactly once")
	board.static_batches.set_suspended(true)
	board.zoom = 64
	board.update_camera()
	board.static_batches.advance_detail_fade(1.0)
	for entry in board.static_batches.detail_sources.values():
		var detail: MeshInstance3D = entry[0].get_ref()
		expect(detail.layers == 0, "Animated-source fallback also respects distant detail LOD")
	board.static_batches.set_suspended(false)
	board.refresh_static_batches()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	# Stopped Ogg playbacks release their decoder on the audio mixing thread.
	await create_timer(1.1).timeout
	print("Map scaling checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
