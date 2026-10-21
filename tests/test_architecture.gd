extends SceneTree
const Document = preload("res://src/editor/level_document.gd")
const Stroke = preload("res://src/editor/brush_stroke.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Economy = preload("res://src/game/visible_economy.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
const Session = preload("res://src/game/session_state.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func brush_transactions() -> void:
	var document = Document.new()
	var stroke = Stroke.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var empty: Dictionary = document.state()
	stroke.begin(document)
	expect(stroke.paint(document, Vector2i.ZERO, "Land", 0, 2, false, rng), "A stroke edits its document without scene controls")
	expect(stroke.paint(document, Vector2i(3, 0), "Land", 0, 2, false, rng), "A long drag paints intermediate hexes")
	for q in range(4):
		expect(document.cells.has(Vector2i(q, 0)), "Interpolation leaves no holes")
	expect(not stroke.paint(document, Vector2i.ZERO, "Value", 0, 6, false, rng), "Revisiting a hex cannot repaint it within a stroke")
	stroke.finish(document)
	expect(document.undo_stack.size() == 1, "A drag creates exactly one history entry")
	document.undo()
	expect(document.state() == empty, "Undo restores the complete pre-stroke document")
	stroke.begin(document)
	stroke.finish(document)
	expect(document.redo_stack.size() == 1 and document.undo_stack.is_empty(), "An empty stroke preserves redo history")
	document.redo()
	expect(document.cells.size() == 4, "Redo restores all interpolated cells")
	stroke.begin(document)
	stroke.paint(document, Vector2i(0, 2), "Land", 0, 1, false, rng)
	stroke.break_path()
	stroke.paint(document, Vector2i(3, 2), "Land", 0, 1, false, rng)
	stroke.finish(document)
	expect(not document.cells.has(Vector2i(1, 2)) and not document.cells.has(Vector2i(2, 2)), "Crossing a UI panel breaks interpolation")
	stroke.begin(document, true)
	stroke.paint(document, Vector2i.ZERO, "Land", 0, 1, false, rng)
	stroke.finish(document)
	expect(not document.cells.has(Vector2i.ZERO), "Erase strokes share the same transaction boundary")
	document.undo()
	expect(document.cells.has(Vector2i.ZERO), "Erasing is undoable")
	for i in range(65):
		stroke.begin(document)
		stroke.paint(document, Vector2i.ZERO, "Value", 0, 1 + i % 2, false, rng)
		stroke.finish(document)
	expect(document.undo_stack.size() == 60 and document.redo_stack.is_empty(), "Committed strokes share the bounded document history policy")
	expect(not stroke.active and stroke.before.is_empty() and stroke.visited.is_empty(), "Finishing releases transaction snapshots")

func projection_isolation() -> void:
	var rules = Rules.new()
	rules.rule_mode = "modern"
	rules.generate(71, "very_small", 3)
	var visible: Dictionary = rules.cells.duplicate(true)
	var banks: Dictionary = rules.kingdoms.duplicate(true)
	var mana: Dictionary = rules.mana_by_faction.duplicate()
	var capital: Vector2i = banks.keys()[0]
	var owner: int = banks[capital]["owner"]
	# Reconstruction clears terrain at capitals. It must affect only the projection.
	visible[capital]["tree"] = true
	var visible_before := visible.duplicate(true)
	var banks_before := banks.duplicate(true)
	var mana_before := mana.duplicate()
	var rules_before: Dictionary = rules.cells.duplicate(true)
	var projected = Economy.project(rules, visible, banks, mana, owner, capital)
	expect(not projected.cells[capital]["tree"], "Projection rebuilds its own kingdom records")
	expect(visible == visible_before and banks == banks_before and mana == mana_before, "Projection cannot mutate borrowed visible state or baselines")
	projected.cells[capital]["value"] = 6
	projected.kingdoms[capital]["gold"] = 999
	projected.set_mana(owner, 0)
	expect(visible == visible_before and banks == banks_before and mana == mana_before and rules.cells == rules_before, "Projected readouts share no mutable records with the live game")
	var signature := Economy.signature(visible, banks, owner, capital, capital, owner, 1)
	var same := Economy.signature(visible, banks, owner, capital, capital, owner, 1)
	expect(signature == same, "Unchanged playback has a stable invalidation signature")
	visible[capital]["value"] += 1
	expect(signature != Economy.signature(visible, banks, owner, capital, capital, owner, 1), "Signature snapshots detect in-place visible record changes")

func snapshot_policies() -> void:
	var model = Rules.new()
	model.rule_mode = "modern"
	model.generate(71, "very_small", 3)
	model.pending_events.append({"coord":Vector2i.ZERO, "choices":[1, 2]})
	model.capital_relocations[0] = 2
	model.effects_by_faction[0] = {"ward":true}
	model.ai_last_decision = {"action":{"kind":"move"}}
	var coord: Vector2i = model.cells.keys()[0]
	model.cells[coord]["event"] = "unknown"
	var before := Snapshots.capture(model)
	var replay := Snapshots.replay_position(model)
	expect(replay.keys() == ["cells", "kingdoms", "mana", "effects", "capital_relocations", "events", "rng", "difficulty", "faction_count"], "Replay schema preserves existing field order and appends dynamic faction count")
	var recorder := RefCounted.new()
	model.replay_log = recorder
	model.cells[coord]["owner"] = -1
	model.pending_events[0]["choices"].append(3)
	model.capital_relocations[0] = 10
	model.faction_names[0] = "Changed"
	model.rng.randf()
	model.ai_last_decision.clear()
	Snapshots.restore(model, before)
	expect(Snapshots.capture(model) == before, "Authoritative round trip restores data, configuration, telemetry and RNG")
	expect(model.replay_log == recorder, "Restoration retains the recorder owned by the live session")
	model.pending_events[0]["choices"].append(3)
	expect(before["events"][0]["choices"] == [1, 2], "Restored records do not alias the retained rollback snapshot")
	Snapshots.restore(model, before)
	var simulation = Snapshots.simulation(model)
	expect(simulation.cells[coord]["event"] == "" and simulation.pending_events.is_empty(), "Simulation deliberately hides undiscovered and pending encounters")
	expect(simulation.replay_log == null and simulation.ai_last_decision.is_empty(), "Search never inherits recorder ownership or live telemetry")
	var independent_rng := RandomNumberGenerator.new()
	independent_rng.seed = 0
	expect(simulation.rng.state == independent_rng.state, "Simulation uses its documented independent RNG policy")
	var bank: Vector2i = simulation.kingdoms.keys()[0]
	simulation.kingdoms[bank]["hexes"].clear()
	simulation.faction_names[0] = "Simulation"
	simulation.effects_by_faction[0]["ward"] = false
	expect(Snapshots.capture(model) == before, "Simulation owns banks, configuration and nested effects")
	# New model fields require an explicit policy rather than silently disappearing.
	var classified: Array = Snapshots.CONFIGURATION.duplicate()
	classified.append_array(Snapshots.POSITION_FIELDS.values())
	classified.append_array(["magic", "replay_log", "ai_last_decision"])
	for property in model.get_script().get_script_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			expect(property["name"] in classified, "Model property has a declared snapshot/runtime policy: " + property["name"])

func session_transitions() -> void:
	var state = Session.new()
	expect(state.phase == Session.Phase.READY and not state.commands_locked(false, false, false), "A ready session accepts commands")
	for gates in [[true, false, false], [false, true, false], [false, false, true]]:
		expect(state.commands_locked(gates[0], gates[1], gates[2]), "Pause, transition and modal gates independently lock commands")
	state.selection.selected = Vector2i.ZERO
	state.begin_work(true)
	expect(state.phase == Session.Phase.PLAYER_PLAYBACK and state.work_active, "Player playback has an explicit phase")
	state.finish_work()
	expect(state.phase == Session.Phase.READY, "Completed player playback returns to ready")
	state.begin_work()
	state.complete()
	expect(state.phase == Session.Phase.COMPLETED and state.work_active, "Completing mid-turn preserves the operation that must drain")
	state.finish_work()
	expect(state.phase == Session.Phase.COMPLETED and state.commands_locked(false, false, false), "Draining work cannot reopen a completed match")
	state.inspect_results(true)
	expect(state.phase == Session.Phase.INSPECTING_RESULTS and state.interaction_blocked(false, false, false), "Results inspection blocks gameplay interaction")
	expect(state.can_navigate(false, false, false), "Completed-map inspection still permits camera navigation")
	expect(not state.input_suspended(false, false) and not state.can_navigate(false, true, false), "Level transitions observe input releases while blocking camera changes")
	state.inspect_results(false)
	expect(state.phase == Session.Phase.COMPLETED, "Leaving inspection retains the completed outcome")
	state.reset()
	expect(state.selection.selected == state.selection.NONE and state.phase == Session.Phase.READY, "New sessions clear transient selection and phase together")
	state.begin_work()
	state.close()
	expect(state.is_closing() and state.work_active, "Cancellation keeps outstanding work visible to the disposer")
	state.complete()
	state.finish_work()
	state.inspect_results(true)
	expect(state.is_closing() and not state.work_active and state.commands_locked(false, false, false), "Completion and unwind cannot resurrect a closing session")
	state.begin_work()
	expect(state.is_closing() and not state.work_active, "Closing sessions reject new work after cancellation has drained")

func view_ownership() -> void:
	var unopened = load("res://scenes/main.tscn").instantiate()
	expect(unopened.hud.get_parent() == unopened, "A session owns its HUD even if freed before entering the tree")
	unopened.free()
	var factory = load("res://src/rendering/board_assets.gd").new()
	var first_color := Color(0.0, 0.25, 0.5)
	var retained: StandardMaterial3D = factory.material(first_color)
	for index in range(factory.MATERIAL_CACHE_LIMIT + 100):
		factory.material(Color(float(index + 1) / 4096.0, 0.25, 0.5))
		factory.material(Color(0.25, float(index + 1) / 4096.0, 0.5))
	expect(factory.material_cache.size() <= factory.MATERIAL_CACHE_LIMIT, "Streaming tint caches have an explicit resource budget")
	expect(retained.albedo_color == first_color and retained != factory.material(first_color), "Eviction releases cache ownership without mutating materials retained by meshes")
	expect(factory.material(first_color) == factory.material(first_color), "The retained cache continues to share repeated materials")
	factory.free()
	var board = load("res://src/rendering/board_view.gd").new()
	expect(board.navigation.get_parent() == board and board.unit_presentation.get_parent() == board, "Board components are owned before scene entry")
	root.add_child(board)
	await process_frame
	expect(board.navigation.get_parent() == board and board.unit_presentation.get_parent() == board, "Camera and actor presenters have the board's scene lifetime")
	board.set_active(false)
	board.set_active(false)
	expect(not board.camera.current and not board.controls_enabled and not board.sky_backdrop.visible, "Deactivation quiesces camera, controls and backdrop idempotently")
	expect(not root.get_node("Video").changed.is_connected(board._apply_video_settings), "A suspended board owns the removal of its settings listener")
	board.set_active(true)
	board.set_active(true)
	expect(board.camera.current and root.get_node("Video").changed.is_connected(board._apply_video_settings), "Activation reconnects settings exactly once")
	board.queue_free()
	await process_frame
	var editor_view = load("res://src/editor/editor_view.gd").new()
	root.add_child(editor_view)
	var observed: Array = []
	editor_view.title_changed.connect(func(value: String): observed.append(value))
	editor_view.action_requested.connect(func(action: StringName, arguments: Array): observed.append([action, arguments]))
	editor_view.build_ui()
	editor_view.settings_shade.show()
	await process_frame
	await process_frame
	for field in [editor_view.gold_choice, editor_view.size_choice, editor_view.mode_choice]:
		expect(field.get_global_rect().end.x <= editor_view.panel.get_global_rect().end.x - 20, "Container form fields retain the panel's right padding")
	editor_view.name_edit.text_changed.emit("A view-only edit")
	editor_view.command(&"new_island", [true]).call()
	expect(observed == ["A view-only edit", [&"new_island", [true]]], "Editor controls emit semantic intentions without a document/controller")
	editor_view.queue_free()
	await process_frame

func run() -> void:
	brush_transactions()
	projection_isolation()
	snapshot_policies()
	session_transitions()
	await view_ownership()
	print("Architecture checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
