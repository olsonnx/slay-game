extends Panel
const Loc = preload("res://src/localization/text.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
const Events = preload("res://src/game/event_catalog.gd")
signal back_requested
var album
var catalogue: Array[Dictionary] = []
var cards: Dictionary = {}
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

func _ready() -> void:
	album = get_tree().root.get_node("PaintingAlbum")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 24
	offset_top = 24
	offset_right = -24
	offset_bottom = -24
	add_theme_stylebox_override("panel", Ui.style(Color("17252a"), 13, true))
	lock_texture = Ui.svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 64 64"><g fill="none" stroke="#adac91" stroke-width="3" stroke-linecap="round"><rect x="16" y="27" width="32" height="26" rx="5"/><path d="M23 27v-8a9 9 0 0 1 18 0v8M32 38v6"/></g></svg>')
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

func build_gallery() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	gallery.add_child(header)
	var titles := column(header)
	text(titles, "Collection", 32)
	progress_label = text(titles, "", 15, Color("adbdaf"))
	action(header, "Back", func(): back_requested.emit())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gallery.add_child(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	var hint := text(gallery, "Discover paintings in events to fill your album. Open a collected painting to see its original colours.", 14, Color("adbdaf"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func build_viewer() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	viewer.add_child(header)
	var titles := column(header)
	painting_title = text(titles, "", 24)
	painting_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	artist_label = text(titles, "", 16, Color("adbdaf"))
	artist_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action(header, "Back to album", close_viewer)
	picture_scroll = ScrollContainer.new()
	picture_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewer.add_child(picture_scroll)
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
	toolbar.alignment = BoxContainer.ALIGNMENT_CENTER
	toolbar.add_theme_constant_override("separation", 12)
	viewer.add_child(toolbar)
	previous_button = action(toolbar, "← Previous", func(): navigate(-1))
	action(toolbar, "Fit", fit_picture)
	action(toolbar, "100%", func(): set_zoom(1.0))
	action(toolbar, "−", func(): set_zoom(zoom / 1.25))
	zoom_label = text(toolbar, "100%", 15, Color("adbdaf"))
	zoom_label.custom_minimum_size.x = 64
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	action(toolbar, "+", func(): set_zoom(zoom * 1.25))
	next_button = action(toolbar, "Next →", func(): navigate(1))
	var hint := text(viewer, "View at 100% for original size. Scroll to explore larger paintings. Escape returns to the album.", 13, Color("adbdaf"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func open_album() -> void:
	close_viewer()
	catalogue = album.entries()
	for child in grid.get_children(): child.free()
	cards.clear()
	progress_label.text = Loc.text("%d / %d paintings collected") % [album.collected_count(), catalogue.size()]
	if album.dirty: progress_label.text += "  ·  " + Loc.text("Progress could not be saved.")
	for index in range(catalogue.size()): build_card(catalogue[index], index)
	update_layout()

func build_card(entry: Dictionary, index: int) -> void:
	var unlocked: bool = album.is_collected(entry.path)
	var button := Button.new()
	button.custom_minimum_size = Vector2(238, 284)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.clip_contents = true
	button.disabled = not unlocked
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_ARROW
	Ui.style_button(button)
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
	text(content, "%02d  ·  %s" % [index + 1, Loc.text("Collected") if unlocked else Loc.text("Locked")], 12, Color("b4b49d"))
	var frame := PanelContainer.new()
	frame.custom_minimum_size.y = 146
	frame.add_theme_stylebox_override("panel", Ui.style(Color("111e22"), 6))
	content.add_child(frame)
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview.texture = thumbnail(entry.path) if unlocked else lock_texture
	frame.add_child(preview)
	var title := text(content, entry.title if unlocked else "Undiscovered painting", 16)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var artist := text(content, entry.artist if unlocked else "Find it during an event.", 13, Color("adbdaf"))
	artist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	artist.max_lines_visible = 2
	for child in button.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE

func thumbnail(path: String) -> Texture2D:
	if thumbnails.has(path): return thumbnails[path]
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
	if grid != null: grid.columns = maxi(1, mini(mini(4, maxi(1, catalogue.size())), floori((size.x - 32) / 254.0)))
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
	previous_button.disabled = unlocked_paths().size() < 2
	next_button.disabled = previous_button.disabled
	fit_mode = true
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
	viewer.hide()
	picture.texture = null
	picture.custom_minimum_size = Vector2.ZERO
	selected_path = ""
	gallery.show()

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not viewer.visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode in [KEY_LEFT, KEY_RIGHT]:
		navigate(-1 if event.keycode == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()
