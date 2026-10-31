extends Node
## Exercise progression observes committed commands; checkboxes never grant progress.
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Conditions = preload("res://src/tutorial_editor/tutorial_conditions.gd")
const Actions = preload("res://src/tutorial_editor/tutorial_actions.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
const Document = preload("res://src/tutorial_editor/tutorial_document.gd")
const Level = preload("res://src/editor/level_document.gd")
const Loc = preload("res://src/localization/text.gd")
signal next_requested(category: String)
var game
var category := "armies"
var steps: Array = []
var index := 0
var text_page := 0
var completed := false
var failed := false
var exercise_done := false
var awaiting_confirmation := false
var confirmation_action: Dictionary = {}
var goal_count := 0
var counted_targets: Dictionary = {}
var checkpoint: Dictionary = {}
var action_before: Dictionary = {}
var feedback := ""
var custom := false
var require_victory := false
var opponent_mode := "scripted"
var course_title := ""
var marker_root: Node3D
var marker_signature: Array = []
var panel
var progress
var heading
var explanation_scroll
var explanation
var retry
var finish
var next_button
var continue_button
var controls_button

func _init(controller) -> void:
	game = controller
	category = game.initial_level_data.get("tutorial_category","armies")
	custom = game.initial_level_data.get("tutorial_custom",false)
	steps = game.initial_level_data.get("tutorial_steps",Lessons.lessons(category)).duplicate(true)
	require_victory = game.initial_level_data.get("tutorial_require_victory",false)
	opponent_mode = game.initial_level_data.get("tutorial_opponent_mode","scripted")
	course_title = game.initial_level_data.get("tutorial_title",Lessons.category_title(category))

func _ready() -> void:
	marker_root = Node3D.new()
	marker_root.name = "TutorialTargets"
	game.view.add_child(marker_root)
	panel = preload("res://src/ui/tutorial_coach.gd").new(self)
	game.hud.ui_root.add_child(panel)
	for field in ["progress","heading","explanation_scroll","explanation","retry","finish","next_button","continue_button","controls_button"]: set(field,panel.get(field))
	game.hud.gold_control.tooltip_shown.connect(func(): observe("finance",game.NONE))
	game.hud.effect_row.effect_inspected.connect(func(effect): observe("status",game.NONE,{"effect":effect}))
	enter_step()

func current() -> Dictionary:
	return steps[index]

func exercise_key(number: int) -> String:
	return str(steps[number].get("exercise","step_"+str(number)))

func exercise_indices() -> Array:
	var result := []
	for number in range(steps.size()):
		if exercise_key(number) == exercise_key(index): result.append(number)
	return result

func enter_step() -> void:
	text_page = 0
	goal_count = 0
	counted_targets.clear()
	awaiting_confirmation = false
	exercise_done = false
	var first: bool = exercise_indices()[0] == index
	if first:
		feedback = ""
		game.message = ""
		game.toast_time = 0
		game.hud.toast_panel.hide()
		game.close_menus()
		game.close_event_ui()
		game.shown_event.clear()
		game.session.selection.reset()
		if current().has("setup"):
			var document := Level.new()
			var error := document.read_data(current().setup)
			if error != "": push_error(error); return
			game.rules = document.build_rules()
			game.rules.ai_difficulty = "easy"
			game.round_number = 1
			game.active_faction = 0
			game.turn_order = range(game.rules.faction_count)
			game.view.value_heatmap.set_active(false)
			game.view.configure_map(game.rules.map_size,game.rules.MapSizes.generation_bounds(game.rules.map_size),game.cells)
		checkpoint = {"state":Snapshots.capture(game.rules),"index":index,"turn_order":game.turn_order.duplicate(),"round":game.round_number,"active_hex":game.session.selection.active_hex,"heatmap":game.view.value_heatmap.active,"top_down":game.view.top_down}
	game.view.render_cells(game.cells)
	# configure_map clears ambience even when this is the same opening board.
	game.view.birds.sync()
	game.refresh_ui()
	show_lesson()
	var target: Vector2i = current().get("focus",current().get("highlight",current().target))
	if target == game.NONE and current().has("targets") and not current().targets.is_empty(): target = current().targets[0]
	if target == game.NONE and current().kind == "move":
		for source in game.cells:
			if game.rules.unit_faction(source) != 0 or game.cells[source].unit == 0 or game.cells[source].moved: continue
			for destination in game.rules.reachable_targets(source):
				if matches(current(),"move",destination,{"source":source},game.cells[destination],false):
					target = destination
					break
			if target != game.NONE: break
	if target == game.NONE:
		for at in game.cells:
			if game.cells[at].owner == 0 and game.cells[at].unit > 0: target = at; break
	if target != game.NONE: focus_target(target)

func focus_target(target: Vector2i) -> void:
	var camera: Camera3D = game.view.camera
	var screen: Vector2 = game.view.get_viewport().get_visible_rect().size * Vector2(0.48,0.35)
	var point: Vector3 = game.view.coord_position(target)
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if absf(direction.y) < 0.001: return
	var projected := origin+direction*((point.y-origin.y)/direction.y)
	var offset := point-projected
	game.view.smooth_pan_to(game.view.focus+Vector3(offset.x,0,offset.z))

func _process(_delta: float) -> void:
	panel.visible = not game.hud.stats_shade.visible
	var locked: bool = game.busy or game.closing or game.view.level_transitioning or game.get_tree().paused
	retry.disabled = locked
	continue_button.disabled = locked or not reading_substeps() and not Conditions.matches(game.rules,game.round_number,current().get("conditions",[]),current().get("condition_mode","all"))
	if not completed and not failed and not exercise_done and not locked:
		if opponent_mode == "ai" and not game.rules.has_capital(0):
			failed = true
			game.game_over = true
			show_lesson()
		elif current().kind == "any": observe("state",game.NONE)
	marker_root.visible = not completed and not failed and not exercise_done and not locked and not game.hud.stats_shade.visible and not game.event_shade.visible

func matches(step: Dictionary, kind: String, target: Vector2i, details: Dictionary, before: Dictionary, committed: bool) -> bool:
	if step.kind != "any" and (kind != step.kind or not Document.target_matches(step,target)): return false
	for key in step.details:
		if key == "outcome" and not committed: continue
		if (details.get("kind") if key == "outcome" else details.get(key)) != step.details[key]: return false
	var criteria: Dictionary = step.get("criteria",{})
	var cell: Dictionary = game.cells.get(target,{})
	if criteria.has("owner_before"):
		if before.get("owner") != int(criteria.owner_before): return false
		if committed and (not details.get("capture",false) or cell.get("owner") != 0): return false
	if criteria.has("unit_before") and before.get("unit") != int(criteria.unit_before): return false
	if criteria.has("animal_before") and before.get("animal","") != criteria.animal_before: return false
	if criteria.has("value_before") and before.get("value") != int(criteria.value_before): return false
	if criteria.has("min_value") and int(before.get("value",0)) < int(criteria.min_value): return false
	if criteria.get("plain",false):
		for key in ["tree","grave","event","treasure","lair","mana_source","mountain","building"]:
			if before.get(key): return false
	if criteria.has("unit") and cell.get("unit") != int(criteria.unit): return false
	if criteria.has("building") and cell.get("building") != criteria.building: return false
	if criteria.has("source_tier"):
		var source: Dictionary = details.get("before_source",game.cells.get(details.get("source"),{}))
		if source.get("unit") != int(criteria.source_tier): return false
	return true

func budget() -> Dictionary:
	var bank: Dictionary = game.active_kingdom()
	return {"gold":bank.get("gold",0),"income":0 if bank.is_empty() else game.rules.income(bank),"net":0 if bank.is_empty() else game.rules.income(bank)-game.rules.upkeep(bank)}

func permits(kind: String, target: Vector2i, details: Dictionary = {}) -> bool:
	if completed or failed: return false
	if kind in ["inspect","select","kingdom","animal","finance","status","view","heatmap","stats"]: return true
	if exercise_done: return false
	if reading_substeps():
		game.announce(Loc.text("Read the tutorial text, then press Continue before taking an action."))
		return false
	var step := current()
	var allowed: bool = not step.get("restrict_actions",true) or step.kind in ["any","continue"] or kind == "end_turn" and step.get("allow_turns",false) or matches(step,kind,target,details,game.cells.get(target,{}),false)
	if not allowed:
		game.announce(Loc.text("Follow the unchecked objective. Any valid highlighted tile counts when no particular location is requested."))
		return false
	action_before = {"kind":kind,"target":target,"cell":game.cells.get(target,{}).duplicate(true),"budget":budget()}
	return true

func observe(kind: String, target: Vector2i, details: Dictionary = {}) -> void:
	if kind == "stats": panel.visible = not game.hud.stats_shade.visible
	if completed or failed or exercise_done or game.closing or game.busy or game.get_tree().paused: return
	var step := current()
	var before: Dictionary = details.get("before_target",action_before.get("cell",{}) if action_before.get("kind") == kind and action_before.get("target") == target else game.cells.get(target,{}))
	if reading_substeps(): return
	if not matches(step,kind,target,details,before,true): return
	if not Conditions.matches(game.rules,game.round_number,step.get("conditions",[]),step.get("condition_mode","all")): return
	if step.get("confirm",false) and not details.get("confirmed",false):
		awaiting_confirmation = true
		confirmation_action = {"target":target,"details":details.duplicate(true).merged({"before_target":before})}
		show_lesson()
		return
	if step.get("count",1) > 1:
		if counted_targets.has(target): return
		counted_targets[target] = true
	goal_count += 1
	if goal_count < int(step.get("count",1)):
		show_lesson()
		return
	if index == steps.size()-1:
		if require_victory and not Conditions.victory(game.rules): return
		completed = true
		if category in Lessons.IDS and not game.initial_level_data.get("tutorial_playtest",false):
			Gameplay.complete_tutorial(category)
		exercise_done = true
		game.game_over = true
		game.winner_faction = 0 if Conditions.victory(game.rules) else -1
	elif exercise_key(index+1) != exercise_key(index): exercise_done = true
	else:
		index += 1
		enter_step()
		return
	show_lesson()

func continue_lesson() -> void:
	if game.busy or game.closing or game.get_tree().paused or game.view.level_transitioning: return
	if reading_substeps():
		text_page += 1
		explanation_scroll.scroll_vertical = 0
		if not reading_substeps() and current().kind == "continue": observe("continue",game.NONE)
		show_lesson()
		return
	if exercise_done and not completed:
		index += 1
		enter_step()
	elif awaiting_confirmation: observe(current().kind,confirmation_action.target,confirmation_action.details.merged({"confirmed":true}))
	else: observe("continue",game.NONE)

func next_topic() -> void:
	var following := Lessons.IDS.find(category)+1
	if following < Lessons.IDS.size(): next_requested.emit(Lessons.IDS[following])

func show_lesson() -> void:
	panel.render()
	refresh_marker()
	game.hud.gold_control.modulate = Color("fff0b8") if current().kind == "finance" and not exercise_done and not completed else Color.WHITE
	for entry in [["recruit",game.hud.recruit_button],["build",game.hud.build_button],["spell",game.hud.spell_button],["end_turn",game.hud.end_button]]:
		entry[1].modulate = Color("fff0b8") if current().kind == entry[0] and not completed and not exercise_done else Color.WHITE

func refresh_marker() -> void:
	if marker_root == null: return
	var target: Vector2i = current().get("highlight",current().target)
	var source: Vector2i = current().details.get("source",game.NONE)
	var targets: Array = Document.target_hexes(current()) if current().has("targets") else ([] if target == game.NONE else [target])
	var signature := [targets,source,completed,exercise_done]
	if signature == marker_signature: return
	marker_signature = signature
	for child in marker_root.get_children(): child.free()
	if completed or exercise_done: return
	var entries: Array = []
	if current().has("targets") and not targets.is_empty():
		var region := {}
		for at in targets: region[at] = true
		# A broad gold band sits below normal reach borders so both remain visible.
		var border: MeshInstance3D = game.view.overlays.show_area(region,Color("ffd66e"),"TutorialAreaBacking","TutorialArea","TutorialAreaWash",-0.01,marker_root,0.24)
		border.set_meta("role","target_area")
		border.set_meta("targets",targets)
	else:
		for at in targets: entries.append([at,Color("ffd66e")])
	entries.append([source,Color("79e1f2")])
	for entry in entries:
		if entry[0] == game.NONE: continue
		var marker := MeshInstance3D.new()
		marker.mesh = game.view.overlays.marker_mesh(1.03,0.79)
		marker.position = game.view.coord_position(entry[0])+Vector3(0,0.08,0)
		marker.set_meta("hex", entry[0])
		marker.set_meta("role", "source" if entry[0] == source else "target")
		marker.material_override = game.view.material(entry[1],true,true)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker_root.add_child(marker)

func restart_lesson() -> void:
	if game.busy or game.closing or game.get_tree().paused or game.view.level_transitioning: return
	completed = false
	failed = false
	game.game_over = false
	index = checkpoint.index
	text_page = 0
	goal_count = 0
	counted_targets.clear()
	awaiting_confirmation = false
	exercise_done = false
	action_before.clear()
	feedback = ""
	game.player_move_revision += 1
	game.player_move_snapshot.clear()
	Snapshots.restore(game.rules,checkpoint.state)
	game.turn_order = checkpoint.turn_order.duplicate()
	game.round_number = checkpoint.round
	game.session.selection.reset()
	game.session.selection.active_hex = checkpoint.active_hex
	game.view.value_heatmap.set_active(checkpoint.heatmap)
	if game.view.top_down != checkpoint.top_down: game.view.toggle_top_down()
	game.shown_event.clear()
	game.close_event_ui()
	game.close_menus()
	game.view.render_cells(game.cells)
	game.refresh_ui()
	show_lesson()
	if not game.rules.pending_events.is_empty(): game.show_next_event()

func end_turn() -> void:
	if game.commands_locked() or not permits("end_turn",game.NONE): return
	if opponent_mode == "ai":
		await preload("res://src/game/opponent_turns.gd").run(game)
		observe("end_turn",game.NONE)
		return
	game.session.begin_work(true)
	game.close_menus()
	game.session.selection.selected = game.NONE
	game.session.selection.action_mode = ""
	for faction in range(1,game.rules.faction_count):
		game.active_faction = faction
		await settle(faction)
		if game.closing: game.session.finish_work(); return
		if opponent_mode == "scripted":
			for order in current().get("opponent",[]):
				if int(order.get("faction",1)) != faction: continue
				var result := Actions.apply(game.rules,order,faction)
				if not result.ok:
					game.session.finish_work()
					game.active_faction = 0
					game.announce(Loc.text("An authored order failed. Retry the exercise."))
					return
				if not result.moves.is_empty(): await game.view.animate_moves(result.moves,game.cells)
				if game.closing: game.session.finish_work(); return
	game.round_number += 1
	if current().get("wildlife_turn",false):
		var actions: Array = game.rules.Wildlife.world_turn(game.rules)
		await game.view.wildlife.play_world(actions,game.cells)
		if game.closing: game.session.finish_work(); return
	game.active_faction = 0
	await settle(0)
	if game.closing: game.session.finish_work(); return
	game.playback_kingdoms.clear()
	game.playback_mana.clear()
	game.view.render_cells(game.cells)
	game.session.finish_work()
	game.refresh_ui()
	observe("end_turn",game.NONE)

func settle(faction: int) -> void:
	var before: Dictionary = game.cells.duplicate(true)
	var deaths: int = game.rules.begin_turn(faction)
	var actions := []
	for at in before:
		if before[at].unit > 0 and game.cells[at].unit == 0:
			actions.append({"kind":"death","coord":at})
	if not actions.is_empty():
		await game.view.play_preparation(actions,game.cells)
		game.announce(Loc.text("%d soldiers starved in %s.") % [deaths,game.NAMES[faction]])

func reading_substeps() -> bool:
	return not completed and not failed and not exercise_done and (current().get("read_before_action",false) or not current().get("substeps",[]).is_empty()) and text_page <= current().get("substeps",[]).size()

func reading_title() -> String:
	if reading_substeps() and text_page > 0:
		var title: String = current().substeps[text_page-1].get("title","")
		if title != "": return title
	return current().title

func reading_text() -> String:
	if reading_substeps() and text_page > 0: return current().substeps[text_page-1].text
	return current().text
