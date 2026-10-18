extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Shared compact, measured tooltips for map objects and native UI hovers.
const EventText = preload("res://src/ui/event_text.gd")
const POSITIVE = EventText.POSITIVE
const NEGATIVE = EventText.NEGATIVE
const MANA = EventText.MANA
const GOLD = EventText.GOLD

static func rich_text(text_value: String, heading := true, event_outcome := false) -> String:
	if event_outcome: return EventText.rich_text(text_value).replace("\n\n", "\n[font_size=6]\n[/font_size]")
	var number := RegEx.new()
	number.compile("[+−-]?\\d+(?:[–-]\\d+)?(?:\\s*/\\s*\\d+)?(?:\\s*(?:G|gold|mana))?")
	var lines := PackedStringArray()
	for line in text_value.split("\n"):
		var result := ""
		var offset := 0
		for found in number.search_all(line):
			result += line.substr(offset, found.get_start() - offset)
			var value: String = found.get_string()
			var colour := MANA if line.to_lower().contains("mana") else NEGATIVE if value.begins_with("−") or value.begins_with("-") else POSITIVE if value.begins_with("+") else GOLD if value.contains("G") else "ede7d4"
			if not line.to_lower().contains("mana") and value.get_slice(" ", 0).trim_prefix("+").trim_prefix("−").trim_prefix("-").to_int() == 0:
				colour = "b5c6bd"
			result += "[color=#%s]%s[/color]" % [colour, value]
			offset = found.get_end()
		result += line.substr(offset)
		lines.append(Loc.text("[b]%s[/b]") % result if lines.is_empty() and heading else result)
	return EventText.mark_units("\n".join(lines)).replace("\n\n", "\n[font_size=6]\n[/font_size]")

static func make_label() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("normal_font_size", 13)
	label.add_theme_font_size_override("bold_font_size", 14)
	label.add_theme_color_override("default_color", Color("ede7d4"))
	return label

static func outcome_layout(text_value: String, font: Font, bold_font: Font, font_size: int, width: float) -> Dictionary:
	# Shape the same mixed-font runs as the label. Measuring a whole line in bold
	# reserves space for glyphs which never appear, especially around short effects.
	var units := RegEx.new()
	units.compile("(?i)" + EventText.unit_pattern())
	var measured := Vector2.ZERO
	var lines := PackedStringArray()
	for line in text_value.split("\n"):
		var paragraph := TextParagraph.new()
		paragraph.width = width
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE | TextServer.BREAK_TRIM_START_EDGE_SPACES | TextServer.BREAK_TRIM_END_EDGE_SPACES
		var offset := 0
		for found in units.search_all(line):
			paragraph.add_string(line.substr(offset, found.get_start() - offset), font, font_size)
			paragraph.add_string(found.get_string(), bold_font, font_size)
			offset = found.get_end()
		paragraph.add_string(line.substr(offset), font, font_size)
		for index in range(paragraph.get_line_count()):
			measured.x = maxf(measured.x, paragraph.get_line_size(index).x)
			var span := paragraph.get_line_range(index)
			lines.append(line.substr(span.x, span.y - span.x).strip_edges())
		if line.is_empty() and paragraph.get_line_count() == 0: lines.append("")
		measured.y += paragraph.get_size().y if not line.is_empty() else font.get_height(font_size)
	return {"size": Vector2(ceilf(measured.x) + 2, ceilf(measured.y) + 2), "text": "\n".join(lines)}

static func fit(box: Control, label: RichTextLabel, text_value: String, padding := Vector2(12, 9)) -> bool:
	text_value = Loc.text(text_value)
	var font := label.get_theme_font("normal_font")
	var font_size := label.get_theme_font_size("normal_font_size")
	var bold_font := label.get_theme_font("bold_font")
	var outcome: bool = label.get_meta("event_outcome", false)
	var title_size := font_size if outcome else label.get_theme_font_size("bold_font_size")
	if outcome:
		label.add_theme_font_size_override("bold_font_size", font_size)
	var signature := [text_value, font, bold_font, font_size, title_size, outcome]
	if label.get_meta(&"fit_signature", []) == signature:
		return false
	label.set_meta(&"fit_signature", signature)
	if outcome:
		var layout := outcome_layout(text_value, font, bold_font, font_size, 280.0)
		var measured: Vector2 = layout["size"]
		# Use the shaped line breaks, so tightening the box cannot wrap a word again.
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.position = padding
		label.custom_minimum_size.x = measured.x
		label.size.x = measured.x
		label.text = rich_text(layout["text"], false, true)
		label.size.y = maxf(label.get_content_height(), measured.y)
		box.size = label.size + padding * 2
		return true
	var emphasized := EventText.has_units(text_value)
	var width := 0.0
	var first := true
	for line in text_value.split("\n"):
		width = maxf(width, (bold_font if first or emphasized else font).get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size if first or emphasized else font_size).x)
		first = false
	width = clampf(ceilf(width) + 2, 96, 280)
	label.position = padding
	label.custom_minimum_size.x = width
	label.size.x = width
	label.text = rich_text(text_value, not outcome, outcome)
	# Native tooltip callbacks run before the popup joins the scene. Its rich
	# label has no shaped content height yet, so measure that case with Font.
	var measured_height := 0.0
	first = true
	for line in text_value.split("\n"):
		var row_font: Font = bold_font if first or emphasized else font
		var row_size: int = title_size if first or emphasized else font_size
		measured_height += row_font.get_multiline_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, width, row_size).y if not line.is_empty() else row_font.get_height(6)
		first = false
	label.size.y = maxf(label.get_content_height(), ceilf(measured_height) + 2)
	box.size = label.size + padding * 2
	return true

static func create(text_value: String, event_outcome := false) -> Control:
	# Godot supplies the native TooltipPanel around custom tooltip content.
	# Returning another styled panel would draw a second box inside it.
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := make_label()
	label.set_meta("event_outcome", event_outcome)
	if event_outcome:
		# Separate effects even when an older language pack still uses semicolons.
		text_value = Loc.text(text_value).replace("; ", "\n").replace(";", "\n").replace(". ", ".\n")
	box.add_child(label)
	fit(box, label, text_value, Vector2.ZERO)
	box.custom_minimum_size = box.size
	return box
