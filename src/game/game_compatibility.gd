extends Node3D
## Compatibility aliases for existing scenes/tests/probes. Production code uses
## the composed HUD and session directly; no gameplay or presentation logic here.
const GameHud = preload("res://src/ui/game_hud.gd")
var hud = GameHud.new()
var session = preload("res://src/game/session_state.gd").new()

func _init() -> void:
	add_child(hud)

const Loc = GameHud.Loc
const UiTheme = GameHud.UiTheme
const Tooltip = GameHud.Tooltip
const COG_ICON = GameHud.COG_ICON
const VIEW_3D_ICON = GameHud.VIEW_3D_ICON
const VIEW_TOP_ICON = GameHud.VIEW_TOP_ICON
const HEATMAP_ICON = GameHud.HEATMAP_ICON

var ui:
	get: return hud.ui
	set(value): hud.ui = value
var ui_root:
	get: return hud.ui_root
	set(value): hud.ui_root = value
var money_label:
	get: return hud.money_label
	set(value): hud.money_label = value
var income_label:
	get: return hud.income_label
	set(value): hud.income_label = value
var gold_control:
	get: return hud.gold_control
	set(value): hud.gold_control = value
var round_label:
	get: return hud.round_label
	set(value): hud.round_label = value
var level_label:
	get: return hud.level_label
	set(value): hud.level_label = value
var turn_spinner:
	get: return hud.turn_spinner
	set(value): hud.turn_spinner = value
var notice_label:
	get: return hud.notice_label
	set(value): hud.notice_label = value
var toast_panel:
	get: return hud.toast_panel
	set(value): hud.toast_panel = value
var recruit_button:
	get: return hud.recruit_button
	set(value): hud.recruit_button = value
var build_button:
	get: return hud.build_button
	set(value): hud.build_button = value
var spell_button:
	get: return hud.spell_button
	set(value): hud.spell_button = value
var mana_label:
	get: return hud.mana_label
	set(value): hud.mana_label = value
var mana_income_label:
	get: return hud.mana_income_label
	set(value): hud.mana_income_label = value
var mana_control:
	get: return hud.mana_control
	set(value): hud.mana_control = value
var economy_dock:
	get: return hud.economy_dock
	set(value): hud.economy_dock = value
var turn_controls:
	get: return hud.turn_controls
	set(value): hud.turn_controls = value
var end_button:
	get: return hud.end_button
	set(value): hud.end_button = value
var stats_button:
	get: return hud.stats_button
	set(value): hud.stats_button = value
var view_button:
	get: return hud.view_button
	set(value): hud.view_button = value
var heatmap_button:
	get: return hud.heatmap_button
	set(value): hud.heatmap_button = value
var heatmap_legend:
	get: return hud.heatmap_legend
	set(value): hud.heatmap_legend = value
var heatmap_gradient:
	get: return hud.heatmap_gradient
	set(value): hud.heatmap_gradient = value
var heatmap_max_label:
	get: return hud.heatmap_max_label
	set(value): hud.heatmap_max_label = value
var heatmap_low_label:
	get: return hud.heatmap_low_label
	set(value): hud.heatmap_low_label = value
var heatmap_bar:
	get: return hud.heatmap_bar
	set(value): hud.heatmap_bar = value
var view_hold_indicator:
	get: return hud.view_hold_indicator
	set(value): hud.view_hold_indicator = value
var pause_button:
	get: return hud.pause_button
	set(value): hud.pause_button = value
var shop_panel:
	get: return hud.shop_panel
	set(value): hud.shop_panel = value
var shop_title:
	get: return hud.shop_title
	set(value): hud.shop_title = value
var shop_items:
	get: return hud.shop_items
	set(value): hud.shop_items = value
var shop_kind:
	get: return hud.shop_kind
	set(value): hud.shop_kind = value
var stats_shade:
	get: return hud.stats_shade
	set(value): hud.stats_shade = value
var stats_panel:
	get: return hud.stats_panel
	set(value): hud.stats_panel = value
var stats_rows:
	get: return hud.stats_rows
	set(value): hud.stats_rows = value
var kingdom_rows:
	get: return hud.kingdom_rows
	set(value): hud.kingdom_rows = value
var help_panel:
	get: return hud.help_panel
	set(value): hud.help_panel = value
var world_tip:
	get: return hud.world_tip
	set(value): hud.world_tip = value
var tip_label:
	get: return hud.tip_label
	set(value): hud.tip_label = value
var gold_delta_label:
	get: return hud.gold_delta_label
	set(value): hud.gold_delta_label = value
var gold_tween:
	get: return hud.gold_tween
	set(value): hud.gold_tween = value
var previous_gold:
	get: return hud.previous_gold
	set(value): hud.previous_gold = value
var previous_kingdom:
	get: return hud.previous_kingdom
	set(value): hud.previous_kingdom = value
var effect_row:
	get: return hud.effect_row
	set(value): hud.effect_row = value
var selected:
	get: return session.selection.selected
	set(value): session.selection.selected = value
var inspected_unit:
	get: return session.selection.inspected_unit
	set(value): session.selection.inspected_unit = value
var hovered:
	get: return session.selection.hovered
	set(value): session.selection.hovered = value
var active_hex:
	get: return session.selection.active_hex
	set(value): session.selection.active_hex = value
var inspected_hex:
	get: return session.selection.inspected_hex
	set(value): session.selection.inspected_hex = value
var action_mode:
	get: return session.selection.action_mode
	set(value): session.selection.action_mode = value
var recruit_tier:
	get: return session.selection.recruit_tier
	set(value): session.selection.recruit_tier = value
var chosen_spell:
	get: return session.selection.chosen_spell
	set(value): session.selection.chosen_spell = value
var valid_targets:
	get: return session.selection.valid_targets
	set(value): session.selection.valid_targets = value
var preview_path:
	get: return session.selection.preview_path
	set(value): session.selection.preview_path = value
var NAMES: Array:
	get: return session.names
	set(value): session.names = value
var COLORS: Array:
	get: return session.colors
	set(value): session.colors = value
var rules:
	get: return session.rules
	set(value): session.rules = value
var round_number: int:
	get: return session.round_number
	set(value): session.round_number = value
var player_faction: int:
	get: return session.player_faction
	set(value): session.player_faction = value
var active_faction: int:
	get: return session.active_faction
	set(value): session.active_faction = value
var level_number: int:
	get: return session.level_number
	set(value): session.level_number = value
var tutorial:
	get: return session.tutorial
	set(value): session.tutorial = value
var initial_level_data: Dictionary:
	get: return session.initial_level_data
	set(value): session.initial_level_data = value

static func style(color: Color, radius := 12, border := false) -> StyleBoxFlat:
	return GameHud.style(color, radius, border)

static func panel(parent: Node, rect: Rect2, stop := true) -> Panel:
	return GameHud.panel(parent, rect, stop)

static func label_at(parent: Node, text_value: String, at: Vector2, font_size := 16, color := Color("ede7d4")) -> Label:
	return GameHud.label_at(parent, text_value, at, font_size, color)

func button_at(parent: Node, text_value: String, rect: Rect2, callback: Callable, tip := "", primary := false) -> Button:
	return hud.button_at(parent, text_value, rect, callback, tip, primary)

func pin_bottom(control: Control, left: float, top: float, width: float, height: float, right := false) -> void:
	hud.pin_bottom(control, left, top, width, height, right)

func refresh_shortcuts() -> void:
	hud.refresh_shortcuts()

func update_effects(model, faction := 0) -> void:
	hud.update_effects(model, faction)

func configure_rules_ui(modern: bool) -> void:
	hud.configure_rules_ui(modern)

func update_mana(amount: int, forecast: int, capacity: int, regeneration: int = 1) -> void:
	hud.update_mana(amount, forecast, capacity, regeneration)

func reset_gold_feedback() -> void:
	hud.reset_gold_feedback()

func update_gold(amount: int, net: int, capital: Vector2i) -> void:
	hud.update_gold(amount, net, capital)
