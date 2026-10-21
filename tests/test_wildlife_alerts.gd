extends SceneTree

const Wildlife = preload("res://src/game/wildlife.gd")
var game
var checks := 0
var failures := 0
const SOURCE := Vector2i.ZERO
const HOME := Vector2i(-1,0)
const PREY := Vector2i(3,0)
const FOREST := Vector2i(1,0)

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture(kind: String, prey := true) -> void:
	game.view.cancel_motion({})
	var s = game.rules
	s.rule_mode = "modern"
	s.cells.clear()
	s.kingdoms.clear()
	for q in range(-5,6):
		for r in range(-5,6):
			var coord := Vector2i(q,r)
			if s.distance(coord,SOURCE) <= 5: s.cells[coord] = s.make_cell()
	s.cells[HOME]["lair"] = kind
	s.cells[SOURCE]["animal"] = kind
	s.cells[SOURCE]["animal_home"] = HOME
	if prey:
		s.cells[PREY].owner = 1
		if kind == "boar": s.cells[PREY].building = "house"
		else: s.cells[PREY].unit = 1
		s.cells[FOREST].tree = true
	game.view.render_cells(s.cells)
	game.view.stop_camera_pan()
	game.view.focus = game.view.coord_position(FOREST)
	game.view.zoom = 8.0
	game.view.update_camera()

func capture(path: String) -> void:
	if "--preview" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)

func wait_for_world() -> void:
	while game.view.is_animating: await process_frame

func run() -> void:
	root.size = Vector2i(1200,800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.camera_follow_suspended = true
	await process_frame
	game.playback_speed.set_process(false)
	game.view.birds.set_loading(true)
	var wildlife = game.view.wildlife
	# Inspect every shipped pose against its original alpha bounds. This
	# catches both accidental blank atlas frames and clipped standing poses.
	for kind in Wildlife.KINDS:
		for pose in wildlife.CLIPS[kind]:
			var clip: Array = wildlife.animation_clip(kind,pose)
			for index in range(clip[1]):
				var data: Dictionary = wildlife.frame(kind,pose,index)
				var full: Image = wildlife.SHEETS[kind].get_image().get_region(Rect2i(index*32,int(clip[0])*32,32,32))
				expect(data.image.get_used_rect().has_area(),"Every %s %s frame contains visible artwork" % [kind,pose])
				expect(full.get_used_rect().position.y >= clip[3],"Frame cropping preserves all %s %s artwork" % [kind,pose])
	for kind in Wildlife.KINDS:
		fixture(kind)
		var actions: Array = Wildlife.world_turn(game.rules)
		var actor: Node3D = wildlife.actors[HOME]
		var initial_position := actor.position
		expect(actor.get_node("Aggro") is Sprite3D and actor.get_node("Aggro").texture.resource_path == "res://assets/ui/exclamation.png","Warnings use the supplied pixel art")
		expect(actions.size() == 2 and actions[0].alert,"First acquisition alerts before pursuing a target")
		wildlife.play_world(actions,game.cells)
		expect(actor.get_meta("pose") == "alert" and actor.get_node("Aggro").visible,"Alert playback shows a visible warning before moving")
		game.view.playback.set_speed_scale(0)
		var clock: float = wildlife.elapsed
		await create_timer(0.08).timeout
		expect(wildlife.elapsed == clock and actor.position == initial_position,"Playback pause freezes the alert pose and movement together")
		game.view.playback.set_speed_scale(1)
		await create_timer(0.45 if kind == "bear" else 0.50 if kind == "wolf" else 0.20).timeout
		expect(actor.position == initial_position,"The alert animation finishes before the animal advances")
		var sprite: Sprite3D = wildlife.sprite_for(actor)
		if kind == "bear": expect(sprite.texture.region.size.y == 24,"The standing bear receives enough vertical space")
		await capture("res://artifacts/wildlife-%s-alert.png" % kind)
		await wait_for_world()
		expect(not game.view.cells[FOREST].tree and not game.view.tile_nodes[FOREST].has_node("Features/Tree"),"Tree destruction updates both visible cells and tree geometry")
		expect(actor.get_node("Aggro").visible and actor.get_meta("aggro_target") == PREY,"The warning remains visible between turns during pursuit")
		await capture("res://artifacts/wildlife-%s-pursuit.png" % kind)
		for turn in range(1):
			var continued: Array = Wildlife.world_turn(game.rules)
			expect(not continued[0].alert,"The same pursuit does not repeatedly play the alert pose")
			await wildlife.play_world(continued,game.cells)
		expect(game.view.cells[PREY].owner == -1 and game.view.cells[PREY].unit == 0 and game.view.cells[PREY].building == "","Attacking prey updates units, buildings and ownership visually")
		expect(not actor.get_node("Aggro").visible,"Defeating the target removes the warning")
		# Seeking/cancelling in the middle of a telegraph cannot leave a warning,
		# a delayed raid, or a tween that shifts the restored animal afterwards.
		fixture(kind)
		var before: Dictionary = game.view.cells.duplicate(true)
		var cancelled: Array = Wildlife.world_turn(game.rules)
		wildlife.play_world(cancelled,game.cells)
		await process_frame
		game.view.cancel_motion(before)
		await create_timer(1.1).timeout
		actor = wildlife.actors[HOME]
		expect(not game.view.is_animating and actor.position == game.view.coord_position(SOURCE) and not actor.get_node("Aggro").visible and game.view.cells == before,"Cancelling an alert restores the animal and prevents late visual changes")
		fixture(kind,false)
		before = game.view.cells.duplicate(true)
		cancelled = Wildlife.world_turn(game.rules)
		wildlife.play_world(cancelled,game.cells)
		await create_timer(0.08).timeout
		game.view.cancel_motion(before)
		await create_timer(0.35).timeout
		expect(wildlife.actors[HOME].position == game.view.coord_position(SOURCE),"Cancelling an in-flight World movement kills its tween")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Wildlife alert checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
