extends SceneTree
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Document = preload("res://src/tutorial_editor/tutorial_document.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
var checks := 0
var failures := 0
var app
var surface: Viewport
var preview := false
var alternate := false

func _initialize() -> void:
	preview = "--preview" in OS.get_cmdline_user_args()
	if preview: root.hide()
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func capture(name: String) -> void:
	if not preview: return
	await create_timer(0.4).timeout
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	surface.get_texture().get_image().save_png("res://artifacts/tutorial-new-"+name+".png")

func move_order(game, step: Dictionary) -> Dictionary:
	for source in game.cells:
		if game.rules.unit_faction(source) != 0 or game.cells[source].unit == 0 or game.cells[source].moved: continue
		if step.details.has("source") and source != step.details.source: continue
		for target in game.rules.reachable_targets(source):
			if game.tutorial.matches(step,"move",target,{"source":source},game.cells[target],false): return {"source":source,"target":target}
	return {}

func target_for(game, step: Dictionary) -> Vector2i:
	if step.target != game.NONE: return step.target
	for at in game.cells:
		var details: Dictionary = step.details.duplicate()
		if not game.tutorial.matches(step,step.kind,at,details,game.cells[at],false): continue
		match step.kind:
			"select":
				if game.rules.unit_faction(at) != 0: continue
			"recruit":
				if not game.rules.can_recruit(at,0,int(step.details.tier)): continue
			"build":
				if not game.rules.can_build(at,0,step.details.building): continue
			"spell":
				if not game.rules.can_cast(step.details.spell,at,0): continue
			"develop":
				if not game.rules.can_develop(at,0): continue
		return at
	return game.NONE

func hover_control(game, control: Control, id: String) -> void:
	if not surface.has_meta("tutorial_mouse_entered"):
		surface.notify_mouse_entered()
		surface.set_meta("tutorial_mouse_entered",true)
	var before: int = game.tutorial.index
	var move := InputEventMouseMotion.new()
	move.position = Vector2(12,84)
	move.global_position = move.position
	surface.push_input(move,true)
	await process_frame
	move = InputEventMouseMotion.new()
	move.position = control.get_global_rect().get_center()
	move.global_position = move.position
	surface.push_input(move,true)
	await create_timer(1.0).timeout
	expect(game.tutorial.index != before or game.tutorial.exercise_done or game.tutorial.completed,"A real mouse hover opens and advances the tooltip objective: "+id)
	await capture(game.tutorial.category+"_"+id+"_tooltip")

func perform(game, step: Dictionary) -> bool:
	var target := target_for(game,step)
	if target == game.NONE and step.kind == "recruit" and step.get("allow_turns",false):
		await game.end_turn()
		target = target_for(game,step)
	match step.kind:
		"select": await game.click_hex(target,"unit")
		"inspect": await game.click_hex(target,"terrain")
		"kingdom": await game.click_hex(target,"terrain")
		"animal": await game.click_hex(target,"wildlife")
		"finance":
			if preview: await hover_control(game,game.hud.gold_control,step.id)
			var tip = game.hud.gold_control._make_custom_tooltip(game.hud.gold_control.tooltip_text)
			tip.free()
		"status":
			var icon = game.hud.effect_row.icons.get(step.details.effect)
			if icon == null: expect(false,"Missing required status icon: "+step.details.effect); return false
			if preview: await hover_control(game,icon,step.id)
			var tip = icon._make_custom_tooltip(icon.tooltip_text)
			tip.free()
		"recruit":
			await game.click_hex(target,"terrain")
			game.choose_unit(int(step.details.tier))
			await game.click_hex(target)
		"build":
			game.choose_building(step.details.building)
			await game.click_hex(target)
		"spell":
			game.choose_spell(step.details.spell)
			await game.click_hex(target)
		"move":
			var order := move_order(game,step)
			if order.is_empty() and step.get("allow_turns",false):
				await game.end_turn()
				order = move_order(game,step)
			if order.is_empty(): expect(false,"No legal move for "+game.tutorial.category+"/"+step.id); return false
			await game.click_hex(order.source,"unit")
			await game.click_hex(order.target)
		"end_turn": await game.end_turn()
		"develop":
			await game.click_hex(target,"terrain")
			game.develop_province()
		"entrench":
			await game.click_hex(target,"terrain")
			game.entrench_province()
		"relocate_capital":
			await game.click_hex(target,"terrain")
			game.relocate_province_capital()
			var gold: int = game.active_kingdom().gold
			game.resolve_capital_relocation(1)
			expect(game.active_kingdom().gold == gold,"Cancelling a relocation costs nothing")
			game.relocate_province_capital()
			game.resolve_capital_relocation(0)
		"stats": game.toggle_stats()
		"event": game.resolve_shown_event(1 if alternate and step.id == "choose" else 0)
		"continue": game.tutorial.continue_lesson()
		"any":
			if alternate:
				for at in game.cells:
					if game.cells[at].owner == 0 and game.cells[at].value == 1:
						await game.click_hex(at,"terrain")
						game.develop_province()
						if game.tutorial.completed or game.tutorial.exercise_done: break
			else:
				game.choose_building("house")
				for at in game.cells:
					if game.rules.can_build(at,0,"house"):
						await game.click_hex(at)
						break
	await process_frame
	return true

func play_topic(category: String) -> void:
	await app.start_tutorial(category)
	var game = app.game
	game.playback_speed.speed_held = true
	surface.size = Vector2i(960,620)
	await process_frame
	var deaths: Array = []
	var attacks: Array = []
	game.view.action_started.connect(func(action):
		if action.kind == "death": deaths.append(action.coord)
		else: attacks.append(action))
	if category == "armies": expect(game.view.birds.visible and game.view.birds.flocks.size() == game.view.birds.MAX_BIRDS,"Birds are already visible before the first Scout moves")
	var was_completed: bool = root.get_node("Gameplay").completed_tutorials.get(category,false)
	var loops := 0
	while not game.tutorial.completed and loops < 120:
		loops += 1
		var tutor = game.tutorial
		if tutor.exercise_done:
			if not was_completed: expect(not root.get_node("Gameplay").completed_tutorials.get(category,false),"An individual exercise does not mark the whole topic complete")
			expect(tutor.panel.checks.all(func(box): return box.button_pressed),"Completed exercise keeps every checkbox ticked")
			await capture(category+"_"+tutor.exercise_key(tutor.index)+"_done")
			tutor.continue_lesson()
			continue
		var step: Dictionary = tutor.current()
		var before: int = tutor.index
		var count: int = tutor.goal_count
		await capture(category+"_"+step.id)
		expect(tutor.panel.checks.size() == tutor.exercise_indices().size(),"Checklist contains the complete current exercise")
		expect(tutor.panel.checks.all(func(box): return box.mouse_filter == Control.MOUSE_FILTER_IGNORE and box.focus_mode == Control.FOCUS_NONE),"Objective boxes cannot be checked manually")
		expect(surface.get_visible_rect().encloses(tutor.panel.get_global_rect()),"Coach fits the minimum window: "+str(tutor.panel.get_global_rect()))
		if category == "economy" and step.id == "deficit":
			expect(game.rules.income(game.active_kingdom()) == 39 and game.rules.upkeep(game.active_kingdom()) == 40 and game.active_kingdom().gold == 0,"The deficit prompt describes a real 39-income, 40-wage shortfall")
		if category == "conquest" and step.id == "relocate":
			expect(game.rules.can_move(Vector2i(0,0),Vector2i(-1,0)) and game.cells[Vector2i(-1,0)].capital == 0,"The Soldier can really capture the original capital before relocation")
		if not await perform(game,step): break
		expect(tutor.completed or tutor.exercise_done or tutor.index != before or tutor.goal_count > count,"Real action progresses "+category+"/"+step.id)
		if tutor.index == before and not tutor.exercise_done and not tutor.completed and tutor.goal_count == count:
			print("STUCK ",step.id," mode ",game.action_mode," target ",target_for(game,step)," before ",tutor.action_before," units ",game.cells.values().filter(func(cell): return cell.owner == 0 and cell.unit > 0))
			break
		if category == "armies" and step.id == "neutral":
			expect(game.rules.territory(0) == 8 and game.rules.income(game.active_kingdom()) == 12,"A plain neutral capture adds owned land and one recurring income")
			expect(game.active_kingdom().gold == 10,"Ordinary capture does not immediately pay tax")
		if category == "armies" and step.id == "knight":
			expect(game.round_number == 1 and game.cells[Vector2i(0,-1)].unit == 3,"The Soldier upgrades to Knight immediately after attacking, without ending the turn")
			expect(game.cells[Vector2i(0,-1)].moved and game.rules.reachable_targets(Vector2i(0,-1)).is_empty(),"The tutorial's upgraded Knight must wait until next turn to attack")
			expect(game.message == "Knight upgraded. Ready next turn.","A spent upgrade explains that its action returns next turn")
		if category == "armies" and step.id == "duel": expect(game.cells[Vector2i(0,0)].owner == 1 and game.cells[Vector2i(0,0)].unit == 0,"Equal Knights die without capture")
		if category == "construction" and step.id == "tower": expect(not game.rules.can_move(Vector2i(0,0),Vector2i(-1,0)),"The Tower really prevents the Soldier attack")
		if category == "construction" and step.id == "tower": expect(game.rules.defense(Vector2i(0,-1)) == 0,"The Tower lends no defense to adjacent neutral land")
		if category == "economy" and step.id == "survive":
			expect(game.cells.values().filter(func(cell): return cell.owner == 0 and cell.unit > 0).size() == 2,"Ordinary Scout expansion funds both armies without a rich neutral province")
		if category == "economy" and step.id == "connect": expect(game.rules.kingdoms.values().filter(func(bank):return bank.owner == 0).size() == 1 and game.active_kingdom().gold == 10,"Reconnecting pools the banks' remaining gold")
		if category == "armies" and step.id == "destroy_tower": expect(game.cells[Vector2i(1,0)].owner == 0 and game.cells[Vector2i(1,0)].building == "","A direct Knight attack destroys the Tower")
		if category == "armies" and step.id == "entrench_turn": expect(game.cells[Vector2i(-2,-1)].unit == 2 and game.cells[Vector2i(-2,-1)].owner == 0 and attacks.any(func(action):return action.kind == "blocked_attack"),"The shield really saves the Soldier from a Knight attack")
		if category == "construction" and step.id == "flank_attack": expect(game.cells[Vector2i(-1,1)].owner == 1,"The enemy flank really captures uncovered friendly land")
		if category == "construction" and step.id == "land": expect(game.round_number == 1 and game.cells[Vector2i(1,0)].unit == 1,"Bridge crossing lands on the shore in the same turn")
		if category == "construction" and step.id == "invest": expect(game.rules.income(game.active_kingdom()) == 28 and game.active_kingdom().gold == 0,"A House gives +4 income for 20 when development costs 8 per increment")
		if category == "conquest" and step.id == "capital": expect(game.cells[Vector2i(1,0)].owner == 0 and game.cells[Vector2i(1,0)].building == "tower","Capital surrender wins the neighboring Tower intact")
		if category == "conquest" and step.id == "pocket_starve": expect([Vector2i(-1,2),Vector2i(0,2),Vector2i(-1,3)].all(func(at):return game.cells[at].unit == 0 and game.cells[at].grave and at in deaths),"All three cut-off Soldiers die with graves and death playback")
		if category == "conquest" and step.id == "old_capital_attack": expect(game.cells[Vector2i(-1,0)].owner == 1 and game.cells[Vector2i(-4,0)].capital == 0 and game.rules.has_capital(0),"Relocation actually saves the kingdom from an incoming capital attack")
		if category == "exploration" and step.id == "bear_raid": expect(game.cells[Vector2i(-1,0)].owner == -1 and game.cells[Vector2i(-1,0)].building == "" and game.cells.values().any(func(cell):return cell.get("animal","") == "bear"),"A visible Bear really raids the House and neutralizes its land")
		if category == "exploration" and step.id == "lair_spawn": expect(game.cells[Vector2i(0,0)].get("animal","") == "bear" and game.cells[Vector2i(-1,0)].building == "house","The Bear visibly emerges before it can raid the House")
		if category == "exploration" and step.id == "create_landmark": expect(game.rules.has_effect(0,"stainless_steel") and game.rules.unit_upkeep(3,0) == 34,"The event landmark really reduces Knight wages")
		if category == "exploration" and step.id == "hunt": expect(game.cells[Vector2i(0,1)].get("lair","") == "" and game.hud.effect_row.icons.has("income_bonus"),"Destroying the cave stops its lair and exposes the lasting income status")
		if category == "conquest" and step.id == "starve": expect(game.cells[Vector2i(-1,2)].unit == 0 and game.cells[Vector2i(-1,2)].grave and Vector2i(-1,2) in deaths,"The cut-off Scout dies through animated starvation")
	expect(game.tutorial.completed,"All exercises are playable: "+category)
	expect(root.get_node("Gameplay").completed_tutorials.get(category,false) and app.menus.tutorial_panel.completion_checks[category].button_pressed,"Completing the whole topic ticks its menu checkbox immediately")
	await capture(category+"_complete")
	await app.return_to_main_menu()

func run() -> void:
	var preferences = root.get_node("Gameplay")
	var previous_path: String = preferences.settings_path
	var previous_progress: Dictionary = preferences.completed_tutorials.duplicate()
	preferences.settings_path = "user://tutorial-progress-test.cfg"
	preferences.completed_tutorials.clear()
	preferences.flush_settings()
	root.size = Vector2i(960,620)
	surface = root
	if preview:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(960,620)
		viewport.own_world_3d = true
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		surface = viewport
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	root.get_node("Sound").set_muted(true,false)
	for category in Lessons.IDS:
		var map = load("res://src/editor/level_document.gd").new()
		expect(map.read_data(Lessons.map_data(category)) == "","Valid topic opening: "+category)
	app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	surface.add_child(app)
	await app.startup_finished
	await process_frame
	app.menus.show_screen(app.menus.Screen.TUTORIAL)
	expect(app.menus.tutorial_panel.category_buttons.size() == 7,"Seven subject groups replace the old three courses")
	await capture("topics")
	for category in Lessons.IDS:
		if category == "practice": continue
		await play_topic(category)
	alternate = true
	await play_topic("construction")
	await play_topic("exploration")
	await app.start_tutorial("armies")
	var game = app.game
	var tutor = game.tutorial
	game.toggle_stats()
	await process_frame
	expect(not tutor.panel.visible,"Stats remains unobscured by the tutorial coach")
	await capture("stats_unobscured")
	game.toggle_stats()
	await process_frame
	expect(tutor.panel.visible,"Closing Stats restores the coach")
	var initial := Snapshots.capture(game.rules)
	await game.click_hex(Vector2i(-2,0),"unit")
	game.choose_unit(3)
	await game.click_hex(Vector2i(-2,0))
	expect(tutor.index == 1 and Snapshots.capture(game.rules) == initial,"Unrelated purchases do not spend or skip a guided objective")
	var order := move_order(game,tutor.current())
	game.click_hex(order.target)
	tutor.game.cancel_action()
	await process_frame
	expect(tutor.index == 1 and game.rules.territory(0) == 7,"Cancelled capture cannot tick its objective")
	tutor.restart_lesson()
	expect(tutor.index == 0 and tutor.goal_count == 0 and Snapshots.capture(game.rules) == initial,"Retry restores the whole exercise and its checks")
	await app.restart_current_level()
	expect(app.game.tutorial.category == "armies" and app.game.tutorial.index == 0,"Restart retains the selected topic")
	await app.return_to_main_menu()
	await play_practice()
	var reloaded = load("res://src/settings/gameplay_settings.gd").new()
	expect(reloaded.load_settings(preferences.settings_path) == OK and Lessons.IDS.all(func(category):return reloaded.completed_tutorials.get(category,false)),"Every completed topic is retained after reloading preferences")
	reloaded.free()
	preferences.settings_path = previous_path
	preferences.completed_tutorials = previous_progress
	app.queue_free()
	await process_frame
	await create_timer(1.2).timeout
	print("Tutorial checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)

func play_practice() -> void:
	await app.start_tutorial("practice")
	var game = app.game
	game.playback_speed.speed_held = true
	game.ai_simulation_workers = false
	var tutor = game.tutorial
	var opening := Snapshots.capture(game.rules)
	expect(tutor.opponent_mode == "ai" and game.rules.territory(0) >= 6 and game.active_kingdom().gold == 10,"Practice uses a normal generated opening and active AI")
	expect(tutor.permits("recruit",Vector2i.ZERO,{"tier":3}) and tutor.permits("build",Vector2i.ZERO,{"building":"house"}),"Practice permits the player's own purchases")
	var enemy_before: int = game.rules.territory(1)
	await game.end_turn()
	await process_frame
	expect(game.round_number == 2 and game.rules.territory(1) > enemy_before,"The practice opponent expands through normal AI turns")
	expect(not tutor.completed,"Surviving enemy capitals keep the practice objective unchecked")
	# Terminal-state fixtures verify the real controller's loss, retry and victory UI.
	# They do not assert that an automated strategy can beat a normal opponent.
	for at in game.cells:
		if game.cells[at].owner == 0: game.cells[at].capital = -1
	await process_frame
	expect(not root.get_node("Gameplay").completed_tutorials.get("practice",false),"Losing a practice match does not record completion")
	expect(tutor.failed and game.game_over and tutor.retry.visible,"Losing the last capital offers a retry instead of stranding the player")
	tutor.restart_lesson()
	expect(not tutor.failed and not game.game_over and game.round_number == 1 and Snapshots.capture(game.rules) == opening,"Retry after defeat restores the complete normal opening")
	for at in game.cells:
		if game.cells[at].owner == 1: game.cells[at].capital = -1
	await process_frame
	expect(tutor.completed and tutor.panel.checks[0].button_pressed,"Removing the last enemy capital completes the practice victory objective")
	await capture("practice_end")
	tutor.finish.pressed.emit()
	await process_frame
	while app.transitioning: await process_frame
	expect(app.game == null and app.menus.tutorial_panel.visible,"Choose topic returns to the seven-topic selector")
