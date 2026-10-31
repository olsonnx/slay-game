extends Panel
## Read-only completion marks accompany replayable topic buttons.
signal selected(category: String)
signal back_requested
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
var category_buttons: Dictionary = {}
var completion_checks: Dictionary = {}

func _ready() -> void:
	add_theme_stylebox_override("panel",Ui.style(Color("17252a"),13,true))
	anchor_left = 0.045
	anchor_right = 0.045
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = 0
	offset_right = 480
	offset_top = -250
	offset_bottom = 250
	Ui.label_at(self,Loc.text("Tutorial"),Vector2(24,16),28)
	var index := 0
	for course in Lessons.categories():
		var button := preload("res://src/ui/tooltip_button.gd").new()
		button.position = Vector2(24,72+index*50)
		button.size = Vector2(432,44)
		button.tooltip_text = course.description
		Ui.style_button(button,index == 0)
		Sound.bind_button(button)
		var category: String = course.id
		button.pressed.connect(func(): selected.emit(category))
		add_child(button)
		category_buttons[category] = button
		var check := CheckBox.new()
		check.position = Vector2(14,10)
		check.mouse_filter = Control.MOUSE_FILTER_IGNORE
		check.focus_mode = Control.FOCUS_NONE
		for state in ["normal","hover","pressed","disabled","focus","hover_pressed"]:
			check.add_theme_stylebox_override(state,StyleBoxEmpty.new())
		var ink := "#20332d" if index == 0 else "#94a59b"
		var fill := "#20332d" if index == 0 else "#a9c89a"
		var tick := "#c3d29c" if index == 0 else "#17252a"
		check.add_theme_icon_override("unchecked",Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22"><rect x="2" y="2" width="18" height="18" rx="3" fill="none" stroke="%s" stroke-width="1.5"/></svg>' % ink))
		check.add_theme_icon_override("checked",Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22"><rect x="2" y="2" width="18" height="18" rx="3" fill="%s"/><path d="M6 11l4 4 7-8" fill="none" stroke="%s" stroke-width="2.5"/></svg>' % [fill,tick]))
		check.size = Vector2(24,24)
		button.add_child(check)
		completion_checks[category] = check
		var title := Ui.label_at(button,"%d. %s" % [index+1,course.title],Vector2(48,11),16,Color("20332d") if index == 0 else Ui.TEXT)
		title.size = Vector2(370,24)
		index += 1
	var back := preload("res://src/ui/tooltip_button.gd").new()
	back.text = Loc.text("Back")
	back.position = Vector2(24,86 + index * 50)
	back.size = Vector2(432,40)
	Ui.style_button(back)
	Sound.bind_button(back)
	back.pressed.connect(func(): back_requested.emit())
	add_child(back)
	var height := back.position.y + 64
	offset_top = -height * 0.5
	offset_bottom = height * 0.5
	Gameplay.changed.connect(refresh_completion)
	refresh_completion()

func refresh_completion() -> void:
	for category in completion_checks:
		completion_checks[category].set_pressed_no_signal(Gameplay.completed_tutorials.get(category,false))
