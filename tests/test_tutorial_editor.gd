extends SceneTree
const Doc = preload("res://src/tutorial_editor/tutorial_document.gd")
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Conditions = preload("res://src/tutorial_editor/tutorial_conditions.gd")
const Simulator = preload("res://src/tutorial_editor/tutorial_simulator.gd")
var checks := 0
var failures := 0
var surface: Viewport
var preview := false

func _initialize() -> void:
	preview = "--preview" in OS.get_cmdline_user_args()
	if preview: root.hide()
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func template(category: String):
	var document := Doc.new()
	document.data = {"format":"slay-tutorial","version":1,"title":category.capitalize(),"category":category,"map":Lessons.Scenarios.map_data(category),"opponent_mode":"ai" if category == "practice" else "scripted","require_victory":category == "practice","steps":Doc.encode(Lessons.builtin_lessons(category))}
	return document

func capture(name: String) -> void:
	if not preview: return
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	surface.get_texture().get_image().save_png("res://artifacts/tutorial-editor-"+name+".png")

func run() -> void:
	for category in Lessons.IDS:
		var document = template(category)
		expect(Doc.validate(document.data) == "","Template is valid portable JSON: " + category)
		var result := Simulator.run(document)
		expect((result.error == "" or result.error.contains("manual playtest")) and result.rules != null,"Simulation either validates a specified path or identifies a manual choice: " + category)
		var filename := "res://artifacts/editor-%s.tutorial.json" % category
		expect(document.save_file(filename) == "","Save tutorial: " + category)
		var loaded := Doc.new()
		expect(loaded.load_file(filename) == "" and loaded.data == JSON.parse_string(JSON.stringify(document.data)),"Round trip preserves authored content")
		expect(loaded.runtime_steps()[0].target is Vector2i,"JSON coordinates restore to game vectors")
		var before: Dictionary = loaded.data.duplicate(true)
		var invalid: Dictionary = before.duplicate(true)
		invalid.steps[0].kind = "bad action"
		expect(loaded.read_data(invalid) != "" and loaded.data == before,"Bad imports preserve the current document")
		var original := FileAccess.get_file_as_string(filename)
		loaded.data.steps[0].kind = "invalid"
		expect(loaded.save_file(filename) != "" and FileAccess.get_file_as_string(filename) == original,"Invalid saves preserve the previous file")
	DirAccess.make_dir_recursive_absolute("res://artifacts/editor-installed")
	var install_doc = template("armies")
	install_doc.data.title = "Installed custom course"
	install_doc.save_file("res://artifacts/editor-installed/armies.json")
	var installed = Lessons.installed("armies","res://artifacts/editor-installed")
	expect(installed != null and installed.level_data().tutorial_steps.size() == Lessons.builtin_lessons("armies").size() and installed.level_data().tutorial_title == "Installed custom course","The game's category loader reads an exported tutorial")
	var document = template("armies")
	var result := Simulator.run(document,0)
	var rules = result.rules
	var at := Vector2i.ZERO
	expect(Conditions.check(rules,1,{"type":"owner","target":[0,0],"value":0}),"Owner predicate reads the prepared position")
	expect(Conditions.check(rules,1,{"type":"unit","target":[0,0],"value":1,"faction":0}),"Unit predicate reads the real army")
	expect(not Conditions.check(rules,1,{"type":"unit","target":[0,0],"value":2,"faction":0}),"Unit predicate rejects weaker armies")
	expect(not Conditions.check(rules,1,{"type":"owner","target":[90,90],"value":0}),"Missing tiles do not satisfy tile conditions")
	var conditions := [{"type":"round","value":2},{"type":"owner","target":[-2,0],"value":0}]
	expect(not Conditions.matches(rules,1,conditions,"all") and Conditions.matches(rules,1,conditions,"any"),"All/any combine conditions correctly")
	expect(not Conditions.victory(rules),"Surviving enemies prevent victory")
	rules.cells[at].road = true
	expect(Conditions.check(rules,1,{"type":"building","target":[0,0],"value":"road"}),"Road conditions read pavement independently of the tile's structure")
	rules.cells[at].erase("road")
	for change in [
		{"conditions":[{"type":"unit","target":null,"value":1}]},
		{"target":[1.5,0]},
		{"details":{"tier":99}},
		{"kind":"any","conditions":[]},
		{"count":0},
		{"allow_turns":"yes"},
		{"setup":{"invalid":"map"}},
		{"criteria":{"owner_before":9}},
		{"criteria":{"plain":1}},
		{"criteria":{"source_tier":4}},
		{"opponent":[{"kind":"move","target":[-2,0],"faction":99}]},
	]:
		var invalid: Dictionary = document.data.duplicate(true)
		invalid.steps[0].merge(change,true)
		expect(Doc.validate(invalid) != "","Malformed authored rule rejected: " + str(change))
	root.size = Vector2i(1360,900)
	surface = root
	if preview:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1360,900)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		surface = viewport
	var editor = load("res://src/tutorial_editor/tutorial_editor.gd").new()
	surface.add_child(editor)
	await process_frame
	expect(not editor.document.dirty(),"Blank editor opens without a false unsaved warning")
	editor.load_template()
	expect(editor.document.data.steps.size() == Lessons.builtin_lessons("armies").size(),"Load template exposes all Armies objectives")
	editor.inspector.fields.title.text = "My first recruit"
	editor.inspector.fields.title.text_changed.emit("My first recruit")
	expect(editor.document.data.steps[0].title == "My first recruit","Textboxes edit the document directly")
	editor.inspector.fields.exercise.text = "new_group"
	editor.inspector.fields.count.value = 2
	editor.inspector.fields.allow_turns.set_pressed_no_signal(true)
	editor.inspector.collect()
	expect(editor.document.data.steps[0].exercise == "new_group" and editor.document.data.steps[0].count == 2 and editor.document.data.steps[0].allow_turns,"Exercise grouping, repeated captures and turn permission are editable")
	editor.commit()
	editor.undo()
	expect(editor.document.data.steps[0].title != "My first recruit","Undo restores text")
	editor.redo()
	expect(editor.document.data.steps[0].title == "My first recruit","Redo restores the edit")
	editor.duplicate_step()
	expect(editor.document.data.steps.size() == Lessons.builtin_lessons("armies").size()+1 and editor.document.data.steps[0].id != editor.document.data.steps[1].id,"Duplicate keeps step IDs unique")
	editor.move_step(1)
	expect(editor.step_index == 2,"Steps can be reordered")
	editor.delete_step()
	expect(editor.document.data.steps.size() == Lessons.builtin_lessons("armies").size(),"Delete preserves remaining steps")
	editor.load_template()
	editor.select_step(0)
	editor.pick_field = editor.inspector.fields.target
	editor.tile_picked(Vector2i(-2,0))
	expect(editor.document.data.steps[0].target == [-2,0],"Map click assigns an action target")
	editor.inspector.select_value("cond_type","gold")
	editor.inspector.fields.cond_target.text = "-3, 0"
	editor.inspector.fields.cond_value.text = "0"
	editor.inspector.save_condition(false)
	expect(editor.document.data.steps[0].conditions.size() == 1,"Board conditions can be added without JSON editing")
	editor.inspector.conditions.select(0)
	editor.inspector.remove_condition()
	expect(editor.document.data.steps[0].conditions.is_empty(),"Conditions can be removed")
	editor.select_step(0)
	editor.inspector.select_value("op_kind","recruit")
	editor.inspector.fields.op_faction.text = "1"
	editor.inspector.fields.op_target.text = "2, 1"
	editor.inspector.fields.op_value.text = "1"
	editor.inspector.save_order(false)
	expect(editor.document.data.steps[0].opponent.size() == 1,"Opponent orders are authored with form fields")
	editor.inspector.orders.select(0)
	editor.inspector.remove_order()
	editor.preview_step()
	expect(editor.canvas.cells[at].owner == 0,"Step preview shows the exercise starting position without changing the map")
	expect(editor.document.data.map.cells.size() == Lessons.Scenarios.map_data("armies").cells.size(),"Preview does not mutate the embedded starting map")
	editor.select_step(0)
	editor.inspector.select_value("kind","build")
	editor.inspector.collect()
	expect(not editor.document.data.steps[0].details.has("tier"),"Changing action removes incompatible filters")
	editor.inspector.select_value("kind","recruit")
	editor.inspector.collect()
	await capture("text")
	editor.inspector.current_tab = 1
	await capture("goals")
	editor.inspector.current_tab = 2
	await capture("conditions")
	editor.select_step(3)
	editor.inspector.current_tab = 3
	await capture("opponent")
	editor.inspector.current_tab = 0
	editor.inspector.fields.title.text = "Recovered heading"
	editor.inspector.fields.title.text_changed.emit("Recovered heading")
	editor.commit()
	editor.new_document()
	editor.recover()
	expect(editor.document.data.steps[3].title == "Recovered heading","Autosave recovery preserves edited tutorial content")
	editor.load_template()
	# Map import is atomic and does not overwrite authored text or steps.
	var map_file := "res://artifacts/editor-map.json"
	Doc.write_atomic(map_file,template("construction").data.map)
	var heading_before: String = editor.document.data.steps[0].title
	editor.import_map(map_file)
	expect(editor.document.data.map.cells.size() == Lessons.Scenarios.map_data("construction").cells.size() and editor.document.data.steps[0].title == heading_before and editor.document.data.steps.all(func(step): return not step.has("setup")),"Import map preserves authored text and replaces every prepared position")
	var map_before: Dictionary = editor.document.data.map.duplicate(true)
	Doc.write_atomic(map_file,{"not":"a map"})
	editor.import_map(map_file)
	expect(editor.document.data.map == map_before,"Invalid map import preserves the draft")
	# Custom data drives the actual tutorial controller, not just the simulator.
	editor.new_document()
	editor.document.data.title = "My custom scenario"
	editor.document.data.steps = [Doc.new_step(),Doc.new_step()]
	for step in editor.document.data.steps: step.exercise = "custom"
	editor.document.data.steps[0].text = "A longer explanation can scroll without hiding the objective or buttons. ".repeat(30)
	editor.document.data.steps[1].id = "free_play"
	editor.document.data.steps[1].kind = "any"
	editor.document.data.steps[1].conditions = [{"type":"round","value":2,"faction":0,"target":null}]
	editor.document.data.opponent_mode = "idle"
	editor.refresh(true)
	var draft: Dictionary = editor.document.data.duplicate(true)
	await editor.playtest(false)
	var progress_before: Dictionary = root.get_node("Gameplay").completed_tutorials.duplicate()
	var game = editor.app.game
	expect(game.tutorial.custom and game.tutorial.course_title == "My custom scenario","Playtest uses the authored course")
	expect(game.tutorial.continue_button.visible,"Manual step shows a Continue button")
	expect(game.tutorial.panel.size.y < 500 and game.tutorial.explanation_scroll.size.y <= 180,"Long text scrolls inside the card")
	await capture("long-prompt")
	game.tutorial.continue_button.pressed.emit()
	expect(game.tutorial.index == 1,"Continue advances exactly one step")
	await game.end_turn()
	await process_frame
	expect(game.tutorial.completed and not game.tutorial.require_victory,"Board-state condition can finish a non-victory lesson")
	expect(root.get_node("Gameplay").completed_tutorials == progress_before,"Editor playtests cannot mark the player's tutorials complete")
	await capture("playtest")
	await editor.stop_playtest()
	expect(editor.visible and editor.document.data == draft,"Returning from playtest preserves the draft")
	# An action and multiple board predicates must all agree before advancing.
	editor.new_document()
	editor.document.data.steps = [Doc.new_step()]
	editor.document.data.steps[0].kind = "recruit"
	editor.document.data.steps[0].target = [-3,0]
	editor.document.data.steps[0].details = {"tier":1}
	editor.document.data.steps[0].conditions = [{"type":"unit","target":[-3,0],"value":1,"faction":0},{"type":"gold","target":[-3,0],"value":0,"faction":0}]
	editor.refresh(true)
	await editor.playtest(false)
	game = editor.app.game
	game.choose_unit(1)
	await game.click_hex(Vector2i(-3,0))
	expect(game.tutorial.completed,"Committed recruitment and all authored board predicates advance together")
	await editor.stop_playtest()
	editor.new_document()
	editor.document.data.opponent_mode = "ai"
	editor.document.data.map = Lessons.Scenarios.position("practice")
	editor.document.data.steps[0].kind = "any"
	editor.document.data.steps[0].conditions = [{"type":"round","value":2,"target":null,"faction":0}]
	editor.refresh(true)
	await editor.playtest(false)
	game = editor.app.game
	var enemy_before: int = game.rules.territory(1)
	await game.end_turn()
	await process_frame
	expect(game.tutorial.completed and game.round_number == 2 and game.rules.territory(1) > enemy_before,"Normal AI can play real turns in a free-play step")
	await editor.stop_playtest()
	# Start at a simulated checkpoint and verify state is real in the game.
	editor.load_template()
	var rank_start := Lessons.builtin_lessons("armies").find_custom(func(step): return step.id == "upgrade_soldier")
	editor.select_step(rank_start)
	await editor.playtest(true)
	expect(editor.app.game.tutorial.index == rank_start and editor.app.game.cells[Vector2i(-3,0)].unit == 2 and editor.app.game.cells[Vector2i(-3,0)].moved and editor.app.game.rules.territory(0) == 16,"Play this step restores the merged Soldier and simulated match checkpoint")
	await editor.stop_playtest()
	editor.select_step(1)
	await editor.playtest(true)
	expect(editor.app.game.tutorial.index == 1 and editor.app.game.tutorial.checkpoint.index == 0,"Later-goal playtests retain the current exercise's retry checkpoint")
	editor.app.game.tutorial.restart_lesson()
	expect(editor.app.game.tutorial.index == 0,"Retry from a later playtest goal returns to the correct exercise")
	await editor.stop_playtest()
	surface.size = Vector2i(1160,720)
	for frame in range(3): await process_frame
	expect(surface.get_visible_rect().encloses(editor.inspector.get_global_rect()) and surface.get_visible_rect().encloses(editor.canvas.get_global_rect()),"Map and inspector fit the tool's minimum window")
	await capture("small-window")
	editor.template.select(Lessons.IDS.find("logistics"))
	editor.load_template()
	var road_index: int = editor.document.data.steps.find_custom(func(step): return step.id == "supply_road")
	editor.select_step(road_index)
	editor.inspector.collect()
	expect(editor.document.data.steps[road_index].target == [3,0] and editor.document.data.steps[road_index].details.source == [-4,0],"Editing a road objective retains both connection endpoints")
	var name_index: int = editor.document.data.steps.find_custom(func(step): return step.id == "name_city")
	editor.select_step(name_index)
	editor.inspector.collect()
	expect(editor.document.data.steps[name_index].target == [3,0] and Doc.validate(editor.document.data) == "","City-naming objectives retain their target in valid portable tutorials")
	editor.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(0.5).timeout
	print("Tutorial editor checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
