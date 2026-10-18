extends SceneTree
## Repeatable CPU/allocation probe; timings are not an FPS benchmark.
const Rules = preload("res://src/game/kingdom_rules.gd")

func _initialize() -> void:
	call_deferred("run")

func measure(task: Callable, repetitions: int) -> float:
	task.call()
	var samples: Array[float] = []
	for sample in range(5):
		var started := Time.get_ticks_usec()
		for index in range(repetitions):
			task.call()
		samples.append(float(Time.get_ticks_usec() - started) / repetitions)
	samples.sort()
	return samples[2]

func mesh_count(node: Node) -> int:
	var total := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		total += mesh_count(child)
	return total

func run() -> void:
	var label := "current"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
	var rules = Rules.new()
	rules.rule_mode = "modern"
	rules.generate(42, "large")
	var initial: Dictionary = rules.cells.duplicate(true)
	# Connected, expanded territory stresses routes and spell highlighting.
	for coord in rules.cells:
		if not rules.is_mountain(coord):
			rules.cells[coord]["owner"] = 0 if coord.x < 5 else 1
	rules.rebuild_kingdoms()
	rules.set_mana(0, 100)
	var source := Rules.NONE as Vector2i
	for coord in rules.cells:
		if rules.unit_faction(coord) == 0 and rules.cells[coord]["unit"] > 0:
			source = coord
			break
	var metrics := {"label": label, "tiles": rules.cells.size()}
	metrics["mana_hud_query_us"] = measure(func():
		if rules.has_method("mana_summary"):
			rules.mana_summary(0)
		else:
			rules.get_mana(0)
			rules.mana_income(0)
			rules.mana_capacity(0)
			rules.mana_regeneration(0), 100)
	metrics["reachable_targets_us"] = measure(func(): rules.reachable_targets(source), 40)
	metrics["all_spell_targets_us"] = measure(func():
		for spell in rules.Spells.SPELLS:
			if rules.has_method("spell_targets"):
				rules.spell_targets(spell, 0)
			else:
				for coord in rules.cells:
					rules.can_cast(spell, coord, 0), 2)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	game.initial_map_size = "large"
	root.add_child(game)
	game.set_process(false)
	game.rules.set_effect(0, "free_spell", true)
	game.rules.set_effect(0, "trailblaze", true)
	game.refresh_ui()
	await process_frame
	var icon: Node = game.effect_row.get_child(0)
	metrics["hud_refresh_us"] = measure(func(): game.refresh_ui(), 20)
	metrics["status_icon_retained"] = game.effect_row.get_child(0) == icon
	var screen: Vector2 = game.view.camera.unproject_position(game.view.coord_position(game.active_capital()))
	metrics["stationary_pick_us"] = measure(func(): game.view.pick_at_screen(screen), 200)
	var marks := 0
	var meshes := 0
	for coord in game.view.tile_nodes:
		var relief: Node = game.view.tile_nodes[coord].get_node_or_null("Features/EventRelief")
		if relief != null:
			marks += 1
			meshes += mesh_count(relief)
	metrics["event_markers"] = marks
	metrics["event_mesh_instances"] = meshes
	metrics["seeded_board_unchanged"] = initial == game.rules.cells
	var output := FileAccess.open("res://artifacts/performance_%s.json" % label, FileAccess.WRITE)
	output.store_string(JSON.stringify(metrics, "\t"))
	output.close()
	print(JSON.stringify(metrics))
	game.queue_free()
	root.get_node("Sound").stop_all()
	await create_timer(1.20).timeout
	quit()
