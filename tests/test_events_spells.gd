extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fixture():
	var rules = Rules.new()
	rules.rule_mode = "modern"
	for q in range(5):
		rules.cells[Vector2i(q, 0)] = rules.make_cell(0 if q < 3 else -1)
	for q in range(2):
		rules.cells[Vector2i(q, 1)] = rules.make_cell(1)
	rules.cells[Vector2i(0, 0)]["capital"] = 0
	rules.cells[Vector2i(0, 1)]["capital"] = 1
	rules.cells[Vector2i(1, 0)]["unit"] = 1
	for cell in rules.cells.values():
		cell["mana_source"] = true
	rules.rebuild_kingdoms()
	rules.set_mana(0, 20)
	return rules

func event_sites(rules) -> Array:
	var result := []
	for coord in rules.cells:
		if rules.cells[coord]["event"] != "": result.append(coord)
	return result

func test_event_scaling() -> void:
	var sizes = preload("res://src/game/map_sizes.gd")
	var totals := {}
	for size_id in sizes.IDS:
		var total := 0
		for count in [2, sizes.MAX_KINGDOMS[size_id]]:
			for seed_value in range(8):
				var rules = Rules.new()
				rules.rule_mode = "modern"
				rules.generate(seed_value, size_id, count)
				var sites := event_sites(rules)
				total += sites.size()
				expect(not sites.is_empty(), "Every supported size/count offers encounters when eligible land exists")
				for index in range(sites.size()):
					var coord: Vector2i = sites[index]
					var cell: Dictionary = rules.cells[coord]
					expect(cell["owner"] == -1 and not rules.is_mountain(coord) and not cell["mana_source"] and rules.Events.EVENTS.has(cell["event"]), "Events occupy eligible neutral land and use valid event definitions")
					for other in sites.slice(index + 1):
						expect(rules.distance(coord, other) >= 3, "More events retain three-hex spacing")
				var repeat = Rules.new()
				repeat.rule_mode = "modern"
				repeat.generate(seed_value, size_id, count)
				expect(repeat.cells == rules.cells and repeat.rng.state == rules.rng.state, "Scaled encounters remain deterministic, including their types and RNG")
			totals[size_id] = total
	print("Event totals across 16 maps per size: ", totals)
	expect(totals["huge"] > totals["small"] * 5 and totals["very_large"] > totals["large"] * 2, "Exploration events grow substantially with land area, independent of kingdom count")
	# Actual usable area drives density even if a caller supplies a different size label.
	var custom = Rules.new()
	custom.rule_mode = "modern"
	custom.faction_count = 2
	custom.map_size = "very_small"
	for q in range(16):
		for r in range(16): custom.cells[Vector2i(q * 3, r * 3)] = custom.make_cell()
	custom.rng.seed = 42
	custom.magic.generate_events(custom)
	expect(event_sites(custom).size() == 16, "256 well-spaced neutral tiles receive 16 encounters regardless of the preset label")
	var empty = Rules.new()
	empty.rule_mode = "modern"
	empty.cells[Vector2i.ZERO] = empty.make_cell(0)
	empty.cells[Vector2i.ONE] = empty.make_cell()
	empty.cells[Vector2i.ONE]["mountain"] = true
	empty.magic.generate_events(empty)
	expect(event_sites(empty).is_empty(), "No eligible land produces no events instead of forcing an invalid placement")
	var cramped = Rules.new()
	cramped.rule_mode = "modern"
	cramped.cells[Vector2i.ZERO] = cramped.make_cell()
	cramped.magic.generate_events(cramped)
	expect(event_sites(cramped).size() == 1, "Crowded maps stop safely when the desired event count cannot fit")
	var crossing = Rules.new()
	crossing.rule_mode = "modern"
	crossing.cells[Vector2i.ZERO] = crossing.make_cell()
	crossing.cells[Vector2i.ZERO]["building"] = "bridge"
	crossing.magic.generate_events(crossing)
	expect(event_sites(crossing).is_empty(), "Generated encounters never land on neutral bridge structures")

func run() -> void:
	test_event_scaling()
	var r = fixture()
	var cap := Vector2i(0, 0)
	var source := Vector2i(1, 0)
	var gap := Vector2i(2, 0)
	var neutral := Vector2i(3, 0)
	expect(r.cast_spell("trailblaze", cap, 0), "Trailblaze casts")
	expect(not r.cast_spell("trailblaze", cap, 0), "Trailblaze cannot stack")
	expect(r.move_unit(source, neutral), "Blessed unit captures neutral land")
	expect(not r.cells[neutral]["moved"] and not r.has_effect(0, "trailblaze"), "Neutral capture grants exactly one extra action")
	expect(r.move_unit(neutral, Vector2i(4, 0)) and r.cells[Vector2i(4, 0)]["moved"], "Second move is spent normally")
	r = fixture()
	r.set_effect(0, "trailblaze", true)
	expect(r.move_unit(source, gap) and r.cells[gap]["moved"] and not r.has_effect(0, "trailblaze"), "Friendly move consumes blessing without bonus")
	r = fixture()
	for removed in ["fortify","grove","barrier"]:
		expect(not r.cast_spell(removed,gap,0), "Removed spells cannot be cast: " + removed)
	r.set_effect(0, "free_spell", true)
	r.set_mana(0, 0)
	expect(not r.cast_spell("summon", source, 0) and r.has_effect(0, "free_spell"), "Invalid cast preserves gift")
	expect(r.cast_spell("trailblaze", cap, 0) and r.get_mana(0) == 0 and not r.has_effect(0, "free_spell"), "Gift bypasses cost and is consumed on success")
	r.set_effect(0, "free_spell", true)
	expect(r.has_effect(0, "trailblaze") and r.has_effect(0, "free_spell"), "Two effects coexist")
	for id in ["gold", "altar", "pit", "duel", "wizard", "goose"]:
		r = fixture()
		r.cells[neutral]["event"] = id
		if id == "altar": r.cells[neutral]["mana_source"] = false
		var action: Dictionary = r.perform_move(source, neutral)
		expect(not action.is_empty() and r.pending_events.size() == 1 and r.cells[neutral]["event"] == "", "Capture queues one event: " + id)
		var event: Dictionary = r.pending_events[0]
		expect(r.resolve_event(event, 99) == "" and r.pending_events.size() == 1, "Invalid choice preserves event")
		var gold: int = r.kingdom_at(neutral)["gold"]
		var choice := 1 if id in ["altar", "duel"] else 0
		expect(r.resolve_event(event, choice) != "" and r.pending_events.is_empty(), "Valid choice resolves event")
		expect(r.resolve_event(event, choice) == "", "Event cannot resolve twice")
		if id == "gold":
			var delta: int = r.kingdom_at(neutral)["gold"] - gold
			expect(delta >= 10 and delta <= 25, "Stash reward lies within disclosed range")
		if id == "pit": expect(r.cells[neutral]["unit"] == 0 and r.cells[neutral]["grave"] and r.cells[neutral]["owner"] == 0, "Pit kills unit but preserves land")
		if id == "wizard": expect(r.has_effect(0, "free_spell"), "Wizard grants gift")
		if id in ["altar", "duel", "goose"]: expect(r.cells[neutral]["unit"] == 1, "Peaceful choice preserves unit")
	# Guaranteed rewards are rolled once for presentation and paid verbatim.
	r = fixture()
	r.cells[neutral]["event"] = "gold"
	r.perform_move(source, neutral)
	var gold_event: Dictionary = r.pending_events[0]
	var shared_gold: Dictionary = r.Events.EVENTS["gold"].duplicate(true)
	var prepared: Dictionary = r.event_definition(gold_event)
	var exact_reward: int = gold_event["gold_reward"]
	var prepared_rng: int = r.rng.state
	var treasury_before: int = r.kingdom_at(neutral)["gold"]
	expect(exact_reward >= 10 and exact_reward <= 25 and prepared["choices"][0][1].contains(str(exact_reward)), "Guaranteed gold preview contains the actual reward")
	r.event_definition(gold_event)
	expect(r.rng.state == prepared_rng and gold_event["gold_reward"] == exact_reward, "Refreshing an event never rerolls its disclosed reward")
	expect(r.resolve_event(gold_event, 99) == "" and r.rng.state == prepared_rng, "Invalid choice preserves the prepared reward and RNG")
	r.resolve_event(gold_event, 0)
	expect(r.kingdom_at(neutral)["gold"] == treasury_before + exact_reward and r.rng.state == prepared_rng, "Acknowledging the event awards exactly the displayed amount without another roll")
	expect(r.Events.EVENTS["gold"] == shared_gold, "Exact reward presentation leaves the shared event catalogue unchanged")
	for id in ["altar", "duel"]:
		var successes := 0
		var deaths := 0
		for seed_value in range(40):
			r = fixture()
			r.rng.seed = seed_value
			r.cells[neutral]["mana_source"] = false
			r.cells[neutral]["event"] = id
			r.perform_move(source, neutral)
			r.resolve_event(r.pending_events[0], 0)
			if r.cells[neutral]["unit"] == 0: deaths += 1
			else:
				successes += 1
				expect(r.cells[neutral]["mana_source"] if id == "altar" else r.cells[neutral]["unit"] == 2, "Successful risky outcome applies")
		expect(successes > 0 and deaths > 0, "Risky event exercises both branches: " + id)
	r = fixture()
	r.cells[source]["unit"] = 3
	r.cells[neutral]["event"] = "duel"
	r.perform_move(source, neutral)
	for seed_value in range(100):
		r.rng.seed = seed_value
		if r.rng.randf() < 0.60:
			r.rng.seed = seed_value
			break
	var gold: int = r.kingdom_at(neutral)["gold"]
	r.resolve_event(r.pending_events[0], 0)
	expect(r.cells[neutral]["unit"] == 3 and r.kingdom_at(neutral)["gold"] == gold + 20, "Knight receives gold instead of fourth tier")
	for size_id in ["very_small", "small", "medium", "large"]:
		r = Rules.new()
		r.rule_mode = "modern"
		r.generate(42, size_id)
		var before: Dictionary = r.cells.duplicate(true)
		var markers := 0
		var eligible := 0
		for coord in r.cells:
			if r.cells[coord]["owner"] == -1 and not r.is_mountain(coord) and not r.cells[coord]["mana_source"]: eligible += 1
			if r.cells[coord]["event"] != "":
				markers += 1
				expect(r.cells[coord]["owner"] == -1 and not r.is_mountain(coord), "Events spawn only on neutral passable land")
		expect(markers >= 2 and markers <= maxi(r.faction_count + 1, roundi(eligible / 16.0)), "Event counts scale with usable neutral land and fit the density budget")
		r.generate(42, size_id)
		expect(r.cells == before, "Restart reproduces markers")
	await ui_checks()
	root.get_node("Sound").stop_all()
	# Allow the dummy audio driver's mixing clock to retire MP3 playback.
	await create_timer(1.20).timeout
	print("Events/spells checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures > 0 else 0)

func ui_checks() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	root.add_child(game)
	await process_frame
	var original_mana: int = game.rules.get_mana(0)
	game.rules.set_mana(0, 2)
	var barrier_coord := game.NONE as Vector2i
	for coord in game.cells:
		if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] == 0 and game.cells[coord]["capital"] < 0 and game.cells[coord]["building"] == "":
			barrier_coord = coord
			break
	expect(barrier_coord != game.NONE, "Legacy barrier fixture has clear owned land")
	if barrier_coord != game.NONE:
		game.cells[barrier_coord]["barrier_by"] = 0 # Stored legacy effect, no longer castable.
		game.view.render_cells(game.cells)
		var tile: Node3D = game.view.tile_nodes[barrier_coord]
		expect(tile.has_node("Barrier") and not tile.has_node("Fortification"), "Barrier uses side walls instead of the fortification sphere")
		var walls := 0
		for child in tile.get_children():
			expect(not child is Label3D, "Barrier tile has no floating symbol")
		for child in tile.get_node("Barrier").get_children():
			if child.name.begins_with("Wall"):
				walls += 1
				expect(child.material_override.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and child.material_override.albedo_color.a > 0.0 and child.material_override.albedo_color.a < 0.5, "Barrier walls are translucent")
		expect(walls == 6, "A wall rises from each hex side")
		game.rules.cells[barrier_coord]["barrier_by"] = -1
		game.view.render_cells(game.cells)
		expect(not game.view.tile_nodes[barrier_coord].has_node("Barrier"), "Expired barrier removes all walls")
	game.rules.set_mana(0, original_mana)
	game.rules.set_effect(0, "trailblaze", true)
	game.rules.set_effect(0, "free_spell", true)
	game.refresh_ui()
	expect(game.effect_row.get_child_count() == 2, "HUD displays both active effects")
	for icon in game.effect_row.get_children():
		expect(icon.custom_minimum_size == Vector2(48, 48) and not icon.tooltip_text.is_empty(), "Effects are square with tooltips")
	game.open_shop("spells")
	expect(game.shop_items.get_child_count() == 3 and game.shop_panel.size.y == 188, "All three spells fit a single-row menu with balanced header and footer spacing")
	game.rules.set_effect(0, "free_spell", false)
	game.rules.cells[game.active_capital()]["unit"] = 1
	var event := {"id": "wizard", "coord": game.active_capital(), "faction": 0}
	game.rules.pending_events.append(event)
	game.show_next_event()
	expect(game.event_shade.visible and game.commands_locked(), "Event is modal")
	expect(game.event_panel.reveal < 1.0 and game.event_shade.color.a < 0.78, "Panel and shade ease in while already blocking commands")
	await process_frame
	await process_frame
	await create_timer(0.30).timeout
	expect(is_equal_approx(game.event_panel.reveal, 1.0) and is_equal_approx(game.event_shade.color.a, 0.78), "Event entrance settles with full panel and dimming (reveal %.3f, shade %.3f)" % [game.event_panel.reveal, game.event_shade.color.a])
	var round_before: int = game.round_number
	game.end_turn()
	game.cancel_action()
	expect(game.event_shade.visible and game.round_number == round_before, "Cannot skip event or end turn")
	game.resolve_shown_event(0)
	expect(not game.event_shade.visible and game.rules.pending_events.is_empty(), "Choice closes popup")
	for id in ["gold", "lumberjack"]:
		game.event_dialog.present(game.rules.Events.EVENTS[id], func(_choice): pass)
		expect(game.event_shade.visible and game.event_panel.reveal == 0.0 and game.event_shade.color.a == 0.0, "Both event types begin hidden but modal: " + id)
		await process_frame
		expect(game.event_panel.reveal == 0.0, "Layout frame does not advance the entrance: " + id)
		await process_frame
		await create_timer(0.30).timeout
		expect(is_equal_approx(game.event_panel.reveal, 1.0) and is_equal_approx(game.event_shade.color.a, 0.78), "Illustrated and plain entrances both settle: " + id)
		game.close_event_ui()
	game.event_dialog.present(game.rules.Events.EVENTS["lumberjack"], func(_choice): pass)
	game.close_event_ui()
	await process_frame
	await process_frame
	await process_frame
	expect(not game.event_shade.visible and not game.event_panel.visible and game.event_panel.reveal == 0.0, "Closing during painting preparation cannot reopen the dialog")
	for id in game.rules.Events.EVENTS:
		var encounter := {"id": id, "coord": game.active_capital(), "faction": 0}
		if game.rules.Events.EVENTS[id].has("authored"):
			game.rules.magic.Encounters.Authored.prepare(game.rules, game.rules.Events.EVENTS[id].authored, encounter)
		game.rules.pending_events.append(encounter)
		game.show_next_event()
		await process_frame
		await process_frame
		await create_timer(0.30).timeout
		if id == "gold":
			var amount: int = game.shown_event["gold_reward"]
			expect(game.event_panel.get_children().filter(func(child): return child is RichTextLabel).size() == 2, "Gold dialog contains only its title and story, with no subtext")
			expect(game.event_panel.get_node("EventChoice0").tooltip_text.contains(str(amount)) and not game.event_panel.get_node("EventChoice0").tooltip_text.contains("10–25"), "Gold choice tooltip agrees with the visible reward")
		var story: RichTextLabel = game.event_panel.get_node("EventStory")
		expect(story.size.x <= 504 and story.get_line_count() <= 5, "Story stays within popup: " + id)
		var last_choice: Button = game.event_panel.get_child(game.event_panel.get_child_count() - 1)
		expect(is_equal_approx(game.event_panel.size.y - last_choice.position.y - last_choice.size.y, 20.0), "All events have equal bottom padding: " + id)
		expect(is_equal_approx(game.event_panel.offset_top + game.event_panel.size.y / 2.0, 0.0), "Flexible event panel remains centered")
		for index in range(game.event_panel.get_child_count()):
			if not game.event_panel.get_child(index) is Button: continue
			expect(not game.event_panel.get_child(index).tooltip_text.is_empty(), "Every choice discloses its outcome")
		game.rules.pending_events.clear()
		game.shown_event = {}
		game.close_event_ui()
	# Exercise the actual player animation/cancellation path with a queued event.
	game.rules = fixture()
	game.active_hex = Vector2i(0, 0)
	game.selected = Vector2i(1, 0)
	game.game_over = false
	game.rules.set_effect(0, "trailblaze", true)
	game.rules.rng.seed = 77
	game.rules.cells[Vector2i(3, 0)]["event"] = "lumberjack"
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var encounter_rng: int = game.rules.rng.state
	game.click_hex(Vector2i(3, 0))
	var first_replacement: Dictionary = game.rules.pending_events[0].duplicate(true)
	var replacement_rng: int = game.rules.rng.state
	game.cancel_action()
	expect(game.rules.rng.state == encounter_rng and game.cells[Vector2i(3, 0)]["event"] == "lumberjack", "Cancelling an arrival restores the weighted draw and original marker")
	await process_frame
	game.selected = Vector2i(1, 0)
	game.refresh_ui()
	game.click_hex(Vector2i(3, 0))
	expect(game.rules.pending_events[0] == first_replacement and game.rules.rng.state == replacement_rng, "Repeating a cancelled arrival reveals the same replacement without rerolling")
	game.cancel_action()
	await process_frame
	game.selected = Vector2i(1, 0)
	game.rules.cells[Vector2i(3, 0)]["event"] = "wizard"
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.click_hex(Vector2i(3, 0))
	expect(game.busy and game.rules.pending_events.size() == 1 and not game.event_shade.visible, "Encounter waits for animation")
	game.cancel_action()
	expect(game.rules.pending_events.is_empty() and game.rules.has_effect(0, "trailblaze") and game.cells[Vector2i(3, 0)]["event"] == "wizard", "Cancellation restores event and blessing")
	await process_frame
	game.selected = Vector2i(1, 0)
	game.refresh_ui()
	game.click_hex(Vector2i(3, 0))
	while game.busy:
		await process_frame
	expect(game.event_shade.visible and game.selected == Vector2i(3, 0), "Arrival opens popup and selects unit with bonus action")
	game.resolve_shown_event(0)
	expect(game.rules.has_effect(0, "free_spell") and not game.cells[Vector2i(3, 0)]["moved"], "Wizard gift preserves bonus move")
	# AI takes a lethal encounter; playback must handle an empty destination.
	game.rules = fixture()
	game.rules.cells[Vector2i(1, 0)]["unit"] = 0
	game.rules.cells[Vector2i(1, 1)]["unit"] = 2
	game.rules.cells[Vector2i(2, 0)]["owner"] = -1
	game.rules.cells[Vector2i(2, 0)]["event"] = "pit"
	game.rules.rebuild_kingdoms()
	game.view.render_cells(game.cells)
	var action: Dictionary = game.rules.perform_move(Vector2i(1, 1), Vector2i(2, 0))
	expect(not action.is_empty() and action["after_target"]["unit"] == 0 and game.rules.pending_events.is_empty(), "AI resolves pit without player popup")
	await game.view.animate_moves([action], game.cells)
	expect(game.view.cells[Vector2i(2, 0)]["grave"] and not game.view.unit_actors.has(Vector2i(2, 0)), "Lethal AI encounter finishes playback with grave")
	game.queue_free()
	await process_frame
