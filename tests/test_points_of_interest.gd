extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Treasure = preload("res://src/game/treasure_placement.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func fixture():
	var model = Rules.new()
	model.rule_mode = "modern"
	for q in range(9): model.cells[Vector2i(q, 0)] = model.make_cell(0 if q < 7 else -1)
	for q in [10, 11, 12]: model.cells[Vector2i(q, 0)] = model.make_cell(1)
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.cells[Vector2i(10, 0)]["capital"] = 1
	model.cells[Vector2i(6, 0)]["unit"] = 1
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank["gold"] = 200
	return model
func capital_checks() -> void:
	var model = fixture()
	var replay = Replay.new()
	model.replay_log = replay
	replay.start(model)
	model.cells[Vector2i.ZERO]["fortified"] = true
	model.cells[Vector2i.ZERO]["fortified_by"] = 0
	expect(model.capital_relocation_cost(0) == 10, "First relocation costs 10 G")
	expect(model.relocate_capital(Vector2i(2, 0), 0), "Capital can move within its territory")
	expect(model.kingdom_at(Vector2i.ZERO)["capital"] == Vector2i(2, 0) and model.kingdom_at(Vector2i.ZERO)["gold"] == 190, "Relocation preserves the local treasury minus the price")
	expect(model.cells[Vector2i.ZERO]["capital"] == -1 and model.cells[Vector2i(2, 0)]["capital"] == 0, "Exactly one capital moves")
	expect(model.cells[Vector2i(2, 0)]["fortified"] and not model.cells[Vector2i.ZERO]["fortified"], "The capital's existing ward moves with the city")
	expect(model.capital_relocation_cost(0) == 20 and model.capital_relocation_cost(1) == 10, "Price increases per color independently")
	var decoded := Replay.read_records(replay.records)
	expect(decoded.get("error") == "" and decoded["position"]["capital_relocations"].get(0) == 1, "Replay captures relocation history")
	model.cells[Vector2i(3, 0)]["owner"] = -1
	model.rebuild_kingdoms()
	expect(model.capital_relocation_cost(0) == 20, "Splitting territory does not reset the price")
	var split: Dictionary = model.kingdom_at(Vector2i(4, 0))
	split["gold"] = 100
	var target := Vector2i(5, 0) if split["capital"] != Vector2i(5, 0) else Vector2i(6, 0)
	expect(model.relocate_capital(target, 0) and model.kingdom_at(target)["gold"] == 80, "Another territory of the same color pays the increased price locally")
	model.cells[target]["owner"] = 1
	model.cells[target]["capital"] = -1
	model.rebuild_kingdoms()
	expect(model.capital_relocation_cost(0) == 30, "Capital destruction and replacement do not reset relocation history")
	model = fixture()
	var site := Vector2i(2, 0)
	for obstacle in ["tree", "grave", "mountain"]:
		model.cells[site][obstacle] = true
		expect(not model.relocate_capital(site, 0), "Blocked land rejects relocation without charging")
		model.cells[site][obstacle] = false
	for building in ["house", "tower", "bridge"]:
		model.cells[site]["building"] = building
		expect(not model.relocate_capital(site, 0), "Existing structures cannot be overwritten")
	model.cells[site]["building"] = ""
	model.cells[site]["barrier_by"] = 0
	expect(not model.relocate_capital(site, 0), "Barriers block capital placement")
	model.cells[site]["barrier_by"] = -1
	expect(not model.relocate_capital(Vector2i.ZERO, 0) and not model.relocate_capital(Vector2i(10, 0), 0) and not model.relocate_capital(Vector2i(7, 0), 0), "Current capital, rival and neutral sites are invalid")
	model.kingdom_at(site)["gold"] = 9
	expect(not model.relocate_capital(site, 0) and model.capital_relocation_cost(0) == 10, "Failed purchases leave history unchanged")
	model.kingdom_at(site)["gold"] = 200
	model.cells[site]["unit"] = 2
	model.cells[Vector2i(0, 1)] = model.make_cell()
	model.cells[Vector2i(0, 1)].merge({"building":"bridge", "unit":1, "unit_owner":0, "unit_home":Vector2i.ZERO}, true)
	expect(model.relocate_capital(site, 0) and model.cells[site]["unit"] == 2, "A garrison may share the new capital")
	expect(model.cells[Vector2i(0, 1)]["unit_home"] == site and not model.unit_kingdom(Vector2i(0, 1)).is_empty(), "Bridge garrisons retain their home treasury")
	var snapshot = model.KingdomAI.Analysis.snapshot(model)
	expect(snapshot.capital_relocations == model.capital_relocations, "AI snapshots preserve faction relocation history")
	model.generate(42)
	expect(model.capital_relocation_cost(0) == 10, "A new match resets relocation history")
func chest_checks() -> void:
	var model = fixture()
	var source := Vector2i(6, 0)
	var target := Vector2i(7, 0)
	model.cells[target]["treasure"] = Treasure.GOLD
	var before: int = model.kingdom_at(source)["gold"]
	var action: Dictionary = model.perform_move(source, target)
	expect(action.get("gold_reward") == 15 and model.kingdom_at(target)["gold"] == before + 15, "Capturing a chest pays the supporting local treasury")
	expect(model.cells[target].get("treasure", 0) == 0 and model.pending_events.is_empty() and model.cells[target]["unit"] == 1, "Chests are safe, consumed once and require no encounter popup")
	model.cells[target]["moved"] = false
	model.perform_move(target, source)
	expect(model.kingdom_at(source)["gold"] == before + 15, "Returning to a collected chest cannot pay again")
	model = fixture()
	model.cells[target].merge({"treasure":15, "fortified":true, "fortified_by":1}, true)
	before = model.kingdom_at(source)["gold"]
	action = model.perform_move(source, target)
	expect(action.get("gold_reward") == 0 and model.cells[target].get("treasure") == 15 and model.kingdom_at(source)["gold"] == before, "Removing a ward does not collect treasure")
	model = fixture()
	var side := Vector2i(6, 1)
	model.cells[side] = model.make_cell()
	model.cells[side]["treasure"] = 15
	for backend in [model.KingdomAI.Planner, model.KingdomAI.Strategist]:
		var planner = backend.new(model, 0)
		var choice: Dictionary = planner.run()
		expect(choice.get("coord") == side, "Both AI planners value guaranteed treasure over comparable ordinary land")
	expect(model.cells[side].get("treasure") == 15 and model.kingdom_at(source)["gold"] == 200, "Treasure analysis never collects the live reward")
	var totals := {}
	for size_id in Rules.MapSizes.IDS:
		var total := 0
		for seed_value in range(6):
			model = Rules.new()
			model.rule_mode = "modern"
			model.generate(seed_value, size_id)
			var chests: Array = []
			var events := 0
			for coord in model.cells:
				var cell: Dictionary = model.cells[coord]
				if cell["event"] != "": events += 1
				if cell.get("treasure", 0) == 0: continue
				chests.append(coord)
				expect(cell["owner"] == -1 and cell["event"] == "" and not cell["mountain"] and not cell["mana_source"] and not cell["tree"], "Chests occupy clear neutral land, distinct from encounters")
				expect(Treasure.site_score(model, coord, model.kingdoms.keys()) >= 4, "Chest placement stays away from starting capitals")
				for other in chests:
					if other != coord: expect(model.distance(coord, other) >= 6, "Treasure sites remain widely spaced")
			expect(chests.size() < events, "Chests are rarer than encounters")
			total += chests.size()
			var repeat = Rules.new()
			repeat.rule_mode = "modern"
			repeat.generate(seed_value, size_id)
			expect(repeat.cells == model.cells and repeat.rng.state == model.rng.state, "Chest generation remains deterministic")
			totals[size_id] = total
	print("Chest totals across six maps per size: ", totals)
	expect(totals["small"] == 0, "Tiny maps never generate treasure")
	expect(totals["medium"] > 0 and totals["large"] > 0 and totals["very_large"] > 0 and totals["huge"] > totals["large"], "Treasure starts at Small and scales on larger maps")
func ui_checks() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.view.cancel_level_transition()
	game.rules = fixture()
	game.active_hex = Vector2i.ZERO
	game.view.render_cells(game.cells)
	game.inspect_province(Vector2i(2, 0))
	var panel = game.province_view
	expect(panel.relocate_button.visible and not panel.relocate_button.disabled and panel.relocate_button.position.y == panel.develop_button.position.y, "Relocation appears alongside development")
	panel.relocate_button.pressed.emit()
	expect(panel.relocate_button.text == "" and panel.relocate_button.icon != null, "Capital action uses an icon with a cost tooltip")
	expect(game.event_shade.visible and game.commands_locked() and game.rules.kingdom_at(Vector2i.ZERO)["gold"] == 200, "Icon asks for confirmation without spending gold")
	var value_before: int = game.rules.cells[Vector2i(2, 0)]["value"]
	game.develop_province()
	expect(game.rules.cells[Vector2i(2, 0)]["value"] == value_before, "Confirmation blocks other purchases behind the modal")
	expect(game.event_panel.get_node("ConfirmationDetail").text.contains("20"), "Confirmation shows the next relocation price")
	expect(game.event_panel.get_node("EventChoice1").has_focus(), "Cancel has keyboard focus to avoid accidental confirmation")
	game.event_panel.get_node("EventChoice1").pressed.emit()
	expect(not game.event_shade.visible and game.rules.capital_relocation_cost(0) == 10, "Cancel preserves the city and price")
	panel.relocate_button.pressed.emit()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	expect(not game.event_shade.visible and game.rules.kingdom_at(Vector2i.ZERO)["gold"] == 200, "Escape cancels relocation without spending")
	panel.relocate_button.pressed.emit()
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	game._input(right_click)
	expect(not game.event_shade.visible and game.rules.capital_relocation_cost(0) == 10, "Right-click also dismisses confirmation safely")
	panel.relocate_button.pressed.emit()
	game.event_panel.get_node("EventChoice0").pressed.emit()
	expect(game.rules.cells[Vector2i(2, 0)]["capital"] == 0 and game.money_label.text == "190 G", "Province action updates the capital and HUD")
	game.resolve_capital_relocation(0)
	expect(game.rules.capital_relocation_cost(0) == 20 and game.rules.kingdom_at(Vector2i(2, 0))["gold"] == 190, "Repeated confirmation cannot charge twice")
	game.inspect_province(Vector2i(1, 0))
	expect(panel.relocate_button.tooltip_text.contains("20") and not panel.relocate_button.disabled, "Another province displays the increased price in the tooltip")
	panel.relocate_button.pressed.emit()
	game.rules.kingdom_at(Vector2i(1, 0))["gold"] = 0
	game.resolve_capital_relocation(0)
	expect(game.rules.cells[Vector2i(2, 0)]["capital"] == 0 and game.rules.capital_relocation_cost(0) == 20, "Confirm revalidates funds before changing the city")
	game.busy = true
	game.refresh_province()
	expect(panel.relocate_button.disabled, "Relocation is disabled during opponent playback")
	game.busy = false
	game.rules.cells[Vector2i(7, 0)]["treasure"] = 15
	game.view.render_cells(game.cells)
	game.inspect_province(Vector2i(7, 0))
	expect(panel.mana_label.text.contains("15") and not panel.relocate_button.visible, "Chest inspector advertises its guaranteed reward")
	expect(game.view.tile_nodes[Vector2i(7, 0)].get_node_or_null("Features/TreasureChest") != null, "Treasure uses a distinct chest model")
	game.view.focus = game.view.coord_position(Vector2i(7, 0))
	game.view.zoom = 9.0
	game.view.update_camera()
	var lid: Vector2 = game.view.camera.unproject_position(game.view.coord_position(Vector2i(7, 0)) + Vector3(0, 0.54, 0))
	expect(game.view.hex_at_screen(lid) == Vector2i(7, 0), "Clicking a chest lid selects its province")
	game.rules.kingdom_at(Vector2i(1, 0))["gold"] = 100
	game.inspect_province(Vector2i(1, 0))
	panel.relocate_button.pressed.emit()
	game.new_game(42)
	expect(game.pending_capital_relocation.is_empty() and not game.event_shade.visible, "Restart discards any pending relocation confirmation")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
func run() -> void:
	capital_checks()
	chest_checks()
	await ui_checks()
	print("Points of interest checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
