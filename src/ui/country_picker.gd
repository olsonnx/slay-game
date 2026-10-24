extends Control
## Country cards replace the long dropdown, while keeping one saved selection.
signal item_selected(index: int)
const Catalog = preload("res://src/game/game_catalog.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
var selected_value := -1
var item_count: int:
	get: return 14 if PlayerProfile.exists() else 13
var selected: int:
	get: return 13 if selected_value == -2 else selected_value + 1
var summary: Button
var caption: Label
var flag
var popup: PopupPanel
var cards: Dictionary = {}
var own_card: Button

func _ready() -> void:
	summary = Button.new()
	add_child(summary)
	summary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sound.bind_button(summary)
	flag = preload("res://src/ui/kingdom_flag.gd").new()
	flag.position = Vector2(12, 6)
	flag.size = Vector2(48, 32)
	summary.add_child(flag)
	caption = Ui.label_at(summary, "", Vector2(78, 10), 16)
	caption.size = Vector2(310, 26)
	caption.clip_text = true
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	Ui.label_at(summary, "...", Vector2(402, 8), 18)
	popup = PopupPanel.new()
	popup.theme = Ui.create_theme()
	add_child(popup)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	popup.add_child(margin)
	margin.add_child(content)
	var title := Label.new()
	title.text = Loc.text("Choose your country")
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	content.add_child(top)
	own_card = card(top, -2, Loc.text("My country"), Color("86b998"))
	card(top, -1, Loc.text("Random default"), Color("9eb2a7"))
	var label := Label.new()
	label.text = Loc.text("Default countries")
	content.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	content.add_child(grid)
	for index in range(Catalog.FACTIONS.size()): card(grid, index, Catalog.FACTIONS[index], Catalog.UI_COLORS[index])
	summary.pressed.connect(func(): refresh(); popup.popup_centered(Vector2i(560, 376)))
	PlayerProfile.changed.connect(refresh)
	refresh()

func card(parent: Control, value: int, text: String, color: Color) -> Button:
	var button := Button.new()
	button.text = Loc.text(text)
	button.custom_minimum_size = Vector2(164 if value >= 0 else 250, 44)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var swatch := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	swatch.fill(color)
	button.icon = ImageTexture.create_from_image(swatch)
	parent.add_child(button)
	Sound.bind_button(button)
	button.pressed.connect(func():
		selected_value = value
		refresh()
		popup.hide()
		item_selected.emit(selected))
	cards[value] = button
	return button

func select(index: int) -> void:
	selected_value = -2 if index == 13 and PlayerProfile.exists() else clampi(index - 1, -1, Catalog.FACTIONS.size() - 1)
	refresh()

func get_selected_metadata() -> int: return selected_value

func refresh() -> void:
	if summary == null: return
	if selected_value == -2 and not PlayerProfile.exists(): selected_value = -1
	own_card.disabled = not PlayerProfile.exists()
	own_card.text = PlayerProfile.data.name if PlayerProfile.exists() else Loc.text("Create a profile first")
	own_card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var own_color := Color(PlayerProfile.data.get("color", "86b998"))
	var own_swatch := Image.create(18, 18, false, Image.FORMAT_RGBA8)
	own_swatch.fill(own_color)
	own_card.icon = ImageTexture.create_from_image(own_swatch)
	if selected_value == -2:
		caption.text = PlayerProfile.data.name
		flag.set_design(PlayerProfile.data.flag)
	else:
		caption.text = Catalog.FACTIONS[selected_value] if selected_value >= 0 else Loc.text("Random default")
		flag.set_design({"field":Catalog.UI_COLORS[selected_value].to_html(false) if selected_value >= 0 else "526863", "pattern":"solid", "symbol":"none"})
	for value in cards: Ui.style_button(cards[value], false, selected_value == value)
