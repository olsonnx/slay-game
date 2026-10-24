extends RefCounted
## Interprets validated event data; all random draws use the authoritative RNG.
const Loc = preload("res://src/localization/text.gd")
const Schema = preload("res://src/game/authored_event_schema.gd")
const Sites = preload("res://src/game/event_sites.gd")

static func conditions(state, event: Dictionary, requirements: Array) -> bool:
	var coord: Vector2i = event.coord
	var faction: int = event.faction
	var bank: Dictionary = state.kingdom_at(coord)
	var cell: Dictionary = state.cells[coord]
	for requirement in requirements:
		var met := false
		var value: int = requirement.get("value",1)
		match requirement.kind:
			"kingdom": met = not bank.is_empty()
			"recruit_space": met = state.magic.Encounters.recruit_site(state,bank) != state.NONE
			"forest": met = not state.magic.Encounters.forest(state,bank).trees.is_empty()
			"forest_overgrown":
				var forest: Dictionary = state.magic.Encounters.forest(state,bank)
				met = forest.blocked*2 > forest.potential
			"multiple_units", "knights":
				var count := 0
				for site in state.cells:
					if state.unit_faction(site) == faction and state.cells[site].unit >= (3 if requirement.kind == "knights" else 1): count += 1
				met = count >= (1 if requirement.kind == "knights" else 2)
			"other_faction":
				for other in range(state.faction_count):
					if other != faction and (state.territory(other) > 0 or state.has_units(other)): met = true
			"rebel_slot": met = state.magic.Encounters.rebel_faction(state) >= 0 and state.magic.Encounters.region(state,coord).size() >= 2
			"no_stainless_steel": met = not state.has_effect(faction,"stainless_steel")
			"duel_reward": met = cell.unit < 3 or not bank.is_empty()
			"income_trade": met = not bank.is_empty() and (state.income(bank) > 0 or bank.gold >= 10)
			"gold_at_least": met = not bank.is_empty() and bank.gold >= value
			"income_at_least": met = not bank.is_empty() and state.income(bank) >= value
			"mana_at_least": met = state.get_mana(faction) >= value
			"mana_space": met = state.get_mana(faction) < state.mana_capacity(faction)
			"unit_tier_at_least": met = cell.unit >= value
			"unit_tier_at_most": met = cell.unit <= value
			"has_effect": met = state.has_effect(faction,requirement.get("effect","free_spell"))
			"no_effect": met = not state.has_effect(faction,requirement.get("effect","free_spell"))
			"mana_source": met = cell.get("mana_source",false)
		if requirement.get("not",false): met = not met
		if not met: return false
	return true

static func story(data: Dictionary, event: Dictionary) -> Dictionary:
	var index: int = event.get("variant",-1)
	return data.variants[index] if index >= 0 and index < data.get("variants",[]).size() else data

static func prepare(state, data: Dictionary, event: Dictionary) -> void:
	event["variant"] = -1
	for i in range(data.get("variants",[]).size()):
		if conditions(state,event,data.variants[i].get("requires",[])):
			event.variant = i
			break
	if data.get("gold_roll_max",0) > 0: event["gold_reward"] = state.rng.randi_range(int(data.get("gold_roll_min",0)),int(data.gold_roll_max))

static func available(state, data: Dictionary, event: Dictionary) -> bool:
	if not data.get("enabled",true) or not conditions(state,event,data.get("requires",[])): return false
	var preview := event.duplicate()
	preview["variant"] = -1
	for i in range(data.get("variants",[]).size()):
		if conditions(state,preview,data.variants[i].get("requires",[])):
			preview.variant = i
			break
	for i in range(story(data,preview).choices.size()):
		if choice_allowed(state,data,preview,i): return true
	return false

static func effects_possible(state, event: Dictionary, effects: Array) -> bool:
	var bank: Dictionary = state.kingdom_at(event.coord)
	var cell: Dictionary = state.cells[event.coord]
	for effect in effects:
		if effect.kind == "promote" and cell.unit >= 3 and int(effect.get("max_rank_gold",20)) > 0 and bank.is_empty(): return false
		match effect.kind:
			"gold", "gold_percent", "clear_trees", "disband", "recruit":
				if bank.is_empty(): return false
			"building":
				if cell.building != "" or cell.capital >= 0: return false
			"revolt":
				if state.magic.Encounters.rebel_faction(state) < 0: return false
		if effect.kind == "recruit" and state.magic.Encounters.recruit_site(state,bank) == state.NONE: return false
	return true

static func choice_allowed(state, data: Dictionary, event: Dictionary, index: int) -> bool:
	var choices: Array = story(data,event).choices
	if index < 0 or index >= choices.size(): return false
	var choice: Dictionary = choices[index]
	if not conditions(state,event,choice.get("requires",[])): return false
	var bank: Dictionary = state.kingdom_at(event.coord)
	if choice.get("cost_gold",0) > 0 and (bank.is_empty() or bank.gold < choice.cost_gold): return false
	if state.get_mana(event.faction) < choice.get("cost_mana",0): return false
	var outcomes := 0
	for result in choice.outcomes:
		if not conditions(state,event,result.get("requires",[])): continue
		outcomes += 1
		# Validate ordered effects against a private position using worst-case rolls.
		# This handles forest clearance opening recruitment space and rewards funding
		# subsequent payments without touching authoritative records or RNG.
		var probe = preload("res://src/game/state_snapshot.gd").simulation(state)
		var home: Dictionary = probe.kingdom_at(event.coord)
		if not home.is_empty(): home.gold -= int(choice.get("cost_gold",0))
		probe.set_mana(event.faction,probe.get_mana(event.faction)-int(choice.get("cost_mana",0)))
		var attempt := event.duplicate()
		attempt["id"] = data.id
		if not attempt.has("gold_reward"): attempt["gold_reward"] = int(data.get("gold_roll_min",0))
		for effect in result.get("effects",[]):
			if not effects_possible(probe,attempt,[effect]): return false
			var minimum_effect: Dictionary = effect.duplicate(true)
			for prefix in ["","income_","mana_"]:
				if minimum_effect.has(prefix+"min"): minimum_effect[prefix+"max"] = minimum_effect[prefix+"min"]
			if effect.kind == "gold":
				var amount: int = attempt.gold_reward if effect.get("use_reveal_roll",false) else effect.get("min",1)
				if home.gold+amount < 0: return false
			if effect.kind == "mana" and probe.get_mana(event.faction)+int(effect.get("min",1)) < 0: return false
			apply(probe,attempt,home,minimum_effect,{"amount":0,"refund":0,"cleared":0})
	return outcomes > 0

static func format_text(state, event: Dictionary, value: String, extra: Dictionary = {}) -> String:
	value = Loc.text(value)
	var bank: Dictionary = state.kingdom_at(event.coord)
	var forest: Dictionary = state.magic.Encounters.forest(state,bank)
	var values := {"gold":event.get("gold_reward",0),"trees":forest.trees.size(),"tier":state.cells[event.coord].unit,
		"treasury":bank.get("gold",0),"knight_upkeep":state.unit_upkeep(3,event.faction),"scout_upkeep":state.unit_upkeep(1,event.faction)}
	values.merge(extra,true)
	for key in values: value = value.replace("{"+str(key)+"}",str(values[key]))
	return value

static func definition(state, data: Dictionary, event: Dictionary) -> Dictionary:
	var selected: Dictionary = story(data,event)
	var definition := data.duplicate(true)
	definition.text = format_text(state,event,selected.get("text",data.text))
	definition.choices = []
	definition["disabled"] = []
	for i in range(selected.choices.size()):
		var choice: Dictionary = selected.choices[i]
		var hint: String = choice.get("hint","")
		if int(choice.get("cost_gold",0)) > 0: hint += "\n"+Loc.text("Cost: %d gold.") % int(choice.cost_gold)
		if int(choice.get("cost_mana",0)) > 0: hint += "\n"+Loc.text("Cost: %d mana.") % int(choice.cost_mana)
		definition.choices.append([format_text(state,event,choice.label),format_text(state,event,hint.strip_edges())])
		definition.disabled.append(not choice_allowed(state,data,event,i))
	return definition

static func ai_choice(state, data: Dictionary, event: Dictionary) -> int:
	var choices: Array = story(data,event).choices
	var best := -1
	var score := -INF
	for i in range(choices.size()):
		if choice_allowed(state,data,event,i) and float(choices[i].get("ai_score",0)) > score:
			best = i
			score = float(choices[i].get("ai_score",0))
	return best

static func roll(state, effect: Dictionary, prefix := "", default_value := 1) -> int:
	var minimum: int = effect.get(prefix+"min",default_value)
	var maximum: int = effect.get(prefix+"max",minimum)
	return minimum if maximum == minimum else state.rng.randi_range(minimum,maximum)

static func resolve(state, data: Dictionary, event: Dictionary, index: int, forced_outcome := -1) -> String:
	if not choice_allowed(state,data,event,index): return ""
	var choice: Dictionary = story(data,event).choices[index]
	var pool: Array = []
	var total := 0
	for result in choice.outcomes:
		if conditions(state,event,result.get("requires",[])):
			pool.append(result)
			total += int(result.weight)
	if forced_outcome >= 0:
		if forced_outcome >= choice.outcomes.size() or not pool.has(choice.outcomes[forced_outcome]): return ""
		pool = [choice.outcomes[forced_outcome]]
	var ticket: int = state.rng.randi_range(1,total) if pool.size() > 1 else 1
	var selected: Dictionary = pool[0]
	for result in pool:
		ticket -= int(result.weight)
		if ticket <= 0: selected = result; break
	var bank: Dictionary = state.kingdom_at(event.coord)
	if not bank.is_empty(): bank.gold -= int(choice.get("cost_gold",0))
	state.set_mana(event.faction,state.get_mana(event.faction)-int(choice.get("cost_mana",0)))
	var values := {"amount":0,"refund":0,"cleared":0}
	for effect in selected.get("effects",[]): apply(state,event,bank,effect,values)
	state.clamp_mana()
	var message := format_text(state,event,selected.get("text",""),values)
	return message if not message.is_empty() else "The journey continues."

static func apply(state, event: Dictionary, bank: Dictionary, effect: Dictionary, values: Dictionary) -> void:
	var coord: Vector2i = event.coord
	var faction: int = event.faction
	var cell: Dictionary = state.cells[coord]
	var encounters = state.magic.Encounters
	match effect.kind:
		"gold":
			var amount: int = event.get("gold_reward",0) if effect.get("use_reveal_roll",false) else roll(state,effect)
			bank.gold += amount
			values.amount = amount
		"gold_percent":
			var amount := floori(bank.gold*float(effect.get("percent",-100))/100.0)
			bank.gold += amount
			values.amount = amount
		"mana":
			var amount := roll(state,effect)
			var previous: int = state.get_mana(faction)
			state.set_mana(faction,previous+amount)
			values.amount = state.get_mana(faction)-previous
		"kill_unit": state.kill_unit(coord)
		"promote":
			if cell.unit >= 3:
				if not bank.is_empty():
					values.amount = int(effect.get("max_rank_gold",20))
					bank.gold += values.amount
			else: cell.unit = clampi(cell.unit+int(effect.get("steps",1)),1,3)
		"recruit":
			var site: Vector2i = encounters.recruit_site(state,bank)
			state.cells[site].unit = int(effect.get("tier",1))
			state.cells[site].unit_owner = faction
			state.cells[site].unit_home = bank.capital
			state.cells[site].moved = not effect.get("ready",true)
		"clear_trees":
			var forest: Dictionary = encounters.forest(state,bank)
			var reward: int = forest.trees.size()*int(effect.get("gold_per_tree",1))
			if effect.get("adaptive",true) and forest.blocked*2 > forest.potential: reward = 0
			for site in forest.trees: state.cells[site].tree = false
			bank.gold += reward
			values.amount = reward
			values.cleared = forest.trees.size()
		"disband":
			for site in state.cells:
				if state.cells[site].unit <= 0 or state.unit_faction(site) != faction: continue
				var home: Dictionary = state.unit_kingdom(site)
				if home.is_empty(): home = bank
				var refund := floori(state.Catalog.unit_price(state.cells[site].unit)*float(effect.get("refund_percent",100))/100.0)
				home.gold += refund
				values.refund += refund
				encounters.disband(state,site)
		"landmark":
			var income := roll(state,effect,"income_",0)
			Sites.create(state,coord,event.id,income,roll(state,effect,"mana_",0),effect.get("steel",false))
			values.amount = income
		"mana_source": cell.mana_source = effect.get("enabled",true)
		"temporary_effect": state.set_effect(faction,effect.get("effect","free_spell"),effect.get("enabled",true))
		"building":
			cell.building = effect.get("building","house")
			cell.tree = false
			cell.grave = false
		"clear_terrain": values.amount = state.clear_terrain(coord,bank)
		"tile_value": cell.value = clampi(cell.value+int(effect.get("amount",1)),1,state.MAX_VALUE)
		"neutralize", "revolt":
			var rebel: int = encounters.rebel_faction(state) if effect.kind == "revolt" else -1
			if rebel >= 0: state.faction_count = maxi(state.faction_count,rebel+1)
			for site in state.cells:
				if state.distance(coord,site) > int(effect.get("radius",1)) or state.is_mountain(site) or state.is_bridge(site): continue
				var province: Dictionary = state.cells[site]
				if rebel < 0 and province.owner != faction: continue
				province.owner = rebel
				province.capital = -1
				province.fortified = false
				province.fortified_by = -1
				province.barrier_by = -1
				province.erase("entrenched_by")
				if rebel < 0:
					encounters.disband(state,site)
					if not Sites.protected(province): province.building = ""
				else:
					province.unit_owner = rebel if province.unit > 0 else -1
					province.unit_home = state.NONE
					province.moved = true
			if rebel >= 0: state.cells[coord].capital = rebel
			state.rebuild_kingdoms()
			if rebel >= 0: state.set_mana(rebel,0)
