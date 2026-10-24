extends RefCounted
const Doc = preload("res://src/tutorial_editor/tutorial_document.gd")

static func victory(rules) -> bool:
	for faction in range(1,rules.faction_count):
		if rules.has_capital(faction): return false
	return true

static func matches(rules, round_number: int, conditions: Array, mode := "all") -> bool:
	if conditions.is_empty(): return true
	for condition in conditions:
		var passed := check(rules,round_number,condition)
		if mode == "any" and passed: return true
		if mode == "all" and not passed: return false
	return mode == "all"

static func check(rules, round_number: int, condition: Dictionary) -> bool:
	var at: Vector2i = Doc.coord(condition.get("target"))
	var faction := int(condition.get("faction",0))
	var value = condition.get("value",0)
	var cell: Dictionary = rules.cells.get(at,{})
	match condition.type:
		"victory": return victory(rules) if faction < 0 else not rules.has_capital(faction)
		"round": return round_number >= int(value)
		"mana": return rules.get_mana(faction) >= int(value)
		"territory": return rules.territory(faction) >= int(value)
		"income":
			var total := 0
			for bank in rules.kingdoms.values():
				if bank.owner == faction: total += rules.income(bank)
			return total >= int(value)
		"gold":
			if at != Doc.NONE: return rules.kingdom_at(at).get("gold",-1) >= int(value)
			var total := 0
			for bank in rules.kingdoms.values():
				if bank.owner == faction: total += bank.gold
			return total >= int(value)
		"owner": return not cell.is_empty() and cell.owner == int(value)
		"unit": return not cell.is_empty() and cell.unit >= int(value) and rules.unit_faction(at) == faction
		"building": return not cell.is_empty() and cell.building == value
		"value": return not cell.is_empty() and cell.value >= int(value)
		"clear": return not cell.is_empty() and not cell.tree and not cell.grave
		"entrenched": return not cell.is_empty() and cell.get("entrenched_by",-1) == faction
	return false
