extends RefCounted
const Loc = preload("res://src/localization/text.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
## Definitions are shared by targeting, prices, UI and computer opponents.
const SPELLS := {
	"trailblaze": {"name": "Trailblaze", "glyph": "↠", "cost": 1, "target": "friendly_land", "description": "Bless your faction: the next unit you move can move again if it captures neutral land. Any valid move consumes the blessing; it does not stack.", "message": "Trailblaze is ready for your next move."},
	"summon": {"name": "Summon", "glyph": "✦", "cost": 2, "target": "empty_friendly_land",
		"description": "Summon a ready Scout on empty land in a friendly kingdom. Clears trees or graves; a cleared tree gives 1 G. The Scout has normal upkeep.", "message": "Scout summoned, ready to move."},
	"shatter": {"name": "Shatter", "glyph": "✕", "cost": 2, "target": "neutral_structure",
		"description": "Destroy a neutral structure next to your kingdom or reachable bridge chain. A destroyed bridge and any soldier on it are lost.", "message": "Shatter struck the neutral structure."}
}

static func tooltip_description(spell: String, scout_upkeep := -1) -> String:
	if scout_upkeep < 0: scout_upkeep = Catalog.unit_upkeep(1, true)
	var description: String = {
		"trailblaze": Loc.text("Next move: act again after a neutral capture\nAny move spends it · no stacking"),
		"summon": Loc.text("Ready Scout on empty friendly land\nClears trees / graves · tree reward +1 G\nUpkeep −%d G / turn"),
		"shatter": Loc.text("Destroy an adjacent / connected neutral structure\nBridge garrison is lost")
	}.get(spell, "")
	return description % scout_upkeep if spell == "summon" else description
