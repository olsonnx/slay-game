extends RefCounted
## Every existing encounter is available as an editable data-driven starting point.
const Schema = preload("res://src/game/authored_event_schema.gd")
const Catalog = preload("res://src/game/event_catalog.gd")

static func requirement(kind: String, value := 1, inverted := false) -> Dictionary:
	return {"kind":kind,"value":value,"not":inverted,"effect":"free_spell"}

static func effect(kind: String, fields: Dictionary = {}) -> Dictionary:
	var result := Schema.action(kind)
	result.merge(fields,true)
	return result

static func outcome(message: String, effects: Array = [], weight := 100) -> Dictionary:
	return {"text":message,"effects":effects,"weight":weight,"requires":[]}

static func template(id: String) -> Dictionary:
	var base: Dictionary = Catalog.BUILTIN_EVENTS[id]
	var data := Schema.fresh(id)
	for field in ["title","text","painting","painting_title","painting_artist","requirements"]:
		if base.has(field): data[field] = base[field]
	data.weight = Catalog.BUILTIN_WEIGHTS[id]
	data.modern_only = id not in ["gold","altar","pit","duel","wizard","goose"]
	for kind in base.get("requires",[]): data.requires.append(requirement(kind))
	data.choices = []
	for source in base.choices:
		var choice := Schema.choice()
		choice.label = source[0]
		choice.hint = source[1]
		data.choices.append(choice)
	match id:
		"gold":
			data.requires = [requirement("kingdom")]
			data.gold_roll_min = 10
			data.gold_roll_max = 25
			data.choices[0].hint = "Gain {gold} gold."
			data.choices[0].outcomes = [outcome("Your kingdom gains {amount} gold.",[effect("gold",{"use_reveal_roll":true})])]
		"goose": data.choices[0].outcomes = [outcome("Your kingdom gains 2 gold.",[effect("gold",{"min":2,"max":2})])]
		"pit": data.choices[0].outcomes = [outcome("Your army was lost in the pit.",[effect("kill_unit")])]
		"wizard":
			data.requires = [requirement("no_effect")]
			data.choices[0].outcomes = [outcome("Your next spell is free.",[effect("temporary_effect")])]
		"altar":
			data.requires = [requirement("mana_source",1,true)]
			data.choices[0].outcomes = [outcome("The altar awakens: a new mana source.",[effect("mana_source"),effect("landmark",{"income_min":0,"income_max":0})],60),outcome("Your army was lost.",[effect("kill_unit")],40)]
		"duel":
			data.requires = [requirement("duel_reward")]
			data.choices[0].outcomes = [outcome("Your champion wins the duel.",[effect("promote")],60),outcome("Your army was lost.",[effect("kill_unit")],40)]
		"comet":
			data.choices[0].outcomes = [outcome("A landmark is built: +{amount} gold per turn.",[effect("landmark",{"income_min":1,"income_max":2})])]
			data.choices[1].requires = [requirement("recruit_space")]
			data.choices[1].outcomes = [outcome("A ready Scout joins your kingdom.",[effect("recruit")])]
		"innkeeper":
			for choice in data.choices:
				choice.outcomes = [outcome("Your army wins 4 gold on a wager.",[effect("gold",{"min":4,"max":4})],50),outcome("The drink lives up to its name. Your army does not.",[effect("kill_unit")],50)]
		"lumberjack":
			data.choices[0].hint = "Clear {trees} trees; gain 1 gold per tree."
			data.choices[0].outcomes = [outcome("{cleared} trees removed; {amount} gold earned.",[effect("clear_trees")])]
			var alternate: Dictionary = data.choices[0].duplicate(true)
			alternate.label = base.overgrown_choices[0][0]
			alternate.hint = "Clear {trees} trees. No gold reward."
			data.variants = [{"text":base.overgrown_text,"requires":[requirement("forest_overgrown")],"choices":[alternate]}]
		"regroup":
			data.choices[0].outcomes = [outcome("Your armies stand down. {refund} gold returned.",[effect("disband")])]
			data.choices[1].outcomes = [outcome("The army remains reassuringly imbalanced.")]
		"cartographer": data.choices[0].outcomes = [outcome("The border is corrected.",[effect("neutralize")])]
		"ransom":
			data.choices[0].outcomes = [outcome("The family pays 20 gold.",[effect("gold",{"min":20,"max":20})])]
			data.choices[1].requires = [requirement("mana_space")]
			data.choices[1].outcomes = [outcome("A grim demonstration of power: +1 mana.",[effect("mana")])]
		"economist":
			data.choices[0].requires = [requirement("income_at_least")]
			data.choices[0].outcomes = [outcome("Gain 10 gold; this landmark costs its kingdom 1 gold per turn.",[effect("gold",{"min":10,"max":10}),effect("landmark",{"income_min":-1,"income_max":-1})])]
			data.choices[1].cost_gold = 10
			data.choices[1].ai_score = 10
			data.choices[1].outcomes = [outcome("This landmark grants its kingdom 1 gold per turn.",[effect("landmark")])]
		"revolt":
			data.choices[0].outcomes = [outcome("A new kingdom declares independence.",[effect("revolt")])]
			data.choices[1].outcomes = [outcome("The treasury is empty.",[effect("gold_percent")])]
			data.choices[1].ai_score = 10
		"stainless_steel": data.choices[0].outcomes = [outcome("The landmark's owner pays 25% lower Knight wages.",[effect("landmark",{"income_min":0,"income_max":0,"steel":true})])]
		"builders_guild", "barracks", "scout_lodge", "watchtower":
			var bonus: String = {"builders_guild":"development_discount", "barracks":"soldier_discount", "scout_lodge":"scout_discount", "watchtower":"defense_aura"}[id]
			data.choices[0].outcomes = [outcome(base.choices[0][1], [effect("landmark", {"income_min":0,"income_max":0,bonus:true})])]
	return data
