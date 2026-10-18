extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Shared gameplay values and presentation metadata. Keep balancing edits here.
const FACTIONS := ["Fern", "Ember", "Tide", "Ochre", "Aster", "Cove", "Ruby", "Dawn", "Moss", "Frost", "Slate", "Iris"]
const UI_COLORS := [Color("86b998"), Color("d79879"), Color("92acc9"), Color("c5b478"), Color("b29acd"), Color("73b7b7"), Color("d47985"), Color("e8b4ca"), Color("bfce78"), Color("9ac1c6"), Color("99958e"), Color("aa99c7")]
const TERRAIN_COLORS := [Color("80ad86"), Color("c58768"), Color("6e8fb3"), Color("b6a66d"), Color("a18ab9"), Color("659f9e"), Color("b75b67"), Color("d5a0b7"), Color("a4b95c"), Color("7cafb6"), Color("74716c"), Color("8875ac")]
const UNIT_NAMES := ["", "Scout", "Soldier", "Knight"]
const UNIT_DESCRIPTIONS := ["", "Claims neutral land and clears trees or graves.", "Defeats Scouts and capital defenses.", "Defeats Soldiers and defensive towers."]
const UPKEEP := [0, 1, 2, 4]
const MODERN_UPKEEP := [0, 4, 12, 36]
const START_GOLD := 16
const MODERN_START_GOLD := 10
const MODERN_START_VALUE := 11
const UNIT_COST := 10
const UNIT_PRICES := [0, 10, 20, 40]
const TOWER_COST := 15
const HOUSE_COST := 20
const HOUSE_INCOME := 4
const BRIDGE_COST := 15

static func unit_upkeep(tier: int, modern := false) -> int:
	return MODERN_UPKEEP[tier] if modern else UPKEEP[tier]

static func unit_price(tier: int) -> int:
	return UNIT_PRICES[tier]

static func unit_tooltip(tier: int, modern := false, wages := -1) -> String:
	return Loc.text("%s · strength %d\nCost %d G · upkeep −%d G / turn\n%s\nUpgrade: pay the difference") % [Loc.text(UNIT_NAMES[tier]), tier, unit_price(tier), unit_upkeep(tier, modern) if wages < 0 else wages, ["", Loc.text("Captures neutral land; clears trees / graves"), Loc.text("Defeats Scouts and capitals"), Loc.text("Defeats Soldiers and towers; protects adjacent friendly land at strength 2")][tier]]

static func building_tooltip(kind: String) -> String:
	if kind == "bridge":
		return Loc.text("Bridge · cost %d G\nSpans water beside your kingdom / bridges\nNeutral crossing · no income") % BRIDGE_COST
	if kind == "tower":
		return Loc.text("Tower · cost %d G\nProtects self + adjacent friendly land\nNeeds clear land · no upkeep") % TOWER_COST
	return Loc.text("House · cost %d G\nIncome +%d G / turn · no upkeep\nNeeds clear land · lost on capture") % [HOUSE_COST, HOUSE_INCOME]
