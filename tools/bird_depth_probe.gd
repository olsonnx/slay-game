extends SceneTree
## Native pixel regression for birds in front of and behind real game sprites.
var checks := 0
var failures := 0
var viewport: SubViewport
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func centered_copy(original: Sprite3D) -> Sprite3D:
	var sprite := original.duplicate() as Sprite3D
	var source := original.texture.get_image()
	var size := Vector2i(source.get_width()/original.hframes,source.get_height()/original.vframes)
	var frame := source.get_region(Rect2i(Vector2i(original.frame%original.hframes,original.frame/original.hframes)*size,size))
	var center := frame.get_used_rect().get_center()
	sprite.position = Vector3(-(center.x-size.x*0.5)*sprite.pixel_size,(center.y-size.y*0.5)*sprite.pixel_size,0)
	sprite.modulate = Color.WHITE
	sprite.layers = 1
	sprite.show()
	return sprite
func capture() -> Image:
	for tick in range(2): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Run this pixel probe with the native renderer, without --headless.")
		quit(1)
		return
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.view.birds.set_process(false)
	viewport = SubViewport.new()
	viewport.size = Vector2i(256,256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	camera.position = Vector3(0,0,8)
	viewport.add_child(camera)
	camera.make_current()
	var bird := centered_copy(game.view.birds.flocks[0].birds[0])
	viewport.add_child(bird)
	bird.hide()
	var background := await capture()
	bird.show()
	var sources: Array[Sprite3D] = []
	for kind in ["bear","wolf","boar"]:
		var actor: Node3D = game.view.wildlife.new_actor(Vector2i.ZERO,kind,Vector2i.ZERO)
		sources.append(game.view.wildlife.sprite_for(actor))
	sources.append(game.view.unit_actors.values()[0].get_node("UnitAnimation").sprite)
	for index in range(sources.size()):
		var other := centered_copy(sources[index])
		other.modulate = Color(0.2,0.7,1.0)
		viewport.add_child(other)
		other.hide()
		var bird_only := await capture()
		bird.hide()
		other.show()
		var other_only := await capture()
		bird.show()
		bird.position.z = 0.2
		var front := await capture()
		bird.position.z = -0.2
		var behind := await capture()
		bird.modulate.a = 0.5
		var fading := await capture()
		var samples := 0
		var front_ok := true
		var behind_ok := true
		var fading_ok := true
		for y in range(96,160):
			for x in range(96,160):
				var feather := bird_only.get_pixel(x,y)
				var target := other_only.get_pixel(x,y)
				var base := background.get_pixel(x,y)
				if Vector3(feather.r-base.r,feather.g-base.g,feather.b-base.b).length() < 0.05 or Vector3(target.r-base.r,target.g-base.g,target.b-base.b).length() < 0.05: continue
				samples += 1
				front_ok = front_ok and front.get_pixel(x,y).is_equal_approx(feather)
				behind_ok = behind_ok and behind.get_pixel(x,y).is_equal_approx(target)
				fading_ok = fading_ok and fading.get_pixel(x,y).is_equal_approx(target)
		expect(samples > 8,"Real sprite silhouettes overlap in the depth fixture")
		expect(front_ok,"Foreground birds cover sprite %d" % index)
		expect(behind_ok,"Sprite %d covers birds behind it" % index)
		expect(fading_ok,"Sprite %d also covers fading birds behind it" % index)
		front.save_png("res://artifacts/bird-depth-%d-front.png" % index)
		behind.save_png("res://artifacts/bird-depth-%d-behind.png" % index)
		bird.modulate.a = 1.0
		bird.position.z = 0.0
		other.queue_free()
		await process_frame
	# Let queued rendering work settle before retiring the readback viewport
	# and its referenced sprite materials under Forward+.
	await create_timer(0.3).timeout
	game.queue_free()
	viewport.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	root.get_node("Sound").stop_all()
	print("Bird sprite depth checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
