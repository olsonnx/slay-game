extends SceneTree
const Terrain = preload("res://src/rendering/terrain_chunks.gd")
const Snapshot = preload("res://src/game/state_snapshot.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func run() -> void:
	var video = root.get_node("Video")
	var original_path: String = video.settings_path
	video.settings_path = "res://artifacts/test-tile-materials.cfg"
	video.set_preference(&"level_transitions", false, false)
	video.set_preference(&"plastic_tiles", true, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var board = game.view
	var before := Snapshot.capture(game.rules)
	var retained: Dictionary = board.tile_nodes.duplicate()
	var coord: Vector2i = game.active_capital()
	var tile: Node3D = board.tile_nodes[coord]
	var top: MeshInstance3D = tile.get_meta("surface")
	var earth: MeshInstance3D = tile.get_meta("earth")
	var options = load("res://src/ui/options_view.gd").new()
	root.add_child(options)
	await process_frame
	expect(top.material_override.roughness <= 0.35 and earth.material_override.roughness > 0.7, "Plastic tops have a restrained stronger sheen while bases remain matte")
	video.set_preference(&"plastic_tiles", false, false)
	expect(not board.plastic_tiles and is_equal_approx(top.material_override.roughness, 0.92) and earth.material_override.albedo_color == Color("776a51"), "Disabling plastic immediately restores original matte tops and brown bases")
	var arrays: Array = top.mesh.surface_get_arrays(0)
	var has_bevel := false
	for normal in arrays[Mesh.ARRAY_NORMAL]:
		if normal.y > 0.05 and normal.y < 0.95: has_bevel = true
	expect(not has_bevel, "Original tiles have no bevels")
	video.set_preference(&"plastic_tiles", true, false)
	expect(board.plastic_tiles and top.material_override.roughness <= 0.35 and earth.material_override.albedo_color == Terrain.BASE_COLOR, "Reenabling plastic restores the new finish")
	expect(Snapshot.capture(game.rules) == before and board.tile_nodes == retained, "Switching finishes retains game state, RNG and tile nodes")
	board.value_heatmap.set_active(true)
	video.set_preference(&"plastic_tiles", false, false)
	expect(board.value_heatmap.active, "Changing finish preserves an active value overlay")
	board.value_heatmap.set_active(false)
	expect(is_equal_approx(top.material_override.roughness, 0.92), "Closing the overlay restores the selected finish")
	var decor = load("res://src/rendering/decorative_map.gd").new()
	decor.initial_seed = 42
	root.add_child(decor)
	expect(not decor.plastic_tiles, "New menu scenery honors the saved finish")
	video.set_preference(&"plastic_tiles", true, false)
	decor.apply_background()
	expect(decor.plastic_tiles, "Existing menu scenery switches finish immediately")
	for slot in decor.slots.values():
		if not slot.node.has_meta("earth"): continue
		expect(slot.node.get_meta("earth").material_override.albedo_color == Terrain.BASE_COLOR, "Menu bases update to rubber too")
		break
	video.set_preference(&"plastic_tiles", false, false)
	expect(video.flush_settings() == OK, "Tile preference saves")
	video.set_preference(&"plastic_tiles", true, false)
	expect(video.load_settings(video.settings_path) == OK and not video.plastic_tiles, "Saved tile preference survives a reload")
	video.set_preference(&"plastic_tiles", "invalid", false)
	expect(not video.plastic_tiles, "Invalid tile preferences are rejected")
	video.save_timer.stop()
	DirAccess.remove_absolute(video.settings_path)
	video.settings_path = original_path
	video.set_preference(&"plastic_tiles", true, false)
	decor.queue_free()
	options.queue_free()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Tile material checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
