extends HBoxContainer
const Loc = preload("res://src/localization/text.gd")
## Update existing controls so refreshes preserve hover tooltips and node identity.
const Hud = preload("res://src/ui/ui_theme.gd")
const Events = preload("res://src/game/event_catalog.gd")
var icons: Dictionary = {}

func _init() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func refresh(model, faction := 0) -> void:
	var active: Dictionary = {}
	for effect in Events.EFFECTS:
		if model.has_effect(faction, effect):
			var definition: Array = Events.EFFECTS[effect]
			active[effect] = [definition[0], Loc.text(definition[1]) + "\n" + (Loc.text("Next move: act again after a neutral capture\nAny move spends it") if effect == "trailblaze" else Loc.text("Next successful spell: 0 mana\nLasts until used")), Color("c7b2fa")]
	if model.has_effect(faction, "stainless_steel"):
		active["stainless_steel"] = ["S", Loc.text("Stainless steel\nKnights cost 2 G less in upkeep. Permanent; does not stack."), Color("b5d5df")]
	var permanent_income: int = model.effects_by_faction.get(faction, {}).get("income_bonus", 0)
	if permanent_income != 0:
		active["income_bonus"] = ["G", Loc.text("Permanent income: %+d G per turn\nApplied to one treasury for this faction. Moves to a surviving treasury if its capital is lost; never multiplied by splits." ) % permanent_income, Color("eed3a1")]
	var counts := {"entrench": 0}
	for cell in model.cells.values():
		if cell.get("entrenched_by", -1) == faction: counts["entrench"] += 1
	if counts["entrench"] > 0:
		active["entrench"] = ["◇", Loc.text("Entrenched units: %d\nAbsorbs one attack on each unit's tile\nExpires next turn") % counts["entrench"], Color("91e2ef")]
	for id in icons.keys():
		if not active.has(id):
			remove_child(icons[id])
			icons[id].queue_free()
			icons.erase(id)
	var index := 0
	for id in active:
		var definition: Array = active[id]
		if not icons.has(id):
			var icon := preload("res://src/ui/tooltip_button.gd").new()
			icon.text = definition[0]
			icon.custom_minimum_size = Vector2(48, 48)
			icon.focus_mode = Control.FOCUS_NONE
			icon.add_theme_font_size_override("font_size", 25)
			Hud.button_foreground(icon,definition[2])
			add_child(icon)
			icons[id] = icon
		var icon: Button = icons[id]
		if icon.tooltip_text != definition[1]:
			icon.tooltip_text = definition[1]
		if icon.get_index() != index:
			move_child(icon, index)
		index += 1
