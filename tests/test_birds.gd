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
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var birds = game.view.birds
	birds.set_process(false)
	expect(birds.flocks.size() == 3, "The entire map contains exactly three independent birds")
	var occupied := {}
	for flock in birds.flocks:
		expect(flock["birds"].size() == 1 and birds.eligible(flock["coord"]), "Each bird perches on a suitable tile")
		var perch: Vector3 = Vector3(flock["coord"].x, 0, flock["coord"].y) + flock["offset"]
		expect(not occupied.has(perch), "Birds sharing a tile have distinct perch positions")
		occupied[perch] = true
	expect(birds.textures.size() == 4 and birds.textures[0].get_image().get_data() != birds.textures[1].get_image().get_data(), "Feather palettes produce distinct sprite colours")
	var saved_cells: Dictionary = game.view.cells.duplicate(true)
	var saved_rng: int = game.rules.rng.state
	var flock: Dictionary = birds.flocks[0]
	var original: Vector2i = flock["coord"]
	birds.scatter(original)
	var due: int = flock["return_round"]
	expect(flock["state"] == "flying" and due in [2, 3], "Disturbed birds leave for one or two complete rounds")
	birds.scatter(original)
	expect(flock["return_round"] == due, "Repeated movement callbacks do not restart a flock's absence")
	birds._process(0.75)
	var bird: Sprite3D = flock["birds"][0]
	expect(bird.position.y > 1.0 and bird.frame in [4, 5, 6, 7] and bird.modulate.a > 0.0 and bird.modulate.a < 1.0, "Birds flap, rise and fade during takeoff")
	birds.set_process(true)
	paused = true
	var clock: float = flock["time"]
	await process_frame
	expect(flock["time"] == clock and not birds.can_process(), "Paused game does not advance cosmetic flight")
	paused = false
	birds.set_process(false)
	birds._process(1.0)
	expect(flock["state"] == "away" and not flock["root"].visible, "Departed birds become hidden without destroying their flock")
	birds.set_round(due - 1)
	expect(flock["state"] == "away", "Refreshing within the waiting period does not return birds early")
	birds.set_round(due)
	expect(flock["state"] == "landing" and flock["coord"] != original and birds.eligible(flock["coord"]), "Birds return to a different suitable tile after their waiting rounds")
	birds._process(0.25)
	expect(bird.position.y > 0.34 and bird.frame >= 4, "Returning birds visibly descend using the flight poses")
	birds._process(1.0)
	expect(flock["state"] == "grounded" and is_equal_approx(bird.modulate.a, 1.0), "Landing finishes in a fully visible grounded flock")
	expect(game.view.cells == saved_cells and game.rules.rng.state == saved_rng, "Bird simulation leaves gameplay cells and seeded RNG untouched")
	for field in ["unit", "capital", "building", "mountain", "grave", "event", "mana_source", "fortified", "barrier_by", "entrenched_by", "treasure"]:
		var test := Vector2i(100, 100)
		var cell: Dictionary = game.rules.make_cell()
		game.view.cells[test] = cell
		cell["tree"] = true
		expect(birds.eligible(test), "Forest tiles allow birds")
		cell[field] = {"unit":1, "capital":0, "building":"house", "mountain":true, "grave":true, "event":"gold", "mana_source":true, "fortified":true, "barrier_by":0, "entrenched_by":0, "treasure":10}[field]
		expect(not birds.eligible(test), "Occupied or special tiles exclude decorative flocks: " + field)
		game.view.cells.erase(test)
	# Exercise real movement through an empty intermediate friendly tile.
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for coord in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]:
		game.rules.cells[coord] = game.rules.make_cell(0)
	game.rules.cells[Vector2i.ZERO]["capital"] = 0
	game.rules.cells[Vector2i.ZERO]["unit"] = 1
	game.rules.rebuild_kingdoms()
	game.view.configure_map("small", Vector2(18, 14), game.cells)
	game.view.render_cells(game.cells)
	flock = birds.flocks[0]
	flock["coord"] = Vector2i(1, 0)
	flock["root"].position = game.view.coord_position(flock["coord"])
	var action: Dictionary = game.rules.perform_move(Vector2i.ZERO, Vector2i(2, 0))
	expect(action.get("path", []).has(Vector2i(1, 0)), "Fixture walks through a flock's intermediate tile")
	game.view.animate_moves([action], game.cells)
	await process_frame
	await process_frame
	expect(flock["state"] == "flying", "A passing animated unit scatters birds before its final board snapshot")
	while game.view.is_animating: await process_frame
	birds._process(2.0)
	for cell in game.view.cells.values(): cell["unit"] = 1
	birds.stationary_units.clear()
	birds.set_round(5)
	expect(flock["state"] == "away", "Birds wait when no safe landing tile is available")
	game.view.cells[Vector2i(3, 0)]["unit"] = 0
	birds.sync()
	expect(flock["state"] == "landing" and flock["coord"] == Vector2i(3, 0), "Waiting flock lands once a new tile becomes available")
	game.view.set_active(false)
	birds._process(0.1)
	expect(not birds.visible, "Inactive boards hide birds")
	game.view.set_active(true)
	birds.set_round(1)
	expect(birds.round_number == 1 and birds.flocks.size() == 3, "Rewinding retains exactly three birds even on tiny maps")
	var shared := Vector2i(3, 0)
	var all_shared := true
	for resident in birds.flocks: all_shared = all_shared and resident["coord"] == shared
	expect(all_shared, "All three birds can share the only safe landing tile")
	birds.scatter(shared, game.view.coord_position(shared) - Vector3.RIGHT)
	var directions := {}
	var durations := {}
	for resident in birds.flocks:
		directions[resident["direction"]] = true
		durations[resident["duration"]] = true
		expect(resident["state"] == "flying" and resident["direction"].dot(Vector3.RIGHT) > 0.0, "Every bird on the entered tile scatters away from the approaching unit")
	expect(directions.size() == 3 and durations.size() == 3, "Birds diverge with individual headings and takeoff durations")
	birds._process(0.4)
	var heights := {}
	for resident in birds.flocks: heights[resident["birds"][0].position.y] = true
	expect(heights.size() == 3, "Scattering birds have independent climb profiles")
	birds._process(2.0)
	for cell in game.view.cells.values(): cell["unit"] = 0
	birds.set_round(4)
	expect(birds.flocks.size() == 3, "Returning birds reuse the same three actors without multiplying")
	var original_visible: Dictionary = game.view.cells
	game.view.cells = {}
	for q in range(1000): game.view.cells[Vector2i(q, 0)] = game.rules.make_cell()
	birds.clear()
	birds.sync()
	expect(birds.flocks.size() == 3, "A huge map still contains only three birds")
	game.view.cells = original_visible
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Bird checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

