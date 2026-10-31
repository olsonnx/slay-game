extends Node3D
## Saved-match browser and spectator playback, isolated from live sessions.
signal closed
signal ui_visibility_changed(shown: bool)
const Loc = preload("res://src/localization/text.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Timeline = preload("res://src/game/replay_timeline.gd")
const Job = preload("res://src/game/replay_job.gd")
const Identity = preload("res://src/game/replay_identity.gd")
const Summary = preload("res://src/game/replay_summary.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
const Icons = preload("res://src/ui/replay_icons.gd")
const PLAYBACK_SPEEDS := [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]
const CAMERA_HOLD_SECONDS := 0.55
const LIBRARY_FPS_LIMIT := 60
const PLAYBACK_FPS_LIMIT := 120
var previous_fps_limit := 0
var timeline = Timeline.new()
var view
var worker
var library_worker
var building := false
var build_coords: Array = []
var build_index := 0
var build_groups: Dictionary = {}
var build_group_keys: Array = []
var build_group_index := 0
var published_tiles: Dictionary = {}
const BUILD_BUDGET_USEC := 4000
var requested_step := -1
var loading_timings: Dictionary = {}
var library_loading := false
var pending_files := PackedStringArray()
var pending_file_index := 0
const LIBRARY_BATCH_SIZE := 64
var playing := false
var speed := 1.0
var elapsed := 0.0
var dragging := false
var rotating := false:
	set(value):
		rotating = value
		if not value and is_instance_valid(view): view.zoom_reference = Vector2(-1, -1)
var paths: Array[String] = []
var replay_directory := Replay.DIRECTORY
var library: PanelContainer
var background: ColorRect
var list: ItemList
var message: Label
var details: Label
var slider: HSlider
var play_button: Button
var watch_button: Button
var back_button: Button
var browse_button: Button
var transport: PanelContainer
var dialog: FileDialog
var title: Label
var startup_timings: Dictionary = {}
var interface: Control
var header_panel: PanelContainer
var legend: HFlowContainer
var legend_labels: Array[Label] = []
var progress: Label
var load_buttons: Array = []
var kingdom_colors: Array = []
var library_backdrop: Texture2D
var summaries: Dictionary = {}
var metadata_worker
var metadata_target := ""
var preview_title: Label
var preview_result: Label
var preview_details: Label
var start_button: Button
var previous_button: Button
var next_button: Button
var end_button: Button
var speed_choice: OptionButton
var movement_checkbox: CheckBox
var camera_button: Button
var camera_hold_indicator: Control
var hide_ui_button: Button
var restore_ui_button: Button
var ui_hidden := false
var camera_press_held := false
var camera_press_consumed := false
var camera_press_time := 0.0

func _enter_tree() -> void:
	previous_fps_limit = Engine.max_fps
	apply_frame_limit(LIBRARY_FPS_LIMIT)

func apply_frame_limit(limit: int) -> void:
	# VSync is a separate user preference and can be disabled or driver-overridden.
	# Keep a bounded render rate throughout browsing, loading and spectating.
	Engine.max_fps = mini(previous_fps_limit, limit) if previous_fps_limit > 0 else limit

func _ready() -> void:
	var started := Time.get_ticks_usec()
	preload("res://src/ui/replay_interface.gd").build(self)
	get_viewport().size_changed.connect(layout_header)
	Keys.changed.connect(refresh_camera_button)
	startup_timings["controls_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	show_library()
	startup_timings["total_ms"] = (Time.get_ticks_usec() - started) / 1000.0

func open_file_dialog() -> void:
	# FileDialog initializes filesystem browsing when constructed, even hidden.
	# Do this only for an explicit import, never while entering the replay menu.
	if dialog == null:
		dialog = FileDialog.new()
		dialog.theme = interface.theme
		dialog.access = FileDialog.ACCESS_FILESYSTEM
		dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dialog.filters = PackedStringArray(["*.jsonl ; Replay recordings"])
		dialog.current_dir = ProjectSettings.globalize_path(replay_directory) if DirAccess.dir_exists_absolute(replay_directory) else OS.get_user_data_dir()
		dialog.file_selected.connect(load_recording)
		interface.add_child(dialog)
	dialog.popup_centered_ratio(0.8)

func file_dialog_visible() -> bool:
	return dialog != null and dialog.visible

func make_button(parent: Node, text_value: String, callback: Callable, primary := false) -> Button:
	var button := preload("res://src/ui/tooltip_button.gd").new()
	button.text = Loc.text(text_value)
	button.tooltip_text = Loc.text(text_value)
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 16)
	Ui.style_button(button, primary)
	Sound.bind_button(button)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

static func recording_label(path: String) -> String:
	var name_value := path.get_file().get_basename()
	if name_value.length() >= 19 and name_value[10] == "T":
		return name_value.substr(0, 10) + "  ·  " + name_value.substr(11, 8).replace("-", ":")
	return name_value

func refresh_library() -> void:
	if library_loading: return
	if metadata_worker != null: metadata_worker.cancel()
	metadata_worker = null
	metadata_target = ""
	preview_title.text = Loc.text("Choose a recording")
	preview_title.add_theme_color_override("font_color", Ui.TEXT)
	preview_result.text = ""
	preview_details.text = ""
	list.clear()
	paths.clear()
	pending_files.clear()
	pending_file_index = 0
	watch_button.disabled = true
	message.text = Loc.text("Loading saved replays…")
	library_loading = true
	library_worker = Job.new()
	var error: int = library_worker.start(scan_recordings.bind(replay_directory))
	if error != OK:
		library_worker = null
		library_loading = false
		message.text = Loc.text("Could not list saved replays. Try Refresh or open a replay file.")

static func scan_recordings(directory_path: String) -> Dictionary:
	var result := PackedStringArray()
	var previews := {}
	var directory := DirAccess.open(directory_path)
	if directory != null:
		var files := directory.get_files()
		files.sort()
		files.reverse()
		for filename in files:
			if filename.get_extension().to_lower() != "jsonl": continue
			result.append(filename)
			var path := directory_path.path_join(filename)
			previews[path] = Summary.read_preview(path)
	return {"files":result, "summaries":previews}

func poll_library() -> void:
	if not library_loading: return
	if library_worker != null:
		if library_worker.is_alive(): return
		var discovered: Dictionary = library_worker.wait_to_finish()
		pending_files = discovered["files"]
		summaries = discovered["summaries"]
		library_worker = null
	# Populate large libraries over multiple frames, without parsing any replay.
	var batch_end := mini(pending_files.size(), pending_file_index + LIBRARY_BATCH_SIZE)
	while pending_file_index < batch_end:
		var filename := pending_files[pending_file_index]
		paths.append(replay_directory.path_join(filename))
		var index := list.add_item(library_row(paths[-1]))
		# ItemList otherwise opens a native filename tooltip on stationary hover.
		# Filename details belong in the existing panel, without popup windows.
		list.set_item_tooltip_enabled(index, false)
		pending_file_index += 1
	if pending_file_index == pending_files.size():
		library_loading = false
		pending_files.clear()
		if message.text == Loc.text("Loading saved replays…"):
			message.text = Loc.text("Choose a recording to watch, or open a replay file from another folder.") if not paths.is_empty() else Loc.text("No saved replays yet. Save one from the results screen after a match, or open a replay file.")

func show_library() -> void:
	cancel_camera_press()
	apply_frame_limit(LIBRARY_FPS_LIMIT)
	if worker != null: worker.cancel()
	if metadata_worker != null: metadata_worker.cancel()
	metadata_worker = null
	worker = null
	building = false
	build_coords.clear()
	build_groups.clear()
	build_group_keys.clear()
	published_tiles.clear()
	requested_step = -1
	set_loading(false)
	set_playing(false)
	dragging = false
	rotating = false
	if view != null:
		# Retiring the spectator also releases its island and animation resources.
		if view.is_animating: view.cancel_motion(view.cells)
		remove_child(view)
		view.queue_free()
		view = null
	timeline = Timeline.new()
	library.show()
	header_panel.hide()
	background.show()
	transport.hide()
	set_ui_hidden(false)
	refresh_library()

func watch_selected() -> void:
	var selection := list.get_selected_items()
	if not selection.is_empty(): load_recording(paths[selection[0]])

func select_recording(index: int) -> void:
	if worker != null or index < 0 or index >= paths.size(): return
	watch_button.disabled = false
	message.text = paths[index].get_file()
	show_summary(summaries.get(paths[index], {}))
	if metadata_worker != null: metadata_worker.cancel()
	metadata_worker = null
	metadata_target = paths[index]
	# Older compact archives did not expose all metadata in their first line.
	# Decode only the selected recording, off the main thread, and cache it.
	if not summaries.get(paths[index], {}).get("details_available", false):
		metadata_worker = Job.new()
		metadata_worker.start(load_summary.bind(paths[index], metadata_worker))

func library_row(path: String) -> String:
	var summary: Dictionary = summaries.get(path, {})
	if summary.is_empty() or summary.get("preview_error", false): return recording_label(path)
	var date: String = str(summary.get("created_utc", "")).replace("T", " ").substr(0, 16)
	if date == "": date = recording_label(path)
	return "%s · %s · %s" % [Summary.players(summary), Summary.outcome(summary), date]

func show_summary(summary: Dictionary) -> void:
	if summary.is_empty() or summary.get("preview_error", false):
		preview_title.text = Loc.text("Replay details unavailable")
		preview_result.text = ""
		preview_details.text = ""
		return
	preview_title.text = Summary.players(summary)
	preview_result.text = Summary.outcome(summary)
	preview_details.text = Summary.description(summary)
	var palette := Identity.resolve({"metadata":{"factions":summary.get("factions", []), "match":summary.get("match", {})}})
	var humans: Array = summary.get("humans", [])
	var faction: int = int(humans[0]) if not humans.is_empty() else -1
	preview_title.add_theme_color_override("font_color", palette["colors"][faction] if faction >= 0 and faction < palette["colors"].size() else Ui.TEXT)

static func load_summary(path: String, job) -> Dictionary:
	var data := Replay.read_replay(path, true, job.is_cancelled)
	if data.get("error", "Invalid replay") != "": return {"preview_error":true}
	var summary := Summary.from_records(data["header"], data["commands"])
	if not Summary.valid_preview(summary): return {"preview_error":true}
	summary["details_available"] = true
	return summary

func poll_metadata() -> void:
	if metadata_worker == null or metadata_worker.is_alive(): return
	var summary: Dictionary = metadata_worker.wait_to_finish()
	metadata_worker = null
	summaries[metadata_target] = summary
	var selected := list.get_selected_items()
	if not selected.is_empty() and selected[0] < paths.size() and paths[selected[0]] == metadata_target:
		show_summary(summary)
		list.set_item_text(selected[0], library_row(metadata_target))

func load_recording(path: String) -> void:
	if worker != null or building: return
	if metadata_worker != null: metadata_worker.cancel()
	metadata_worker = null
	apply_frame_limit(LIBRARY_FPS_LIMIT)
	set_playing(false)
	message.text = Loc.text("Loading replay…")
	set_loading(true)
	worker = Job.new()
	var error: int = worker.start(prepare_recording.bind(path, worker))
	if error != OK:
		worker = null
		set_loading(false)
		message.text = Loc.text("Could not load the replay.")
	else:
		title.text = recording_label(path)

func set_loading(loading: bool) -> void:
	# Back and Choose recording remain usable while reading/building.
	back_button.disabled = false
	browse_button.disabled = false
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE if loading else Control.MOUSE_FILTER_STOP
	for button in load_buttons: button.disabled = loading
	if not loading: watch_button.disabled = list.get_selected_items().is_empty()

static func prepare_recording(path: String, job) -> Dictionary:
	var started := Time.get_ticks_usec()
	var data := Replay.read_replay(path, true, job.is_cancelled)
	var replacement = Timeline.new()
	var error: String = replacement.open(data, job.is_cancelled)
	return {"error":error, "timeline":replacement, "load_ms":(Time.get_ticks_usec() - started) / 1000.0}

func finish_loading(data: Dictionary) -> bool:
	var replacement = data.get("timeline")
	var error: String = data.get("error", "Invalid replay")
	# Direct data injection remains useful to inspection tools and fixtures.
	if replacement == null and error == "":
		replacement = Timeline.new()
		error = replacement.open(data)
	if error != "":
		set_loading(false)
		message.text = Loc.text("Could not load the replay.") + "\n" + error
		return false
	timeline = replacement
	timeline.set_movement_only(movement_checkbox.button_pressed)
	loading_timings = {"read_and_index_ms":data.get("load_ms", 0.0)}
	if view != null:
		if view.is_animating: view.cancel_motion(view.cells)
		remove_child(view)
		view.queue_free()
	var started := Time.get_ticks_usec()
	view = load("res://src/rendering/board_view.gd").new()
	var identity := Identity.resolve(timeline.header)
	view.COLORS = identity["terrain"]
	kingdom_colors = identity["colors"]
	add_child(view)
	build_legend()
	loading_timings["board_ready_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	view.controls_enabled = false
	view.set_active(false)
	view.hide()
	# Smaller spectator chunks let initial geometry publication span frames too.
	view.static_batches.chunk_size = 8
	view.static_batches.terrain_group_size = 8
	view.cells = timeline.position["cells"].duplicate(true)
	build_coords = view.cells.keys()
	build_index = 0
	build_groups.clear()
	build_group_keys.clear()
	build_group_index = 0
	published_tiles.clear()
	building = true
	set_loading(true)
	return true

func poll_board_build() -> void:
	if not building: return
	var started := Time.get_ticks_usec()
	while build_index < build_coords.size():
		var coord = build_coords[build_index]
		view.build_tile(coord, view.cells[coord])
		# Material inspection and geometry extraction share the construction budget.
		view.static_batches.parts_for_tile(view.tile_nodes[coord])
		var group := Vector2i(floori(float(coord.x) / 8), floori(float(coord.y) / 8))
		if not build_groups.has(group):
			build_groups[group] = {}
			build_group_keys.append(group)
		build_groups[group][coord] = view.tile_nodes[coord]
		build_index += 1
		message.text = Loc.text("Loading replay…") + " %d / %d" % [build_index, build_coords.size()]
		if Time.get_ticks_usec() - started >= BUILD_BUDGET_USEC:
			loading_timings["max_build_batch_ms"] = maxf(loading_timings.get("max_build_batch_ms", 0.0), (Time.get_ticks_usec() - started) / 1000.0)
			return
	if build_group_index < build_group_keys.size():
		published_tiles.merge(build_groups[build_group_keys[build_group_index]])
		view.static_batches.sync_tiles(published_tiles, {}, false, view.tile_nodes)
		build_group_index += 1
		loading_timings["max_publish_batch_ms"] = maxf(loading_timings.get("max_publish_batch_ms", 0.0), (Time.get_ticks_usec() - started) / 1000.0)
		return
	building = false
	build_coords.clear()
	build_groups.clear()
	build_group_keys.clear()
	published_tiles.clear()
	view.notify_visible_board_changed()
	var size_id: String = str(timeline.header.get("map_size", "small"))
	view.configure_map(size_id, preload("res://src/game/map_sizes.gd").generation_bounds(size_id), view.cells)
	view.reset_camera()
	view.show()
	view.set_active(true)
	view.controls_enabled = false
	await view.lighting.warmup()
	view.controls_enabled = true
	refresh_camera_button()
	set_loading(false)
	dragging = false
	rotating = false
	library.hide()
	header_panel.show()
	apply_frame_limit(PLAYBACK_FPS_LIMIT)
	background.hide()
	transport.show()
	set_ui_hidden(false)
	slider.max_value = maxi(1, timeline.steps.size() - 1)
	slider.editable = timeline.steps.size() > 1
	refresh_transport()
	loading_timings["finalize_ms"] = (Time.get_ticks_usec() - started) / 1000.0

func set_playing(value: bool) -> void:
	playing = value
	elapsed = 0.0
	if play_button != null:
		play_button.icon = Icons.get_icon("pause" if playing else "play", true)
		play_button.tooltip_text = Loc.text("Pause · Space") if playing else Loc.text("Play · Space")
	update_playback_speed()

func update_playback_speed() -> void:
	if view != null: view.playback.set_speed_scale(speed if playing else 0.0)

func select_speed(index: int) -> void:
	if index < 0 or index >= PLAYBACK_SPEEDS.size(): return
	speed = PLAYBACK_SPEEDS[index]
	update_playback_speed()

func set_movement_only(enabled: bool) -> void:
	if view == null or building: return
	set_playing(false)
	if view.is_animating: view.cancel_motion(timeline.position["cells"])
	timeline.set_movement_only(enabled)
	view.render_cells(timeline.position["cells"])
	slider.max_value = maxi(1, timeline.steps.size() - 1)
	slider.editable = timeline.steps.size() > 1
	refresh_transport()

func toggle_ui() -> void:
	if view == null or building or library.visible: return
	set_ui_hidden(not ui_hidden)

func set_ui_hidden(hidden: bool) -> void:
	cancel_camera_press()
	ui_hidden = hidden
	var viewing := view != null and not building and not library.visible
	header_panel.visible = viewing and not hidden
	transport.visible = viewing and not hidden
	restore_ui_button.visible = viewing and hidden
	if hidden:
		dragging = false
		rotating = false
	ui_visibility_changed.emit(not hidden)

func begin_camera_press() -> void:
	camera_press_held = true
	camera_press_consumed = false
	camera_press_time = 0.0
	camera_hold_indicator.progress = 0.0

func end_camera_press() -> void:
	camera_press_held = false
	camera_hold_indicator.progress = 0.0

func cancel_camera_press() -> void:
	camera_press_held = false
	camera_press_consumed = true
	if camera_hold_indicator != null: camera_hold_indicator.progress = 0.0

func advance_camera_press(delta: float) -> void:
	if not camera_press_held or camera_press_consumed or view == null: return
	camera_press_time += delta
	camera_hold_indicator.progress = camera_press_time / CAMERA_HOLD_SECONDS
	if camera_press_time >= CAMERA_HOLD_SECONDS:
		camera_press_consumed = true
		center_camera()

func camera_activated() -> void:
	if not camera_press_consumed: toggle_camera_view()

func toggle_camera_view() -> void:
	if view == null: return
	view.toggle_top_down()
	refresh_camera_button()

func center_camera() -> void:
	if view == null: return
	view.reset_camera()
	refresh_camera_button()

func refresh_camera_button() -> void:
	if camera_button == null or view == null: return
	camera_button.icon = preload("res://assets/ui/view_top.svg") if view.top_down else preload("res://assets/ui/view_3d.svg")
	camera_button.tooltip_text = Loc.text("%s · %s\nHold: centre / reset camera") % [Loc.text("3D view" if view.top_down else "Top-down"), Keys.key_name("view")]
	camera_button.tooltip_text += "\n" + Loc.text("Wheel: zoom · right drag: rotate · middle drag: pan\nHome: centre camera")

func layout_header() -> void:
	if header_panel == null or title == null: return
	var font := title.get_theme_font("font")
	var natural := font.get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 80
	var legend_width := 28.0
	for label in legend_labels:
		if label.visible: legend_width += label.custom_minimum_size.x + 16
	natural = maxf(natural, legend_width)
	header_panel.size = Vector2(clampf(natural, 240, minf(720, get_viewport().get_visible_rect().size.x - 40)), 0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel_camera_press()
		dragging = false
		rotating = false

func toggle_play() -> void:
	if view == null or library.visible or building: return
	if not playing and timeline.cursor == timeline.steps.size() - 1: seek_to(0)
	set_playing(not playing)

func seek_to(step: int, animate := false) -> void:
	if view == null or building: return
	requested_step = -1
	if not animate: set_playing(false)
	if view.is_animating: view.cancel_motion(timeline.position["cells"])
	var before: Dictionary = timeline.position["cells"]
	var target := clampi(step, 0, timeline.steps.size() - 1)
	if animate and timeline.movement_only and timeline.steps[target] > 0 and (timeline.commands[timeline.steps[target] - 1]["action"] == "move" or timeline.commands[timeline.steps[target] - 1]["action"].begins_with("wildlife_")):
		# Skipped recruit/settlement patches must be visible before animating the
		# next move, whose source may not exist in the previous movement frame.
		before = timeline.before_step(target)["cells"]
		view.render_cells(before)
	timeline.seek(step)
	var action: Dictionary = timeline.movement(before) if animate else {}
	var wildlife_action: Dictionary = timeline.wildlife_action(before) if animate else {}
	if not wildlife_action.is_empty():
		view.wildlife.play_world([wildlife_action],timeline.position["cells"])
	elif action.is_empty():
		view.render_cells(timeline.position["cells"])
	else:
		view.playback.animate_moves([action], timeline.position["cells"])
	elapsed = 0.0
	refresh_transport()

func refresh_transport() -> void:
	slider.set_value_no_signal(timeline.cursor)
	var row: Dictionary = timeline.current_command()
	if view != null: view.birds.set_round(int(row.get("round", 1)))
	if row.is_empty():
		details.text = Loc.text("Starting position")
		details.add_theme_color_override("font_color", Ui.TEXT)
	else:
		var faction := int(row["faction"])
		var names: Array = timeline.header.get("names", [])
		var owner: String = str(names[faction]) if faction >= 0 and faction < names.size() else Loc.text("World")
		details.text = Loc.text("Round %d · %s · %s") % [int(row["round"]), owner, str(row["action"]).replace("_", " ").capitalize()]
		details.add_theme_color_override("font_color", kingdom_colors[faction] if faction >= 0 and faction < kingdom_colors.size() else Ui.TEXT)
	if timeline.cursor == timeline.steps.size() - 1: details.text += " · " + Loc.text("End of replay")
	progress.text = "%d / %d" % [timeline.cursor, timeline.steps.size() - 1]
	var count: int = timeline.position.get("faction_count", timeline.header.get("factions", 0))
	for index in range(legend_labels.size()): legend_labels[index].visible = index < count
	layout_header()
	if playing and timeline.cursor == timeline.steps.size() - 1 and not view.is_animating: set_playing(false)

func build_legend() -> void:
	for child in legend.get_children():
		legend.remove_child(child)
		child.queue_free()
	legend_labels.clear()
	var names: Array = timeline.header.get("names", [])
	for index in range(mini(names.size(), kingdom_colors.size())):
		var label := preload("res://src/ui/replay_interface.gd").label(legend, "●  " + str(names[index]), 14, kingdom_colors[index])
		label.custom_minimum_size.x = minf(180, label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 2)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.clip_text = true
		legend_labels.append(label)

func _process(delta: float) -> void:
	poll_library()
	poll_metadata()
	advance_camera_press(delta)
	if worker != null and not worker.is_alive():
		var data: Dictionary = worker.wait_to_finish()
		worker = null
		finish_loading(data)
	poll_board_build()
	if building: return
	if requested_step >= 0:
		var target := requested_step
		requested_step = -1
		seek_to(target)
	if view == null: return
	view.controls_enabled = not library.visible and not file_dialog_visible()
	if not playing or view.is_animating or library.visible: return
	if timeline.cursor == timeline.steps.size() - 1:
		set_playing(false)
		return
	elapsed += delta * speed
	if elapsed >= 0.8: seek_to(timeline.cursor + 1, true)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE: dragging = false
		if event.button_index == MOUSE_BUTTON_RIGHT: rotating = false
	if view == null or building or library.visible or file_dialog_visible(): return
	if event is InputEventKey and event.pressed and not event.echo:
		# Spectator shortcuts also work when a playback button has GUI focus.
		var handled := true
		match event.keycode:
			KEY_SPACE:
				if movement_checkbox.has_focus(): return
				toggle_play()
			KEY_LEFT: seek_to(timeline.cursor - 1)
			KEY_RIGHT: seek_to(timeline.cursor + 1)
			KEY_HOME: center_camera()
			KEY_END: seek_to(timeline.steps.size() - 1)
			KEY_F10: toggle_ui()
			_:
				if Keys.matches(event, "view"): toggle_camera_view()
				else: handled = false
		if handled: get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		if dragging: view.drag_pan(event.relative)
		if rotating:
			view.orbit(event.relative)
			refresh_camera_button()

func _unhandled_input(event: InputEvent) -> void:
	if file_dialog_visible(): return
	if event is InputEventKey and event.pressed and not event.echo:
		var input_viewport := get_viewport()
		if event.keycode == KEY_ESCAPE:
			if ui_hidden: set_ui_hidden(false)
			elif library.visible: request_close()
			else: show_library()
		input_viewport.set_input_as_handled()
	if view == null or library.visible: return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: view.change_zoom(1, event.position)
			MOUSE_BUTTON_WHEEL_DOWN: view.change_zoom(-1, event.position)
			MOUSE_BUTTON_MIDDLE: dragging = true
			MOUSE_BUTTON_RIGHT:
				rotating = true
				view.zoom_reference = event.position

func request_close() -> void:
	set_playing(false)
	closed.emit()

func _exit_tree() -> void:
	cancel_camera_press()
	ui_visibility_changed.emit(true)
	Engine.max_fps = previous_fps_limit
	# Worker callables own only their job and immutable path, so pending reads
	# can finish safely after this viewer has gone away.
	if worker != null: worker.cancel()
	if metadata_worker != null: metadata_worker.cancel()
	metadata_worker = null
	worker = null
	library_worker = null
	if is_instance_valid(view) and view.is_animating: view.cancel_motion(view.cells)
