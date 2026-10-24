extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Encounters = preload("res://src/game/encounter_rules.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
const Replay = preload("res://src/game/replay_log.gd")
const C := Vector2i(5, 0)
var passed := 0
var failed := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	if value: passed += 1
	else:
		failed += 1
		push_error(message)

func fixture():
	var r = Rules.new()
	r.rule_mode = "modern"
	r.faction_count = 2
	r.human_factions = [0]
	for q in range(6):
		r.cells[Vector2i(q, 0)] = r.make_cell(0)
		r.cells[Vector2i(q, 0)]["value"] = 2
	for q in range(9, 12): r.cells[Vector2i(q, 0)] = r.make_cell(1)
	r.cells[Vector2i.ZERO]["capital"] = 0
	r.cells[Vector2i.ZERO]["mana_source"] = true
	r.cells[Vector2i(9, 0)]["capital"] = 1
	r.cells[C]["unit"] = 1
	r.cells[Vector2i(10, 0)]["unit"] = 1
	r.rebuild_kingdoms()
	for bank in r.kingdoms.values(): bank["gold"] = 30
	r.set_mana(0, 0)
	return r

func prepare(r, id: String) -> void:
	match id:
		"lumberjack": r.cells[Vector2i(1, 0)]["tree"] = true
		"lumberjack_overgrown":
			for q in range(1, 5): r.cells[Vector2i(q, 0)]["tree"] = true
		"regroup": r.cells[Vector2i(4, 0)]["unit"] = 2
		"economist", "stainless_steel": r.cells[C]["unit"] = 3

func queue(r, id: String) -> Dictionary:
	var event := {"id": id, "coord": C, "faction": 0}
	r.pending_events.append(event)
	return event

func choose(r, id: String, choice: int) -> Dictionary:
	expect(Encounters.main_outcome_available(r, id, C, 0), "Eligible fixture: " + id)
	var event := queue(r, id)
	expect(r.resolve_event(event, choice) != "", "Choice resolves: %s/%d" % [id, choice])
	return event

func income_total(r, faction: int) -> int:
	var total := 0
	for bank in r.kingdoms.values():
		if bank["owner"] == faction: total += r.income(bank)
	return total

func weighted_checks() -> void:
	var r = fixture()
	var counts := {}
	r.rng.seed = 8624
	for id in Rules.Events.EVENTS:
		expect(Rules.Events.WEIGHTS.has(id), "Every catalog event has an explicit weight: " + id)
	for draw in range(13000):
		var id := Encounters.weighted_event(r, C, 0, {"gold": 12, "pit": 1, "goose": 0})
		counts[id] = int(counts.get(id, 0)) + 1
	expect(counts.size() == 2 and counts.get("gold", 0) > counts.get("pit", 0) * 10 and counts.get("gold", 0) < counts.get("pit", 0) * 14, "Relative weights yield the expected 12:1 frequency and exclude zero weights")
	var rng_before: int = r.rng.state
	expect(Encounters.weighted_event(r, C, 0, {"gold": 0, "pit": -1}) == "" and r.rng.state == rng_before, "Empty weighted pools do not roll or change RNG")
	# Replacement draws exclude unavailable events and always offer a consequence.
	for seed_value in range(64):
		for marker in ["lumberjack", "regroup", "stainless_steel", "wizard", "altar"]:
			r = fixture()
			r.rng.seed = seed_value
			if marker == "wizard": r.set_effect(0, "free_spell", true)
			if marker == "altar": r.cells[C]["mana_source"] = true
			var saved := Snapshots.capture(r)
			var event := Encounters.prepare_event(r, marker, C, 0)
			var rolled_rng: int = r.rng.state
			Snapshots.restore(r, saved)
			expect(Encounters.prepare_event(r, marker, C, 0) == event and r.rng.state == rolled_rng, "Snapshot reproduces weighted replacement and RNG: " + marker)
			expect(event["id"] != marker and Encounters.main_outcome_available(r, event["id"], C, 0) and not event.has("fallback"), "Unmet requirements draw an eligible replacement: " + marker)
			r.pending_events.append(event)
			var definition: Dictionary = r.event_definition(event)
			var choice := 1 if definition.get("disabled", []).size() > 0 and definition["disabled"][0] else 0
			var before := [r.cells.duplicate(true), r.kingdoms.duplicate(true), r.effects_by_faction.duplicate(true), r.mana_by_faction.duplicate(true)]
			expect(r.resolve_event(event, choice) != "", "Replacement resolves: " + marker)
			expect(before != [r.cells, r.kingdoms, r.effects_by_faction, r.mana_by_faction], "Replacement has a gameplay consequence: " + marker)
	expect(not Rules.Events.EVENTS.has("lumberjack_overgrown") and not Rules.Events.WEIGHTS.has("lumberjack_overgrown"), "Catalog and lottery expose only one lumberjack event")
	# Heavy forests use the paid variant's one weight, rather than two chances.
	r = fixture()
	prepare(r, "lumberjack_overgrown")
	expect(Encounters.weighted_event(r, C, 0, {"lumberjack": 8}) == "lumberjack", "Heavy forests use the single lumberjack lottery entry")
	r = fixture()
	var event := queue(r, "goose")
	r.resolve_event(event, 0)
	expect(r.kingdom_at(C)["gold"] == 32, "The goose now awards a small tangible tax reward")

func run() -> void:
	weighted_checks()
	for id in Encounters.NEW_EVENTS:
		for choice in range(Rules.Events.EVENTS[id]["choices"].size()):
			var r = fixture()
			prepare(r, id)
			var event := queue(r, id)
			var definition: Dictionary = r.event_definition(event)
			expect(not definition.has("hint") and definition["disabled"].size() == definition["choices"].size(), "Choice availability is disclosed without requirements subtext: " + id)
			var before := Snapshots.capture(r)
			expect(r.resolve_event(event, 99) == "" and Snapshots.capture(r) == before, "Invalid choices leave state and RNG intact: " + id)
			expect(r.resolve_event(event, choice) != "" and r.pending_events.is_empty(), "Every new choice resolves: %s/%d" % [id, choice])
			expect(r.resolve_event(event, choice) == "", "Events cannot resolve twice: " + id)
	var gated = fixture()
	for id in ["lumberjack", "regroup", "stainless_steel"]:
		expect(not Encounters.main_outcome_available(gated, id, C, 0), "Unmet requirement selects alternate: " + id)
	for cell in gated.cells.values():
		if cell["owner"] == 0: cell["unit"] = 1
	expect(Encounters.main_outcome_available(gated, "comet", C, 0), "A full kingdom still receives the comet's income option")
	var full_comet := Encounters.prepare_event(gated, "comet", C, 0)
	gated.pending_events.append(full_comet)
	expect(gated.event_definition(full_comet)["disabled"] == [false, true], "Only comet recruitment is disabled when every province is occupied")
	var full_income := income_total(gated, 0)
	expect(gated.resolve_event(full_comet, 0) != "" and income_total(gated, 0) > full_income, "Comet still awards income without recruitment space")
	gated = fixture()
	gated.faction_names = ["Fern", "Ember"]
	expect(not Encounters.main_outcome_available(gated, "revolt", C, 0), "Revolt main outcome requires an unused nonhuman kingdom identity")
	for cell in gated.cells.values():
		if cell["owner"] == 1: cell["owner"] = -1; cell["unit"] = 0; cell["capital"] = -1
	gated.rebuild_kingdoms()
	expect(not Encounters.main_outcome_available(gated, "ransom", C, 0), "Ransom needs another living faction")
	# Comet random income is exact and bounded; an alternative really recruits.
	var gains := {}
	for seed_value in range(24):
		var r = fixture()
		r.rng.seed = seed_value
		var before := income_total(r, 0)
		choose(r, "comet", 0)
		var gain := income_total(r, 0) - before
		gains[gain] = true
		expect(gain in [1, 2], "Comet grants only the advertised income")
	expect(gains.size() == 2, "Both comet income rolls are exercised")
	var r = fixture()
	var before_wages: int = r.upkeep(r.kingdom_at(C))
	choose(r, "comet", 1)
	expect(r.upkeep(r.kingdom_at(C)) == before_wages + r.unit_upkeep(1, 0), "Free Scout still pays ordinary upkeep")
	var scouts := 0
	for cell in r.cells.values():
		if cell["owner"] == 0 and cell["unit"] == 1: scouts += 1
	expect(scouts == 2, "Comet recruits an additional Scout")
	# Both drinks have the same disclosed risk, not deterministic flavour choices.
	for choice in [0, 1]:
		var deaths := 0
		var survivors := 0
		for seed_value in range(40):
			r = fixture()
			r.rng.seed = seed_value
			choose(r, "innkeeper", choice)
			if r.cells[C]["unit"] == 0:
				deaths += 1
				expect(r.cells[C]["grave"] and r.kingdom_at(C)["gold"] == 30, "Bad drink kills without paying")
			else:
				survivors += 1
				expect(r.kingdom_at(C)["gold"] == 34, "Good drink pays exactly 4 gold")
		expect(deaths > 0 and survivors > 0, "Both outcomes occur for each drink")
	# Income weighting, exact-half boundary and connected-kingdom scope.
	r = fixture()
	for q in [1, 2, 3]: r.cells[Vector2i(q, 0)]["tree"] = true
	expect(Encounters.main_outcome_available(r, "lumberjack", C, 0) and Encounters.forest_reward(Encounters.forest(r, r.kingdom_at(C))) == 3, "Exactly half uses paid lumberjack")
	for q in [-6, -5]: r.cells[Vector2i(q, 0)] = r.make_cell(0)
	r.rebuild_kingdoms()
	r.cells[Vector2i(-5, 0)]["tree"] = true
	choose(r, "lumberjack", 0)
	expect(r.kingdom_at(C)["gold"] == 33 and r.cells[Vector2i(-5, 0)]["tree"], "Paid lumberjack clears only the local kingdom and pays per tree")
	r = fixture()
	for q in [1, 2]:
		r.cells[Vector2i(q, 0)]["tree"] = true
		r.cells[Vector2i(q, 0)]["value"] = 6
	expect(Encounters.main_outcome_available(r, "lumberjack", C, 0) and Encounters.forest_reward(Encounters.forest(r, r.kingdom_at(C))) == 0, "Two valuable trees can block over half the income")
	var heavy_event := queue(r, "lumberjack")
	var heavy_definition: Dictionary = r.event_definition(heavy_event)
	expect(heavy_definition["text"].contains("mostly forest") and heavy_definition["title"] == "Lumberjack's Offer" and heavy_definition["choices"][0][1] == "Clear 2 trees.\nNo gold reward.", "One lumberjack event shows the heavy-forest story and exact reward")
	r.resolve_event(heavy_event, 0)
	expect(r.kingdom_at(C)["gold"] == 30 and not r.cells[Vector2i(1, 0)]["tree"], "Heavy forest clears without paying")
	# Regroup refunds separate home treasuries, including bridge garrisons.
	r = fixture()
	r.cells[Vector2i(4, 0)]["unit"] = 2
	for q in [-6, -5]: r.cells[Vector2i(q, 0)] = r.make_cell(0)
	r.cells[Vector2i(-6, 0)]["capital"] = 0
	r.cells[Vector2i(-5, 0)]["unit"] = 3
	r.rebuild_kingdoms()
	r.kingdom_at(Vector2i(-5, 0))["gold"] = 7
	var bridge := Vector2i(-1, 0)
	r.cells[bridge] = r.make_cell()
	r.cells[bridge].merge({"building":"bridge", "unit":1, "unit_owner":0, "unit_home":Vector2i.ZERO}, true)
	choose(r, "regroup", 0)
	expect(not r.has_units(0) and r.has_units(1), "Regroup only disbands the triggering faction")
	expect(r.kingdom_at(C)["gold"] == 70 and r.kingdom_at(Vector2i(-5, 0))["gold"] == 47, "Refunds go to the correct local treasuries")
	expect(not r.cells[C]["grave"], "Disbanding is not a death")
	r = fixture()
	prepare(r, "regroup")
	var preserved: Dictionary = r.cells.duplicate(true)
	choose(r, "regroup", 1)
	expect(r.cells == preserved, "Rejecting regroup preserves every army")
	# Area effects affect the specified region and rebuild ownership immediately.
	r = fixture()
	r.cells[Vector2i(5, 1)] = r.make_cell(1)
	choose(r, "cartographer", 0)
	expect(r.cells[C]["owner"] == -1 and r.cells[Vector2i(4, 0)]["owner"] == -1 and r.cells[Vector2i(3, 0)]["owner"] == 0 and r.cells[Vector2i(5, 1)]["owner"] == 1, "Cartographer neutralizes own event province and neighbours only")
	r = fixture()
	choose(r, "revolt", 0)
	var rebels: int = r.cells[C]["owner"]
	expect(rebels == 2 and r.faction_count == 3 and not r.kingdom_at(C).is_empty() and r.cells[C]["capital"] == rebels, "Revolt creates an independent AI kingdom at the event")
	expect(r.cells[Vector2i(4, 0)]["owner"] == rebels and r.cells[Vector2i(3, 0)]["owner"] == 0 and rebels not in r.human_factions, "Revolt captures the neighbouring region only")
	r = fixture()
	choose(r, "revolt", 1)
	expect(r.kingdom_at(C)["gold"] == 0 and r.cells[C]["owner"] == 0, "Revolt payment empties the local treasury and keeps land")
	# Payments and capacity are validated before consuming an encounter.
	r = fixture()
	choose(r, "ransom", 0)
	expect(r.kingdom_at(C)["gold"] == 50, "Ransom pays the advertised 20 gold")
	r = fixture()
	choose(r, "ransom", 1)
	expect(r.get_mana(0) == 1, "Execution awards exactly one mana")
	r.set_mana(0, r.mana_capacity(0))
	var event := queue(r, "ransom")
	var snapshot := Snapshots.capture(r)
	expect(r.event_definition(event)["disabled"][1] and r.resolve_event(event, 1) == "" and Snapshots.capture(r) == snapshot, "Full mana disables execution without wasting event")
	r = fixture()
	prepare(r, "economist")
	r.kingdom_at(C)["gold"] = 9
	event = queue(r, "economist")
	expect(r.event_definition(event)["title"] == "A crisis of confidence" and r.event_definition(event)["disabled"][1], "Economist has a stable title and shows affordability")
	snapshot = Snapshots.capture(r)
	expect(r.resolve_event(event, 1) == "" and Snapshots.capture(r) == snapshot, "Cannot buy income without 10 gold")
	var prior_income := income_total(r, 0)
	r.resolve_event(event, 0)
	expect(r.kingdom_at(C)["gold"] == 19 and income_total(r, 0) == prior_income - 1, "Selling future income gives exactly 10 gold for 1 income")
	r = fixture()
	prepare(r, "economist")
	prior_income = income_total(r, 0)
	choose(r, "economist", 1)
	expect(r.kingdom_at(C)["gold"] == 20 and income_total(r, 0) == prior_income + 1, "Investing gives exactly 1 income for 10 gold")
	# A solvent economy still gets the promised trade, rather than a no-op joke.
	r = fixture()
	var reform := Encounters.prepare_event(r, "economist", C, 0)
	r.pending_events.append(reform)
	expect(not reform.get("fallback", false), "Crisis of confidence offers actual choices without a deficit")
	prior_income = income_total(r, 0)
	r.resolve_event(reform, 0)
	expect(r.kingdom_at(C)["gold"] == 40 and income_total(r, 0) == prior_income - 1, "Solvent economist encounter applies its advertised trade")
	# Income may reach zero after previous reforms; disable selling, keep investing.
	r = fixture()
	Encounters.change_income(r, 0, r.kingdom_at(C), -income_total(r, 0))
	reform = Encounters.prepare_event(r, "economist", C, 0)
	r.pending_events.append(reform)
	expect(not reform.get("fallback", false) and r.event_definition(reform)["disabled"] == [true, false], "Zero income disables selling without hiding the investment")
	snapshot = Snapshots.capture(r)
	expect(r.resolve_event(reform, 0) == "" and Snapshots.capture(r) == snapshot, "Selling nonexistent income cannot award free gold")
	r.resolve_event(reform, 1)
	expect(income_total(r, 0) == 1 and r.kingdom_at(C)["gold"] == 20, "Investment restores income from zero")
	r = fixture()
	Encounters.change_income(r, 0, r.kingdom_at(C), -income_total(r, 0))
	r.human_factions = [1]
	r.cells[C]["event"] = "economist"
	expect(r.magic.trigger_event(r, C, 0) and r.pending_events.is_empty() and income_total(r, 0) == 1, "AI picks an available trade when its preferred choice is disabled")
	# Permanent effects remain through simulation, topology changes and snapshots.
	r = fixture()
	prepare(r, "stainless_steel")
	choose(r, "stainless_steel", 0)
	expect(r.unit_upkeep(3, 0) == 34 and r.unit_upkeep(3, 1) == 36 and not Encounters.main_outcome_available(r, "stainless_steel", C, 0), "Steel discount is faction-wide and cannot stack")
	expect(Snapshots.simulation(r).upkeep(r.kingdom_at(C)) == r.upkeep(r.kingdom_at(C)), "AI simulations use discounted wages")
	var visible = preload("res://src/game/visible_economy.gd").project(r, r.cells, r.kingdoms, r.mana_by_faction, 0, C)
	expect(visible.upkeep(visible.kingdom_at(C)) == r.upkeep(r.kingdom_at(C)), "Visible finances use discounted wages")
	Encounters.change_income(r, 0, r.kingdom_at(C), 2)
	for q in [-6, -5]: r.cells[Vector2i(q, 0)] = r.make_cell(0)
	r.rebuild_kingdoms()
	var adjustments := 0
	for bank in r.kingdoms.values():
		if bank["owner"] == 0: adjustments += Encounters.income_adjustment(r, bank)
	expect(adjustments == 2, "Disconnected kingdoms never duplicate a faction's permanent income")
	snapshot = Snapshots.capture(r)
	r.effects_by_faction.clear()
	Snapshots.restore(r, snapshot)
	expect(r.has_effect(0, "stainless_steel") and r.effects_by_faction[0]["income_bonus"] == 2, "Snapshot restores permanent event effects")
	r.cells[Vector2i.ZERO]["capital"] = -1
	r.cells[Vector2i.ZERO]["owner"] = 1
	r.rebuild_kingdoms()
	adjustments = 0
	for bank in r.kingdoms.values():
		if bank["owner"] == 0: adjustments += Encounters.income_adjustment(r, bank)
	expect(adjustments == 2, "Income survives capital loss without transferring to the captor")
	# Every marker resolves on entry, including unmet conditions. Revisits cannot farm it.
	for id in Encounters.NEW_EVENTS:
		r = fixture()
		var target := Vector2i(6, 0)
		r.cells[target] = r.make_cell()
		r.cells[target]["event"] = id
		r.perform_move(C, target)
		expect(r.pending_events.size() == 1 and r.cells[target]["event"] == "", "Every new event consumes its marker on entry: " + id)
		event = r.pending_events[0]
		expect(Encounters.main_outcome_available(r, event["id"], target, 0) and not event.has("fallback"), "Every entered marker reveals an eligible event: " + id)
		expect(r.resolve_event(event, 0) != "" and r.pending_events.is_empty(), "First visit finishes the encounter: " + id)
		if r.cells[target]["owner"] == 0 and r.cells[target]["unit"] > 0:
			r.cells[target]["moved"] = false
			r.move_unit(target, C)
			r.cells[C]["moved"] = false
			r.move_unit(C, target)
			expect(r.pending_events.is_empty() and r.cells[target]["event"] == "", "Revisiting never repeats an encounter: " + id)
	# Forest variants share one chance; a treeless kingdom draws a useful event.
	for marker in ["lumberjack", "lumberjack_overgrown"]:
		r = fixture()
		var prepared := Encounters.prepare_event(r, marker, C, 0)
		expect(prepared["id"] not in ["lumberjack", "lumberjack_overgrown"] and Encounters.main_outcome_available(r, prepared["id"], C, 0), "A treeless kingdom receives an eligible replacement")
		r.cells[Vector2i(1, 0)]["tree"] = true
		prepared = Encounters.prepare_event(r, marker, C, 0)
		expect(prepared["id"] == "lumberjack" and not prepared.get("fallback", false), "Either lumberjack marker selects the paid version for light forest")
		for q in [2, 3, 4]: r.cells[Vector2i(q, 0)]["tree"] = true
		prepared = Encounters.prepare_event(r, marker, C, 0)
		expect(prepared["id"] == "lumberjack" and Encounters.forest_reward(Encounters.forest(r, r.kingdom_at(C))) == 0 and not prepared.get("fallback", false), "Either lumberjack marker selects the unpaid version for heavy forest")
	# AI resolves replacement encounters without leaving a pending dialog.
	for id in ["regroup", "economist", "revolt", "stainless_steel", "lumberjack"]:
		r = fixture()
		r.human_factions = [1]
		if id == "revolt": r.faction_names = ["Fern", "Ember"]
		r.cells[C]["event"] = id
		expect(r.magic.trigger_event(r, C, 0) and r.pending_events.is_empty() and r.cells[C]["event"] == "", "AI resolves an eligible replacement without leaving pending events: " + id)
	# Replay persists both faction growth and durable modifiers.
	r = fixture()
	r.replay_log = Replay.new()
	r.replay_log.start(r)
	choose(r, "comet", 0)
	choose(r, "revolt", 0)
	var replay: Dictionary = Replay.read_records(r.replay_log.records)
	expect(replay["error"] == "" and replay["position"]["faction_count"] == 3 and replay["position"]["cells"][C].get("site_income",0) > 0, "Replay reconstructs new factions and permanent effects")
	await ui_and_playback_checks()
	print("New event checks: %d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)

func ui_and_playback_checks() -> void:
	root.size = Vector2i(960, 620)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	root.add_child(game)
	await process_frame
	for id in Encounters.NEW_EVENTS:
		game.rules = fixture()
		prepare(game.rules, id)
		game.configure_players()
		game.session.selection.selected = game.NONE
		game.view.render_cells(game.cells)
		game.rules.pending_events.append({"id":id, "coord":C, "faction":0})
		game.show_next_event()
		await create_timer(0.3).timeout
		expect(game.event_shade.visible and game.event_panel.size.y <= root.get_visible_rect().size.y - 24, "New dialog fits minimum window: " + id)
		for index in range(game.event_panel.get_child_count()):
			if not game.event_panel.get_child(index) is Button: continue
			expect(not game.event_panel.get_child(index).tooltip_text.is_empty(), "New choices disclose outcomes in UI: " + id)
		if "--preview" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://artifacts/new_event_%s.png" % id)
		game.resolve_shown_event(1 if id == "regroup" else 0)
		expect(not game.event_shade.visible, "New encounter closes after resolving: " + id)
		if id == "revolt":
			expect(2 in game.turn_order and game.rules.faction_count == 3, "New AI kingdom joins the real turn order")
		if id == "stainless_steel":
			game.open_shop("recruit")
			expect(game.hud.shop_items.get_child(2).tooltip_text.contains("34"), "Recruit card discloses discounted Knight upkeep")
			game.cancel_action()
	game.rules = fixture()
	game.configure_players()
	game.view.render_cells(game.cells)
	game.cells[C]["event"] = "lumberjack"
	game.rules.magic.trigger_event(game.rules, C, 0)
	game.show_next_event()
	await create_timer(0.3).timeout
	var replacement: Dictionary = game.rules.pending_events[0]
	expect(replacement["id"] not in ["lumberjack", "lumberjack_overgrown"] and not game.event_panel.get_node("EventStory").text.contains("treeless"), "Treeless forest marker shows the replacement event's own story")
	var replacement_definition: Dictionary = game.rules.event_definition(replacement)
	var replacement_choice := 0
	if replacement_definition.get("disabled", []).size() > 0 and replacement_definition["disabled"][0]: replacement_choice = 1
	game.resolve_shown_event(replacement_choice)
	expect(not game.event_shade.visible and game.cells[C]["event"] == "" and game.rules.pending_events.is_empty(), "Replacement encounter closes and consumes the marker")
	# Reuse the real dialog across event types without carrying forest text or effects.
	game.rules = fixture()
	game.configure_players()
	game.view.render_cells(game.cells)
	game.cells[Vector2i(1, 0)]["tree"] = true
	for id in ["comet", "lumberjack", "comet", "economist"]:
		game.cells[C]["event"] = id
		game.rules.magic.trigger_event(game.rules, C, 0)
		game.show_next_event()
		var expected_title: String = Rules.Events.EVENTS[id]["title"]
		expect(game.event_panel.get_node("EventTitle").text == expected_title, "Reused dialog shows the current event title: " + id)
		var income_before := income_total(game.rules, 0)
		var previous_site_income: int = game.cells[C].get("site_income",0)
		game.resolve_shown_event(0)
		if id == "comet":
			expect(income_total(game.rules, 0) == income_before-previous_site_income+int(game.cells[C].get("site_income",0)) and int(game.cells[C].get("site_income",0)) > 0, "Comet dialog applies income after switching event types")
			if game.cells[Vector2i(1, 0)]["tree"]:
				expect(game.rules.kingdom_at(C)["gold"] == 30, "Comet leaves forest and tree payments alone")
	# AI area effects must reach visible playback as well as the authoritative board.
	for id in ["lumberjack", "regroup", "cartographer", "revolt"]:
		game.rules = fixture()
		prepare(game.rules, id)
		game.rules.human_factions = [1]
		if id == "regroup":
			game.cells[C]["unit"] = 3
			game.rules.kingdom_at(C)["gold"] = 0
		var target := Vector2i(6, 0)
		game.cells[target] = game.rules.make_cell()
		game.cells[target]["event"] = id
		game.view.render_cells(game.cells)
		var action: Dictionary = game.rules.perform_move(C, target)
		expect(not action.is_empty() and game.rules.pending_events.is_empty(), "AI resolves new encounters without a player popup: " + id)
		await game.view.animate_moves([action], game.cells)
		expect(game.view.cells == game.cells, "AI event playback includes all changed provinces: " + id)
	# An originally harmless/ineligible marker may now redraw into an area effect.
	game.rules = fixture()
	game.rules.human_factions = [1]
	var replacement_neighbor := Vector2i(5, 1)
	game.cells[replacement_neighbor] = game.rules.make_cell(0)
	game.rules.rebuild_kingdoms()
	var replacement_seed := -1
	for seed_value in range(512):
		game.rules.rng.seed = seed_value
		if Encounters.prepare_event(game.rules, "lumberjack", C, 0)["id"] == "cartographer":
			replacement_seed = seed_value
			break
	expect(replacement_seed >= 0, "A deterministic seed exercises an area-effect replacement")
	game.rules.rng.seed = replacement_seed
	var replacement_target := Vector2i(6, 0)
	game.cells[replacement_target] = game.rules.make_cell()
	game.cells[replacement_target]["event"] = "lumberjack"
	game.view.render_cells(game.cells)
	var replacement_action: Dictionary = game.rules.perform_move(C, replacement_target)
	expect(game.cells[replacement_neighbor]["owner"] == -1 and replacement_action["annexed"].has(replacement_neighbor), "Redrawn cartographer records changes beyond its arrival tile")
	await game.view.animate_moves([replacement_action], game.cells)
	expect(game.view.cells == game.cells, "AI playback includes the redrawn event's complete area effect")
	# Random solo/multiplayer palettes leave distinct identities for rebels.
	game.rules = fixture()
	game.initial_match_config = {"slots":[{"name":"Iris", "color":11, "controller":"human", "difficulty":"normal"}, {"name":"Aster", "color":4, "controller":"ai", "difficulty":"normal"}], "order":"fixed"}
	game.configure_players()
	var palettes: Array = []
	for color in game.view.COLORS:
		if color not in palettes: palettes.append(color)
	expect(palettes.size() == game.rules.faction_names.size(), "Rebel identities keep distinct unused palettes after seat colors are shuffled")
	game.rules.pending_events.append({"id":"revolt", "coord":C, "faction":0})
	game.show_next_event()
	game.resolve_shown_event(0)
	game.session.begin_work()
	await preload("res://src/game/opponent_turns.gd").play_ai(game, 2)
	game.session.finish_work()
	expect(2 in game.turn_order and game.cells == game.view.cells, "A newly spawned AI kingdom completes a real turn beyond the original lobby seats")
	game.shutdown()
	game.queue_free()
	await process_frame
