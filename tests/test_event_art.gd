extends SceneTree
const Events = preload("res://src/game/event_catalog.gd")
const Painting = preload("res://src/ui/event_painting.gd")
const Schema = preload("res://src/game/authored_event_schema.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var paths := {}
	for id in Events.EVENTS:
		var definition: Dictionary = Events.EVENTS[id]
		expect(definition.has("painting") and definition.painting != "","Every current event has a specific painting: "+id)
		var texture := Events.painting_texture(definition.painting)
		expect(texture != null and texture.get_width() >= 900 and texture.get_height() >= 600,"Event image has enough resolution for the 424px frame: "+id)
		paths[definition.painting] = true
		var painting := Painting.new(texture,424,"",Events.painting_focus(definition))
		expect(painting.size == Vector2(424,212) and painting.texture == texture,"Event crop keeps a fixed 2:1 frame and the original source texture")
		painting.free()
	expect(paths.size() == Events.EVENTS.size(),"Every event now has distinct artwork")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/art/event_painting_sources.json"))
	expect(manifest.artworks.size() == 17,"All seventeen new assignments have source and reuse records")
	for record in manifest.artworks:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(FileAccess.get_file_as_bytes(record.path))
		expect(context.finish().hex_encode() == record.sha256,"Imported artwork matches its recorded source bytes")
		expect(record.license in ["Public domain","CC0","PDM-owner"] and record.source.begins_with("https://commons.wikimedia.org/"),"Every new image has explicit public-domain or CC0 source evidence")
		expect(Events.EVENTS[record.event].painting == record.path,"Built-in and authored overrides use the intended image")
	var authored := Schema.fresh("crop_test")
	authored.painting_focus = [50,31]
	expect(Schema.validate(authored).is_empty() and Events.painting_focus(Schema.normalize(authored)) == Vector2(0.5,0.31),"Portrait framing survives authored-pack integer normalization")
	authored.painting_focus = [50,101]
	expect(not Schema.validate(authored).is_empty(),"Invalid crop percentages are rejected")
	expect(Events.painting_focus({"painting_focus":["bad",10]}) == Vector2(0.5,0.5),"Malformed programmatic focus falls back safely")
	print("Event art checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
