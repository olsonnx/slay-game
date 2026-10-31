extends SceneTree
const Events = preload("res://src/game/event_catalog.gd")
const Warmup = preload("res://src/ui/event_art_warmup.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var warmup := Warmup.new()
	root.add_child(warmup)
	await warmup.prepare()
	expect(warmup.completed and warmup.prepared_count == 20,"Boot prepares all event banners and the fallback")
	var memory := 0
	for definition in Events.EVENTS.values():
		var artwork := Events.artwork(definition)
		var texture := Events.event_texture(artwork)
		expect(texture.get_size() == Vector2(1024,512),"Every event uses a bounded 1024 by 512 texture")
		expect(not ResourceLoader.has_cached(artwork.painting),"Preparing an event does not decode or retain its Collection original")
		expect(Events.event_texture(artwork) == texture,"Event reveal reuses the prepared texture")
		expect(Events.event_texture_focus(artwork) == Vector2(0.5,0.5),"Prepared artwork is not cropped a second time")
		memory += texture.get_width()*texture.get_height()*4
	var album = root.get_node("PaintingAlbum")
	var previous_seen: Dictionary = album.seen.duplicate()
	var previous_path: String = album.settings_path
	album.settings_path = "user://event-art-loading-test.cfg"
	album.seen.clear()
	expect(album.discover(Events.EVENTS.goose),"A prepared event can unlock its full-image Collection identity")
	expect(not ResourceLoader.has_cached(Events.EVENTS.goose.painting),"Discovery does not decode the original on the reveal frame")
	album.seen = previous_seen
	album.settings_path = previous_path
	var count := warmup.viewport.get_child_count()
	await warmup.prepare()
	expect(warmup.viewport.get_child_count() == count,"New matches reuse the completed warmup without duplicating textures")
	var custom := {"painting":Events.DEFAULT_PAINTING.painting,"painting_focus":[37,51]}
	expect(Events.event_texture_path(custom) == Events.DEFAULT_PAINTING.painting,"Unbuilt custom crops fall back to the original safely")
	print("Prepared event texture memory: ",memory/1048576.0," MiB for current events")
	print("Event art loading checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
