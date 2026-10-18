extends Control

func _make_custom_tooltip(text_value: String) -> Object:
	return preload("res://src/ui/compact_tooltip.gd").create(text_value)
