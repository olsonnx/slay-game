extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const BeforeCandidates = preload("res://tests/fixtures/ai_candidates_before_army_optimization.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func canonical_ties(actions: Array) -> Array:
	# Godot's sort is unstable: optimization can reorder equally valued moves.
	# Normalize only adjacent exact ties, retaining ranking and selected actions.
	var result := []
	var index := 0
	while index < actions.size():
		var end := index + 1
		while end < actions.size() and actions[end]["priority"] == actions[index]["priority"]: end += 1
		var tied := actions.slice(index, end)
		tied.sort_custom(func(a, b): return JSON.stringify(a) < JSON.stringify(b))
		result.append_array(tied)
		index = end
	return result

func query_checks(model) -> void:
	var query = Analysis.Queries.new(model)
	var inspected := 0
	for coord in model.cells:
		if model.cells[coord]["unit"] == 0: continue
		var actual: Array = query.candidate_targets(coord).duplicate()
		actual.erase(coord)
		actual.sort()
		var expected: Array = model.reachable_targets(coord).keys()
		expected.sort()
		expect(actual == expected, "Shared candidate regions equal authoritative legal destinations")
		inspected += 1
		if inspected == 48: break
	for faction in range(model.faction_count):
		var old: Array = BeforeCandidates.movements(model, faction)
		var current: Array = Candidates.movements(model, faction)
		var tactical_change := query.defense_needs(faction) != query.threats(faction)
		for action in old + current:
			var target: Vector2i = action["coord"]
			if model.cells[target]["owner"] >= 0 and model.cells[target]["owner"] != faction and query.cut_value(target) > 0: tactical_change = true
			if query.campaign_value(target,faction) > 0: tactical_change = true
			for next in [target] + model.neighbors(target):
				if model.cells[next]["owner"] == faction and query.supply_risk(next) > 0: tactical_change = true
		# Destination/rank diversity deliberately replaces repeated jobs in the
		# historical shortlist; keep equivalence checks for unaffected lists.
		var old_jobs := {}
		var repeated_job := false
		for action in old:
			var target: Vector2i = action["coord"]
			var job := Vector3i(target.x,target.y,model.cells[action["source"]]["unit"])
			if old_jobs.has(job): repeated_job = true
			old_jobs[job] = true
		expect(canonical_ties(current) == canonical_ties(old) or tactical_change or repeated_job, "Candidate equivalence holds outside intentional tactical/diversity changes")
		expect(current.size() <= int(Analysis.profile(model)["candidates"]),"New tactics retain the candidate budget")
		var jobs := {}
		var departures := {}
		var previous_priority := INF
		for action in current:
			expect(model.can_move(action["source"],action["coord"]),"New tactical candidates remain authoritative-legal")
			var target: Vector2i = action["coord"]
			var job := Vector3i(target.x,target.y,model.cells[action["source"]]["unit"])
			jobs[job] = jobs.get(job,0)+1
			departures[action["source"]] = departures.get(action["source"],0)+1
			expect(jobs[job] <= 2 and departures[action["source"]] <= 2, "Diverse candidates bound repeated jobs and departures")
			expect(action["priority"] <= previous_priority, "Diverse candidates retain descending priority")
			previous_priority = action["priority"]
func run() -> void:
	var a := {"priority":2.0, "coord":Vector2i.ZERO}
	var b := {"priority":2.0, "coord":Vector2i.ONE}
	var c := {"priority":1.0, "coord":Vector2i(2, 0)}
	expect(canonical_ties([a,b,c]) == canonical_ties([b,a,c]), "Equivalent moves may swap inside an exact priority tie")
	expect(canonical_ties([a,b,c]) != canonical_ties([a,c,b]) and canonical_ties([a,b,c]) != canonical_ties([a,c]), "Tie normalization preserves ranking and every selected action")
	for mode in ["classic", "modern"]:
		for seed_value in range(8):
			var model = Rules.new()
			model.rule_mode = mode
			model.generate(seed_value, "large", 6)
			query_checks(model)
	for seed_value in [42, 71]:
		for count in [120, 300, 600]:
			query_checks(Fixture.crowded("huge", seed_value, count))
	var crossings = Rules.new()
	crossings.rule_mode = "modern"
	crossings.faction_count = 2
	for q in range(8):
		crossings.cells[Vector2i(q, 0)] = crossings.make_cell(0 if q < 3 else 1 if q > 4 else -1)
		if q in [3, 4]: crossings.cells[Vector2i(q, 0)]["building"] = "bridge"
	crossings.cells[Vector2i(1, 0)]["unit"] = 1
	crossings.cells[Vector2i(3, 0)]["unit"] = 2
	crossings.cells[Vector2i(3, 0)]["unit_owner"] = 0
	crossings.cells[Vector2i(4, 0)]["unit"] = 1
	crossings.cells[Vector2i(4, 0)]["unit_owner"] = 1
	crossings.cells[Vector2i(6, 0)]["unit"] = 3
	crossings.rebuild_kingdoms()
	query_checks(crossings)
	crossings.cells[Vector2i(4, 0)]["unit_owner"] = 0
	crossings.cells[Vector2i(2, 0)]["barrier_by"] = 0
	query_checks(crossings)
	var video = root.get_node("Video")
	var transitions: bool = video.level_transitions
	video.set_preference(&"level_transitions", false, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var board = game.view
	var coord: Vector2i = game.active_capital()
	for unit_coord in board.unit_actors:
		if game.cells[unit_coord]["owner"] == 0:
			coord = unit_coord
			break
	var tile: Node3D = board.tile_nodes[coord]
	var actor: Node3D = board.unit_actors[coord]
	var terrain_count: int = board.static_batches.terrain_rebuild_count
	game.cells[coord]["moved"] = true
	board.render_cells(game.cells)
	await process_frame
	expect(board.tile_nodes[coord] == tile and board.unit_actors[coord] == actor, "Moved tint preserves terrain and actor identity")
	expect(board.static_batches.terrain_rebuild_count == terrain_count, "Moved state does not rebuild merged terrain")
	game.cells[coord]["unit"] = 2
	board.render_cells(game.cells)
	await process_frame
	expect(board.tile_nodes[coord] == tile and board.unit_actors[coord] == actor and actor.get_node("Pips").get_child_count() == 2, "Upgrade updates the existing actor and rank markers")
	expect(board.static_batches.terrain_rebuild_count == terrain_count, "Rank upgrades do not rebuild merged terrain")
	var sprite: Sprite3D
	for child in actor.get_children():
		if child is Sprite3D: sprite = child
	expect(sprite.layers == 0 and board.unit_batches.sprite_slots.has(sprite.get_instance_id()), "Settled sprite is represented by a batch slot")
	var uploads: int = board.unit_batches.upload_count
	board.set_unit_hover(coord)
	await create_timer(0.15).timeout
	expect(board.unit_batches.upload_count == uploads and sprite.get_node("HoverOutline").visible, "Hover fades the existing instance without rebuilding a batch")
	board.clear_unit_hover()
	actor.reparent(board.animation_root, true)
	board.unit_batches.sync()
	expect(sprite.layers != 0, "A moving actor restores its source sprite")
	actor.reparent(tile, true)
	board.unit_batches.sync()
	expect(sprite.layers == 0, "A settled actor returns to its batch")
	board.unit_batches.enabled = false
	board.unit_batches.sync()
	expect(sprite.layers != 0 and not board.unit_batches.visible, "Disabled army batching restores individual actors")
	board.unit_batches.enabled = true
	board.unit_batches.sync()
	var gameplay = root.get_node("Gameplay")
	var clear: bool = gameplay.clear_indicators
	gameplay.set_clear_indicators(true, false)
	game.cells[coord]["moved"] = false
	var valid: Dictionary = game.rules.reachable_targets(coord)
	board.overlays.show_overlays(coord, game.NONE, valid, [], coord)
	var area: Node = board.overlay_root.get_node("ReachableArea")
	for destination in valid:
		board.overlays.show_overlays(coord, destination, valid, [], coord)
		expect(board.overlay_root.get_node("ReachableArea") == area, "Hover retains the same reachable-area mesh")
		break
	gameplay.set_clear_indicators(clear, false)
	game.shutdown()
	game.queue_free()
	await process_frame
	video.set_preference(&"level_transitions", transitions, false)
	print("Army optimization checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
