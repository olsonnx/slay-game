extends SceneTree
## Native benchmark only. Production algorithms are copied by prepare_map_stress.ps1.
const StressRules = preload("res://artifacts/map_stress_source/kingdom_rules.gd")
const StressSizes = preload("res://artifacts/map_stress_source/map_sizes.gd")
var app
var game
var results: Array = []
var sizes := [210, 500, 1000, 2000, 4000]
var seeds := [42, 71]
var cases := ["wide", "orbit"]
var duration := 5.0
var label := "sweep"
var config: Dictionary
var live_quality := false

func _initialize() -> void:
	call_deferred("run")

func percentile(values: Array, fraction: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, ceili(sorted.size() * fraction) - 1)]

static func profile(target: int) -> Dictionary:
	var scale := sqrt(float(target) / 210.0)
	return {"name": "Stress", "bounds": Vector2(24, 15.5) * scale,
		"min_factions": 6, "max_factions": 6, "radius_min": maxi(4, roundi(4 * scale)),
		"radius_max": maxi(5, roundi(5 * scale)), "core": maxi(2, roundi(2 * scale)),
		"min_land": target, "zoom": 38 * scale, "mountain_groups": maxi(6, roundi(6 * scale * scale))}

func persist() -> void:
	var file := FileAccess.open("res://artifacts/map_stress_%s.json" % label, FileAccess.WRITE)
	file.store_string(JSON.stringify({"configuration": config, "results": results}, "\t"))

func sample(case_name: String, info: Dictionary) -> void:
	game.cancel_action()
	game.view.focus = Vector3.ZERO
	game.view.pitch = 0.82
	game.view.yaw = 0.35
	game.view.rotating = case_name == "rotate"
	game.view.zoom = info["overview_zoom"]
	if not live_quality:
		game.view.sun.directional_shadow_max_distance = 75
		game.view.sun.shadow_enabled = true
		game.view.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		game.view.static_batches.chunk_size = 12
	game.set_process(true)
	game.view.set_process(true)
	if case_name == "close":
		game.view.focus = game.view.coord_position(game.active_capital())
		game.view.zoom = 11
	if case_name == "shadow_range":
		game.view.sun.directional_shadow_max_distance = maxf(75, info["overview_zoom"] * 2)
	if case_name == "no_shadows":
		game.view.sun.shadow_enabled = false
	if case_name == "one_shadow":
		game.view.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	if case_name.begins_with("chunk"):
		game.view.static_batches.chunk_size = case_name.trim_prefix("chunk").to_int()
	if case_name in ["no_scripts", "orbit_no_pick"]:
		game.set_process(false)
	if case_name == "no_scripts":
		game.view.set_process(false)
	game.view.refresh_static_batches()
	game.view.update_camera()
	var start_rebuilds: int = game.view.static_batches.rebuild_count
	var start_syncs: int = game.view.static_batches.sync_count
	game.hovered = game.NONE
	game.refresh_ui()
	root.warp_mouse(Vector2(15, 150))
	await create_timer(1.0).timeout
	var viewport := root.get_viewport_rid()
	var frames: Array = []
	var render_cpu: Array = []
	var render_gpu: Array = []
	var previous := Time.get_ticks_usec()
	var started := previous
	var bad := 0
	while Time.get_ticks_usec() - started < duration * 1000000:
		if case_name == "zoom_spam":
			var phase := (Time.get_ticks_usec() - started) / 1000000.0
			game.view.zoom = 42.0 + 22.0 * sin(phase * TAU * 2.0)
			game.view.update_camera()
		if case_name in ["orbit", "orbit_no_pick", "rotate"]:
			game.view.yaw += 0.006
			game.view.update_camera()
		if case_name == "hover" or case_name.ends_with("_hover"):
			var t := (Time.get_ticks_usec() - started) / 1000000.0
			root.warp_mouse(Vector2(640 + 300 * sin(t * 2.0), 410 + 190 * cos(t * 3.0)))
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var frame := (now - previous) / 1000.0
		frames.append(frame)
		bad += int(frame > 1000.0 / 240.0)
		previous = now
		render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
		render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	var result := info.duplicate(true)
	result.merge({"case": case_name, "frames": frames.size(), "fps_mean": frames.size() * 1000000.0 / (previous - started),
		"frame_ms_p50": percentile(frames, 0.5), "frame_ms_p95": percentile(frames, 0.95), "frame_ms_p99": percentile(frames, 0.99),
		"frame_ms_max": frames.max(), "over_budget_percent": 100.0 * bad / frames.size(),
		"render_cpu_ms_p50": percentile(render_cpu, 0.5), "render_gpu_ms_p50": percentile(render_gpu, 0.5),
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "chunks": game.view.static_batches.chunks.size(),
		"camera_zoom": game.view.zoom, "shadow_distance": game.view.sun.directional_shadow_max_distance})
	result["window_resolution"] = str(DisplayServer.window_get_size())
	result["shadow_opacity"] = game.view.sun.shadow_opacity
	result["shadow_mode"] = game.view.sun.directional_shadow_mode
	result["chunk_size"] = game.view.static_batches.chunk_size
	result["lod_rebuilds"] = game.view.static_batches.rebuild_count - start_rebuilds
	result["lod_syncs"] = game.view.static_batches.sync_count - start_syncs
	for type_value in range(2):
		var name_value: String = ["visible", "shadow"][type_value]
		result[name_value + "_draws"] = RenderingServer.viewport_get_render_info(viewport, type_value, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		result[name_value + "_primitives"] = RenderingServer.viewport_get_render_info(viewport, type_value, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	result["frame_intervals_ms"] = frames
	results.append(result)
	persist()
	var summary := result.duplicate()
	summary.erase("frame_intervals_ms")
	print(JSON.stringify(summary))
	game.view.rotating = false

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use native rendering for FPS measurements")
		quit(1)
		return
	for argument in OS.get_cmdline_user_args():
		if argument == "--live-quality":
			live_quality = true
		if argument.begins_with("--sizes="):
			sizes = []
			for value in argument.trim_prefix("--sizes=").split(","):
				sizes.append(value.to_int() if value.is_valid_int() else value)
		if argument.begins_with("--seeds="):
			seeds = []
			for value in argument.trim_prefix("--seeds=").split(","):
				seeds.append(value.to_int())
		if argument.begins_with("--cases="):
			cases = Array(argument.trim_prefix("--cases=").split(","))
		if argument.begins_with("--duration="):
			duration = argument.trim_prefix("--duration=").to_float()
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
	var video = root.get_node("Video")
	config = {"device": RenderingServer.get_video_adapter_name(), "engine": Engine.get_version_info().string,
		"saved_resolution": str(video.resolution), "saved_msaa": video.antialiasing, "resolution": "1920x1080",
		"msaa": video.antialiasing, "shadow_mode": "automatic LOD" if live_quality else "4 splits", "background": "water", "duration_seconds": duration,
		"vsync": false, "fps_cap": 0, "six_factions": true, "date": "2026-10-14"}
	config["live_quality"] = live_quality
	video.set_preference(&"fullscreen", false, false)
	video.set_preference(&"resolution", Vector2i(1920, 1080), false)
	video.set_preference(&"vsync", false, false)
	video.set_preference(&"level_transitions", false, false)
	video.set_preference(&"background", "water", false)
	video.set_preference(&"shadows", true, false)
	Engine.max_fps = 0
	root.get_node("Sound").set_muted(true, false)
	app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await app.start_new_game(42, "large", "normal", 6)
	game = app.game
	game.view.cancel_level_transition()
	config["hidden_menu_disabled"] = app.menus.menu_background.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await create_timer(2.0).timeout
	for target in sizes:
		for seed_value in seeds:
			var supported := target is String
			if not supported:
				StressSizes.stress_profile = profile(target)
			var rules = StressRules.new()
			rules.rule_mode = "modern"
			var started := Time.get_ticks_usec()
			rules.generate(seed_value, target if supported else "stress", 4 if supported and target == "very_small" else 6)
			var generation_ms := (Time.get_ticks_usec() - started) / 1000.0
			var connected: bool = rules.connected_land()
			var passable: bool = rules.MapGenerator.new(rules).passable_land_connected()
			game.rules = rules
			started = Time.get_ticks_usec()
			game.new_game(seed_value, true, false)
			var build_ms := (Time.get_ticks_usec() - started) / 1000.0
			game.view.cancel_level_transition()
			var current_profile: Dictionary = StressSizes.spec(target) if supported else StressSizes.stress_profile
			var bounds: Vector2 = current_profile["bounds"]
			# Include the whole configured rectangle, not merely a central camera crop.
			var overview_zoom: float = maxf(38, current_profile["zoom"] * 1.7) if supported else 64.6 * sqrt(float(target) / 210.0)
			game.view.max_zoom = overview_zoom
			var info := {"target_tiles": target, "tiles": rules.cells.size(), "seed": seed_value, "generation_ms": generation_ms,
				"generation_stages_ms": rules.generation_stages, "scene_build_ms": build_ms, "bounds": str(bounds),
				"overview_zoom": overview_zoom, "connected": connected, "passable_connected": passable,
				"kingdoms": rules.kingdoms.size(), "msaa_actual": root.msaa_3d}
			print("GENERATED " + JSON.stringify(info))
			await process_frame
			await process_frame
			for case_name in cases:
				await sample(case_name, info)
	game.shutdown()
	root.get_node("Sound").stop_all()
	quit()
