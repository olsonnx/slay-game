extends SceneTree
const Library = preload("res://src/rendering/unit_sprite_library.gd")
const Lighting = preload("res://src/rendering/sprite_lighting.gd")
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func run() -> void:
	var library = Library.new()
	for animation in Library.FOOT_CLIPS:
		var clip: Array = Library.clip(1, animation)
		for index in range(clip[1]):
			var texture: Texture2D = library.frame(1, Color.WHITE, animation, index).texture
			var region: Rect2 = texture.get_meta("normal_region")
			expect(region == Rect2(Vector2(index * 32, clip[0] * 32 + 12) / Vector2(Library.SHEETS[1].get_size()), Vector2(32,20) / Vector2(Library.SHEETS[1].get_size())), "Normal region follows cropped animation frame")
			var material := Lighting.make_material(texture, Vector2(32,20), 0.08)
			expect(material.get_shader_parameter("has_normal_map") and material.get_shader_parameter("normal_texture") == Lighting.ScoutNormal, "Scout frame uses supplied normal sheet")
	for tier in [2,3]:
		var texture: Texture2D = library.frame(tier, Color.WHITE).texture
		expect(not Lighting.make_material(texture,Vector2(32,20),0.08).get_shader_parameter("has_normal_map"), "Other ranks retain existing shading")
	expect(Lighting.ScoutNormal.get_size() == Library.SHEETS[1].get_size(), "Normal sheet aligns with source sheet")
	if DisplayServer.get_name() != "headless":
		var lab = load("res://scenes/lighting_lab.tscn").instantiate()
		root.add_child(lab)
		await process_frame
		var board = lab.board
		for coord in board.unit_actors:
			var actor: Node3D = board.unit_actors[coord]
			var animator = actor.get_node("UnitAnimation")
			if animator.tier == 1:
				board.focus = board.coord_position(coord)
				break
		board.zoom = 8.0
		board.update_camera()
		# Freeze poses and scenery for an identical A/B capture.
		board.unit_presentation.set_process(false)
		board.birds.set_process(false)
		board.wildlife.set_process(false)
		for actor in board.unit_actors.values(): actor.get_node("UnitAnimation").set_process(false)
		var uploads: int = board.unit_batches.upload_count
		var captures: Array[Image] = []
		for strength in [0.0, 0.65]:
			lab.fields.normal_strength.value = strength
			for frame in range(5): await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png("res://artifacts/scout-normal-%s.png" % ("off" if strength == 0.0 else "on"))
			captures.append(image)
		# Compare only the map; exclude changing slider text.
		var different := 0
		for y in range(captures[0].get_height()):
			for x in range(captures[0].get_width()-350):
				if captures[0].get_pixel(x,y) != captures[1].get_pixel(x,y): different += 1
		expect(different > 0, "Normals visibly affect rendered map pixels")
		expect(board.unit_batches.upload_count == uploads, "Normal strength does not rebuild army buffers")
		lab.queue_free()
		await process_frame
	print("Scout normal checks: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)
