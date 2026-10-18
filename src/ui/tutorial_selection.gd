extends Panel
## Course selection stays separate from the match and its objective card.
signal selected(category: String)
signal back_requested
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
var category_buttons: Dictionary = {}

func _ready() -> void:
	add_theme_stylebox_override("panel", Ui.style(Color("17252a"),13,true))
	anchor_left = 0.045
	anchor_right = 0.045
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = 0
	offset_right = 480
	offset_top = -260
	offset_bottom = 260
	Ui.label_at(self, Loc.text("Learn by playing"), Vector2(24,22), 28)
	Ui.label_at(self, Loc.text("Three short matches. Start anywhere."), Vector2(24,66), 15, Ui.MUTED)
	var index := 0
	for course in Lessons.categories():
		var y := 108 + index * 108
		var button := preload("res://src/ui/tooltip_button.gd").new()
		button.text = course["title"]
		button.position = Vector2(24,y)
		button.size = Vector2(432,48)
		Ui.style_button(button,index == 0)
		Sound.bind_button(button)
		var category: String = course["id"]
		button.pressed.connect(func(): selected.emit(category))
		add_child(button)
		category_buttons[category] = button
		var caption := Ui.label_at(self,course["description"],Vector2(24,y+54),14,Ui.MUTED)
		caption.size = Vector2(432,42)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.max_lines_visible = 2
		caption.clip_text = true
		caption.tooltip_text = course["description"]
		index += 1
	var back := preload("res://src/ui/tooltip_button.gd").new()
	back.text = Loc.text("Back")
	back.position = Vector2(24,450)
	back.size = Vector2(432,46)
	Ui.style_button(back)
	Sound.bind_button(back)
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)
