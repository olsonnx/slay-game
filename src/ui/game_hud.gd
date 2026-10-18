extends Node3D
const Loc = preload("res://src/localization/text.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Tooltip = preload("res://src/ui/compact_tooltip.gd")
## Layout and reusable UI construction. Game actions live in the controller.

var ui: CanvasLayer
var ui_root: Control
var money_label: Label
var income_label: Label
var gold_control: Control
var round_label: Label
var level_label: Label
var turn_spinner
var notice_label: Label
var toast_panel: Panel
var recruit_button: Button
var build_button: Button
var spell_button: Button
var mana_label: Label
var mana_income_label: Label
var mana_control: Control
var economy_dock: Panel
var turn_controls: Control
var end_button: Button
var stats_button: Button
var view_button: Button
var heatmap_button: Button
var heatmap_legend: Panel
var heatmap_gradient: Gradient
var heatmap_max_label: Label
var heatmap_low_label: Label
var heatmap_bar: TextureRect
var view_hold_indicator
var pause_button: Button
var shop_panel
var shop_title: Label
var shop_items: Control
var shop_kind := ""
var stats_shade: ColorRect
var stats_panel: Panel
var stats_rows: VBoxContainer
var kingdom_rows: VBoxContainer
var help_panel: Panel
var world_tip: Panel
var tip_label: RichTextLabel
var gold_delta_label: Label
var gold_tween: Tween
var previous_gold := -1
var previous_kingdom := Vector2i(999, 999)
var effect_row
const COG_ICON = preload("res://assets/ui/cog.svg")
const VIEW_3D_ICON = preload("res://assets/ui/view_3d.svg")
const VIEW_TOP_ICON = preload("res://assets/ui/view_top.svg")
const HEATMAP_ICON = preload("res://assets/ui/value_heatmap.svg")

static func style(color: Color, radius := 12, border := false) -> StyleBoxFlat:
	return UiTheme.style(color, radius, border)

static func panel(parent: Node, rect: Rect2, stop := true) -> Panel:
	return UiTheme.panel(parent, rect, stop)

static func label_at(parent: Node, text_value: String, at: Vector2, font_size := 16, color := Color("ede7d4")) -> Label:
	return UiTheme.label_at(parent, text_value, at, font_size, color)

func button_at(parent: Node, text_value: String, rect: Rect2, callback: Callable, tip := "", primary := false) -> Button:
	var button := preload("res://src/ui/tooltip_button.gd").new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.tooltip_text = tip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 16)
	UiTheme.style_button(button,primary)
	Sound.bind_button(button, func(): return activation.call(callback))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func pin_bottom(control: Control, left: float, top: float, width: float, height: float, right := false) -> void:
	control.anchor_top = 1
	control.anchor_bottom = 1
	control.anchor_left = 1 if right else 0
	control.anchor_right = control.anchor_left
	control.offset_left = left
	control.offset_right = left + width
	control.offset_top = top
	control.offset_bottom = top + height

signal shortcuts_changed
var activation: Callable

func build_ui(actions: Dictionary, cue: Callable) -> void:
	activation = cue
	ui = CanvasLayer.new()
	add_child(ui)
	ui_root = Control.new()
	ui.add_child(ui_root)
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := UiTheme.create_theme()
	ui_root.theme = theme
	level_label = label_at(ui_root, "Level 1", Vector2(28, 22), 27)
	round_label = label_at(ui_root, Loc.text("FERN  /  TURN 01"), Vector2(30, 60), 12, Color("b5c6bd"))
	for heading in [level_label, round_label]:
		heading.add_theme_constant_override("outline_size", 2)
		heading.add_theme_color_override("font_outline_color", Color(0.035, 0.055, 0.065, 0.8))
	var view_controls := Control.new()
	ui_root.add_child(view_controls)
	view_controls.anchor_left = 1
	view_controls.anchor_right = 1
	view_controls.offset_left = -248
	view_controls.offset_right = -24
	view_controls.offset_top = 24
	view_controls.offset_bottom = 64
	view_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view_button = button_at(view_controls, "", Rect2(0, 0, 50, 40), actions["view_button_activated"])
	view_hold_indicator = preload("res://src/ui/hold_indicator.gd").new()
	view_button.add_child(view_hold_indicator)
	view_hold_indicator.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view_button.button_down.connect(actions["begin_view_press"])
	view_button.button_up.connect(actions["end_view_press"])
	view_button.mouse_exited.connect(actions["cancel_view_press"])
	heatmap_button = button_at(view_controls, "", Rect2(60, 0, 50, 40), actions["toggle_value_heatmap"])
	heatmap_button.icon = HEATMAP_ICON
	heatmap_button.toggle_mode = true
	button_at(view_controls, "?", Rect2(120, 0, 44, 40), actions["toggle_help"], Loc.text("Camera controls and quick help."))
	pause_button = button_at(view_controls, "", Rect2(174, 0, 50, 40), actions["open_pause"], Loc.text("Pause / options. Escape cancels an action first, then pauses."))
	pause_button.icon = COG_ICON
	var dock := panel(ui_root, Rect2(0, 0, 418, 82))
	economy_dock = dock
	pin_bottom(dock, 24, -106, 418, 82)
	gold_control = preload("res://src/ui/tooltip_control.gd").new()
	gold_control.position = Vector2(15, 59)
	gold_control.size = Vector2(190, 52)
	gold_control.mouse_filter = Control.MOUSE_FILTER_STOP
	dock.add_child(gold_control)
	label_at(gold_control, Loc.text("GOLD · NEXT TURN"), Vector2(0, 0), 10, Color("9eb2a7"))
	money_label = label_at(gold_control, "", Vector2(0, 17), 24, Color("eed3a1"))
	income_label = label_at(gold_control, "+6 G", Vector2(88, 17), 24, Color("bed099"))
	money_label.pivot_offset = Vector2(0, 18)
	gold_delta_label = label_at(gold_control, "", Vector2(120, -3), 13)
	gold_delta_label.size = Vector2(70, 18)
	gold_delta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold_delta_label.add_theme_constant_override("outline_size", 3)
	gold_delta_label.add_theme_color_override("font_outline_color", Color("172c33"))
	gold_delta_label.hide()
	recruit_button = button_at(dock, "Recruit", Rect2(172, 16, 110, 50), actions["open_shop"].bind("recruit"), Loc.text("Choose a Scout, Soldier or Knight.\nPlace on your land or upgrade an unmoved unit.\nRecruitment uses that kingdom's gold."))
	build_button = button_at(dock, "Build", Rect2(292, 16, 110, 50), actions["open_shop"].bind("build"), Loc.text("Choose a defensive tower or an income house.\nBuild on a clear empty hex in your kingdom."))
	mana_control = preload("res://src/ui/tooltip_control.gd").new()
	mana_control.position = Vector2(223, 59)
	mana_control.size = Vector2(180, 52)
	mana_control.mouse_filter = Control.MOUSE_FILTER_STOP
	dock.add_child(mana_control)
	label_at(mana_control, Loc.text("MANA · NEXT TURN"), Vector2(0, 0), 10, Color("ada6c3"))
	mana_label = label_at(mana_control, "", Vector2(0, 17), 24, Color("c7b2fa"))
	mana_income_label = label_at(mana_control, "", Vector2(40, 17), 24, Color("a89cc5"))
	mana_control.hide()
	spell_button = button_at(dock, "Spells", Rect2(412, 27, 110, 50), actions["open_shop"].bind("spells"), Loc.text("Spend shared faction mana on a spell."))
	spell_button.hide()
	turn_controls = Control.new()
	ui_root.add_child(turn_controls)
	pin_bottom(turn_controls, -288, -90, 264, 66, true)
	turn_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_button = button_at(turn_controls, "Stats", Rect2(0, 8, 78, 50), actions["toggle_stats"], Loc.text("Open faction statistics and your kingdom finances."))
	end_button = button_at(turn_controls, Loc.text("End turn  →"), Rect2(90, 8, 174, 50), actions["turn_button_activated"], Loc.text("End turn. Hold Ctrl to speed up movement. Shortcut: Space."), true)
	turn_spinner = preload("res://src/ui/turn_spinner.gd").new()
	turn_spinner.position = Vector2(12, 17)
	turn_spinner.size = Vector2(16, 16)
	end_button.add_child(turn_spinner)
	shop_panel = preload("res://src/ui/context_panel.gd").new()
	shop_panel.add_theme_stylebox_override("panel", style(Color(0.09, 0.14, 0.16, 0.96), 13, true))
	ui_root.add_child(shop_panel)
	pin_bottom(shop_panel, 24, -342, 418, 188)
	shop_title = label_at(shop_panel, "Recruit", Vector2(15, 20), 16)
	UiTheme.place_close_button(button_at(shop_panel, "×", Rect2(), actions["cancel_action"], Loc.text("Cancel placement and close this menu. Shortcut: Escape.")))
	shop_items = Control.new()
	shop_items.position = Vector2(15, 62)
	shop_items.size = Vector2(388, 111)
	shop_items.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shop_panel.add_child(shop_items)
	shop_panel.hide()
	stats_shade = ColorRect.new()
	stats_shade.color = Color(0.04, 0.08, 0.10, 0.60)
	ui_root.add_child(stats_shade)
	stats_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats_shade.hide()
	stats_panel = panel(stats_shade, Rect2(-235, -222, 470, 444))
	stats_panel.anchor_left = 0.5
	stats_panel.anchor_right = 0.5
	stats_panel.anchor_top = 0.5
	stats_panel.anchor_bottom = 0.5
	stats_panel.offset_left = -235
	stats_panel.offset_right = 235
	stats_panel.offset_top = -222
	stats_panel.offset_bottom = 222
	label_at(stats_panel, "Island ledger", Vector2(24, 18), 24)
	UiTheme.place_close_button(button_at(stats_panel, "×", Rect2(), actions["toggle_stats"], "Close statistics."), 16)
	label_at(stats_panel, "FACTION", Vector2(25, 68), 12, Color("98b0a7"))
	label_at(stats_panel, "HEXES", Vector2(262, 68), 12, Color("98b0a7"))
	label_at(stats_panel, "KINGDOMS", Vector2(363, 68), 12, Color("98b0a7"))
	stats_rows = VBoxContainer.new()
	var faction_scroll := ScrollContainer.new()
	faction_scroll.position = Vector2(25, 94)
	faction_scroll.size = Vector2(420, 170)
	faction_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stats_panel.add_child(faction_scroll)
	stats_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_rows.add_theme_constant_override("separation", 10)
	faction_scroll.add_child(stats_rows)
	label_at(stats_panel, "Your kingdoms", Vector2(25, 277), 17)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(25, 312)
	scroll.size = Vector2(420, 105)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stats_panel.add_child(scroll)
	kingdom_rows = VBoxContainer.new()
	kingdom_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kingdom_rows.add_theme_constant_override("separation", 10)
	scroll.add_child(kingdom_rows)
	help_panel = panel(ui_root, Rect2(-338, 78, 314, 237))
	help_panel.anchor_left = 1
	help_panel.anchor_right = 1
	help_panel.offset_left = -338
	help_panel.offset_right = -24
	help_panel.offset_top = 78
	help_panel.hide()
	toast_panel = panel(ui_root, Rect2(-234, 24, 468, 59), false)
	toast_panel.anchor_left = 0.5
	toast_panel.anchor_right = 0.5
	toast_panel.offset_left = -234
	toast_panel.offset_right = 234
	toast_panel.offset_top = 24
	toast_panel.offset_bottom = 83
	notice_label = label_at(toast_panel, "", Vector2(14, 8), 14)
	toast_panel.hide()
	world_tip = panel(ui_root, Rect2(0, 0, 278, 88), false)
	tip_label = Tooltip.make_label()
	world_tip.add_child(tip_label)
	world_tip.hide()
	effect_row = preload("res://src/ui/status_effects.gd").new()
	ui_root.add_child(effect_row)
	pin_bottom(effect_row, 454, -84, 180, 48)
	heatmap_legend = panel(ui_root, Rect2(24, 94, 278, 102), false)
	label_at(heatmap_legend, "Province value", Vector2(12, 9), 16)
	var zero := ColorRect.new()
	zero.color = Color.BLACK
	zero.position = Vector2(12, 38)
	zero.size = Vector2(24, 12)
	zero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heatmap_legend.add_child(zero)
	var zero_label := label_at(heatmap_legend, "0", Vector2(12, 52), 13)
	zero_label.size.x = 24
	zero_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heatmap_gradient = Gradient.new()
	var texture := GradientTexture1D.new()
	texture.gradient = heatmap_gradient
	heatmap_bar = TextureRect.new()
	heatmap_bar.texture = texture
	heatmap_bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	heatmap_bar.position = Vector2(46, 38)
	heatmap_bar.size = Vector2(218, 12)
	heatmap_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heatmap_legend.add_child(heatmap_bar)
	heatmap_low_label = label_at(heatmap_legend, "1", Vector2(46, 52), 13)
	heatmap_max_label = label_at(heatmap_legend, "3", Vector2(216, 52), 13)
	heatmap_max_label.size.x = 48
	heatmap_max_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_at(heatmap_legend, Loc.text("Borders show kingdoms"), Vector2(12, 77), 12, Color("b5c6bd"))
	heatmap_legend.hide()
	Keys.changed.connect(refresh_shortcuts)
	refresh_shortcuts()

func refresh_shortcuts() -> void:
	shortcuts_changed.emit()
	heatmap_button.tooltip_text = Loc.text("Province values\nShortcut: %s") % Keys.key_name("heatmap")
	recruit_button.tooltip_text = Loc.text("Recruit on friendly land\nUpgrade unmoved units · uses local gold\nShortcut: %s") % Keys.key_name("recruit")
	build_button.tooltip_text = Loc.text("Build\nTower, house or bridge\nShortcut: %s") % Keys.key_name("build")
	spell_button.tooltip_text = Loc.text("Spells\nUses faction mana\nShortcut: %s") % Keys.key_name("spells")
	shop_panel.get_node("Close").tooltip_text = Loc.text("Cancel placement\nShortcut: %s") % Keys.key_name("cancel")
	for card in shop_items.get_children():
		if card.has_meta("shortcut_action"):
			card.tooltip_text = card.get_meta("base_tooltip") + "\n" + Loc.text("Shortcut: %s") % Keys.key_name(card.get_meta("shortcut_action"))
	for child in help_panel.get_children():
		help_panel.remove_child(child)
		child.queue_free()
	var heading := label_at(help_panel, Loc.text("Explore the island"), Vector2(18, 13), 19)
	UiTheme.fit_text(heading, heading.text, 278)
	var pan_keys := " / ".join([Keys.key_name("pan_up"), Keys.key_name("pan_left"), Keys.key_name("pan_down"), Keys.key_name("pan_right")])
	var menu_keys := " / ".join([Keys.key_name("recruit"), Keys.key_name("build"), Keys.key_name("spells")])
	var choice_keys := " / ".join([Keys.key_name("choice_1"), Keys.key_name("choice_2"), Keys.key_name("choice_3")])
	var row_y := heading.position.y + heading.size.y + 14
	for entry in [["Right-drag", Loc.text("Rotate and tilt")], ["Right-click", "Cancel action"], ["Wheel drag", Loc.text("Pan · scroll to zoom")], [pan_keys, "Pan"], [Keys.key_name("view"), Loc.text("Top-down / 3D")], [Keys.key_name("heatmap"), "Value heatmap"], [Keys.key_name("develop"), Loc.text("Develop inspected province")], ["Hold view", Loc.text("Center and reset")], [menu_keys, Loc.text("Recruit / build / spells")], [choice_keys, Loc.text("Menu choices")], [Keys.key_name("speed"), Loc.text("Hold for faster moves")], ["Hold turn", Loc.text("Speed up opponents")], [Keys.key_name("end_turn"), "End turn"], [Keys.key_name("cancel"), Loc.text("Cancel / pause")]]:
		var key := label_at(help_panel, entry[0], Vector2(18, row_y), 15)
		var action := label_at(help_panel, entry[1], Vector2(124, row_y), 15, Color("c8d4c8"))
		UiTheme.fit_text(key, key.text, 96)
		UiTheme.fit_text(action, action.text, 172)
		row_y += maxf(key.size.y, action.size.y) + 4
	help_panel.size.y = row_y - 4 + 13

func update_effects(model, faction := 0) -> void:
	effect_row.refresh(model, faction)

func configure_rules_ui(modern: bool) -> void:
	spell_button.visible = modern
	mana_control.visible = modern
	mana_label.visible = modern
	gold_control.size.x = 190 if modern else 256
	pin_bottom(economy_dock, 24, -144, 418 if modern else 286, 120)
	recruit_button.position = Vector2(15, 12)
	recruit_button.size = Vector2(124, 38)
	build_button.position = Vector2(147, 12)
	build_button.size = Vector2(124, 38)
	spell_button.position = Vector2(279, 12)
	spell_button.size = Vector2(124, 38)
	pin_bottom(shop_panel, 24, -342, 418, 188)

func update_mana(amount: int, forecast: int, capacity: int, regeneration: int = 1) -> void:
	mana_label.text = Loc.text("%d / %d") % [amount, capacity]
	mana_income_label.text = Loc.text("%+d") % forecast
	mana_label.size.x = mana_label.get_minimum_size().x
	mana_income_label.position.x = mana_label.size.x + 10
	mana_control.tooltip_text = Loc.text("Faction mana %d / %d\nNext turn +%d mana · regen %d\nMana capacity: source +1 · capital / tree +2") % [amount, capacity, forecast, regeneration]

func reset_gold_feedback() -> void:
	if gold_tween != null and gold_tween.is_valid():
		gold_tween.kill()
	previous_gold = -1
	previous_kingdom = Vector2i(999, 999)
	money_label.scale = Vector2.ONE
	money_label.add_theme_color_override("font_color", Color("eed3a1"))
	gold_delta_label.hide()

func update_gold(amount: int, net: int, capital: Vector2i) -> void:
	money_label.text = Loc.text("%d G") % amount
	income_label.text = Loc.text("%+d G") % net
	# Follow the actual text width rather than reserving a fixed amount column.
	money_label.size.x = money_label.get_minimum_size().x
	income_label.position.x = money_label.position.x + money_label.size.x + 10
	var delta := amount - previous_gold
	if previous_gold >= 0 and previous_kingdom == capital and delta != 0:
		if gold_tween != null and gold_tween.is_valid():
			gold_tween.kill()
		var color := Color("bde69c") if delta > 0 else Color("eca18c")
		money_label.scale = Vector2.ONE
		money_label.add_theme_color_override("font_color", color)
		gold_delta_label.text = Loc.text("%+d G") % delta
		gold_delta_label.add_theme_color_override("font_color", color)
		var delta_origin := Vector2(gold_control.size.x - 70, -3)
		gold_delta_label.position = delta_origin
		gold_delta_label.modulate.a = 1
		gold_delta_label.show()
		gold_tween = create_tween().set_parallel(true)
		gold_tween.tween_property(money_label, "scale", Vector2(1.08, 1.08), 0.08)
		gold_tween.tween_property(money_label, "scale", Vector2.ONE, 0.20).set_delay(0.08)
		gold_tween.tween_property(money_label, "theme_override_colors/font_color", Color("eed3a1"), 0.32)
		gold_tween.tween_property(gold_delta_label, "position", delta_origin + Vector2(4, 0), 0.65)
		gold_tween.tween_property(gold_delta_label, "modulate:a", 0.0, 0.65)
	elif previous_kingdom != capital:
		reset_gold_feedback()
	previous_gold = amount
	previous_kingdom = capital

