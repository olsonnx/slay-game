extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func compare_economy(game) -> void:
	var full = Rules.new()
	full.rule_mode = game.rules.rule_mode
	full.faction_count = game.rules.faction_count
	full.cells = game.view.cells.duplicate(true)
	full.kingdoms = game.playback_kingdoms.duplicate(true)
	full.mana_by_faction = game.playback_mana.duplicate()
	full.rebuild_kingdoms()
	var partial = game.visible_economy()
	var owner: int = game.view.cells.get(game.inspected_hex, {}).get("owner", -2)
	for kingdom in full.kingdoms.values():
		if kingdom["owner"] != 0 and kingdom["owner"] != owner: continue
		var current: Dictionary = partial.kingdoms.get(kingdom["capital"], {})
		expect(not current.is_empty(), "Readout retains complete player/inspected kingdoms")
		if current.is_empty(): continue
		expect(current == kingdom, "Readout preserves capitals, territory ordering and treasury")
		expect(partial.income(current) == full.income(kingdom), "Readout preserves income")
		expect(partial.upkeep(current) == full.upkeep(kingdom), "Readout preserves bridge support wages")
	expect(partial.mana_summary(0) == full.mana_summary(0), "Readout preserves player mana")
func run() -> void:
	var economy_script = preload("res://src/game/visible_economy.gd")
	var tracker = economy_script.new()
	var fixture = Fixture.crowded("huge", 71, 120)
	var visible_cells: Dictionary = fixture.cells.duplicate(true)
	var banks: Dictionary = fixture.kingdoms.duplicate(true)
	var inspected := Vector2i(999, 999)
	var full_signature: Array = economy_script.signature(visible_cells, banks, 0, inspected, inspected, 1, 1)
	expect(tracker.scoped_signature(visible_cells, banks, 0, inspected, inspected, 1, 1, {}) == full_signature, "Economy cache initializes from a complete snapshot")
	for point in visible_cells:
		var cell: Dictionary = visible_cells[point]
		if economy_script.relevant(point, cell, 0, inspected, -2): continue
		var retained: Array = tracker.cached_signature
		cell["moved"] = not cell["moved"]
		expect(is_same(tracker.scoped_signature(visible_cells, banks, 0, inspected, inspected, 1, 1, {point:true}), retained), "Unrelated enemy movement reuses the economy signature")
		break
	for point in visible_cells.keys():
		visible_cells[point]["moved"] = not visible_cells[point]["moved"]
		if point.x % 3 == 0: visible_cells[point]["owner"] = 0
		if point.x % 7 == 0: visible_cells[point]["building"] = "bridge"
		if point.x % 11 == 0: visible_cells[point]["owner"] = 2
		var expected: Array = economy_script.signature(visible_cells, banks, 0, inspected, inspected, 1, 1)
		expect(tracker.scoped_signature(visible_cells, banks, 0, inspected, inspected, 1, 1, {point:true}) == expected, "Scoped readout matches full scan for movement, captures and bridges")
	var erased: Vector2i = visible_cells.keys()[0]
	visible_cells.erase(erased)
	expect(tracker.scoped_signature(visible_cells, banks, 0, inspected, inspected, 1, 1, {erased:true}) == economy_script.signature(visible_cells, banks, 0, inspected, inspected, 1, 1), "Removed territory invalidates cached readout")
	for bank in banks.values(): bank["gold"] += 1
	inspected = visible_cells.keys()[0]
	expect(tracker.scoped_signature(visible_cells, banks, 0, inspected, inspected, 2, 2, {erased:true}) == economy_script.signature(visible_cells, banks, 0, inspected, inspected, 2, 2), "Treasury, inspection and turn context invalidate cached readout")
	var video = root.get_node("Video")
	var transitions: bool = video.level_transitions
	video.set_preference(&"level_transitions", false, false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.rules = Fixture.crowded("huge", 71, 120)
	game.new_game(71, true, false)
	var board = game.view
	game.busy = true
	game.active_faction = 1
	game.playback_kingdoms = game.rules.kingdoms.duplicate(true)
	game.playback_mana = game.rules.mana_by_faction.duplicate()
	for faction in range(6):
		for coord in board.cells:
			if board.cells[coord]["owner"] == faction:
				game.inspected_hex = coord
				break
		compare_economy(game)
	game.busy = false
	game.inspected_hex = game.NONE
	var coord: Vector2i = board.cells.keys()[0]
	var tile: Node3D = board.tile_nodes[coord]
	var untouched: Vector2i = board.cells.keys()[-1]
	var untouched_record: Dictionary = board.cells[untouched]
	var snapshot: Dictionary = board.cells.duplicate(true)
	snapshot[coord]["owner"] = (snapshot[coord]["owner"] + 1) % 6
	board.render_cells(snapshot)
	board.flush_batch_update()
	expect(board.tile_nodes[coord] == tile, "Ownership changes retain the tile hierarchy")
	expect(is_same(board.cells[untouched], untouched_record), "Unchanged visible records are retained")
	snapshot[coord]["value"] += 1
	expect(board.cells[coord]["value"] != snapshot[coord]["value"], "Changed records are isolated from authoritative mutations")
	# A pure tint must preserve the merged terrain mesh and vertex geometry.
	var surface: MeshInstance3D = tile.get_meta("surface")
	var builds: int = board.static_batches.terrain_rebuild_count
	surface.material_override = board.tile_material(Color(0.17, 0.31, 0.53))
	board.mark_batch_dirty(coord)
	board.notify_visible_board_changed()
	board.flush_batch_update()
	expect(board.static_batches.terrain_rebuild_count == builds, "Color-only updates preserve terrain buffers")
	expect(board.static_batches.last_tiles_scanned < board.tile_nodes.size(), "Incremental scans visit only touched chunks")
	if "--preview" in OS.get_cmdline_user_args():
		root.size = Vector2i(1920, 1080)
		board.focus = board.coord_position(coord)
		board.zoom = 16
		board.update_camera()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/capture_color_buffer.png")
	# Compare incremental army buffers with a complete authoritative rescan.
	board.unit_batches.sync()
	var unit_coord: Vector2i = board.unit_actors.keys()[0]
	var unit_change: Dictionary = {unit_coord: board.cells[unit_coord].duplicate(true)}
	unit_change[unit_coord]["moved"] = not unit_change[unit_coord]["moved"]
	board.render_cells(unit_change, true)
	board.flush_batch_update()
	board.unit_batches.sync(true)
	var scoped_army: Dictionary = {}
	for key in board.unit_batches.batches:
		scoped_army[key] = board.unit_batches.batches[key].get_meta("signature").duplicate(true)
	board.unit_batches.sync()
	for key in board.unit_batches.batches:
		expect(scoped_army.get(key, []) == board.unit_batches.batches[key].get_meta("signature"), "Scoped army buffers match a complete rescan")
	# Check a generated crystal in this retained-board fixture.
	for point in board.cells:
		if not board.cells[point].get("mana_source", false) or board.cells[point]["capital"] >= 0: continue
		var crystal: Node3D = board.tile_nodes[point].get_node("ManaSource")
		var crystal_cell: Dictionary = board.cells[point].duplicate(true)
		crystal_cell["unit"] = 1 if crystal_cell["unit"] == 0 else 0
		board.render_cells({point: crystal_cell}, true)
		expect(board.tile_nodes[point].get_node("ManaSource") == crystal, "Unit occupancy changes retain crystal geometry and lighting source")
		break
	var scoped_lights: Dictionary = board.lighting.sources_by_coord.duplicate(true)
	var scoped_birds: Dictionary = board.birds.stationary_units.duplicate(true)
	board.lighting.refresh_sources()
	board.birds.track_units()
	expect(board.lighting.sources_by_coord == scoped_lights, "Scoped light discovery matches a complete rescan")
	expect(board.birds.stationary_units == scoped_birds, "Scoped bird tracking matches a complete rescan")
	for point in board.cells:
		if board.cells[point].get("mana_source", false) or board.cells[point]["capital"] >= 0: continue
		var light_cell: Dictionary = board.cells[point].duplicate(true)
		light_cell["mana_source"] = true
		board.render_cells({point: light_cell}, true)
		expect(board.lighting.sources_by_coord.get(point, {}).get("mana", false), "Scoped updates discover a new crystal light")
		light_cell["mana_source"] = false
		board.render_cells({point: light_cell}, true)
		expect(not board.lighting.sources_by_coord.has(point), "Scoped updates retire a removed crystal light")
		break
	# A tiny budget processes one coherent chunk and leaves the rest queued.
	for point in board.tile_nodes:
		board.mark_batch_dirty(point)
	board.batch_update_pending = true
	board.batch_last_flush_frame = -1
	var pending: int = board.batch_dirty_ids.size()
	board.flush_batch_update(1)
	expect(board.batch_update_pending and board.batch_dirty_ids.size() < pending, "Budgeted uploads make progress without processing the whole island")
	board.flush_batch_update()
	expect(not board.batch_update_pending, "Explicit flush drains every queued chunk")
	var visible_events := [0]
	var count_event := func(): visible_events[0] += 1
	board.visible_board_changed.connect(count_event)
	board.render_cells(board.cells)
	board.visible_board_changed.disconnect(count_event)
	expect(visible_events[0] == 0, "Unchanged settlement snapshots skip board listeners")
	board.remove_tile(coord)
	board.cells.erase(coord)
	board.notify_visible_board_changed()
	board.flush_batch_update()
	for entry in board.static_batches.tile_records.values():
		expect(is_instance_valid(entry["records"][0][0]), "Removal clears obsolete cached sources")
	# Neutral bridges connect player banks; hostile garrisons still have support
	# semantics independent of the inspected faction.
	var bridge_model = Rules.new()
	bridge_model.rule_mode = "modern"
	bridge_model.faction_count = 3
	for q in range(9):
		bridge_model.cells[Vector2i(q, 0)] = bridge_model.make_cell(0 if q < 3 or q > 5 else 1)
	bridge_model.cells[Vector2i(3, 0)]["owner"] = -1
	bridge_model.cells[Vector2i(3, 0)]["building"] = "bridge"
	bridge_model.cells[Vector2i(3, 0)]["unit"] = 2
	bridge_model.cells[Vector2i(3, 0)]["unit_owner"] = 0
	bridge_model.rebuild_kingdoms()
	game.rules = bridge_model
	board.render_cells(bridge_model.cells)
	game.playback_kingdoms = bridge_model.kingdoms.duplicate(true)
	game.playback_mana = bridge_model.mana_by_faction.duplicate()
	game.active_faction = 1
	game.inspected_hex = Vector2i(4, 0)
	compare_economy(game)
	var retired_sprite := Sprite3D.new()
	board.unit_presentation.units.append(retired_sprite)
	retired_sprite.free()
	await board.retire_cells()
	expect(board.units.is_empty() and board.unit_actors.is_empty() and board.tile_nodes.is_empty(), "Covered retirement clears stale sprite and actor registries")
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.20).timeout
	video.set_preference(&"level_transitions", transitions, false)
	print("Capture update checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
