extends "res://src/editor/editor_compatibility.gd"
const Loc = preload("res://src/localization/text.gd")
signal back_requested
signal play_requested(data: Dictionary)
const Document = preload("res://src/editor/level_document.gd")
const Hud = preload("res://src/ui/game_hud.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const TOOL_GROUPS = preload("res://src/editor/editor_view.gd").TOOL_GROUPS
var document = Document.new()
var view
var random_values := false
var event_id := ""
var player_marker: Label3D
var brush_preview: MeshInstance3D
var brush_preview_land: StandardMaterial3D
var brush_preview_water: StandardMaterial3D
var brush_rng := RandomNumberGenerator.new()
var pending_action: Callable
var stroke = preload("res://src/editor/brush_stroke.gd").new()
var painting: bool:
	get: return stroke.active
var removing: bool:
	get: return stroke.removing
var rotating := false:
	set(value):
		rotating = value
		if not value and is_instance_valid(view): view.zoom_reference = Vector2(-1, -1)
var panning := false
var file_path := ""
var suspended := false
var loading_map := false
var loading_camera_mask := 1
var pointer_position := Vector2.ZERO
var document_status := ""
var previous_fps_limit := 0
var owns_fps_limit := false

func _enter_tree() -> void:
	previous_fps_limit = Engine.max_fps
	Engine.max_fps = mini(previous_fps_limit, 120) if previous_fps_limit > 0 else 120
	owns_fps_limit = true

func _exit_tree() -> void:
	if owns_fps_limit:
		Engine.max_fps = previous_fps_limit
		owns_fps_limit = false

func _ready() -> void:
	view = preload("res://src/rendering/board_view.gd").new()
	add_child(view)
	# Smaller upload regions keep whole-map editor replacements responsive.
	view.static_batches.chunk_size = 12
	brush_preview = MeshInstance3D.new()
	brush_preview.name = "EditorBrushPreview"
	brush_preview.mesh = view.outline_mesh
	brush_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	brush_preview_land = view.material(Color("f2eed6"), true, true)
	brush_preview_water = view.material(Color("95c9ee"), true, true)
	brush_preview.hide()
	view.overlay_root.add_child(brush_preview)
	ui.layer = 20
	ui.action_requested.connect(_on_view_action)
	ui.focus_release_requested.connect(release_text_focus)
	ui.title_changed.connect(func(value: String): document.title = value; update_status())
	ui.gold_changed.connect(func(value: int): document.starting_gold = value; update_status())
	ui.owner_changed.connect(func(): end_stroke(); update_status())
	ui.value_changed.connect(func(): end_stroke(); update_status())
	ui.random_values_changed.connect(set_random_values)
	ui.brush_changed.connect(update_status)
	ui.file_chosen.connect(file_selected)
	ui.discard_confirmed.connect(discard_changes)
	ui.discard_cancelled.connect(func(): pending_action = Callable())
	ui.shortcuts_requested.connect(refresh_help)
	ui.build_ui()
	brush_rng.randomize()
	view.value_heatmap.changed.connect(refresh_heatmap)
	view.visible_board_changed.connect(refresh_heatmap)
	Keys.changed.connect(refresh_help)
	document.generate("small", Gameplay.rule_mode)
	refresh(true)
	select_tool("Land")

func active_tool() -> String:
	return Document.TOOLS[ui.tool_choice.selected]

func select_tool(tool: String) -> void:
	if tool not in Document.TOOLS: return
	end_stroke()
	release_text_focus()
	ui.tool_choice.select(Document.TOOLS.find(tool))
	ui.tool_panel.close()
	ui.help_panel.hide()
	ui.render_context(tool, true)
	update_status()
	for button in ui.tool_buttons:
		button.set_pressed_no_signal(button.get_meta("tool") == tool)

func open_tools(group: String) -> void:
	end_stroke()
	if ui.tool_panel.visible and ui.tool_group == group:
		ui.tool_panel.close()
		ui.render_context(active_tool())
		return
	var tools: Array = TOOL_GROUPS[group]
	if active_tool() not in tools: select_tool(tools[0])
	ui.context_panel.close()
	ui.render_tools(group, document.rule_mode, active_tool(), view.unit_icon_texture)

func refresh_view_icon() -> void:
	ui.view_button.icon = Hud.VIEW_TOP_ICON if view.top_down else Hud.VIEW_3D_ICON

func select_player_start() -> void:
	ui.tool_panel.close()
	select_tool("Player start")
	update_status(Loc.text("Click an owned province to mark the starting kingdom. Right click removes the marker."))

func refresh_player_marker() -> void:
	if not is_instance_valid(player_marker):
		player_marker = Label3D.new()
		player_marker.name = "PlayerStartMarker"
		player_marker.text = Loc.text("PLAYER START") + "\n▼"
		player_marker.font_size = 40
		player_marker.pixel_size = 0.008
		player_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		player_marker.modulate = Color("ffe5a2")
		player_marker.outline_modulate = Color("25342d")
		player_marker.outline_size = 6
		player_marker.no_depth_test = true
		view.add_child(player_marker)
	player_marker.visible = document.player_start != Document.Rules.NONE
	if player_marker.visible:
		player_marker.position = view.coord_position(document.player_start) + Vector3(0, 2.8, 0)
		player_marker.modulate = Color("ffe5a2") if document.player_faction >= 0 else Color("ed8c79")

func refresh_player_labels() -> void:
	var selected_owner: int = ui.owner_choice.selected - 1
	ui.owner_choice.clear()
	ui.owner_choice.add_item(Loc.text("Neutral"))
	for faction in range(document.factions.size()):
		ui.owner_choice.add_item(document.factions[faction]["name"] + (Loc.text(" (Player)") if faction == document.player_faction else ""))
	ui.owner_choice.select(clampi(selected_owner + 1, 0, document.factions.size()))
	refresh_player_marker()

func close_context() -> void:
	end_stroke()
	release_text_focus()
	ui.context_panel.close()

func set_event(id: String) -> void:
	end_stroke()
	event_id = id if Document.Events.EVENTS.has(id) else ""
	update_status()

func select_event(id: String) -> void:
	if not Document.Events.EVENTS.has(id): return
	ui.selected_event = id
	ui.filter_events()
	set_event(id)
	select_tool("Event")

func toggle_settings() -> void:
	end_stroke()
	release_text_focus()
	ui.settings_shade.visible = not ui.settings_shade.visible
	ui.context_panel.close()
	ui.help_panel.hide()
	ui.tool_panel.close()

func update_status(message := "") -> void:
	# Recompute document state only after edits/settings/save/undo, never hover.
	ui.undo_button.disabled = document.undo_stack.is_empty()
	ui.redo_button.disabled = document.redo_stack.is_empty()
	document_status = Loc.text("EDITOR%s  /  %s  /  %d TILES  /  %s: %s") % [" *" if painting or document.dirty() else "", Loc.text("MAP"), document.cells.size(), Loc.text("Tiles" if active_tool() in Document.TILE_TOOLS else "Paint").to_upper(), Loc.text(active_tool()).to_upper()]
	show_pointer_status(message)
	ui.brush_label.text = Loc.text(active_tool())

func update_brush_preview(coord: Vector2i) -> void:
	brush_preview.visible = not loading_map and not view.value_heatmap.active and document.in_bounds(coord)
	if not brush_preview.visible: return
	var position_wanted: Vector3 = view.coord_position(coord) + Vector3(0, 0.026, 0)
	if brush_preview.position != position_wanted: brush_preview.position = position_wanted
	var material: StandardMaterial3D = brush_preview_land if document.cells.has(coord) else brush_preview_water
	if brush_preview.material_override != material: brush_preview.material_override = material

func show_pointer_status(message := "") -> void:
	var text: String = message if message != "" else document_status
	if ui.status.text != text: ui.status.text = text

func refresh(reset_view := false, render_board := true) -> void:
	brush_preview.hide()
	ui.name_edit.set_block_signals(true)
	ui.name_edit.text = document.title
	ui.name_edit.set_block_signals(false)
	ui.gold_choice.set_value_no_signal(document.starting_gold)
	view.COLORS = document.faction_colors("terrain")
	refresh_player_labels()
	ui.size_choice.select(maxi(0, Document.Sizes.IDS.find(document.map_size)))
	ui.events_enabled = true
	ui.filter_events()
	ui.category_buttons["Events"].disabled = not ui.events_enabled
	if ui.tool_choice.is_item_disabled(ui.tool_choice.selected): ui.tool_choice.select(0)
	view.configure_map(document.map_size, Document.Sizes.generation_bounds(document.map_size) + Vector2(5.7, 6), document.cells)
	if render_board: view.render_cells(document.cells)
	if ui.tool_panel.visible:
		var group: String = ui.tool_group
		ui.tool_panel.close()
		open_tools(group)
	elif ui.context_panel.visible:
		ui.render_context(active_tool())
	if reset_view:
		view.reset_camera()
		center_camera()
	update_status()
	refresh_view_icon()

func center_camera() -> void:
	release_text_focus()
	view.reset_camera()
	refresh_view_icon()

func undo() -> void:
	end_stroke()
	document.undo()
	refresh()

func redo() -> void:
	end_stroke()
	document.redo()
	refresh()

func toggle_view() -> void:
	release_text_focus()
	view.toggle_top_down()
	refresh_view_icon()

func toggle_heatmap() -> void:
	end_stroke()
	release_text_focus()
	view.value_heatmap.set_active(not view.value_heatmap.active)
	brush_preview.hide()
	refresh_heatmap()

func refresh_heatmap() -> void:
	var active: bool = view.value_heatmap.active
	ui.heatmap_button.set_pressed_no_signal(active)
	ui.heatmap_legend.visible = active
	var maximum: int = maxi(1, view.value_heatmap.maximum)
	ui.heatmap_gradient.offsets = PackedFloat32Array([0, 0.5, 1])
	ui.heatmap_gradient.colors = PackedColorArray([view.value_heatmap.value_color(1, maximum), view.value_heatmap.value_color(maximum / 2.0 + 0.5, maximum), view.value_heatmap.value_color(maximum, maximum)])
	ui.heatmap_range_label.text = Loc.text("0: mountain / bridge     Land: 1–%d") % maximum

func set_random_values(enabled: bool) -> void:
	end_stroke()
	random_values = enabled
	ui.random_toggle.set_pressed_no_signal(enabled)
	ui.value_choice.editable = not enabled
	release_text_focus()
	update_status()

func release_text_focus() -> void:
	if not is_inside_tree(): return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit and focus.get_parent() is SpinBox:
		var spin: SpinBox = focus.get_parent()
		spin.apply()
	get_viewport().gui_release_focus()
	if is_instance_valid(view): view.controls_enabled = not modal_open()

func modal_open() -> bool:
	return loading_map or ui.file_dialog.visible or ui.confirm.visible or ui.settings_shade.visible or ui.variant_choice.get_popup().visible or ui.owner_choice.get_popup().visible or ui.size_choice.get_popup().visible

func pointer_over_ui(position: Vector2) -> bool:
	if modal_open(): return true
	for control in ui.ui_blockers:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(position): return true
	return false

func refresh_help() -> void:
	ui.undo_button.tooltip_text = Loc.text("Undo stroke · Ctrl+Z")
	ui.redo_button.tooltip_text = Loc.text("Redo stroke · Ctrl+Y / Ctrl+Shift+Z")
	for group in ui.category_buttons:
		if group in ["Events", "Start"]:
			ui.category_buttons[group].tooltip_text = Loc.text("Search and paint events.") if group == "Events" else Loc.text("Mark the player's starting kingdom on the map.")
			continue
		var key: String = "T" if group == "Tiles" else Keys.key_name("recruit" if group == "Units" else "build" if group == "Build" else "spells")
		ui.category_buttons[group].tooltip_text = Loc.text("%s · %s\nRight drag: %s") % [Loc.text(group), key, Loc.text("delete tiles" if group == "Tiles" else "clear decorations")]
	ui.heatmap_button.tooltip_text = Loc.text("Province value heatmap · ") + Keys.key_name("heatmap")
	ui.view_button.tooltip_text = Loc.text("Overhead / 3D · ") + Keys.key_name("view") + Loc.text("\nHome: centre · Alt + right drag: rotate")
	ui.help_text.text = Loc.text("Left drag: place / paint\nRight drag: Tiles deletes tiles; Paint clears decorations\nAlt + right drag: rotate · middle drag / wheel: pan / zoom\n%s / %s / %s / %s: pan\n%s: overhead / 3D · %s: value heatmap\nT / %s / %s / %s: Tiles / Units / Build / Paint\n1–6: choose card in open panel\nI / Alt + left click: eyedropper · V: random 1–3\nHome: center · F5: playtest\nCtrl+Z / Ctrl+Y: undo / redo\nCtrl+S: save · Ctrl+Shift+S: save as · Ctrl+O: load\nEnter / map interaction: finish text editing\nEscape: close panel / island settings") % [Keys.key_name("pan_up"), Keys.key_name("pan_left"), Keys.key_name("pan_down"), Keys.key_name("pan_right"), Keys.key_name("view"), Keys.key_name("heatmap"), Keys.key_name("recruit"), Keys.key_name("build"), Keys.key_name("spells")]

func sample_at(position: Vector2) -> void:
	end_stroke()
	release_text_focus()
	var coord: Vector2i = view.hex_at_screen(position)
	if not document.cells.has(coord): return
	var cell: Dictionary = document.cells[coord]
	ui.owner_choice.select(cell["owner"] + 1)
	set_random_values(false)
	ui.value_choice.set_value_no_signal(maxi(1, cell["value"]))
	var tool := "Land"
	if cell["mountain"]: tool = "Mountain"
	elif cell["building"] == "bridge": tool = "Bridge"
	elif cell.get("lair", "") != "":
		tool = Document.LAIR_TOOLS.find_key(cell.lair)
	elif cell["event"] != "":
		event_id = cell["event"]
		ui.selected_event = event_id
		tool = "Event"
	elif cell["unit"] > 0: tool = ["Scout", "Soldier", "Knight"][cell["unit"] - 1]
	elif cell["capital"] >= 0: tool = "Capital"
	elif cell["building"] != "": tool = str(cell["building"]).capitalize()
	elif cell["tree"]: tool = "Tree"
	elif cell["grave"]: tool = "Grave"
	elif cell.get("ore_source", false): tool = "Ore source"
	elif cell["mana_source"]: tool = "Mana source"
	select_tool(tool)
	update_status(Loc.text("Picked %s · value %d · %s") % [Loc.text(tool), cell["value"], Loc.text("Neutral") if cell["owner"] < 0 else document.factions[cell["owner"]]["name"]])

func save_level(save_as := false) -> void:
	end_stroke()
	release_text_focus()
	if file_path == "" or save_as: open_save()
	else:
		ui.file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		file_selected(file_path)

func begin_map_load():
	loading_map = true
	brush_preview.hide()
	end_stroke()
	rotating = false
	panning = false
	view.controls_enabled = false
	view.stop_camera_pan()
	view.birds.set_loading(true)
	loading_camera_mask = view.camera.cull_mask
	view.camera.cull_mask = 0
	view.process_mode = Node.PROCESS_MODE_DISABLED
	var preparation = preload("res://src/ui/preparation_screen.gd").new()
	add_child(preparation)
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	return preparation

func finish_map_load(preparation) -> void:
	refresh(true, false)
	await view.replace_cells(document.cells)
	view.camera.cull_mask = loading_camera_mask
	await view.lighting.warmup()
	# Warm the replacement beneath the cover before revealing it.
	for frame in range(2):
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	view.process_mode = Node.PROCESS_MODE_INHERIT
	view.birds.set_loading(false)
	await preparation.reveal()
	loading_map = false
	view.controls_enabled = not modal_open()

func new_island(blank: bool) -> void:
	if loading_map: return
	var size_id: String = Document.Sizes.IDS[ui.size_choice.selected]
	var mode := "modern"
	ui.settings_shade.hide()
	var preparation = await begin_map_load()
	var replacement = Document.new()
	replacement.title = document.title
	if blank:
		replacement.generate(size_id, mode, true)
	else:
		var task := WorkerThreadPool.add_task(replacement.generate.bind(size_id, mode, false), false, "Prepare editor island")
		while not WorkerThreadPool.is_task_completed(task): await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(task)
	document = replacement
	file_path = ""
	await finish_map_load(preparation)

func discard_changes() -> void:
	var action := pending_action
	pending_action = Callable()
	if action.is_valid(): action.call()

func request_action(action: Callable) -> void:
	if ui.confirm.visible: return
	end_stroke()
	release_text_focus()
	if document.dirty():
		pending_action = action
		ui.confirm.popup_centered()
		view.controls_enabled = false
	else: action.call()

func prepare_files() -> void:
	DirAccess.make_dir_recursive_absolute("user://levels")
	ui.file_dialog.current_dir = file_path.get_base_dir() if file_path != "" else OS.get_user_data_dir().path_join("levels")

func open_save() -> void:
	end_stroke()
	prepare_files()
	ui.file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	ui.file_dialog.title = "Save level"
	ui.file_dialog.current_file = file_path.get_file() if file_path != "" else document.title.validate_filename() + ".json"
	ui.file_dialog.popup_centered_ratio(0.75)

func open_load() -> void:
	end_stroke()
	prepare_files()
	ui.file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	ui.file_dialog.title = "Load level"
	ui.file_dialog.popup_centered_ratio(0.75)

func file_selected(path: String) -> void:
	if loading_map: return
	if ui.file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		if not path.to_lower().ends_with(".json"): path += ".json"
		var error: Error = document.save_file(path)
		if error != OK:
			update_status(Loc.text("Could not finish saving the level."))
			return
		file_path = path
		update_status(Loc.text("Saved %s") % path.get_file())
	else:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 2000000:
			update_status(Loc.text("Could not open this level."))
			return
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		file.close()
		if parse_error != OK:
			update_status(Loc.text("This is not a supported Slay level."))
			return
		var error: String = document.read_data(parser.data)
		if error != "":
			update_status(error)
			return
		file_path = path
		var preparation = await begin_map_load()
		await finish_map_load(preparation)
		update_status(Loc.text("Loaded %s") % path.get_file())

func playtest() -> void:
	end_stroke()
	release_text_focus()
	var error: String = document.playable_error()
	if error != "":
		update_status(error)
		return
	play_requested.emit(document.state())

func set_suspended(value: bool) -> void:
	suspended = value
	end_stroke()
	rotating = false
	panning = false
	view.set_active(not value)
	visible = not value
	ui.visible = not value
	process_mode = Node.PROCESS_MODE_DISABLED if value else Node.PROCESS_MODE_INHERIT

func end_stroke() -> void:
	stroke.finish(document)
	if is_instance_valid(ui.status): update_status()

func paint_at(position: Vector2) -> void:
	var hit: Dictionary = view.pick_at_screen(position, true)
	if stroke.paint(document, hit["coord"], active_tool(), ui.owner_choice.selected - 1, int(ui.value_choice.value), random_values, brush_rng, event_id):
		view.render_cells(document.cells)
		update_brush_preview(hit["coord"])
		refresh_player_labels()
		update_status()

func handle_shortcut(event: InputEventKey) -> bool:
	if not event.pressed or event.echo: return false
	if modal_open():
		if ui.confirm.visible: return false
		if ui.settings_shade.visible and event.keycode == KEY_ESCAPE:
			toggle_settings()
			return true
		return false
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit
	# Reserve Tab before LineEdit/Control can use it for focus traversal.
	if event.keycode == KEY_TAB or (not typing and Keys.matches(event, "view")):
		toggle_view()
		return true
	if event.keycode == KEY_F5:
		playtest()
		return true
	if typing and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		release_text_focus()
		return true
	if typing and not pointer_over_ui(pointer_position):
		release_text_focus()
		typing = false
	if event.ctrl_pressed:
		if event.keycode == KEY_S:
			save_level(event.shift_pressed)
			return true
		if event.keycode == KEY_O:
			release_text_focus()
			request_action(open_load)
			return true
		if not typing and event.keycode in [KEY_Z, KEY_Y]:
			if event.keycode == KEY_Y or event.shift_pressed: redo()
			else: undo()
			return true
		return false
	if typing: return false
	if Keys.matches(event, "view"):
		toggle_view()
	elif Keys.matches(event, "heatmap"):
		toggle_heatmap()
	elif event.keycode == KEY_HOME:
		center_camera()
	elif event.keycode == KEY_I:
		sample_at(pointer_position)
	elif event.keycode == KEY_V:
		set_random_values(not random_values)
	elif event.keycode == KEY_T:
		open_tools("Tiles")
		select_tool("Land")
	elif Keys.matches(event, "recruit"):
		open_tools("Units")
	elif Keys.matches(event, "build"):
		open_tools("Build")
	elif Keys.matches(event, "spells"):
		open_tools("Paint")
	elif event.keycode >= KEY_1 and event.keycode <= KEY_9 and ui.tool_panel.visible:
		var index := event.keycode - KEY_1
		if index < ui.tool_buttons.size() and not ui.tool_buttons[index].disabled:
			select_tool(ui.tool_buttons[index].get_meta("tool"))
	elif event.keycode == KEY_ESCAPE or Keys.matches(event, "cancel"):
		end_stroke()
		if ui.tool_panel.visible: ui.tool_panel.close()
		elif ui.context_panel.visible: close_context()
		elif ui.help_panel.visible: ui.help_panel.hide()
		else: toggle_settings()
	else: return false
	return true

func _input(event: InputEvent) -> void:
	if loading_map: return
	if suspended: return
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		pointer_position = event.position
		if not pointer_over_ui(event.position):
			release_text_focus()
		else:
			brush_preview.hide()
			if event is InputEventMouseMotion and painting:
				# Do not connect a stroke across a UI panel.
				stroke.break_path()
	if event is InputEventKey:
		# Playtest detaches this scene synchronously; retain its input viewport.
		var input_viewport := get_viewport()
		if handle_shortcut(event):
			input_viewport.set_input_as_handled()
			return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and not removing: end_stroke()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			rotating = false
			if removing: end_stroke()
		if event.button_index == MOUSE_BUTTON_MIDDLE: panning = false
	if event is InputEventMouseMotion:
		if rotating:
			view.orbit(event.relative)
			refresh_view_icon()
			get_viewport().set_input_as_handled()
		if panning:
			view.drag_pan(event.relative)
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if suspended or modal_open(): return
	if event is InputEventMouseButton and event.pressed:
		if pointer_over_ui(event.position): return
		release_text_focus()
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if event.alt_pressed:
					sample_at(event.position)
					return
				end_stroke()
				stroke.begin(document)
				paint_at(event.position)
			MOUSE_BUTTON_RIGHT:
				if event.alt_pressed:
					rotating = true
					view.zoom_reference = event.position
				else:
					end_stroke()
					stroke.begin(document, true)
					paint_at(event.position)
			MOUSE_BUTTON_MIDDLE: panning = true
			MOUSE_BUTTON_WHEEL_UP: view.change_zoom(1, event.position)
			MOUSE_BUTTON_WHEEL_DOWN: view.change_zoom(-1, event.position)
	if event is InputEventMouseMotion:
		if pointer_over_ui(event.position): return
		var coord: Vector2i = view.hex_at_screen(event.position, true)
		update_brush_preview(coord)
		if view.value_heatmap.active:
			view.value_heatmap.set_hovered(coord)
		if painting: paint_at(event.position)
		elif document.cells.has(coord):
			var cell: Dictionary = document.cells[coord]
			var owner: int = cell["owner"]
			show_pointer_status(Loc.text("%s · Province %d, %d · Value %d · %s") % [Loc.text(Document.Events.EVENTS[event_id]["title"]) if active_tool() == "Event" and Document.Events.EVENTS.has(event_id) else Loc.text(active_tool()), coord.x, coord.y, cell["value"], Loc.text("Neutral") if owner < 0 else document.factions[owner]["name"]])
		else: show_pointer_status()

func _process(_delta: float) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	view.controls_enabled = not modal_open() and not focus is LineEdit and not Input.is_key_pressed(KEY_CTRL) and (not Input.is_key_pressed(KEY_ALT) or rotating)
	if painting and not rotating and not panning and not pointer_over_ui(pointer_position):
		paint_at(pointer_position)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		end_stroke()
		rotating = false
		panning = false

func _on_view_action(action: StringName, arguments: Array) -> void:
	if loading_map: return
	match action:
		&"open_event_editor":
			var process_id := OS.create_process(OS.get_executable_path(),PackedStringArray(["--path",ProjectSettings.globalize_path("res://"),"--script","res://tools/event_editor.gd"]))
			update_status(Loc.text("Event Editor opened. Save your event, then press Reload here.") if process_id >= 0 else Loc.text("Could not open Event Editor. Use Event Editor.cmd in the project folder."))
		&"reload_events":
			var pack := preload("res://src/game/authored_event_schema.gd").load_pack()
			if pack.error != "": update_status(pack.error)
			else:
				Document.Events.reload()
				ui.filter_events()
				update_status(Loc.text("Event library reloaded."))
		&"toggle_view": toggle_view()
		&"toggle_heatmap": toggle_heatmap()
		&"undo": undo()
		&"redo": redo()
		&"toggle_settings": toggle_settings()
		&"close_context": close_context()
		&"event_selected": set_event(arguments[0])
		&"select_event": select_event(arguments[0])
		&"select_player_start": select_player_start()
		&"save_level": save_level()
		&"playtest": playtest()
		&"open_tools": open_tools(arguments[0])
		&"select_tool": select_tool(arguments[0])
		&"load": request_action(open_load)
		&"new_island": request_action(new_island.bind(arguments[0]))
		&"center":
			view.reset_camera()
			ui.settings_shade.hide()
		&"back": request_action(func(): back_requested.emit())
