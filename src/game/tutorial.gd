extends Node
const Loc = preload("res://src/localization/text.gd")
## Objective progression observes committed game commands, never elapsed time.
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Conditions = preload("res://src/tutorial_editor/tutorial_conditions.gd")
const Actions = preload("res://src/tutorial_editor/tutorial_actions.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
var game
signal next_requested(category: String)
var category := "basics"
var steps: Array = []
var index := 0
var completed := false
var checkpoint: Dictionary = {}
var panel: Panel
var progress: Label
var heading: Label
var explanation: Label
var explanation_scroll: ScrollContainer
var objective: Label
var retry: Button
var finish: Button
var next_button: Button
var continue_button: Button
var custom := false
var require_victory := true
var opponent_mode := "scripted"
var course_title := ""
var marker_root: Node3D
var marker_signature: Array = []

func _init(controller) -> void:
	game = controller
	category = game.initial_level_data.get("tutorial_category", "basics")
	custom = game.initial_level_data.get("tutorial_custom",false)
	steps = game.initial_level_data.get("tutorial_steps",Lessons.lessons(category)).duplicate(true)
	require_victory = game.initial_level_data.get("tutorial_require_victory",true)
	opponent_mode = game.initial_level_data.get("tutorial_opponent_mode","scripted")
	course_title = game.initial_level_data.get("tutorial_title",Lessons.category_title(category))

func _ready() -> void:
	marker_root = Node3D.new()
	marker_root.name = "TutorialTargets"
	game.view.add_child(marker_root)
	panel = Ui.panel(game.hud.ui_root,Rect2(0,0,300,220))
	panel.anchor_left = 1
	panel.anchor_right = 1
	panel.offset_left = -324
	panel.offset_right = -24
	panel.offset_top = 88
	progress = Ui.label_at(panel,"",Vector2(18,14),12,Ui.MUTED)
	heading = Ui.label_at(panel,"",Vector2(18,39),20)
	explanation_scroll = ScrollContainer.new()
	explanation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(explanation_scroll)
	explanation = Ui.label_at(explanation_scroll,"",Vector2.ZERO,14)
	explanation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective = Ui.label_at(panel,"",Vector2(18,200),15,Ui.ACCENT)
	retry = game.hud.button_at(panel,"Retry step",Rect2(18,180,126,34),restart_lesson)
	retry.add_theme_font_size_override("font_size",14)
	finish = game.hud.button_at(panel,"Main menu",Rect2(18,180,126,34),func(): game.tutorial_exit_requested.emit(),"",true)
	finish.hide()
	var following := Lessons.IDS.find(category) + 1
	next_button = game.hud.button_at(panel, "", Rect2(156,180,126,34), func():
		if following < Lessons.IDS.size(): next_requested.emit(Lessons.IDS[following]), "", true)
	next_button.add_theme_font_size_override("font_size",14)
	next_button.text = Loc.text("Next match")
	next_button.hide()
	continue_button = game.hud.button_at(panel,"Continue",Rect2(156,180,126,34),func(): observe("continue",game.NONE),"",true)
	continue_button.hide()
	enter_step()

func current() -> Dictionary:
	return steps[index]

func enter_step() -> void:
	var step := current()
	game.close_menus()
	game.session.selection.selected = game.NONE
	game.session.selection.action_mode = ""
	game.session.selection.inspected_unit = game.NONE
	game.session.selection.inspected_animal = game.NONE
	game.message = ""
	game.toast_time = 0
	game.hud.toast_panel.hide()
	game.session.selection.valid_targets.clear()
	var target: Vector2i = step.get("highlight",step["target"])
	var source: Vector2i = step["details"].get("source",target)
	if game.cells.has(source) and game.cells[source]["owner"] == 0: game.session.selection.active_hex = source
	checkpoint = {"cells":game.cells.duplicate(true),"kingdoms":game.rules.kingdoms.duplicate(true),"mana":game.rules.mana_by_faction.duplicate(true),"effects":game.rules.effects_by_faction.duplicate(true),"faction_count":game.rules.faction_count,"turn_order":game.turn_order.duplicate(),"events":game.rules.pending_events.duplicate(true),"rng":game.rules.rng.state,"round":game.round_number,"active_hex":game.session.selection.active_hex,"heatmap":game.view.value_heatmap.active,"top_down":game.view.top_down}
	game.view.render_cells(game.cells)
	game.refresh_ui()
	show_lesson()
	if target != game.NONE:
		game.view.smooth_pan_to(game.view.coord_position(target)+game.view.camera.global_basis.x*3.0)

func _process(_delta: float) -> void:
	retry.disabled = game.busy or game.view.level_transitioning or game.closing
	continue_button.disabled = retry.disabled or not Conditions.matches(game.rules,game.round_number,current().get("conditions",[]),current().get("condition_mode","all"))
	if not completed and not retry.disabled and not game.get_tree().paused and current()["kind"] == "any": observe("state",game.NONE)
	marker_root.visible = not completed and not game.busy and not game.view.level_transitioning and not game.hud.stats_shade.visible and not game.event_shade.visible

func permits(kind: String, target: Vector2i, details: Dictionary = {}) -> bool:
	if completed: return false
	if not current().get("restrict_actions",true) or current()["kind"] in ["any","continue"]: return true
	# Inspection, selection, camera and statistics remain available for learning.
	if kind in ["inspect","select","view","heatmap","stats"]: return true
	var step := current()
	if kind != step["kind"] or (step["target"] != game.NONE and target != step["target"]):
		game.announce(Loc.text("Follow the tutorial objective. Right-click / Escape cancels placement."))
		return false
	for key in step["details"]:
		if key != "outcome" and details.get(key) != step["details"][key]:
			game.announce(Loc.text("Use the unit or purchase named in this lesson."))
			return false
	return true

func observe(kind: String, target: Vector2i, details: Dictionary = {}) -> void:
	if completed or game.closing or game.busy or game.get_tree().paused: return
	var step := current()
	if step["kind"] != "any" and (kind != step["kind"] or (step["target"] != game.NONE and target != step["target"])): return
	for key in step["details"]:
		var value = details.get("kind") if key == "outcome" else details.get(key)
		if value != step["details"][key]: return
	if not Conditions.matches(game.rules,game.round_number,step.get("conditions",[]),step.get("condition_mode","all")): return
	if index == steps.size()-1:
		if require_victory and not Conditions.victory(game.rules):
			return
		completed = true
		game.winner_faction = 0
		game.announce(Loc.text("Victory!") if Conditions.victory(game.rules) else "Lesson complete")
		game.game_over = true
		game.session.selection.selected = game.NONE
		game.session.selection.action_mode = ""
		game.close_menus()
		game.refresh_ui()
		show_lesson()
		return
	index += 1
	enter_step()

func show_lesson() -> void:
	var step := current()
	progress.text = ((Loc.text("%s - Match won") if Conditions.victory(game.rules) else "%s - Complete") % course_title) if completed else Loc.text("%s  ·  %d / %d") % [course_title,index+1,steps.size()]
	heading.text = (Loc.text("Victory!") if Conditions.victory(game.rules) else "Lesson complete") if completed else step["title"]
	Ui.fit_text(heading,heading.text,264)
	explanation_scroll.position = Vector2(18,heading.position.y+heading.size.y+12)
	var completion := "Tutorial finished. Return to the menu when you are ready." if custom else Loc.text("You defeated your opponent. Play the next match or return to the menu.") if category != "advanced" else Loc.text("You defeated your opponent. You are ready for Quick Play.")
	Ui.fit_text(explanation,completion if completed else step["text"],246)
	explanation_scroll.size = Vector2(264,minf(140,explanation.get_minimum_size().y))
	objective.position.y = explanation_scroll.position.y+explanation_scroll.size.y+12
	Ui.fit_text(objective,"" if completed else step["task"],264)
	retry.position.y = objective.position.y+objective.size.y+14
	finish.position.y = retry.position.y
	next_button.position.y = retry.position.y
	continue_button.position.y = retry.position.y
	continue_button.visible = not completed and step["kind"] == "continue"
	panel.size.y = retry.position.y+retry.size.y+16
	retry.visible = not completed
	finish.visible = completed
	next_button.visible = completed and category != "advanced" and not custom
	for button in [game.hud.recruit_button,game.hud.build_button,game.hud.spell_button,game.hud.end_button,game.hud.view_button,game.hud.heatmap_button,game.hud.stats_button]:
		button.modulate = Color.WHITE
		button.queue_redraw()
	var button = {"recruit":game.hud.recruit_button,"build":game.hud.build_button,"spell":game.hud.spell_button,"end_turn":game.hud.end_button,"view":game.hud.view_button,"heatmap":game.hud.heatmap_button,"stats":game.hud.stats_button}.get(step["kind"])
	if button != null and not completed: button.modulate = Color("fff0b8")
	refresh_marker()

func refresh_marker() -> void:
	var target: Vector2i = current().get("highlight",current()["target"])
	var source: Vector2i = current()["details"].get("source",game.NONE)
	var signature: Array = [target,source,completed]
	if signature == marker_signature: return
	marker_signature = signature
	for child in marker_root.get_children():
		marker_root.remove_child(child)
		child.queue_free()
	if completed: return
	for entry in [[target,Color("ffd66e")],[source,Color("79e1f2")]]:
		if entry[0] == game.NONE: continue
		for layer in range(2):
			var marker := MeshInstance3D.new()
			marker.mesh = game.view.overlays.marker_mesh(1.03 if layer == 0 else 0.995,0.79 if layer == 0 else 0.84)
			marker.position = game.view.coord_position(entry[0])+Vector3(0,0.075+layer*0.03,0)
			marker.material_override = game.view.material(Color("182d34") if layer == 0 else entry[1],true,true)
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			marker_root.add_child(marker)

func restart_lesson() -> void:
	if game.busy or game.closing or game.get_tree().paused or game.view.level_transitioning: return
	completed = false
	game.game_over = false
	game.player_move_revision += 1
	game.player_move_snapshot.clear()
	game.rules.cells = checkpoint["cells"].duplicate(true)
	game.rules.kingdoms = checkpoint["kingdoms"].duplicate(true)
	game.rules.mana_by_faction = checkpoint["mana"].duplicate(true)
	game.rules.effects_by_faction = checkpoint["effects"].duplicate(true)
	game.rules.faction_count = checkpoint.get("faction_count", game.rules.faction_count)
	game.turn_order = checkpoint.get("turn_order", game.turn_order).duplicate()
	game.rules.pending_events = checkpoint["events"].duplicate(true)
	game.rules.rng.state = checkpoint["rng"]
	game.round_number = checkpoint["round"]
	game.session.selection.active_hex = checkpoint["active_hex"]
	game.view.value_heatmap.set_active(checkpoint["heatmap"])
	if game.view.top_down != checkpoint["top_down"]: game.view.toggle_top_down()
	game.shown_event.clear()
	game.close_event_ui()
	game.close_menus()
	game.session.selection.selected = game.NONE
	game.session.selection.action_mode = ""
	game.view.render_cells(game.cells)
	game.refresh_ui()
	show_lesson()

func end_turn() -> void:
	if game.commands_locked() or not permits("end_turn",game.NONE): return
	game.view.unit_presentation.set_turn(-1)
	game.session.begin_work(true)
	game.close_menus()
	game.session.selection.selected = game.NONE
	game.session.selection.action_mode = ""
	for faction in range(1,game.rules.faction_count):
		game.active_faction = faction
		game.refresh_ui()
		if opponent_mode == "ai":
			await preload("res://src/game/opponent_turns.gd").play_ai(game,faction)
		else:
			game.rules.begin_turn(faction)
		if opponent_mode == "scripted":
			for order in current().get("opponent",[]):
				if int(order.get("faction",1)) != faction: continue
				var target: Vector2i = order["target"]
				game.view.smooth_pan_to(game.view.coord_position(target)+game.view.camera.global_basis.x*3.0)
				var result: Dictionary = Actions.apply(game.rules,order,faction)
				if not result.ok:
					game.active_faction = 0
					game.session.finish_work()
					game.announce("Tutorial order failed. Retry this step or return to the editor.")
					return
				if not result.moves.is_empty(): await game.view.animate_moves(result.moves,game.cells)
				if game.closing:
					game.session.finish_work()
					return
				game.view.render_cells(game.cells)
				await game.get_tree().create_timer(0.1 if game.playback_speed.speed_held else 0.65,false).timeout
				if game.closing:
					game.session.finish_work()
					return
		if game.closing:
			game.session.finish_work()
			return
		game.view.unit_presentation.set_turn(-1)
	game.round_number += 1
	game.active_faction = 0
	game.rules.begin_turn(0)
	game.playback_kingdoms.clear()
	game.playback_mana.clear()
	game.view.render_cells(game.cells)
	game.session.finish_work()
	game.refresh_ui()
	observe("end_turn",game.NONE)
