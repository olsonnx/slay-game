extends Control
signal tooltip_shown

func _make_custom_tooltip(text_value: String) -> Object:
	var content := preload("res://src/ui/compact_tooltip.gd").create(text_value)
	if content != null: tooltip_shown.emit()
	return content
