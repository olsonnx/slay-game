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
	var source := Vector2i.ZERO
	var destination := Vector2i(2, 0)
	for rank in [1, 2, 3]:
		game.rules.cells.clear()
		game.rules.kingdoms.clear()
		for coord in [source, Vector2i(1, 0), destination]:
			game.rules.cells[coord] = game.rules.make_cell(0)
		game.rules.cells[source]["capital"] = 0
		game.rules.cells[source]["unit"] = rank
		game.rules.cells[Vector2i(1, 0)]["building"] = "house"
		game.rules.rebuild_kingdoms()
		game.view.configure_map("small", Vector2(18, 14), game.cells)
		game.view.render_cells(game.cells)
		expect(birds.flocks.size() == 3 and not birds.head_eligible(source), "Fresh units cannot attract a head-perching bird")
		# Ground birds depart, leaving the patient soldier as their only future perch.
		game.cells[destination]["grave"] = true
		game.view.render_cells(game.cells)
		birds._process(2.0)
		for turn in [2, 3]:
			birds.set_round(turn)
			expect(not birds.head_eligible(source), "Fewer than three full stationary turns keeps the helmet unavailable")
		birds.set_round(3)
		expect(not birds.head_eligible(source), "Repeated refreshes within a turn do not age the unit")
		var cells_before: Dictionary = game.view.cells.duplicate(true)
		var rng_before: int = game.rules.rng.state
		birds.set_round(4)
		expect(birds.head_eligible(source), "Three complete stationary turns unlock the unit's head")
		var perched: Array = birds.flocks.filter(func(resident): return resident.get("head_actor", 0) != 0)
		expect(perched.size() == 1 and perched[0]["state"] == "landing", "Only one returning bird lands on the soldier's head")
		if perched.is_empty(): continue
		var resident: Dictionary = perched[0]
		birds._process(1.0)
		var sprite: Sprite3D = resident["birds"][0]
		var actor: Node3D = game.view.unit_actors[source]
		var unit_sprite: Sprite3D = actor.get_node("UnitAnimation").sprite
		var separation: Vector2
		for overhead in [false, true]:
			game.view.reset_camera()
			if overhead: game.view.toggle_top_down()
			birds._process(0.0)
			separation = game.view.camera.unproject_position(sprite.global_position) - game.view.camera.unproject_position(unit_sprite.global_position)
			expect(resident["state"] == "grounded" and separation.y < 0.0 and absf(separation.x) < 8.0, "Rank %d bird sits above the helmet in either camera view" % rank)
		game.view.reset_camera()
		var animator = actor.get_node("UnitAnimation")
		var per_frame_positions: Array[Vector3] = []
		for frame in range(4 if rank < 3 else 8):
			animator.show_idle_frame(frame)
			birds._process(0.0)
			per_frame_positions.append(sprite.global_position)
		if rank < 3:
			var difference := per_frame_positions[1] - per_frame_positions[0]
			expect(difference.distance_to(-game.view.camera.global_basis.y * 0.08) < 0.001, "The perching bird follows the one-pixel head bob in the actual idle frame")
			expect(per_frame_positions[0].distance_to(per_frame_positions[3]) < 0.001, "The bird returns with the head at the end of the idle cycle")
		expect(game.view.cells == cells_before and game.rules.rng.state == rng_before, "Head perching leaves gameplay and RNG untouched")
		var action: Dictionary = game.rules.perform_move(source, destination)
		game.view.animate_moves([action], game.cells)
		expect(resident["state"] == "flying" and not birds.head_eligible(source), "Starting a move immediately scatters the head bird and resets patience")
		while game.view.is_animating: await process_frame
		expect(not birds.head_eligible(destination), "A moved unit starts a fresh stationary wait on arrival")
		birds.set_round(6)
		expect(not birds.head_eligible(destination), "The fresh wait lasts three full turns")
		birds.set_round(7)
		expect(birds.head_eligible(destination), "A moved unit can attract another bird after waiting again")
		# In-place upgrades and ownership changes must not inherit the old unit's age.
		game.cells[destination]["unit"] = 2 if rank == 1 else 1
		game.view.render_cells(game.cells)
		expect(not birds.head_eligible(destination), "An upgraded or replaced unit loses its old stationary age")
		birds.set_round(10)
		expect(birds.head_eligible(destination), "The upgraded unit can earn a new perch")
		game.cells[destination]["owner"] = 1
		game.view.render_cells(game.cells)
		expect(not birds.head_eligible(destination), "Changing unit ownership resets stationary age")
		birds.set_round(12)
		birds.set_round(5)
		expect(not birds.head_eligible(destination), "Rewinding does not inherit stationary age from the future")
		game.view.visible_change_coords = {source: true}
		birds.set_round(1)
		game.view.visible_change_coords = {}
		expect(birds.stationary_units.has(destination), "A scoped rewind rebuilds tracking for untouched units")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Bird head checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
