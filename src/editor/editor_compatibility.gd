extends Node3D
## Compatibility for tools inspecting editor controls. New code uses the view.
const EditorView = preload("res://src/editor/editor_view.gd")
var ui: EditorView = EditorView.new()

func _init() -> void:
	add_child(ui)

var ui_root:
	get: return ui.ui_root
	set(value): ui.ui_root = value
var panel:
	get: return ui.panel
	set(value): ui.panel = value
var tool_panel:
	get: return ui.tool_panel
	set(value): ui.tool_panel = value
var tool_group:
	get: return ui.tool_group
	set(value): ui.tool_group = value
var tool_buttons:
	get: return ui.tool_buttons
	set(value): ui.tool_buttons = value
var settings_shade:
	get: return ui.settings_shade
	set(value): ui.settings_shade = value
var help_panel:
	get: return ui.help_panel
	set(value): ui.help_panel = value
var view_button:
	get: return ui.view_button
	set(value): ui.view_button = value
var brush_label:
	get: return ui.brush_label
	set(value): ui.brush_label = value
var heatmap_button:
	get: return ui.heatmap_button
	set(value): ui.heatmap_button = value
var heatmap_legend:
	get: return ui.heatmap_legend
	set(value): ui.heatmap_legend = value
var heatmap_range_label:
	get: return ui.heatmap_range_label
	set(value): ui.heatmap_range_label = value
var heatmap_gradient:
	get: return ui.heatmap_gradient
	set(value): ui.heatmap_gradient = value
var random_toggle:
	get: return ui.random_toggle
	set(value): ui.random_toggle = value
var ui_blockers:
	get: return ui.ui_blockers
	set(value): ui.ui_blockers = value
var category_buttons:
	get: return ui.category_buttons
	set(value): ui.category_buttons = value
var help_text:
	get: return ui.help_text
	set(value): ui.help_text = value
var status:
	get: return ui.status
	set(value): ui.status = value
var name_edit:
	get: return ui.name_edit
	set(value): ui.name_edit = value
var tool_choice:
	get: return ui.tool_choice
	set(value): ui.tool_choice = value
var owner_choice:
	get: return ui.owner_choice
	set(value): ui.owner_choice = value
var value_choice:
	get: return ui.value_choice
	set(value): ui.value_choice = value
var size_choice:
	get: return ui.size_choice
	set(value): ui.size_choice = value
var gold_choice:
	get: return ui.gold_choice
	set(value): ui.gold_choice = value
var undo_button:
	get: return ui.undo_button
	set(value): ui.undo_button = value
var redo_button:
	get: return ui.redo_button
	set(value): ui.redo_button = value
var file_dialog:
	get: return ui.file_dialog
	set(value): ui.file_dialog = value
var confirm:
	get: return ui.confirm
	set(value): ui.confirm = value
