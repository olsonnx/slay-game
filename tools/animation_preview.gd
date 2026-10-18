extends SceneTree
## Run with --fixed-fps 30, then encode motion_frames/frame_%04d.png at 30 fps.

var recording := true
var frame_number := 0

func _initialize() -> void:
	call_deferred("capture")

func record_frames() -> void:
	while recording:
		await RenderingServer.frame_post_draw
		if not recording:
			break
		root.get_texture().get_image().save_png("res://artifacts/motion_frames/frame_%04d.png" % frame_number)
		frame_number += 1

func capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	DirAccess.make_dir_recursive_absolute("res://artifacts/motion_frames")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	game.view.set_process(false)
	game.rules.generate(42)
	# A labeled demonstration fixture: one long approach and a defended border.
	var target := Vector2i(-2, 0)
	game.cells[target]["owner"] = 1
	game.cells[target]["unit"] = 1
	game.cells[target]["tree"] = false
	var source: Vector2i = game.NONE
	var farthest := -1
	for coord in game.cells:
		if game.cells[coord]["owner"] == 0:
			game.cells[coord]["unit"] = 0
			var distance: int = game.rules.distance(coord, target)
			if game.cells[coord]["capital"] < 0 and distance > farthest:
				farthest = distance
				source = coord
	game.cells[source]["unit"] = 3
	game.rules.rebuild_kingdoms()
	for kingdom in game.rules.kingdoms.values():
		kingdom["gold"] = 36
	game.active_hex = source
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.label_at(game.ui_root, "MOVEMENT PREVIEW", Vector2(30, 82), 11, Color("a7b8ae"))
	record_frames()
	await create_timer(0.5).timeout
	game.click_hex(source)
	await game.click_hex(target)
	await create_timer(0.4).timeout
	await game.end_turn()
	await create_timer(0.65).timeout
	recording = false
	await process_frame
	print("Captured %d motion frames" % frame_number)
	quit()
