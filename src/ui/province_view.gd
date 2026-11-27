extends "res://src/ui/context_panel.gd"
const Loc = preload("res://src/localization/text.gd")
## Small inspector with a pausable slide, independent of rule mutations.
const Hud = preload("res://src/ui/game_hud.gd")
signal upgrade_requested
signal develop_requested
signal entrench_requested
signal relocate_requested
signal road_requested
signal rename_requested(coord: Vector2i, text: String)
signal close_requested
var title: Label
var value_label: Label
var income_label: Label
var mana_label: Label
var upgrade_button: Button
var develop_button: Button
var relocate_button: Button
var entrench_button: Button
var road_button: Button
var name_input: LineEdit
var name_coord := Vector2i(1000000, 1000000)
var saved_name := ""

func _ready() -> void:
	rest_top = -318.0
	panel_height = 164.0
	anchor_top = 1
	anchor_bottom = 1
	offset_left = 24
	offset_right = 442
	reveal = 0
	add_theme_stylebox_override("panel", Hud.style(Color("17252a"), 13, true))
	title = Hud.label_at(self, "Province", Vector2(16, 12), 17)
	title.size = Vector2(340, 32)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = Loc.text("Close province details.")
	close.pressed.connect(func(): close_requested.emit())
	Sound.bind_button(close, func(): return &"ui_close")
	add_child(close)
	Hud.UiTheme.place_close_button(close, 12)
	value_label = Hud.label_at(self, "", Vector2(16, 47), 23, Color("eed3a1"))
	income_label = Hud.label_at(self, "", Vector2(224, 53), 16, Color("b5c6bd"))
	mana_label = Hud.label_at(self, "", Vector2(16, 84), 13, Color("bdb0ed"))
	upgrade_button = preload("res://src/ui/tooltip_button.gd").new()
	upgrade_button.size = Vector2(386, 36)
	Hud.UiTheme.style_button(upgrade_button)
	upgrade_button.pressed.connect(func(): upgrade_requested.emit())
	Sound.bind_button(upgrade_button)
	add_child(upgrade_button)
	develop_button = preload("res://src/ui/tooltip_button.gd").new()
	develop_button.position = Vector2(16, 113)
	develop_button.size = Vector2(386, 36)
	develop_button.clip_text = true
	Hud.UiTheme.style_button(develop_button)
	develop_button.pressed.connect(func(): develop_requested.emit())
	Sound.bind_button(develop_button)
	add_child(develop_button)
	relocate_button = preload("res://src/ui/tooltip_button.gd").new()
	relocate_button.size = Vector2(42, 36)
	relocate_button.icon = Hud.UiTheme.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#ede7d4" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3 18V8h3v3h3V8h3v3h3V8h3v10H3z M9 18v-4h3v4 M14 4h7m-3-3 3 3-3 3"/></g></svg>')
	Hud.UiTheme.style_button(relocate_button)
	relocate_button.pressed.connect(func(): relocate_requested.emit())
	Sound.bind_button(relocate_button)
	add_child(relocate_button)
	road_button = preload("res://src/ui/tooltip_button.gd").new()
	road_button.size = Vector2(42, 36)
	road_button.icon = Hud.UiTheme.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#ede7d4" stroke-width="1.8" stroke-linecap="round"><path d="M8 3 4 21M16 3l4 18M12 4v3m0 4v3m0 4v3"/></g></svg>')
	road_button.tooltip_text = Loc.text("Connect road\nChoose a friendly structure or existing road tile to connect.\n1 G per newly paved tile; existing pavement is free.")
	Hud.UiTheme.style_button(road_button)
	road_button.pressed.connect(func(): road_requested.emit())
	Sound.bind_button(road_button)
	add_child(road_button)
	entrench_button = preload("res://src/ui/tooltip_button.gd").new()
	entrench_button.size = Vector2(386, 36)
	entrench_button.clip_text = true
	Hud.UiTheme.style_button(entrench_button)
	entrench_button.pressed.connect(func(): entrench_requested.emit())
	Sound.bind_button(entrench_button)
	add_child(entrench_button)
	name_input = LineEdit.new()
	name_input.max_length = 40
	name_input.position = Vector2(12, 12)
	name_input.size = Vector2(346, 32)
	name_input.add_theme_font_size_override("font_size", 17)
	name_input.add_theme_color_override("font_color", Color("ede7d4"))
	name_input.add_theme_color_override("font_placeholder_color", Color("ede7d4"))
	var name_style := StyleBoxEmpty.new()
	name_style.content_margin_left = 4
	name_style.content_margin_right = 4
	name_style.content_margin_top = 4
	name_style.content_margin_bottom = 4
	name_input.add_theme_stylebox_override("normal", name_style)
	name_input.add_theme_stylebox_override("read_only", name_style)
	name_input.add_theme_stylebox_override("focus", Hud.UiTheme.focus_style(Vector2(4, 4)))
	name_input.tooltip_text = Loc.text("Click to edit the name · Enter or click away to save · leave empty to reset")
	name_input.text_submitted.connect(func(_text: String): name_input.release_focus())
	name_input.focus_exited.connect(commit_name)
	add_child(name_input)
	hide()

func commit_name() -> void:
	if name_input.text == saved_name: return
	saved_name = name_input.text.strip_edges()
	name_input.text = saved_name
	rename_requested.emit(name_coord, saved_name)

func close() -> void:
	name_input.release_focus()
	super.close()

func refresh(model, coord: Vector2i, can_act: bool, faction := 0) -> void:
	if name_coord != coord: name_input.release_focus()
	if not model.cells.has(coord):
		close()
		return
	var cell: Dictionary = model.cells[coord]
	var owner: int = cell["owner"]
	var bridge: bool = model.is_bridge(coord)
	var mountain: bool = model.is_mountain(coord)
	var owner_name: String = model.faction_names[owner] if owner >= 0 else "Neutral"
	title.text = "Mountains" if mountain else Loc.text("%s · %s") % [owner_name if owner >= 0 else Loc.text("Neutral"), Loc.text("Bridge" if bridge else "Province")]
	var value: int = cell.get("value", 1)
	value_label.text = "Impassable" if mountain else "Wooden crossing" if bridge else Loc.text("Value %d") % value
	var blocked: bool = cell["tree"] or cell["grave"]
	var earnings: int = (0 if blocked else value) + (model.CITY_INCOME if cell["building"] == "city" else 0)
	income_label.text = Loc.text("%d G / turn") % earnings
	mana_label.text = Loc.text("Mana source · +%d maximum mana") % model.mana_source_capacity(cell) if cell.get("mana_source", false) else ""
	if preload("res://src/game/event_sites.gd").protected(cell):
		title.text = preload("res://src/game/event_sites.gd").structure_name(cell)
		mana_label.text = preload("res://src/game/event_sites.gd").description(cell)
		income_label.text = Loc.text("%d G / turn") % (earnings+int(cell.get("site_income",0)))
	if mountain:
		mana_label.text = Loc.text("Cannot be destroyed, developed or bridged")
	if blocked:
		mana_label.text += (" · " if mana_label.text != "" else "") + Loc.text("%s blocks gold income") % Loc.text("Tree" if cell["tree"] else "Grave")
	if cell.get("fortified", false):
		mana_label.text = Loc.text("Fortified · absorbs one hit until the caster's next turn")
	if cell.get("treasure", 0) > 0:
		mana_label.text = Loc.text("Treasure chest · guaranteed %d G on capture") % cell["treasure"]
	if model.is_entrenched(coord): mana_label.text = Loc.text("Entrenched · absorbs one attack until your next turn")
	if cell["building"] == "city":
		title.text = Loc.text("Castle")
		mana_label.text += ("\n" if mana_label.text != "" else "") + Loc.text("Recruitment range %d · ready immediately · no bonus income") % preload("res://src/game/logistics.gd").recruitment_range(cell)
	if cell.capital >= 0: title.text = Loc.text("Capital")
	if preload("res://src/game/logistics.gd").recruitment_hub(cell) and cell.get("settlement_name", "") != "":
		title.text = cell.settlement_name
	title.size.x = 340
	title.clip_text = true
	if cell["building"] == "tower": title.text = Loc.text("Tower")
	if cell["building"] == "tower": mana_label.text += ("\n" if mana_label.text != "" else "") + Loc.text("Tower upkeep · 2 G / turn")
	if bridge:
		var payer: Dictionary = preload("res://src/game/logistics.gd").bridge_bank(model, cell)
		mana_label.text = Loc.text("Bridge upkeep · 2 G / turn · treasury (%d, %d)") % [payer.capital.x, payer.capital.y] if not payer.is_empty() else Loc.text("Neutral bridge · no sponsor")
	if cell.get("road", false): mana_label.text += ("\n" if mana_label.text != "" else "") + Loc.text("Road · friendly road steps cost ½ movement")
	if cell.get("animal", "") != "" or cell.get("lair", "") != "":
		var kind: String = cell.get("animal",cell.get("lair", ""))
		var animal: Dictionary = model.Wildlife.DEFINITIONS[kind]
		title.text = Loc.text(animal.lair if cell.get("lair", "") != "" else animal.name)
		mana_label.text = Loc.text("Requires a Knight" if kind == "bear" else "Requires a Soldier or Knight")
		if cell.get("lair", "") != "": income_label.text = Loc.text("Reward: +5 G / turn" if kind == "bear" else "Reward: +1 mana / turn" if kind == "wolf" else "Reward: 20 G + 2 mana")
		income_label.add_theme_font_size_override("font_size",12)
	else: income_label.add_theme_font_size_override("font_size",16)
	entrench_button.visible = cell["unit"] > 0 and model.unit_faction(coord) == faction
	entrench_button.disabled = not can_act or not model.can_entrench(coord, faction)
	entrench_button.text = Loc.text("Entrenched") if model.is_entrenched(coord) else Loc.text("Entrench")
	entrench_button.tooltip_text = Loc.text("An unmoved unit spends its action to absorb one valid attack.\nProtects only this tile; expires at your next turn.\nNo gold or mana cost; does not protect bridges from Shatter.")
	develop_button.visible = not bridge and not mountain
	develop_button.disabled = not can_act or not model.can_develop(coord, faction)
	develop_button.text = Loc.text("Develop · %d G") % model.development_cost(coord) if value < model.MAX_VALUE else "Fully developed"
	if cell.get("ore_source", false):
		mana_label.text += ("\n" if mana_label.text != "" else "") + Loc.text("Ore source · %d Ore / turn · 1 per %d development") % [model.ore_source_income(cell), model.Catalog.ORE_DEVELOPMENT_PER_INCOME]
	var structure: bool = cell.capital >= 0 or cell.building in ["city", "tower"]
	upgrade_button.visible = structure and owner == faction
	upgrade_button.disabled = not can_act or not model.can_upgrade_building(coord, faction)
	if structure:
		var tier: int = model.building_tier(coord)
		mana_label.text += ("\n" if mana_label.text != "" else "") + Loc.text("Tier %d / 3") % tier
		if cell.capital >= 0:
			mana_label.text += Loc.text(" · recruitment range %d") % preload("res://src/game/logistics.gd").recruitment_range(cell)
		if cell.building == "tower" or cell.capital >= 0:
			mana_label.text += " · " + Loc.text("Requires Soldier" if tier == 1 else "Requires Knight")
		if cell.building == "tower" and tier == 3: mana_label.text += "\n" + Loc.text("Entrenched each turn · absorbs one attack")
		if cell.capital >= 0 and tier == 3: mana_label.text += "\n" + Loc.text("Development costs −50% here and on adjacent friendly tiles")
		upgrade_button.text = Loc.text("Upgrade to tier %d · %d Ore") % [tier + 1, model.building_upgrade_cost(coord)] if tier < 3 else Loc.text("Fully upgraded · tier 3")
		upgrade_button.tooltip_text = Loc.text("Fully upgraded") if tier == 3 else (
			Loc.text("Tier 2 · requires a Knight to defeat · recruitment range 2") if cell.capital >= 0 and tier == 1 else
			Loc.text("Tier 3 · development costs −50% here and on adjacent friendly tiles") if cell.capital >= 0 else
			Loc.text("Tier %d · recruitment range %d") % [tier + 1, tier] if cell.building == "city" else
			Loc.text("Tier 2 · requires a Knight to destroy") if tier == 1 else Loc.text("Tier 3 · absorbs the first valid attack each owner's turn"))
	if owner != faction:
		develop_button.text = Loc.text("Capture this province to develop it")
	elif model.kingdom_at(coord).is_empty():
		develop_button.text = Loc.text("Reconnect this province to develop it")
	relocate_button.visible = not bridge and not mountain and owner == faction and cell["capital"] < 0
	relocate_button.disabled = not can_act or not model.can_relocate_capital(coord, faction)
	relocate_button.text = ""
	relocate_button.tooltip_text = Loc.text("Move capital · %d G") % model.capital_relocation_cost(faction) + "\n" + Loc.text("Move this territory's capital here using its local treasury.\nRequires clear land; a unit may stay here.\nEach relocation costs 10 G more for your color, even after splits or capital loss.")
	road_button.visible = preload("res://src/game/road_construction.gd").endpoint(model, coord, faction)
	road_button.disabled = not can_act or model.road_targets(coord, faction).is_empty()
	develop_button.size.x = 386 - (50 if relocate_button.visible else 0) - (50 if road_button.visible else 0) - (128 if entrench_button.visible else 0)
	if relocate_button.visible and owner == faction and value >= model.MAX_VALUE:
		develop_button.text = Loc.text("Fully developed")
	Hud.UiTheme.fit_text(mana_label, mana_label.text, 386)
	var content_bottom := mana_label.position.y + mana_label.size.y
	var action_y := maxf(113, content_bottom + 10)
	develop_button.position = Vector2(16, action_y)
	relocate_button.position = Vector2(360, action_y)
	road_button.position = Vector2(310 if relocate_button.visible else 360, action_y)
	entrench_button.position = Vector2(24 + develop_button.size.x if develop_button.visible else 16, action_y)
	entrench_button.size.x = 120 if develop_button.visible else 386
	if develop_button.visible or entrench_button.visible:
		content_bottom = action_y + 36
	if upgrade_button.visible:
		upgrade_button.position = Vector2(16, content_bottom + 8)
		content_bottom += 44
	name_input.visible = model.can_rename_settlement(coord, faction)
	title.visible = not name_input.visible
	name_input.editable = can_act
	if name_input.visible:
		name_input.placeholder_text = Loc.text("Capital" if cell.capital >= 0 else "Castle")
		if name_coord != coord or not name_input.has_focus():
			name_input.text = cell.get("settlement_name", "")
			saved_name = name_input.text
	name_coord = coord
	panel_height = maxf(164, content_bottom + 15) if develop_button.visible or entrench_button.visible else content_bottom + 15
	# Keep the bottom above the resource dock when extra lines grow upwards.
	rest_top = -154 - panel_height
	reveal = reveal
	develop_button.tooltip_text = Loc.text("Develop · +1 value (max %d)\nCost %d G · uses local treasury\nTrees / graves still block income") % [model.MAX_VALUE, model.development_cost(coord)] if value < model.MAX_VALUE else Loc.text("Maximum value %d") % model.MAX_VALUE
	develop_button.tooltip_text += "\n" + Loc.text("Shortcut: %s") % Keys.key_name("develop")
