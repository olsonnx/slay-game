extends SceneTree
## Native pixels: artwork fidelity, actual sun shadows and coloured local lights.
const Lighting = preload("res://src/rendering/sprite_lighting.gd")
var viewport: SubViewport
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func capture() -> Image:
	for tick in range(3): await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func mean_rgb(image: Image) -> Vector3:
	var total := Vector3.ZERO
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x,y)
			if c.r+c.g+c.b > 0.03:
				total += Vector3(c.r,c.g,c.b)
				count += 1
	return total/maxi(count,1)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	root.get_node("Sound").set_muted(true,false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	viewport = SubViewport.new()
	viewport.size = Vector2i(192,192)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.0
	viewport.add_child(camera)
	camera.make_current()
	var sources: Array[Sprite3D] = []
	for kind in ["bear","wolf","boar"]:
		var animal: Node3D = game.view.wildlife.new_actor(Vector2i.ZERO,kind,Vector2i.ZERO)
		for pose in game.view.wildlife.CLIPS[kind]:
			animal.set_meta("pose",pose)
			game.view.wildlife.set_frame(animal)
			sources.append(game.view.wildlife.sprite_for(animal).duplicate())
	for faction in range(game.view.COLORS.size()):
		var source := Sprite3D.new()
		source.texture = game.view.unit_sprites.frame(3,game.view.COLORS[faction],"attack",3).texture
		source.pixel_size = 0.08
		source.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		source.shaded = false
		source.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		source.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sources.append(source)
	for source in sources:
		viewport.add_child(source)
		source.position = Vector3.ZERO
		source.layers = 1
		source.show()
		var tex: Texture2D = source.texture.atlas if source.texture is AtlasTexture else source.texture
		var material := Lighting.make_material(tex,Vector2(source.texture.get_width(),source.texture.get_height()),source.pixel_size)
		material.set_shader_parameter("shadow_fill",Vector3.ONE)
		material.set_shader_parameter("sun_gain",0.0)
		material.set_shader_parameter("highlight_softening",0.0)
		for position in [Vector3(0,0,8),Vector3(5,6,8)]:
			camera.position = position
			camera.look_at(Vector3.ZERO)
			for flip in [false,true]:
				source.modulate = Color("a8b2ae") if flip else Color.WHITE
				source.flip_h = flip
				source.material_override = null
				var native := await capture()
				source.material_override = material
				var shaded := await capture()
				var errors := 0
				var pixels := 0
				for y in range(192):
					for x in range(192):
						var a := native.get_pixel(x,y)
						var b := shaded.get_pixel(x,y)
						if a.r+a.g+a.b > 0.03: pixels += 1
						if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length() > 0.025: errors += 1
				expect(pixels > 40 and errors == 0,"Neutral shader preserves atlas, faction pixels, facing and silhouette at camera %s" % position)
		if source.texture is not AtlasTexture:
			source.material_override = null
			var native := await capture()
			source.hide()
			var render := MultiMeshInstance3D.new()
			var instances := MultiMesh.new()
			instances.transform_format = MultiMesh.TRANSFORM_3D
			instances.use_colors = true
			var quad := QuadMesh.new()
			quad.size = Vector2(source.texture.get_width(),source.texture.get_height())*source.pixel_size
			instances.mesh = quad
			instances.instance_count = 1
			instances.set_instance_transform(0,Transform3D.IDENTITY)
			instances.set_instance_color(0,source.modulate)
			render.multimesh = instances
			var batched_material := Lighting.make_material(tex,Vector2(source.texture.get_width(),source.texture.get_height()),source.pixel_size,source.flip_h)
			batched_material.set_shader_parameter("shadow_fill",Vector3.ONE)
			batched_material.set_shader_parameter("sun_gain",0.0)
			batched_material.set_shader_parameter("highlight_softening",0.0)
			render.material_override = batched_material
			viewport.add_child(render)
			var batched := await capture()
			var errors := 0
			for y in range(192):
				for x in range(192):
					var a := native.get_pixel(x,y)
					var b := batched.get_pixel(x,y)
					if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length() > 0.025: errors += 1
			expect(errors == 0,"Army instance tint and faction palette match the native sprite")
			viewport.remove_child(render)
			render.free()
		viewport.remove_child(source)
		source.free()
	# Real engine shadows, not a manually supplied darkness value.
	camera.position = Vector3(0,0,8)
	camera.look_at(Vector3.ZERO)
	var actor := Sprite3D.new()
	actor.texture = game.view.unit_sprites.frame(2,game.view.COLORS[0]).texture
	actor.pixel_size = 0.08
	actor.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	actor.material_override = Lighting.make_material(actor.texture,Vector2(32,20),0.08)
	viewport.add_child(actor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees.x = -90
	sun.light_color = Color("ffe6be")
	sun.light_energy = 0.92
	sun.shadow_enabled = true
	viewport.add_child(sun)
	var sunlight := await capture()
	var current_material: ShaderMaterial = actor.material_override
	var original_material := current_material.duplicate() as ShaderMaterial
	original_material.set_shader_parameter("shadow_fill",Vector3(0.55,0.63,0.78))
	original_material.set_shader_parameter("sun_gain",0.60)
	original_material.set_shader_parameter("highlight_softening",0.0)
	actor.material_override = original_material
	sun.light_energy = 1.12
	var original_sunlight := await capture()
	actor.material_override = current_material
	sun.light_energy = 0.92
	expect(mean_rgb(sunlight).length() < mean_rgb(original_sunlight).length()*0.9,"New sprite treatment is visibly gentler than the previous bright pass")
	var roof := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(4,0.2,4)
	roof.mesh = box
	roof.position.y = 3
	viewport.add_child(roof)
	var shadow := await capture()
	sun.hide()
	roof.hide()
	var fill := await capture()
	var lit_rgb := mean_rgb(sunlight)
	var shaded_rgb := mean_rgb(shadow)
	var fill_rgb := mean_rgb(fill)
	expect(lit_rgb.length() > shaded_rgb.length()*1.08,"Real shadow caster reduces sprite sunlight")
	expect(shaded_rgb.distance_to(fill_rgb) < 0.03,"Deep shadow retains the controlled ambient floor")
	expect(fill_rgb.length() > lit_rgb.length()*0.45,"Sprites remain readable in deep shade")
	var point := OmniLight3D.new()
	point.position = Vector3(0,2,2)
	point.omni_range = 6
	point.light_energy = 2
	viewport.add_child(point)
	point.light_color = Color("70aaff")
	var blue := await capture()
	point.light_color = Color("ffc070")
	var warm := await capture()
	var blue_delta := mean_rgb(blue)-fill_rgb
	var warm_delta := mean_rgb(warm)-fill_rgb
	expect(blue_delta.z > blue_delta.x*1.25 and blue_delta.z > 0.015,"Mana light adds restrained blue tint")
	expect(warm_delta.x > warm_delta.z*1.25 and warm_delta.x > 0.015,"Building light adds restrained warm tint")
	for item in [[sunlight,"sun"],[shadow,"shadow"],[blue,"mana"],[warm,"warm"]]:
		item[0].save_png("res://artifacts/sprite-lighting-probe-%s.png" % item[1])
	print("Native sprite lighting checks: %d passed, %d failed" % [checks-failures,failures])
	game.queue_free()
	viewport.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit(1 if failures else 0)
