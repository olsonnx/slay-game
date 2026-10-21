extends "res://src/game/game_compatibility.gd"

const Rules = preload("res://src/game/kingdom_rules.gd")
const BoardView = preload("res://src/rendering/board_view.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const NONE := Vector2i(999, 999)
const UNIT_NAMES = Catalog.UNIT_NAMES
const ProvinceView = preload("res://src/ui/province_view.gd")
const Spells = preload("res://src/game/spell_catalog.gd")
const VisibleEconomy = preload("res://src/game/visible_economy.gd")
const ReplayLog = preload("res://src/game/replay_log.gd")

signal faction_started(faction: int)
signal faction_finished(faction: int)
signal pause_requested
signal tutorial_exit_requested
signal defeat_requested

var input_handler
var presenter
var player_actions = preload("res://src/game/player_actions.gd").new()
var cells: Dictionary:
	get:
		return session.rules.cells
var view
var game_over: bool:
	get: return session.outcome_reached
	set(value): session.complete(value)
var busy: bool:
	get: return session.work_active
	set(value):
		if value: session.begin_work()
		else: session.finish_work()
var initial_human_count := 1
var initial_match_config: Dictionary = {}
var initial_quick_play_kingdom := -2 # Opt in only for generated solo sessions.
var turn_order: Array = []
var winner_faction := -1
var rmb_down := false
var mmb_down := false
var view_press_held := false
var view_press_consumed := false
var view_press_time := 0.0
const VIEW_HOLD_SECONDS := 0.55
var rmb_dragged := false
var rmb_can_rotate := false
var rmb_travel := Vector2.ZERO
const ROTATE_THRESHOLD := 6.0
var player_move_snapshot: Dictionary = {}
var player_move_revision := 0
var message := ""
var hover_time := 0.0
var toast_time := 0.0
var closing: bool:
	get: return session.is_closing()
	set(value):
		if value: session.close()
var visible_economy_signature: Array = []
var visible_economy_tracker = VisibleEconomy.new()
var ai_simulation_workers := true # Internal diagnostic override; graphics/settings are unaffected.
var settling_turn := false
var initial_seed := -1
var initial_rule_mode := "classic"
var initial_map_size := "small"
var initial_kingdom_count := 0
var initial_difficulty := "normal"
var deferred_startup := false
var startup_timings: Dictionary = {}
var prepared_level_document = null
var province_view
var playback_kingdoms: Dictionary = {}
var playback_mana: Dictionary = {}
var camera_follow_suspended := false
var animate_level_changes := false
var completion_started: bool:
	get: return session.departure_active
	set(value): session.departure_active = value
var defeat_notified := false
var event_shade: ColorRect
var event_panel
var event_dialog
var playback_speed
var shown_event: Dictionary = {}
var pending_capital_relocation: Dictionary = {}
var replay_error_reported := false
var match_clock = preload("res://src/game/match_clock.gd").new()
var match_results: Dictionary = {}
var inspecting_results_map: bool:
	get: return session.phase == session.Phase.INSPECTING_RESULTS
	set(value): session.inspect_results(value)

func _ready() -> void:
	input_handler = preload("res://src/game/game_input.gd").new(self)
	view = BoardView.new()
	add_child(view)
	presenter = preload("res://src/ui/game_presenter.gd").new(session, hud, view, presentation_actions())
	view.action_started.connect(_on_visual_action_started)
	view.action_finished.connect(_on_visual_action_finished)
	view.wildlife.world_action_started.connect(_on_world_action_started)
	view.visible_board_changed.connect(_on_visible_board_changed)
	view.visible_board_changed.connect(presenter.invalidate_tip)
	view.manual_camera_moved.connect(_on_manual_camera_moved)
	view.level_transition_finished.connect(_on_level_transition_finished)
	Sound.settings_save_failed.connect(_on_audio_save_failed)
	hud.shortcuts_changed.connect(refresh_province)
	hud.build_ui({
		"begin_view_press": begin_view_press,
		"cancel_action": cancel_action,
		"cancel_view_press": cancel_view_press,
		"end_view_press": end_view_press,
		"open_pause": open_pause,
		"open_shop": open_shop,
		"toggle_help": toggle_help,
		"toggle_stats": toggle_stats,
		"toggle_value_heatmap": toggle_value_heatmap,
		"turn_button_activated": turn_button_activated,
		"view_button_activated": view_button_activated
	}, activation_cue)
	view.value_heatmap.changed.connect(refresh_heatmap_button)
	build_event_ui()
	playback_speed = preload("res://src/ui/playback_speed.gd").new(self)
	add_child(playback_speed)
	Keys.changed.connect(refresh_ui)
	Gameplay.changed.connect(refresh_overlays)
	province_view = ProvinceView.new()
	hud.ui_root.add_child(province_view)
	province_view.develop_requested.connect(develop_province)
	province_view.entrench_requested.connect(entrench_province)
	province_view.relocate_requested.connect(relocate_province_capital)
	province_view.close_requested.connect(close_province)
	session.rules.rule_mode = initial_rule_mode
	session.rules.ai_difficulty = initial_difficulty
	if not deferred_startup:
		new_game(initial_seed)

func new_game(seed_value := -1, render_board := true, generate_rules := true) -> void:
	if busy or closing or get_tree().paused:
		return
	if session.rules.replay_log != null:
		session.rules.replay_log.finish(session.rules, "restarted")
		session.rules.replay_log = null
	session.reset()
	var started := Time.get_ticks_usec()
	view.value_heatmap.set_active(false)
	if generate_rules:
		session.rules.generate(seed_value, initial_map_size, initial_kingdom_count)
		startup_timings["generation_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	close_event_ui()
	shown_event.clear()
	pending_capital_relocation.clear()
	hud.configure_rules_ui(session.rules.is_modern())
	close_province()
	hud.reset_gold_feedback()
	configure_players()
	winner_faction = -1
	session.round_number = 1
	match_clock.reset(not deferred_startup)
	match_results.clear()
	inspecting_results_map = false
	session.selection.selected = NONE
	session.selection.hovered = NONE
	session.selection.active_hex = NONE
	session.selection.action_mode = ""
	session.selection.recruit_tier = 0
	game_over = false
	replay_error_reported = false
	completion_started = false
	defeat_notified = false
	hud.economy_dock.show()
	hud.turn_controls.show()
	session.active_faction = session.player_faction
	playback_kingdoms.clear()
	playback_mana.clear()
	camera_follow_suspended = false
	message = ""
	close_menus()
	if not session.initial_level_data.get("tutorial", false):
		session.rules.replay_log = ReplayLog.new()
		if not session.rules.replay_log.start(session.rules, {"generation_version":session.rules.MapGenerator.GENERATION_VERSION, "difficulty":initial_difficulty, "algorithm":session.rules.ai_algorithm, "turn_order":turn_order, "match":initial_match_config,
			"factions":preload("res://src/game/replay_identity.gd").capture(session.names, session.colors, view.COLORS),
			"mode":"hotseat" if is_hotseat() else "editor" if not session.initial_level_data.is_empty() else "quick_play",
			"map_title":session.initial_level_data.get("title", "")}):
			push_warning("Replay could not be saved: " + session.rules.replay_log.error)
	for kingdom in session.rules.kingdoms.values():
		if kingdom["owner"] == session.player_faction:
			session.selection.active_hex = kingdom["capital"]
			break
	if not session.initial_level_data.is_empty():
		var marker = session.initial_level_data.get("player_start")
		if marker is Array:
			var start_kingdom: Dictionary = session.rules.kingdom_at(Vector2i(int(marker[0]), int(marker[1])))
			if not start_kingdom.is_empty() and start_kingdom["owner"] == session.player_faction:
				session.selection.active_hex = start_kingdom["capital"]
	view.configure_map(session.rules.map_size, session.rules.bridge_bounds(), cells)
	view.reset_camera()
	if render_board:
		started = Time.get_ticks_usec()
		view.render_cells(cells)
		startup_timings["scene_build_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	refresh_ui()
	if is_hotseat():
		session.rules.begin_turn(session.player_faction)
		if render_board:
			view.render_cells(cells)
		begin_local_turn()

func prepare_board() -> void:
	var job = preload("res://src/game/island_preparation.gd").new()
	var work: Callable = job.generate.bind(initial_seed, initial_map_size, initial_rule_mode, initial_kingdom_count)
	if not session.initial_level_data.is_empty():
		work = job.prepare_level.bind(session.initial_level_data)
	var task := WorkerThreadPool.add_task(work, false, "Prepare island")
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	assert(job.error.is_empty(), job.error)
	prepared_level_document = job.document
	session.rules = job.rules
	session.rules.ai_difficulty = initial_difficulty
	startup_timings["generation_ms"] = job.generation_ms
	var setup_started := Time.get_ticks_usec()
	new_game(initial_seed, false, false)
	startup_timings["session_setup_ms"] = (Time.get_ticks_usec() - setup_started) / 1000.0
	prepared_level_document = null
	await view.build_initial_cells(cells)
	startup_timings.merge(view.startup_timings, true)
	refresh_ui()

func active_kingdom(economy = null) -> Dictionary:
	return session.active_kingdom(economy)

func build_event_ui() -> void:
	event_dialog = preload("res://src/ui/event_dialog.gd").new(hud.button_at)
	hud.ui_root.add_child(event_dialog)
	event_shade = event_dialog
	event_panel = event_dialog.panel

func close_event_ui() -> void:
	pending_capital_relocation.clear()
	event_dialog.close_dialog()

func sync_event_factions() -> void:
	for faction in range(session.rules.faction_count):
		if faction not in turn_order: turn_order.append(faction)

func show_next_event() -> void:
	if session.rules.pending_events.is_empty():
		return
	shown_event = session.rules.pending_events[0]
	var definition: Dictionary = session.rules.event_definition(shown_event)
	close_menus()
	reset_camera_gesture()
	view.stop_camera_pan()
	hud.world_tip.hide()
	event_dialog.present(definition, resolve_shown_event)

func resolve_shown_event(choice: int) -> void:
	var result: String = session.rules.resolve_event(shown_event, choice)
	if result == "":
		return
	sync_event_factions()
	shown_event.clear()
	close_event_ui()
	if session.selection.selected != NONE and (cells[session.selection.selected]["unit"] == 0 or session.rules.unit_faction(session.selection.selected) != session.player_faction):
		session.selection.selected = NONE
	view.render_cells(cells)
	announce(result)
	show_next_event()
	if not event_shade.visible:
		check_winner()
	refresh_ui()
	report_tutorial_action("event",NONE,{"choice":choice})

func _process(delta: float) -> void:
	if closing:
		return
	if inspecting_results_map: return
	advance_view_press(delta)
	toast_time = maxf(0, toast_time - delta)
	hud.toast_panel.visible = toast_time > 0 or game_over
	if view.level_transitioning or completion_started:
		view.clear_unit_hover()
		return
	if busy or view.rotating or mmb_down or hud.stats_shade.visible or get_viewport().gui_get_hovered_control() != null:
		view.value_heatmap.set_hovered(NONE)
		view.set_unit_hover(NONE)
		if session.selection.hovered != NONE:
			session.selection.hovered = NONE
			session.selection.preview_path.clear()
			refresh_overlays()
		hover_time = 0
		hud.world_tip.hide()
		return
	var hit: Dictionary = view.pick_at_screen(get_viewport().get_mouse_position(), session.selection.action_mode == "bridge")
	var coord: Vector2i = hit["coord"]
	view.value_heatmap.set_hovered(coord)
	view.set_unit_hover(coord if hit["kind"] in ["unit", "wildlife"] else NONE, hit["kind"])
	if coord != session.selection.hovered:
		session.selection.hovered = coord
		hover_time = 0
		hud.world_tip.hide()
		session.selection.preview_path = session.rules.movement_path(session.selection.selected, session.selection.hovered, session.selection.valid_targets) if session.selection.valid_targets.has(session.selection.hovered) and session.selection.action_mode == "" else []
		refresh_overlays()
	else:
		hover_time += delta
	if cells.has(session.selection.hovered) and hover_time > 0.65:
		show_world_tip()

func _input(event: InputEvent) -> void:
	input_handler._input(event)

func _notification(what: int) -> void:
	if input_handler == null:
		return
	input_handler._notification(what)

func _unhandled_input(event: InputEvent) -> void:
	input_handler._unhandled_input(event)

func announce(text_value: String) -> void:
	message = text_value
	UiTheme.fit_text_panel(hud.toast_panel, hud.notice_label, text_value, Vector2(14, 8))
	toast_time = 4.0
	hud.toast_panel.visible = true

func click_hex(coord: Vector2i, hit_kind := "auto") -> void:
	await player_actions.click_hex(self, coord, hit_kind)

func inspect_province(coord: Vector2i) -> void:
	if not session.rules.is_modern() or not view.cells.has(coord):
		return
	Sound.play(&"ui_click")
	session.selection.inspected_hex = coord
	hud.shop_panel.close()
	refresh_province(visible_economy() if busy else session.rules)
	province_view.open()
	report_tutorial_action("inspect",coord)

func close_province() -> void:
	session.selection.inspected_hex = NONE
	session.selection.inspected_unit = NONE
	session.selection.inspected_animal = NONE
	if is_instance_valid(province_view):
		province_view.close()

func refresh_province(model = null) -> void:
	if not is_instance_valid(province_view) or session.selection.inspected_hex == NONE:
		return
	var economy = session.rules if model == null else model
	province_view.refresh(economy, session.selection.inspected_hex, not commands_locked(), session.player_faction)

func develop_province() -> void:
	if commands_locked():
		return
	if not tutorial_permits("develop",session.selection.inspected_hex): return
	if session.rules.develop(session.selection.inspected_hex, session.player_faction):
		view.render_cells(cells)
		view.action_marker(session.selection.inspected_hex, Color("eed3a1"))
		Sound.play(&"action_place")
		refresh_ui()
		report_tutorial_action("develop",session.selection.inspected_hex)

func entrench_province() -> void:
	if commands_locked() or not province_view.visible or not tutorial_permits("entrench", session.selection.inspected_hex): return
	if session.rules.entrench(session.selection.inspected_hex, session.player_faction):
		session.selection.selected = NONE
		view.render_cells(cells)
		view.action_marker(session.selection.inspected_hex, Color("91e2ef"))
		Sound.play(&"action_place")
		refresh_ui()
		report_tutorial_action("entrench", session.selection.inspected_hex)

func relocate_province_capital() -> void:
	if commands_locked() or not tutorial_permits("relocate_capital", session.selection.inspected_hex): return
	if not session.rules.can_relocate_capital(session.selection.inspected_hex, session.player_faction): return
	var cost: int = session.rules.capital_relocation_cost(session.player_faction)
	reset_camera_gesture()
	pending_capital_relocation = {"coord":session.selection.inspected_hex, "faction":session.player_faction, "cost":cost, "capital":session.rules.kingdom_at(session.selection.inspected_hex)["capital"]}
	event_dialog.present({"heading":Loc.text("CAPITAL RELOCATION"), "title":Loc.text("Move your capital here?"),
		"text":Loc.text("Spend %d G from this territory's treasury to move its capital to the selected province?") % cost,
		"hint":Loc.text("Your next capital relocation will cost %d G.") % (cost + 10), "focus_cancel":true,
		"choices":[[Loc.text("Move capital · %d G") % cost, ""], [Loc.text("Cancel"), ""]]}, resolve_capital_relocation)
	refresh_ui()

func resolve_capital_relocation(choice: int) -> void:
	if pending_capital_relocation.is_empty(): return
	var request := pending_capital_relocation.duplicate()
	pending_capital_relocation.clear()
	close_event_ui()
	var coord: Vector2i = request["coord"]
	var bank: Dictionary = session.rules.kingdom_at(coord)
	if choice == 0 and not commands_locked() and session.player_faction == request["faction"] and session.rules.capital_relocation_cost(session.player_faction) == request["cost"] and bank.get("capital", NONE) == request["capital"] and tutorial_permits("relocate_capital", coord) and session.rules.relocate_capital(coord, session.player_faction):
		session.selection.active_hex = coord
		session.selection.selected = NONE
		view.render_cells(cells)
		view.action_marker(coord, Color("eed3a1"))
		Sound.play(&"action_place")
	if not closing: refresh_ui()

func choose_spell(spell: String) -> void:
	if commands_locked() or not session.rules.is_modern() or not Spells.SPELLS.has(spell):
		return
	session.selection.chosen_spell = spell
	session.selection.action_mode = "spell"
	session.selection.selected = NONE
	hud.shop_panel.close()
	close_province()
	refresh_ui()

func toggle_action(mode: String) -> void:
	if commands_locked():
		return
	session.selection.action_mode = "" if session.selection.action_mode == mode else mode
	session.selection.selected = NONE
	session.selection.inspected_unit = NONE
	session.selection.inspected_animal = NONE
	hud.shop_panel.close()
	refresh_ui()

func choose_unit(tier: int) -> void:
	if commands_locked():
		return
	session.selection.recruit_tier = tier
	close_province()
	session.selection.action_mode = "recruit"
	session.selection.selected = NONE
	hud.shop_panel.close()
	refresh_ui()

func choose_building(kind: String) -> void:
	if commands_locked():
		return
	session.selection.action_mode = kind
	close_province()
	session.selection.selected = NONE
	hud.shop_panel.close()
	refresh_ui()

func can_place_unit(coord: Vector2i) -> bool:
	var capital := active_capital()
	return capital != NONE and session.rules.can_recruit(coord, session.player_faction, session.selection.recruit_tier, capital)

func active_capital() -> Vector2i:
	return active_kingdom().get("capital", NONE)

func end_turn() -> void:
	if session.tutorial != null:
		await session.tutorial.end_turn()
		return
	await preload("res://src/game/opponent_turns.gd").run(self)

func turn_button_activated() -> void:
	if not busy and not playback_speed.turn_press_consumed:
		end_turn()

func check_winner() -> void:
	if session.tutorial != null: return
	if is_hotseat():
		var survivors: Array = []
		for cell in cells.values():
			if cell["capital"] >= 0 and cell["owner"] not in survivors:
				survivors.append(cell["owner"])
		if survivors.size() <= 1:
			game_over = true
			winner_faction = survivors[0] if not survivors.is_empty() else -1
			announce(Loc.text("Victory for %s!") % session.names[winner_faction] if winner_faction >= 0 else Loc.text("Draw — no kingdoms remain."))
		else:
			var human_survives := false
			for faction in session.rules.human_factions:
				if session.rules.territory(faction) > 0:
					human_survives = true
			if not human_survives:
				game_over = true
				announce(Loc.text("Defeat — all local kingdoms have fallen."))
		begin_completion_exit()
		return
	if session.rules.territory(session.player_faction) == 0:
		game_over = true
		announce(Loc.text("Your kingdom has fallen."))
	else:
		var enemy_capital_exists := false
		for cell in cells.values():
			if cell["owner"] >= 0 and cell["owner"] != session.player_faction and cell["capital"] == cell["owner"]:
				enemy_capital_exists = true
				break
		if not enemy_capital_exists:
			game_over = true
			announce(Loc.text("Victory for %s!") % session.names[session.player_faction])
	begin_completion_exit()

func play_level_entry() -> void:
	if closing:
		return
	view.start_level_transition(true)
	refresh_ui()

func begin_completion_exit() -> void:
	if not game_over: return
	match_clock.pause()
	if session.rules.replay_log != null and not session.rules.replay_log.finished:
		var winner: int = winner_faction if is_hotseat() else session.player_faction if session.rules.territory(session.player_faction) > 0 else -1
		var result := "victory" if not is_hotseat() and winner >= 0 else "defeat"
		if is_hotseat():
			result = "completed" if winner >= 0 else "draw" if not cells.values().any(func(cell): return cell["capital"] >= 0) else "defeat"
		session.rules.replay_log.finish(session.rules, "completed", winner, {"duration_seconds":match_clock.seconds(), "result":result})
		match_results = preload("res://src/game/match_results.gd").summarize(session.rules.replay_log)
	if busy or closing or defeat_notified or not animate_level_changes: return
	defeat_notified = true
	session.selection.selected = NONE
	session.selection.action_mode = ""
	close_menus()
	# The session owner presents results for both victory and defeat.
	defeat_requested.emit()

func play_level_departure() -> void:
	# Quiesce commands before moving their whole tiles. In-flight turn coroutines
	# see closing and unwind without planning another opponent phase.
	closing = true
	reset_camera_gesture()
	hud.ui_root.hide()
	view.stop_camera_pan()
	if completion_started and not view.island_transition.entering:
		while view.level_transitioning:
			await get_tree().process_frame
		return
	view.cancel_level_transition()
	view.cancel_motion(cells)
	view.controls_enabled = false
	view.overlay_root.hide()
	while busy:
		await get_tree().process_frame
	session.departure_active = true
	view.start_level_transition(false)
	while view.level_transitioning:
		await get_tree().process_frame

func _on_level_transition_finished() -> void:
	if not closing:
		refresh_ui()
		if is_hotseat(): follow_active_faction(true)

func open_shop(kind: String) -> void:
	presenter.open_shop(kind)

func commands_locked() -> bool:
	return session.commands_locked(get_tree().paused, view.level_transitioning, event_shade.visible)

func cancel_action() -> void:
	if interaction_blocked():
		return
	var closing_stats: bool = hud.stats_shade.visible
	if has_cancellable_action():
		Sound.play(&"ui_close")
	if not player_move_snapshot.is_empty():
		player_move_revision += 1
		preload("res://src/game/state_snapshot.gd").restore(session.rules, player_move_snapshot)
		if session.rules.replay_log != null: session.rules.replay_log.cancel_transaction()
		session.selection.active_hex = player_move_snapshot["active_hex"]
		player_move_snapshot = {}
		view.cancel_motion(cells)
		busy = false
		session.active_faction = session.player_faction
	session.selection.action_mode = ""
	session.selection.selected = NONE
	session.selection.recruit_tier = 0
	session.selection.chosen_spell = ""
	close_province()
	session.selection.preview_path.clear()
	close_menus()
	hover_time = 0
	toast_time = 0
	hud.toast_panel.hide()
	refresh_ui()
	if closing_stats: report_tutorial_action("stats",NONE,{"open":false})

func toggle_view() -> void:
	if view.level_transitioning or completion_started:
		return
	view.toggle_top_down()
	refresh_view_button()
	hud.world_tip.hide()
	hover_time = 0
	report_tutorial_action("view")

func center_camera() -> void:
	if view.level_transitioning or completion_started:
		return
	view.reset_camera()
	refresh_view_button()

func refresh_view_button() -> void:
	hud.view_button.icon = VIEW_TOP_ICON if view.top_down else VIEW_3D_ICON
	hud.view_button.tooltip_text = Loc.text("%s · %s\nHold: centre / reset camera") % [Loc.text("3D view" if view.top_down else "Top-down"), Keys.key_name("view")]

func begin_view_press() -> void:
	input_handler.begin_view_press()

func end_view_press() -> void:
	input_handler.end_view_press()

func cancel_view_press() -> void:
	input_handler.cancel_view_press()

func advance_view_press(delta: float) -> void:
	input_handler.advance_view_press(delta)

func view_button_activated() -> void:
	input_handler.view_button_activated()

func toggle_help() -> void:
	hud.help_panel.visible = not hud.help_panel.visible
	hud.shop_panel.close()

func toggle_value_heatmap() -> void:
	if closing or get_tree().paused or view.level_transitioning or completion_started:
		return
	view.value_heatmap.set_active(not view.value_heatmap.active)
	refresh_overlays()
	report_tutorial_action("heatmap",NONE,{"active":view.value_heatmap.active})

func refresh_heatmap_button() -> void:
	var active: bool = view.value_heatmap.active
	hud.heatmap_button.set_pressed_no_signal(active)
	hud.heatmap_legend.visible = active
	var maximum: int = view.value_heatmap.maximum
	hud.heatmap_max_label.text = str(maximum)
	hud.heatmap_max_label.visible = maximum > 1
	hud.heatmap_low_label.visible = maximum >= 1
	hud.heatmap_bar.visible = maximum >= 1
	hud.heatmap_gradient.offsets = PackedFloat32Array([0, 0.5, 1])
	hud.heatmap_gradient.colors = PackedColorArray([view.value_heatmap.value_color(1, maximum), view.value_heatmap.value_color(maximum / 2.0 + 0.5, maximum), view.value_heatmap.value_color(maximum, maximum)])

func close_menus() -> void:
	close_province()
	hud.shop_panel.close()
	hud.stats_shade.hide()
	hud.help_panel.hide()
	hud.world_tip.hide()
	view.controls_enabled = not view.level_transitioning and not completion_started
	view.rotating = false
	rmb_down = false
	rmb_can_rotate = false

func toggle_stats() -> void:
	hud.stats_shade.visible = not hud.stats_shade.visible
	view.controls_enabled = not hud.stats_shade.visible
	view.rotating = false
	hud.shop_panel.close()
	hud.help_panel.hide()
	if hud.stats_shade.visible:
		refresh_stats()
	report_tutorial_action("stats",NONE,{"open":hud.stats_shade.visible})

func refresh_stats() -> void:
	presenter.refresh_stats()

func select_kingdom(capital: Vector2i) -> void:
	if session.rules.kingdoms.has(capital) and session.rules.kingdoms[capital].owner == session.player_faction:
		session.selection.active_hex = capital
	view.focus = view.coord_position(capital)
	view.update_camera()
	toggle_stats()
	refresh_ui()

func refresh_ui(economy = null) -> void:
	view.birds.set_round(session.round_number)
	if not settling_turn: view.unit_presentation.set_turn(-1 if game_over else session.active_faction)
	if session.rules.replay_log != null and session.rules.replay_log.error != "" and not replay_error_reported:
		replay_error_reported = true
		announce(Loc.text("Replay recording stopped: %s") % session.rules.replay_log.error)
	presenter.refresh_hud(economy)
	refresh_targets()
	refresh_overlays()
	refresh_province(economy)
	if hud.stats_shade.visible:
		refresh_stats()

func refresh_targets() -> void:
	session.selection.valid_targets = {}
	if not busy:
		var capital := active_capital()
		match session.selection.action_mode:
			"": session.selection.valid_targets = session.rules.reachable_targets(session.selection.selected)
			"spell": session.selection.valid_targets = session.rules.spell_targets(session.selection.chosen_spell, session.player_faction, capital)
			"bridge": session.selection.valid_targets = session.rules.bridge_targets(session.player_faction, capital)
			"recruit", "tower", "house":
				for coord in cells:
					if can_place_unit(coord) if session.selection.action_mode == "recruit" else session.rules.can_build(coord, session.player_faction, session.selection.action_mode, capital):
						session.selection.valid_targets[coord] = true
	session.selection.preview_path = session.rules.movement_path(session.selection.selected, session.selection.hovered, session.selection.valid_targets) if session.selection.valid_targets.has(session.selection.hovered) and session.selection.action_mode == "" else []

func refresh_overlays() -> void:
	presenter.refresh_overlays()
	if session.tutorial != null: session.tutorial.refresh_marker()

func tile_intent(coord: Vector2i) -> Dictionary:
	return presenter.tile_intent(coord)

func show_world_tip() -> void:
	presenter.show_world_tip()

func activation_cue(callback: Callable) -> StringName:
	match callback.get_method():
		"turn_button_activated": return &"" if busy or playback_speed.turn_press_consumed else &"ui_click"
		"view_button_activated": return &"" # Short and long presses play once when resolved.
		"cancel_action": return &"" # Keyboard, RMB and the close button share this handler.
		"toggle_stats": return &"ui_close" if hud.stats_shade.visible else &"ui_click"
		"toggle_help": return &"ui_close" if hud.help_panel.visible else &"ui_click"
		"open_shop":
			var args := callback.get_bound_arguments()
			return &"ui_close" if hud.shop_panel.visible and not args.is_empty() and hud.shop_kind == args[0] else &"ui_click"
	return &"ui_click"

func activate_ui(callback: Callable) -> void:
	var cue := activation_cue(callback)
	if cue != &"":
		Sound.play(cue)
	callback.call()

func _on_visual_action_started(action: Dictionary) -> void:
	if not closing and action["kind"] in ["recruit", "upgrade", "build", "spell", "develop"]:
		Sound.play(&"action_place")

func _on_audio_save_failed(_error: Error) -> void:
	if is_inside_tree():
		announce(Loc.text("Sound settings could not be saved."))

func _on_visual_action_finished(action: Dictionary) -> void:
	if not closing and action["kind"] in ["move", "attack", "merge", "blocked_attack", "knight_duel"]:
		Sound.play(&"action_place")

func reset_camera_gesture() -> void:
	input_handler.reset_camera_gesture()

func has_cancellable_action() -> bool:
	return not player_move_snapshot.is_empty() or session.selection.selected != NONE or session.selection.action_mode != "" or hud.shop_panel.visible or hud.stats_shade.visible or hud.help_panel.visible or session.selection.inspected_hex != NONE or session.selection.inspected_animal != NONE

func open_pause() -> void:
	if not closing:
		playback_speed.reset()
		pause_requested.emit()

func shutdown() -> void:
	pending_capital_relocation.clear()
	close_event_ui()
	if session.rules.replay_log != null: session.rules.replay_log.finish(session.rules, "left_game")
	closing = true
	playback_speed.reset()
	view.clear_unit_hover()
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_camera_gesture()
	view.stop_camera_pan()
	view.cancel_level_transition()
	view.set_active(false)
	for child in view.get_children():
		if child is WorldEnvironment:
			child.environment = null
	view.cancel_motion(cells)

func _exit_tree() -> void:
	if session.rules.replay_log != null: session.rules.replay_log.finish(session.rules, "closed")

func _on_visible_board_changed() -> void:
	if closing or not busy:
		return
	# Settlement publishes a final readout before unlocking commands. Wildlife
	# impacts retain their immediate feedback while their animation is playing.
	if settling_turn and not view.wildlife.is_playing: return
	if session.active_faction == session.player_faction and not view.wildlife.is_playing:
		if session.selection.inspected_hex != NONE:
			refresh_province(visible_economy())
		return
	# Enemy captures of unrelated land do not change the player's displayed
	# economy. Keep immediate impact feedback when player land/support changes,
	# without cloning and rebuilding the entire economy for every enemy actor.
	var signature: Array = visible_economy_tracker.scoped_signature(view.cells, playback_kingdoms, session.player_faction, session.selection.inspected_hex, session.selection.active_hex, session.active_faction, session.round_number, view.visible_change_coords)
	if signature == visible_economy_signature:
		return
	visible_economy_signature = signature
	# AI commands are committed ahead of playback. Derive displayed finances from
	# the visible snapshot so losses appear when their impact/capture is shown.
	refresh_ui(visible_economy())

func visible_economy():
	var started := Time.get_ticks_usec() if view.profile_capture else 0
	var own_turn: bool = session.active_faction == session.player_faction and not view.wildlife.is_playing
	var baseline: Dictionary = player_move_snapshot.get("kingdoms", session.rules.kingdoms) if own_turn else playback_kingdoms
	var mana: Dictionary = player_move_snapshot.get("mana", session.rules.mana_by_faction) if own_turn else playback_mana
	var economy = VisibleEconomy.project(session.rules, view.cells, baseline, mana, session.player_faction, session.selection.inspected_hex)
	if view.profile_capture: view.capture_samples.append({"stage": "economy_readout", "ms": (Time.get_ticks_usec() - started) / 1000.0, "tiles": economy.cells.size()})
	return economy

func _on_manual_camera_moved() -> void:
	if busy:
		camera_follow_suspended = true

func _on_world_action_started(action: Dictionary) -> void:
	if closing or camera_follow_suspended or not Video.follow_turn_camera: return
	view.smooth_pan_to(view.coord_position(action.target))

func follow_active_faction(force := false) -> void:
	if closing or game_over or view.level_transitioning or (not force and (camera_follow_suspended or not Video.follow_turn_camera)):
		return
	var coords: Array = []
	if session.active_faction == session.player_faction:
		var kingdom := active_kingdom()
		if not kingdom.is_empty():
			coords = kingdom["hexes"]
	if coords.is_empty():
		for coord in cells:
			if cells[coord]["owner"] == session.active_faction:
				coords.append(coord)
	if coords.is_empty():
		return
	var center := Vector3.ZERO
	for coord in coords:
		center += view.coord_position(coord)
	view.smooth_pan_to(center / coords.size())


func is_hotseat() -> bool:
	return session.rules.human_factions.size() > 1

func begin_local_turn() -> void:
	close_menus()
	reset_camera_gesture()
	playback_speed.reset()
	hud.reset_gold_feedback()
	session.selection.selected = NONE
	session.selection.hovered = NONE
	session.selection.active_hex = NONE
	session.selection.action_mode = ""
	session.selection.recruit_tier = 0
	session.selection.chosen_spell = ""
	session.selection.preview_path.clear()
	message = ""
	toast_time = 0
	hud.toast_panel.hide()
	player_move_snapshot.clear()
	view.controls_enabled = not view.level_transitioning
	view.stop_camera_pan()
	view.clear_unit_hover()
	camera_follow_suspended = false
	refresh_ui()
	follow_active_faction(true)
	announce(Loc.text("%s's turn") % session.names[session.player_faction])

func configure_players() -> void:
	if initial_match_config.is_empty() and initial_quick_play_kingdom >= -1:
		initial_match_config = preload("res://src/game/match_setup.gd").quick_play(session.rules.map_size,session.rules.faction_count,initial_difficulty,initial_quick_play_kingdom,session.rules.level_seed,session.rules.rule_mode)
	session.names = Catalog.FACTIONS.duplicate()
	session.colors = Catalog.UI_COLORS.duplicate()
	view.COLORS = Catalog.TERRAIN_COLORS.duplicate()
	var authored_document = null
	if not session.initial_level_data.is_empty():
		authored_document = prepared_level_document
		if authored_document == null:
			authored_document = preload("res://src/editor/level_document.gd").new()
			authored_document.restore(session.initial_level_data)
		session.names = authored_document.faction_names()
		session.colors = authored_document.faction_colors("color")
		view.COLORS = authored_document.faction_colors("terrain")
	turn_order = range(session.rules.faction_count)
	session.rules.human_factions = range(clampi(initial_human_count, 1, session.rules.faction_count))
	if not initial_match_config.is_empty():
		session.rules.human_factions = []
		for index in range(session.rules.faction_count):
			var seat: Dictionary = initial_match_config["slots"][index]
			session.names[index] = seat["name"]
			session.colors[index] = Catalog.UI_COLORS[seat["color"]]
			view.COLORS[index] = Catalog.TERRAIN_COLORS[seat["color"]]
			if seat["controller"] == "human": session.rules.human_factions.append(index)
		# Keep unused identities distinct so a later revolt has a free palette.
		var used_palettes: Array = initial_match_config["slots"].map(func(seat): return seat["color"])
		var spare: int = session.rules.faction_count
		for palette in range(Catalog.FACTIONS.size()):
			if palette in used_palettes: continue
			if spare >= session.names.size():
				session.names.append("")
				session.colors.append(Color.WHITE)
				view.COLORS.append(Color.WHITE)
			session.names[spare] = Catalog.FACTIONS[palette]
			session.colors[spare] = Catalog.UI_COLORS[palette]
			view.COLORS[spare] = Catalog.TERRAIN_COLORS[palette]
			spare += 1
		if initial_match_config.get("order") == "random":
			var order_rng := RandomNumberGenerator.new()
			order_rng.seed = session.rules.level_seed ^ 0x51A7
			for index in range(turn_order.size()-1,0,-1):
				var other := order_rng.randi_range(0,index)
				var previous: int = turn_order[index]
				turn_order[index] = turn_order[other]
				turn_order[other] = previous
		while turn_order[0] not in session.rules.human_factions:
			turn_order.append(turn_order.pop_front())
	if initial_match_config.is_empty() and not session.initial_level_data.is_empty():
		var authored_player: int = authored_document.player_faction
		# Older tutorial maps and programmatic fixtures may lack a player kingdom.
		if authored_player < 0: authored_player = 0
		session.rules.human_factions = [authored_player]
		turn_order.erase(authored_player)
		turn_order.push_front(authored_player)
	session.rules.faction_names = session.names.duplicate()
	session.player_faction = turn_order[0]

func tutorial_permits(kind: String, coord := NONE, details: Dictionary = {}) -> bool:
	return session.tutorial == null or session.tutorial.permits(kind,coord,details)

func report_tutorial_action(kind: String, coord := NONE, details: Dictionary = {}) -> void:
	if session.tutorial != null: session.tutorial.observe(kind,coord,details)

func ai_execution():
	return preload("res://src/game/ai_execution.gd").new(get_tree(), session.is_closing, view.record_capture_sample if view.profile_capture else Callable())

func interaction_blocked() -> bool:
	return session.interaction_blocked(get_tree().paused, view.level_transitioning, event_shade.visible)

func input_suspended() -> bool:
	return session.input_suspended(get_tree().paused, event_shade.visible)

func can_navigate() -> bool:
	return session.can_navigate(get_tree().paused, view.level_transitioning, event_shade.visible)

func presentation_actions() -> Dictionary:
	return {"commands_locked": commands_locked, "close_province": close_province,
		"choose_unit": choose_unit, "choose_spell": choose_spell, "choose_building": choose_building,
		"select_kingdom": select_kingdom, "refresh_heatmap_button": refresh_heatmap_button,
		"refresh_view_button": refresh_view_button,
		"modal_open": func(): return event_shade.visible,
		"update_playback": func():
			if playback_speed != null: playback_speed.update()}
