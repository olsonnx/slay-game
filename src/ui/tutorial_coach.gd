extends Panel
## Read-only objective checklist: state comes from committed game actions.
const Ui = preload("res://src/ui/ui_theme.gd")
const Loc = preload("res://src/localization/text.gd")
var tutor
var progress: Label
var heading: Label
var explanation: Label
var explanation_scroll: ScrollContainer
var rows_scroll: ScrollContainer
var rows: Control
var checks: Array[CheckBox] = []
var retry: Button
var finish: Button
var next_button: Button
var continue_button: Button
var controls_button: Button
var row_signature: Array = []

func _init(controller) -> void:
	tutor = controller

func _ready() -> void:
	add_theme_stylebox_override("panel",Ui.style(Color("17252a"),13,true))
	anchor_left = 1
	anchor_right = 1
	offset_left = -368
	offset_right = -24
	offset_top = 88
	progress = Ui.label_at(self,"",Vector2(16,12),12,Ui.MUTED)
	heading = Ui.label_at(self,"",Vector2(16,34),20)
	explanation_scroll = ScrollContainer.new()
	explanation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(explanation_scroll)
	explanation = Ui.label_at(explanation_scroll,"",Vector2.ZERO,14)
	explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_scroll = ScrollContainer.new()
	rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(rows_scroll)
	rows = Control.new()
	rows_scroll.add_child(rows)
	get_viewport().size_changed.connect(render)
	retry = tutor.game.hud.button_at(self,"Retry exercise",Rect2(16,0,152,34),tutor.restart_lesson)
	retry.add_theme_font_size_override("font_size",14)
	retry.tooltip_text = Loc.text("Restore this exercise's starting board, gold, mana and choices. Earlier exercises stay complete.")
	finish = tutor.game.hud.button_at(self,"Choose topic",Rect2(16,0,152,34),func(): tutor.game.tutorial_exit_requested.emit(),"",true)
	finish.add_theme_font_size_override("font_size",14)
	next_button = tutor.game.hud.button_at(self,"Next topic",Rect2(176,0,152,34),func(): tutor.next_topic(),"",true)
	next_button.add_theme_font_size_override("font_size",14)
	continue_button = tutor.game.hud.button_at(self,"Next exercise",Rect2(176,0,152,34),tutor.continue_lesson,"",true)
	continue_button.add_theme_font_size_override("font_size",14)
	controls_button = tutor.game.hud.button_at(self,"Controls",Rect2(176,0,152,34),tutor.game.toggle_help)
	controls_button.add_theme_font_size_override("font_size",14)

func render() -> void:
	var indices: Array = tutor.exercise_indices()
	var step: Dictionary = tutor.current()
	var title: String = tutor.reading_title()
	if tutor.completed: title = Loc.text("Match won") if tutor.category == "practice" else Loc.text("Topic complete")
	if tutor.failed: title = Loc.text("Your kingdom fell")
	var page_hint: String = " | %d/%d" % [tutor.text_page+1,step.get("substeps",[]).size()+1] if tutor.reading_substeps() and not step.get("substeps",[]).is_empty() else ""
	Ui.fit_text(progress,tutor.course_title+page_hint,312)
	Ui.fit_text(heading,title,312)
	explanation_scroll.position = Vector2(16,heading.position.y+heading.size.y+8)
	var text: String = tutor.reading_text()
	if tutor.completed: text = Loc.text("You have completed this topic. Choose another subject or use what you learned in Your first match. Every topic is available immediately.")
	if tutor.completed and tutor.category == "practice": text = Loc.text("You won the practice match. Try a new island in Quick Play, or return to a topic to practice a particular skill.")
	elif tutor.failed: text = Loc.text("The opponent took your last capital. Retry this exercise to try a different opening. Expand into useful land, keep your armies paid, and reinforce where they can act.")
	Ui.fit_text(explanation,text,294)
	explanation_scroll.size = Vector2(312,minf(146,explanation.get_minimum_size().y))
	explanation_scroll.tooltip_text = text
	rows_scroll.position = Vector2(16,explanation_scroll.position.y+explanation_scroll.size.y+10)
	rows.size.x = 294
	if row_signature != indices:
		row_signature = indices.duplicate()
		rows_scroll.scroll_vertical = 0
		for child in rows.get_children(): child.free()
		checks.clear()
		var checked := Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22"><rect x="2" y="2" width="18" height="18" rx="3" fill="#a9c89a"/><path d="M6 11l4 4 7-8" fill="none" stroke="#17252a" stroke-width="2.5"/></svg>')
		var unchecked := Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22"><rect x="2" y="2" width="18" height="18" rx="3" fill="none" stroke="#94a59b" stroke-width="1.5"/></svg>')
		for number in indices:
			var row := Control.new()
			rows.add_child(row)
			var box := CheckBox.new()
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.focus_mode = Control.FOCUS_NONE
			for state in ["normal","hover","pressed","disabled","focus","hover_pressed"]:
				box.add_theme_stylebox_override(state,StyleBoxEmpty.new())
			box.size = Vector2(24,24)
			box.add_theme_icon_override("checked",checked)
			box.add_theme_icon_override("unchecked",unchecked)
			row.add_child(box)
			checks.append(box)
			var label := Ui.label_at(row,"",Vector2(32,0),14)
			Ui.fit_text(label,tutor.steps[number].task,256)
	var row_y := 0.0
	for slot in range(indices.size()):
		var number: int = indices[slot]
		var done: bool = number < tutor.index or number == tutor.index and (tutor.exercise_done or tutor.completed)
		checks[slot].set_pressed_no_signal(done)
		var label: Label = rows.get_child(slot).get_child(1)
		var caption: String = tutor.steps[number].task
		if number == tutor.index and int(step.get("count",1)) > 1: caption += "  %d/%d" % [tutor.goal_count,int(step.count)]
		Ui.fit_text(label,caption,256)
		label.add_theme_color_override("font_color",Ui.MUTED if done else Ui.ACCENT if number == tutor.index else Ui.TEXT)
		var height := maxf(24,label.get_minimum_size().y)
		rows.get_child(slot).position = Vector2(0,row_y)
		rows.get_child(slot).size = Vector2(294,height)
		checks[slot].position.y = (height-24)/2
		row_y += height+6
	rows.custom_minimum_size = Vector2(294,row_y)
	rows.size = Vector2(294,row_y)
	var available: float = get_viewport().get_visible_rect().size.y-88-90-rows_scroll.position.y-58
	rows_scroll.size = Vector2(312,minf(row_y,maxf(72,available)))
	if not tutor.exercise_done and not tutor.completed:
		var active: int = indices.find(tutor.index)
		if active >= 0: rows_scroll.ensure_control_visible.call_deferred(rows.get_child(active))
	var footer: float = rows_scroll.position.y+rows_scroll.size.y+8
	for button in [retry,finish,next_button,continue_button,controls_button]: button.position.y = footer
	size = Vector2(344,footer+50)
	retry.visible = not tutor.completed
	retry.disabled = tutor.game.busy or tutor.game.closing or tutor.game.view.level_transitioning
	finish.visible = tutor.completed
	next_button.visible = tutor.completed and tutor.category != tutor.Lessons.IDS.back() and not tutor.custom
	continue_button.visible = not tutor.completed and not tutor.failed and (tutor.reading_substeps() or tutor.exercise_done or tutor.awaiting_confirmation or step.kind == "continue")
	continue_button.text = Loc.text("Next exercise") if tutor.exercise_done else Loc.text("Continue")
	continue_button.disabled = retry.disabled
	controls_button.visible = not tutor.completed and not continue_button.visible
