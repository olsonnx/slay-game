extends SceneTree

var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func fixture(owners: Dictionary, units: Dictionary) -> void:
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for coord in owners:
		game.rules.cells[coord] = game.rules.make_cell(owners[coord])
	game.rules.rebuild_kingdoms()
	for coord in units:
		game.cells[coord]["unit"] = units[coord]
	for kingdom in game.rules.kingdoms.values():
		kingdom["gold"] = 100
	game.selected = game.NONE
	game.active_hex = owners.keys()[0]
	game.action_mode = ""
	game.game_over = false
	game.view.render_cells(game.cells)
	game.refresh_ui()

func wait_for_motion() -> void:
	while game.view.is_animating:
		await process_frame

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var d := Vector2i(3, 0)
	var e := Vector2i(0, 2)
	var f := Vector2i(1, 2)
	var g := Vector2i(2, 2)
	fixture({a: 0, b: 0, c: 0, e: 0, f: 0, g: 0}, {a: 1, e: 1})
	var retained_features: Node3D = game.view.tile_nodes[c].get_node("Features")
	var actor_a: Node3D = game.view.unit_actors[a]
	var actor_e: Node3D = game.view.unit_actors[e]
	var sprite: Sprite3D = game.view.units[0]
	var sprite_position := sprite.position
	var texture := sprite.texture
	await create_timer(0.20).timeout
	expect(sprite.position == sprite_position and sprite.texture != texture and sprite.get_meta("animation") == "idle", "Ready units animate their idle frames without shifting the foot anchor")
	var start_a := actor_a.global_position
	var start_e := actor_e.global_position
	var first: Dictionary = game.rules.perform_move(a, c)
	var second: Dictionary = game.rules.perform_move(e, g)
	expect(first["path"].size() == 3 and second["path"].size() == 3, "Recorded movement follows actual friendly routes")
	expect(game.view.cells[a]["unit"] == 1 and game.cells[a]["unit"] == 0, "Display keeps pre-movement snapshot while rules commit")
	game.view.animate_moves([first, second], game.cells)
	expect(game.view.active_motions.size() == 2, "Two movement tweens start in the same batch")
	await create_timer(0.10).timeout
	expect(actor_a.global_position != start_a and actor_e.global_position != start_e, "Both units visibly travel at once")
	expect(actor_a.global_position.distance_to(game.view.coord_position(c)) > 0.1, "Unit is shown between source and destination")
	expect(sprite.position == sprite_position and sprite.texture != texture and sprite.get_meta("animation") == "run", "Travel animates running frames with a stable foot anchor")
	var shadow: Node3D = actor_a.get_child(0)
	expect(shadow.get_parent() == actor_a and shadow.global_position.x == actor_a.global_position.x, "Shadow travels with the unit group")
	await wait_for_motion()
	expect(game.view.active_motions.is_empty() and game.view.animation_root.get_child_count() == 0, "Batch cleans up temporary travelers")
	expect(game.view.unit_actors.has(c) and game.view.unit_actors.has(g) and not game.view.unit_actors.has(a), "Final unit positions match committed rules")
	expect(game.view.unit_actors[c] == actor_a and game.view.unit_actors[g] == actor_e, "Settled travelers retain their original actors")
	expect(game.view.units.has(sprite), "Settled movement retains its original picking sprite")
	expect(game.view.tile_nodes[c].get_node("Features") == retained_features, "Friendly movement retains unchanged scenery")

	fixture({a: 0, b: 0, c: 1, d: 1}, {a: 2, c: 1})
	actor_a = game.view.unit_actors[a]
	var defender: Node3D = game.view.unit_actors[c]
	var stages: Array = []
	var inspect_attack := func(action: Dictionary, stage: String):
		if action["source"] == a:
			stages.append({"stage": stage, "position": actor_a.global_position,
				"defender_visible": defender.is_visible_in_tree()})
	game.view.motion_stage.connect(inspect_attack)
	var attack: Dictionary = game.rules.perform_move(a, c)
	expect(attack["kind"] == "attack" and attack["before_target"]["unit"] == 1, "Action preserves the enemy defender before capture")
	game.view.animate_moves([attack], game.cells)
	expect(defender.visible, "Defender remains visible while attacker approaches")
	await wait_for_motion()
	game.view.motion_stage.disconnect(inspect_attack)
	expect(stages.size() == 4 and stages[0]["stage"] == "travel" and stages[1]["stage"] == "jab" and stages[2]["stage"] == "impact" and stages[3]["stage"] == "occupy", "Attack plays approach, jab, impact, then occupation")
	expect(stages[1]["defender_visible"] and stages[2]["defender_visible"], "Defender stays visible for its death animation at impact")
	var target_point: Vector3 = game.view.coord_position(c)
	expect(stages[2]["position"].distance_to(target_point) < stages[1]["position"].distance_to(target_point), "Jab lunges toward the defender")
	expect(stages[3]["position"].is_equal_approx(target_point), "Attacker takes the defender's place after the jab")
	expect(game.view.cells[c]["owner"] == 0 and game.view.unit_actors.size() == 1, "Animated capture shows one surviving attacker and updated ownership")
	fixture({a: 0, b: 0, c: 1, d: 1}, {a: 2, c: 1})
	var saved_cells: Dictionary = game.cells.duplicate(true)
	var saved_banks: Dictionary = game.rules.kingdoms.duplicate(true)
	var cancel_on_arrival := func(_action: Dictionary, stage: String):
		if stage == "occupy":
			game.rules.cells = saved_cells.duplicate(true)
			game.rules.kingdoms = saved_banks.duplicate(true)
			game.view.cancel_motion(game.cells)
	game.view.motion_stage.connect(cancel_on_arrival)
	var interrupted: Dictionary = game.rules.perform_move(a, c)
	await game.view.animate_moves([interrupted], game.cells)
	game.view.motion_stage.disconnect(cancel_on_arrival)
	expect(game.cells == saved_cells and game.view.unit_actors.has(a), "Arrival observers can cancel without resurrecting a settled traveler")
	expect(game.view.unit_spawn_effects.get_child_count() == 0, "Cancelled arrivals leave no spawn effects")

	fixture({a: 0, b: 0, c: 0}, {a: 1, b: 1})
	game.cells[b]["moved"] = true
	game.view.render_cells(game.cells)
	defender = game.view.unit_actors[b]
	# Recorded pre-0.2 games can still contain field merges.
	var merge: Dictionary = game.rules.Movement.record_validated_move(game.rules, a, b, [a, b])
	game.view.animate_moves([merge], game.cells)
	await create_timer(0.06).timeout
	expect(defender.visible, "Friendly merge destination remains visible during approach")
	await wait_for_motion()
	expect(game.view.unit_actors.size() == 1 and game.view.cells[b]["unit"] == 2, "Merge finishes as a single stronger unit")
	expect(game.view.cells[b]["moved"] and not game.rules.can_move(b, c), "Merging into a moved ally finishes with its move already spent")
	var merge_effects: Array[Node] = game.view.unit_spawn_effects.get_children()
	expect(merge_effects.size() == 1 and merge_effects[0].get_meta("hex") == b and merge_effects[0].get_meta("tier") == 2, "Merge arrival plays a spawn effect for the resulting rank and survives board synchronization")

	fixture({a: 0, b: 0, c: -1, d: 1, Vector2i(4, 0): 1}, {a: 1})
	game.click_hex(a)
	game.click_hex(c)
	expect(game.busy and game.view.is_animating, "Player command starts a visible animation and locks gameplay")
	var round_before: int = game.round_number
	game.end_turn()
	game.new_game()
	expect(game.round_number == round_before and game.busy, "End turn and restart cannot interrupt a traveling unit")
	var playback_zoom_before: float = game.view.zoom
	game.view.change_zoom(1)
	game.view.navigation._process(0.1)
	expect(game.view.zoom < playback_zoom_before, "Camera zoom remains available during playback")
	while game.busy:
		await process_frame
	expect(game.cells[c]["owner"] == 0 and not game.end_button.disabled, "Player regains control after arrival")

	game.new_game()
	# Two independent fronts per faction make concurrent movement possible.
	# Generated-map plans may deliberately chain captures and require serial playback.
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for faction in range(4):
		for q in range(-1, 8):
			var coord := Vector2i(q, faction * 4 - 6)
			game.cells[coord] = game.rules.make_cell(faction if q >= 0 and q <= 6 else -1)
			game.cells[coord]["value"] = 2
			if q in [1, 5]:
				game.cells[coord]["unit"] = 1
	game.rules.rebuild_kingdoms()
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var turn_order: Array = []
	var simultaneous := {1: 0, 2: 0, 3: 0}
	game.faction_started.connect(func(faction: int):
		turn_order.append(["start", faction])
		expect(game.view.active_motions.is_empty(), "Next faction begins only after prior movements finish"))
	game.faction_finished.connect(func(faction: int):
		turn_order.append(["finish", faction])
		expect(not game.view.is_animating, "Faction completion waits for all its visual actions"))
	game.view.action_started.connect(func(action: Dictionary):
		if game.busy and game.active_faction > 0:
			expect(action["faction"] == game.active_faction, "Visual action belongs to currently displayed faction")
			simultaneous[action["faction"]] = maxi(simultaneous[action["faction"]], game.view.active_motions.size()))
	await game.end_turn()
	expect(turn_order == [["start", 1], ["finish", 1], ["start", 2], ["finish", 2], ["start", 3], ["finish", 3]], "Enemy factions play red, blue, then yellow without overlapping")
	for faction in range(1, 4):
		expect(simultaneous[faction] >= 2, "Each faction's moving units are displayed concurrently")
	expect(game.active_faction == 0 and game.round_number == 2 and not game.busy, "Completed replay restores the player's turn")
	print("Animation checks: %d passed, %d failed" % [checks - failures, failures])
	game.shutdown()
	await process_frame
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	# Let the dummy audio driver retire the streamed ambience before exit.
	await create_timer(1.20).timeout
	quit(1 if failures else 0)
