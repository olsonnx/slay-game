extends RefCounted
## Durable rewards belong to the province, never to the discovering faction.
const Loc = preload("res://src/localization/text.gd")
const KIND := "monument"
const BONUS_FIELDS := {"development_discount":"site_development_discount", "soldier_discount":"site_soldier_discount", "scout_discount":"site_scout_discount", "defense_aura":"site_defense_aura"}
const WAGE_FIELDS := {"stainless_steel":"site_steel", "soldier_discount":"site_soldier_discount", "scout_discount":"site_scout_discount"}

static func create(state, coord: Vector2i, source: String, income := 0, mana := 0, steel := false, bonuses: Dictionary = {}) -> void:
	var cell: Dictionary = state.cells[coord]
	cell["building"] = KIND
	cell["site_source"] = source
	cell["site_income"] = income
	cell["site_mana"] = mana
	cell["site_steel"] = steel
	for bonus in BONUS_FIELDS: cell[BONUS_FIELDS[bonus]] = bonuses.get(bonus, false)
	cell["tree"] = false
	cell["grave"] = false

static func protected(cell: Dictionary) -> bool:
	return cell.get("building", "") == KIND

static func structure_name(cell: Dictionary) -> String:
	match cell.get("site_source", ""):
		"builders_guild": return Loc.text("Builders' Guild")
		"barracks": return Loc.text("Soldiers' Barracks")
		"scout_lodge": return Loc.text("Scout Lodge")
		"watchtower": return Loc.text("Watchtower")
	return Loc.text("Landmark")

static func has_aura(state, coord: Vector2i, bonus: String, faction := -2) -> bool:
	if faction == -2: faction = state.cells[coord]["owner"]
	if faction < 0: return false
	for site in [coord] + state.neighbors(coord):
		var cell: Dictionary = state.cells[site]
		if cell["owner"] == faction and protected(cell) and cell.get(BONUS_FIELDS[bonus], false): return true
	return false

static func defense_bonus(state, coord: Vector2i, base: int) -> int:
	var cell: Dictionary = state.cells[coord]
	if cell["owner"] < 0:
		if cell["unit"] > 0 and has_aura(state, coord, "defense_aura", state.unit_faction(coord)): return maxi(base, cell["unit"] + 1)
		return base
	if protected(cell) and cell.get("site_defense_aura", false): return base + 1
	if cell["unit"] > 0 and has_aura(state, coord, "defense_aura"):
		return maxi(base, cell["unit"] + 1)
	return base

static func mana_bonus(state, faction: int) -> int:
	var total: int = state.effects_by_faction.get(faction,{}).get("wildlife_mana_regen",0)
	for cell in state.cells.values():
		if cell["owner"] == faction and protected(cell): total += int(cell.get("site_mana",0))
	return total

static func faction_effects(state, faction: int) -> Dictionary:
	# Legacy faction rewards remain readable in saved positions and old replays.
	var effects: Dictionary = state.effects_by_faction.get(faction, {}).duplicate(true)
	for coord in state.cells:
		var cell: Dictionary = state.cells[coord]
		if cell["owner"] != faction or not protected(cell): continue
		for pair in [["site_income","income_bonus","income"],["site_mana","wildlife_mana_regen","mana"]]:
			if pair[0] == "site_income" and state.kingdom_at(coord).is_empty(): continue
			var amount: int = cell.get(pair[0],0)
			if amount == 0: continue
			effects[pair[1]] = int(effects.get(pair[1],0))+amount
			var source: String = cell.get("site_source", "")
			var counts: Dictionary = effects.get(pair[2]+"_sources",{})
			var amounts: Dictionary = effects.get(pair[2]+"_source_amounts",{})
			counts[source] = int(counts.get(source,0))+1
			amounts[source] = int(amounts.get(source,0))+amount
			effects[pair[2]+"_sources"] = counts
			effects[pair[2]+"_source_amounts"] = amounts
		if cell.get("site_steel",false): effects["stainless_steel"] = true
		for bonus in BONUS_FIELDS:
			if cell.get(BONUS_FIELDS[bonus], false): effects[bonus] = true
	return effects

static func description(cell: Dictionary) -> String:
	var lines := PackedStringArray([Loc.text("Conquerable landmark · cannot be destroyed")])
	if cell.get("site_income",0) != 0: lines.append(Loc.text("%+d G / turn to this kingdom") % int(cell.site_income))
	if cell.get("site_mana",0) != 0: lines.append(Loc.text("%+d mana / turn to its owner") % int(cell.site_mana))
	if cell.get("site_steel",false): lines.append(Loc.text("Owner's Knight wages are 25% lower (does not stack)"))
	if cell.get("site_soldier_discount", false): lines.append(Loc.text("Owner's Soldier wages are 50% lower (does not stack)"))
	if cell.get("site_scout_discount", false): lines.append(Loc.text("Owner's Scout wages are 50% lower (does not stack)"))
	if cell.get("site_development_discount", false): lines.append(Loc.text("Development costs 50% less here and on adjacent friendly provinces (does not stack)"))
	if cell.get("site_defense_aura", false): lines.append(Loc.text("+1 defense here and to adjacent friendly units; no attack bonus (does not stack)"))
	if cell.get("mana_source",false): lines.append(Loc.text("Mana source · +%d maximum mana") % (2 if cell.get("capital",-1) >= 0 or cell.get("tree",false) else 1))
	return "\n".join(lines)
