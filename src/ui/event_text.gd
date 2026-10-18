extends RefCounted
## Shared event typography. Catalogues and translations remain plain text.
const Loc = preload("res://src/localization/text.gd")
const POSITIVE := "a5d6a0"
const NEGATIVE := "ed9b91"
const MANA := "8fbfe8"
const GOLD := "e5ca8b"
const MUTED := "b5c6bd"
const NORMAL := "ede7d4"
const ACTIONS := "gain|gains|gained|earn|earns|earned|recruit|recruits|refund|refunds|free|clear|clears|remove|removes|reduce|reduces|reduced|lower|increase|increases|lose|loses|lost|loss|pay|pays|cost|costs|spend|spends|die|dies|death|disband|disbands|seize|seizes"

static func escape(value: String) -> String:
	return value.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")

static func regex_escape(value: String) -> String:
	var result := ""
	for letter in value:
		if letter in "\\.^$|?*+()[]{}": result += "\\"
		result += letter
	return result

static func unit_pattern() -> String:
	var names: Array[String] = []
	for name in ["Scout", "Scouts", "Soldier", "Soldiers", "Knight", "Knights", "unit", "units", "army", "armies", "garrison", "garrisons"]:
		for word in [name, Loc.text(name)]:
			if word != "" and word not in names: names.append(word)
	names.sort_custom(func(a: String, b: String): return a.length() > b.length())
	var escaped: Array[String] = []
	for name in names: escaped.append(regex_escape(name))
	return "(?<![\\p{L}\\p{N}_])(?:%s)(?![\\p{L}\\p{N}_])" % "|".join(escaped)

static func mark_units(value: String) -> String:
	var pattern := RegEx.new()
	pattern.compile("(?i)" + unit_pattern())
	return pattern.sub(value, "[b]$0[/b]", true)

static func has_units(value: String) -> bool:
	var pattern := RegEx.new()
	pattern.compile("(?i)" + unit_pattern())
	return pattern.search(value) != null

static func clause(value: String, position: int) -> Dictionary:
	var start := position
	var end := position
	while start > 0 and value[start - 1] not in ".!?;\n": start -= 1
	while end < value.length() and value[end] not in ".!?;\n": end += 1
	return {"text": value.substr(start, end - start).to_lower(), "offset": position - start}

static func action_color(action: String, context: String) -> String:
	if action in ["reduce", "reduces", "reduced", "lower"]:
		return POSITIVE if context.contains("upkeep") or context.contains("wage") or context.contains("cost") else NEGATIVE
	if action in ["increase", "increases"]:
		return NEGATIVE if context.contains("upkeep") or context.contains("wage") or context.contains("cost") else POSITIVE
	if action in ["remove", "removes"]:
		return POSITIVE if context.contains("tree") or context.contains("grave") else NEGATIVE
	return NEGATIVE if action in ["lose", "loses", "lost", "loss", "pay", "pays", "cost", "costs", "spend", "spends", "die", "dies", "death", "disband", "disbands", "seize", "seizes"] else POSITIVE

static func quantity_color(value: String, context: Dictionary) -> String:
	var lower := value.to_lower()
	if value.begins_with("-") or value.begins_with("−"): return NEGATIVE
	var actions := RegEx.new()
	actions.compile("(?i)\\b(?:" + ACTIONS + ")\\b")
	var previous: RegExMatch
	var following: RegExMatch
	for found in actions.search_all(context["text"]):
		if found.get_start() < context["offset"]: previous = found
		elif following == null: following = found
	var action := previous.get_string() if previous != null else following.get_string() if following != null else ""
	var tone := action_color(action, context["text"]) if action != "" else ""
	if lower.contains("mana") or (tone == "" and context["text"].contains("mana") and not lower.contains("gold") and not value.ends_with("G")): return NEGATIVE if tone == NEGATIVE else MANA
	if lower.trim_prefix("+").replace(" ", "") in ["0", "0g", "0gold", "0%"]: return MUTED
	if tone != "": return tone
	if value.begins_with("+"): return POSITIVE
	return GOLD if lower.contains("gold") or value.ends_with("G") else NORMAL

static func rich_text(value: String) -> String:
	var tokens := RegEx.new()
	tokens.compile("(?i)(?<unit>" + unit_pattern() + ")|(?<quantity>[+−-]?\\d+(?:[–-]\\d+)?(?:\\s*/\\s*\\d+)?(?:\\s*(?:%|gold|mana|G)(?![\\p{L}]))?)|(?<action>\\b(?:" + ACTIONS + ")\\b)|(?<resource>\\b(?:mana|gold)\\b)")
	var result := ""
	var offset := 0
	for found in tokens.search_all(value):
		result += escape(value.substr(offset, found.get_start() - offset))
		var token := escape(found.get_string())
		var context := clause(value, found.get_start())
		if found.get_string("unit") != "":
			result += "[b]%s[/b]" % token
		else:
			var color := quantity_color(found.get_string(), context) if found.get_string("quantity") != "" else action_color(found.get_string().to_lower(), context["text"]) if found.get_string("action") != "" else MANA if found.get_string().to_lower() == "mana" else GOLD
			result += "[color=#%s]%s[/color]" % [color, token]
		offset = found.get_end()
	return result + escape(value.substr(offset))

static func label(parent: Node, plain_text: String, at: Vector2, width: float, font_size: int, color: Color) -> RichTextLabel:
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	rich.fit_content = true
	rich.scroll_active = false
	rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rich.add_theme_font_size_override("normal_font_size", font_size)
	rich.add_theme_font_size_override("bold_font_size", font_size)
	rich.add_theme_color_override("default_color", color)
	parent.add_child(rich)
	rich.position = at
	rich.size.x = width
	rich.text = rich_text(Loc.text(plain_text))
	# Measure bold text conservatively, including before native tooltip layout.
	var bold := rich.get_theme_font("bold_font")
	rich.size.y = maxf(rich.get_content_height(), ceilf(bold.get_multiline_string_size(plain_text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size).y) + 2)
	return rich

static func decorate_choice(button: Button) -> void:
	# Preserve native text for accessibility and shortcuts; a rich overlay adds emphasis.
	var colors := {}
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		colors[state] = button.get_theme_color(state)
		button.add_theme_color_override(state, Color.TRANSPARENT)
	button.clip_text = true
	var rich := label(button, button.text, Vector2(12, 0), button.size.x - 24, 14, colors["font_color"])
	# Button captions retain their state colours; their outcome tooltip carries semantics.
	rich.text = "[center]" + mark_units(escape(button.text)) + "[/center]"
	rich.custom_minimum_size.y = rich.size.y
	button.size.y = maxf(38, rich.size.y + 16)
	rich.position.y = (button.size.y - rich.size.y) / 2
	rich.set_meta("event_choice_caption", true)
	button.draw.connect(func():
		var state := "font_disabled_color" if button.disabled else "font_pressed_color" if button.is_pressed() else "font_hover_color" if button.is_hovered() else "font_color"
		if rich.get_theme_color("default_color") != colors[state]: rich.add_theme_color_override("default_color", colors[state]))
