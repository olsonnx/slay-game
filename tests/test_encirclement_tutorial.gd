extends SceneTree
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Chapter = preload("res://src/game/encirclement_tutorial.gd")
const Doc = preload("res://src/tutorial_editor/tutorial_document.gd")
const Simulator = preload("res://src/tutorial_editor/tutorial_simulator.gd")
const Conditions = preload("res://src/tutorial_editor/tutorial_conditions.gd")
var checks := 0
var failures := 0
var surface: Viewport
var preview := false
var game

func _initialize() -> void:
	preview = "--preview" in OS.get_cmdline_user_args()
	if preview: root.hide()
	call_deferred("run")

func expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(text)

func capture(name: String) -> void:
	if not preview: return
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	surface.get_texture().get_image().save_png("res://artifacts/encirclement-"+name+".png")

func acknowledge_text() -> void:
	var index: int = game.tutorial.index
	var clicks := 0
	while game.tutorial.index == index and game.tutorial.reading_substeps() and clicks < 8:
		game.tutorial.continue_lesson()
		clicks += 1
		await process_frame

func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	root.get_node("Sound").set_muted(true,false)
	expect(Lessons.IDS[1] == "encirclement" and "conquest" not in Lessons.IDS,"The distinct cut-off topic follows Armies without restoring the removed conquest lesson")
	var doc := Doc.new()
	doc.data = {"format":"slay-tutorial","version":1,"title":"Cutting off armies","category":"encirclement","map":Chapter.map_data(),"steps":Chapter.authored_steps(),"opponent_mode":"scripted","require_victory":false}
	expect(Doc.validate(doc.data) == "","The chapter is valid portable tutorial data")
	var simulated: Dictionary = Simulator.run(doc)
	expect(simulated.error == "","The entire authored path passes the normal rules simulator: " + simulated.error)
	# A larger detached pocket can support the same Knight on its own income.
	var pocket_level = Chapter.Level.new()
	pocket_level.read_data(Chapter.map_data())
	for at in [Chapter.ENEMY,Vector2i(1,-1),Vector2i.ZERO,Vector2i(0,-1),Vector2i(-1,0),Vector2i(-1,-1)]:
		pocket_level.cells[at].owner = 1
		pocket_level.cells[at].value = 6
	var pocket_rules = pocket_level.build_rules()
	pocket_rules.perform_move(Chapter.SOURCE,Chapter.CONNECTION)
	expect(not pocket_rules.unit_kingdom(Chapter.ENEMY).is_empty(),"A larger detached pocket forms a real kingdom rather than counting as unsupported")
	pocket_rules.begin_turn(1)
	expect(pocket_rules.cells[Chapter.ENEMY].unit == 3,"A sufficiently productive detached pocket can pay the Knight's normal upkeep")
	var round_trip := Doc.new()
	expect(doc.save_file("res://artifacts/encirclement-roundtrip.json") == "" and round_trip.load_file("res://artifacts/encirclement-roundtrip.json") == "" and round_trip.data.steps.size() == 6,"Six main objectives and their reading pages survive saving")
	for path in ["res://tutorials/encirclement.json","res://tutorials/encirclement.tutorial.json"]:
		var saved := Doc.new()
		expect(saved.load_file(path) == "" and saved.data.steps == JSON.parse_string(JSON.stringify(doc.data.steps)),"Installed/editable chapter matches the authored text and actions")
	for kind in ["isolated","no_unit"]:
		var invalid: Dictionary = doc.data.duplicate(true)
		invalid.steps[0].kind = "continue"
		invalid.steps[0].conditions = [{"type":kind,"target":null}]
		expect(Doc.validate(invalid) != "","Army state predicates require a real tile")
	surface = root
	if preview:
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280,800)
		viewport.own_world_3d = true
		viewport.gui_embed_subwindows = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		surface = viewport
	game = load("res://scenes/main.tscn").instantiate()
	game.initial_level_data = doc.level_data()
	game.initial_level_data.tutorial_playtest = true
	surface.add_child(game)
	game.tutorial = load("res://src/game/tutorial.gd").new(game)
	game.add_child(game.tutorial)
	game.playback_speed.speed_held = true
	await process_frame
	var tutor = game.tutorial
	var enemy_bank: Dictionary = game.rules.unit_kingdom(Chapter.ENEMY)
	expect(not enemy_bank.is_empty() and enemy_bank.capital == Chapter.CAPITAL and enemy_bank.gold == 100,"The enemy Knight begins connected to a funded capital")
	expect(not Conditions.check(game.rules,1,{"type":"isolated","target":Chapter.ENEMY,"faction":1}),"The Knight is not considered isolated before the cut")
	expect(not tutor.permits("move",Chapter.CONNECTION,{"source":Chapter.SOURCE}),"The opening explanation blocks actions until read")
	await capture("opening")
	await acknowledge_text()
	expect(tutor.current().id == "inspect_knight" and tutor.panel.checks.size() == 6,"Reading pages are hidden from the six-objective checklist")
	await game.click_hex(Chapter.ENEMY,"terrain")
	expect(tutor.awaiting_confirmation,"Inspecting the enemy waits for a reading acknowledgement")
	tutor.continue_lesson()
	expect(tutor.current().id == "cut_connection" and tutor.reading_substeps(),"The cut objective requires its instructions to be acknowledged")
	await acknowledge_text()
	expect(not tutor.permits("move",Chapter.ENEMY,{"source":Chapter.SOURCE}),"A direct Knight duel cannot substitute for cutting the land connection")
	game.cancel_action()
	await game.click_hex(Chapter.SOURCE,"unit")
	await capture("cut-preview")
	await game.click_hex(Chapter.CONNECTION)
	expect(tutor.current().id == "isolated" and game.cells[Chapter.CONNECTION].owner == 0,"The real capture severs the only connection and advances the objective")
	expect(game.cells[Chapter.ENEMY].unit == 3 and game.rules.unit_kingdom(Chapter.ENEMY).is_empty(),"The unsupported Knight stays alive immediately after the capture")
	expect(Conditions.check(game.rules,1,{"type":"isolated","target":Chapter.ENEMY,"faction":1}),"Isolation predicate checks actual treasury connectivity")
	expect(not Conditions.check(game.rules,1,{"type":"isolated","target":Chapter.ENEMY,"faction":0}),"Isolation predicate cannot confuse friendly and enemy units")
	expect(game.rules.kingdom_at(Chapter.CAPITAL).gold == 100,"The lesson does not bankrupt or delete the enemy treasury to fake isolation")
	await capture("isolated")
	await acknowledge_text()
	expect(tutor.current().id == "wait_for_isolation" and not tutor.permits("end_turn",game.NONE),"The next instruction must be read before ending the turn")
	await acknowledge_text()
	await game.end_turn()
	expect(game.cells[Chapter.ENEMY].unit == 0 and game.cells[Chapter.ENEMY].grave,"The enemy's real turn removes its unsupported Knight and leaves a grave")
	expect(game.cells[Chapter.CONNECTION].unit == 3 and game.rules.has_capital(1),"The player's Knight survives and the enemy kingdom remains")
	expect(tutor.current().id == "positioning" and Conditions.check(game.rules,game.round_number,{"type":"no_unit","target":Chapter.ENEMY}),"The final explanation follows a verified empty army tile")
	await capture("result")
	await acknowledge_text()
	expect(tutor.completed,"Acknowledging the conclusion completes the topic")
	tutor.restart_lesson()
	expect(tutor.index == 0 and tutor.reading_substeps() and game.cells[Chapter.ENEMY].unit == 3 and not game.rules.unit_kingdom(Chapter.ENEMY).is_empty(),"Retry restores the shared board, supported Knight, and opening reading pages")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	print("Encirclement tutorial checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
