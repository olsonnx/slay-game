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
	expect(Lessons.IDS.size() == 8 and "conquest" not in Lessons.IDS and Doc.CATEGORIES == Lessons.IDS,"The redundant conquest course is removed from both game and editor catalogues")
	expect(Lessons.builtin_lessons("conquest").is_empty() and Lessons.installed("conquest") == null,"The removed course has no built-in or installed loader entry")
	expect(Lessons.IDS[1] == "encirclement","Cutting off armies follows the user-edited first topic")
	expect(Lessons.IDS[Lessons.IDS.find("logistics")+1] == "magic","Next topic proceeds directly from logistics to magic")
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
		{"target":null,"targets":[]},
		{"target":null,"targets":"bad"},
		{"target":null,"targets":[null]},
		{"target":null,"targets":[[1.5,0]]},
		{"target":null,"targets":[[101,0]]},
		{"target":null,"targets":[[0,0],[0,0]]},
		{"target":[0,0],"targets":[[1,0]]},
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
	expect(editor.inspector.conditions.get_selected_items() == PackedInt32Array([0]),"Adding a condition selects it for further editing")
	editor.inspector.fields.cond_value.text = "5"
	editor.inspector.save_condition(true)
	editor.inspector.fields.cond_value.text = "7"
	editor.inspector.save_condition(true)
	expect(editor.document.data.steps[0].conditions.size() == 1 and editor.document.data.steps[0].conditions[0].value == 7,"Repeated updates keep editing the selected condition")
	editor.inspector.select_value("cond_type","victory")
	editor.inspector.condition_defaults()
	expect(not editor.inspector.groups.cond_target.visible and not editor.inspector.groups.cond_value.visible and editor.inspector.groups.cond_faction.visible,"Victory condition only asks for its relevant faction")
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
	expect(editor.inspector.orders.get_selected_items() == PackedInt32Array([0]),"Adding an order selects it for further editing")
	editor.inspector.fields.op_value.text = "2"
	editor.inspector.save_order(true)
	editor.inspector.fields.op_value.text = "3"
	editor.inspector.save_order(true)
	expect(editor.document.data.steps[0].opponent.size() == 1 and editor.document.data.steps[0].opponent[0].tier == 3,"Repeated updates keep editing the selected opponent order")
	editor.inspector.orders.select(0)
	editor.inspector.remove_order()
	editor.start_pick(editor.inspector.fields.target)
	editor.select_step(1)
	expect(editor.pick_field == null,"Switching steps cancels a pending tile pick")
	expect(editor.inspector.fields.op_target.text == "" and editor.inspector.fields.cond_target.text == "","Switching steps clears uncommitted row forms")
	editor.select_step(0)
	expect(editor.step_menu.is_item_disabled(1) and not editor.step_menu.is_item_disabled(2),"Step movement buttons reflect the selected position")
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
	# Embedded level tools edit the prepared position, with stroke-level undo.
	editor.template.select(0)
	editor.load_template()
	editor.select_step(0)
	var original_level_draft: Dictionary = editor.document.data.duplicate(true)
	editor.set_level_mode(true)
	expect(editor.editing_level and not editor.inspector.visible and editor.level_tools.visible,"Level mode replaces the inspector with topic-wide tools")
	editor.level_tools.group.select(0)
	editor.level_tools.populate_tools()
	editor.level_tools.tool.select(3) # Tree
	editor.begin_level_stroke()
	editor.paint_level(Vector2i(-2,0),false)
	editor.paint_level(Vector2i(-1,0),false)
	editor.end_level_stroke()
	expect(editor.level_document.cells[Vector2i(-2,0)].tree and editor.level_document.cells[Vector2i(-1,0)].tree,"A brush stroke paints several tiles")
	expect(editor.document.data.map != original_level_draft.map,"Painting updates the topic starting map as well as exercise positions")
	editor.undo()
	expect(editor.document.data == original_level_draft,"One undo restores the complete map brush stroke")
	editor.redo()
	expect(editor.level_document.cells[Vector2i(-2,0)].tree,"Redo restores painted cells in the active level tools")
	editor.level_tools.gold.value = 42
	editor.set_level_mode(false)
	editor.inspector.collect()
	expect(editor.document.data.steps[0].setup.gold == 42,"Editing step text preserves the exercise's opening gold")
	await editor.playtest(true)
	expect(editor.app.game.cells[Vector2i(-2,0)].tree,"Playtest uses the position painted in the tutorial editor")
	await editor.stop_playtest()
	editor.set_level_mode(true)
	var exercise_before: Dictionary = editor.document.data.steps[0].setup.duplicate(true)
	editor.level_tools.tool.select(1) # Water
	editor.begin_level_stroke()
	editor.paint_level(Vector2i(0,0),false)
	editor.end_level_stroke()
	expect(not editor.level_document.cells.has(Vector2i(0,0)) and editor.document.data.steps[0].setup != exercise_before,"Topic-level painting updates prepared positions too")
	editor.undo()
	editor.level_tools.tool.select(0) # Land
	editor.level_tools.owner_choice.select(1)
	editor.begin_level_stroke()
	editor.paint_level(Vector2i(5,0),false)
	editor.end_level_stroke()
	expect(editor.level_document.cells.has(Vector2i(5,0)) and editor.level_document.cells[Vector2i(5,0)].owner == 0,"Land brush adds new player-owned tiles")
	# Exercise pointer input, including interpolation and right-click erasing.
	var stroke_before: Dictionary = editor.document.data.duplicate(true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = editor.canvas.origin+editor.canvas.at(Vector2i(6,0))*editor.canvas.scale_value
	editor.canvas._gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = editor.canvas.origin+editor.canvas.at(Vector2i(8,0))*editor.canvas.scale_value
	editor.canvas._gui_input(drag)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	editor.canvas._gui_input(release)
	expect(editor.level_document.cells.has(Vector2i(6,0)) and editor.level_document.cells.has(Vector2i(7,0)) and editor.level_document.cells.has(Vector2i(8,0)),"Pointer dragging fills skipped hexes along the stroke")
	editor.undo()
	expect(editor.document.data == stroke_before,"A complete pointer drag is undone as one action")
	press.button_index = MOUSE_BUTTON_RIGHT
	press.position = editor.canvas.origin+editor.canvas.at(Vector2i(5,0))*editor.canvas.scale_value
	editor.canvas._gui_input(press)
	release.button_index = MOUSE_BUTTON_RIGHT
	editor.canvas._gui_input(release)
	expect(not editor.level_document.cells.has(Vector2i(5,0)),"Right-click erases using the active terrain brush")
	editor.undo()
	expect(editor.document.save_file("res://artifacts/editor-painted.tutorial.json") == "","Painted tutorials save as valid portable files")
	var painted = Doc.new()
	expect(painted.load_file("res://artifacts/editor-painted.tutorial.json") == "" and painted.data == JSON.parse_string(JSON.stringify(editor.document.data)),"Painted terrain and exercise positions survive save and reload")
	editor.level_tools.update_fields()
	editor.update_level_hint()
	await capture("level-tools")
	expect(surface.get_visible_rect().encloses(editor.level_tools.get_global_rect()),"Level tools fit the minimum editor window")
	editor.set_level_mode(false)
	await capture("simplified-workspace")
	await test_topic_level_edits(editor)
	await test_target_areas(editor)
	await test_tutorial_movement_highlights(editor)
	await test_reading_step(editor)
	await test_reading_substeps(editor)
	await test_text_action_lock(editor)
	editor.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(0.5).timeout
	print("Tutorial editor checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)

func test_target_areas(editor) -> void:
	var grid = preload("res://src/game/hex_grid.gd")
	expect(grid.boundary_edges({Vector2i.ZERO:true,Vector2i(3,0):true}).size() == 12,"Separated area patches keep both outlines")
	var ring := {}
	for direction in grid.DIRECTIONS: ring[direction] = true
	var ring_edges: Array = grid.boundary_edges(ring)
	var hole_edges := 0
	for edge in ring_edges:
		if edge[0]+grid.DIRECTIONS[edge[1]] == Vector2i.ZERO: hole_edges += 1
	expect(ring_edges.size() == 24 and hole_edges == 6,"Area outlines preserve holes without filling unselected hexes")
	editor.new_document()
	var area_level = editor.Level.new()
	area_level.read_data(editor.document.data.map)
	var rules = area_level.build_rules()
	var capital := Doc.NONE
	var border := Doc.NONE
	var outside := Doc.NONE
	for at in rules.cells:
		if rules.cells[at].capital == 0 and rules.can_recruit(at,0,1): capital = at; break
	for at in rules.cells:
		if at != capital and rules.Grid.distance(at,capital) == 1 and rules.can_recruit(at,0,1): border = at; break
	for at in rules.cells:
		if at not in [capital,border] and rules.can_recruit(at,0,1): outside = at; break
	expect(capital != Doc.NONE and border != Doc.NONE and outside != Doc.NONE,"Area fixture offers a capital, neighboring recruitment tile and legal outside tile")
	if Doc.NONE in [capital,border,outside]: return
	var step: Dictionary = editor.document.data.steps[0]
	step.kind = "recruit"
	step.target = [capital.x,capital.y]
	step.details = {"tier":1}
	step.restrict_actions = true
	editor.refresh(true)
	editor.inspector.fields.use_area.button_pressed = true
	expect(step.target == null and step.targets == [[capital.x,capital.y]],"Switching to area mode retains the original target")
	editor.start_area_pick()
	var before_area: Dictionary = editor.document.data.duplicate(true)
	editor.begin_level_stroke()
	editor.paint_level(border,false)
	editor.paint_level(border,false)
	editor.paint_level(outside,false)
	editor.paint_level(outside,true)
	editor.end_level_stroke()
	expect(step.targets.size() == 2 and editor.canvas.area_targets.has(border),"Area brush adds unique targets, removes hexes, and updates map highlighting")
	editor.cancel_pick()
	expect(not editor.canvas.edit_enabled and not editor.picking_area,"Finishing area selection restores normal map interaction")
	editor.undo()
	expect(editor.document.data == before_area,"Area brush undo restores the full selection stroke")
	editor.redo()
	step = editor.document.data.steps[0]
	expect(step.targets.size() == 2 and editor.inspector.fields.use_area.button_pressed,"Redo restores the selection and area controls")
	var runtime: Dictionary = editor.document.runtime_steps()[0]
	expect(Doc.target_matches(runtime,capital) and Doc.target_matches(runtime,border) and not Doc.target_matches(runtime,outside),"Area target membership accepts every selected hex and excludes others")
	expect(Doc.validate(editor.document.data) == "","Area targets are valid portable tutorial data")
	expect(editor.document.save_file("res://artifacts/editor-area.tutorial.json") == "","Area target tutorial saves")
	var loaded := Doc.new()
	expect(loaded.load_file("res://artifacts/editor-area.tutorial.json") == "" and loaded.runtime_steps()[0].targets == runtime.targets,"Area targets survive save, reload and runtime decoding")
	var simulation: Dictionary = Simulator.run(editor.document)
	expect(simulation.error.contains("manual playtest"),"Script checking identifies the choice boundary rather than choosing a target arbitrarily")
	var checkpoint: Dictionary = Simulator.run(editor.document,0)
	expect(checkpoint.error == "","Play selected step can start immediately before an area objective")
	editor.inspector.current_tab = 1
	editor.start_area_pick()
	await capture("area-selection")
	editor.cancel_pick()
	for target in [capital,border]:
		await editor.playtest(false)
		var game = editor.app.game
		expect(game.tutorial.permits("recruit",target,{"tier":1}) and not game.tutorial.permits("recruit",outside,{"tier":1}),"Recruit restrictions allow the selected capital and bordering tile while rejecting an outside legal tile")
		expect(not game.tutorial.permits("recruit",target,{"tier":3}),"An area keeps the required army rank restriction")
		var area_border = game.tutorial.marker_root.get_node("TutorialArea")
		expect(area_border.get_meta("targets").size() == 2 and area_border.get_meta("boundary_edges").size() == 10,"Adjacent targets share one area outline with no internal border")
		expect(game.tutorial.marker_root.get_child_count() == 3,"Area highlighting uses a shared border, backing and fill instead of per-tile rings")
		if target == capital: await capture("area-playtest")
		game.choose_unit(1)
		await game.click_hex(target)
		expect(game.tutorial.completed and game.cells[target].unit == 1,"Actual recruitment at either selected tile completes the area objective")
		await editor.stop_playtest()
	# Confirmation must remember the actual inspected tile in the area.
	step.kind = "inspect"
	step.details = {}
	step.confirm = true
	editor.refresh(true)
	await editor.playtest(false)
	var game = editor.app.game
	game.tutorial.observe("inspect",border)
	expect(game.tutorial.awaiting_confirmation and not game.tutorial.completed,"Area inspection waits for Continue")
	game.tutorial.continue_lesson()
	expect(game.tutorial.completed,"Continue acknowledges the actual inspected area tile")
	await editor.stop_playtest()
	editor.inspector.fields.use_area.button_pressed = false
	expect(not step.has("targets") and step.target == [capital.x,capital.y],"Switching back to a single hex retains the first area tile")

func test_tutorial_movement_highlights(editor) -> void:
	editor.new_document()
	var level = editor.Level.new()
	level.read_data(editor.document.data.map)
	var rules = level.build_rules()
	var source := Doc.NONE
	for at in rules.cells:
		if rules.unit_faction(at) == 0 and rules.cells[at].unit > 0 and not rules.cells[at].moved:
			source = at
			break
	expect(source != Doc.NONE,"Highlight fixture has a ready player army")
	if source == Doc.NONE: return
	var region: Dictionary = rules.reachable_targets(source)
	region[source] = true
	var step: Dictionary = editor.document.data.steps[0]
	step.kind = "move"
	step.target = null
	step.targets = Doc.encode(region.keys())
	step.details = {"source":[source.x,source.y]}
	step.restrict_actions = true
	editor.refresh(true)
	var preferences = root.get_node("Gameplay")
	var previous: bool = preferences.clear_indicators
	preferences.set_clear_indicators(true,false)
	await editor.playtest(false)
	var game = editor.app.game
	await game.click_hex(source)
	var tutorial_border: MeshInstance3D = game.tutorial.marker_root.get_node("TutorialArea")
	var movement_border: MeshInstance3D = game.view.overlay_root.get_node("ReachableArea")
	var gold_bounds := tutorial_border.mesh.get_aabb()
	var reach_bounds := movement_border.mesh.get_aabb()
	expect(tutorial_border.get_meta("boundary_edges") == movement_border.get_meta("boundary_edges"),"Fixture overlays tutorial and movement boundaries on identical edges")
	expect(gold_bounds.size.x > reach_bounds.size.x and gold_bounds.position.y < reach_bounds.position.y,"Thicker tutorial band sits beneath the usual movement outline, leaving both visible")
	expect(is_equal_approx(reach_bounds.position.y,0.09) and movement_border.material_override.albedo_color == Color("8ee1dc"),"Movement range keeps its normal height and cyan color")
	var movement_id := movement_border.get_instance_id()
	game.tutorial.marker_signature.clear()
	game.tutorial.refresh_marker()
	expect(game.view.overlay_root.get_node("ReachableArea").get_instance_id() == movement_id,"Refreshing tutorial highlighting preserves the movement overlay")
	await capture("area-movement-overlap")
	await editor.stop_playtest()
	preferences.set_clear_indicators(previous,false)

func test_reading_step(editor) -> void:
	editor.new_document()
	expect(editor.document.data.steps[0].kind == "read","New steps default to no condition / read and continue")
	var step: Dictionary = editor.document.data.steps[0]
	step.title = "Read before recruiting"
	step.text = "Take your time reading this explanation. Click Continue when you are ready."
	step.kind = "recruit"
	step.target = [-3,0]
	step.details = {"tier":2}
	step.conditions = [{"type":"round","value":999}]
	step.criteria = {"unit_before":0}
	step.count = 3
	step.restrict_actions = true
	step.allow_turns = true
	editor.refresh(true)
	editor.commit()
	var gated: Dictionary = editor.document.data.duplicate(true)
	editor.inspector.select_value("kind","read")
	editor.inspector.collect()
	expect(step.target == null and step.conditions.is_empty() and step.details.is_empty() and step.criteria.is_empty() and step.count == 1 and not step.restrict_actions and not step.allow_turns,"Selecting No condition removes old action and board requirements")
	expect(editor.inspector.fields.read_help.visible and editor.inspector.is_tab_disabled(2) and editor.inspector.is_tab_disabled(3),"Reading mode explains Continue and disables irrelevant condition/order tabs")
	editor.undo()
	expect(editor.document.data == gated,"Undo restores requirements removed by the reading preset")
	editor.redo()
	expect(editor.document.data.steps[0].kind == "read","Redo restores the reading preset")
	expect(Doc.validate(editor.document.data) == "" and Simulator.run(editor.document).error == "","Reading-only step validates without a board action")
	expect(editor.document.save_file("res://artifacts/editor-reading.tutorial.json") == "","Reading steps save normally")
	var loaded := Doc.new()
	expect(loaded.load_file("res://artifacts/editor-reading.tutorial.json") == "" and loaded.data.steps[0].kind == "read" and loaded.runtime_steps()[0].kind == "continue","Reading label survives save/reload and uses the existing manual Continue behavior")
	var invalid: Dictionary = editor.document.data.duplicate(true)
	invalid.steps[0].conditions = [{"type":"round","value":999}]
	expect(Doc.validate(invalid) != "","No-condition files cannot silently contain a board requirement")
	editor.inspector.current_tab = 1
	await capture("reading-goal")
	await editor.playtest(false)
	var game = editor.app.game
	var before: Dictionary = game.cells.duplicate(true)
	for frame in range(3): await process_frame
	expect(game.tutorial.continue_button.visible and not game.tutorial.continue_button.disabled and not game.tutorial.completed,"Reading step waits indefinitely with Continue available")
	game.tutorial.observe("select",Vector2i(-3,0))
	expect(not game.tutorial.completed,"Board interactions cannot complete the reading step")
	await capture("reading-playtest")
	game.tutorial.continue_button.pressed.emit()
	expect(game.tutorial.completed and game.cells == before,"Continue acknowledges the text without requiring a board change")
	await editor.stop_playtest()

func test_reading_substeps(editor) -> void:
	editor.new_document()
	editor.document.data.steps[0].title = "Briefing"
	editor.document.data.steps[0].text = "Main explanation"
	editor.document.data.steps[0].task = "Read the briefing"
	editor.refresh(true)
	var sub = editor.inspector.substeps_editor
	sub.add_page()
	sub.title_field.text = "First detail"
	sub.text_field.text = "First extra explanation"
	sub.collect()
	sub.add_page()
	sub.title_field.text = "Second detail"
	sub.text_field.text = "Second extra explanation"
	sub.collect()
	expect(editor.steps_list.item_count == 1 and editor.document.data.steps.size() == 1 and sub.pages().size() == 2,"Reading sub-steps stay nested and out of the main step list")
	sub.page_action(0)
	expect(sub.pages()[0].title == "Second detail","Sub-steps can be moved earlier")
	sub.page_action(1)
	expect(sub.pages()[0].title == "First detail","Sub-steps can be moved later")
	editor.commit()
	sub.page_action(2)
	expect(sub.pages().size() == 1,"Sub-steps can be removed independently")
	editor.undo()
	expect(sub.pages().size() == 2,"Undo restores a removed sub-step")
	editor.redo()
	expect(sub.pages().size() == 1,"Redo removes the sub-step again")
	editor.undo()
	sub.selector.select(2)
	sub.refresh_fields()
	sub.preview_changed.emit()
	expect(editor.preview.text.contains("Second extra explanation"),"The player prompt preview can show a selected sub-step")
	expect(Doc.validate(editor.document.data) == "" and Simulator.run(editor.document).error == "","Nested reading pages validate and need no simulated board actions")
	expect(editor.document.save_file("res://artifacts/editor-substeps.tutorial.json") == "","Tutorial with sub-steps saves")
	var loaded := Doc.new()
	expect(loaded.load_file("res://artifacts/editor-substeps.tutorial.json") == "" and loaded.runtime_steps().size() == 1 and loaded.runtime_steps()[0].substeps.size() == 2,"Save and runtime decoding preserve nested pages without adding steps")
	for value in ["invalid",[{}],[{"text":"ok","kind":"recruit"}],[{"text":"x".repeat(4001)}]]:
		var invalid: Dictionary = loaded.data.duplicate(true)
		invalid.steps[0].substeps = value
		expect(Doc.validate(invalid) != "","Malformed or actionable reading sub-step is rejected")
	editor.duplicate_step()
	editor.document.data.steps[1].substeps[0].text = "Edited copy"
	expect(editor.document.data.steps[0].substeps[0].text == "First extra explanation","Duplicated steps own independent copies of their reading pages")
	editor.document = loaded
	editor.step_index = 0
	editor.reset_history()
	editor.refresh(true)
	editor.inspector.current_tab = 0
	sub.get_parent().get_meta("toggle").button_pressed = true
	sub.selector.select(1)
	sub.refresh_fields()
	sub.preview_changed.emit()
	await capture("substeps-editor")
	await editor.playtest(false)
	var game = editor.app.game
	var tutor = game.tutorial
	var before: Dictionary = game.cells.duplicate(true)
	expect(tutor.reading_substeps() and tutor.explanation.text == "Main explanation" and tutor.panel.checks.size() == 1,"Main text begins the reading sequence with only one checklist objective")
	tutor.continue_lesson()
	expect(tutor.index == 0 and tutor.goal_count == 0 and tutor.heading.text == "First detail" and tutor.explanation.text == "First extra explanation","Continue shows the first sub-step without advancing the main step")
	await capture("substeps-playtest")
	tutor.continue_lesson()
	expect(not tutor.completed and tutor.explanation.text == "Second extra explanation","Each extra page waits for its own Continue click")
	tutor.restart_lesson()
	expect(tutor.text_page == 0 and tutor.reading_substeps() and tutor.explanation.text == "Main explanation","Retry returns to the first reading page")
	for page in range(3): tutor.continue_lesson()
	expect(tutor.completed and game.cells == before,"Final Continue finishes a reading-only parent without changing the board")
	await editor.stop_playtest()
	# Action goals become available only after all their reading pages.
	var step: Dictionary = editor.document.data.steps[0]
	step.kind = "recruit"
	step.target = [-3,0]
	step.details = {"tier":1}
	step.restrict_actions = true
	editor.refresh(true)
	await editor.playtest(false)
	game = editor.app.game
	tutor = game.tutorial
	expect(not tutor.permits("recruit",Vector2i(-3,0),{"tier":1}) and tutor.permits("inspect",Vector2i(-3,0)),"Reading pages pause goal actions while keeping map inspection available")
	tutor.observe("recruit",Vector2i(-3,0),{"tier":1})
	expect(not tutor.completed and tutor.goal_count == 0,"Board observations cannot skip the reading sequence")
	for page in range(3): tutor.continue_lesson()
	expect(not tutor.reading_substeps() and not tutor.completed and not tutor.continue_button.visible and tutor.permits("recruit",Vector2i(-3,0),{"tier":1}),"After reading, the parent action becomes available and still must be completed")
	game.choose_unit(1)
	await game.click_hex(Vector2i(-3,0))
	expect(tutor.completed,"The parent goal works normally after its reading sub-steps")
	await editor.stop_playtest()
	step.kind = "continue"
	step.target = null
	step.details = {}
	step.conditions = [{"type":"round","value":999}]
	editor.refresh(true)
	await editor.playtest(false)
	tutor = editor.app.game.tutorial
	await process_frame
	expect(not tutor.continue_button.disabled,"Unmet goal conditions do not block reading the extra text")
	for page in range(3): tutor.continue_lesson()
	await process_frame
	expect(not tutor.completed and not tutor.reading_substeps() and tutor.continue_button.disabled,"Finishing the text still respects the parent's board conditions")
	await editor.stop_playtest()

	# A parent's extra pages do not shift the main-step index or checklist count.
	step.kind = "read"
	step.conditions = []
	step.restrict_actions = false
	step.exercise = "briefing"
	var next_step := Doc.new_step()
	next_step.id = "after_briefing"
	next_step.title = "Next objective"
	next_step.exercise = "briefing"
	editor.document.data.steps.append(next_step)
	editor.refresh(true)
	await editor.playtest(false)
	tutor = editor.app.game.tutorial
	for page in range(3): tutor.continue_lesson()
	expect(tutor.index == 1 and tutor.text_page == 0 and tutor.current().get("substeps",[]).is_empty() and tutor.panel.checks.size() == 2,"Finishing nested text advances to the next parent with only parent checklist entries")
	await editor.stop_playtest()

func test_topic_level_edits(editor) -> void:
	editor.template.select(Lessons.IDS.find("economy"))
	editor.load_template()
	editor.set_level_mode(true)
	var prepared: Array = []
	for index in range(editor.document.data.steps.size()):
		if editor.document.data.steps[index].has("setup"): prepared.append(index)
	expect(prepared.size() >= 2,"Topic fixture contains distinct prepared exercises")
	if prepared.size() < 2: return
	var untouched: Array = []
	for index in prepared:
		var cells: Array = editor.document.data.steps[index].setup.cells
		untouched.append(cells.filter(func(cell): return cell.q != -2 or cell.r != 0).duplicate(true))
	editor.level_tools.group.select(0)
	editor.level_tools.populate_tools()
	editor.level_tools.tool.select(3) # Tree
	editor.begin_level_stroke()
	editor.paint_level(Vector2i(-2,0),false)
	editor.end_level_stroke()
	var all_painted := true
	var all_retained := true
	for slot in range(prepared.size()):
		var level = editor.Level.new()
		level.read_data(editor.document.data.steps[prepared[slot]].setup)
		all_painted = all_painted and level.cells[Vector2i(-2,0)].tree
		all_retained = all_retained and editor.document.data.steps[prepared[slot]].setup.cells.filter(func(cell): return cell.q != -2 or cell.r != 0) == untouched[slot]
	expect(all_painted,"One brush edit reaches every prepared exercise")
	expect(all_retained,"Topic-wide edits preserve untouched exercise-specific cells and objects")
	editor.undo()
	expect(editor.document.data.steps[prepared[0]].setup.cells.filter(func(cell): return cell.q == -2 and cell.r == 0)[0].tree == false,"One undo restores the edit throughout the topic")
	editor.redo()
	editor.select_step(prepared[1])
	expect(editor.level_document.cells[Vector2i(-2,0)].tree,"Switching to another exercise keeps the same edited topic level")
	# Reapplying a brush also repairs prepared positions when the base is already painted.
	for cell in editor.document.data.steps[prepared[1]].setup.cells:
		if cell.q == -2 and cell.r == 0: cell.tree = false
	editor.refresh(true)
	editor.begin_level_stroke()
	editor.paint_level(Vector2i(-2,0),false)
	editor.end_level_stroke()
	expect(editor.document.data.steps[prepared[1]].setup.cells.filter(func(cell): return cell.q == -2 and cell.r == 0)[0].tree,"A brush no-op on the base still updates differing prepared positions")
	editor.level_tools.gold.value = 22
	expect(editor.document.data.map.gold == 22 and prepared.all(func(index): return editor.document.data.steps[index].setup.gold == 22),"Level opening gold applies to the entire topic")
	editor.set_level_mode(false)
	editor.inspector.fields.gold.value = 33
	expect(editor.document.data.map.gold == 33 and prepared.all(func(index): return editor.document.data.steps[index].setup.gold == 33),"Course opening gold also updates every prepared position")
	expect(editor.document.save_file("res://artifacts/editor-topic-level.tutorial.json") == "","Topic-wide edits save normally")
	var loaded := Doc.new()
	expect(loaded.load_file("res://artifacts/editor-topic-level.tutorial.json") == "" and loaded.data == JSON.parse_string(JSON.stringify(editor.document.data)),"Reload preserves topic-wide edits and all exercise variants")
	await editor.playtest(true)
	expect(editor.app.game.cells[Vector2i(-2,0)].tree,"Starting a later exercise uses the topic-wide map edits")
	await editor.stop_playtest()

func test_text_action_lock(editor) -> void:
	# The normal read-only step must not let the player spend the Knight's move early.
	editor.new_document()
	var level = editor.Level.new()
	level.read_data(editor.document.data.map)
	var source := Vector2i.ZERO
	var target := Vector2i(-1,0)
	level.cells[source].unit = 3
	editor.document.data.map = level.state()
	editor.document.data.steps[0].text = "Read about the Knight's movement before moving it."
	editor.refresh(true)
	await editor.playtest(false)
	var game = editor.app.game
	var tutor = game.tutorial
	var before: Dictionary = game.cells.duplicate(true)
	await game.click_hex(source,"unit")
	await game.click_hex(target)
	expect(game.cells == before and not tutor.completed,"Actual Knight movement is blocked during a standalone reading step")
	expect(not tutor.permits("recruit",Vector2i(-3,0),{"tier":1}) and not tutor.permits("end_turn",game.NONE),"Purchases and End turn cannot bypass reading")
	expect(tutor.permits("inspect",target) and tutor.permits("stats",game.NONE),"Reading still permits inspection and information panels")
	tutor.continue_lesson()
	expect(tutor.completed,"Continue still finishes the read-only instruction")
	await editor.stop_playtest()
	# Action steps can independently require an acknowledgement without extra pages.
	var step: Dictionary = editor.document.data.steps[0]
	step.kind = "move"
	step.target = [target.x,target.y]
	step.details = {"source":[source.x,source.y]}
	step.restrict_actions = true
	editor.refresh(true)
	editor.inspector.fields.read_before_action.button_pressed = true
	expect(step.read_before_action and Doc.validate(editor.document.data) == "","The text acknowledgement option is editable on an action step")
	expect(editor.document.save_file("res://artifacts/editor-read-before-action.tutorial.json") == "","Text action lock saves")
	var loaded := Doc.new()
	expect(loaded.load_file("res://artifacts/editor-read-before-action.tutorial.json") == "" and loaded.runtime_steps()[0].read_before_action,"Text action lock survives save and reload")
	await editor.playtest(false)
	game = editor.app.game
	tutor = game.tutorial
	before = game.cells.duplicate(true)
	await game.click_hex(source,"unit")
	await game.click_hex(target)
	expect(game.cells == before and tutor.reading_substeps() and tutor.continue_button.visible,"Acknowledgement blocks the exact requested action even when it is otherwise legal")
	tutor.continue_lesson()
	expect(not tutor.reading_substeps() and not tutor.completed and not tutor.continue_button.visible,"Continue unlocks the goal without completing it")
	game.cancel_action()
	await game.click_hex(source,"unit")
	await game.click_hex(target)
	expect(tutor.completed and game.cells[target].unit == 3,"The Knight's move works normally once the text is acknowledged")
	await editor.stop_playtest()
	# Retry replays the acknowledgement instead of leaving the action unlocked.
	await editor.playtest(false)
	tutor = editor.app.game.tutorial
	tutor.continue_lesson()
	tutor.restart_lesson()
	expect(tutor.reading_substeps() and not tutor.permits("move",target,{"source":source}),"Retry restores the reading lock")
	await editor.stop_playtest()
