extends SceneTree
const Events = preload("res://src/game/event_catalog.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	root.get_node("Sound").set_muted(true,false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await process_frame
	var album = root.get_node("PaintingAlbum")
	album.seen.clear()
	var entries: Array = album.entries()
	for entry in entries: album.seen[entry.path] = true
	var collection = app.menus.collection_panel
	app.menus.collection_button.pressed.emit()
	expect(app.transitioning and app.menus.navigation_locked,"Cold gallery entry locks navigation while its loading cover is present")
	var cover = get_first_node_in_group("loading_screens")
	expect(cover != null and cover.caption.text == "Loading collection...","Cold gallery uses the shared loading screen with the correct caption")
	expect(not app.music_controls.visible,"Music control stays hidden above the gallery loading cover")
	var progress := []
	cover.progress_changed.connect(func(value): progress.append(value))
	var frames := 0
	while app.transitioning:
		frames += 1
		await process_frame
	expect(frames >= entries.size() and progress.size() >= entries.size(),"Thumbnail preparation yields and reports real progress between images")
	expect(app.menus.screen == app.menus.Screen.COLLECTION and collection.thumbnails.size() == entries.size(),"Loading reveals the complete gallery")
	for entry in entries:
		var texture: Texture2D = collection.thumbnails[entry.path]
		expect(maxf(texture.get_width(),texture.get_height()) <= 512,"Cards use small prebuilt thumbnails")
		expect(texture.resource_path == Events.gallery_thumbnail_path(entry.path),"Gallery thumbnails preserve their source mapping")
		expect(not ResourceLoader.has_cached(entry.path),"Gallery entry does not decode the full-resolution original")
	var first_card = collection.cards[entries[0].path]
	app.menus.show_screen(app.menus.Screen.MAIN)
	await process_frame
	app.menus.collection_button.pressed.emit()
	expect(not app.transitioning and app.menus.screen == app.menus.Screen.COLLECTION,"Returning to a prepared gallery opens immediately")
	expect(not collection.needs_preparation(),"Gallery retains thumbnails for subsequent visits")
	expect(collection.cards[entries[0].path] == first_card,"Returning to the gallery reuses unchanged cards")
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Gallery loading checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
