extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## HUD formatting, context menus, statistics, world tooltips and action overlays.
const Catalog = preload("res://src/game/game_catalog.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Spells = preload("res://src/game/spell_catalog.gd")
var session
var hud
var board
var actions: Dictionary
var tip_signature: Array = []
var tip_revision := 0

func invalidate_tip() -> void:
	tip_revision += 1

func _init(state, view_hud, board_view, commands: Dictionary) -> void:
	session = state
	hud = view_hud
	board = board_view
	actions = commands

func open_shop(kind: String) -> void:
	if actions["commands_locked"].call():
		return
	actions["close_province"].call()
	hud.help_panel.hide()
	if hud.shop_panel.visible and hud.shop_kind == kind:
		hud.shop_panel.close()
		return
	hud.shop_kind = kind
	hud.shop_items.size.y = 111
	hud.shop_panel.panel_height = hud.shop_items.position.y + hud.shop_items.size.y + 15
	hud.shop_panel.rest_top = -154 - hud.shop_panel.panel_height
	hud.pin_bottom(hud.shop_panel, 24, hud.shop_panel.rest_top, 418, hud.shop_panel.panel_height)
	hud.shop_title.text = "Recruit" if kind == "recruit" else "Spells" if kind == "spells" else "Build"
	for child in hud.shop_items.get_children():
		hud.shop_items.remove_child(child)
		child.queue_free()
	if kind == "recruit":
		for tier in range(1, 4):
			var button: Button = hud.button_at(hud.shop_items, "", Rect2((tier - 1) * 132, 0, 124, 111), actions["choose_unit"].bind(tier), Catalog.unit_tooltip(tier,  session.rules.unit_upkeep(tier, session.player_faction)))
			var name_label: Label = hud.label_at(button, Catalog.UNIT_NAMES[tier], Vector2(0, 66), 16)
			name_label.size.x = 124
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var price: Label = hud.label_at(button, (Loc.text("%d G + %d Ore") % [Catalog.unit_price(tier), Catalog.KNIGHT_ORE_COST] if tier == 3 else Loc.text("%d G") % Catalog.unit_price(tier)), Vector2(0, 90), 14, Color("eed3a1"))
			price.name = "Cost"
			price.size.x = 124
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var image := TextureRect.new()
			image.texture = board.unit_icon_texture(tier, session.player_faction)
			image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			image.position = Vector2(44, 6)
			image.size = Vector2(36, 54)
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(image)
			bind_card_shortcut(button, "choice_%d" % tier)
	elif kind == "spells":
		var index := 0
		for spell in Spells.SPELLS:
			var definition: Dictionary = Spells.SPELLS[spell]
			var mana_cost: int = 0 if session.rules.has_effect(session.player_faction, "free_spell") else definition["cost"]
			var description: String = Spells.tooltip_description(spell, session.rules.unit_upkeep(1, session.player_faction))
			var button: Button = hud.button_at(hud.shop_items, "", Rect2((index % 3) * 132, floori(index / 3.0) * 119, 124, 111), actions["choose_spell"].bind(spell), Loc.text("%s · %d mana\n%s") % [Loc.text(definition["name"]), mana_cost, description])
			var glyph: Label = hud.label_at(button, definition["glyph"], Vector2(0, 8), 36, Color("bda2fa"))
			glyph.size.x = 124
			glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var name_label: Label = hud.label_at(button, definition["name"], Vector2(0, 66), 16)
			name_label.size.x = 124
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var price: Label = hud.label_at(button, "Free" if session.rules.has_effect(session.player_faction, "free_spell") else Loc.text("%d mana") % definition["cost"], Vector2(0, 90), 14, Color("bda2fa"))
			price.size.x = 124
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bind_card_shortcut(button, "choice_%d" % (index + 1))
			index += 1
	else:
		var kinds := ["tower", "city", "bridge"]
		var width := 124
		var stride := 132
		for index in range(kinds.size()):
			var kind_name: String = kinds[index]
			var cost: int = session.rules.tower_cost(session.player_faction) if kind_name == "tower" else Catalog.BRIDGE_COST if kind_name == "bridge" else Catalog.CITY_COST
			var tip := Catalog.building_tooltip(kind_name, cost)
			var button: Button = hud.button_at(hud.shop_items, "", Rect2(index * stride, 0, width, 111), actions["choose_building"].bind(kind_name), tip)
			var name_label: Label = hud.label_at(button, ("Castle" if kind_name == "city" else kind_name.capitalize()), Vector2(0, 66), 16)
			name_label.size.x = width
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var price: Label = hud.label_at(button, Loc.text("%d G") % cost, Vector2(0, 90), 14, Color("eed3a1"))
			price.name = "Cost"
			price.size.x = width
			price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var image := TextureRect.new()
			image.texture = board.building_icon(kind_name)
			image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			image.position = Vector2((width - 54) / 2, 6)
			image.size = Vector2(54, 54)
			image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			image.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(image)
	hud.shop_panel.open(true)
	for index in range(hud.shop_items.get_child_count()):
		if kind == "build":
			bind_card_shortcut(hud.shop_items.get_child(index), "choice_%d" % (index + 1))

func bind_card_shortcut(button: Button, action: String) -> void:
	button.set_meta("base_tooltip", button.tooltip_text)
	button.set_meta("shortcut_action", action)
	button.tooltip_text += "\n" + Loc.text("Shortcut: %s") % Keys.key_name(action)

func refresh_stats() -> void:
	for container in [hud.stats_rows, hud.ledger_table_header]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	var ledger: Dictionary = preload("res://src/ui/ledger_model.gd").build(session.rules, session.round_number)
	for title in ["Faction", "Hexes", "Gold", "Income", "Costs", "Profit", "Units", ""]:
		ledger_cell(hud.ledger_table_header, Loc.text(title), hud.UiTheme.MUTED, hud.ledger_table_header.get_child_count(), true)
	var lines: Array = []
	var capital_icon = hud.UiTheme.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20"><g fill="none" stroke="#ede7d4" stroke-width="1.5" stroke-linecap="round"><circle cx="10" cy="10" r="5"/><path d="M10 1v5m0 8v5M1 10h5m8 0h5"/></g></svg>')
	for index in range(session.rules.faction_count+1):
		var owner := index if index < session.rules.faction_count else -1
		var data: Dictionary = ledger.factions[owner]
		var color: Color = session.colors[owner] if owner >= 0 else Color("a0aa83")
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 36
		row.add_theme_constant_override("separation", 8)
		hud.stats_rows.add_child(row)
		ledger_cell(row,session.names[owner] if owner >= 0 else Loc.text("Neutral"),color,0)
		var column := 1
		for field in ["hexes","gold","income","costs","profit","units"]:
			var value := "%+d" % data[field] if field == "profit" else str(data[field])
			if owner < 0 and field != "hexes": value = "—"
			var tint: Color = Color("ed9b91") if field == "profit" and data.profit < 0 else Color("bed099") if field == "profit" else hud.UiTheme.TEXT
			ledger_cell(row,value,tint,column)
			column += 1
		var focus := preload("res://src/ui/tooltip_button.gd").new()
		focus.name = "ViewCapital"
		focus.icon = capital_icon
		focus.tooltip_text = Loc.text("View capital")
		focus.focus_mode = Control.FOCUS_NONE
		focus.custom_minimum_size = Vector2(32,32)
		focus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hud.UiTheme.style_button(focus,false,false,true)
		focus.disabled = data.capital == session.selection.NONE
		if owner < 0: focus.modulate.a = 0.0
		Sound.bind_button(focus)
		focus.pressed.connect(actions["select_kingdom"].bind(data.capital))
		row.add_child(focus)
		if owner >= 0:
			lines.append({"title":session.names[owner],"color":color,"points":data.points})
	hud.ledger_table_scroll.custom_minimum_size.y = minf(252,(session.rules.faction_count+1)*36)
	hud.ledger_graph.series = lines
	hud.ledger_graph.maximum = maxf(2,ceilf(ledger.max_income/2.0)*2)
	hud.ledger_graph.last_round = session.round_number
	hud.ledger_graph.hover_round = -1
	hud.ledger_graph.queue_redraw()

func ledger_cell(row: HBoxContainer, text: String, color: Color, column: int, heading := false) -> Label:
	var label: Label = hud.label_at(row,text,Vector2.ZERO,12 if heading else 15,color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if column == 0:
		label.custom_minimum_size.x = 130
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
	else:
		label.custom_minimum_size.x = 32 if column == 7 else 76
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

func refresh_overlays() -> void:
	if session.work_active or board.level_transitioning or session.departure_active:
		board.show_overlays(session.selection.NONE, session.selection.NONE, {}, [], session.selection.NONE)
		return
	var kingdom: Dictionary = session.active_kingdom()
	var capital: Vector2i = kingdom["capital"] if not kingdom.is_empty() else session.selection.NONE
	var protector: Vector2i = session.selection.selected if session.selection.selected != session.selection.NONE else session.selection.inspected_unit
	if session.selection.action_mode != "":
		protector = session.selection.NONE
	var inspected: Vector2i = session.selection.inspected_hex if session.selection.action_mode == "" else session.selection.NONE
	if session.selection.action_mode == "" and session.selection.inspected_animal != session.selection.NONE:
		inspected = session.selection.inspected_animal
	var recruitment: bool = session.selection.action_mode == "recruit" or session.selection.action_mode == "spell" and session.selection.chosen_spell == "summon"
	board.show_overlays(session.selection.selected, session.selection.hovered, session.selection.valid_targets, session.selection.preview_path, capital, tile_intent(session.selection.hovered), protector, inspected, recruitment)
	if session.selection.inspected_hex != session.selection.NONE and session.selection.inspected_hex != session.selection.selected and session.rules.cells.has(session.selection.inspected_hex):
		board.outline(session.selection.inspected_hex, Color("ede7d4"))

func tile_intent(coord: Vector2i) -> Dictionary:
	if not session.work_active and session.selection.action_mode == "bridge" and coord != session.selection.NONE:
		return {"kind": "bridge", "valid": session.selection.valid_targets.has(coord)}
	if session.work_active or not session.rules.cells.has(coord):
		return {}
	if session.selection.action_mode == "recruit":
		var tier: int = session.rules.cells[coord]["unit"] + 1 if session.selection.recruit_tier == 0 else session.selection.recruit_tier
		return {"kind": "upgrade" if session.rules.cells[coord]["owner"] == session.player_faction and session.rules.cells[coord]["unit"] > 0 else "recruit", "valid": session.selection.valid_targets.has(coord), "tier": tier, "faction": session.player_faction}
	if session.selection.action_mode == "road":
		return {"kind":"road", "valid":session.selection.valid_targets.has(coord), "source":session.selection.selected}
	if session.selection.action_mode in ["tower", "city"]:
		return {"kind": session.selection.action_mode, "valid": session.selection.valid_targets.has(coord)}
	if session.selection.action_mode == "spell":
		if session.selection.chosen_spell == "summon":
			return {"kind": "recruit", "valid": session.selection.valid_targets.has(coord), "tier": 1, "faction": session.player_faction}
		return {"kind": "spell", "valid": session.selection.valid_targets.has(coord), "glyph": Spells.SPELLS.get(session.selection.chosen_spell, {}).get("glyph", "✦")}
	if session.rules.cells.has(session.selection.selected) and session.rules.cells[session.selection.selected]["unit"] > 0 and not session.rules.cells[session.selection.selected]["moved"] and coord != session.selection.selected:
		var kind := "move"
		if session.rules.is_bridge(coord):
			kind = "attack" if session.rules.cells[coord]["unit"] > 0 and session.rules.unit_faction(coord) != session.player_faction else "merge" if session.rules.cells[coord]["unit"] > 0 else "move"
		elif session.rules.cells[coord]["owner"] != session.player_faction:
			kind = "attack" if session.rules.cells[coord]["unit"] > 0 or session.rules.cells[coord]["building"] != "" or session.rules.cells[coord]["capital"] >= 0 else "capture"
		elif session.rules.cells[coord]["unit"] > 0:
			kind = "merge"
		return {"kind": kind, "valid": session.selection.valid_targets.has(coord), "source": session.selection.selected}
	return {}

func show_world_tip() -> void:
	var road_plan: Dictionary = session.selection.valid_targets.get(session.selection.hovered, {}) if session.selection.action_mode == "road" else {}
	var signature := [session.selection.hovered, session.rules.cells[session.selection.hovered], board.value_heatmap.active, tip_revision, session.selection.action_mode, session.selection.selected, road_plan.get("cost", -1)]
	if tip_signature == signature:
		place_world_tip()
		return
	tip_signature = signature.duplicate(true)
	if not road_plan.is_empty():
		hud.Tooltip.fit(hud.world_tip, hud.tip_label, Loc.text("Build road · %d G") % road_plan.cost + "\n" + Loc.text("1 G per new tile · click to build"))
		place_world_tip()
		return
	var cell: Dictionary = session.rules.cells[session.selection.hovered]
	var owner_name: String = session.names[cell["owner"]] if cell["owner"] >= 0 else Loc.text("Neutral")
	var mountain: bool = session.rules.is_mountain(session.selection.hovered)
	var bridge: bool = session.rules.is_bridge(session.selection.hovered)
	var filtered: bool = board.value_heatmap.active
	var feature := "Land"
	if mountain:
		feature = "Mountains"
	elif cell["unit"] > 0 and not filtered:
		feature = Catalog.UNIT_NAMES[cell["unit"]]
		owner_name = session.names[session.rules.unit_faction(session.selection.hovered)]
	elif bridge:
		feature = "Bridge"
	elif cell["capital"] >= 0:
		feature = "Capital"
	elif preload("res://src/game/event_sites.gd").protected(cell):
		feature = preload("res://src/game/event_sites.gd").structure_name(cell)
	elif cell["building"] != "":
		feature = "Castle" if cell["building"] == "city" else cell["building"].capitalize()
	elif cell["tree"] or cell["grave"]:
		feature = "Tree" if cell["tree"] else "Grave"
	var rows := PackedStringArray([Loc.text("%s · %s") % [owner_name, Loc.text(feature)]])
	if preload("res://src/game/logistics.gd").recruitment_hub(cell) and cell.get("settlement_name", "") != "":
		rows.append(cell.settlement_name)
	if cell.get("animal", "") != "":
		var animal: Dictionary = Rules.Wildlife.DEFINITIONS[cell.animal]
		rows.append(Loc.text(animal.name) + " · " + Loc.text("Requires a Knight" if cell.animal == "bear" else "Requires a Soldier or Knight"))
		rows.append(Loc.text("Targets units, buildings and provinces" if cell.animal == "bear" else "Targets units and provinces; leaves buildings intact" if cell.animal == "wolf" else "Targets buildings and provinces; cannot kill units"))
		rows.append(Loc.text("Sight 3 · two actions each World turn"))
		if cell.has("animal_target"):
			var target: Vector2i = cell.animal_target
			rows.append(Loc.text("Alert · pursuing province (%d, %d)") % [target.x,target.y])
		else: rows.append(Loc.text("Roaming near its lair"))
	if cell.get("lair", "") != "":
		var lair: Dictionary = Rules.Wildlife.DEFINITIONS[cell.lair]
		rows.append(Loc.text(lair.lair) + " · " + Loc.text("Requires a Knight" if cell.lair == "bear" else "Requires a Soldier or Knight"))
		rows.append(Loc.text("Destroy to gain: %s") % Loc.text(lair.reward))
		rows.append(Loc.text("One animal per lair · respawns after 3 World turns"))
	if mountain:
		rows.append(Loc.text("Impassable"))
	else:
		if not filtered and cell["unit"] > 0:
			rows.append(Loc.text("Movement %d · connected roads cost half") % Catalog.MOVEMENT[cell["unit"]])
			rows.append(Loc.text("%s · upkeep −%d G / turn") % [Loc.text("Ready" if board.unit_presentation.is_ready(cell) else "Moved"), session.rules.unit_upkeep(cell["unit"], session.rules.unit_faction(session.selection.hovered))])
			rows.append("")
		var income: int = 0 if bridge or cell["tree"] or cell["grave"] else cell.get("value", 1)
		if cell["building"] == "city":
			income += Rules.CITY_INCOME
		if cell.get("road", false): rows.append(Loc.text("Road · friendly road steps cost ½ movement"))
		var earnings := Loc.text("Income %+d G / turn") % income if income > 0 else Loc.text("Income 0 G")
		rows.append(Loc.text("Province · Value %d") % board.value_heatmap.tile_value(cell))
		rows.append(earnings)
		if cell["tree"] or cell["grave"]:
			rows.append(Loc.text("%s blocks income") % Loc.text("Tree" if cell["tree"] else "Grave"))
		if cell.get("ore_source", false):
			rows.append(Loc.text("Ore source · %d Ore / turn") % session.rules.ore_source_income(cell))
		if cell.capital >= 0 or cell.building in ["city", "tower"]: rows.append(Loc.text("Tier %d / 3") % session.rules.building_tier(session.selection.hovered))
		if cell.get("mana_source", false):
			rows.append(Loc.text("Mana source · capacity +%d") % session.rules.mana_source_capacity(cell))
	if session.rules.is_entrenched(session.selection.hovered):
		rows.append(Loc.text("Entrenched · absorbs one attack until next turn"))
	if cell.get("fortified", false):
		rows.append(Loc.text("Fortified · absorbs one hit"))
	if session.rules.is_barrier(session.selection.hovered):
		rows.append(Loc.text("Barrier · blocks passage until next turn"))
	elif cell.get("barrier_used", false):
		rows.append(Loc.text("Barrier already used"))
	if cell.get("event", "") != "":
		rows.append(Loc.text("? Unexplored encounter"))
		if cell["owner"] == session.player_faction:
			rows.append(Loc.text("One visit only. Main outcome requirements: %s") % Loc.text(session.rules.Events.EVENTS.get(cell["event"], {}).get("requirements", "Any army entering this province.")))
	if cell.get("treasure", 0) > 0:
		rows.append(Loc.text("Treasure chest · guaranteed %d G on capture") % cell["treasure"])
	var kingdom: Dictionary = session.rules.unit_kingdom(session.selection.hovered) if cell["unit"] > 0 else session.rules.kingdom_at(session.selection.hovered)
	if not kingdom.is_empty():
		rows.append("")
		rows.append(Loc.text("Kingdom %d G · net %+d G") % [kingdom["gold"], session.rules.income(kingdom) - session.rules.upkeep(kingdom)])
	elif cell["owner"] >= 0:
		rows.append("")
		rows.append(Loc.text("Isolated · no treasury"))
	hud.Tooltip.fit(hud.world_tip, hud.tip_label, "\n".join(rows))
	place_world_tip()

func place_world_tip() -> void:
	var screen: Vector2 = hud.get_viewport().get_visible_rect().size
	var point: Vector2 = hud.get_viewport().get_mouse_position() + Vector2(18, -hud.world_tip.size.y - 12)
	hud.UiTheme.keep_on_screen(hud.world_tip, point, screen)
	hud.world_tip.show()


func refresh_hud(economy = null) -> void:
	invalidate_tip()
	hud.update_effects(session.rules, session.player_faction)
	var model = session.rules if economy == null else economy
	var mana: Dictionary = model.mana_summary(session.player_faction)
	hud.update_mana(mana["amount"], mana["income"], mana["capacity"], mana["regeneration"])
	hud.update_ore(model.get_ore(session.player_faction), model.ore_income(session.player_faction))
	var kingdom: Dictionary = session.active_kingdom(model)
	if kingdom.is_empty() and (not model.cells.has(session.selection.active_hex) or model.cells[session.selection.active_hex]["owner"] != session.player_faction):
		for candidate in model.kingdoms.values():
			if candidate["owner"] == session.player_faction:
				session.selection.active_hex = candidate["capital"]
				kingdom = candidate
				break
	if not kingdom.is_empty():
		var income: int = model.income(kingdom)
		var wages: int = model.upkeep(kingdom)
		var net := income - wages
		hud.update_gold(kingdom["gold"], net, kingdom["capital"])
		hud.income_label.add_theme_color_override("font_color", Color("bed099") if net >= 0 else Color("dfa08e"))
		hud.gold_control.tooltip_text = Loc.text("Kingdom · %d tiles\nTreasury %d G\nIncome +%d G · upkeep −%d G\nNet %+d G / turn") % [kingdom["hexes"].size(), kingdom["gold"], income, wages, net]
		hud.gold_control.tooltip_text += "\n" + Loc.text("Infrastructure upkeep: %d G / turn") % model.infrastructure_upkeep(kingdom)
	else:
		hud.reset_gold_feedback()
		hud.money_label.text = "—"
		hud.income_label.text = ""
		hud.gold_control.tooltip_text = Loc.text("Isolated land · no treasury\nSelect a connected friendly kingdom")
	hud.level_label.text = session.names[session.active_faction]
	var flag: Dictionary = session.flags.get(session.active_faction, {"field":session.colors[session.active_faction].to_html(false), "pattern":"solid", "symbol":"none"})
	if hud.country_flag.design != flag: hud.country_flag.set_design(flag)
	hud.round_label.text = Loc.text("Turn %02d · %s") % [session.round_number, Loc.text("Tutorial" if session.tutorial != null else "Online" if session.online else "Hotseat" if session.is_hotseat() else "Playtest" if not session.initial_level_data.is_empty() else "Quick Play")]
	if board.wildlife != null and board.wildlife.is_playing: hud.round_label.text += " · " + Loc.text("World")
	hud.update_turn_color(session.colors[session.active_faction])
	hud.recruit_button.text = Loc.text(Catalog.UNIT_NAMES[session.selection.recruit_tier]) + " ×" if session.selection.action_mode == "recruit" and session.selection.recruit_tier > 0 else "Recruit"
	hud.build_button.text = Loc.text("Castle" if session.selection.action_mode == "city" else session.selection.action_mode.capitalize()) + " ×" if session.selection.action_mode in ["tower", "city", "road", "bridge"] else "Build"
	hud.spell_button.text = Loc.text(Spells.SPELLS[session.selection.chosen_spell]["name"]) + " ×" if session.selection.action_mode == "spell" and Spells.SPELLS.has(session.selection.chosen_spell) else "Spells"
	for button in [hud.recruit_button, hud.build_button, hud.spell_button]:
		button.disabled = actions["commands_locked"].call()
	# Busy opponent playback permits a hold, but commands remain locked.
	hud.end_button.disabled = actions["commands_locked"].call() and not (session.work_active and session.active_faction != session.player_faction and not session.is_closing() and not session.outcome_reached and not hud.get_tree().paused and not board.level_transitioning and not actions["modal_open"].call())
	hud.end_button.tooltip_text = Loc.text("Hold: opponents at 6× speed\nAlso: hold %s") % Keys.key_name("speed") if session.work_active and session.active_faction != session.player_faction else Loc.text("End turn · %s\nHold %s: faster movement") % [Keys.key_name("end_turn"), Keys.key_name("speed")]
	hud.stats_button.disabled = session.work_active or board.level_transitioning or session.departure_active
	hud.view_button.disabled = board.level_transitioning or session.departure_active
	hud.heatmap_button.disabled = board.level_transitioning or session.departure_active
	actions["refresh_heatmap_button"].call()
	hud.end_button.text = session.names[session.active_faction] + "…" if session.work_active and session.active_faction != session.player_faction else "Moving…" if session.work_active else Loc.text("End turn  →")
	hud.turn_spinner.set_active(session.work_active and session.active_faction != session.player_faction)
	actions["update_playback"].call()
	actions["refresh_view_button"].call()
