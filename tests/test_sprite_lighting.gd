extends SceneTree
const Snapshot = preload("res://src/game/state_snapshot.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	root.get_node("Video").set_preference(&"atmospheric_lighting",true,false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await process_frame
	var renderer = game.view.sprite_lighting
	var source: Vector2i = game.view.unit_actors.keys()[0]
	for coord in game.view.unit_actors:
		if game.view.unit_actors[coord].get_meta("unit_ready",false):
			source = coord
			break
	var actor: Node3D = game.view.unit_actors[source]
	var animator = actor.get_node("UnitAnimation")
	var saved := Snapshot.capture(game.rules)
	var uploads: int = game.view.unit_batches.upload_count
	var sprite: Sprite3D = animator.sprite
	expect(renderer.enabled and sprite.material_override is ShaderMaterial,"Atmospheric lighting shades live unit sprites")
	var slot: Array = game.view.unit_batches.sprite_slots[sprite.get_instance_id()]
	var batch: MultiMeshInstance3D = slot[0].get_ref()
	var instances := batch.multimesh.get_instance_id()
	expect(batch.material_override is ShaderMaterial and batch.material_override.get_shader_parameter("sprite_texture") == sprite.texture,"Batched and live units use the same source pixels")
	for index in range(4):
		animator.show_idle_frame(index)
		game.view.unit_batches.animate_idle(index)
		expect(sprite.material_override.get_shader_parameter("sprite_texture") == sprite.texture and batch.material_override.get_shader_parameter("sprite_texture") == sprite.texture,"Lighting follows animation frames without replacing the artwork")
	animator.show_idle_frame(1)
	game.view.unit_batches.sync()
	expect(batch.material_override.get_shader_parameter("sprite_texture") == sprite.texture,"Returning to an existing batch immediately restores its current pose")
	for kind in ["bear","wolf","boar"]:
		var animal: Node3D = game.view.wildlife.new_actor(Vector2i.ZERO,kind,Vector2i.ZERO)
		for pose in game.view.wildlife.CLIPS[kind]:
			animal.set_meta("pose",pose)
			game.view.wildlife.set_frame(animal)
			var image: Sprite3D = game.view.wildlife.sprite_for(animal)
			expect(image.material_override is ShaderMaterial and image.material_override.get_shader_parameter("sprite_texture") == image.texture.atlas,"Animal poses retain their atlas regions under lighting")
	for flock in game.view.birds.flocks:
		var bird: Sprite3D = flock.birds[0]
		renderer.sync(bird)
		expect(bird.material_override.shader == renderer.Fading,"Birds keep a separate fading/depth-prepass shader")
	root.get_node("Video").set_preference(&"atmospheric_lighting",false,false)
	expect(sprite.material_override == null and batch.material_override is StandardMaterial3D,"Simple restores native unlit sprites and the original army material")
	expect(not renderer.enabled,"Simple disables sprite lighting with the existing toggle")
	root.get_node("Video").set_preference(&"atmospheric_lighting",true,false)
	expect(sprite.material_override is ShaderMaterial and batch.material_override is ShaderMaterial,"Returning to Atmospheric restores both rendering paths")
	expect(batch.multimesh.get_instance_id() == instances and game.view.unit_batches.upload_count == uploads,"Switching sprite lighting keeps army instance buffers intact")
	expect(Snapshot.capture(game.rules) == saved,"Lighting never changes gameplay, RNG, effects or unit readiness")
	expect(renderer.materials.size() <= renderer.CACHE_LIMIT,"Frame material caching stays bounded")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Sprite lighting checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
