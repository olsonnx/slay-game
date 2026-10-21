extends "res://src/ui/context_panel.gd"
const Loc = preload("res://src/localization/text.gd")
## Small inspector with a pausable slide, independent of rule mutations.
const Hud = preload("res://src/ui/game_hud.gd")
signal develop_requested
signal entrench_requested
signal relocate_requested
signal close_requested
var title: Label
var value_label: Label
var income_label: Label
var mana_label: Label
var develop_button: Button
var relocate_button: Button
var entrench_button: Button

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
	entrench_button = preload("res://src/ui/tooltip_button.gd").new()
	entrench_button.size = Vector2(386, 36)
	entrench_button.clip_text = true
	Hud.UiTheme.style_button(entrench_button)
	entrench_button.pressed.connect(func(): entrench_requested.emit())
	Sound.bind_button(entrench_button)
	add_child(entrench_button)
	hide()

func refresh(model, coord: Vector2i, can_act: bool, faction := 0) -> void:
	if not model.cells.has(coord):
		close()
		return
	var cell: Dictionary = model.cells[coord]
	var owner: int = cell["owner"]
	var bridge: bool = model.is_bridge(coord)
	var mountain: bool = model.is_mountain(coord)
	var owner_name: String = model.faction_names[owner] if owner >= 0 else "Neutral"
	title.text = "Mountains" if mountain else Loc.text("%s · %s") % [owner_name if owner >= 0 else Loc.text("Neutral"), Loc.text("Bridge" if bridge else "Province")]
	tooltip_text = Loc.text("Province %d, %d") % [coord.x, coord.y]
	var value: int = cell.get("value", 1)
	value_label.text = "Impassable" if mountain else "Wooden crossing" if bridge else Loc.text("Value %d") % value
	var blocked: bool = cell["tree"] or cell["grave"]
	var earnings: int = (0 if blocked else value) + (model.HOUSE_INCOME if cell["building"] == "house" else 0)
	income_label.text = Loc.text("%d G / turn") % earnings
	mana_label.text = Loc.text("Mana source · +%d maximum mana") % model.mana_source_capacity(cell) if cell.get("mana_source", false) else ""
	if mountain:
		mana_label.text = Loc.text("Cannot be destroyed, developed or bridged")
	if blocked:
		mana_label.text += (" · " if mana_label.text != "" else "") + Loc.text("%s blocks gold income") % Loc.text("Tree" if cell["tree"] else "Grave")
	if cell.get("fortified", false):
		mana_label.text = Loc.text("Fortified · absorbs one hit until the caster's next turn")
	if cell.get("treasure", 0) > 0:
		mana_label.text = Loc.text("Treasure chest · guaranteed %d G on capture") % cell["treasure"]
	if model.is_entrenched(coord): mana_label.text = Loc.text("Entrenched · absorbs one attack until your next turn")
	if cell.get("animal", "") != "" or cell.get("lair", "") != "":
		var kind: String = cell.get("animal",cell.get("lair", ""))
		var animal: Dictionary = model.Wildlife.DEFINITIONS[kind]
		title.text = Loc.text(animal.lair if cell.get("lair", "") != "" else animal.name)
		mana_label.text = Loc.text("Requires a Knight" if kind == "bear" else "Requires a Soldier or Knight")
		if cell.get("lair", "") != "": income_label.text = Loc.text("Reward: +5 G / turn" if kind == "bear" else "Reward: +1 mana / turn" if kind == "wolf" else "Reward: 20 G + 2 mana")
		income_label.add_theme_font_size_override("font_size",12)
	else: income_label.add_theme_font_size_override("font_size",16)
	entrench_button.visible = model.is_modern() and cell["unit"] > 0 and model.unit_faction(coord) == faction
	entrench_button.disabled = not can_act or not model.can_entrench(coord, faction)
	entrench_button.text = Loc.text("Entrenched") if model.is_entrenched(coord) else Loc.text("Entrench")
	entrench_button.tooltip_text = Loc.text("An unmoved unit spends its action to absorb one valid attack.\nProtects only this tile; expires at your next turn.\nNo gold or mana cost; does not protect bridges from Shatter.")
	develop_button.visible = not bridge and not mountain
	develop_button.disabled = not can_act or not model.can_develop(coord, faction)
	develop_button.text = Loc.text("Develop · %d G") % model.development_cost(coord) if value < model.MAX_VALUE else "Fully developed"
	if owner != faction:
		develop_button.text = Loc.text("Capture this province to develop it")
	elif model.kingdom_at(coord).is_empty():
		develop_button.text = Loc.text("Reconnect this province to develop it")
	relocate_button.visible = not bridge and not mountain and owner == faction and cell["capital"] < 0
	relocate_button.disabled = not can_act or not model.can_relocate_capital(coord, faction)
	relocate_button.text = ""
	relocate_button.tooltip_text = Loc.text("Move capital · %d G") % model.capital_relocation_cost(faction) + "\n" + Loc.text("Move this territory's capital here using its local treasury.\nRequires clear land; a unit may stay here.\nEach relocation costs 10 G more for your color, even after splits or capital loss.")
	develop_button.size.x = 386 - (50 if relocate_button.visible else 0) - (128 if entrench_button.visible else 0)
	if relocate_button.visible and owner == faction and value >= model.MAX_VALUE:
		develop_button.text = Loc.text("Fully developed")
	Hud.UiTheme.fit_text(mana_label, mana_label.text, 386)
	var content_bottom := mana_label.position.y + mana_label.size.y
	var action_y := maxf(113, content_bottom + 10)
	develop_button.position = Vector2(16, action_y)
	relocate_button.position = Vector2(360, action_y)
	entrench_button.position = Vector2(24 + develop_button.size.x if develop_button.visible else 16, action_y)
	entrench_button.size.x = 120 if develop_button.visible else 386
	if develop_button.visible or entrench_button.visible:
		content_bottom = action_y + 36
	panel_height = maxf(164, content_bottom + 15) if develop_button.visible or entrench_button.visible else content_bottom + 15
	# Keep the bottom above the resource dock when extra lines grow upwards.
	rest_top = -154 - panel_height
	reveal = reveal
	develop_button.tooltip_text = Loc.text("Develop · +1 value (max %d)\nCost %d G · uses local treasury\nTrees / graves still block income") % [model.MAX_VALUE, model.development_cost(coord)] if value < model.MAX_VALUE else Loc.text("Maximum value %d") % model.MAX_VALUE
	develop_button.tooltip_text += "\n" + Loc.text("Shortcut: %s") % Keys.key_name("develop")
