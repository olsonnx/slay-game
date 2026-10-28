extends SceneTree
const Schema = preload("res://src/game/authored_event_schema.gd")
const Runtime = preload("res://src/game/authored_event_runtime.gd")
const Catalog = preload("res://src/game/event_catalog.gd")
const Templates = preload("res://src/event_editor/event_templates.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
const Replay = preload("res://src/game/replay_log.gd")
var checks := 0
var failures := 0
var editor
const COORD := Vector2i(2,0)

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func install(data: Dictionary) -> void:
	Catalog.EVENTS[data.id] = Catalog.public_definition(data)
	Catalog.WEIGHTS[data.id] = int(data.weight)

func ready_event(state, data: Dictionary) -> Dictionary:
	state.cells[COORD].event = data.id
	expect(state.magic.trigger_event(state,COORD,0),"Authored encounter triggers through the real game")
	return state.pending_events[0] if not state.pending_events.is_empty() else {}

func run() -> void:
	pack_size_checks()
	editor = load("res://src/event_editor/event_editor.gd").new()
	root.add_child(editor)
	var original_events := Catalog.EVENTS.duplicate(true)
	var original_weights := Catalog.WEIGHTS.duplicate()
	for id in Catalog.BUILTIN_EVENTS:
		var data := Templates.template(id)
		expect(Schema.validate(data).is_empty(),"Every built-in event has a valid editable template: "+id)
		data.id = "authored_"+id
		install(data)
		editor.data = data
		var state = editor.sandbox()
		var event := ready_event(state,data)
		if event.is_empty(): continue
		var random_state: int = state.rng.state
		var definition: Dictionary = state.magic.event_definition(state,event)
		expect(definition.title == data.title and definition.choices.size() == data.choices.size(),"Authored dialog uses the edited story and choices: "+id)
		state.magic.event_definition(state,event)
		expect(state.rng.state == random_state,"Repeated event reveal does not reroll outcomes or gold: "+id)
		var choices: Array = Runtime.story(data,event).choices
		for index in range(choices.size()):
			for result in range(choices[index].outcomes.size()):
				var copy = editor.sandbox()
				var attempt := {"id":data.id,"coord":COORD,"faction":0}
				Runtime.prepare(copy,data,attempt)
				expect(Runtime.choice_allowed(copy,data,attempt,index),"Template choice is executable in a suitable sandbox: %s/%d" % [id,index])
				expect(Runtime.resolve(copy,data,attempt,index,result) != "","Every weighted template outcome executes: %s/%d/%d" % [id,index,result])
				var snapshot := Snapshots.capture(copy)
				var simulation = Snapshots.simulation(copy)
				expect(simulation.cells == copy.cells,"Simulation retains authored outcome state: "+id)
				Snapshots.restore(copy,snapshot)
				expect(copy.cells == snapshot.cells,"Snapshots preserve authored events: "+id)
	# Costs are validated before any state or RNG mutation.
	var data := Templates.template("economist")
	data.id = "authored_cost"
	install(data)
	editor.data = data
	var state = editor.sandbox()
	state.kingdom_at(COORD).gold = 9
	var event := ready_event(state,data)
	var before := Snapshots.capture(state)
	expect(state.resolve_event(event,1) == "","Unaffordable authored choices are rejected")
	expect(Snapshots.capture(state) == before,"Rejected choices preserve money, pending event, RNG and board")
	state.kingdom_at(COORD).gold = 30
	state.replay_log = Replay.new()
	state.replay_log.start(state)
	expect(state.resolve_event(event,1) != "" and state.cells[COORD].building == "monument","Authored permanent rewards construct a landmark")
	expect(state.kingdom_at(COORD).gold == 20,"Choice cost is charged exactly once")
	var replay := Replay.read_records(state.replay_log.records)
	expect(replay.error == "" and replay.position.cells[COORD] == state.cells[COORD],"Replay reconstructs authored landmarks")
	state.cells[COORD].owner = 1
	state.rebuild_kingdoms()
	expect(state.cells[COORD].site_income == 1 and state.cells[COORD].owner == 1,"Authored landmark rewards survive conquest")
	# Variants are selected once; previews do not alter the original template.
	editor.data = Templates.template("lumberjack")
	editor.context.trees = 24
	state = editor.sandbox()
	event = {"id":"sandbox","coord":COORD,"faction":0}
	Runtime.prepare(state,editor.data,event)
	expect(event.variant == 0,"Overgrown forest chooses the conditional story")
	var gold: int = state.kingdom_at(COORD).gold
	expect(Runtime.resolve(state,editor.data,event,0) != "" and state.kingdom_at(COORD).gold == gold,"Adaptive tree clearance withholds payment in overgrown kingdoms")
	editor.context.trees = 4
	# Weighted outcomes remain seeded, repeatable and approximately proportional.
	data = Schema.fresh("authored_random")
	data.choices[0].outcomes = [Templates.outcome("one",[Templates.effect("gold",{"min":1,"max":1})],70),Templates.outcome("two",[Templates.effect("gold",{"min":2,"max":2})],30)]
	editor.data = data
	var counts := {"one":0,"two":0}
	for seed in range(300):
		editor.context.seed = seed
		state = editor.sandbox()
		event = {"id":data.id,"coord":COORD,"faction":0}
		var result := Runtime.resolve(state,data,event,0)
		counts[result] += 1
		var second = editor.sandbox()
		expect(Runtime.resolve(second,data,event,0) == result,"Seeded outcomes reproduce exactly")
	expect(counts.one > 170 and counts.one < 250 and counts.two > 50,"Weighted results retain a 70/30 distribution")
	# All-unusable events are excluded, avoiding a permanently blocked encounter.
	data.choices[0].cost_gold = 99999
	install(data)
	expect(not state.magic.Encounters.main_outcome_available(state,data.id,COORD,0),"Events with no affordable choice are ineligible")
	expect(state.magic.Encounters.weighted_event(state,COORD,0,{data.id:100,"gold":1}) == "gold","Ineligible custom events fall back to a useful encounter")
	# Multi-action outcomes cannot overspend or recruit into a nonexistent slot.
	data = Schema.fresh("authored_atomic")
	data.choices[0].outcomes[0].effects = [Templates.effect("gold_percent"),Templates.effect("gold",{"min":-1,"max":-1})]
	expect(not Runtime.choice_allowed(state,data,event,0),"A percent drain followed by a payment cannot overspend")
	data.choices[0].outcomes[0].effects = [Templates.effect("gold",{"min":10,"max":10}),Templates.effect("gold",{"min":-5,"max":-5})]
	state.kingdom_at(COORD).gold = 0
	expect(Runtime.choice_allowed(state,data,event,0),"Sequential grants can fund subsequent effects")
	# Every supported condition has an explicit expected result in a known position.
	editor.context.seed = 42
	editor.context.mana = 0
	editor.data = Schema.fresh("condition_fixture")
	state = editor.sandbox()
	event = {"id":"condition_fixture","coord":COORD,"faction":0}
	var expected_conditions := {"kingdom":true,"recruit_space":true,"forest":true,"multiple_units":true,"knights":true,"other_faction":true,"rebel_slot":true,"no_stainless_steel":true,"income_trade":true,"duel_reward":true,"gold_at_least":true,"income_at_least":true,"mana_at_least":false,"mana_space":true,"unit_tier_at_least":true,"unit_tier_at_most":false,"forest_overgrown":false,"has_effect":false,"no_effect":true,"mana_source":false}
	for kind in Schema.CONDITIONS:
		expect(expected_conditions.has(kind),"Every condition has semantic coverage")
		expect(Runtime.conditions(state,event,[Templates.requirement(kind)]) == expected_conditions[kind],"Condition checks actual state: "+kind)
		expect(Runtime.conditions(state,event,[Templates.requirement(kind,1,true)]) != expected_conditions[kind],"Condition inversion works: "+kind)
	# Exercise every effect, including effects not used by the existing templates.
	for kind in Schema.ACTIONS:
		data = Schema.fresh("matrix_"+kind)
		data.choices[0].outcomes[0].effects = [Schema.action(kind)]
		editor.data = data
		state = editor.sandbox()
		event = {"id":data.id,"coord":COORD,"faction":0}
		expect(Schema.validate(data).is_empty(),"Every effect has a valid default form: "+kind)
		expect(Runtime.resolve(state,data,event,0) != "","Every supported effect runs: "+kind)
		match kind:
			"building": expect(state.cells[COORD].building == "city","Ordinary building effects construct the selected type")
			"tile_value": expect(state.cells[COORD].value == int(editor.context.income)+1,"Province development changes the actual value")
			"temporary_effect": expect(state.has_effect(0,"free_spell"),"Temporary effects reach spell rules")
			"landmark": expect(state.cells[COORD].site_income == 1,"Landmark settings reach authoritative cell data")
			"gold_percent": expect(state.kingdom_at(COORD).gold == 0,"A -100 percent payment empties the treasury")
	# Costs in mana and AI preferences use the same choice validation as humans.
	data = Schema.fresh("authored_mana_cost")
	data.choices[0].cost_mana = 2
	data.choices[0].outcomes[0].effects = [Templates.effect("mana")]
	editor.data = data
	editor.context.mana = 3
	state = editor.sandbox()
	event = {"id":data.id,"coord":COORD,"faction":0}
	expect(Runtime.resolve(state,data,event,0) != "" and state.get_mana(0) == 2,"Mana cost is paid once before the reward")
	data.choices.append(Schema.choice())
	data.choices[1].ai_score = 10
	data.choices[1].outcomes[0].effects = [Templates.effect("temporary_effect",{"effect":"trailblaze"})]
	install(data)
	state = editor.sandbox()
	state.human_factions = [1]
	state.cells[COORD].event = data.id
	expect(state.magic.trigger_event(state,COORD,0) and state.pending_events.is_empty() and state.has_effect(0,"trailblaze"),"AI resolves authored choices using the authored preference")
	editor.context.mana = 0
	# Clearing forests can open a recruitment site for the next ordered effect.
	data = Schema.fresh("clear_then_recruit")
	data.choices[0].outcomes[0].effects = [Templates.effect("clear_trees"),Templates.effect("recruit")]
	editor.data = data
	state = editor.sandbox()
	for cell in state.cells.values():
		if cell.owner == 0 and cell.unit == 0: cell.tree = true
	event = {"id":data.id,"coord":COORD,"faction":0}
	var position_before := Snapshots.capture(state)
	expect(Runtime.choice_allowed(state,data,event,0),"Forest clearance can open space for a following recruit")
	expect(Snapshots.capture(state) == position_before,"Ordered-effect validation changes neither the board nor RNG")
	expect(Runtime.resolve(state,data,event,0) != "","Ordered clearance and recruitment both execute")
	# Validation rejects invalid imports instead of partially installing them.
	for bad in [{},null,[],{"id":"INVALID"}]: expect(not Schema.validate(bad).is_empty(),"Malformed top-level data is rejected")
	for bad in ["effect",{"kind":"execute_script"},{"kind":"gold","min":"oops","max":2}]:
		var invalid := Schema.fresh()
		invalid.choices[0].outcomes[0].effects = [bad]
		expect(not Schema.validate(invalid).is_empty(),"Unknown or malformed effects are rejected")
	data = Templates.template("comet")
	data.id = "imported_comet"
	var path := "res://artifacts/test-authored-event-pack.json"
	expect(Schema.save_pack(path,[data]) == "","Event packs save successfully")
	expect(Schema.save_pack(path,[data]) == "" and FileAccess.file_exists(path+".bak"),"Replacing a pack preserves a backup")
	var loaded := Schema.load_pack(path)
	expect(loaded.error == "" and loaded.events[0] == data,"Export/import round-trips all event features")
	var original_pack := FileAccess.get_file_as_string(path)
	var invalid := data.duplicate(true)
	invalid.id = "invalid id"
	expect(Schema.save_pack(path,[invalid]) != "" and FileAccess.get_file_as_string(path) == original_pack,"Invalid saves leave existing event files untouched")
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	image.save_png("res://artifacts/unimported-event-art.png")
	expect(Catalog.painting_texture("res://artifacts/unimported-event-art.png").get_width() == 2,"New artwork previews before a Godot asset import")
	# Form edits, undo and import use the same schema, without saving to the game.
	editor.select_event("economist")
	editor.change(editor.data,"title","Edited title")
	expect(editor.dirty(),"Form edits mark the document dirty")
	editor.undo()
	expect(editor.data.title != "Edited title","Undo restores the previous document")
	editor.redo()
	expect(editor.data.title == "Edited title","Redo restores the edited document")
	editor.saved = editor.data.duplicate(true)
	editor.file_action = "import"
	editor.file_selected(ProjectSettings.globalize_path(path))
	expect(editor.data.id == "imported_comet" and editor.dirty(),"Import opens an uninstalled draft")
	editor.open_test()
	editor.test_all_outcomes()
	expect(editor.test_log.text.contains("CHOICE:"),"The sandbox can execute every eligible outcome")
	editor.test_window.hide()
	# Long authored dialogs retain every choice inside a bounded scrolling panel.
	data = Schema.fresh("long_story")
	data.text = "The army discovers a long account of the kingdom's history. ".repeat(100)
	data.choices = []
	for i in range(4):
		var choice := Schema.choice()
		choice.label = "Choice %d" % i
		data.choices.append(choice)
	editor.data = data
	state = editor.sandbox()
	event = {"id":data.id,"coord":COORD,"faction":0}
	editor.preview_dialog.present(Runtime.definition(state,data,event),func(_choice): pass)
	await process_frame
	expect(editor.preview_dialog.panel.get_child(0) is ScrollContainer,"Long four-choice events use a scrolling dialog")
	expect(editor.preview_dialog.panel.panel_height <= editor.get_viewport_rect().size.y-64,"Long event dialog stays within the window")
	editor.preview_dialog.close_dialog()
	Catalog.EVENTS.assign(original_events)
	Catalog.WEIGHTS.assign(original_weights)
	editor.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Event editor checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)

func pack_size_checks() -> void:
	var path := "res://artifacts/test-event-pack-size.json"
	var data := Schema.fresh("size_boundary")
	var empty_size := JSON.stringify({"version":Schema.VERSION,"events":[data]},"\t").to_utf8_buffer().size()
	data.choices[0].hint = "x".repeat(Schema.MAX_PACK_BYTES - empty_size)
	expect(Schema.save_pack(path,[data]) == "" and FileAccess.get_file_as_bytes(path).size() == Schema.MAX_PACK_BYTES and Schema.load_pack(path).error == "", "A pack at the exact byte limit saves and reloads")
	# Establish a backup and prove an oversized replacement touches neither file.
	expect(Schema.save_pack(path,[Schema.fresh("small_pack")]) == "", "A smaller valid pack replaces the boundary fixture")
	var previous := FileAccess.get_file_as_bytes(path)
	var backup := FileAccess.get_file_as_bytes(path+".bak")
	data.choices[0].hint = "é".repeat(Schema.MAX_PACK_BYTES / 2 + 1)
	expect(Schema.validate(data).is_empty() and Schema.save_pack(path,[data]) != "", "Oversize checking counts UTF-8 bytes, including valid multibyte text")
	expect(FileAccess.get_file_as_bytes(path) == previous and FileAccess.get_file_as_bytes(path+".bak") == backup and Schema.load_pack(path).error == "", "Rejected saves preserve the installed pack and its recovery copy")
