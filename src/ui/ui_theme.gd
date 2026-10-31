extends RefCounted
## Shared visual primitives, independent of any screen or controller.
const TEXT := Color("ede7d4")
const Loc = preload("res://src/localization/text.gd")
const MUTED := Color("9eb2a7")
const SURFACE := Color("283b3e")
const ACCENT := Color("c8d3a1")
const BUTTON_STATES := ["normal", "hover", "pressed", "hover_pressed", "disabled"]

static func control_style(color: Color, padding := Vector2(12,6), radius := 9) -> StyleBoxFlat:
	var box := style(color,radius)
	box.content_margin_left = padding.x
	box.content_margin_right = padding.x
	box.content_margin_top = padding.y
	box.content_margin_bottom = padding.y
	return box

static func button_styles(primary := false, selected := false, compact := false) -> Dictionary:
	var base := ACCENT if primary else SURFACE
	var padding := Vector2(4,4) if compact else Vector2(12,6)
	var pressed := Color("3c5654") if selected else base.darkened(0.14)
	return {"normal":control_style(base,padding), "hover":control_style(base.lightened(0.10),padding),
		"pressed":control_style(pressed,padding), "hover_pressed":control_style(pressed.lightened(0.08),padding),
		"disabled":control_style(base.darkened(0.16),padding)}

static func focus_style(padding := Vector2(12,6)) -> StyleBoxFlat:
	var box := control_style(Color(0,0,0,0),padding)
	box.set_border_width_all(1)
	box.border_color = Color("a3baab")
	return box

static func button_foreground(button: Button, color: Color) -> void:
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state,color)
	button.add_theme_color_override("font_disabled_color",color.lerp(SURFACE,0.50))
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		button.add_theme_color_override(state,Color.WHITE)
	button.add_theme_color_override("icon_disabled_color",Color(1,1,1,0.45))

static func style_button(button: Button, primary := false, selected := false, compact := false) -> void:
	var styles := button_styles(primary,selected,compact)
	for state in BUTTON_STATES: button.add_theme_stylebox_override(state,styles[state])
	button.add_theme_stylebox_override("focus",focus_style(Vector2(4,4) if compact else Vector2(12,6)))
	button_foreground(button,Color("20332d") if primary else TEXT)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_constant_override("outline_size",0)
	button.add_theme_constant_override("h_separation",8)

static func svg_texture(source: String) -> Texture2D:
	var image := Image.new()
	image.load_svg_from_string(source)
	return ImageTexture.create_from_image(image)

static func create_theme() -> Theme:
	var theme := Theme.new()
	var tree = Engine.get_main_loop()
	if tree is SceneTree and tree.root.has_node("Languages"):
		var font = tree.root.get_node("Languages").active_font
		if font != null: theme.default_font = font
	theme.default_font_size = 14
	theme.set_color("font_color","Label",TEXT)
	theme.set_color("default_color","RichTextLabel",TEXT)
	var styles := button_styles()
	for kind in ["Button","OptionButton"]:
		for state in BUTTON_STATES: theme.set_stylebox(state,kind,styles[state])
		theme.set_stylebox("focus",kind,focus_style())
		for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
			theme.set_color(state,kind,TEXT)
		theme.set_color("font_disabled_color",kind,Color("84988e"))
		theme.set_constant("outline_size",kind,0)
		theme.set_constant("h_separation",kind,8)
		theme.set_color("icon_disabled_color",kind,Color(1,1,1,0.45))
	for state in ["normal","read_only"]:
		var box := control_style(Color("1c2d32") if state == "normal" else Color("203136"))
		box.set_border_width_all(1)
		box.border_color = Color("3b5050")
		theme.set_stylebox(state,"LineEdit",box)
	theme.set_stylebox("focus","LineEdit",focus_style())
	theme.set_color("font_color","LineEdit",TEXT)
	theme.set_color("font_uneditable_color","LineEdit",MUTED)
	theme.set_color("font_placeholder_color","LineEdit",Color("84988e"))
	theme.set_color("caret_color","LineEdit",ACCENT)
	theme.set_color("selection_color","LineEdit",Color("45635d"))
	theme.set_constant("outline_size","LineEdit",0)
	for state in ["normal","read_only"]: theme.set_stylebox(state,"TextEdit",theme.get_stylebox(state,"LineEdit"))
	theme.set_stylebox("focus","TextEdit",focus_style())
	theme.set_color("font_color","TextEdit",TEXT)
	theme.set_color("font_readonly_color","TextEdit",MUTED)
	theme.set_color("caret_color","TextEdit",ACCENT)
	theme.set_color("selection_color","TextEdit",Color("45635d"))
	for state in BUTTON_STATES:
		theme.set_stylebox(state,"CheckButton",control_style(Color(0,0,0,0),Vector2(0,6)))
	theme.set_stylebox("focus","CheckButton",focus_style(Vector2(0,6)))
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
		theme.set_color(state,"CheckButton",TEXT)
	theme.set_color("font_disabled_color","CheckButton",Color("84988e"))
	theme.set_constant("h_separation","CheckButton",12)
	for checked in [true,false]:
		for disabled in [true,false]:
			var track := "#677c62" if disabled and checked else "#c8d3a1" if checked else "#30474a"
			var icon := svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="34" height="20"><rect x="1" y="1" width="32" height="18" rx="9" fill="%s"/><circle cx="%d" cy="10" r="6" fill="%s"/></svg>' % [track,24 if checked else 10,"#80968a" if disabled else "#ede7d4"])
			var key := ("checked" if checked else "unchecked") + ("_disabled" if disabled else "")
			theme.set_icon(key,"CheckButton",icon)
	for state in BUTTON_STATES:
		theme.set_stylebox(state,"CheckBox",control_style(Color(0,0,0,0),Vector2(0,6)))
	theme.set_stylebox("focus","CheckBox",focus_style(Vector2(0,6)))
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]: theme.set_color(state,"CheckBox",TEXT)
	theme.set_color("font_disabled_color","CheckBox",MUTED)
	theme.set_constant("h_separation","CheckBox",10)
	for checked in [true,false]:
		for disabled in [true,false]:
			var fill := "#677c62" if disabled and checked else "#c8d3a1" if checked else "#283b3e"
			var mark := '<path d="m6 10 3 3 5-6" fill="none" stroke="#20332d" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' if checked else ""
			var icon := svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect x="2" y="2" width="16" height="16" rx="4" fill="%s" stroke="#52736d"/>%s</svg>' % [fill,mark])
			theme.set_icon(("checked" if checked else "unchecked")+("_disabled" if disabled else ""),"CheckBox",icon)
	for state in ["tab_selected","tab_unselected","tab_hovered","tab_disabled"]:
		var color := Color("3c5654") if state == "tab_selected" else SURFACE.lightened(0.07) if state == "tab_hovered" else SURFACE
		for kind in ["TabBar","TabContainer"]: theme.set_stylebox(state,kind,control_style(color))
	for kind in ["TabBar","TabContainer"]:
		for state in ["font_selected_color","font_hovered_color","font_unselected_color"]: theme.set_color(state,kind,TEXT)
		theme.set_color("font_disabled_color",kind,MUTED)
		theme.set_stylebox("tab_focus",kind,focus_style())
	theme.set_stylebox("panel","TabContainer",control_style(Color("17252a"),Vector2(12,12),9))
	theme.set_stylebox("panel","PopupMenu",style(Color("17252a"),9,true))
	theme.set_stylebox("hover","PopupMenu",control_style(Color("3c5654"),Vector2(8,4),6))
	theme.set_color("font_color","PopupMenu",TEXT)
	theme.set_color("font_hover_color","PopupMenu",TEXT)
	theme.set_color("font_disabled_color","PopupMenu",MUTED)
	theme.set_constant("v_separation","PopupMenu",6)
	for kind in ["Tree","ItemList"]:
		theme.set_stylebox("panel",kind,control_style(Color("1c2d32")))
		for state in ["selected","selected_focus"]:
			theme.set_stylebox(state,kind,control_style(Color("3c5654"),Vector2(8,4),6))
		theme.set_stylebox("focus",kind,focus_style())
		theme.set_color("font_color",kind,TEXT)
		theme.set_color("font_selected_color",kind,TEXT)
	for kind in ["HScrollBar","VScrollBar"]:
		theme.set_stylebox("scroll",kind,control_style(Color("1c2d32"),Vector2(4,4),4))
		for state in ["grabber","grabber_highlight","grabber_pressed"]:
			theme.set_stylebox(state,kind,control_style(Color("52736d") if state == "grabber" else Color("759286"),Vector2(4,4),4))
	theme.set_stylebox("panel","PopupPanel",style(Color("17252a"),12,true))
	theme.set_stylebox("panel","AcceptDialog",style(Color("17252a"),12,true))
	# Embedded file/authoring windows need their own chrome and content theme.
	var window_frame := style(Color("17252a"),13,true)
	window_frame.expand_margin_top = 36
	window_frame.expand_margin_left = 8
	window_frame.expand_margin_right = 8
	window_frame.expand_margin_bottom = 8
	theme.set_stylebox("embedded_border","Window",window_frame)
	theme.set_color("title_color","Window",TEXT)
	theme.set_font_size("title_font_size","Window",18)
	theme.set_constant("title_height","Window",36)
	theme.set_stylebox("panel","TooltipPanel",style(Color("17252a"),8,true))
	theme.set_color("font_color","TooltipLabel",TEXT)
	theme.set_font_size("font_size","TooltipLabel",14)
	for state in ["slider","grabber_area","grabber_area_highlight"]:
		theme.set_stylebox(state,"HSlider",control_style(Color("30474a") if state == "slider" else Color("8fae92"),Vector2(0,2),3))
	for state in ["grabber","grabber_highlight","grabber_disabled"]:
		var color := "#8a9d91" if state == "grabber_disabled" else "#e0e8ca" if state == "grabber_highlight" else "#c8d3a1"
		theme.set_icon(state,"HSlider",svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14"><circle cx="7" cy="7" r="6" fill="%s"/></svg>' % color))
	return theme

static func style(color: Color, radius := 12, border := false) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(radius)
	if border:
		result.set_border_width_all(1)
		result.border_color = Color("52605c")
	result.content_margin_left = 12
	result.content_margin_right = 12
	result.content_margin_top = 8
	result.content_margin_bottom = 8
	return result

static func panel_style() -> StyleBoxFlat:
	return style(Color(0.09, 0.14, 0.16, 0.96), 13, true)

static func panel(parent: Node, rect: Rect2, stop := true) -> Panel:
	var node := Panel.new()
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_STOP if stop else Control.MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", panel_style())
	parent.add_child(node)
	return node

static func label_at(parent: Node, text_value: String, at: Vector2, font_size := 16, color := Color("ede7d4")) -> Label:
	var label := Label.new()
	label.text = Loc.text(text_value)
	label.position = at
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

static func fit_text(label: Label, text_value: String, width: float) -> bool:
	text_value = Loc.text(text_value)
	# Label performs the same word wrapping used when drawing. Cache the inputs
	# so stationary hover updates do not reshape text or resize controls.
	var signature := [text_value, width, label.get_theme_font("font"), label.get_theme_font_size("font_size"), label.get_theme_constant("line_spacing")]
	if label.get_meta(&"fit_signature", []) == signature:
		return false
	label.set_meta(&"fit_signature", signature)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text_value
	# Discard the previous unwrapped minimum before assigning a narrow width.
	# Otherwise Control can clamp it to the old full-line width for one frame.
	label.get_minimum_size()
	label.size.x = width
	label.size.y = label.get_minimum_size().y
	return true

static func fit_text_panel(box: Panel, label: Label, text_value: String, padding: Vector2) -> void:
	if fit_text(label, text_value, box.size.x - padding.x * 2):
		label.position = padding
		box.size.y = label.size.y + padding.y * 2

static func keep_on_screen(box: Control, point: Vector2, screen: Vector2, margin := 12.0) -> void:
	box.position = Vector2(clampf(point.x, margin, maxf(margin, screen.x - box.size.x - margin)), clampf(point.y, margin, maxf(margin, screen.y - box.size.y - margin)))

static func place_close_button(button: Button, inset := 15.0) -> void:
	# Normal button padding can enlarge the requested rectangle. Give the
	# close glyph compact margins so its 32 px square remains a square.
	button.name = "Close"
	style_button(button,false,false,true)
	button.add_theme_font_size_override("font_size", 16)
	for state in BUTTON_STATES + ["focus"]:
		var box := button.get_theme_stylebox(state).duplicate() as StyleBox
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			box.set_content_margin(side, 4)
		button.add_theme_stylebox_override(state, box)
	button.anchor_left = 1
	button.anchor_right = 1
	button.offset_left = -inset - 32
	button.offset_right = -inset
	button.offset_top = inset
	button.offset_bottom = inset + 32

