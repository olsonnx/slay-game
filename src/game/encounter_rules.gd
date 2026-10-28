extends RefCounted
## Conditional encounters and durable faction effects. No UI or retained model.
const Loc = preload("res://src/localization/text.gd")
const Events = preload("res://src/game/event_catalog.gd")
const Authored = preload("res://src/game/authored_event_runtime.gd")
const Sites = preload("res://src/game/event_sites.gd")
const NEW_EVENTS := ["comet", "innkeeper", "lumberjack", "regroup", "cartographer", "ransom", "economist", "revolt", "stainless_steel", "builders_guild", "barracks", "scout_lodge", "watchtower"]

static func primary_treasury(state, faction: int, preferred: Dictionary = {}) -> Dictionary:
	var home: Vector2i = state.effects_by_faction.get(faction, {}).get("income_home", state.NONE)
	if state.kingdoms.has(home) and state.kingdoms[home]["owner"] == faction: return state.kingdoms[home]
	if not state.effects_by_faction.get(faction, {}).has("income_home") and not preferred.is_empty(): return preferred
	var capitals: Array = []
	for capital in state.kingdoms:
		if state.kingdoms[capital]["owner"] == faction: capitals.append(capital)
	capitals.sort_custom(func(a: Vector2i, b: Vector2i): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return {} if capitals.is_empty() else state.kingdoms[capitals[0]]

static func income_adjustment(state, kingdom: Dictionary) -> int:
	var faction: int = kingdom["owner"]
	var bonus: int = state.effects_by_faction.get(faction, {}).get("income_bonus", 0)
	var total := bonus if bonus != 0 and primary_treasury(state, faction).get("capital") == kingdom["capital"] else 0
	for coord in kingdom["hexes"]:
		if Sites.protected(state.cells[coord]): total += int(state.cells[coord].get("site_income",0))
	return total

static func change_income(state, faction: int, kingdom: Dictionary, amount: int, source := "") -> void:
	if not state.effects_by_faction.has(faction): state.effects_by_faction[faction] = {}
	var effects: Dictionary = state.effects_by_faction[faction]
	if not effects.has("income_home"): effects["income_home"] = kingdom["capital"]
	effects["income_bonus"] = int(effects.get("income_bonus", 0)) + amount
	add_source(effects,"income_sources",source,amount)

static func add_source(effects: Dictionary, key: String, source: String, amount := 1) -> void:
	if source == "": return
	var amounts_key := key.trim_suffix("_sources")+"_source_amounts"
	if not effects.has(amounts_key):
		effects[amounts_key] = {}
		# Older positions recorded counts only. Fixed lair rewards are recoverable.
		for previous in effects.get(key,{}):
			if key == "income_sources" and previous == "bear": effects[amounts_key][previous] = int(effects[key][previous])*5
			elif key == "mana_sources" and previous == "wolf": effects[amounts_key][previous] = int(effects[key][previous])
	if not effects.has(key): effects[key] = {}
	effects[key][source] = int(effects[key].get(source,0))+1
	effects[amounts_key][source] = int(effects[amounts_key].get(source,0))+amount

static func forest(state, kingdom: Dictionary) -> Dictionary:
	var result := {"trees": [], "blocked": 0, "potential": 0}
	if kingdom.is_empty(): return result
	for coord in kingdom["hexes"]:
		var cell: Dictionary = state.cells[coord]
		var value: int = cell["value"]
		result["potential"] += value + (state.CITY_INCOME if cell["building"] == "city" else 0)
		if cell["tree"]:
			result["trees"].append(coord)
			result["blocked"] += value
	return result

static func recruit_site(state, kingdom: Dictionary) -> Vector2i:
	if kingdom.is_empty(): return state.NONE
	for coord in kingdom["hexes"]:
		var cell: Dictionary = state.cells[coord]
		if cell["unit"] == 0 and preload("res://src/game/logistics.gd").recruitment_zone(state, coord, kingdom.owner) and not cell["tree"] and not cell["grave"] and not state.is_barrier(coord): return coord
	return state.NONE

static func rebel_faction(state) -> int:
	for faction in range(mini(64, state.faction_names.size())):
		if faction not in state.human_factions and state.territory(faction) == 0 and not state.has_units(faction): return faction
	return -1

static func region(state, coord: Vector2i) -> Array:
	var result: Array = []
	for site in [coord] + state.neighbors(coord):
		if not state.is_mountain(site) and not state.is_bridge(site): result.append(site)
	return result

static func main_outcome_available(state, id: String, coord: Vector2i, faction: int) -> bool:
	if not Events.EVENTS.has(id) or not state.cells.has(coord) or state.cells[coord]["unit"] <= 0 or state.unit_faction(coord) != faction: return false
	if Events.EVENTS[id].has("authored"):
		return Authored.available(state,Events.EVENTS[id].authored,{"coord":coord,"faction":faction})
	var kingdom: Dictionary = state.kingdom_at(coord)
	for requirement in Events.EVENTS[id].get("requires", []):
		match requirement:
			"kingdom":
				if kingdom.is_empty(): return false
			"recruit_space":
				if recruit_site(state, kingdom) == state.NONE: return false
			"forest":
				if forest(state, kingdom)["trees"].is_empty(): return false
			"multiple_units", "knights":
				var count := 0
				for site in state.cells:
					if state.unit_faction(site) == faction and state.cells[site]["unit"] >= (3 if requirement == "knights" else 1): count += 1
				if count < (1 if requirement == "knights" else 2): return false
			"other_faction":
				var found := false
				for other in range(state.faction_count):
					if other != faction and (state.territory(other) > 0 or state.has_units(other)): found = true
				if not found: return false
			"income_trade":
				var treasury := kingdom
				if treasury.is_empty() or (state.income(treasury) < 1 and kingdom["gold"] < 10): return false
			"rebel_slot":
				if rebel_faction(state) < 0 or region(state, coord).size() < 2: return false
			"no_stainless_steel":
				if state.has_effect(faction, "stainless_steel"): return false
			_: return false
	match id:
		"gold", "goose":
			if kingdom.is_empty(): return false
		"wizard":
			if state.has_effect(faction, "free_spell"): return false
		"altar":
			if state.cells[coord]["mana_source"]: return false
		"duel":
			if state.cells[coord]["unit"] >= 3 and kingdom.is_empty(): return false
	return true

static func forest_reward(trees: Dictionary) -> int:
	return 0 if trees["blocked"] * 2 > trees["potential"] else trees["trees"].size()

static func weighted_event(state, coord: Vector2i = Vector2i.ZERO, faction: int = -1, weights = null, used: Dictionary = {}) -> String:
	if weights == null: weights = Events.WEIGHTS
	var pool: Dictionary = {}
	var total := 0
	for entry in weights:
		var weight := maxi(0, int(weights[entry]))
		if weight == 0 or not Events.EVENTS.has(entry): continue
		var id: String = String(entry)
		if faction >= 0 and not main_outcome_available(state, id, coord, faction): continue
		pool[id] = int(pool.get(id, 0)) + weight
		total += weight
	# Prefer unused types without losing weighting or making exhausted pools empty.
	var unused: Dictionary = {}
	var unused_total := 0
	for id in pool:
		if not used.has(id):
			unused[id] = pool[id]
			unused_total += int(pool[id])
	if not unused.is_empty():
		pool = unused
		total = unused_total
	if total == 0: return ""
	var ticket: int = state.rng.randi_range(1, total)
	for id in pool:
		ticket -= int(pool[id])
		if ticket <= 0: return id
	return ""

static func prepare_event(state, id: String, coord: Vector2i, faction: int) -> Dictionary:
	id = Events.canonical_id(id)
	if not Events.EVENTS.has(id) or not state.cells.has(coord) or state.cells[coord]["unit"] <= 0 or state.unit_faction(coord) != faction: return {}
	# Choose once, before revealing any text. Ineligible encounters never become
	# no-op stories, and an already revealed choice never rerolls the encounter.
	if not main_outcome_available(state, id, coord, faction):
		var used: Dictionary = {}
		for site in state.cells:
			var cell: Dictionary = state.cells[site]
			for key in ["event", "event_seen"]:
				var previous: String = Events.canonical_id(String(cell.get(key, "")))
				if previous != "": used[previous] = true
		for pending in state.pending_events: used[pending.id] = true
		id = weighted_event(state, coord, faction, null, used)
	if id.is_empty(): return {}
	var event := {"id": id, "coord": coord, "faction": faction}
	if Events.EVENTS[id].has("authored"): Authored.prepare(state,Events.EVENTS[id].authored,event)
	return event

static func choice_allowed(state, event: Dictionary, choice: int) -> bool:
	var coord: Vector2i = event["coord"]
	var faction: int = event["faction"]
	var kingdom: Dictionary = state.kingdom_at(coord)
	match event["id"]:
		"comet": return choice == 0 or recruit_site(state, kingdom) != state.NONE
		"ransom": return choice == 0 or state.get_mana(faction) < state.mana_capacity(faction)
		"economist":
			if kingdom.is_empty(): return false
			var treasury := kingdom
			return not treasury.is_empty() and state.income(treasury) > 0 if choice == 0 else kingdom["gold"] >= 10
		"revolt": return choice == 1 or rebel_faction(state) >= 0
	return true

static func definition(state, event: Dictionary, base: Dictionary) -> Dictionary:
	var id: String = event["id"]
	if id not in NEW_EVENTS: return base
	var kingdom: Dictionary = state.kingdom_at(event["coord"])
	if id == "lumberjack":
		var trees := forest(state, kingdom)
		if trees["blocked"] * 2 > trees["potential"]:
			base["text"] = base["overgrown_text"]
			base["choices"] = base["overgrown_choices"].duplicate(true)
		var reward := forest_reward(trees)
		base["choices"][0][1] = Loc.text("Clear %d trees.") % trees["trees"].size() + "\n" + (Loc.text("Gain %d gold.") % reward if reward > 0 else Loc.text("No gold reward."))
	if id == "comet":
		base["choices"][1][1] = Loc.text("Gain a ready Scout.\nUpkeep: %d gold per turn.") % state.unit_upkeep(1, event["faction"])
	if id == "revolt" and not kingdom.is_empty():
		base["choices"][1][1] = Loc.text("Pay %d gold (your entire treasury).") % kingdom["gold"]
	base["disabled"] = []
	for index in range(base["choices"].size()): base["disabled"].append(not choice_allowed(state, event, index))
	return base

static func disband(state, coord: Vector2i) -> void:
	var cell: Dictionary = state.cells[coord]
	cell["unit"] = 0
	cell["unit_owner"] = -1
	cell["unit_home"] = state.NONE
	cell["moved"] = false
	cell.erase("entrenched_by")

static func resolve(state, event: Dictionary, choice: int) -> String:
	var id: String = event["id"]
	var coord: Vector2i = event["coord"]
	var faction: int = event["faction"]
	var kingdom: Dictionary = state.kingdom_at(coord)
	match id:
		"comet":
			if choice == 0:
				var gain: int = state.rng.randi_range(1, 2)
				Sites.create(state,coord,"comet",gain)
				return Loc.text("A landmark is built: +%d gold per turn to its kingdom while controlled.") % gain
			var site := recruit_site(state, kingdom)
			state.cells[site]["unit"] = 1
			state.cells[site]["moved"] = false
			return Loc.text("A free Scout joins your kingdom. Normal upkeep applies.")
		"innkeeper":
			if state.rng.randf() < 0.5:
				state.kill_unit(coord)
				return Loc.text("The drink lives up to its name. Your army does not.")
			if not kingdom.is_empty(): kingdom["gold"] += 4
			return Loc.text("Your army survives the drink and wins 4 gold on a wager.")
		"lumberjack":
			var trees := forest(state, kingdom)
			for site in trees["trees"]: state.cells[site]["tree"] = false
			var reward: int = forest_reward(trees)
			kingdom["gold"] += reward
			return Loc.text("%d trees removed; %d gold earned. The forester requests a promotion.") % [trees["trees"].size(), reward]
		"regroup":
			if choice == 1: return Loc.text("The army remains reassuringly imbalanced.")
			var total := 0
			for site in state.cells:
				if state.cells[site]["unit"] <= 0 or state.unit_faction(site) != faction: continue
				var home: Dictionary = state.unit_kingdom(site)
				if home.is_empty(): home = kingdom
				var refund: int = state.Catalog.unit_price(state.cells[site]["unit"])
				home["gold"] += refund
				total += refund
				disband(state, site)
			return Loc.text("Your armies stand down. %d gold is returned to their treasuries.") % total
		"cartographer":
			for site in region(state, coord):
				var cell: Dictionary = state.cells[site]
				if cell["owner"] != faction: continue
				disband(state, site)
				cell["owner"] = -1
				cell["capital"] = -1
				if not Sites.protected(cell): cell["building"] = ""
				cell["fortified"] = false
				cell["fortified_by"] = -1
				cell["barrier_by"] = -1
			state.rebuild_kingdoms()
			return Loc.text("The border is corrected. Several provinces were apparently a clerical error.")
		"ransom":
			if choice == 0:
				kingdom["gold"] += 20
				return Loc.text("The family pays 20 gold. No receipt is requested.")
			state.set_mana(faction, state.get_mana(faction) + 1)
			return Loc.text("A grim demonstration of power: +1 mana.")
		"economist":
			kingdom["gold"] += 10 if choice == 0 else -10
			Sites.create(state,coord,"economist",-1 if choice == 0 else 1)
			return Loc.text("Gain 10 gold here; build a landmark costing its kingdom 1 gold per turn while controlled.") if choice == 0 else Loc.text("Pay 10 gold here; build a landmark granting its kingdom 1 gold per turn while controlled.")
		"revolt":
			if choice == 1:
				kingdom["gold"] = 0
				return Loc.text("The treasury is empty. The peasants have discovered fiscal policy.")
			var rebels := rebel_faction(state)
			state.faction_count = maxi(state.faction_count, rebels + 1)
			for site in region(state, coord):
				var cell: Dictionary = state.cells[site]
				cell["owner"] = rebels
				cell["capital"] = -1
				cell["unit_owner"] = rebels if cell["unit"] > 0 else -1
				cell["unit_home"] = state.NONE
				cell["moved"] = true
				cell["fortified"] = false
				cell["fortified_by"] = -1
				cell["barrier_by"] = -1
				cell.erase("entrenched_by")
			state.cells[coord]["capital"] = rebels
			state.rebuild_kingdoms()
			state.set_mana(rebels, 0)
			return Loc.text("The %s kingdom declares independence. Its constitution is mostly pitchforks.") % state.faction_names[rebels]
		"stainless_steel":
			Sites.create(state,coord,"stainless_steel",0,0,true)
			return Loc.text("A landmark is built: its owner's Knight wages are 25% lower.")
		"builders_guild", "barracks", "scout_lodge", "watchtower":
			var bonus: String = {"builders_guild":"development_discount", "barracks":"soldier_discount", "scout_lodge":"scout_discount", "watchtower":"defense_aura"}[id]
			Sites.create(state, coord, id, 0, 0, false, {bonus:true})
			return Loc.text(Events.EVENTS[id].choices[0][1])
	return Loc.text("The journey continues.")
