extends RefCounted
## Native tooltip callbacks for the other standard UI controls.
class Choice extends OptionButton:
	func _make_custom_tooltip(text_value: String) -> Object:
		return preload("res://src/ui/compact_tooltip.gd").create(text_value)

class Toggle extends CheckButton:
	func _make_custom_tooltip(text_value: String) -> Object:
		return preload("res://src/ui/compact_tooltip.gd").create(text_value)

class Checkbox extends CheckBox:
	func _make_custom_tooltip(text_value: String) -> Object:
		return preload("res://src/ui/compact_tooltip.gd").create(text_value)

class RangeSlider extends HSlider:
	func _make_custom_tooltip(text_value: String) -> Object:
		return preload("res://src/ui/compact_tooltip.gd").create(text_value)
