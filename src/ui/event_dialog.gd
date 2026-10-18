extends ColorRect
const Loc = preload("res://src/localization/text.gd")
## Owns the event's layout and entrance; decisions remain in the controller.
const Hud = preload("res://src/ui/ui_theme.gd")
const EventText = preload("res://src/ui/event_text.gd")
const ContextPanel = preload("res://src/ui/context_panel.gd")
const EventPainting = preload("res://src/ui/event_painting.gd")
const Events = preload("res://src/game/event_catalog.gd")
var make_button: Callable
var panel
var dim_tween: Tween
var entrance_revision := 0

func _init(button_factory: Callable) -> void:
	make_button = button_factory

func _ready() -> void:
	material = preload("res://src/ui/modal_shade.gd").create_material()
	color = Color(0.03, 0.06, 0.08, 0.78)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = ContextPanel.new()
	panel.add_theme_stylebox_override("panel", Hud.style(Color(0.09, 0.14, 0.16, 0.96), 8, true))
	add_child(panel)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -240
	panel.offset_right = 240
	close_dialog()

func present(definition: Dictionary, choose: Callable) -> void:
	entrance_revision += 1
	panel.close()
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	var title := wrapped_label(definition["title"], Vector2(28, 20), 23, Color("eed3a1"))
	title.name = "EventTitle"
	var story_top: float = title.position.y + title.size.y + 8
	var painting: TextureRect
	var artwork := definition
	if String(artwork.get("painting", "")).is_empty():
		artwork = {} if definition.get("focus_cancel", false) else Events.DEFAULT_PAINTING
	if artwork.has("painting"):
		var texture := load(String(artwork["painting"])) as Texture2D
		if texture != null:
			var caption := Loc.text(artwork.get("painting_title", String(artwork["painting"]).get_file().get_basename().replace("_", " ")))
			if artwork.has("painting_artist"): caption += "\n" + Loc.text(artwork["painting_artist"])
			painting = EventPainting.new(texture, 424.0, caption)
			painting.position = Vector2(28, story_top)
			story_top += painting.size.y + 12
	var story := wrapped_label(definition["text"], Vector2(28, story_top), 15)
	story.name = "EventStory"
	var choice_top := story.position.y + story.size.y + 12
	# Explicit confirmation details (e.g. relocation prices) are not encounter hints.
	if definition.get("focus_cancel", false) and definition.has("hint"):
		var detail := wrapped_label(definition["hint"], Vector2(28, choice_top), 12, Color("9eb2a7"))
		detail.name = "ConfirmationDetail"
		choice_top += detail.size.y + 8
	if painting != null: panel.add_child(painting)
	var choice_y := choice_top
	var cancel_focus: Button
	for index in range(definition["choices"].size()):
		var choice: Array = definition["choices"][index]
		var button: Button = make_button.call(panel, choice[0], Rect2(28, choice_y, 424, 38), choose.bind(index), choice[1], index == 0)
		button.name = "EventChoice%d" % index
		button.add_theme_font_size_override("font_size", 14)
		button.size.y = 38
		button.set_meta("event_outcome", true)
		button.disabled = definition.get("disabled", []).size() > index and definition["disabled"][index]
		EventText.decorate_choice(button)
		choice_y += button.size.y + 6
		if definition.get("focus_cancel", false):
			button.focus_mode = Control.FOCUS_ALL
			if index == definition["choices"].size() - 1: cancel_focus = button
	panel.panel_height = choice_y - 6 + 20
	panel.rest_top = -panel.panel_height / 2.0
	panel.reveal = 0.0
	panel.show()
	show()
	move_to_front()
	if cancel_focus != null: cancel_focus.grab_focus()
	if dim_tween != null and dim_tween.is_valid():
		dim_tween.kill()
	color.a = 0.0
	begin_entrance(entrance_revision)

func begin_entrance(revision: int) -> void:
	# Loading a painting and laying out the larger dialog can take a whole frame.
	# Let that frame finish before creating tweens, so its delta cannot skip the
	# beginning of the entrance. Use the same timing for illustrated and plain events.
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != entrance_revision or not visible: return
	panel.open(true)
	dim_tween = create_tween()
	dim_tween.tween_property(self, "color:a", 0.78, ContextPanel.ENTRANCE_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func wrapped_label(text_value: String, at: Vector2, font_size: int, font_color := Color("ede7d4")) -> RichTextLabel:
	return EventText.label(panel, text_value, at, 424, font_size, font_color)

func close_dialog() -> void:
	entrance_revision += 1
	if dim_tween != null and dim_tween.is_valid():
		dim_tween.kill()
	dim_tween = null
	panel.close()
	hide()
