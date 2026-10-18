extends "res://tools/map_stress_probe.gd"
## Diagnostic only: production rules/rendering on deterministic crowded boards.
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const SearchJob = preload("res://src/game/ai_search_job.gd")
var mode := "render"
var search_limit := 20.0
var turn_difficulty := "normal"
var turn_limit := 180.0
var turn_units := 300
var turn_algorithm := "auto"

static func crowded(size_id: String, seed_value: int, unit_count: int):
	var model = Rules.new()
	model.rule_mode = "modern"
	model.generate(seed_value, size_id, 6)
	# Multi-source expansion: contiguous faction regions, actual generated mountains.
	var queue: Array = []
	var seen: Dictionary = {}
	for bank in model.kingdoms.values():
		queue.append(bank["capital"])
		seen[bank["capital"]] = bank["owner"]
	var head := 0
	while head < queue.size():
		var coord: Vector2i = queue[head]
		head += 1
		for next in model.neighbors(coord):
			if not seen.has(next) and not model.is_mountain(next):
				seen[next] = seen[coord]
				queue.append(next)
	for coord in model.cells:
		var cell: Dictionary = model.cells[coord]
		cell["unit"] = 0
		cell["event"] = ""
		cell["moved"] = false
		if seen.has(coord):
			cell["owner"] = seen[coord]
			cell["value"] = 6
	model.rebuild_kingdoms()
	var local_rng := RandomNumberGenerator.new()
	local_rng.seed = seed_value + 100
	var sites: Array = seen.keys()
	for index in range(sites.size() - 1, 0, -1):
		var other := local_rng.randi_range(0, index)
		var saved = sites[index]
		sites[index] = sites[other]
		sites[other] = saved
	for index in range(mini(unit_count, sites.size())):
		var cell: Dictionary = model.cells[sites[index]]
		cell["tree"] = false
		cell["grave"] = false
		cell["building"] = ""
		cell["unit"] = 3 if index % 10 == 0 else 2 if index % 3 == 0 else 1
	for bank in model.kingdoms.values():
		bank["gold"] = 300
	model.clamp_mana()
	return model

func install(size_id: String, unit_count: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	game.rules = crowded(size_id, 71, unit_count)
	game.rules.ai_algorithm = turn_algorithm
	game.new_game(71, true, false)
	game.view.cancel_level_transition()
	game.view.controls_enabled = false
	return {"target_tiles": size_id, "tiles": game.cells.size(), "units": game.view.unit_actors.size(),
		"kingdoms": game.rules.kingdoms.size(), "seed": 71, "overview_zoom": game.view.max_zoom,
		"setup_ms": (Time.get_ticks_usec() - started) / 1000.0, "synthetic": true}

func run() -> void:
	var label_suffix := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mode="): mode = arg.trim_prefix("--mode=")
		if arg.begins_with("--duration="): duration = arg.trim_prefix("--duration=").to_float()
		if arg.begins_with("--difficulty="): turn_difficulty = arg.trim_prefix("--difficulty=")
		if arg.begins_with("--turn-limit="): turn_limit = arg.trim_prefix("--turn-limit=").to_float()
		if arg.begins_with("--units="): turn_units = arg.trim_prefix("--units=").to_int()
		if arg.begins_with("--algorithm="): turn_algorithm = arg.trim_prefix("--algorithm=")
		if arg.begins_with("--label-suffix="): label_suffix = "_" + arg.trim_prefix("--label-suffix=")
	label = "heavy_" + mode
	if mode == "turn": label += "_%s_%d" % [turn_difficulty, turn_units]
	label += label_suffix
	if mode == "cpu":
		await cpu_probe()
		quit()
		return
	if DisplayServer.get_name() == "headless":
		push_error("Rendering stress requires native rendering")
		quit(1)
		return
	var video = root.get_node("Video")
	video.set_preference(&"resolution", Vector2i(1920, 1080), false)
	video.set_preference(&"fullscreen", false, false)
	video.set_preference(&"vsync", false, false)
	video.set_preference(&"level_transitions", false, false)
	video.set_preference(&"shadows", true, false)
	video.set_preference(&"background", "water", false)
	root.get_node("Sound").set_muted(true, false)
	Engine.max_fps = 0
	live_quality = true
	config = {"resolution": "1920x1080", "msaa": video.antialiasing, "device": RenderingServer.get_video_adapter_name(),
		"vsync": false, "fps_cap": 0, "seed": 71, "synthetic": true, "date": "2026-10-14", "mode": mode}
	config["algorithm"] = turn_algorithm
	app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await app.start_new_game(71, "huge", "normal", 6)
	game = app.game
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	if mode == "render":
		for size_id in ["very_large", "huge"]:
			for count in [0, 120, 300, 600]:
				if size_id == "very_large" and count == 600: continue
				var info := install(size_id, count)
				await sample("hover", info)
				if count >= 300: await sample("close", info)
		# Isolate soldier submission/transparent drawing from scripts and shadows.
		var info := install("huge", 600)
		await sample("no_scripts", info)
		await sample("no_shadows", info)
		for actor in game.view.unit_actors.values(): actor.hide()
		game.view.unit_batches.sync()
		await sample("hidden_units_hover", info)
		for actor in game.view.unit_actors.values(): actor.show()
	elif mode == "ai":
		for count in [120, 300, 600]:
			var info := install("huge", count)
			for difficulty in ["normal", "hard"]:
				game.rules.ai_difficulty = difficulty
				await worker_sample(info, difficulty)
	elif mode == "ablate":
		var info := install("huge", 600)
		await sample("wide", info)
		root.get_texture().get_image().save_png("res://artifacts/heavy_huge_600%s.png" % label_suffix)
		await sample("close", info)
		root.get_texture().get_image().save_png("res://artifacts/heavy_huge_600_close%s.png" % label_suffix)
		for actor in game.view.unit_actors.values(): actor.get_node("Pips").hide()
		game.view.unit_batches.sync()
		await sample("no_rank_pips", info)
		for actor in game.view.unit_actors.values():
			for child in actor.get_children():
				if child is MeshInstance3D: child.hide() # Flat blob shadow.
		game.view.unit_batches.sync()
		await sample("no_pips_or_blob_shadows", info)
		for actor in game.view.unit_actors.values(): actor.hide()
		game.view.unit_batches.sync()
		await sample("hidden_units", info)
		for actor in game.view.unit_actors.values():
			actor.show()
			actor.get_node("Pips").show()
			for child in actor.get_children():
				if child is MeshInstance3D: child.show()
		select_during_warmup()
		await sample("selected_unit_hover", info)
		results[-1]["selected"] = str(game.selected)
		results[-1]["legal_targets"] = game.valid_targets.size()
		persist()
	elif mode == "interaction":
		var info := install("huge", 300)
		select_during_warmup()
		await sample("selected_unit_hover", info)
		results[-1]["selected"] = str(game.selected)
		results[-1]["legal_targets"] = game.valid_targets.size()
		persist()
		var structures := 0
		var wards := 0
		var barriers := 0
		for coord in game.cells:
			var cell: Dictionary = game.cells[coord]
			if cell["mountain"] or cell["capital"] >= 0: continue
			if structures < 150 and cell["unit"] == 0:
				cell["tree"] = false
				cell["building"] = "house" if structures % 2 else "tower"
				structures += 1
			if wards < 50 and cell["building"] in ["house", "tower"]:
				cell["fortified"] = true
				cell["fortified_by"] = cell["owner"]
				wards += 1
			elif barriers < 50 and cell["unit"] == 0 and cell["building"] == "":
				cell["tree"] = false
				cell["barrier_by"] = cell["owner"]
				barriers += 1
		game.view.render_cells(game.cells)
		info.merge({"structures": structures, "wards": wards, "barriers": barriers})
		await sample("buildings_and_effects_hover", info)
		await sample("close", info)
	elif mode == "turn":
		for difficulty in [turn_difficulty]:
			var info := install("huge", turn_units)
			game.rules.ai_difficulty = difficulty
			await turn_sample(info, difficulty)
			if game.closing: break
	game.shutdown()
	while game.busy:
		await process_frame
	await process_frame
	app.queue_free()
	await process_frame
	quit()

func select_during_warmup() -> void:
	await create_timer(0.2).timeout
	for coord in game.cells:
		if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] > 0:
			game.click_hex(coord, "unit")
			return

func frame_report(frames: Array, wall_ms: float) -> Dictionary:
	var bad := 0
	for frame in frames: bad += int(frame > 1000.0 / 240)
	return {"wall_ms": wall_ms, "frames": frames.size(), "fps_mean": frames.size() * 1000.0 / wall_ms,
		"frame_ms_p50": percentile(frames, 0.5), "frame_ms_p95": percentile(frames, 0.95),
		"frame_ms_p99": percentile(frames, 0.99), "frame_ms_max": frames.max(), "over_budget_percent": bad * 100.0 / frames.size()}

func worker_sample(info: Dictionary, difficulty: String) -> void:
	game.busy = true # Production disables interactive picking during AI planning.
	game.view.zoom = game.view.max_zoom
	game.view.focus = Vector3.ZERO
	game.view.update_camera()
	await create_timer(1.0).timeout
	var started := Time.get_ticks_usec()
	var job := SearchJob.new(Analysis.snapshot(game.rules), 1, false)
	var snapshot_ms := (Time.get_ticks_usec() - started) / 1000.0
	var task := WorkerThreadPool.add_task(job.run, false, "Heavy strain AI")
	var frames: Array = []
	var previous := started
	var timed_out := false
	while not WorkerThreadPool.is_task_completed(task):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		previous = now
		if now - started > search_limit * 1000000:
			timed_out = true
			job.cancel()
	WorkerThreadPool.wait_for_task_completion(task)
	var result := info.duplicate()
	result.merge(frame_report(frames, (Time.get_ticks_usec() - started) / 1000.0))
	result.merge({"case": "worker_search", "difficulty": difficulty, "snapshot_main_thread_ms": snapshot_ms,
		"timed_out": timed_out, "evaluated": job.planner.evaluated, "search_complete": job.planner.done,
		"max_worker_step_ms": job.planner.max_step_usec / 1000.0, "sequence_length": job.planner.best_sequence.size()})
	result["frame_intervals_ms"] = frames
	results.append(result)
	persist()
	result.erase("frame_intervals_ms")
	print(JSON.stringify(result))
	game.busy = false

func turn_sample(info: Dictionary, difficulty: String) -> void:
	game.view.zoom = game.view.max_zoom
	game.view.update_camera()
	await create_timer(1.0).timeout
	var started := Time.get_ticks_usec()
	var previous := started
	var frames: Array = []
	var slow: Array = []
	var rebuilds: int = game.view.static_batches.rebuild_count
	var syncs: int = game.view.static_batches.sync_count
	var terrain_rebuilds: int = game.view.static_batches.terrain_rebuild_count
	var timeout_batches: Array = []
	var timeout_rebuilds := 0
	var timeout_syncs := 0
	var observed_scales: Dictionary = {}
	game.view.static_batches.profile_sync = true
	game.view.profile_capture = true
	game.view.capture_samples.clear()
	game.view.static_batches.profile_samples.clear()
	game.playback_speed.speed_held = true
	# Benchmark intent must survive window-focus notifications resetting the
	# human hold control. Pin it before processing each frame, only in this probe.
	var keep_fast := func():
		if game.busy and not game.closing:
			game.playback_speed.speed_held = true
			game.playback_speed.update()
	process_frame.connect(keep_fast)
	game.end_turn()
	while game.busy:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var scale_key := str(game.view.playback.speed_scale)
		observed_scales[scale_key] = observed_scales.get(scale_key, 0) + 1
		var frame := (now - previous) / 1000.0
		frames.append(frame)
		if frame > 8:
			slow.append({"ms": frame, "elapsed_ms": (now - started) / 1000.0,
				"animating": game.view.is_animating, "faction": game.active_faction,
				"revision": game.rules.ai_revision, "rebuilds": game.view.static_batches.rebuild_count - rebuilds})
		previous = now
		if now - started > turn_limit * 1000000:
			timeout_batches = game.view.static_batches.profile_samples.duplicate(true)
			timeout_rebuilds = game.view.static_batches.rebuild_count - rebuilds
			timeout_syncs = game.view.static_batches.sync_count - syncs
			game.shutdown()
			break
	process_frame.disconnect(keep_fast)
	var result := info.duplicate()
	result.merge(frame_report(frames, (previous - started) / 1000.0))
	result.merge({"case": "full_opponent_round_6x_playback", "difficulty": difficulty,
		"round_completed": game.round_number == 2, "timed_out": game.closing,
		"ai_decisions": game.rules.ai_revision, "active_faction_at_end": game.active_faction,
		"chunk_rebuilds": timeout_rebuilds if game.closing else game.view.static_batches.rebuild_count - rebuilds,
		"syncs": timeout_syncs if game.closing else game.view.static_batches.sync_count - syncs})
	result["terrain_rebuilds"] = game.view.static_batches.terrain_rebuild_count - terrain_rebuilds
	result["playback_scale_frames"] = observed_scales
	result["capture_profile"] = game.view.capture_samples.duplicate(true)
	result["slow_frames"] = slow
	result["batch_profile"] = timeout_batches if game.closing else game.view.static_batches.profile_samples.duplicate(true)
	result["frame_intervals_ms"] = frames
	results.append(result)
	persist()
	result.erase("frame_intervals_ms")
	result.erase("slow_frames")
	result.erase("batch_profile")
	result.erase("capture_profile")
	print(JSON.stringify(result))

func cpu_probe() -> void:
	config = {"headless": true, "synthetic": true, "seed": 71, "mode": "cpu"}
	for size_id in ["very_large", "huge"]:
		for count in [120, 300, 600]:
			if size_id == "very_large" and count == 600: continue
			var model = crowded(size_id, 71, count)
			var result := {"size": size_id, "tiles": model.cells.size(), "units": count, "kingdoms": model.kingdoms.size()}
			for operation in ["snapshot", "rebuild", "threats", "evaluate", "movement_candidates", "spending_candidates"]:
				var timings: Array = []
				for repetition in range(3):
					var copy = Analysis.snapshot(model)
					var query = Analysis.Queries.new(copy)
					var started := Time.get_ticks_usec()
					match operation:
						"snapshot": Analysis.snapshot(model)
						"rebuild": copy.rebuild_kingdoms()
						"threats": query.threats(1)
						"evaluate": Analysis.evaluate(copy, 1, query)
						"movement_candidates": Candidates.movements(copy, 1, query)
						"spending_candidates": Candidates.preparation(copy, 1, query)
					timings.append((Time.get_ticks_usec() - started) / 1000.0)
				result[operation + "_ms"] = percentile(timings, 0.5)
			results.append(result)
			persist()
			print(JSON.stringify(result))
			await process_frame
