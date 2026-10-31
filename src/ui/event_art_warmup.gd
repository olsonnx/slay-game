extends Node
## Retain small banners and their rendered shader variants behind the load cover.
const Events = preload("res://src/game/event_catalog.gd")
const Painting = preload("res://src/ui/event_painting.gd")
var viewport: SubViewport
var completed := false
var signature := ""
var prepared_count := 0
var prepare_ms := 0.0

func prepare(report: Callable = Callable()) -> void:
	var artworks := {}
	var definitions: Array = Events.EVENTS.values()
	definitions.append(Events.DEFAULT_PAINTING)
	for definition in definitions:
		var artwork := Events.artwork(definition)
		if artwork.has("painting"): artworks[Events.event_texture_key(artwork)] = artwork
	var keys := artworks.keys()
	keys.sort()
	var next_signature := "\n".join(keys)
	if completed and signature == next_signature:
		if report.is_valid(): report.call(1.0)
		return
	var started := Time.get_ticks_usec()
	if viewport == null:
		viewport = SubViewport.new()
		viewport.name = "EventArtPreparation"
		viewport.size = Vector2i(424,212)
		viewport.disable_3d = true
		add_child(viewport)
	for child in viewport.get_children(): child.queue_free()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	prepared_count = 0
	for key in keys:
		var artwork: Dictionary = artworks[key]
		var texture := Events.event_texture(artwork)
		if texture != null:
			viewport.add_child(Painting.new(texture,424,"",Events.event_texture_focus(artwork)))
			prepared_count += 1
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
		if report.is_valid(): report.call(float(prepared_count)/maxi(1,keys.size()))
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	completed = true
	signature = next_signature
	prepare_ms = (Time.get_ticks_usec()-started)/1000.0
