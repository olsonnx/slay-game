extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Shared gameplay values and presentation metadata. Keep balancing edits here.
const FACTIONS := ["Fern", "Ember", "Tide", "Ochre", "Aster", "Cove", "Ruby", "Dawn", "Moss", "Frost", "Slate", "Iris"]
const UI_COLORS := [Color("86b998"), Color("d79879"), Color("92acc9"), Color("c5b478"), Color("b29acd"), Color("73b7b7"), Color("d47985"), Color("e8b4ca"), Color("bfce78"), Color("9ac1c6"), Color("99958e"), Color("aa99c7")]
const TERRAIN_COLORS := [Color("80ad86"), Color("c58768"), Color("6e8fb3"), Color("b6a66d"), Color("a18ab9"), Color("659f9e"), Color("b75b67"), Color("d5a0b7"), Color("a4b95c"), Color("7cafb6"), Color("74716c"), Color("8875ac")]
const UNIT_NAMES := ["", "Scout", "Soldier", "Knight"]
const UNIT_DESCRIPTIONS := ["", "Claims neutral land and clears trees or graves.", "Defeats Scouts and capital defenses.", "Defeats Soldiers and defensive towers."]
const UPKEEP := [0, 4, 12, 36]
const START_GOLD := 10
const MODERN_START_VALUE := 11
const UNIT_COST := 10
const UNIT_PRICES := [0, 10, 20, 40]
const TOWER_COST := 15
const CITY_COST := 25
const CITY_INCOME := 0
const ROAD_COST := 1
const TOWER_INCREMENT := 5
const TOWER_UPKEEP := 2
const BRIDGE_UPKEEP := 2
const MOVEMENT := [0, 5, 4, 3]
const BRIDGE_COST := 15

static func unit_upkeep(tier: int, _legacy_mode := true) -> int:
	return UPKEEP[tier]

static func unit_price(tier: int) -> int:
	return UNIT_PRICES[tier]

static func unit_tooltip(tier: int, wages := -1) -> String:
	return Loc.text("%s · strength %d\nCost %d G · upkeep −%d G / turn\n%s\nMove %d hexes · roads cost half\nRecruit on or beside cities / capitals; ready immediately") % [Loc.text(UNIT_NAMES[tier]), tier, unit_price(tier), unit_upkeep(tier) if wages < 0 else wages, ["", Loc.text("Captures neutral land; clears trees / graves"), Loc.text("Defeats Scouts and capitals"), Loc.text("Defeats Soldiers and towers; protects adjacent friendly land at strength 2")][tier], MOVEMENT[tier]]

static func building_tooltip(kind: String, price := -1) -> String:
	if kind == "bridge":
		return Loc.text("Bridge · cost %d G\nNeutral crossing · upkeep 2 G / turn per segment\nBuilder pays; only Shatter can remove it") % BRIDGE_COST
	if kind == "tower":
		return Loc.text("Tower · cost %d G\nProtects self + adjacent friendly land\nUpkeep 2 G / turn · next tower costs 5 G more") % (TOWER_COST if price < 0 else price)
	if kind == "road":
		return Loc.text("Road · %d G per newly paved tile · no upkeep\nConnect friendly structures using the province road icon\nConnected road steps cost ½ movement") % ROAD_COST
	return Loc.text("City · cost %d G · no upkeep\nRecruit here or next door · ready immediately · no bonus income\nCaptured cities survive and change ownership") % CITY_COST
