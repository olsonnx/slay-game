extends SceneTree

const Wildlife = preload("res://src/game/wildlife.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.size = Vector2i(1200,800)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await tree_growth_checks(game)
	var s = game.rules
	s.rule_mode = "modern"
	s.cells.clear()
	s.kingdoms.clear()
	for q in range(-4,5):
		for r in range(-3,4):
			var coord := Vector2i(q,r)
			if s.distance(coord,Vector2i.ZERO) <= 4: s.cells[coord] = s.make_cell()
	var homes := [Vector2i(-2,0),Vector2i(0,0),Vector2i(2,0)]
	for index in range(3):
		s.cells[homes[index]]["lair"] = Wildlife.KINDS[index]
		s.cells[homes[index]]["lair_wait"] = 0
	game.view.render_cells(s.cells)
	var wildlife = game.view.wildlife
	expect(wildlife.actors.is_empty(),"Lairs start without animals")
	if "--preview" in OS.get_cmdline_user_args():
		game.view.stop_camera_pan()
		game.view.focus = game.view.coord_position(Vector2i.ZERO)
		game.view.zoom = 9.0
		game.view.update_camera()
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/wildlife-lairs-preview.png")
	var simulator = s.KingdomAI.new(s)
	var actions: Array = await simulator.world_async(game.ai_execution())
	expect(actions.size() == 3,"First World turn emerges all three species")
	await wildlife.play_world(actions,simulator.preparation_cells(),simulator.presentation_patch_ready)
	expect(wildlife.actors.size() == 3 and not wildlife.is_playing and not game.view.is_animating,"World playback creates three actors and releases its animation lock")
	for home in homes:
		var actor: Node3D = wildlife.actors[home]
		var coord: Vector2i = actor.get_meta("hex")
		expect(actor.position == game.view.coord_position(coord) and s.distance(coord,home) == 1,"Animal actor occupies a neighboring province")
		var sprite: Sprite3D = wildlife.sprite_for(actor)
		expect(sprite.texture != null and sprite.get_meta("image").get_size() == Vector2i(32,20),"Each species has a cropped, pickable sprite frame like infantry")
		for pose in ["idle","run","attack","death"]:
			var data: Dictionary = wildlife.frame(actor.get_meta("kind"),pose,2)
			expect(not data.image.is_empty() and data.texture.region.size == Vector2(32,20),"All animation clips have valid frames")
		var cave: Node3D = game.view.tile_nodes[home].get_node("Features/WildlifeLair")
		expect(cave.get_child(0).material_override.albedo_color.a == 1.0,"Caves remain fully visible beside their animals")
	# Idle poses follow real time while action poses follow accelerated playback.
	var saved_elapsed: float = wildlife.elapsed
	var saved_idle: float = wildlife.idle_elapsed
	var saved_speed: float = game.view.playback.speed_scale
	wildlife.elapsed = 0.0
	wildlife.idle_elapsed = 0.0
	game.view.playback.set_speed_scale(1.0)
	wildlife._process(0.19)
	for home in homes:
		var actor: Node3D = wildlife.actors[home]
		expect(wildlife.sprite_for(actor).texture == wildlife.frame(actor.get_meta("kind"),"idle",1).texture,"Animal idle advances at its normal frame rate")
	game.view.playback.set_speed_scale(6.0)
	wildlife._process(0.19)
	for home in homes:
		var actor: Node3D = wildlife.actors[home]
		expect(wildlife.sprite_for(actor).texture == wildlife.frame(actor.get_meta("kind"),"idle",2).texture,"Ctrl speed-up leaves animal idle animation at normal speed")
		actor.set_meta("pose","attack")
		actor.set_meta("pose_time",wildlife.elapsed)
	wildlife._process(0.035)
	for home in homes:
		var actor: Node3D = wildlife.actors[home]
		expect(wildlife.sprite_for(actor).texture == wildlife.frame(actor.get_meta("kind"),"attack",2).texture,"Animal action animations still accelerate with playback")
		actor.set_meta("pose","idle")
	wildlife.elapsed = saved_elapsed
	wildlife.idle_elapsed = saved_idle
	game.view.playback.set_speed_scale(saved_speed)
	for actor in wildlife.actors.values(): wildlife.set_frame(actor)
	game.view.stop_camera_pan()
	var saved_yaw: float = game.view.yaw
	var saved_pitch: float = game.view.pitch
	for angle in [Vector2(0.18,0.92),Vector2(1.7,0.45),Vector2(3.4,1.37),Vector2(0,deg_to_rad(89.9))]:
		game.view.yaw = angle.x
		game.view.pitch = angle.y
		game.view.update_camera()
		await process_frame
		await process_frame
		for home in homes:
			var actor: Node3D = wildlife.actors[home]
			var sprite: Sprite3D = wildlife.sprite_for(actor)
			expect(sprite.position.is_equal_approx(Vector3(0,wildlife.UnitSprites.height(2),0)) and is_equal_approx(sprite.pixel_size,wildlife.UnitSprites.pixel_size(2)),"Animal sprites use the same centered position and pixel scale as infantry")
			var image: Image = sprite.get_meta("image")
			var pixels := Vector2(image.get_used_rect().get_center())-Vector2(16,10)
			var screen: Vector2 = game.view.camera.unproject_position(sprite.global_position)+pixels*(root.size.y/game.view.camera.size)*sprite.pixel_size
			expect(game.view.pick_at_screen(screen).coord == actor.get_meta("hex"),"Centered animal pixels remain pickable at every camera angle")
	game.view.yaw = saved_yaw
	game.view.pitch = saved_pitch
	game.view.focus = game.view.coord_position(Vector2i.ZERO)
	game.view.zoom = 12.0
	game.view.update_camera()
	if "--preview" in OS.get_cmdline_user_args():
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/wildlife-preview.png")
	# A deliberate adjacent raid exercises defender death, territory repainting,
	# and actor movement without depending on the random roaming choice.
	var bear_home: Vector2i = homes[0]
	var source: Vector2i = wildlife.actors[bear_home].get_meta("hex")
	var target: Vector2i = s.NONE
	for coord in s.neighbors(source):
		if not Wildlife.present(s.cells[coord]):
			target = coord
			break
	s.cells[target].owner = 0
	s.cells[target].unit = 1
	game.view.render_cells(s.cells)
	var before: Dictionary = s.cells.duplicate(true)
	Wildlife.raid(s,target,"bear")
	s.cells[source].erase("animal")
	s.cells[source].erase("animal_home")
	s.cells[target]["animal"] = "bear"
	s.cells[target]["animal_home"] = bear_home
	var changes := {}
	for coord in s.cells:
		if s.cells[coord] != before[coord]: changes[coord] = s.cells[coord].duplicate(true)
	await wildlife.play_world([{"kind":"attack","source":source,"target":target,"home":bear_home,"animal":"bear","changes":changes}],s.cells)
	expect(game.view.cells[target].owner == -1 and game.view.cells[target].unit == 0,"World attack playback reveals neutralized province and slain defender")
	expect(wildlife.actors[bear_home].get_meta("hex") == target,"Attacker presentation follows the final animal state")
	var empty_cave: Node3D = game.view.tile_nodes[bear_home].get_node("Features/WildlifeLair")
	expect(empty_cave.get_child(0).material_override.albedo_color.a == 1.0,"Caves retain their full appearance during animal actions")
	wildlife.defeat(target)
	expect(wildlife.dying.size() == 1 and wildlife.actors.size() == 2,"A killed animal plays its death separately from living actors")
	await create_timer(0.5).timeout
	expect(wildlife.dying.is_empty(),"Death presentation retires its actor")
	game.view.render_cells(s.cells)
	wildlife.cancel_effects()
	expect(not wildlife.is_playing,"Cancellation releases World presentation state")
	# Cancel a running World tween and ensure its late continuation cannot
	# reapply a province change after restoring the board.
	var visible_before: Dictionary = game.view.cells.duplicate(true)
	var cancelled_action := {"kind":"move","source":target,"target":Vector2i(-1,1),"home":bear_home,"animal":"bear","changes":{}}
	wildlife.play_world([cancelled_action],s.cells)
	await process_frame
	expect(wildlife.is_playing and game.view.is_animating,"World motion locks playback while its tween runs")
	game.view.cancel_motion(visible_before)
	await create_timer(0.35).timeout
	expect(not wildlife.is_playing and not game.view.is_animating and game.view.cells == visible_before,"Cancelled World playback cannot commit late changes")
	if "--preview" in OS.get_cmdline_user_args():
		var coastal: Dictionary = s.cells.duplicate(true)
		coastal[target].erase("animal")
		coastal[target].erase("animal_home")
		coastal[bear_home].erase("lair")
		var edge := Vector2i(0,3)
		var cave_hex := Vector2i(0,2)
		coastal[cave_hex]["lair"] = "bear"
		coastal[edge]["animal"] = "bear"
		coastal[edge]["animal_home"] = cave_hex
		game.view.render_cells(coastal)
		game.view.stop_camera_pan()
		game.view.focus = game.view.coord_position(edge)
		game.view.zoom = 5.0
		game.view.update_camera()
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/wildlife-coastal-centered.png")
	wildlife.clear()
	expect(wildlife.actors.is_empty() and wildlife.dying.is_empty(),"Board retirement clears wildlife actors")
	game.queue_free()
	await process_frame
	await hotseat()
	root.get_node("Sound").stop_all()
	await create_timer(0.1).timeout
	print("Wildlife presentation checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)

func hotseat() -> void:
	var settings = root.get_node("Gameplay")
	var previous_rules: String = settings.rule_mode
	settings.set_rules("modern",false)
	var video = root.get_node("Video")
	var previous_transitions: bool = video.level_transitions
	video.set_preference(&"level_transitions",false,false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await app.start_new_game(42,"large","easy",2,{},2)
	var game = app.game
	var initial: Dictionary = game.cells.duplicate(true)
	var lairs := 0
	for cell in game.cells.values(): lairs += int(cell.get("lair", "") != "")
	expect(lairs > 0 and game.view.wildlife.actors.is_empty(),"A new Modern hotseat map starts with distant, dormant lairs")
	await game.end_turn()
	expect(game.round_number == 1 and game.view.wildlife.actors.is_empty(),"Passing between humans does not run the World early")
	await game.end_turn()
	expect(game.round_number == 2 and game.active_faction == 0 and game.view.wildlife.actors.size() == lairs,"A full hotseat round runs the World once and emerges every animal")
	expect(not game.commands_locked() and not game.view.wildlife.is_playing,"World completion returns playable control to the next human")
	await app.restart_current_level()
	expect(app.game.cells == initial and app.game.view.wildlife.actors.is_empty(),"Restart restores dormant lairs and clears all roaming actors")
	app.queue_free()
	await process_frame
	settings.set_rules(previous_rules,false)
	video.set_preference(&"level_transitions",previous_transitions,false)

func tree_growth_checks(game) -> void:
	var board = game.view
	var cells := {}
	for x in range(5): cells[Vector2i(x,0)] = game.rules.make_cell()
	cells[Vector2i.ZERO].tree = true
	board.render_cells(cells)
	expect(board.playback.growing_trees.is_empty(),"Initial forests are fully grown without arrival animations")
	cells[Vector2i(3,0)].tree = true
	board.render_cells(cells)
	expect(board.playback.growing_trees.is_empty(),"Ordinary board refresh does not animate trees")
	cells[Vector2i(1,0)].tree = true
	cells[Vector2i(2,0)].tree = true
	await board.wildlife.play_world([],cells)
	board.flush_batch_update()
	expect(board.playback.growing_trees.size() == 2,"World settlement animates only newly grown trees, even without animal actions")
	var entries: Dictionary = board.playback.growing_trees.duplicate()
	for entry in entries.values():
		entry.tween.pause()
		var trunk: MeshInstance3D = entry.tree.get_child(1)
		expect(trunk.has_meta("visual_transform") and trunk.global_transform.basis.get_scale().is_equal_approx(Vector3.ONE),"Growth is visual and preserves canonical source geometry")
		expect(trunk.get_meta("visual_transform").basis.get_scale().y < 0.05,"New trees begin as small sprouts")
	await capture_tree_growth(board,"sprout")
	var rebuilds: int = board.static_batches.rebuild_count
	for entry in entries.values():
		entry.tween.custom_step(0.08)
		var trunk: MeshInstance3D = entry.tree.get_child(1)
		var height: float = trunk.get_meta("visual_transform").basis.get_scale().y
		expect(height > 0.05 and height < 1.0,"Tree rises smoothly before settling at full height")
		if DisplayServer.get_name() != "headless":
			var slot: Array = trunk.get_meta("visual_batch_slot")
			var render: MultiMeshInstance3D = slot[0].get_ref()
			var actual: Transform3D = render.global_transform*render.multimesh.get_instance_transform(slot[1])
			expect(actual.is_equal_approx(trunk.get_meta("visual_transform")),"Visible batched tree follows the animated transform")
	await capture_tree_growth(board,"growing")
	expect(board.static_batches.rebuild_count == rebuilds,"Growth updates instance transforms without rebuilding chunks each frame")
	# A neighboring scenery update can republish a chunk during growth.
	cells[Vector2i(4,0)].grave = true
	board.render_cells(cells)
	board.flush_batch_update()
	for entry in entries.values():
		var trunk: MeshInstance3D = entry.tree.get_child(1)
		if DisplayServer.get_name() != "headless":
			var slot: Array = trunk.get_meta("visual_batch_slot")
			var render: MultiMeshInstance3D = slot[0].get_ref()
			expect((render.global_transform*render.multimesh.get_instance_transform(slot[1])).is_equal_approx(trunk.get_meta("visual_transform")),"Chunk publication retains a tree's in-flight growth")
	board.playback.set_speed_scale(6)
	for entry in entries.values():
		entry.tween.custom_step(0.05)
		var trunk: MeshInstance3D = entry.tree.get_child(1)
		expect(not trunk.has_meta("visual_transform"),"Ctrl accelerates tree growth and completed trees restore regular rendering")
	await capture_tree_growth(board,"grown")
	expect(board.playback.growing_trees.is_empty(),"Finished tree growth leaves no animation state")
	board.playback.set_speed_scale(1)
	cells[Vector2i(4,0)].grave = false
	cells[Vector2i(4,0)].tree = true
	await board.wildlife.play_world([],cells)
	board.cancel_motion(cells)
	expect(board.playback.growing_trees.is_empty(),"Cancelling playback settles growing trees")
	cells[Vector2i(1,0)].tree = false
	board.render_cells(cells)
	cells[Vector2i(1,0)].tree = true
	await board.wildlife.play_world([],cells)
	cells[Vector2i(1,0)].tree = false
	board.render_cells(cells)
	expect(board.playback.growing_trees.is_empty(),"Removing a growing tree cleans up its animation")
	board.render_cells(game.rules.cells)

func capture_tree_growth(board, stage: String) -> void:
	if not "--tree-preview" in OS.get_cmdline_user_args(): return
	board.stop_camera_pan()
	board.focus = board.coord_position(Vector2i(2,0))
	board.zoom = 7.0
	board.update_camera()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/tree-growth-%s.png" % stage)
