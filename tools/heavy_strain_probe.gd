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
var turn_speed := 6.0
var ablation := ""
var turn_map := "huge"
var diagnose_frames := false
var turn_zoom := 0.0

class NoRipplePlayback extends "res://src/rendering/board_playback.gd":
	func action_marker(_coord: Vector2i, _color: Color) -> void:
		pass

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
		# This synthetic army board replaces neutral objectives with occupied
		# provinces; retain no lairs beneath its directly assigned troops.
		for field in ["animal","animal_home","lair","lair_wait"]: cell.erase(field)
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
		if arg == "--diagnose": diagnose_frames = true
		if arg.begins_with("--zoom="): turn_zoom = arg.trim_prefix("--zoom=").to_float()
		if arg.begins_with("--map-size="): turn_map = arg.trim_prefix("--map-size=")
		if arg.begins_with("--ablation="): ablation = arg.trim_prefix("--ablation=")
		if arg.begins_with("--speed="): turn_speed = arg.trim_prefix("--speed=").to_float()
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
		"vsync": false, "renderer": RenderingServer.get_current_rendering_method(), "ablation": ablation, "speed": turn_speed, "fps_cap": 0, "seed": 71, "synthetic": true, "date": "2026-10-20", "mode": mode}
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
	elif mode == "handoff":
		await handoff_sample()
	elif mode == "simulation":
		await simulation_comparison()
	elif mode == "ai":
		for count in [turn_units] if diagnose_frames else [120, 300, 600]:
			var info := install(turn_map, count)
			if diagnose_frames:
				game.busy = true
				await create_timer(1.0).timeout
				await idle_timing_sample(info)
			for difficulty in [turn_difficulty] if diagnose_frames else ["normal", "hard"]:
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
			var info := install(turn_map, turn_units)
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
	var worker_timings := []
	var previous := started
	var timed_out := false
	while not WorkerThreadPool.is_task_completed(task):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		if diagnose_frames: worker_timings.append(timing_row((now - previous) / 1000.0))
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
	if diagnose_frames and not worker_timings.is_empty(): result["cpu_gpu_timings"] = timing_summary(worker_timings)
	result["frame_intervals_ms"] = frames
	results.append(result)
	persist()
	result.erase("frame_intervals_ms")
	print(JSON.stringify(result))
	game.busy = false

func turn_sample(info: Dictionary, difficulty: String) -> void:
	if ablation == "serial_simulation": game.ai_simulation_workers = false
	if ablation == "effect_churn":
		# Reproduce the original uninitialized, unretained shader templates.
		game.view.playback.marker_material = game.view.playback.marker_material.duplicate()
		game.view.playback.flash_material = game.view.playback.flash_material.duplicate()
		for child in game.view.playback.get_children():
			if child is MeshInstance3D: child.queue_free()
		await process_frame
	if ablation == "ripples":
		game.view.playback.queue_free()
		game.view.playback = NoRipplePlayback.new(game.view)
		game.view.add_child(game.view.playback)
	if ablation == "terrain":
		game.view.static_batches.merge_terrain = false
		game.view.refresh_static_batches()
	if ablation == "simple":
		root.get_node("Video").set_preference(&"atmospheric_lighting", false, false)
	game.view.zoom = turn_zoom if turn_zoom > 0 else game.view.max_zoom
	game.view.update_camera()
	await create_timer(1.0).timeout
	if diagnose_frames: await idle_timing_sample(info)
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
	var phase_timings: Dictionary = {}
	game.view.static_batches.profile_sync = true
	game.view.unit_sprites.profile_frames = true
	game.view.unit_sprites.frame_samples.clear()
	game.view.profile_capture = true
	game.view.capture_samples.clear()
	game.view.static_batches.profile_samples.clear()
	game.playback_speed.speed_held = turn_speed > 1.0
	# Benchmark intent must survive window-focus notifications resetting the
	# human hold control. Pin it before processing each frame, only in this probe.
	var keep_fast := func():
		if game.busy and not game.closing:
			game.playback_speed.speed_held = turn_speed > 1.0
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
		if diagnose_frames:
			var phase := "animation" if game.view.is_animating else "planning_or_settlement"
			if not phase_timings.has(phase): phase_timings[phase] = []
			phase_timings[phase].append(timing_row(frame))
		if frame > 8:
			slow.append({"frame":Engine.get_process_frames(),"pipelines":pipeline_counts(),"ms": frame, "elapsed_ms": (now - started) / 1000.0,
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
	result.merge({"case": "full_opponent_round_%sx_playback" % turn_speed, "difficulty": difficulty,
		"round_completed": game.round_number == 2, "timed_out": game.closing,
		"ai_decisions": game.rules.ai_revision, "active_faction_at_end": game.active_faction,
		"chunk_rebuilds": timeout_rebuilds if game.closing else game.view.static_batches.rebuild_count - rebuilds,
		"syncs": timeout_syncs if game.closing else game.view.static_batches.sync_count - syncs})
	if diagnose_frames:
		result["phase_timings"] = {}
		for phase in phase_timings: result["phase_timings"][phase] = timing_summary(phase_timings[phase])
	result["terrain_rebuilds"] = game.view.static_batches.terrain_rebuild_count - terrain_rebuilds
	result["playback_scale_frames"] = observed_scales
	result["sprite_frames"] = game.view.unit_sprites.frame_samples.duplicate(true)
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
	result.erase("sprite_frames")
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

func simulation_comparison() -> void:
	# Keep one rendered board fixed. Interleave identical computation-only phases
	# to distinguish worker scheduling from startup/animation/GPU timing changes.
	var info := install(turn_map, turn_units)
	game.view.zoom = game.view.max_zoom
	game.view.update_camera()
	game.busy = true
	var schema = preload("res://src/game/state_snapshot.gd")
	var initial: Dictionary = schema.capture(game.rules)
	await create_timer(1.0).timeout
	for threaded in [false, true, true, false]:
		schema.restore(game.rules, initial)
		if game.rules.replay_log != null:
			game.rules.replay_log = game.rules.replay_log.get_script().new()
			game.rules.replay_log.start(game.rules)
		var opponent = game.rules.KingdomAI.new(game.rules)
		opponent.threaded_simulation = threaded
		var completed := [false]
		var samples := []
		var execution = game.ai_execution()
		execution.trace = func(row): samples.append(row)
		var operation := func():
			await opponent.prepare_async(execution, 1)
			for batch in range(2): await opponent.movements_async(execution, 1)
			completed[0] = true
		var started := Time.get_ticks_usec()
		var previous := started
		var rows := []
		operation.call()
		while not completed[0]:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			rows.append(timing_row((now - previous) / 1000.0))
			previous = now
		var result := info.duplicate()
		result.merge(timing_summary(rows))
		result["case"] = "worker" if threaded else "serial"
		result["wall_ms"] = (Time.get_ticks_usec() - started) / 1000.0
		result["samples"] = samples
		result["position_hash"] = hash(schema.capture(game.rules)["cells"])
		results.append(result)
		persist()
		var brief := result.duplicate()
		brief.erase("samples")
		print(JSON.stringify(brief))
		await create_timer(0.3).timeout
	game.busy = false

func handoff_sample() -> void:
	var info := install(turn_map, turn_units)
	for cell in game.cells.values():
		if cell["unit"] > 0: cell["moved"] = true
	game.view.render_cells(game.cells)
	game.busy = true
	game.active_faction = 5
	game.view.unit_presentation.set_turn(-1)
	game.view.zoom = game.view.max_zoom
	game.view.update_camera()
	game.playback_speed.speed_held = true
	game.playback_speed.update()
	# The real handoff follows AI jobs; exclude first-use pool startup here too.
	var warmup := WorkerThreadPool.add_task(func(): pass)
	while not WorkerThreadPool.is_task_completed(warmup): await process_frame
	WorkerThreadPool.wait_for_task_completion(warmup)
	await create_timer(1.0).timeout
	game.view.profile_capture = true
	game.view.capture_samples.clear()
	var previous := [Time.get_ticks_usec()]
	var timings := []
	var watch := func():
		var now := Time.get_ticks_usec()
		timings.append((now - previous[0]) / 1000.0)
		previous[0] = now
	RenderingServer.frame_post_draw.connect(watch)
	var started := Time.get_ticks_usec()
	game.round_number += 1
	await preload("res://src/game/opponent_turns.gd").play_world(game)
	await preload("res://src/game/opponent_turns.gd").finish_player_turn_handoff(game)
	var result := info.duplicate()
	result["handoff_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	RenderingServer.frame_post_draw.disconnect(watch)
	result["frame_intervals_ms"] = timings
	result["capture_profile"] = game.view.capture_samples.duplicate(true)
	results.append(result)
	persist()
	print(JSON.stringify(result))

func pipeline_counts() -> Array:
	var values := []
	for monitor in [Performance.PIPELINE_COMPILATIONS_CANVAS,Performance.PIPELINE_COMPILATIONS_MESH,Performance.PIPELINE_COMPILATIONS_SURFACE,Performance.PIPELINE_COMPILATIONS_DRAW,Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		values.append(Performance.get_monitor(monitor))
	return values

func timing_row(frame_ms: float) -> Dictionary:
	var viewport := root.get_viewport_rid()
	return {"frame_ms":frame_ms,
		"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),
		"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}

func timing_summary(rows: Array) -> Dictionary:
	var report := {"frames":rows.size()}
	for key in ["frame_ms","render_cpu_ms","render_gpu_ms","draw_calls"]:
		var values := []
		for row in rows: values.append(row[key])
		report[key+"_p50"] = percentile(values,0.5)
		report[key+"_p95"] = percentile(values,0.95)
	return report

func idle_timing_sample(info: Dictionary) -> void:
	var rows := []
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec()-started < 2000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		rows.append(timing_row((now-previous)/1000.0))
		previous = now
	var result := info.duplicate()
	result["case"] = "idle_cpu_gpu"
	result.merge(timing_summary(rows))
	results.append(result)
	persist()
	print(JSON.stringify(result))
