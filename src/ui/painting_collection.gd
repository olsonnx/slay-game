extends Panel
const Loc = preload("res://src/localization/text.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
const Events = preload("res://src/game/event_catalog.gd")
signal back_requested
var album
var catalogue: Array[Dictionary] = []
var cards: Dictionary = {}
var card_state: Array = []
var thumbnails: Dictionary = {}
var gallery: VBoxContainer
var grid: GridContainer
var progress_label: Label
var viewer: VBoxContainer
var picture_scroll: ScrollContainer
var picture: TextureRect
var painting_title: Label
var artist_label: Label
var zoom_label: Label
var previous_button: Button
var next_button: Button
var selected_path := ""
var fit_mode := true
var zoom := 1.0
var lock_texture: Texture2D
var gallery_scroll: ScrollContainer
var collection_tabs
var progress_bar: ProgressBar
var empty_label: Label
var back_button: Button
var viewer_toolbar: HBoxContainer
var viewer_back_button: Button
var header_spacers: Array[Control] = []

func _ready() -> void:
	album = get_tree().root.get_node("PaintingAlbum")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -536
	offset_top = 24
	offset_right = 536
	offset_bottom = -24
	add_theme_stylebox_override("panel", Ui.panel_style())
	lock_texture = Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 24 24"><g fill="none" stroke="#9eb2a7" stroke-width="1.6" stroke-linecap="round"><rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/></g></svg>')
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	gallery = column(margin)
	build_gallery()
	viewer = column(margin)
	build_viewer()
	viewer.hide()
	resized.connect(update_layout)
	get_viewport().size_changed.connect(update_layout)
	picture_scroll.resized.connect(func():
		if fit_mode and picture.texture != null: update_zoom())
	album.changed.connect(func():
		if is_visible_in_tree() and not viewer.visible: open_album())
	visibility_changed.connect(func():
		if not is_visible_in_tree(): close_viewer())

func column(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	parent.add_child(box)
	return box

func text(parent: Node, message: String, font_size: int, color := Color("ede7d4")) -> Label:
	var label := Label.new()
	label.text = Loc.text(message)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func action(parent: Node, title: String, callback: Callable) -> Button:
	var button := preload("res://src/ui/tooltip_button.gd").new()
	button.text = Loc.text(title)
	button.custom_minimum_size = Vector2(82, 40)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Ui.style_button(button)
	Sound.bind_button(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func icon_action(parent: Node, kind: String, hint: String, callback: Callable) -> Button:
	var button := action(parent,"",callback)
	button.custom_minimum_size = Vector2(40,40)
	button.tooltip_text = Loc.text(hint)
	button.accessibility_name = Loc.text(hint)
	Ui.style_button(button,false,false,true)
	if kind == "back": button.icon = preload("res://src/ui/replay_icons.gd").get_icon("back")
	else:
		var path := "m15 6-6 6 6 6" if kind == "previous" else "m9 6 6 6-6 6"
		button.icon = Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><path d="%s" fill="none" stroke="#ede7d4" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>' % path)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return button

func toolbar_clearance(header: HBoxContainer) -> void:
	var space := Control.new()
	header.add_child(space)
	header_spacers.append(space)

func build_gallery() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	gallery.add_child(header)
	back_button = icon_action(header,"back","Back to main menu",func(): back_requested.emit())
	var titles := column(header)
	titles.add_theme_constant_override("separation",4)
	text(titles, "Collection", 28)
	var progress := column(header)
	progress.size_flags_horizontal = Control.SIZE_SHRINK_END
	progress.custom_minimum_size.x = 216
	progress.add_theme_constant_override("separation",10)
	progress_label = text(progress, "", 13, Ui.MUTED)
	progress_label.clip_text = true
	progress_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 5
	progress_bar.show_percentage = false
	progress_bar.add_theme_stylebox_override("background",Ui.control_style(Ui.SURFACE,Vector2.ZERO,3))
	progress_bar.add_theme_stylebox_override("fill",Ui.control_style(Ui.ACCENT,Vector2.ZERO,3))
	progress.add_child(progress_bar)
	toolbar_clearance(header)
	collection_tabs = preload("res://src/ui/options_tabs.gd").new()
	collection_tabs.custom_minimum_size = Vector2(300,36)
	collection_tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	collection_tabs.add_tab("All paintings")
	collection_tabs.add_tab("Collected")
	collection_tabs.tab_changed.connect(func(_index): refresh_cards(); Sound.play(&"ui_click"))
	gallery.add_child(collection_tabs)
	gallery_scroll = ScrollContainer.new()
	gallery_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gallery_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gallery.add_child(gallery_scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	gallery_scroll.add_child(grid)
	empty_label = text(gallery,"No paintings collected yet.",16,Ui.MUTED)
	empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_label.hide()

func build_viewer() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	viewer.add_child(header)
	viewer_back_button = icon_action(header,"back","Back to album",close_viewer)
	var titles := column(header)
	titles.add_theme_constant_override("separation",4)
	painting_title = text(titles, "", 24)
	painting_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	painting_title.max_lines_visible = 2
	painting_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	artist_label = text(titles, "", 14, Ui.MUTED)
	artist_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toolbar_clearance(header)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel",Ui.control_style(Color("111e22"),Vector2(12,12),9))
	viewer.add_child(frame)
	picture_scroll = ScrollContainer.new()
	picture_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(picture_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture_scroll.add_child(center)
	picture = TextureRect.new()
	picture.name = "OriginalPainting"
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(picture)
	var toolbar := HBoxContainer.new()
	viewer_toolbar = toolbar
	toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	toolbar.add_theme_constant_override("separation", 12)
	viewer.add_child(toolbar)
	previous_button = icon_action(toolbar,"previous","Previous painting",func(): navigate(-1))
	var left_space := Control.new()
	left_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(left_space)
	action(toolbar, "Fit", fit_picture)
	action(toolbar, "100%", func(): set_zoom(1.0))
	var zoom_out := action(toolbar, "−", func(): set_zoom(zoom / 1.25))
	zoom_out.custom_minimum_size.x = 40
	zoom_out.tooltip_text = Loc.text("Zoom out")
	zoom_label = text(toolbar, "100%", 15, Color("adbdaf"))
	zoom_label.custom_minimum_size.x = 64
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var zoom_in := action(toolbar, "+", func(): set_zoom(zoom * 1.25))
	zoom_in.custom_minimum_size.x = 40
	zoom_in.tooltip_text = Loc.text("Zoom in")
	var right_space := Control.new()
	right_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(right_space)
	next_button = icon_action(toolbar,"next","Next painting",func(): navigate(1))

func open_album() -> void:
	close_viewer()
	catalogue = album.entries()
	var collected := 0
	for entry in catalogue: collected += int(album.is_collected(entry.path))
	progress_label.text = Loc.text("%d / %d paintings collected") % [collected, catalogue.size()]
	progress_bar.max_value = maxi(1,catalogue.size())
	progress_bar.value = collected
	if album.dirty: progress_label.text += "  ·  " + Loc.text("Progress could not be saved.")
	progress_label.tooltip_text = progress_label.text
	refresh_cards()

func needs_preparation() -> bool:
	for entry in album.entries():
		if album.is_collected(entry.path) and not thumbnails.has(entry.path): return true
	return false

func prepare_thumbnails(report: Callable = Callable()) -> void:
	var entries: Array = album.entries().filter(func(entry): return album.is_collected(entry.path) and not thumbnails.has(entry.path))
	var prepared := 0
	for entry in entries:
		thumbnail(entry.path)
		prepared += 1
		if report.is_valid(): report.call(float(prepared)/entries.size())
		await get_tree().process_frame

func refresh_cards() -> void:
	var state: Array = [collection_tabs.current_tab, TranslationServer.get_locale(), catalogue.duplicate(true)]
	for entry in catalogue: state.append(album.is_collected(entry.path))
	if state == card_state:
		update_layout()
		return
	card_state = state
	for child in grid.get_children(): child.free()
	cards.clear()
	for index in range(catalogue.size()):
		if collection_tabs.current_tab == 1 and not album.is_collected(catalogue[index].path): continue
		build_card(catalogue[index],index)
	var empty := cards.is_empty()
	gallery_scroll.visible = not empty
	empty_label.visible = empty
	update_layout()

func build_card(entry: Dictionary, index: int) -> void:
	var unlocked: bool = album.is_collected(entry.path)
	var button := Button.new()
	button.custom_minimum_size = Vector2(220, 276)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.disabled = not unlocked
	button.accessibility_name = Loc.text(entry.title) if unlocked else Loc.text("Undiscovered painting")
	button.tooltip_text = Loc.text(entry.title)+"\n"+Loc.text(entry.artist) if unlocked else Loc.text("Find it during an event.")
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_ARROW
	Ui.style_button(button)
	for state in Ui.BUTTON_STATES:
		var surface := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		surface.bg_color = Color("1c2d32") if state in ["normal","disabled"] else Ui.SURFACE if state == "hover" else Color("30474a")
		button.add_theme_stylebox_override(state,surface)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_ARROW
	Sound.bind_button(button)
	button.pressed.connect(open_painting.bind(entry.path))
	grid.add_child(button)
	cards[entry.path] = button
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 12)
	button.add_child(margin)
	var content := column(margin)
	content.add_theme_constant_override("separation", 8)
	var caption := HBoxContainer.new()
	content.add_child(caption)
	var number := text(caption,"%02d" % [index+1],12,Ui.MUTED)
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text(caption,"Collected" if unlocked else "Locked",12,Ui.ACCENT if unlocked else Ui.MUTED)
	var frame := PanelContainer.new()
	frame.custom_minimum_size.y = 144
	frame.add_theme_stylebox_override("panel", Ui.style(Color("111e22"), 6))
	content.add_child(frame)
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview.texture = thumbnail(entry.path) if unlocked else lock_texture
	if unlocked: frame.add_child(preview)
	else:
		var center := CenterContainer.new()
		frame.add_child(center)
		preview.custom_minimum_size = Vector2(32,32)
		center.add_child(preview)
	var title := text(content, entry.title if unlocked else "Undiscovered painting", 15,Ui.TEXT if unlocked else Ui.MUTED)
	title.custom_minimum_size.y = 44
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var artist := text(content, entry.artist if unlocked else "Find it during an event.", 13, Color("adbdaf"))
	artist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	artist.max_lines_visible = 1
	artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for child in button.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func thumbnail(path: String) -> Texture2D:
	if thumbnails.has(path): return thumbnails[path]
	var prepared_path := Events.gallery_thumbnail_path(path)
	if prepared_path != "":
		var prepared := Events.painting_texture(prepared_path)
		if prepared != null:
			thumbnails[path] = prepared
			return prepared
	var source := Events.painting_texture(path)
	if source == null: return null
	var image := source.get_image()
	if image == null or image.is_empty(): return null
	if image.is_compressed() and image.decompress() != OK: return null
	var scale := minf(1.0, 512.0 / maxf(image.get_width(), image.get_height()))
	image.resize(maxi(1, roundi(image.get_width() * scale)), maxi(1, roundi(image.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	thumbnails[path] = ImageTexture.create_from_image(image)
	return thumbnails[path]

func update_layout() -> void:
	var available: float = get_viewport_rect().size.x
	var width := minf(1120,maxf(280,available-48))
	offset_left = -width/2.0
	offset_right = width/2.0
	if grid != null: grid.columns = maxi(1, mini(mini(4, maxi(1, cards.size())), floori((width - 48) / 236.0)))
	var rows := maxi(1,ceili(float(cards.size())/maxi(1,grid.columns))) if grid != null else 1
	var height := get_viewport_rect().size.y-48
	var top := 24.0
	if viewer == null or not viewer.visible:
		height = minf(get_viewport_rect().size.y-104,168+rows*276+(rows-1)*16)
		top = maxf(80,(get_viewport_rect().size.y-height)/2.0)
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_top = top-get_viewport_rect().size.y/2.0
	offset_bottom = offset_top+height
	# Reserve the global music control's row only where the header can reach it.
	var near_toolbar := top+24 < 80
	var clearance := maxf(0,(available+width)/2.0-24-(available-90)) if near_toolbar else 0.0
	for space in header_spacers: space.custom_minimum_size.x = clearance
	if viewer != null and viewer.visible and fit_mode: update_zoom()

func open_painting(path: String) -> void:
	if not album.is_collected(path): return
	var found := catalogue.filter(func(entry): return entry.path == path)
	if found.is_empty(): return
	var source := Events.painting_texture(path)
	if source == null: return
	selected_path = path
	picture.texture = source
	# This is the original texture, with no event painting shader or tint.
	painting_title.text = Loc.text(found[0].title)
	artist_label.text = Loc.text(found[0].artist)
	gallery.hide()
	viewer.show()
	viewer_back_button.grab_focus()
	previous_button.disabled = unlocked_paths().size() < 2
	next_button.disabled = previous_button.disabled
	fit_mode = true
	update_layout()
	call_deferred("update_zoom")

func unlocked_paths() -> Array:
	return catalogue.filter(func(entry): return album.is_collected(entry.path)).map(func(entry): return entry.path)

func navigate(direction: int) -> void:
	var paths := unlocked_paths()
	if paths.is_empty(): return
	open_painting(paths[posmod(paths.find(selected_path) + direction, paths.size())])

func fit_picture() -> void:
	fit_mode = true
	update_zoom()

func set_zoom(value: float) -> void:
	fit_mode = false
	zoom = clampf(value, 0.05, 4.0)
	update_zoom()

func update_zoom() -> void:
	if picture == null or picture.texture == null: return
	var native_size := picture.texture.get_size()
	if fit_mode:
		var available := picture_scroll.size - Vector2(20, 20)
		zoom = minf(1.0, minf(maxf(1, available.x) / native_size.x, maxf(1, available.y) / native_size.y))
	picture.custom_minimum_size = native_size * zoom
	picture.size = picture.custom_minimum_size
	zoom_label.text = "%d%%" % roundi(zoom * 100)
	if fit_mode:
		picture_scroll.scroll_horizontal = 0
		picture_scroll.scroll_vertical = 0

func close_viewer() -> void:
	if viewer == null: return
	var previous := selected_path
	viewer.hide()
	picture.texture = null
	picture.custom_minimum_size = Vector2.ZERO
	selected_path = ""
	gallery.show()
	update_layout()
	if is_visible_in_tree() and cards.has(previous) and not cards[previous].disabled: cards[previous].grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not viewer.visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode in [KEY_LEFT, KEY_RIGHT]:
		navigate(-1 if event.keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
