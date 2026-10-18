## Native-renderer visual checks; run without --headless. Saves into artifacts/.
extends SceneTree
func _initialize() -> void:
	root.hide()
	call_deferred("run")
func capture(viewport: SubViewport, path: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://artifacts/" + path + ".png")
func run() -> void:
	root.get_node("Video").set_preference(&"background", "water", false)
	root.get_node("Video").set_preference(&"stylized_water", true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280,820)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_rule_mode = "modern"
	viewport.add_child(game)
	game.set_process(false)
	var water: ShaderMaterial = game.view.water.material_override
	for texture_name in ["noise1", "noise2", "normalmap"]:
		var texture = water.get_shader_parameter(texture_name)
		if texture.get_image() == null: await texture.changed
	water.set_shader_parameter("time_override", 12.0)
	await capture(viewport, "water-after-game")
	water.set_shader_parameter("time_override", 15.0)
	await capture(viewport, "water-after-motion")
	water.set_shader_parameter("time_override", 12.0)
	game.view.toggle_top_down()
	await capture(viewport, "water-after-top")
	game.view.toggle_top_down()
	if FileAccess.file_exists("res://artifacts/water-before.gdshader"):
		water.shader = load("res://artifacts/water-before.gdshader")
		await capture(viewport, "water-before-game")
	game.shutdown()
	game.queue_free()
	await process_frame
	var map = load("res://src/rendering/decorative_map.gd").new()
	map.initial_seed = 1
	viewport.add_child(map)
	map.layout_camera(1280.0 / 820.0)
	map.active = true
	map.advance(0.1)
	map.water.material_override.set_shader_parameter("time_override",12.0)
	await capture(viewport, "water-after-menu")
	map.queue_free()
	await process_frame
	var first := Image.load_from_file("res://artifacts/water-after-game.png")
	var second := Image.load_from_file("res://artifacts/water-after-motion.png")
	var changed := 0
	for y in range(90, 190):
		for x in range(50, 650):
			if first.get_pixel(x, y) != second.get_pixel(x, y): changed += 1
	assert(changed > 1000, "Water must visibly animate in the native renderer")
	print("Water previews saved; animated water pixels changed: ", changed, " / 60000")
	quit()
