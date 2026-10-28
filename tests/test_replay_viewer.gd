extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Timeline = preload("res://src/game/replay_timeline.gd")
const Identity = preload("res://src/game/replay_identity.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const Summary = preload("res://src/game/replay_summary.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func finish_board(viewer) -> void:
	while viewer.building:
		viewer.poll_board_build()
		await process_frame

func frame_limit_checks() -> void:
	var original_limit := Engine.max_fps
	var video = root.get_node("Video")
	var original_vsync: bool = video.vsync
	video.set_preference(&"vsync", false, false)
	for application_limit in [0, 30, 144]:
		Engine.max_fps = application_limit
		var viewer = load("res://src/ui/replay_viewer.gd").new()
		root.add_child(viewer)
		expect(Engine.max_fps == (30 if application_limit == 30 else 60), "Replay menu is capped with VSync off and respects a lower application limit")
		viewer.apply_frame_limit(viewer.PLAYBACK_FPS_LIMIT)
		expect(Engine.max_fps == (30 if application_limit == 30 else 120), "Spectator playback remains capped and respects a lower application limit")
		viewer.show_library()
		expect(Engine.max_fps == (30 if application_limit == 30 else 60), "Returning to the library restores its menu cap")
		viewer.free()
		expect(Engine.max_fps == application_limit and not video.vsync, "Closing Replays restores the previous FPS limit without changing VSync")
	Engine.max_fps = original_limit
	video.set_preference(&"vsync", original_vsync, false)

func summary_checks() -> void:
	var broken_path := "res://artifacts/replay-preview-broken.jsonl"
	var broken := FileAccess.open(broken_path, FileAccess.WRITE)
	broken.store_string("not JSON\n")
	broken.close()
	expect(Summary.read_preview(broken_path).get("preview_error",false), "Malformed library headers are recoverable without emitting engine errors")
	DirAccess.remove_absolute(broken_path)
	var model = Rules.new()
	model.rule_mode = "modern"
	model.generate(42, "very_small", 2)
	model.faction_names = Catalog.FACTIONS.duplicate()
	model.faction_names[0] = "Iris"
	var replay := Replay.new()
	var path := "res://artifacts/metadata-preview.jsonl"
	replay.start(model, {"mode":"editor", "map_title":"The Long Coast", "difficulty":"hard"}, path)
	replay.round_number = 7
	replay.finish(model, "completed", 0, {"duration_seconds":3723, "result":"victory"})
	replay.save_completed(model)
	var preview := Summary.read_preview(path)
	expect(Summary.players(preview) == "Iris" and Summary.outcome(preview) == "Victory", "Library summary identifies the recorded player kingdom and result")
	expect(preview.duration_seconds == 3723 and preview.rounds == 7 and preview.mode == "editor" and preview.map_title == "The Long Coast", "Library header exposes elapsed time, rounds, mode and authored map title")
	expect(Summary.description(preview).contains("01:02:03") and Summary.description(preview).contains("Hard"), "Summary formats duration and difficulty for display")
	var original := FileAccess.get_file_as_string(path).strip_edges().split("\n")
	var header: Dictionary = JSON.parse_string(original[0])
	header["summary"]["duration_seconds"] = 1
	var damaged := original.duplicate()
	damaged[0] = JSON.stringify(header)
	var output := FileAccess.open(path, FileAccess.WRITE)
	output.store_string("\n".join(damaged) + "\n")
	output.close()
	expect(Replay.read_replay(path, true).get("error") == "Replay summary mismatch", "Playback verifies exposed metadata against the checksum-protected details")
	header.erase("summary")
	damaged[0] = JSON.stringify(header)
	output = FileAccess.open(path, FileAccess.WRITE)
	output.store_string("\n".join(damaged) + "\n")
	output.close()
	var older := Summary.read_preview(path)
	expect(Summary.players(older) == "Iris" and Summary.outcome(older) == "Victory" and older.rounds == 7 and not older.details_available, "Older compact files expose their readable result without decompressing the details")
	var job = preload("res://src/game/replay_job.gd").new()
	var complete: Dictionary = load("res://src/ui/replay_viewer.gd").load_summary(path, job)
	expect(complete.map_title == "The Long Coast" and complete.difficulty == "hard", "Selecting an older recording recovers its remaining metadata")
	header["summary"] = preview.duplicate(true)
	header["summary"].erase("details_available")
	damaged[0] = JSON.stringify(header)
	damaged[-1] = JSON.stringify({"data":Marshalls.raw_to_base64("different details".to_utf8_buffer().compress(FileAccess.COMPRESSION_GZIP))})
	output = FileAccess.open(path, FileAccess.WRITE)
	output.store_string("\n".join(damaged) + "\n")
	output.close()
	expect(Summary.read_preview(path).get("duration_seconds") == 3723, "Library previews read the small header without touching the compressed tape")
	expect(Replay.read_replay(path, true).get("error") != "", "Preview availability never bypasses full validation before playback")
	var hotseat := Summary.from_records({"names":["Fern", "Tide"], "humans":[0, 1]}, [{"action":"result", "round":4, "args":{"outcome":"completed", "winner":1}}])
	expect(Summary.mode_name(hotseat) == "Local multiplayer" and Summary.players(hotseat) == "Fern / Tide" and Summary.outcome(hotseat) == "Tide won", "Multiplayer metadata lists all local kingdoms and names the winner")
	hotseat.mode = "steam_online"
	expect(Summary.mode_name(hotseat) == "Steam multiplayer", "Steam recordings are distinguished from local multiplayer in the library")
	expect(Summary.description(hotseat).contains("Duration: Not recorded"), "Missing historical duration is clearly marked rather than estimated")
	var mixed := Summary.from_records({"names":["Alice", "Bot A", "Bot B"], "humans":[0], "metadata":{"match":{"slots":[{"color":11,"controller":"human"}, {"controller":"ai","difficulty":"easy"}, {"controller":"ai","difficulty":"hard"}]}}}, [])
	expect(Summary.players(mixed) == "Iris (Alice)" and Summary.description(mixed).contains("Difficulty: Mixed"), "Summary distinguishes a player's name from their kingdom and preserves mixed AI settings")
	var malformed := preview.duplicate(true)
	malformed["duration_seconds"] = {}
	expect(not Summary.valid_preview(malformed), "Malformed summary values are rejected before reaching labels")
	var malformed_results: Array = []
	Summary.append_result(malformed_results, {}, {})
	expect(malformed_results.is_empty(), "Malformed legacy result previews are skipped without a runtime error")
	DirAccess.remove_absolute(path)

func identity_checks(viewer, data: Dictionary) -> void:
	var legacy := data.duplicate(true)
	legacy["header"]["metadata"] = {"match":{"slots":[{"color":11}, {"color":6}]}}
	legacy["header"]["names"][0] = "Custom player"
	var palette := Identity.resolve(legacy["header"])
	expect(palette["terrain"][0] == Catalog.TERRAIN_COLORS[11] and palette["colors"][1] == Catalog.UI_COLORS[6], "Older match metadata restores chosen seat colors independently of names")
	expect(palette["terrain"][2] == Catalog.TERRAIN_COLORS[0] and palette["terrain"][8] == Catalog.TERRAIN_COLORS[7], "Unused and revolt seats preserve the live game's remaining palette order")
	expect(viewer.finish_loading(legacy), "Viewer accepts an older recording with remapped kingdom colors")
	await finish_board(viewer)
	expect(viewer.view.COLORS == palette["terrain"] and viewer.legend_labels[0].text == "●  Custom player", "Recorded palette and names reach the board and spectator legend")
	expect(viewer.legend_labels[0].get_theme_color("font_color") == Catalog.UI_COLORS[11], "Legend uses the recorded seat's UI color")
	viewer.seek_to(1)
	expect(viewer.details.get_theme_color("font_color") == Catalog.UI_COLORS[11], "Action status identifies the acting seat with its recorded color")
	var custom := legacy.duplicate(true)
	var colors: Array = Catalog.UI_COLORS.duplicate()
	var terrain: Array = Catalog.TERRAIN_COLORS.duplicate()
	colors[0] = Color("123456")
	terrain[0] = Color("ab3759")
	custom["header"]["metadata"]["factions"] = Identity.capture(custom["header"]["names"], colors, terrain)
	var records: Array = [custom["header"]]
	records.append_array(custom["commands"])
	var path := "res://artifacts/replay-viewer-tests/custom-colors.jsonl"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("\n".join(Replay.archive_objects(records)) + "\n")
	file.close()
	var loaded := Replay.read_replay(path, true)
	expect(loaded.get("error") == "" and Identity.resolve(loaded["header"])["terrain"] == terrain, "Exact custom colors survive a saved compressed replay")
	expect(viewer.finish_loading(loaded), "Viewer loads exact custom-map colors")
	await finish_board(viewer)
	expect(viewer.view.COLORS == terrain and viewer.kingdom_colors == colors, "Exact authored colors override indexed match palettes")
	viewer.seek_to(1)
	viewer.seek_to(0)
	expect(viewer.view.COLORS == terrain, "Seeking retains the recording's palette")
	DirAccess.remove_absolute(path)
	var fallback := Identity.resolve({})
	expect(fallback["terrain"] == Catalog.TERRAIN_COLORS, "Legacy files without color metadata retain the original indexed palette")
	viewer.show_library()

func indexed_seek_checks(data: Dictionary) -> void:
	var long_data := data.duplicate(true)
	long_data["commands"] = []
	var coord: String = long_data["header"]["initial"]["cells"].keys()[0]
	var cell: Dictionary = long_data["header"]["initial"]["cells"][coord].duplicate(true)
	for index in range(4096):
		var changed := cell.duplicate(true)
		changed["unit"] = index % 4
		long_data["commands"].append({"seq":index + 1,"round":1,"faction":0,"action":"fixture","args":{},"delta":{"cells":{"set":{coord:changed},"erase":[]}}})
	var indexed := Timeline.new()
	expect(indexed.open(long_data) == "", "Long recording prepares an indexed timeline")
	for target in [4096, 2048, 2047, 3971, 1, 0, 4050, 4049, 4050]:
		indexed.seek(target)
		var expected: Dictionary = long_data["header"]["initial"].duplicate(true)
		for index in range(target): Replay.apply_delta(expected, long_data["commands"][index]["delta"])
		expect(indexed.position == Replay.decode(expected), "Indexed random seek exactly matches independent reconstruction at %d" % target)
		expect(indexed.last_seek_patches < indexed.checkpoint_interval, "Seeking applies fewer than one checkpoint interval of changes")
	expect(indexed.checkpoints.size() <= indexed.MAX_CHECKPOINTS + 1, "Checkpoint count stays bounded for a long match")
	var retained: Dictionary = Replay.encode(indexed.position)
	var retained_position: Dictionary = indexed.position
	indexed.seek(4070)
	expect(Replay.encode(retained_position) == retained, "Seeking preserves earlier board references used by animations")
	var topology := data.duplicate(true)
	var added := "@hex:100,100"
	topology["commands"] = [
		{"action":"bridge","delta":{"cells":{"set":{added:cell},"erase":[]},"rng":{"value":"123"}}},
		{"action":"remove","delta":{"cells":{"set":{},"erase":[added]},"rng":{"value":"456"}}}]
	var edits := Timeline.new()
	expect(edits.open(topology) == "", "Timeline indexes tile creation, deletion and scalar changes")
	edits.seek(1)
	expect(edits.position["cells"].has(Vector2i(100, 100)) and edits.position["rng"] == "123", "Forward patches create tiles and change scalar state")
	edits.seek(2)
	expect(not edits.position["cells"].has(Vector2i(100, 100)), "Forward patches erase tiles")
	edits.seek(1)
	expect(edits.position["cells"].has(Vector2i(100, 100)) and edits.position["rng"] == "123", "Undo restores deleted tiles and previous scalar state")
	edits.seek(0)
	expect(edits.position == Replay.decode(topology["header"]["initial"]), "Undo of tile creation restores the complete initial position")

func movement_filter_checks(data: Dictionary) -> void:
	var fixture := data.duplicate(true)
	fixture["commands"] = []
	for action in ["recruit", "move", "develop", "move", "turn_end", "result"]:
		fixture["commands"].append({"action":action,"args":{},"delta":{"rng":{"value":str(fixture["commands"].size())}}})
	var indexed := Timeline.new()
	expect(indexed.open(fixture) == "", "Movement filter fixture opens")
	indexed.set_movement_only(true)
	expect(indexed.steps == [0, 2, 4, 6], "Movement-only steps contain the opening, movements and exact final position")
	for step in range(indexed.steps.size()):
		indexed.seek(step)
		var expected: Dictionary = fixture["header"]["initial"].duplicate(true)
		for index in range(indexed.steps[step]): Replay.apply_delta(expected, fixture["commands"][index]["delta"])
		expect(indexed.position == Replay.decode(expected), "Movement filtering retains every skipped state patch")
	indexed.seek(2)
	expect(indexed.before_step(2)["rng"] == "2", "Filtered movement animation starts after skipped recruitment and development")
	indexed.set_movement_only(false)
	expect(indexed.applied == 4 and indexed.cursor == 4, "Disabling the filter retains the same recorded command")
	for row in fixture["commands"]: row["action"] = "build"
	var no_moves := Timeline.new()
	no_moves.open(fixture)
	no_moves.set_movement_only(true)
	no_moves.seek(1)
	expect(no_moves.steps == [0, 6] and no_moves.position["rng"] == "5", "A recording without movements still exposes its exact ending")

func control_checks(viewer) -> void:
	for button in [viewer.start_button, viewer.previous_button, viewer.play_button, viewer.next_button, viewer.end_button, viewer.browse_button, viewer.camera_button, viewer.hide_ui_button, viewer.restore_ui_button]:
		expect(button.text == "" and button.icon != null and not button.tooltip_text.is_empty(), "Replay icon controls have visible icons and descriptive tooltips")
		var tooltip: Control = button._make_custom_tooltip(button.tooltip_text)
		expect(tooltip.custom_minimum_size.x > 0 and tooltip.custom_minimum_size.y > 0 and not tooltip.get_child(0).text.is_empty(), "Custom replay tooltips contain measured text")
		tooltip.free()
	expect(viewer.speed_choice.item_count == 6 and viewer.speed_choice.get_item_text(5) == "16×", "Replay speed menu includes 8× and 16×")
	viewer.select_speed(5)
	viewer.set_playing(true)
	expect(viewer.speed == 16.0 and viewer.view.playback.speed_scale == 16.0, "16× applies to animation playback")
	viewer.set_playing(false)
	viewer.select_speed(1)
	viewer.end_button.pressed.emit()
	expect(viewer.timeline.applied == viewer.timeline.commands.size() and not viewer.playing, "Go to end pauses at the complete final position")
	viewer.start_button.pressed.emit()
	expect(viewer.timeline.cursor == 0, "Start icon returns to the opening")
	await process_frame
	expect(viewer.header_panel.position.x == 20 and viewer.header_panel.size.x < root.get_visible_rect().size.x * 0.8, "Replay header fits its contents at the left without spanning the viewport")
	expect(viewer.transport.is_ancestor_of(viewer.browse_button), "Choose recording lives in the bottom toolbar")
	viewer.hide_ui_button.pressed.emit()
	expect(viewer.ui_hidden and not viewer.header_panel.visible and not viewer.transport.visible and viewer.restore_ui_button.visible, "Hide UI leaves a small restore icon available")
	viewer.restore_ui_button.pressed.emit()
	expect(not viewer.ui_hidden and viewer.header_panel.visible and viewer.transport.visible, "The restore icon shows the replay controls")
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_F10
	shortcut.pressed = true
	viewer._input(shortcut)
	shortcut.keycode = KEY_ESCAPE
	viewer._unhandled_input(shortcut)
	expect(not viewer.ui_hidden and not viewer.library.visible, "Escape restores hidden UI before leaving the recording")
	var original_view: bool = viewer.view.top_down
	viewer.camera_button.button_down.emit()
	viewer.camera_button.button_up.emit()
	viewer.camera_button.pressed.emit()
	expect(viewer.view.top_down != original_view, "A short camera-button click switches views")
	viewer.view.focus += Vector3(5, 0, 3)
	viewer.camera_button.button_down.emit()
	viewer.advance_camera_press(0.56)
	var reset_view: bool = viewer.view.top_down
	viewer.camera_button.button_up.emit()
	viewer.camera_button.pressed.emit()
	expect(viewer.view.focus == viewer.view.map_center and viewer.view.top_down == reset_view, "Holding the camera button recenters without toggling on release")
	viewer.camera_button.button_down.emit()
	viewer.advance_camera_press(0.2)
	viewer.camera_button.mouse_exited.emit()
	expect(not viewer.camera_press_held and viewer.camera_hold_indicator.progress == 0.0, "Leaving the camera button cancels its hold indicator")

func filtered_animation_checks(viewer) -> void:
	var model = Rules.new()
	model.rule_mode = "modern"
	for x in range(4): model.cells[Vector2i(x, 0)] = model.make_cell(0 if x < 2 else 1)
	model.rebuild_kingdoms()
	model.cells[Vector2i(2, 0)]["unit"] = 1
	var recorder := Replay.new()
	model.replay_log = recorder
	recorder.start(model)
	model.cells[Vector2i.ZERO]["unit"] = 2
	recorder.record(model, "recruit", 0)
	model.perform_move(Vector2i.ZERO, Vector2i(2, 0))
	recorder.finish(model, "completed", 0)
	viewer.movement_checkbox.set_pressed_no_signal(true)
	expect(viewer.finish_loading(Replay.read_records(recorder.records)), "Movement-only playback loads a newly recruited mover")
	await finish_board(viewer)
	viewer.select_speed(5)
	viewer.set_playing(true)
	viewer.seek_to(1, true)
	expect(viewer.view.is_animating, "Filtered playback animates a unit recruited during skipped actions")
	for tick in range(200):
		if not viewer.view.is_animating: break
		await create_timer(0.01).timeout
	expect(not viewer.view.is_animating and viewer.view.cells == model.cells, "Filtered 16× animation reaches the exact recorded combat state")
	viewer.end_button.pressed.emit()
	expect(viewer.timeline.applied == viewer.timeline.commands.size() and viewer.view.cells == model.cells, "Filtered go-to-end retains final settlement changes")
	viewer.movement_checkbox.set_pressed_no_signal(false)
	viewer.set_movement_only(false)
	viewer.select_speed(1)

func combat_checks(viewer) -> void:
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var d := Vector2i(3, 0)
	for kind in ["attack", "knight_duel", "blocked_attack", "merge"]:
		var model = Rules.new()
		model.rule_mode = "modern"
		for coord in [a, b, c, d]: model.cells[coord] = model.make_cell(0 if coord in [a, b] or kind == "merge" else 1)
		model.rebuild_kingdoms()
		model.cells[a]["unit"] = 3 if kind == "knight_duel" else 1 if kind == "merge" else 2
		model.cells[c]["unit"] = 3 if kind == "knight_duel" else 1
		if kind == "blocked_attack": model.entrench(c, 1)
		var recorder := Replay.new()
		model.replay_log = recorder
		recorder.start(model)
		var actual: Dictionary = model.perform_move(a, c)
		expect(actual.get("kind") == kind, "Recorded combat fixture produces " + kind)
		var data := Replay.read_records(recorder.records)
		expect(viewer.finish_loading(data), "Viewer loads " + kind)
		await finish_board(viewer)
		viewer.speed = 4.0
		viewer.set_playing(true)
		viewer.seek_to(1, true)
		for tick in range(200):
			if not viewer.view.is_animating: break
			await create_timer(0.02).timeout
		expect(not viewer.view.is_animating and viewer.view.cells == model.cells, "Animated replay exactly reproduces " + kind)
		viewer.set_playing(false)

func run() -> void:
	root.size = Vector2i(960, 620)
	summary_checks()
	frame_limit_checks()
	var model = Rules.new()
	model.rule_mode = "modern"
	model.generate(42, "very_small", 2)
	var recorder := Replay.new()
	model.replay_log = recorder
	var directory := "res://artifacts/replay-viewer-tests"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("viewer-match.jsonl")
	recorder.start(model, {}, path)
	var initial := Replay.position(model)
	var faction: int = model.human_factions[0]
	var capital: Vector2i = model.kingdom_at(model.kingdoms.keys()[0])["capital"]
	for coord in model.cells:
		if model.cells[coord]["unit"] > 0 and model.cells[coord]["owner"] == faction:
			capital = coord
			break
	var destinations: Dictionary = model.reachable_targets(capital)
	expect(not destinations.is_empty(), "Viewer fixture has a recorded unit movement")
	if not destinations.is_empty(): model.perform_move(capital, destinations.keys()[0])
	var move_state := Replay.position(model)
	recorder.record(model, "ai_decision", faction, {"score":1})
	model.spread_trees()
	recorder.finish(model, "completed", faction)
	recorder.save_completed(model)
	var original_bytes := FileAccess.get_file_as_bytes(path)
	var data := Replay.read_replay(path)
	var playback_data := Replay.read_replay(path, true)
	expect(playback_data.get("error") == "" and playback_data.get("position") == data.get("position"), "Checksum-authenticated playback reader reconstructs the same state as the full inspection reader")
	expect(Replay.read_replay(path, true, func(): return true).get("error") != "", "Replay decoding cooperatively stops a cancelled load")
	expect(Timeline.new().open(data, func(): return true) != "", "Timeline indexing cooperatively stops a cancelled load")
	var damaged_path := directory.path_join("damaged.jsonl")
	var damaged_rows: Array = [data["header"].duplicate(true), data["commands"][0].duplicate(true)]
	damaged_rows[1]["delta"] = {"cells":{"set":[],"erase":[]}}
	var damaged := FileAccess.open(damaged_path, FileAccess.WRITE)
	damaged.store_string("\n".join(Replay.archive_objects(damaged_rows)) + "\n")
	damaged.close()
	expect(Replay.read_replay(damaged_path, true).get("error") != "", "Playback rejects malformed patches even with a valid archive checksum")
	damaged = FileAccess.open(damaged_path, FileAccess.WRITE)
	damaged.store_string(FileAccess.get_file_as_string(path).replace('"sha256":"', '"sha256":"bad'))
	damaged.close()
	expect(Replay.read_replay(damaged_path, true).get("error") != "", "Playback rejects a damaged archive checksum")
	DirAccess.remove_absolute(damaged_path)
	indexed_seek_checks(data)
	movement_filter_checks(data)
	expect(data["error"] == "", "Saved compressed replay loads through the existing verified reader")
	var timeline := Timeline.new()
	expect(timeline.open(data) == "", "Viewer accepts a completed compact replay")
	expect(Replay.encode(timeline.position) == initial, "Viewer starts at the exact recorded opening")
	expect(timeline.steps.size() < data["commands"].size() + 1, "Playback skips AI diagnostic-only steps")
	timeline.seek(1)
	expect(Replay.encode(timeline.position) == move_state, "Forward stepping applies the recorded move")
	var movement := timeline.movement(Replay.decode(initial)["cells"])
	expect(not movement.is_empty() and movement["source"] == capital, "Movement animation is reconstructed from recording data")
	timeline.seek(9999)
	expect(Replay.encode(timeline.position) == Replay.position(model), "Seeking to the end reproduces the complete final state")
	timeline.seek(-2)
	expect(Replay.encode(timeline.position) == initial, "Backward seeking restores the exact opening")
	var legacy := Replay.read_records(recorder.records)
	expect(Timeline.new().open(legacy) == "", "Viewer also accepts legacy replay records")
	expect(Timeline.new().open({"error":"Broken archive"}) == "Broken archive", "Load errors remain recoverable")
	var unsupported := data.duplicate(true)
	unsupported["header"]["initial"]["cells"] = {"@hex:0,0":{}}
	expect(Timeline.new().open(unsupported) != "", "Unsupported board data is rejected before rendering")
	var viewer = load("res://src/ui/replay_viewer.gd").new()
	viewer.replay_directory = directory
	root.add_child(viewer)
	viewer.set_process(false)
	expect(viewer.dialog == null, "Entering Replays does not construct a filesystem file picker")
	for tick in range(200):
		viewer.poll_library()
		if not viewer.library_loading: break
		await create_timer(0.01).timeout
	expect(viewer.paths.size() == 1 and viewer.library.visible, "Replay browser lists local recordings")
	expect(not viewer.list.is_item_tooltip_enabled(0), "Replay filenames never spawn automatic hover tooltip windows")
	viewer.list.select(0)
	viewer.list.item_selected.emit(0)
	expect(viewer.message.text == path.get_file() and not viewer.watch_button.disabled and viewer.view == null, "Selecting a filename shows it inline without loading a recording")
	expect(viewer.preview_title.text == Summary.players(viewer.summaries[path]) and viewer.preview_details.text.contains("Duration: Not recorded") and viewer.metadata_worker == null, "Selecting a current recording shows its stored summary immediately without decoding playback")
	# A large library must populate across frames, never parse files on entry.
	viewer.library_loading = true
	viewer.pending_files.clear()
	viewer.pending_file_index = 0
	for index in range(1000): viewer.pending_files.append("unparsed-%d.jsonl" % index)
	var before_items: int = viewer.list.item_count
	viewer.poll_library()
	expect(viewer.library_loading and viewer.list.item_count - before_items == viewer.LIBRARY_BATCH_SIZE, "Large replay libraries add only one bounded batch per frame")
	while viewer.library_loading: viewer.poll_library()
	expect(viewer.list.item_count == before_items + 1000, "Background discovery lists every file without opening recordings")
	var tooltips_disabled := true
	for index in range(viewer.list.item_count):
		tooltips_disabled = tooltips_disabled and not viewer.list.is_item_tooltip_enabled(index)
	expect(tooltips_disabled, "Every asynchronously added replay row disables hover popups")
	await process_frame
	expect(root.get_visible_rect().encloses(viewer.library.get_global_rect()), "Replay library fits within the minimum viewport")
	expect(viewer.watch_button.get_theme_stylebox("normal").bg_color == preload("res://src/ui/ui_theme.gd").ACCENT and viewer.watch_button.custom_minimum_size.y == 44, "Library uses the shared primary button color and standard control height")
	expect(viewer.finish_loading(data), "Viewer builds the recorded island")
	expect(viewer.building and viewer.library.visible, "Island construction keeps the library visible while building in frame budgets")
	expect(Engine.max_fps <= 60, "Replay loading retains the menu frame limit")
	await finish_board(viewer)
	expect(Engine.max_fps <= 120, "Completed island construction applies the spectator frame limit")
	expect(viewer.view.cells == Replay.decode(initial)["cells"] and not viewer.playing, "Opening a replay is paused and read-only")
	var terrain_rebuilds: int = viewer.view.static_batches.terrain_rebuild_count
	viewer.view.static_batches.sync_tiles(viewer.view.tile_nodes)
	expect(viewer.view.static_batches.terrain_rebuild_count == terrain_rebuilds, "Progressive geometry matches a full publication, including shared faces at region borders")
	await control_checks(viewer)
	viewer.play_button.grab_focus()
	var shortcut := InputEventKey.new()
	shortcut.keycode = KEY_SPACE
	shortcut.pressed = true
	viewer._input(shortcut)
	expect(viewer.playing, "Space controls playback even with a focused button")
	shortcut.keycode = KEY_TAB
	viewer._input(shortcut)
	expect(viewer.view.top_down, "Configured camera view shortcut works ahead of GUI focus traversal")
	viewer._input(shortcut)
	viewer.set_playing(false)
	viewer.seek_to(1)
	expect(viewer.view.cells == Replay.decode(move_state)["cells"], "Stepping updates the rendered board")
	viewer.seek_to(0)
	viewer.set_playing(true)
	viewer.seek_to(1, true)
	expect(viewer.view.is_animating, "Playing a move uses the game's unit animation system")
	viewer.set_playing(false)
	await create_timer(0.1).timeout
	expect(viewer.view.is_animating and viewer.view.playback.speed_scale == 0.0, "Pause freezes an in-progress replay movement")
	viewer.speed = 4.0
	viewer.set_playing(true)
	for tick in range(150):
		if not viewer.view.is_animating: break
		await create_timer(0.03).timeout
	expect(not viewer.view.is_animating and viewer.view.cells == Replay.decode(move_state)["cells"], "Recorded movement finishes at the exact recorded board")
	viewer.seek_to(0)
	viewer.set_playing(true)
	viewer.seek_to(1, true)
	viewer.seek_to(0)
	expect(not viewer.view.is_animating and viewer.view.cells == Replay.decode(initial)["cells"], "Seeking during movement safely cancels animation")
	viewer.seek_to(9999)
	viewer.set_playing(true)
	viewer._process(1.0)
	expect(not viewer.playing, "Playback stops at the end of the recording")
	viewer.toggle_play()
	expect(viewer.timeline.cursor == 0 and viewer.playing, "Play at the end restarts from the opening")
	viewer.show_library()
	expect(viewer.library.visible and not viewer.playing and viewer.view == null, "Returning to the library releases the spectator island")
	viewer.load_recording(directory.path_join("missing.jsonl"))
	for tick in range(200):
		viewer._process(0.01)
		if viewer.worker == null and not viewer.building: break
		await create_timer(0.01).timeout
	expect(viewer.worker == null and viewer.library.visible and not viewer.back_button.disabled, "Failed asynchronous loads leave the browser usable")
	viewer.load_recording(path)
	for tick in range(200):
		viewer._process(0.01)
		if viewer.worker == null and not viewer.building: break
		await create_timer(0.01).timeout
	expect(viewer.worker == null and not viewer.library.visible and viewer.timeline.cursor == 0, "A valid replay can load after a failed import")
	expect(FileAccess.get_file_as_bytes(path) == original_bytes, "Watching and seeking never modifies the recording")
	viewer.show_library()
	viewer.open_file_dialog()
	var import_dialog = viewer.dialog
	expect(import_dialog != null and viewer.file_dialog_visible(), "Explicit replay import creates and opens the file picker on demand")
	viewer.dialog.hide()
	viewer.open_file_dialog()
	expect(viewer.dialog == import_dialog, "Repeated imports reuse one file picker")
	viewer.dialog.hide()
	await combat_checks(viewer)
	await filtered_animation_checks(viewer)
	await identity_checks(viewer, data)
	viewer.show_library()
	viewer.worker = preload("res://src/game/replay_job.gd").new()
	viewer.worker.start(func(): OS.delay_msec(150); return {})
	var close_started := Time.get_ticks_usec()
	viewer.show_library()
	expect(viewer.worker == null and Time.get_ticks_usec() - close_started < 100000, "Cancelling a pending read never joins its background task")
	viewer.finish_loading(data)
	viewer.poll_board_build()
	viewer.show_library()
	expect(not viewer.building and viewer.view == null, "Cancelling island construction releases the partially built board")
	viewer.load_recording(path)
	viewer.free()
	await create_timer(0.2).timeout
	viewer = null
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	app.open_replays()
	expect(is_instance_valid(app.replay_viewer) and app.game == null and app.menus.screen == app.menus.Screen.HIDDEN, "Main menu opens the spectator without creating a live match")
	expect(app.replay_viewer.library_backdrop == app.menus.menu_background.viewport.get_texture() and app.menus.menu_background.viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Replay browser reuses the menu backdrop without rendering its decorative 3D scene")
	app.replay_viewer.finish_loading(data)
	await finish_board(app.replay_viewer)
	app.replay_viewer.toggle_ui()
	expect(not app.fps_counter.visible, "Replay Hide UI also hides the application's FPS overlay")
	app.replay_viewer.show_library()
	expect(app.fps_counter.visible, "Returning to the library restores the FPS overlay")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app.replay_viewer._unhandled_input(escape)
	expect(app.replay_viewer == null and app.menus.screen == app.menus.Screen.MAIN, "Closing the viewer restores the main menu")
	await process_frame
	await process_frame
	var baseline_nodes: int = app.get_child_count()
	for cycle in range(5):
		var entry_started := Time.get_ticks_usec()
		app.open_replays()
		expect(Time.get_ticks_usec() - entry_started < 500000 and app.replay_viewer.dialog == null, "Replay entry stays lightweight without initializing filesystem browsing")
		app.replay_viewer.request_close()
		await process_frame
		await process_frame
		expect(app.get_child_count() == baseline_nodes, "Repeated replay entry and exit retain no spectator scene nodes")
	app.free()
	await process_frame
	await process_frame
	print("Replay viewer checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
