extends SceneTree
## Native rendering A/B probe. Runtime experiments only; never saves preferences.
var app
var game
var meshes: Array = []
var mesh_state: Dictionary = {}
var results: Array = []
var batches: Node3D
var configuration: Dictionary = {}
var label := "current"
var duration := 1.5
var focused := false
var seed_value := 42
var native_msaa := false
var base_msaa := Viewport.MSAA_4X
var capture_cases := false
var production := false

func _initialize() -> void:
	call_deferred("run")

func percentile(values: Array, fraction: float) -> float:
	values.sort()
	return values[mini(values.size() - 1, int(values.size() * fraction))]

func collect(node: Node) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
		mesh_state[node] = [node.visible, node.cast_shadow]
	for child in node.get_children():
		collect(child)

func is_grass(node: MeshInstance3D) -> bool:
	var parent := node.get_parent()
	if parent.name == "GrassDetail":
		parent = parent.get_parent()
	if parent.name != "Features" or not parent.get_parent().has_meta("hex"):
		return false
	var cell: Dictionary = game.view.cells[parent.get_parent().get_meta("hex")]
	return not cell.get("mountain", false) and cell["unit"] == 0 and cell["capital"] < 0 and cell["building"] == "" and not cell["tree"] and not cell["grave"] and cell.get("event", "") == ""

func make_batches(terrain_only: bool, color_batches := false, grass_only := false) -> int:
	batches = Node3D.new()
	game.view.add_child(batches)
	var groups: Dictionary = {}
	for node in meshes:
		if not node.is_visible_in_tree() or node.mesh == null:
			continue
		var material = node.material_override
		if not material is StandardMaterial3D or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var terrain: bool = node.get_parent().has_meta("surface")
		if terrain_only and not terrain:
			continue
		if grass_only and not is_grass(node):
			continue
		var colored: bool = terrain or color_batches and material.albedo_texture == null
		var key: String = str(node.mesh.get_rid()) + ":" + str(node.cast_shadow) + ":" + (str(material.shading_mode) + ":" + str(material.cull_mode) if colored else str(material.get_rid()))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(node)
	var count := 0
	for group in groups.values():
		if group.size() < 2:
			continue
		var source: MeshInstance3D = group[0]
		var instance := MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		var colored: bool = source.get_parent().has_meta("surface") or color_batches and source.material_override.albedo_texture == null
		multimesh.use_colors = colored
		multimesh.mesh = source.mesh
		multimesh.instance_count = group.size()
		for index in range(group.size()):
			multimesh.set_instance_transform(index, group[index].global_transform)
			if colored:
				multimesh.set_instance_color(index, group[index].material_override.albedo_color)
			group[index].hide()
		instance.multimesh = multimesh
		instance.cast_shadow = source.cast_shadow
		instance.material_override = source.material_override
		if colored:
			var material: StandardMaterial3D = source.material_override.duplicate()
			material.albedo_color = Color.WHITE
			material.vertex_color_use_as_albedo = true
			instance.material_override = material
		batches.add_child(instance)
		count += 1
	return count

func reset_case() -> void:
	if game.view.get("static_batches") != null:
		game.view.static_batches.set_enabled(false)
	if is_instance_valid(batches):
		batches.free()
	game.cancel_action()
	game.view.value_heatmap.set_active(false)
	game.set_process(true)
	game.view.set_process(true)
	game.view.board_root.show()
	game.view.animation_root.show()
	game.view.overlay_root.show()
	game.view.get_node("ScreenEdgeSoftening").show()
	for node in meshes:
		node.visible = mesh_state[node][0]
		node.cast_shadow = mesh_state[node][1]
	for tile in game.view.tile_nodes.values():
		tile.get_node("Features").show()
		if tile.has_node("ManaSource"):
			tile.get_node("ManaSource").show()
	root.get_node("Video").set_preference(&"background", "water", false)
	root.msaa_3d = base_msaa
	DisplayServer.window_set_size(Vector2i(1280, 820))
	game.view.sun.shadow_enabled = true
	game.view.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	game.view.focus = Vector3.ZERO
	game.view.zoom = game.view.max_zoom
	game.view.update_camera()
	game.hovered = game.NONE
	game.refresh_ui()

func configure(name_value: String) -> Dictionary:
	reset_case()
	var extra: Dictionary = {}
	if production and name_value != "legacy_renderer":
		game.view.static_batches.set_enabled(true)
		game.view.refresh_static_batches()
	match name_value:
		"close":
			game.view.zoom = 11
			game.view.focus = game.view.coord_position(game.active_capital())
			game.view.update_camera()
		"legacy_close":
			game.view.static_batches.set_enabled(false)
			game.view.zoom = 11
			game.view.focus = game.view.coord_position(game.active_capital())
			game.view.update_camera()
		"no_scripts":
			game.set_process(false)
			game.view.set_process(false)
		"no_shadows": game.view.sun.shadow_enabled = false
		"one_shadow_pass": game.view.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		"no_edge_blur": game.view.get_node("ScreenEdgeSoftening").hide()
		"no_msaa": root.msaa_3d = Viewport.MSAA_DISABLED
		"sky": root.get_node("Video").set_preference(&"background", "sky", false)
		"no_water": game.view.water.hide()
		"no_props":
			for tile in game.view.tile_nodes.values():
				tile.get_node("Features").hide()
				if tile.has_node("ManaSource"):
					tile.get_node("ManaSource").hide()
		"no_grass":
			for coord in game.view.cells:
				var cell: Dictionary = game.view.cells[coord]
				if not cell.get("mountain", false) and cell["unit"] == 0 and cell["capital"] < 0 and cell["building"] == "" and not cell["tree"] and not cell["grave"] and cell.get("event", "") == "":
					game.view.tile_nodes[coord].get_node("Features").hide()
		"no_tiny_shadows":
			for node in meshes:
				if node.mesh.get_aabb().size.length() < 0.4:
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"terrain_batches": extra["batches"] = make_batches(true)
		"opaque_batches": extra["batches"] = make_batches(false)
		"grass_batches": extra["batches"] = make_batches(false, true, true)
		"color_batches": extra["batches"] = make_batches(false, true)
		"batches_one_shadow":
			game.view.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			extra["batches"] = make_batches(false, true)
		"close_color_batches":
			game.view.zoom = 11
			game.view.focus = game.view.coord_position(game.active_capital())
			game.view.update_camera()
			extra["batches"] = make_batches(false, true)
		"hover_tile":
			root.warp_mouse(game.view.camera.unproject_position(game.view.coord_position(game.active_capital())))
		"selected":
			for coord in game.cells:
				if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] > 0:
					game.click_hex(coord)
					break
		"no_world":
			game.view.board_root.hide()
			game.view.animation_root.hide()
			game.view.overlay_root.hide()
		"half_resolution": DisplayServer.window_set_size(Vector2i(960, 620))
		"full_hd": DisplayServer.window_set_size(Vector2i(1920, 1080))
	return extra

func sample(name_value: String, round_value: int) -> void:
	var extra := configure(name_value)
	await create_timer(0.65).timeout
	var viewport := root.get_viewport_rid()
	var wall: Array = []
	var cpu: Array = []
	var gpu: Array = []
	var setup: Array = []
	var process_times: Array = []
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < duration * 1000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall.append((now - previous) / 1000.0)
		previous = now
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
		setup.append(RenderingServer.get_frame_setup_time_cpu())
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000)
	var result := {"case": name_value, "round": round_value, "frames": wall.size(), "frame_ms_p50": percentile(wall, 0.5), "frame_ms_p95": percentile(wall, 0.95), "frame_ms_p99": percentile(wall, 0.99), "fps_mean": wall.size() * 1000000.0 / (previous - started), "render_cpu_ms_p50": percentile(cpu, 0.5), "render_gpu_ms_p50": percentile(gpu, 0.5), "setup_cpu_ms_p50": percentile(setup, 0.5), "process_ms_p50": percentile(process_times, 0.5), "resolution": str(DisplayServer.window_get_size())}
	for type_value in range(3):
		var type_name: String = ["visible", "shadow", "canvas"][type_value]
		result[type_name + "_draws"] = RenderingServer.viewport_get_render_info(viewport, type_value, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		result[type_name + "_objects"] = RenderingServer.viewport_get_render_info(viewport, type_value, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		result[type_name + "_primitives"] = RenderingServer.viewport_get_render_info(viewport, type_value, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	result.merge(extra)
	results.append(result)
	print(JSON.stringify(result))
	var file := FileAccess.open("res://artifacts/render_performance_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"configuration": configuration, "results": results}, "\t"))
	file.close()
	if capture_cases and round_value == 0 and name_value in ["wide", "color_batches", "batches_one_shadow"]:
		root.get_texture().get_image().save_png("res://artifacts/render_%s_%s.png" % [label, name_value])
	root.warp_mouse(Vector2(15, 150))

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This probe requires a native window and real rendering; do not use --headless.")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
		if argument.begins_with("--seed="):
			seed_value = argument.trim_prefix("--seed=").to_int()
		if argument == "--focused":
			focused = true
		if argument == "--native-msaa":
			native_msaa = true
		if argument == "--capture":
			capture_cases = true
		if argument == "--production":
			production = true
	var video = root.get_node("Video")
	if native_msaa:
		base_msaa = video.antialiasing
	configuration = {"saved_resolution": str(video.resolution), "saved_fullscreen": video.fullscreen, "saved_msaa": video.antialiasing, "benchmark_msaa": base_msaa, "saved_shadows": video.shadows, "saved_background": video.background, "device": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info().string, "seed": seed_value, "kingdoms": 6, "size": "large"}
	video.set_preference(&"fullscreen", false, false)
	video.set_preference(&"resolution", Vector2i(1280, 820), false)
	video.set_preference(&"vsync", false, false)
	video.set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	Engine.max_fps = 0
	app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await app.start_new_game(seed_value, "large", "normal", 6)
	game = app.game
	game.view.cancel_level_transition()
	configuration["tiles"] = game.cells.size()
	configuration["menu_viewport_disabled"] = app.menus.menu_background.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
	collect(game.view.board_root)
	collect(game.view.animation_root)
	configuration["mesh_instances"] = meshes.size()
	configuration["native_shadow_mode"] = game.view.sun.directional_shadow_mode
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print(JSON.stringify(configuration))
	var cases := ["wide", "close", "no_scripts", "no_shadows", "one_shadow_pass", "no_edge_blur", "no_msaa", "sky", "no_water", "no_props", "no_grass", "no_tiny_shadows", "terrain_batches", "opaque_batches", "selected", "no_world", "half_resolution", "full_hd"]
	if focused:
		cases = ["wide", "close", "hover_tile", "grass_batches", "color_batches", "batches_one_shadow", "one_shadow_pass", "close_color_batches", "wide"]
		root.warp_mouse(Vector2(15, 150))
	if production:
		cases = ["legacy_renderer", "wide", "close", "legacy_close", "hover_tile", "selected", "one_shadow_pass", "wide"]
		root.warp_mouse(Vector2(15, 150))
	await create_timer(2.0).timeout
	for round_value in range(2):
		if round_value == 1:
			cases.reverse()
		for case_value in cases:
			await sample(case_value, round_value)
	reset_case()
	game.shutdown()
	root.get_node("Sound").stop_all()
	quit()
