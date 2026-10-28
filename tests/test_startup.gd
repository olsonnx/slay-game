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

func loading_screen(app):
	for child in app.get_children():
		if child.get_script() == load("res://src/ui/preparation_screen.gd") and not child.is_queued_for_deletion():
			return child
	return null

func valid_progress(values: Array) -> bool:
	if values.size() < 4 or values.back() != 1.0: return false
	var previous := 0.0
	var intermediate := false
	for value in values:
		if value < previous or value < 0.0 or value > 1.0: return false
		if value > 0.1 and value < 0.9: intermediate = true
		previous = value
	return intermediate

func run() -> void:
	var video = root.get_node("Video")
	var previous: bool = video.level_transitions
	video.set_preference(&"level_transitions", true, false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	var boot_screen = loading_screen(app)
	var boot_progress := []
	boot_screen.progress_changed.connect(func(value: float): boot_progress.append(value))
	expect(boot_screen.caption.text == "Loading..." and boot_screen.progress_bar.value == 0.0, "Startup displays Loading... and an empty progress bar")
	expect(not app.startup_complete and app.game == null and app.menus.navigation_locked and app.menus.screen == app.menus.Screen.HIDDEN, "Application warmup covers and locks navigation before any match exists")
	expect(not app.music_controls.visible, "Music button stays hidden during application loading")
	var observed_boot_fade := false
	while not app.startup_complete:
		if app.menus.screen == app.menus.Screen.MAIN and is_instance_valid(boot_screen):
			var opacity: float = boot_screen.cover.modulate.a
			if opacity > 0.0 and opacity < 1.0:
				observed_boot_fade = true
				expect(app.menus.navigation_locked, "Navigation remains locked while startup fades into the ready menu")
		await process_frame
	expect(observed_boot_fade and loading_screen(app) == null, "Startup fades over the destination before releasing its loading cover")
	expect(valid_progress(boot_progress), "Startup reports intermediate, monotonic progress and reaches 100 percent")
	expect(app.startup_complete and app.game == null and app.menus.screen == app.menus.Screen.MAIN, "Application warmup completes before showing the main menu")
	expect(app.music_controls.visible, "Music button returns with the ready main menu")
	var boot_frames: int = app.startup_warmup.prepared_frames
	app.start_new_game(42, "large")
	var map_screen = loading_screen(app)
	var map_progress := []
	map_screen.progress_changed.connect(func(value: float):
		map_progress.append(value)
		expect(is_equal_approx(map_screen.progress_bar.value, value) and is_equal_approx(map_screen.hex_art.progress, value), "Map bar and hex assembly both display reported work"))
	expect(map_screen.caption.text == "Creating map...", "Map creation displays its own progress screen")
	expect(app.transitioning and app.game == null and not app.menus.menu_background.active, "Preparation is covered and the menu stops before scene creation")
	expect(not app.music_controls.visible, "Music button stays hidden while preparing a match")
	app.start_new_game(99, "very_small")
	var responsive_frames := 0
	var floating_birds := false
	var publishing_frames := 0
	while app.transitioning:
		responsive_frames += 1
		if is_instance_valid(app.game):
			var published: int = app.game.view.static_batches.tile_records.size()
			if published > 0 and published < app.game.cells.size(): publishing_frames += 1
		if is_instance_valid(app.game) and app.game.view.level_transitioning:
			floating_birds = floating_birds or app.game.view.birds.visible
		await process_frame
	expect(valid_progress(map_progress), "Map creation reports intermediate, monotonic progress and reaches 100 percent")
	var screen = load("res://src/ui/preparation_screen.gd").new()
	root.add_child(screen)
	screen.set_progress(0.5)
	screen.set_progress(0.2)
	expect(screen.progress_bar.value == 0.5, "Late progress updates cannot move the bar backwards")
	screen._process(5.0)
	expect(screen.hex_art.progress == 0.5 and screen.percentage.text == "50%", "Hex animation never advances the reported loading progress")
	screen.set_progress(2.0)
	expect(screen.progress_bar.value == 1.0 and screen.percentage.text == "100%", "Progress is clamped to completion")
	screen.queue_free()
	expect(not floating_birds and not app.game.view.birds.visible, "Birds stay hidden during covered preparation and island entrance")
	var game = app.game
	var focus_settings = root.get_node("Gameplay")
	var previous_focus_pause: bool = focus_settings.pause_on_focus_loss
	focus_settings.set_preference("pause_on_focus_loss",true,false)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(paused,"Focus-loss preference pauses a real solo match")
	app.continue_game()
	focus_settings.set_preference("pause_on_focus_loss",previous_focus_pause,false)
	var prepared_value_syncs: int = game.view.static_batches.sync_count
	var prepared_value_rebuilds: int = game.view.static_batches.terrain_rebuild_count
	game.view.value_heatmap.set_active(true)
	expect(game.view.value_heatmap.tiles.size() == game.cells.size() and game.view.static_batches.sync_count == prepared_value_syncs and game.view.static_batches.terrain_rebuild_count == prepared_value_rebuilds, "Map loading and entry leave the first province-value switch fully prepared")
	game.view.value_heatmap.set_active(false)
	var original_unit_texture: Texture2D = game.view.soldier_texture(1, 1)
	var warmup = app.startup_warmup
	var warmup_board = warmup.get_parent()
	expect(game.view.unit_sprites == warmup_board.unit_sprites and game.view.get_node_or_null("GraphicsWarmup") == null and warmup.prepared_frames == boot_frames, "Matches reuse application texture caches without repeating graphics warmup")
	expect(app.startup_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Retained startup resources stop rendering after boot")
	expect(warmup.completed and not warmup.visible and warmup.prepared_frames > 0, "Warmup completes under the cover and hides its retained specimens")
	expect(warmup.has_node("WarmupRoadSurface") and warmup.has_node("WarmupRoadBorder"), "Startup submits the real road and preview surfaces")
	expect(warmup.get_node("WarmupRoadSurface").material_override == game.view.roads.material, "Matches reuse the exact road material warmed at boot")
	var road_meshes: int = game.view.roads.mesh_cache.size()
	game.view.roads.tile_mesh(37, game.view.COLORS[0].darkened(game.view.roads.DARKENING))
	expect(game.view.roads.mesh_cache.size() == road_meshes, "Road junction geometry is preloaded before the first placement")
	expect(warmup.rendered_passes == (0 if DisplayServer.get_name() == "headless" else 3), "Native warmup actually draws the variants; headless never waits for GPU signals")
	var cached_frames: int = game.view.unit_sprites.frames.size()
	var cached_outlines: int = game.view.hover_outline_cache.size()
	var owners := {}
	for cell in game.cells.values():
		if cell.owner >= 0: owners[cell.owner] = true
	var library = load("res://src/rendering/unit_sprite_library.gd")
	for owner in owners:
		for tier in range(1, library.CLIPS.size()):
			for animation in library.CLIPS[tier]:
				for index in range(int(library.clip(tier, animation)[1])):
					game.view.unit_sprites.frame(tier, game.view.COLORS[owner], animation, index)
			for index in range(int(library.clip(tier, "idle")[1])):
				game.view.soldier_hover_outline(tier, owner, index)
	expect(game.view.unit_sprites.frames.size() == cached_frames and game.view.hover_outline_cache.size() == cached_outlines, "Every faction's upgrades, attacks, deaths and hover poses reuse prepared textures")
	var specimen_count: int = warmup.get_child_count()
	await warmup.prepare(warmup_board)
	expect(warmup.get_child_count() == specimen_count, "Repeated preparation is idempotent")
	var previews_restored: bool = warmup_board.overlays.building_storage.position == Vector3.ZERO
	for container in [warmup_board.playback, warmup_board.overlays.building_storage]:
		for surface in container.find_children("*", "GeometryInstance3D", true, false):
			previews_restored = previews_restored and surface.layers == 0
	expect(previews_restored and warmup_board.playback.scaled_tweens.is_empty(), "Warmup restores hidden effect surfaces and previews without playing game actions")
	var expected = load("res://src/game/kingdom_rules.gd").new()
	expected.rule_mode = game.initial_rule_mode
	expected.generate(42, "large")
	expect(game.cells == expected.cells and game.rules.rng.state == expected.rng.state and game.rules.kingdoms == expected.kingdoms, "Worker preparation reproduces all seeded rules and ignores duplicate starts")
	expect(publishing_frames > 1, "Normal startup spreads scenery collection across frames")
	expect(responsive_frames > 5 and game.startup_timings["batches"] > 1, "Large preparation yields between construction batches")
	expect(game.view.level_transitioning and not game.view.controls_enabled, "Entrance starts after preparation with controls locked")
	while game.view.level_transitioning:
		await process_frame
	expect(game.view.birds.visible, "Birds appear after the island settles")
	expect(game.view.controls_enabled and game.view.tile_nodes.size() == game.cells.size(), "Prepared board settles completely and unlocks")
	await app.return_to_main_menu()
	var document = load("res://src/editor/level_document.gd").new()
	document.cells = expected.cells.duplicate(true)
	for cell in document.cells.values():
		cell["event"] = ""
		cell.erase("treasure")
	document.map_size = "large"
	document.rule_mode = expected.rule_mode
	document.seed_value = 42
	document.player_faction = 1
	document.starting_gold = 73
	document.factions[1]["name"] = "Restart kingdom"
	document.factions[1]["color"] = "ff6644"
	document.factions[1]["terrain"] = "44aa66"
	var draft: Dictionary = document.state()
	var untouched: Dictionary = draft.duplicate(true)
	# Compare against the same serialized authored format the loader receives.
	var reloaded = load("res://src/editor/level_document.gd").new()
	expect(reloaded.read_data(draft.duplicate(true)).is_empty(), "Authored startup fixture validates")
	var authored_expected = reloaded.build_rules()
	await app.start_new_game(42, "large", "", 0, draft)
	while app.game.view.level_transitioning: await process_frame
	expect(app.game.cells == authored_expected.cells and app.game.rules.kingdoms == authored_expected.kingdoms, "Worker-loaded authored rules preserve cells and starting resources")
	expect(app.game.player_faction == 1 and app.game.session.names[1] == "Restart kingdom" and app.game.session.colors[1] == Color("ff6644") and app.game.view.COLORS[1] == Color("44aa66"), "Prepared document supplies authored player and kingdom palettes")
	expect(app.game.view.soldier_texture(1, 1) != original_unit_texture and app.game.view.soldier_texture(1, 1) == warmup_board.unit_sprites.frame(1, Color("44aa66")).texture, "Shared caches distinguish authored colors from the same faction index in earlier matches")
	app.pause_game()
	await app.restart_current_level()
	while app.game.view.level_transitioning: await process_frame
	expect(app.game.cells == authored_expected.cells and app.game.rules.kingdoms == authored_expected.kingdoms, "Playtest restart restores the exact authored map through background preparation")
	expect(draft == untouched and app.custom_level == untouched, "Background validation and restart leave the original editor snapshot untouched")
	expect(app.game.view.static_batches.tile_records.size() == app.game.cells.size() and not app.game.view.bulk_rebuilding, "Restart finishes publishing every tile before enabling play")
	expect(app.startup_warmup == warmup and warmup.prepared_frames == boot_frames, "Authored games and restarts retain the original application warmup")
	await app.return_to_main_menu()
	video.set_preference(&"level_transitions", previous, false)
	app.queue_free()
	await process_frame
	print("Startup checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
