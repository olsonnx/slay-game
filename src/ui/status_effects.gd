extends HBoxContainer
signal effect_inspected(effect: String)
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
	var owned_effects: Dictionary = preload("res://src/game/event_sites.gd").faction_effects(model,faction)
	for effect in Events.EFFECTS:
		if model.has_effect(faction, effect):
			var definition: Array = Events.EFFECTS[effect]
			active[effect] = [definition[0], Loc.text(definition[1]) + "\n" + (Loc.text("Next move: act again after a neutral capture\nAny move spends it") if effect == "trailblaze" else Loc.text("Next successful spell: 0 mana\nLasts until used")), Color("c7b2fa")]
	if model.has_effect(faction, "stainless_steel"):
		active["stainless_steel"] = ["S", Loc.text("Invention of stainless steel\nEach Knight costs 2 less gold per turn\nActive while you control its landmark"), Color("b5d5df")]
	var permanent_income: int = owned_effects.get("income_bonus", 0)
	if permanent_income != 0:
		active["income_bonus"] = ["G", source_breakdown(owned_effects, "income", permanent_income, Loc.text("Gold per turn")), Color("eed3a1")]
	var counts := {"entrench": 0}
	var wildlife_regen: int = owned_effects.get("wildlife_mana_regen",0)
	if wildlife_regen > 0:
		active["wildlife_mana_regen"] = ["M",source_breakdown(owned_effects, "mana", wildlife_regen, Loc.text("Mana per turn")),Color("bdb0ed")]
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
			icon.tooltip_shown.connect(func(): effect_inspected.emit(id))
		var icon: Button = icons[id]
		if icon.tooltip_text != definition[1]:
			icon.tooltip_text = definition[1]
		if icon.get_index() != index:
			move_child(icon, index)
		index += 1

func source_breakdown(effects: Dictionary, resource: String, total: int, heading: String) -> String:
	var sources: Dictionary = effects.get(resource+"_sources", {"wolf":total} if resource == "mana" else {})
	var amounts: Dictionary = effects.get(resource+"_source_amounts",{}).duplicate()
	var lines := PackedStringArray([heading])
	var unknown := PackedStringArray()
	var accounted := 0
	for source in sources:
		var title: String = Events.EVENTS.get(source,{}).get("title",preload("res://src/game/wildlife.gd").DEFINITIONS.get(source,{}).get("lair",Loc.text("Other sources")))
		var count: int = sources[source]
		var name_value := Loc.text(title)+( " ×%d" % count if count > 1 else "")
		if not amounts.has(source):
			if resource == "income" and source == "bear": amounts[source] = count*5
			elif resource == "mana" and source == "wolf": amounts[source] = count
		if amounts.has(source):
			var amount: int = amounts[source]
			accounted += amount
			lines.append("%s: %+d" % [name_value,amount])
		else: unknown.append(name_value)
	# Keep old positions accurate when an event's original random amount is unknown.
	if not unknown.is_empty() or accounted != total or lines.size() == 1:
		lines.append("%s: %+d" % [", ".join(unknown) if not unknown.is_empty() else Loc.text("Other sources"),total-accounted])
	return "\n".join(lines)
