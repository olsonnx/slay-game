extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Spell validation, effects and encounters operate on the supplied authoritative state.
## No retained model reference: the rules can own this helper without a reference cycle.
const Spells = preload("res://src/game/spell_catalog.gd")
const Encounters = preload("res://src/game/encounter_rules.gd")
const Events = preload("res://src/game/event_catalog.gd")
const EVENT_TILES_PER_ENCOUNTER := 16.0
const NONE = preload("res://src/game/hex_grid.gd").NONE

func generate_events(state) -> void:
	if state.is_modern():
		var sites: Array = []
		for coord in state.cells:
			if state.cells[coord]["owner"] == -1 and not state.is_mountain(coord) and not state.is_bridge(coord) and not state.cells[coord]["mana_source"]:
				sites.append(coord)
		# Keep small-map encounter counts, then scale with explorable land rather
		# than the number of factions. Mountains, homes and sources do not count.
		var target: int = maxi(state.faction_count + 1, roundi(sites.size() / EVENT_TILES_PER_ENCOUNTER))
		var placed: Array = []
		for coord in state.shuffled(sites):
			var nearby := false
			for other in placed:
				if state.distance(coord, other) < 3:
					nearby = true
			if nearby:
				continue
			state.cells[coord]["event"] = Encounters.weighted_event(state)
			placed.append(coord)
			if placed.size() >= target:
				break

func has_effect(state, faction: int, effect: String) -> bool:
	return state.effects_by_faction.get(faction, {}).get(effect, false)

func set_effect(state, faction: int, effect: String, enabled: bool) -> void:
	if not state.effects_by_faction.has(faction):
		state.effects_by_faction[faction] = {}
	if enabled:
		state.effects_by_faction[faction][effect] = true
	else:
		state.effects_by_faction[faction].erase(effect)

func spell_cost(state, spell: String, faction: int) -> int:
	return 0 if state.has_effect(faction, "free_spell") else int(Spells.SPELLS[spell]["cost"])

func event_definition(state, event: Dictionary) -> Dictionary:
	if not state.pending_events.has(event) or not Events.EVENTS.has(event.get("id", "")):
		return {}
	var definition: Dictionary = Events.EVENTS[event["id"]].duplicate(true)
	if event["id"] == "gold":
		if not event.has("gold_reward"):
			event["gold_reward"] = state.rng.randi_range(10, 25)
		definition["gold_reward"] = event["gold_reward"]
		definition["choices"][0][1] = Loc.text("Gain %d gold.") % event["gold_reward"]
	if event["id"] == "duel":
		var victory := Loc.text("60%: gain 20 gold.") if state.cells[event["coord"]]["unit"] >= 3 else Loc.text("60%: gain 1 tier.")
		definition["choices"][0][1] = victory + "\n" + Loc.text("40%: this army dies.")
	return Encounters.definition(state, event, definition)

func trigger_event(state, coord: Vector2i, faction: int) -> bool:
	var id: String = state.cells[coord].get("event", "")
	var encounter: Dictionary = Encounters.prepare_event(state, id, coord, faction)
	if encounter.is_empty(): return false
	state.cells[coord]["event"] = ""
	state.pending_events.append(encounter)
	if faction not in state.human_factions:
		var choice: int = state.KingdomAI.Analysis.event_choice(state, encounter)
		var definition: Dictionary = event_definition(state, encounter)
		var disabled: Array = definition.get("disabled", [])
		if choice < 0 or choice >= definition["choices"].size() or (choice < disabled.size() and disabled[choice]):
			for index in range(definition["choices"].size()):
				if index >= disabled.size() or not disabled[index]:
					choice = index
					break
		state.resolve_event(encounter, choice)
	return true

func resolve_event(state, event: Dictionary, choice: int) -> String:
	if not state.pending_events.has(event) or not Events.EVENTS.has(event.get("id", "")):
		return ""
	var definition: Dictionary = Events.EVENTS[event["id"]]
	if choice < 0 or choice >= definition["choices"].size():
		return ""
	if not Encounters.main_outcome_available(state, event["id"], event["coord"], event["faction"]): return ""
	if event["id"] in Encounters.NEW_EVENTS:
		if not Encounters.choice_allowed(state, event, choice): return ""
		state.pending_events.erase(event)
		var outcome := Encounters.resolve(state, event, choice)
		state.clamp_mana()
		return outcome
	state.pending_events.erase(event)
	var coord: Vector2i = event["coord"]
	var faction: int = event["faction"]
	var kingdom: Dictionary = state.kingdom_at(coord)
	var reward := 0
	var result := Loc.text("The journey continues.")
	match event["id"]:
		"goose": reward = 2
		"gold": reward = int(event["gold_reward"]) if event.has("gold_reward") else state.rng.randi_range(10, 25)
		"wizard":
			state.set_effect(faction, "free_spell", true)
			result = Loc.text("Your next spell is free.")
		"pit":
			state.kill_unit(coord)
			result = Loc.text("Your army was lost in the pit.")
		"altar", "duel":
			if choice == 0:
				if state.rng.randf() < 0.60:
					if event["id"] == "altar":
						state.cells[coord]["mana_source"] = true
						result = Loc.text("The altar awakens: a new mana source.")
					elif state.cells[coord]["unit"] < 3:
						state.cells[coord]["unit"] += 1
						result = Loc.text("Your champion wins and gains a tier.")
					else: reward = 20
				else:
					state.kill_unit(coord)
					result = Loc.text("Your army was lost.")
	if reward > 0 and not kingdom.is_empty():
		kingdom["gold"] += reward
		result = Loc.text("Your kingdom gains %d gold.") % reward
	state.clamp_mana()
	return result

func casting_kingdom(state, spell: String, coord: Vector2i, faction: int, capital := NONE) -> Dictionary:
	if not state.cells.has(coord):
		return {}
	if state.cells[coord]["owner"] == faction:
		return state.kingdom_at(coord)
	if spell != "shatter" or state.cells[coord]["owner"] >= 0:
		return {}
	return state.construction_kingdom(coord, faction, capital)

func can_cast(state, spell: String, coord: Vector2i, faction: int, capital := NONE, available_mana := -1) -> bool:
	if not state.is_modern() or not Spells.SPELLS.has(spell) or not state.cells.has(coord) or state.is_mountain(coord) or state.is_barrier(coord):
		return false
	var cell: Dictionary = state.cells[coord]
	match Spells.SPELLS[spell]["target"]:
		"friendly_land":
			if cell["owner"] != faction or state.has_effect(faction, "trailblaze"):
				return false
		"empty_friendly_land":
			if state.has_wildlife(coord) or cell["owner"] != faction or cell["unit"] > 0 or cell["building"] != "" or state.kingdom_at(coord).is_empty():
				return false
		"neutral_structure":
			if cell["owner"] != -1 or cell["building"] == "":
				return false
	if available_mana < 0:
		available_mana = state.get_mana(faction)
	if available_mana < state.spell_cost(spell, faction):
		return false
	var kingdom: Dictionary = casting_kingdom(state, spell, coord, faction, capital)
	if spell == "trailblaze":
		return not kingdom.is_empty() and (capital == NONE or kingdom["capital"] == capital)
	match Spells.SPELLS[spell]["target"]:
		"empty_friendly_land": return true
		"neutral_structure": return not kingdom.is_empty()
	return false

func cast_spell(state, spell: String, coord: Vector2i, faction: int, capital := NONE) -> bool:
	if not state.can_cast(spell, coord, faction, capital):
		return false
	var kingdom: Dictionary = casting_kingdom(state, spell, coord, faction, capital)
	state.set_mana(faction, state.get_mana(faction) - state.spell_cost(spell, faction))
	state.set_effect(faction, "free_spell", false)
	match spell:
		"trailblaze": state.set_effect(faction, "trailblaze", true)
		"summon":
			state.cells[coord]["unit"] = 1
			state.cells[coord]["moved"] = false
			state.clear_terrain(coord, kingdom)
		"shatter":
			if state.cells[coord].get("fortified", false):
				state.cells[coord]["fortified"] = false
				state.cells[coord]["fortified_by"] = -1
			elif state.is_bridge(coord):
				state.cells.erase(coord)
				state.rebuild_kingdoms()
			else:
				state.cells[coord]["building"] = ""
	return true

func spell_targets(state, spell: String, faction: int, capital := NONE) -> Dictionary:
	var targets: Dictionary = {}
	if not state.is_modern() or not Spells.SPELLS.has(spell):
		return targets
	# Mana is read once for this query, never cached across mutable game commands.
	var available_mana: int = state.get_mana(faction)
	if available_mana < spell_cost(state, spell, faction):
		return targets
	for coord in state.cells:
		if can_cast(state, spell, coord, faction, capital, available_mana):
			targets[coord] = true
	return targets

