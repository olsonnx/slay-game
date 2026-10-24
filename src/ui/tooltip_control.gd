extends Control
signal tooltip_shown

func _make_custom_tooltip(text_value: String) -> Object:
	tooltip_shown.emit()
	return preload("res://src/ui/compact_tooltip.gd").create(text_value)
