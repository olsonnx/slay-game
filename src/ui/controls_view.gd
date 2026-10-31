extends Control
const Loc = preload("res://src/localization/text.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
const NOTE := "Click a binding, then press a key. Escape cancels.\nMenu choices take priority while a menu is open."
var pending := ""
var buttons: Dictionary = {}
var note: Label

func _ready() -> void:
	set_process_input(false)
	note = Ui.label_at(self, "", Vector2.ZERO, 13, Color("c5cdbb"))
	set_note(NOTE)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 58)
	scroll.size = Vector2(432, 266)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	for group in [["Actions", ["recruit", "build", "spells", "view", "heatmap", "develop", "end_turn", "cancel", "speed"]], ["Menu choices", ["choice_1", "choice_2", "choice_3"]], ["Camera", ["pan_up", "pan_left", "pan_down", "pan_right"]]]:
		Ui.label_at(rows, group[0], Vector2.ZERO, 15, Color("eed3a1"))
		for action in group[1]:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			rows.add_child(row)
			var title := Ui.label_at(row, Keys.TITLES[action], Vector2.ZERO, 14)
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			var button := Button.new()
			Ui.style_button(button)
			button.custom_minimum_size = Vector2(120, 36)
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(begin_capture.bind(action))
			Sound.bind_button(button)
			row.add_child(button)
			buttons[action] = button
	Keys.changed.connect(refresh)
	refresh()

func set_note(text_value: String) -> void:
	Ui.fit_text(note, text_value, 432)

func begin_capture(action: String) -> void:
	cancel_capture()
	pending = action
	buttons[action].text = Loc.text("Press a key…")
	set_note(Loc.text("New key for %s.\nPress Escape to cancel.") % Loc.text(Keys.TITLES[action]))
	set_process_input(true)

func cancel_capture() -> void:
	pending = ""
	set_process_input(false)
	if note != null:
		set_note(NOTE)
		refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_capture()
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_capture()

func _input(event: InputEvent) -> void:
	if pending == "" or not event is InputEventKey:
		return
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		cancel_capture()
		return
	var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	var error: String = Keys.set_binding(pending, code)
	if error != "":
		set_note(error + "\n" + Loc.text("Escape cancels."))
	else:
		cancel_capture()

func refresh() -> void:
	for action in buttons:
		buttons[action].text = Loc.text("Press a key…") if pending == action else Keys.key_name(action)
