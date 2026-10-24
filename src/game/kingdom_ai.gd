extends RefCounted
## Shared AI entry points, validated commits and existing animation records.
const Execution = preload("res://src/game/ai_execution.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const SearchJob = preload("res://src/game/ai_search_job.gd")
const Strategist = preload("res://src/game/ai_strategist.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
const SimulationJob = preload("res://src/game/simulation_job.gd")
var state
var strategic_context: Dictionary = {}
var pending_orders: Array = []
var strategic_planner
var threaded_simulation := true
var simulation_job
var worker_cancel: Callable
var presentation_patch: Dictionary = {}
var presentation_patch_ready := false
var settlement_deaths := 0

func world_async(host) -> Array[Dictionary]:
	presentation_patch_ready = false
	if can_simulate_on_worker(): return await simulate_async(Execution.adapt(host), -1, false, "world")
	return state.world_turn()

func begin_turn_async(host, faction: int) -> int:
	presentation_patch_ready = false
	if can_simulate_on_worker():
		await simulate_async(Execution.adapt(host), faction, false, "settlement")
		return settlement_deaths
	return state.begin_turn(faction)

func preparation_cells() -> Dictionary:
	return presentation_patch if presentation_patch_ready else state.cells

func movement_cells(actions: Array) -> Dictionary:
	if not presentation_patch_ready: return state.cells
	var result := presentation_patch.duplicate()
	for action in actions:
		for coord in [action["source"], action["target"], action.get("landing", action["target"])]:
			result[coord] = state.cells[coord]
	return result

func is_cancelled() -> bool:
	return worker_cancel.is_valid() and worker_cancel.call()

func run_planner(faction: int, spending := false):
	var planner
	if state.uses_strategic_ai() and worker_cancel.is_valid():
		var view = Snapshots.analysis_view(state)
		planner = Strategist.new(view, faction, spending, true, strategic_context)
	else:
		planner = Strategist.new(state, faction, spending, false, strategic_context) if state.uses_strategic_ai() else Planner.new(state, faction, spending)
	while not is_cancelled() and not planner.step(): pass
	return planner

func can_simulate_on_worker() -> bool:
	return threaded_simulation and (state.replay_log == null or not state.replay_log.transaction)

func simulate_async(execution: Execution, faction: int, preparation: bool, operation := "") -> Array[Dictionary]:
	if execution.is_cancelled(): return []
	await execution.wait_until_resumed()
	if execution.is_cancelled(): return []
	if simulation_job == null: simulation_job = SimulationJob.new()
	var job = simulation_job
	var started := execution.start_sample()
	job.packet = Snapshots.worker_input(state)
	job.clear_outputs()
	job.faction = faction
	job.preparation = preparation
	job.operation = operation
	job.deaths = 0
	job.recorder = state.replay_log.fork_worker() if state.replay_log != null else null
	var expected_sequence: int = state.replay_log.sequence if state.replay_log != null else 0
	execution.finish_sample(started, "simulation_input")
	# Round settlement is short and blocks the next turn; do not queue it behind
	# background loading or shader preparation. Long AI searches keep normal priority.
	var task := WorkerThreadPool.add_task(job.run, operation != "", "Kingdom simulation")
	while not WorkerThreadPool.is_task_completed(task):
		await execution.next_frame()
		if execution.is_cancelled(): job.cancel()
	WorkerThreadPool.wait_for_task_completion(task)
	await execution.wait_until_resumed()
	if execution.is_cancelled() or job.is_cancelled():
		simulation_job = null
		return []
	if job.result.is_empty():
		push_error("Simulation worker did not produce a completed transaction")
		simulation_job = null
		return []
	started = execution.start_sample()
	Snapshots.publish_worker(state, job.result)
	settlement_deaths = job.deaths
	presentation_patch = job.result["cells"]
	presentation_patch_ready = job.result["removed"].is_empty()
	if job.recorder != null: state.replay_log.publish_worker(job.recorder, expected_sequence)
	strategic_context = job.opponent.strategic_context.duplicate(true)
	pending_orders = job.opponent.pending_orders.duplicate(true)
	var actions: Array[Dictionary] = job.actions
	job.packet = {}
	job.clear_outputs()
	job.recorder = null
	execution.finish_sample(started, "simulation_publish")
	if execution.trace.is_valid(): execution.trace.call({"stage":"simulation_worker", "ms":job.worker_ms})
	return actions

func _init(rules) -> void:
	state = rules

func record_decision(action: Dictionary, planner) -> void:
	state.ai_revision += 1
	state.ai_last_decision = {"action": action.duplicate(true), "score": planner.best_score,
		"evaluated": planner.evaluated, "max_step_ms": planner.max_step_usec / 1000.0,
		"search_ms": planner.planning_usec / 1000.0 if planner is Strategist else (Time.get_ticks_usec() - planner.started_usec) / 1000.0}
	state.ai_last_decision["algorithm"] = "strategic" if planner is Strategist else "legacy"
	# A separate annotation preserves search information without replaying it.
	state.record_replay("ai_decision", planner.faction, state.ai_last_decision)

func prepare_ai_turn(faction: int) -> Array[Dictionary]:
	if is_cancelled() or state.territory(faction) == 0 and not state.has_units(faction):
		return []
	var before: Dictionary = state.cells.duplicate(true)
	state.begin_turn(faction)
	for purchase in range(int(Analysis.profile(state)["spending"])):
		if is_cancelled(): break
		var planner = run_planner(faction, true)
		var action: Dictionary = planner.best
		if is_cancelled() or action.is_empty() or not Candidates.apply(state, action, faction):
			break
		record_decision(action, planner)
	return preparation_records(before, faction)

func prepare_async(host, faction: int) -> Array[Dictionary]:
	presentation_patch_ready = false
	var execution: Execution = Execution.adapt(host)
	if can_simulate_on_worker(): return await simulate_async(execution, faction, true)
	var before: Dictionary = state.cells.duplicate(true)
	state.begin_turn(faction)
	for purchase in range(int(Analysis.profile(state)["spending"])):
		if execution.is_cancelled():
			break
		var planner = await search_async(execution, faction, true)
		if planner == null:
			break
		var action: Dictionary = planner.best
		if execution.is_cancelled() or action.is_empty() or not Candidates.apply(state, action, faction):
			break
		record_decision(action, planner)
	return preparation_records(before, faction)

func search_async(host, faction: int, spending := false):
	var execution: Execution = Execution.adapt(host)
	if execution.is_cancelled():
		return null
	# Copy on the owning thread; all analysis and candidate simulations belong
	# exclusively to the worker. Main-thread commits still revalidate commands.
	var started := execution.start_sample()
	var job := SearchJob.new(Analysis.snapshot(state), faction, spending, strategic_context)
	execution.finish_sample(started, "ai_snapshot")
	var task := WorkerThreadPool.add_task(job.run, false, "Kingdom AI search")
	while not WorkerThreadPool.is_task_completed(task):
		await execution.next_frame()
		if execution.is_cancelled():
			job.cancel()
			# Completion must be acknowledged to release the pool task's resources.
			while not WorkerThreadPool.is_task_completed(task):
				await execution.next_frame()
			WorkerThreadPool.wait_for_task_completion(task)
			return null
	WorkerThreadPool.wait_for_task_completion(task)
	await execution.wait_until_resumed()
	if execution.is_cancelled(): return null
	if state.uses_strategic_ai() and not spending:
		strategic_context = job.planner.context
	return job.planner

func movements_async(host, faction: int, retry := true) -> Array[Dictionary]:
	presentation_patch_ready = false
	var execution: Execution = Execution.adapt(host)
	if can_simulate_on_worker(): return await simulate_async(execution, faction, false)
	if state.uses_strategic_ai():
		if execution.is_cancelled(): return []
		var cached := not pending_orders.is_empty()
		if pending_orders.is_empty():
			strategic_planner = await search_async(execution, faction)
			if strategic_planner == null: return []
			pending_orders = strategic_planner.best_sequence.duplicate(true)
		var result: Array[Dictionary] = []
		var dependencies: Dictionary = {}
		while not pending_orders.is_empty() and result.size() < 4:
			await execution.wait_until_resumed()
			if execution.is_cancelled(): return []
			var started := execution.start_sample()
			var records := commit_strategic(strategic_planner, 1, dependencies)
			execution.finish_sample(started, "rules_commit")
			if records.is_empty(): break
			result.append_array(records)
			# Each validated command is atomic; batches cooperate between commands.
			# No worker is permitted to mutate authoritative live rules.
			if not pending_orders.is_empty() and result.size() < 4: await execution.next_frame()
		if result.is_empty() and cached and retry and not execution.is_cancelled():
			pending_orders.clear()
			return await movements_async(execution, faction, false)
		return result
	var planner = await search_async(execution, faction)
	if planner == null:
		return []
	var started := execution.start_sample()
	var result := commit_move(planner.best, planner)
	execution.finish_sample(started, "rules_commit")
	return result

func ai_movements(faction: int, retry := true) -> Array[Dictionary]:
	if is_cancelled(): return []
	if state.uses_strategic_ai():
		var cached := not pending_orders.is_empty()
		if pending_orders.is_empty():
			strategic_planner = run_planner(faction)
			if is_cancelled(): return []
			strategic_context = strategic_planner.context
			pending_orders = strategic_planner.best_sequence.duplicate(true)
		var result := commit_strategic(strategic_planner)
		if result.is_empty() and cached and retry:
			pending_orders.clear()
			return ai_movements(faction, false)
		return result
	var planner = run_planner(faction)
	return [] if is_cancelled() else commit_move(planner.best, planner)

func finish_record(command: Dictionary, planner, movement: Dictionary) -> void:
	if movement["faction"] == 0 and movement["before_target"]["event"] != "":
		for event in state.pending_events.duplicate():
			if event["faction"] == 0 and event["coord"] == movement["target"]:
				state.resolve_event(event, Analysis.event_choice(state, event))
				movement["after_target"] = state.cells[movement["target"]].duplicate(true)
	movement["ai_reason"] = command.get("reason", "improve position")
	record_decision(command, planner)

func needs_replan(movement: Dictionary) -> bool:
	return not movement["annexed"].is_empty() or movement["before_target"]["capital"] >= 0 or movement["kind"] in ["merge", "blocked_attack", "knight_duel"] or movement["before_target"]["event"] != "" or not movement["after_target"]["moved"]

func commit_strategic(planner, limit := 4, dependencies: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	while not pending_orders.is_empty() and result.size() < limit:
		if is_cancelled(): break
		var command: Dictionary = pending_orders.pop_front()
		var source: Vector2i = command["source"]
		var target: Vector2i = command["coord"]
		if not state.cells.has(source) or not state.cells.has(target) or state.cells[source]["unit"] != command["expected_tier"] or state.cells[source]["moved"] or state.unit_faction(source) != planner.faction or state.cells[target]["owner"] != command["target_owner"]: continue
		var path: Array = state.movement_path(source, target)
		var dependent := false
		for coord in path:
			if dependencies.has(coord): dependent = true
		if dependent:
			pending_orders.push_front(command)
			break
		if path.is_empty(): continue
		var movement: Dictionary = state.Movement.record_validated_move(state, source, target, path)
		finish_record(command, planner, movement)
		result.append(movement)
		dependencies[source] = true
		dependencies[target] = true
		if needs_replan(movement):
			pending_orders.clear()
			break
	return result

func commit_move(action: Dictionary, planner) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if action.is_empty():
		return result
	var dependencies: Dictionary = {}
	for command in planner.best_sequence:
		var path: Array = state.movement_path(command["source"], command["coord"])
		var dependent := false
		for coord in path:
			if dependencies.has(coord):
				dependent = true
		if dependent or path.is_empty():
			break
		var movement: Dictionary = state.Movement.record_validated_move(state, command["source"], command["coord"], path)
		if movement.is_empty():
			break
		# Simulation harnesses can let the AI control faction zero too. The normal
		# player command path still keeps its encounters pending for the popup.
		finish_record(command, planner, movement)
		result.append(movement)
		dependencies[movement["target"]] = true
		# These changes must finish visually before any dependent route is planned.
		if not movement["annexed"].is_empty() or movement["kind"] in ["merge", "blocked_attack", "knight_duel"] or movement["before_target"]["event"] != "" or not movement["after_target"]["moved"]:
			break
	return result

func preparation_records(before: Dictionary, faction: int) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var changed_coords := before.duplicate()
	changed_coords.merge(state.cells, true)
	for coord in changed_coords:
		var old: Dictionary = before.get(coord, {})
		var cell: Dictionary = state.cells.get(coord, {})
		var kind := ""
		if old.is_empty():
			kind = "build"
		elif cell.is_empty():
			kind = "spell"
		elif old["unit"] > 0 and cell["unit"] == 0:
			kind = "death"
		elif cell["unit"] > old["unit"]:
			kind = "recruit" if old["unit"] == 0 else "upgrade"
		elif cell["building"] != old["building"]:
			kind = "build"
		elif cell["tree"] and not old["tree"]:
			kind = "tree"
		elif old["tree"] and not cell["tree"] or old["grave"] and not cell["grave"]:
			kind = "spell"
		elif cell.get("value", 1) > old.get("value", 1):
			kind = "develop"
		elif cell.get("entrenched_by", -1) != old.get("entrenched_by", -1):
			kind = "entrench" if state.is_entrenched(coord) else "expire"
		elif cell.get("fortified", false) != old.get("fortified", false):
			kind = "spell" if cell.get("fortified", false) else "expire"
		elif cell.get("barrier_by", -1) != old.get("barrier_by", -1):
			kind = "spell" if cell.get("barrier_by", -1) >= 0 else "expire"
		if kind != "":
			actions.append({"kind": kind, "faction": faction, "coord": coord,
				"before": old, "after": cell.duplicate(true)})
	return actions

func ai_turn(faction: int) -> Array[Dictionary]:
	var actions := prepare_ai_turn(faction)
	var wave := ai_movements(faction)
	while not wave.is_empty():
		actions.append_array(wave)
		wave = ai_movements(faction)
	return actions
