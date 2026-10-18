extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	check_complete_islands()
	await check_streamed_cache_budget()
	var video = root.get_node("Video")
	var original_transitions: bool = video.level_transitions
	var original_background: String = video.background
	var original_antialiasing: int = video.antialiasing
	var original_shadows: bool = video.shadows
	var original_borders: float = video.internal_borders
	video.set_preference(&"level_transitions", false, false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var background = app.menus.menu_background
	var map = background.map
	expect(background.active and background.visible and map.active, "Main menu starts decorative world")
	expect(map.sun.shadow_enabled == video.shadows, "Menu shadows follow the initial video preference")
	video.set_preference(&"shadows", false, false)
	expect(not map.sun.shadow_enabled, "Menu shadows disable live")
	video.set_preference(&"shadows", true, false)
	expect(map.sun.shadow_enabled and map.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL, "Menu uses a single orthographic shadow pass")
	video.set_preference(&"shadows", original_shadows, false)
	expect(background.viewport.own_world_3d and background.viewport.world_3d != root.world_3d, "Decorative world is isolated from gameplay")
	var pool_size: int = map.ROW_COUNT * (map.HALF_COLUMNS * 2 + 1)
	expect(map.slots.size() == pool_size and map.rows.size() == map.ROW_COUNT, "Scrolling strip has a fixed pool with border overscan")
	var identities: Dictionary = {}
	for id in map.slots:
		var tile: Node3D = map.slots[id]["node"]
		identities[id] = tile.get_instance_id()
		expect(tile.has_node("Features") and tile.has_meta("surface"), "Menu uses actual gameplay tile construction")
	var population := land_count(map)
	expect(population > 100 and population < pool_size, "Strip has coherent land and outside water")
	check_shared_assets(map)
	check_border_preferences(map, video)
	expect(app.menus.main_panel.anchor_left < 0.1 and app.menus.main_panel.size.x == 384, "Main menu sits on left side")
	expect(app.menus.main_panel.get_global_rect().end.x < root.get_visible_rect().size.x * 0.5, "Map has the right half of the screen")
	var peak_motions := 0
	background.set_process(false)
	var camera_before: Transform3D = map.camera.transform
	var starting_models := snapshot(map)
	var interiors_unchanged := true
	var borders_only := true
	var independent := false
	var visible_depth_safe := true
	for step in range(120):
		map.advance(0.1)
		for slot in map.slots.values():
			var tile: Node3D = slot["node"]
			var pixel: Vector2 = map.camera.unproject_position(tile.global_position)
			if tile.visible and Rect2(Vector2.ZERO, Vector2(background.viewport.size)).has_point(pixel):
				var depth: float = -map.camera.to_local(tile.global_position).z
				if depth < map.camera.near + 2.0 or depth > map.camera.far - 2.0:
					visible_depth_safe = false
		for row in map.rows:
			var z: float = row["node"].position.z
			var phases: Dictionary = {}
			for id in row["slots"]:
				if map.slots[id]["cell"]["land"]:
					phases[map.slots[id]["state"]] = true
			if phases.size() > 1 and (phases.has("entering") or phases.has("leaving")):
				independent = true
			if absf(z) < 11.0:
				if row["state"] != "settled":
					borders_only = false
				for id in row["slots"]:
					var slot: Dictionary = map.slots[id]
					if slot["node"].position != slot["base"]:
						borders_only = false
					if starting_models.has(slot["coord"]):
						var original: Dictionary = starting_models[slot["coord"]]
						if original["cell"] != slot["cell"] or original["features"] != slot["node"].get_node("Features").get_instance_id():
							interiors_unchanged = false
		if step % 30 == 0:
			await process_frame
	expect(borders_only, "Only border rows fall; interior tiles retain exact relative placement")
	expect(interiors_unchanged, "Interior terrain and props are never regenerated")
	expect(independent, "Neighbouring border tiles have independent flight schedules")
	expect(visible_depth_safe, "Tighter shadow camera range retains visible tiles and prop depth throughout motion")
	expect(map.camera.transform != camera_before and map.camera_pitch < 0.60 and map.camera_yaw > 0.20, "Camera uses a lower oblique angle and gentle live orbit")
	var started := Time.get_ticks_usec()
	for step in range(600):
		map.advance(0.25)
		peak_motions = maxi(peak_motions, map.motions.size())
		if step % 60 == 0:
			await process_frame
	var elapsed := Time.get_ticks_usec() - started
	expect(map.changed_tiles > 0 and map.scroll_steps > 50, "Terrain continually scrolls and generates incoming rows")
	expect(peak_motions < 80, "Independent falling stays within bounded border bands")
	expect(map.slots.size() == pool_size and map.rows.size() == map.ROW_COUNT, "Scrolling does not grow the pool")
	expect(map.landscape.chunks.size() <= 8 and map.material_cache.size() < 1500, "Actual-map chunks and shared material caches remain bounded (%d chunks, %d materials, seed %d)" % [map.landscape.chunks.size(), map.material_cache.size(), map.landscape.seed_value])
	for id in map.slots:
		expect(map.slots[id]["node"].get_instance_id() == identities[id], "Only offscreen props refresh; tile nodes are reused")
		var slot: Dictionary = map.slots[id]
		expect(slot["logical_joined_mask"] == map.landscape.joined_mask(slot["column"], slot["coord"].y) and slot["node"].get_meta("joined_mask") == slot["joined_mask"], "Recycled tiles retain logical topology and the current visible edge mask")
		if slot["joined_mask"] != 0:
			expect(is_equal_approx(slot["node"].get_meta("border_visibility"), video.internal_borders), "Recycled kingdom surfaces use the current border visibility")
	print("Scrolling menu: 150 simulated seconds advanced in %.2f ms; peak falling tiles %d" % [elapsed / 1000.0, peak_motions])
	var frames_before: int = background.rendered_frames
	var time_before: float = map.camera_time
	for tick in range(120):
		background._process(1.0 / 120.0)
		background._on_frame_drawn()
	expect(background.rendered_frames - frames_before == 120 and is_equal_approx(map.camera_time - time_before, 1.0), "Background advances and counts draws at 120 Hz without an artificial cap")
	expect(background.viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Active background renders every application frame")
	var counted: int = background.rendered_frames
	background.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	background._on_frame_drawn()
	expect(background.rendered_frames == counted, "FPS counter does not count a disabled background renderer")
	background.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	app.fps_counter.refresh()
	expect(app.fps_counter.readout.text.contains("Menu:") and app.fps_counter.readout.visible, "FPS counter exposes both application and menu rates")
	var toggle := InputEventKey.new()
	toggle.keycode = KEY_F3
	toggle.pressed = true
	app.fps_counter._input(toggle)
	expect(not app.fps_counter.readout.visible, "F3 hides the FPS overlay")
	app.fps_counter._input(toggle)
	background.set_process(true)
	app.menus.show_screen(app.menus.Screen.SETUP)
	expect(background.active, "Background remains active during New Game setup")
	app.menus.open_options(app.menus.Screen.MAIN)
	expect(background.active and app.menus.options_panel.anchor_left < 0.1, "Main options keep side composition")
	video.set_preference(&"background", "water", false)
	expect(map.water.visible, "Water preference applies to menu")
	video.set_preference(&"background", "sky", false)
	expect(not map.water.visible, "Sky preference applies to menu")
	for quality in range(4):
		video.set_preference(&"antialiasing", quality, false)
		expect(background.viewport.msaa_3d == quality, "Antialiasing preference applies to isolated viewport")
	app.menus.show_screen(app.menus.Screen.MAIN)
	await app.start_new_game(42)
	expect(app.game.view.water.material_override.get_shader_parameter("backdrop_depth") == false, "Gameplay retains physical water depth while menu uses decorative backdrop depth")
	expect(not background.active and not map.active and not background.visible and not background.is_processing(), "Starting gameplay stops decorative update/rendering")
	expect(background.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden viewport does not render")
	video.set_preference(&"internal_borders", 0.0, false)
	expect(map.internal_border_visibility == 0.0 and app.game.view.internal_border_visibility == 0.0, "A visual preference updates both gameplay and the hidden menu landmass")
	video.set_preference(&"internal_borders", original_borders, false)
	app.fps_counter.refresh()
	expect(not app.fps_counter.readout.text.contains("Menu:"), "Match keeps its FPS counter without a stale menu rate")
	var changed_before: int = map.changed_tiles
	map.advance(60.0)
	expect(map.changed_tiles == changed_before, "Inactive map cannot evolve")
	app.pause_game()
	expect(not background.active, "Pause does not run a second decorative scene")
	app.menus.open_options(app.menus.Screen.PAUSE)
	expect(app.menus.options_panel.anchor_left == 0.5, "Pause options retain centered layout")
	app.continue_game()
	app.return_to_main_menu()
	while app.retiring_games > 0 or app.transitioning:
		await process_frame
	expect(background.active and map.slots.size() == pool_size, "Returning resumes original decorative pool")
	background.update_resolution()
	expect(background.viewport.size.x <= 1280 and background.viewport.size.y <= 820, "Offscreen resolution is bounded")
	video.set_preference(&"background", original_background, false)
	video.set_preference(&"antialiasing", original_antialiasing, false)
	video.set_preference(&"level_transitions", original_transitions, false)
	video.set_preference(&"internal_borders", original_borders, false)
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Menu background checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func check_streamed_cache_budget() -> void:
	# Seed 1 previously retained 1,632 materials after these streamed rows.
	var map = load("res://src/rendering/decorative_map.gd").new()
	map.initial_seed = 1
	root.add_child(map)
	map.active = true
	for step in range(660):
		map.advance(0.25)
		if step % 60 == 0: await process_frame
	expect(map.material_cache.size() <= map.MATERIAL_CACHE_LIMIT, "Fixed seed 1 keeps all streaming material variants within the shared budget")
	expect(map.landscape.chunks.size() <= 8, "Fixed seed 1 also releases obsolete streamed island chunks")
	map.queue_free()
	await process_frame

func check_border_preferences(map, video) -> void:
	var terrain = load("res://src/rendering/terrain_tile.gd")
	var reference = load("res://src/rendering/board_assets.gd").new()
	var original: float = video.internal_borders
	var before := snapshot(map)
	var affected := 0
	for slot in map.slots.values():
		affected += int(slot["joined_mask"] != 0)
	expect(affected > 0 and is_equal_approx(map.internal_border_visibility, original), "Menu initially applies the saved internal-border preference")
	for visibility in [0.0, 0.5, 1.0]:
		video.set_preference(&"internal_borders", visibility, false)
		reference.set_internal_border_visibility(visibility)
		expect(is_equal_approx(map.internal_border_visibility, visibility), "Menu changes border visibility live at zero, half and full values")
		for slot in map.slots.values():
			var actual: Mesh = slot["node"].get_meta("surface").mesh
			var expected: Mesh = terrain.cap_mesh(reference, slot["joined_mask"])
			expect(actual.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == expected.surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "Menu uses exactly the shared gameplay border geometry")
		expect(snapshot(map) == before, "Slider changes retain menu terrain data and prop identities")
	for percent in range(101):
		video.set_preference(&"internal_borders", percent / 100.0, false)
	expect(map.mesh_cache.keys().filter(func(key): return str(key).begins_with("kingdom_cap:")).size() <= 63, "Menu slider changes keep only one visibility's mesh variants")
	video.set_preference(&"internal_borders", original, false)
	reference.free()
	# Same local capital/color in neighboring chunks must not join two islands.
	var landscape = load("res://src/game/decorative_terrain.gd").new(0)
	var rules = load("res://src/game/kingdom_rules.gd").new()
	var cell: Dictionary = rules.make_cell(0)
	cell["kingdom"] = Vector2i.ZERO
	var half: int = 8
	var boundary_before: Vector2i = landscape.coord_at(0, half - 2)
	var last: Vector2i = landscape.coord_at(0, half - 1)
	var after: Vector2i = landscape.coord_at(0, half)
	var local_after: Vector2i = landscape.coord_at(0, -half)
	landscape.chunks[0] = {"start":0, "end":half, "origin":0, "cells": {last: cell, boundary_before: cell}, "seed": 0, "filled": []}
	landscape.chunks[1] = {"start":half, "end":half*3, "origin":half*2, "cells": {local_after: cell}, "seed": 1, "filled": []}
	var outside_edge: int = landscape.Grid.DIRECTIONS.find(after - last)
	var inside_edge: int = landscape.Grid.DIRECTIONS.find(last - boundary_before)
	expect(landscape.joined_mask(0, half - 1) & (1 << outside_edge) == 0, "Different streamed islands do not join through matching capital coordinates")
	expect(landscape.joined_mask(0, half - 2) & (1 << inside_edge) != 0, "Matching kingdoms in the same island join normally")

func land_count(map) -> int:
	var total := 0
	for slot in map.slots.values():
		if slot["cell"]["land"]:
			total += 1
	return total

func snapshot(map) -> Dictionary:
	var result: Dictionary = {}
	for slot in map.slots.values():
		result[slot["coord"]] = {"cell": slot["cell"].duplicate(true),
			"features": slot["node"].get_node("Features").get_instance_id()}
	return result

func geometry_signature(node: Node3D) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is MeshInstance3D:
			result.append([child.transform, child.mesh.get_aabb(), child.material_override.albedo_color,
				child.material_override.transparency, child.material_override.albedo_texture != null])
		elif child is Node3D:
			result.append([child.transform, geometry_signature(child)])
	return result

func check_shared_assets(map) -> void:
	var checked: Dictionary = {}
	for slot in map.slots.values():
		var cell: Dictionary = slot["cell"]
		for kind in ["tree", "mountain", "mana_source"]:
			if not cell[kind] or checked.has(kind):
				continue
			var reference := Node3D.new()
			match kind:
				"tree": map.add_tree(reference, Vector3(0.13, 0, 0))
				"mountain": map.add_mountain(reference, slot["style"])
				"mana_source": map.add_mana_source(reference)
			var actual: Node3D = slot["node"].get_node("ManaSource" if kind == "mana_source" else "Features")
			var expected: Node3D = reference.get_child(0) if kind == "mana_source" else reference
			expect(geometry_signature(actual) == geometry_signature(expected), "Menu geometry, scale and colors match game asset: " + kind)
			reference.free()
			checked[kind] = true
	expect(checked.size() == 3, "Fixture includes trees, mountain clusters and actual game mana sources")
	var Rules = load("res://src/game/kingdom_rules.gd")
	var generated: Dictionary = map.landscape.chunk(0)
	var expected_rules = Rules.new()
	expected_rules.rule_mode = "modern"
	expected_rules.generate(generated["seed"], generated["size"])
	var matches := true
	for coord in expected_rules.cells:
		var original: Dictionary = expected_rules.cells[coord]
		var displayed_coord: Vector2i = map.landscape.placed_coord(coord, generated["placement"])
		var decorated: Dictionary = generated["cells"].get(displayed_coord, {})
		for field in ["mountain", "value", "mana_source", "capital"]:
			if decorated.get(field) != original.get(field): matches = false
		if original["owner"] >= 0 and decorated.get("owner") != original["owner"]: matches = false
	expect(matches, "Cosmetic kingdoms preserve generated terrain, resources, capitals and original home territories")
	var neutral := 0
	var buildings := {"house":0, "tower":0}
	var claimed := 0
	for coord in generated["cells"]:
		var cell: Dictionary = generated["cells"][coord]
		if cell["owner"] < 0: neutral += 1
		elif expected_rules.cells.get(generated["source_coords"].get(coord, coord), {}).get("owner", -1) < 0: claimed += 1
		if cell.get("treasure", 0) > 0:
			expect(cell["owner"] == -1 and cell["building"] == "" and not cell["tree"], "Decorative captures collect chests before placing settlement props")
		if buildings.has(cell["building"]):
			buildings[cell["building"]] += 1
			expect(cell["owner"] >= 0 and cell["capital"] < 0 and not cell["tree"] and not cell["mountain"], "Decorative buildings occupy clear kingdom land")
	expect(claimed > 0 and neutral >= 10, "Menu kingdoms grow irregular borders while substantial neutral land remains")
	expect(buildings["house"] > 0 and buildings["tower"] > 0, "Menu kingdoms include scattered houses and towers")
	expect(generated["cells"].size() == expected_rules.cells.size() + generated["filled"].size(), "Only enclosed single-hex water holes are added cosmetically")
	var original_center: Vector2i = expected_rules.kingdoms.keys()[0]
	var center: Vector2i = map.landscape.placed_coord(original_center, generated["placement"])
	var column: int = map.landscape.column_at(center)
	var displayed: Dictionary = map.landscape.cell_for(column, center.y)
	expect(displayed["capital"] == expected_rules.cells[original_center]["capital"] and displayed["mana_source"], "Actual castle and resource placement reaches the streamed renderer")
	map.landscape.prune(map.rows[0]["index"], map.rows[-1]["index"])
	check_landmass(map)

func check_complete_islands() -> void:
	var Landscape = load("res://src/game/decorative_terrain.gd")
	# Seed 2 previously lost eight tiles; include negative/recycled chunks too.
	for seed_value in range(256):
		var landscape = Landscape.new(seed_value)
		for index in ([-2,-1,0,1,2] if seed_value < 8 else [0]):
			var data: Dictionary = landscape.chunk(index)
			var complete := true
			var padded := true
			for coord in data["cells"]:
				var column: int = Landscape.column_at(coord)
				if absi(column) >= Landscape.HALF_COLUMNS or coord.y < 1 or coord.y > Landscape.MAX_ISLAND_ROWS: padded = false
				var displayed: Dictionary = landscape.cell_for(column,coord.y + data["origin"])
				for field in ["owner","value","capital","mountain","building","mana_source"]:
					if displayed.get(field) != data["cells"][coord].get(field): complete = false
			expect(complete, "Every island tile and feature survives streaming without clipping")
			expect(padded, "Natural coasts finish before the column pool and chunk boundaries")
			var original = load("res://src/game/kingdom_rules.gd").new()
			original.rule_mode = "modern"
			original.generate(data["seed"],data["size"])
			expect(data["source_coords"].size() == original.cells.size(), "Fitting preserves the complete gameplay-generated island")
			for row in range(data["start"],data["end"]):
				expect(not landscape.cell_for(-Landscape.HALF_COLUMNS,row)["land"] and not landscape.cell_for(Landscape.HALF_COLUMNS,row)["land"], "Pool boundaries contain water instead of sliced land")

func check_landmass(map) -> void:
	var Landscape = load("res://src/game/decorative_terrain.gd")
	for seed_value in [0,2,42,71]:
		var landscape = Landscape.new(seed_value)
		var heights := {}
		var first_cells := {}
		for row in range(-20,21):
			for column in range(-8,9): first_cells[Vector2i(column,row)] = landscape.cell_for(column,row)
		for shift in range(0,81,4):
			var kingdoms := {}
			var water_rows := 0
			for row in range(-14-shift,15-shift):
				var land := 0
				for column in range(-8,9):
					var cell: Dictionary = landscape.cell_for(column,row)
					if cell["land"]: land += 1
					if cell["capital"] >= 0: kingdoms[cell["island"]] = true
				if land == 0: water_rows += 1
				heights[land] = true
			expect(kingdoms.size() >= 2, "New kingdom groups arrive while earlier kingdoms remain on screen")
			expect(water_rows > 0 and water_rows < 12, "Natural water gaps replace the long neutral filler rectangle")
			landscape.prune(-20-shift,20-shift)
			expect(landscape.chunks.size() <= 8, "Variable-height streaming keeps the map cache bounded")
		expect(heights.size() >= 8, "Streamed coast widths vary instead of forming a constant-width strip")
		var reproducible := true
		for coord in first_cells:
			if landscape.cell_for(coord.x,coord.y) != first_cells[coord]: reproducible = false
		expect(reproducible, "Pruned islands regenerate at the same positions and retain their decorations")
