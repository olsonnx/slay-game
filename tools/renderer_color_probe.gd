extends SceneTree
## Native source-vs-batch colour parity, water styles, and live renderer profiles.
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func capture() -> Image:
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func error_between(a: Image, b: Image) -> float:
	var error := 0.0
	var count := 0
	for y in range(100,a.get_height()-100,3):
		for x in range(60,a.get_width()-60,3):
			var first := a.get_pixel(x,y)
			var second := b.get_pixel(x,y)
			error += Vector3(first.r-second.r,first.g-second.g,first.b-second.b).length()
			count += 1
	return error/maxi(count,1)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.get_node("Sound").set_muted(true,false)
	var video = root.get_node("Video")
	video.set_preference(&"level_transitions",false,false)
	video.set_preference(&"stylized_water",false,false)
	video.set_preference(&"atmospheric_lighting",false,false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 71
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await process_frame
	game.view.unit_presentation.set_process(false)
	game.view.birds.set_process(false)
	game.view.wildlife.set_process(false)
	Engine.time_scale = 0.0
	var view = game.view
	view.zoom = 18
	view.update_camera()
	view.sun.shadow_enabled = false
	view.sun.light_energy = 0
	view.background_environment.ambient_light_energy = 1.0
	view.background_environment.ambient_light_color = Color.WHITE
	var batched := await capture()
	view.static_batches.set_suspended(true)
	var sources := await capture()
	var error := error_between(batched,sources)
	print("Source/batch colour error: %.6f" % error)
	expect(error < 0.012,"Retained terrain and props match their source materials in linear rendering")
	for material in view.static_batches.materials.values():
		expect(material.vertex_color_is_srgb,"Batch materials identify authored vertex and instance colours as sRGB")
	view.static_batches.set_suspended(false)
	view.refresh_static_batches()
	video.set_preference(&"atmospheric_lighting",true,false)
	view.sun.shadow_enabled = video.shadows
	view.lighting.apply_style("atmospheric")
	view.zoom = 12
	view.focus = view.coord_position(game.rules.kingdoms.keys()[0])
	view.update_camera()
	view.lighting.advance(1.0)
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	var renderer := RenderingServer.get_current_rendering_method()
	expect(view.background_environment.ssao_enabled == (forward and video.shadows),"Only Forward+ Atmospheric enables contact occlusion")
	for stylized in [false,true]:
		video.set_preference(&"stylized_water",stylized,false)
		if stylized: view.water.material_override.set_shader_parameter("time_override",1.0)
		var image := await capture()
		image.save_png("res://artifacts/%s-water-%s.png" % [renderer,"stylized" if stylized else "original"])
		var water := image.get_pixel(image.get_width()-20,image.get_height()/2)
		expect(water.b > water.r and water.r < 0.25 and water.g < 0.4,"Both water styles retain a deep blue palette")
	video.set_preference(&"shadows",false,false)
	expect(not view.background_environment.ssao_enabled,"The shadow preference also suppresses contact occlusion")
	video.set_preference(&"atmospheric_lighting",false,false)
	expect(not view.background_environment.ssao_enabled and is_zero_approx(view.sun.light_angular_distance),"Simple resets Forward+ occlusion and soft-sun settings")
	print("Renderer colour checks: %d passed, %d failed" % [checks-failures,failures])
	Engine.time_scale = 1.0
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit(1 if failures else 0)
