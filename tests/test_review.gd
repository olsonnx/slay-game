extends SceneTree

const Rules = preload("res://src/game/kingdom_rules.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var rules = Rules.new()
	var source := Vector2i(-1, 0)
	var target := Vector2i.ZERO
	for coord in [source, Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0)]:
		rules.cells[coord] = rules.make_cell(0)
	rules.cells[source]["unit"] = 1
	rules.cells[target] = rules.make_cell(-1)
	rules.rebuild_kingdoms()
	var targets: Dictionary = rules.reachable_targets(source)
	var path: Array = rules.movement_path(source, target)
	expect(path == [source, target], "Border capture chooses the nearest friendly approach, not the first neighbor")
	expect(rules.movement_path(source, target, targets) == path, "Cached route preview agrees with a fresh shortest path")
	var action: Dictionary = rules.perform_move(source, target)
	expect(action["path"] == path and rules.cells[target]["owner"] == 0, "Recorded command uses the shortest path and still captures")
	var game = load("res://scenes/main.tscn").instantiate()
	var ai = Rules.new()
	ai.rule_mode = "modern"
	for coord in [Vector2i(-3, 0), Vector2i(-2, 0), Vector2i(0, 0), Vector2i(1, 0)]:
		ai.cells[coord] = ai.make_cell(0)
		ai.cells[coord]["unit"] = 1
	ai.cells[Vector2i(-3, 0)]["capital"] = 0
	ai.cells[Vector2i(1, 0)]["capital"] = 0
	ai.rebuild_kingdoms()
	for bank in ai.kingdoms.values():
		bank["gold"] = 60
	# Four value-1 provinces and four Scouts settle before any purchases.
	# Read the current wage table so balance edits cannot stale this invariant.
	var settled_gold: int = 120 + 4 - 4 * ai.Catalog.unit_upkeep(1, true)
	ai.prepare_ai_turn(0)
	expect(ai.kingdoms.size() == 1 and ai.is_bridge(Vector2i(-1, 0)), "AI can connect its separate kingdoms with a bridge")
	var spent := 15
	for coord in ai.cells:
		if ai.is_bridge(coord):
			continue
		for value in range(1, ai.cells[coord]["value"]):
			spent += 2 * value * value
	expect(ai.kingdoms.values()[0]["gold"] == settled_gold - spent, "Merged treasury accounts once for income, wages, bridge and actual development")
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var before: int = game.view.tiles_built
	var existing: Dictionary = game.view.tile_nodes.duplicate()
	game.view.render_cells(game.cells)
	expect(game.view.tiles_built == before, "An unchanged board allocates no replacement tiles")
	for coord in existing:
		expect(game.view.tile_nodes[coord] == existing[coord], "Unchanged tile retains its scene identity")
	var changed := game.NONE as Vector2i
	for coord in game.cells:
		if game.cells[coord]["unit"] == 0 and game.cells[coord]["capital"] < 0:
			changed = coord
			break
	var previous_features: Node = game.view.tile_nodes[changed].get_node("Features")
	game.cells[changed]["tree"] = not game.cells[changed]["tree"]
	game.view.render_cells(game.cells)
	expect(game.view.tiles_built == before, "One prop change allocates no replacement terrain tiles")
	expect(game.view.tile_nodes[changed] == existing[changed] and game.view.tile_nodes[changed].get_node("Features") != previous_features, "Changed props are replaced while retaining their terrain tile")
	var topology_before: int = game.view.tiles_built
	game.cells[changed]["kingdom"] = Vector2i(123, 123)
	game.view.render_cells(game.cells)
	expect(game.view.tiles_built == topology_before, "Membership-only updates do not rebuild geometry")
	expect(game.view.cylinder_mesh(0.2, 0.3, 0.6) == game.view.cylinder_mesh(0.2, 0.3, 0.6), "Identical cylinder geometry shares a mesh resource")
	expect(game.view.roof_mesh(1, 1, 0.4) == game.view.roof_mesh(1, 1, 0.4), "Identical roofs reuse geometry")
	expect(game.view.building_icon("house") == game.view.building_icon("house"), "Repeated shop openings reuse building icons")
	game.rmb_down = true
	game.rmb_can_rotate = true
	game.view.rotating = true
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect(not game.rmb_down and not game.view.rotating, "Losing window focus cannot leave camera orbit stuck")
	for coord in game.cells:
		var point: Vector3 = game.view.coord_position(coord) + Vector3(0.2, 0, 0.1)
		expect(game.view.BoardPicker.terrain_at_point(game.view, point) == coord, "Direct axial picking identifies an interior point on every tile")
	var edge: Vector3 = game.view.coord_position(game.cells.keys()[0]) + Vector3(sqrt(3.0) / 2, 0, 0)
	expect(game.view.BoardPicker.terrain_at_point(game.view, edge) == game.NONE, "The gap between shrunken hexes remains unpickable")
	var finished: Array = []
	var completion_callback := func(event: Dictionary): finished.append(event)
	game.view.action_finished.connect(completion_callback)
	game.view.play_preparation([{"coord": changed, "kind": "build"}], game.cells)
	game.view.cancel_motion(game.cells)
	await create_timer(0.40).timeout
	expect(finished.is_empty() and not game.view.is_animating and game.view.playback.preparation_tween == null, "Cancelling preparation stops its hold and prevents late completion callbacks")
	game.view.action_finished.disconnect(completion_callback)
	print("Review regression checks: %d passed, %d failed" % [checks - failures, failures])
	root.get_node("Sound").stop_all()
	await create_timer(0.1).timeout
	quit(1 if failures else 0)
