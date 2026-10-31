extends SceneTree
const Collection = preload("res://src/settings/painting_collection.gd")
const Events = preload("res://src/game/event_catalog.gd")
const Snapshot = preload("res://src/game/state_snapshot.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count := 3) -> void:
	for index in range(count): await process_frame

func escape(menus) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	menus._unhandled_input(event)

func run() -> void:
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	var path := "res://artifacts/painting-collection-test.cfg"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var model := Collection.new()
	model.settings_path = path
	root.add_child(model)
	var entries := model.entries()
	expect(entries.size() >= 3 and model.collected_count() == 0, "A new album lists the event artwork with no pre-unlocked paintings")
	var paths := entries.map(func(entry): return entry.path)
	expect(paths.count(Events.DEFAULT_PAINTING.painting) == 0, "A fresh album has no unreachable fallback slot once every event has dedicated art")
	expect(not model.discover({"focus_cancel":true}) and not model.discover({"painting":"res://assets/paintings/missing.png"}), "Confirmations and missing artwork never grant collection progress")
	expect(model.discover(Events.DEFAULT_PAINTING) and not model.discover(Events.DEFAULT_PAINTING) and model.collected_count() == 1, "First discovery unlocks once, independently of event ID")
	expect(model.entries().map(func(entry): return entry.path).count(Events.DEFAULT_PAINTING.painting) == 1,"Previously discovered fallback paintings remain in the album exactly once")
	var reloaded := Collection.new()
	reloaded.settings_path = path
	expect(reloaded.load_settings() == OK and reloaded.is_collected(Events.DEFAULT_PAINTING.painting), "Collection progress survives a fresh model and file reload")
	var bad_data := ConfigFile.new()
	var different_path: String = entries.filter(func(entry): return entry.path != Events.DEFAULT_PAINTING.painting)[0].path
	bad_data.set_value("collection", "paintings", {Events.DEFAULT_PAINTING.painting:true,"res://src/game/game.gd":true,different_path:1})
	bad_data.save(path)
	reloaded.load_settings()
	expect(reloaded.seen.size() == 1, "Saved progress accepts only painting paths and true boolean unlocks")
	reloaded.free()
	model.queue_free()
	var album = root.get_node("PaintingAlbum")
	var original_path: String = album.settings_path
	var original_seen: Dictionary = album.seen.duplicate()
	var original_dirty: bool = album.dirty
	album.settings_path = "res://artifacts/painting-collection-integration.cfg"
	album.seen.clear()
	album.dirty = false
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	app.menus.collection_button.pressed.emit()
	while app.transitioning: await process_frame
	await frames()
	var panel = app.menus.collection_panel
	expect(app.menus.screen == app.menus.Screen.COLLECTION and panel.visible and panel.cards.size() == entries.size(), "Main menu Collection opens the complete digital album")
	expect(panel.thumbnails.is_empty(), "A locked album does not load or reveal its paintings")
	for entry in entries:
		expect(panel.cards[entry.path].disabled, "Unseen paintings are locked")
		panel.open_painting(entry.path)
	expect(not panel.viewer.visible and panel.selected_path == "", "Locked paintings cannot be opened even through direct viewer calls")
	escape(app.menus)
	expect(app.menus.screen == app.menus.Screen.MAIN, "Escape returns from the album to the main menu")
	await app.start_new_game(71, "very_small", "easy", 2)
	var game = app.game
	var coord: Vector2i = game.active_capital()
	game.rules.pending_events.append({"id":"wizard","coord":coord,"faction":game.player_faction})
	game.show_next_event()
	game.close_event_ui()
	await frames(4)
	expect(album.collected_count() == 0, "A dialog cancelled during preparation does not unlock an unseen painting")
	game.show_next_event()
	var before_discovery := Snapshot.capture(game.rules)
	await frames(5)
	expect(album.is_collected(Events.EVENTS.wizard.painting), "An actual game event unlocks the painting once it is revealed")
	expect(Snapshot.capture(game.rules) == before_discovery, "Collecting artwork never changes the match state or RNG")
	game.resolve_shown_event(0)
	await app.return_to_main_menu()
	app.menus.collection_button.pressed.emit()
	while app.transitioning: await process_frame
	await frames()
	expect(not panel.cards[Events.EVENTS.wizard.painting].disabled and panel.thumbnails.size() == 1, "Returning from a match reveals only collected artwork")
	panel.open_painting(Events.EVENTS.wizard.painting)
	await frames()
	expect(panel.viewer.visible and panel.picture.texture != null and panel.picture.material == null and panel.picture.modulate == Color.WHITE, "Viewer uses the original full-colour texture without the event treatment")
	panel.set_zoom(1.0)
	await frames()
	expect(panel.picture.custom_minimum_size == panel.picture.texture.get_size(), "100 percent displays the original image at its native pixel dimensions")
	panel.fit_picture()
	await frames()
	expect(panel.picture.custom_minimum_size.x <= panel.picture_scroll.size.x and panel.picture.custom_minimum_size.y <= panel.picture_scroll.size.y, "Fit displays the entire painting without cropping or distortion")
	var another: Dictionary = entries.filter(func(entry): return entry.path != Events.EVENTS.wizard.painting)[0]
	album.discover({"painting":another.path})
	panel.open_album()
	panel.open_painting(Events.EVENTS.wizard.painting)
	panel.navigate(1)
	expect(panel.selected_path == another.path, "Viewer navigation skips locked paintings")
	escape(app.menus)
	expect(app.menus.screen == app.menus.Screen.COLLECTION and not panel.viewer.visible and panel.picture.texture == null, "First Escape closes the full-size viewer and releases its original texture")
	escape(app.menus)
	expect(app.menus.screen == app.menus.Screen.MAIN, "Second Escape returns to the main menu")
	var saved := Collection.new()
	saved.settings_path = album.settings_path
	saved.load_settings()
	expect(saved.collected_count() == 2, "Progress from actual event discovery remains on disk after leaving the match")
	saved.free()
	app.queue_free()
	await frames()
	album.settings_path = original_path
	album.seen = original_seen
	album.dirty = original_dirty
	print("Painting collection checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
