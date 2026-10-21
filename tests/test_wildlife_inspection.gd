extends SceneTree
const Wildlife = preload("res://src/game/wildlife.gd")
const Encounters = preload("res://src/game/encounter_rules.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
var checks := 0
var failures := 0
var game
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func capture(path: String) -> void:
	if "--preview" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
func run() -> void:
	root.size = Vector2i(1200,800)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.view.birds.set_loading(true)
	var s = game.rules
	s.rule_mode = "modern"
	s.cells.clear()
	for q in range(-5,6):
		for r in range(-5,6):
			var coord := Vector2i(q,r)
			if s.distance(coord,Vector2i.ZERO) <= 5: s.cells[coord] = s.make_cell()
	for coord in [Vector2i(-4,0),Vector2i(-3,0),Vector2i(-3,1)]: s.cells[coord].owner = 0
	for coord in [Vector2i(4,0),Vector2i(4,-1),Vector2i(3,0)]: s.cells[coord].owner = 1
	s.cells[Vector2i(-4,0)].capital = 0
	s.cells[Vector2i(4,0)].capital = 1
	s.cells[Vector2i(-3,0)].building = "tower"
	s.cells[Vector2i(-1,0)]["lair"] = "bear"
	s.cells[Vector2i.ZERO]["animal"] = "bear"
	s.cells[Vector2i.ZERO]["animal_home"] = Vector2i(-1,0)
	s.cells[Vector2i.ZERO]["animal_target"] = Vector2i(3,0)
	s.rebuild_kingdoms()
	game.view.render_cells(s.cells)
	game.view.stop_camera_pan()
	game.view.focus = Vector3.ZERO
	game.view.zoom = 11.0
	game.view.update_camera()
	for frame in range(3): await process_frame
	for item in [[Vector2i(-3,0),"defense",Color("edbd75")],[Vector2i(-1,0),"roaming",Color("c19af0")],[Vector2i.ZERO,"vision",Color("71dce8")]]:
		await game.click_hex(item[0],"terrain")
		var border = game.view.overlay_root.get_node_or_null("InspectionRange")
		expect(border != null,"Clicking a structure or animal displays its range")
		if border == null: continue
		expect(border.get_meta("kind") == item[1] and border.material_override.albedo_color == item[2],"Range uses the correct category and color")
		var region: Array = border.get_meta("region")
		var radius: int = 1 if item[1] == "defense" else 2 if item[1] == "roaming" else 3
		for coord in s.cells:
			var expected: bool = s.distance(coord,item[0]) <= radius and (item[1] != "defense" or s.cells[coord].owner == 0)
			expect(region.has(coord) == expected,"Range perimeter matches the game's radius and tower ownership rules")
		expect(game.view.overlay_root.has_node("AnimalTarget") == (item[1] == "vision"),"Only animal inspection displays chased prey")
		await capture("res://artifacts/inspection-%s.png" % item[1])
	var target = game.view.overlay_root.get_node("AnimalTarget")
	expect(target.material_override.albedo_color == Color("ef5350"),"Current prey is highlighted in red")
	s.cells[Vector2i.ZERO].erase("animal_target")
	game.view.render_cells(s.cells)
	game.refresh_overlays()
	expect(not game.view.overlay_root.has_node("AnimalTarget"),"Losing prey clears its inspection highlight")
	game.close_province()
	game.refresh_overlays()
	expect(not game.view.overlay_root.has_node("InspectionRange"),"Closing inspection removes ranges")
	s.rule_mode = "classic"
	await game.click_hex(Vector2i(-3,0),"terrain")
	expect(game.view.overlay_root.has_node("InspectionRange"),"Classic towers also show their defensive coverage")
	await game.click_hex(Vector2i(-3,1),"terrain")
	expect(not game.view.overlay_root.has_node("InspectionRange"),"Inspecting ordinary Classic land clears tower coverage")
	s.rule_mode = "modern"
	var bank: Dictionary = s.kingdom_at(Vector2i(-4,0))
	Encounters.change_income(s,0,bank,2,"comet")
	Encounters.change_income(s,0,bank,1,"economist")
	for coord in [Vector2i(-1,0),Vector2i(1,0)]:
		s.cells[coord]["lair"] = "bear"
		Wildlife.destroy_lair(s,coord,0,bank)
	s.cells[Vector2i(2,0)]["lair"] = "wolf"
	Wildlife.destroy_lair(s,Vector2i(2,0),0,bank)
	var saved := Snapshots.capture(s)
	var effects = preload("res://src/ui/status_effects.gd").new()
	root.add_child(effects)
	effects.refresh(s,0)
	if "--preview" in OS.get_cmdline_user_args():
		var layer := CanvasLayer.new()
		root.add_child(layer)
		for index in range(2):
			var tip := PanelContainer.new()
			tip.theme = preload("res://src/ui/ui_theme.gd").create_theme()
			tip.add_theme_stylebox_override("panel",preload("res://src/ui/ui_theme.gd").style(Color("17252a"),8,true))
			layer.add_child(tip)
			tip.position = Vector2(450+index*330,260)
			var text: String = effects.icons.income_bonus.tooltip_text if index == 0 else effects.icons.wildlife_mana_regen.tooltip_text
			tip.add_child(preload("res://src/ui/compact_tooltip.gd").create(text))
		for frame in range(2): await process_frame
		await capture("res://artifacts/recurring-bonus-tooltips.png")
		layer.queue_free()
	var income: String = effects.icons.income_bonus.tooltip_text
	expect(income.contains("Comet sighted!") and income.contains("Bear cave ×2: +10") and income.contains("Comet sighted!: +2") and income.contains(Encounters.Events.EVENTS.economist.title),"Income status lists grouped event and lair source names")
	expect(not income.contains("treasury") and income.begins_with("Gold per turn\n"),"Income status omits implementation explanations")
	expect(effects.icons.wildlife_mana_regen.tooltip_text == "Mana per turn\nWolf den: +1","Mana status lists its source and signed amount")
	Encounters.change_income(s,0,bank,-2,"economist")
	effects.refresh(s,0)
	expect(effects.icons.income_bonus.tooltip_text.contains(Encounters.Events.EVENTS.economist.title+" ×2: -1"),"Repeated sources show their actual signed net contribution")
	var legacy: String = effects.source_breakdown({"income_sources":{"bear":2,"comet":1}},"income",12,"Gold per turn")
	expect(legacy.contains("Bear cave ×2: +10") and legacy.contains("Comet sighted!: +2"),"Older positions retain accurate contribution totals")
	saved = Snapshots.capture(s)
	s.effects_by_faction.clear()
	Snapshots.restore(s,saved)
	expect(s.effects_by_faction[0].income_sources.bear == 2 and s.effects_by_faction[0].mana_sources.wolf == 1 and s.effects_by_faction[0].income_source_amounts.economist == -1 and s.effects_by_faction[0].mana_source_amounts.wolf == 1,"Snapshots preserve reward provenance")
	effects.queue_free()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Wildlife inspection checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
