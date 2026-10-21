extends SceneTree
const Model = preload("res://src/ui/ledger_model.gd")
const Replay = preload("res://src/game/replay_log.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func run() -> void:
	root.size = Vector2i(1100,760)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.rules.rule_mode = "modern"
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	game.rules.faction_count = 2
	var a := Vector2i.ZERO
	var b := Vector2i(5,0)
	var c := Vector2i(0,5)
	for origin in [a,b,c]:
		for dx in range(3):
			game.rules.cells[origin+Vector2i(dx,0)] = game.rules.make_cell(1 if origin == b else 0)
	game.rules.rebuild_kingdoms()
	var own: Dictionary = game.rules.kingdom_at(a)
	var enemy: Dictionary = game.rules.kingdom_at(b)
	own.gold = 3
	enemy.gold = 40
	game.cells[a].unit = 3
	game.cells[b].unit = 1
	game.cells[c].unit = 2
	var recorder := Replay.new()
	game.rules.replay_log = recorder
	recorder.header = {"economy":Replay.economics(game.rules)}
	game.cells[a+Vector2i(1,0)].value = 3
	recorder.rows.append({"round":1,"economy":Replay.economics(game.rules)})
	game.cells[a+Vector2i(2,0)].value = 2
	recorder.rows.append({"round":2,"economy":Replay.economics(game.rules)})
	game.round_number = 3
	var before: Dictionary = preload("res://src/game/state_snapshot.gd").capture(game.rules)
	var ledger: Dictionary = Model.build(game.rules,3)
	for owner in range(2):
		var income := 0
		var costs := 0
		var gold := 0
		for bank in game.rules.kingdoms.values():
			if bank.owner == owner:
				income += game.rules.income(bank)
				costs += game.rules.upkeep(bank)
				gold += bank.gold
		var faction: Dictionary = ledger.factions[owner]
		expect(faction.income == income and faction.costs == costs and faction.gold == gold,"Faction finances aggregate all their territories")
		expect(faction.profit == income-costs,"Faction profit matches settlement")
		expect(faction.points.size() == 3 and faction.points[-1] == Vector2(3,income),"Each faction history includes completed rounds and a live point")
	expect(ledger.factions[0].hexes == 6 and ledger.factions[0].units == 2,"Faction table combines disconnected territories")
	expect(before == preload("res://src/game/state_snapshot.gd").capture(game.rules),"Ledger remains read-only")
	# Historical income follows the faction when its capitals change.
	recorder.rows.append({"round":2,"economy":[{"capital":Vector2i(99,99),"faction":0,"income":99}]})
	var history: Dictionary = Model.histories(recorder,3,2)
	expect(history[0].size() == 2 and history[0][-1].y == 99,"Faction history survives capital changes and uses one sample per round")
	expect(history[1][-1].y == 0,"Eliminated faction income becomes zero")
	recorder.rows.pop_back()
	game.active_hex = own.capital
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.toggle_stats()
	for frame in range(4): await process_frame
	expect(game.hud.stats_button.text == "" and game.hud.stats_button.icon != null,"Ledger launcher remains an icon at the top right")
	expect(game.hud.stats_rows.get_child_count() == 3,"One table row per faction plus neutral land")
	expect(game.stats_panel.find_children("IncomeGraph","",true,false).size() == 1,"Ledger has one combined graph")
	expect(game.hud.ledger_graph.series.size() == 2,"Combined graph contains every faction")
	expect(game.stats_panel.find_children("KingdomCard","",true,false).is_empty(),"Ledger does not list individual kingdoms")
	for row in game.hud.stats_rows.get_children():
		expect(row.get_child_count() == 8,"Table rows have aligned finance columns and navigation")
		var focus: Button = row.get_node("ViewCapital")
		expect(focus.text == "" and focus.icon != null,"Capital buttons use an icon")
		for column in range(1,7):
			expect(is_equal_approx(row.get_child(column).position.x,game.hud.ledger_table_header.get_child(column).position.x),"Table cells align with column headers")
	expect(root.get_visible_rect().encloses(game.stats_panel.get_global_rect()),"Ledger fits the window")
	var motion := InputEventMouseMotion.new()
	motion.position = game.hud.ledger_graph.point_position(Vector2(2,0))
	game.hud.ledger_graph._gui_input(motion)
	expect(game.hud.ledger_graph.hover_round == 2 and game.hud.ledger_graph._get_tooltip(Vector2.ZERO).contains(game.session.names[0]),"Graph hover compares faction incomes for the selected round")
	game.hud.ledger_graph.hover_round = -1
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/ledger-preview.png")
	var selected: Vector2i = game.active_hex
	var enemy_focus: Button = game.hud.stats_rows.get_child(1).get_node("ViewCapital")
	enemy_focus.pressed.emit()
	expect(game.active_hex == selected and not game.hud.stats_shade.visible,"Enemy capital navigation keeps the player's treasury selection")
	expect(game.view.focus == game.view.coord_position(enemy.capital),"Capital icon focuses the faction capital")
	game.toggle_stats()
	root.size = Vector2i(960,640)
	for frame in range(4): await process_frame
	expect(root.get_visible_rect().encloses(game.stats_panel.get_global_rect()),"Ledger fits a smaller window")
	for row in game.hud.stats_rows.get_children():
		expect(row.size.x <= game.hud.ledger_table_scroll.size.x,"Faction rows fit without horizontal scrolling")
	if "--preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/ledger-small-preview.png")
	game.rules.replay_log = null
	expect(Model.build(game.rules,3).factions[0].points.size() == 1,"Unrecorded games show available current data")
	var crossing := Vector2i(3,0)
	game.cells[crossing] = game.rules.make_cell()
	game.cells[crossing].building = "bridge"
	game.cells[crossing].unit = 1
	game.cells[crossing]["unit_owner"] = 0
	game.cells[crossing]["unit_home"] = own.capital
	var bridge_ledger: Dictionary = Model.build(game.rules,3)
	expect(bridge_ledger.factions[0].units == 3 and bridge_ledger.factions[0].tiers == [1,1,1],"Bridge garrisons count toward faction troops")
	var expected_costs := 0
	for bank in game.rules.kingdoms.values():
		if bank.owner == 0: expected_costs += game.rules.upkeep(bank)
	expect(bridge_ledger.factions[0].costs == expected_costs,"Bridge garrison wages match settlement rules")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Ledger checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
