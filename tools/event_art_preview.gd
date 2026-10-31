extends SceneTree
## Render every assigned event crop together for visual review.
const Events = preload("res://src/game/event_catalog.gd")
const Painting = preload("res://src/ui/event_painting.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1800,1320)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.size = viewport.size
	background.color = Color("17252a")
	viewport.add_child(background)
	var index := 0
	for id in Events.EVENTS:
		var definition: Dictionary = Events.EVENTS[id]
		var artwork := Events.artwork(definition)
		var at := Vector2(24+(index%4)*444,24+(index/4)*258)
		var label := Label.new()
		label.text = definition.title
		label.position = at
		label.size = Vector2(424,26)
		label.add_theme_font_size_override("font_size",16)
		label.clip_text = true
		viewport.add_child(label)
		var texture := Events.event_texture(artwork)
		var painting := Painting.new(texture,424,"",Events.event_texture_focus(artwork))
		painting.position = at+Vector2(0,30)
		viewport.add_child(painting)
		index += 1
	for frame in range(12): await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://artifacts/event-art-contact-sheet.png")
	print("Rendered event artwork: ",index)
	quit()
