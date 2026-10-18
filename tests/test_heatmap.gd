extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event

func run() -> void:
	var keys = root.get_node("Keys")
	var original_bindings: Dictionary = keys.bindings.duplicate()
	var older := ConfigFile.new()
	older.set_value("keys", "recruit", KEY_F)
	older.save("res://artifacts/heatmap_old_keys.cfg")
	keys.load_settings("res://artifacts/heatmap_old_keys.cfg")
	expect(keys.bindings["recruit"] == KEY_F and keys.bindings["heatmap"] == KEY_H, "New heatmap action preserves an older customised F binding")
	keys.reset_defaults(false)
	var video = root.get_node("Video")
	var original_background: String = video.background
	var sound = root.get_node("Sound")
	var muted: bool = sound.is_muted()
	sound.set_muted(true, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var a := Vector2i.ZERO
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var mountain := Vector2i(0, 1)
	var bridge := Vector2i(1, 1)
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for coord in [a, b, c, mountain, bridge]:
		game.cells[coord] = game.rules.make_cell(0 if coord in [a, b] else 1 if coord == c else -1)
	game.cells[a]["unit"] = 3
	game.cells[a]["tree"] = true
	game.cells[a]["value"] = 3
	game.cells[b]["value"] = 1
	# Keep the authored tree/unit fixture independent of replacement-capital safety.
	game.cells[b]["capital"] = 0
	game.cells[c]["value"] = 3
	game.cells[mountain]["mountain"] = true
	game.cells[mountain]["value"] = 0
	game.cells[bridge]["building"] = "bridge"
	game.cells[bridge]["land"] = false
	game.cells[bridge]["value"] = 0
	game.rules.rebuild_kingdoms()
	game.active_hex = a
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var before: Dictionary = game.cells.duplicate(true)
	var rng_before: int = game.rules.rng.state
	var camera_before: Transform3D = game.view.camera.transform
	var heatmap = game.view.value_heatmap
	var original_tile: Node3D = game.view.tile_nodes[b]
	var original_surface: MeshInstance3D = original_tile.get_meta("surface")
	var original_mesh: Mesh = original_surface.mesh
	var original_material: Material = original_surface.material_override
	game._unhandled_input(key(KEY_F))
	expect(heatmap.active and game.heatmap_legend.visible and game.heatmap_button.button_pressed, "F enables heatmap and legend/button feedback")
	expect(game.heatmap_button.size == game.view_button.size and game.heatmap_button.icon != null, "Heatmap icon button matches camera button dimensions")
	expect(game.cells == before and game.rules.rng.state == rng_before and game.view.camera.transform == camera_before, "Heatmap leaves rules, RNG and camera untouched")
	expect(game.view.board_root.visible and not game.view.animation_root.visible and not game.view.overlay_root.visible, "Original 3D terrain stays visible while units/action clutter are hidden")
	expect(heatmap.tiles.size() == game.cells.size(), "Every occupied tile has a value surface and number")
	expect(heatmap.maximum == 3, "Scale uses highest visible province value")
	expect(game.view.tile_nodes[b] == original_tile and original_surface.mesh == original_mesh, "Filter preserves the actual raised terrain geometry")
	expect(original_surface.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "Value tint uses the standard lit material")
	expect(game.view.tile_nodes[mountain].get_node("Features").is_visible_in_tree(), "Mountain relief remains three-dimensional")
	expect(not game.view.tile_nodes[a].get_node("Features/Tree").visible and not game.view.unit_actors[a].visible, "Trees and units are selectively hidden")
	expect(not heatmap.tiles[b].get_node("Value").visible, "Numerical clutter is absent until hover")
	heatmap.set_hovered(b)
	expect(heatmap.tiles[b].get_node("Value").visible and not heatmap.tiles[a].get_node("Value").visible, "Only the hovered tile shows its value number")
	heatmap.set_hovered(game.NONE)
	expect(game.view.tile_nodes[mountain].get_meta("surface").material_override.albedo_color == Color.BLACK and heatmap.tiles[bridge].get_node("Value").text == "0", "Mountains and bridges have zero-value black tiles")
	expect(game.view.tile_nodes[b].get_meta("surface").material_override.albedo_color == heatmap.LOW, "Value one is red")
	expect(game.view.tile_nodes[c].get_meta("surface").material_override.albedo_color == heatmap.HIGH, "Highest available value is green")
	expect(heatmap.tiles[a].get_node("Value").text == "3", "Trees do not replace underlying province value with income zero")
	expect(heatmap.borders.get_meta("edge_count") == 16, "Kingdom borders omit shared edges within a kingdom")
	var point: Vector2 = game.view.camera.unproject_position(game.view.coord_position(a))
	var hit: Dictionary = game.view.pick_at_screen(point)
	expect(hit["kind"] == "terrain" and hit["coord"] == a, "Hidden props and units cannot steal heatmap tile clicks")
	var retained: Node = heatmap.tiles[a]
	var border_mesh: Mesh = heatmap.borders.mesh
	heatmap.sync()
	expect(heatmap.tiles[a] == retained and heatmap.borders.mesh == border_mesh, "Unchanged heatmap retains nodes and boundary mesh")
	game.cells[b]["value"] = 6
	game.view.render_cells(game.cells)
	expect(heatmap.maximum == 6 and game.heatmap_max_label.text == "6", "Value updates change highest value and legend live")
	expect(game.view.tile_nodes[b].get_meta("surface").material_override.albedo_color == heatmap.HIGH and game.view.tile_nodes[a].get_meta("surface").material_override.albedo_color != heatmap.HIGH, "Higher development renormalizes the whole scale")
	expect(heatmap.tiles[a] == retained and heatmap.borders.mesh == border_mesh, "Value-only update retains geometry and boundaries")
	game.hovered = b
	game.show_world_tip()
	expect(game.tip_label.get_parsed_text().contains("Value 6") and not game.tip_label.get_parsed_text().contains("Defence"), "Heatmap hover describes value rather than hidden combat details")
	game.world_tip.hide()
	game._input(key(KEY_TAB))
	expect(game.view.top_down and heatmap.active, "Camera view and heatmap can be combined")
	game._input(key(KEY_TAB))
	for background in ["water", "sky"]:
		video.set_preference(&"background", background, false)
		expect(game.view.water.visible == (background == "water") and game.view.sky_backdrop.visible == (background == "sky"), "Existing Water/Sky atmosphere stays visible in the value filter")
	game.cells[c]["unit"] = 1
	game.view.render_cells(game.cells)
	var defender: Node3D = game.view.unit_actors[c]
	defender.name = "Renamed defender"
	var switch_at_arrival := func(_action: Dictionary, stage: String):
		if stage == "occupy":
			heatmap.set_active(false)
			expect(not defender.visible, "Exiting the filter during occupation never resurrects the defeated defender")
			heatmap.set_active(true)
	game.view.motion_stage.connect(switch_at_arrival)
	var capture: Dictionary = game.rules.perform_move(a, c)
	expect(not capture.is_empty(), "Capture fixture produces a movement")
	heatmap.sync()
	expect(heatmap.borders.mesh == border_mesh, "Preplanned rules changes do not leak future ownership into the heatmap")
	game.busy = true
	game.playback_speed._input(key(KEY_CTRL))
	await game.view.animate_moves([capture], game.cells)
	game.view.motion_stage.disconnect(switch_at_arrival)
	game.busy = false
	game.refresh_ui()
	expect(heatmap.active and game.view.board_root.visible and heatmap.borders.get_meta("edge_count") == 14, "Capture updates kingdom borders at visible arrival without flashing props")
	game._unhandled_input(key(KEY_F))
	expect(not heatmap.active and not game.heatmap_legend.visible and game.view.board_root.visible and game.view.animation_root.visible and game.view.sky_backdrop.visible, "F restores normal terrain/details and latest background setting")
	expect(original_surface.material_override == original_material, "Filter restores the original surface material exactly")
	keys.set_binding("heatmap", KEY_H, false)
	game._unhandled_input(key(KEY_F))
	expect(not heatmap.active, "Old heatmap key stops working after rebind")
	game._unhandled_input(key(KEY_H))
	expect(heatmap.active and game.heatmap_button.tooltip_text.contains("Shortcut: H"), "Rebound heatmap key and tooltip work")
	game.heatmap_button.pressed.emit()
	expect(not heatmap.active, "Icon button toggles heatmap off")
	game.heatmap_button.pressed.emit()
	game.new_game(42)
	expect(not heatmap.active and not game.heatmap_legend.visible, "New game clears the transient heatmap mode")
	expect(heatmap.value_color(1, 1) == heatmap.LOW and heatmap.value_color(0, 0) == Color.BLACK, "Single-value/zero-value maps have stable colors without division by zero")
	game.shutdown()
	game.queue_free()
	await process_frame
	keys.bindings = original_bindings
	keys.changed.emit()
	video.set_preference(&"background", original_background, false)
	sound.stop_all()
	await create_timer(0.1).timeout
	sound.set_muted(muted, false)
	print("Heatmap checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

