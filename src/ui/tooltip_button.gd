extends Button
signal tooltip_shown

func _init() -> void:
	preload("res://src/ui/ui_theme.gd").style_button(self)

func _make_custom_tooltip(text_value: String) -> Object:
	var content := preload("res://src/ui/compact_tooltip.gd").create(text_value, get_meta("event_outcome", false))
	if content != null: tooltip_shown.emit()
	return content
