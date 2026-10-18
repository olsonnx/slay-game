extends SceneTree
const Library = preload("res://src/rendering/unit_sprite_library.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func asset_checks() -> void:
	var library := Library.new()
	for tier in range(1, 4):
		var source: Image = Library.SHEETS[tier].get_image()
		source.convert(Image.FORMAT_RGBA8)
		var original := source.get_data()
		for color in Catalog.TERRAIN_COLORS:
			var sheet: Image = library.sheet(tier, color)
			var changed := sheet.get_data()
			var preserved := true
			var recolored := 0
			for offset in range(0, original.size(), 4):
				var cloth := (original[offset] == 96 and original[offset+1] == 152 and original[offset+2] == 232) or (original[offset] == 64 and original[offset+1] == 88 and original[offset+2] == 192)
				var detail := (tier == 1 and original[offset] == 90 and original[offset+1] == 123 and original[offset+2] == 148) or (tier == 3 and original[offset] == 55 and original[offset+1] == 55 and original[offset+2] == 87)
				if cloth:
					var expected: Color = color.lightened(0.12) if original[offset] == 96 else color.darkened(0.28)
					preserved = preserved and changed[offset] == expected.r8 and changed[offset+1] == expected.g8 and changed[offset+2] == expected.b8
					recolored += 1
				elif not detail:
					preserved = preserved and changed[offset] == original[offset] and changed[offset+1] == original[offset+1] and changed[offset+2] == original[offset+2]
				elif changed[offset] != original[offset] or changed[offset+1] != original[offset+1] or changed[offset+2] != original[offset+2]:
					var expected: Color = color.darkened(0.42 if tier == 1 else 0.12)
					preserved = preserved and changed[offset] == expected.r8 and changed[offset+1] == expected.g8 and changed[offset+2] == expected.b8
				preserved = preserved and changed[offset+3] == original[offset+3]
			expect(preserved and recolored > 0, "Team colors preserve alpha, skin, weapons and horse coat")
			expect(library.sheet(tier, color) == sheet, "Faction sheets are shared through the cache")
		for animation in Library.CLIPS[tier]:
			var sequence := Library.clip(tier, animation)
			for index in range(sequence[1]):
				var frame := library.frame(tier, Color.RED, animation, index)
				var used: Rect2i = frame.image.get_used_rect()
				expect(used.has_area(), "Every mapped animation frame contains a sprite")
				var source_frame := source.get_region(Rect2i(index*32, int(sequence[0])*32, 32, 32))
				var bounds := source_frame.get_used_rect()
				expect(tier == 3 or bounds.position.y >= 12, "Consistent foot cropping never clips a weapon or pose")
				expect(library.frame(tier, Color.RED, animation, index).texture == frame.texture, "Animation textures are shared, not allocated per tick")
		expect(source.get_data() == original, "Runtime recoloring leaves source artwork unchanged")
	mask_regressions(library)

func mask_regressions(library) -> void:
	# Independent landmarks from the source art: the sleeve shares a helmet color,
	# and the tail shares a bridle color. Both boundaries matter for this fix.
	for color in Catalog.TERRAIN_COLORS:
		var scout: Image = library.sheet(1, color)
		var sleeve_color: Color = color.darkened(0.42)
		sleeve_color = Color.from_rgba8(sleeve_color.r8,sleeve_color.g8,sleeve_color.b8)
		for point in [Vector2i(19,25), Vector2i(20,26), Vector2i(19+32,23+64), Vector2i(14+96,25+96)]:
			expect(scout.get_pixelv(point).is_equal_approx(sleeve_color), "Scout sleeves recolor in idle, jump and attack poses")
		for point in [Vector2i(13,20), Vector2i(14,19), Vector2i(13+64,23+64)]:
			expect(scout.get_pixelv(point) == Color("5a7b94"), "Scout helmet shading stays steel blue")
		var knight: Image = library.sheet(3, color)
		var landmarks := [
			[Vector2i(9,23),Vector2i(9,23),Vector2i(9,23),Vector2i(9,23),Vector2i(9,23),Vector2i(8,23),Vector2i(9,23),Vector2i(9,23)],
			[Vector2i(9,23),Vector2i(10,23),Vector2i(9,22),Vector2i(9,22),Vector2i(6,23),Vector2i(7,23)],
			[Vector2i(9,23),Vector2i(10,23),Vector2i(9,22),Vector2i(9,22),Vector2i(6,23),Vector2i(7,23)],
			[Vector2i(9,22),Vector2i(6,18),Vector2i(6,22)],
			[Vector2i(9,23),Vector2i(9,23),Vector2i(9,23),Vector2i(8,23),Vector2i(9,23),Vector2i(9,23),Vector2i(9,23)],
			[Vector2i(8,23),Vector2i(9,23)],
			[Vector2i(9,23),Vector2i(6,24),Vector2i(8,24),Vector2i(6,28),Vector2i(7,29),Vector2i(7,29)],
		]
		var tail_color: Color = color.darkened(0.12)
		tail_color = Color.from_rgba8(tail_color.r8,tail_color.g8,tail_color.b8)
		for row in range(landmarks.size()):
			for column in range(landmarks[row].size()):
				var point: Vector2i = landmarks[row][column]+Vector2i(column*32,row*32)
				expect(knight.get_pixelv(point).is_equal_approx(tail_color), "Horse tail recolors in every animation frame")
		for point in [Vector2i(19,19),Vector2i(16,20),Vector2i(16,22)]:
			expect(knight.get_pixelv(point) == Color("373757"), "Horse tack and rider trim keep their original color")
	expect(Library.clip(2,"hurt") == [5,3,12.0] and Library.clip(2,"death") == [6,4,10.0], "Replacement warrior uses the new hurt and death rows")

func fixture(attacker: int, defender: int) -> void:
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for x in range(4): game.cells[Vector2i(x, 0)] = game.rules.make_cell(0 if x < 2 else 1)
	game.rules.rebuild_kingdoms()
	game.cells[Vector2i.ZERO].unit = attacker
	game.cells[Vector2i(2, 0)].unit = defender
	game.view.render_cells(game.cells)

func run() -> void:
	asset_checks()
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	fixture(2, 1)
	var actor: Node3D = game.view.unit_actors[Vector2i.ZERO]
	var animator = actor.get_node("UnitAnimation")
	expect(not animator.is_processing(), "Ready idle uses a shared clock instead of per-unit processing")
	animator.play("run", true)
	animator.advance(0.21)
	expect(animator.frame_index == 2, "Run animation advances through the sheet")
	animator.advance(0.6)
	expect(animator.frame_index == 2, "Run animation loops without blank trailing cells")
	animator.play("hurt")
	animator.advance(0.4)
	expect(animator.animation == "idle" and not actor.get_meta("sprite_action_active"), "Hurt recovers to a batchable idle pose")
	animator.play("death", false, true)
	animator.advance(2)
	expect(animator.animation == "death" and animator.frame_index == 3 and not animator.is_processing(), "Death holds its last valid frame")
	game.view.cancel_motion(game.cells)
	expect(animator.animation == "idle" and actor.visible, "Cancellation restores a dying defender to idle")
	animator.face(actor.global_position - game.view.camera.global_basis.x)
	expect(animator.sprite.flip_h, "Facing follows the camera's horizontal axis")
	game.view.unit_batches.queue_sync()
	game.view.unit_batches.sync(true)
	var mirrored := false
	for material in game.view.unit_batches.sprite_materials.values():
		if material.albedo_texture == animator.sprite.texture and material.uv1_scale.x == -1: mirrored = true
	expect(mirrored, "Settled batches retain the actor's facing")
	game.view.playback.set_speed_scale(6)
	animator.play("run", true)
	animator._process(0.05)
	expect(animator.frame_index == 3, "Fast playback accelerates sprite frames with movement")
	animator.play("idle")
	game.view.playback.set_speed_scale(1)
	animator.play("run", true)
	paused = true
	await create_timer(0.15, true).timeout
	expect(animator.frame_index == 0, "Pausing freezes action frames with the board")
	paused = false
	animator.play("idle")
	for duel in [false, true]:
		fixture(3 if duel else 2, 3 if duel else 1)
		var target := Vector2i(2, 0)
		var defender: Node3D = game.view.unit_actors[target]
		var attacker: Node3D = game.view.unit_actors[Vector2i.ZERO]
		var impact_seen := [false]
		var inspect := func(_action, stage):
			if stage != "impact": return
			impact_seen[0] = true
			expect(defender.visible and defender.get_node("UnitAnimation").animation == "death", "Impact plays the defender's death animation")
			expect(defender.get_node("UnitAnimation").sprite.layers != 0, "Dying defenders leave static batches immediately")
			if duel: expect(attacker.get_node("UnitAnimation").animation == "death", "Both knights die in a duel")
		game.view.motion_stage.connect(inspect)
		var action: Dictionary = game.rules.perform_move(Vector2i.ZERO, target)
		await game.view.animate_moves([action], game.cells)
		game.view.motion_stage.disconnect(inspect)
		expect(impact_seen[0] and game.view.cells == game.cells, "Animated combat ends at the committed board")
		expect(game.view.unit_actors.size() == (0 if duel else 1), "Combat removes exactly the defeated actors")
	fixture(1, 0)
	var dead: Node3D = game.view.unit_actors[Vector2i.ZERO]
	game.cells[Vector2i.ZERO].unit = 0
	game.cells[Vector2i.ZERO].grave = true
	game.view.play_preparation([{"kind":"death", "coord":Vector2i.ZERO}], game.cells)
	expect(dead.visible and dead.get_node("UnitAnimation").animation == "death", "Starvation also plays the death clip before removal")
	while game.view.is_animating: await process_frame
	expect(not game.view.unit_actors.has(Vector2i.ZERO) and game.view.cells == game.cells, "Starvation playback finishes on the final grave tile")
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(0.3).timeout
	print("Unit sprite checks: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)
