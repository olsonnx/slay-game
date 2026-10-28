extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Sites = preload("res://src/game/event_sites.gd")
const Roads = preload("res://src/rendering/kingdom_roads.gd")
const Snapshot = preload("res://src/game/state_snapshot.gd")
const Replay = preload("res://src/game/replay_log.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func road_color_matches(actual: Color, expected: Color) -> bool:
	# Mesh vertex colours are stored as 8-bit channels.
	return maxf(absf(actual.r-expected.r),maxf(absf(actual.g-expected.g),absf(actual.b-expected.b))) <= 1.0/255.0 and actual.a == expected.a

func fixture():
	var r = Rules.new()
	r.rule_mode = "modern"
	r.faction_count = 2
	r.human_factions = [0,1]
	for q in range(8):
		r.cells[Vector2i(q,0)] = r.make_cell(0 if q < 4 else 1)
	r.cells[Vector2i.ZERO].capital = 0
	r.cells[Vector2i(7,0)].capital = 1
	r.cells[Vector2i.ZERO].mana_source = true
	r.cells[Vector2i(7,0)].mana_source = true
	r.rebuild_kingdoms()
	for bank in r.kingdoms.values(): bank.gold = 50
	return r
func run() -> void:
	landmark_bonus_checks()
	for id in ["comet","economist","stainless_steel","builders_guild","barracks","scout_lodge","watchtower"]:
		for choice in ([0,1] if id == "economist" else [0]):
			var model = fixture()
			var site := Vector2i(3,0)
			model.cells[site].unit = 3
			var event := {"id":id,"coord":site,"faction":0}
			model.pending_events.append(event)
			expect(model.resolve_event(event,choice) != "" and Sites.protected(model.cells[site]),"Permanent event choices construct landmarks")
			expect(model.effects_by_faction.is_empty(),"New permanent rewards are not stored on factions")
	var target := Vector2i(3,0)
	var source := Vector2i(4,0)
	for reward in [-1,1,5]:
		var r = fixture()
		Sites.create(r,target,"economist",reward)
		var original: int = r.magic.Encounters.income_adjustment(r,r.kingdom_at(target))
		expect(original == reward,"Signed income belongs to the site's local kingdom")
		r.cells[source].unit = 3
		r.replay_log = Replay.new()
		r.replay_log.start(r)
		expect(not r.perform_move(source,target).is_empty(),"Enemies can conquer a landmark")
		expect(Sites.protected(r.cells[target]) and r.cells[target].owner == 1,"Capturing keeps the landmark intact")
		expect(r.magic.Encounters.income_adjustment(r,r.kingdom_at(target)) == reward,"Conquest transfers positive and negative income")
		expect(r.magic.Encounters.income_adjustment(r,r.kingdom_at(Vector2i.ZERO)) == 0,"Former owner loses the site's income")
		var replay := Replay.read_records(r.replay_log.records)
		expect(replay.error == "" and replay.position.cells[target] == r.cells[target],"Replay preserves landmark identity and reward on capture")
		var snapshot := Snapshot.capture(r)
		var copy = Snapshot.simulation(r)
		expect(copy.income(copy.kingdom_at(target)) == r.income(r.kingdom_at(target)),"AI simulations preserve site income")
		r.cells[target].owner = -1
		r.rebuild_kingdoms()
		expect(Sites.faction_effects(r,1).get("income_bonus",0) == 0,"Neutral sites grant nobody an effect")
		Snapshot.restore(r,snapshot)
		expect(r.cells[target].site_income == reward,"Snapshots restore local rewards")
		r.cells[target].moved = false
		expect(r.can_move(target,source),"A garrison can leave a captured landmark")
		r.move_unit(target,source)
		r.cells[source].moved = false
		expect(r.can_move(source,target),"Friendly troops can return to a landmark")
	var r = fixture()
	Sites.create(r,target,"wolf",0,1)
	expect(r.mana_regeneration(0) == 2 and r.mana_regeneration(1) == 1,"Wolf landmark grants its owner mana regeneration")
	r.cells[source].unit = 3
	r.perform_move(source,target)
	expect(r.mana_regeneration(0) == 1 and r.mana_summary(1).regeneration == 2,"Mana regeneration transfers on capture")
	r = fixture()
	Sites.create(r,target,"stainless_steel",0,0,true)
	expect(r.unit_upkeep(3,0) == 27,"Steel landmark lowers its owner's knight upkeep")
	r.cells[source].unit = 3
	r.perform_move(source,target)
	expect(r.unit_upkeep(3,0) == 36 and r.unit_upkeep(3,1) == 27,"Steel benefit follows conquest")
	r.cells[target].owner = -1
	r.rebuild_kingdoms()
	r.set_mana(1,99)
	expect(not r.can_cast("shatter",target,1),"Shatter cannot destroy a neutral landmark")
	r = fixture()
	Sites.create(r,target,"comet",2)
	r.cells[Vector2i(2,0)].owner = 1
	r.rebuild_kingdoms()
	expect(Sites.protected(r.cells[target]) and r.magic.Encounters.income_adjustment(r,r.kingdom_at(Vector2i.ZERO)) == 0,"An isolated site does not pay another kingdom")
	# Even capital replacement in a component made only of monuments preserves them.
	for q in range(2):
		Sites.create(r,Vector2i(q,0),"comet",1)
		r.cells[Vector2i(q,0)].capital = -1
	r.rebuild_kingdoms()
	expect(Sites.protected(r.cells[Vector2i.ZERO]) and Sites.protected(r.cells[Vector2i(1,0)]),"Replacement capitals never erase landmarks")
	for kind in ["bear","wolf","boar"]:
		r = fixture()
		r.cells[target]["lair"] = kind
		var bank: Dictionary = r.kingdom_at(target)
		var gold: int = bank.gold
		r.Wildlife.destroy_lair(r,target,0,bank)
		expect(Sites.protected(r.cells[target]) and not r.cells[target].has("lair"),"Every cleared lair leaves a landmark")
		var after: int = bank.gold
		r.Wildlife.destroy_lair(r,target,0,bank)
		expect(bank.gold == after and (after == gold+20 if kind == "boar" else after == gold),"Immediate lair rewards cannot repeat")
		r.Wildlife.raid(r,target,"bear")
		expect(Sites.protected(r.cells[target]),"Wildlife raids cannot destroy landmarks")
	# Roads avoid foreign territory and mountains and ignore unit occupancy.
	r = fixture()
	r.cells[Vector2i(3,0)].building = "house"
	var edges: Dictionary = Roads.network(r.cells)
	expect(edges.size() == 3,"A building connects to the nearest capital by a shortest path")
	for pair in edges:
		expect(r.cells[pair[0]].kingdom == r.cells[pair[1]].kingdom and r.distance(pair[0],pair[1]) == 1,"Every road edge stays within its kingdom")
	r.cells[Vector2i(1,0)].unit = 3
	expect(Roads.network(r.cells) == edges,"Decorative roads ignore army occupancy")
	r.cells[Vector2i(1,0)].mountain = true
	expect(Roads.network(r.cells).is_empty(),"Roads do not cross impassable mountains")
	for coord in [Vector2i(0,1),Vector2i(1,1)]:
		r.cells[coord] = r.make_cell(0)
		r.cells[coord].kingdom = Vector2i.ZERO
	var detour: Dictionary = Roads.network(r.cells)
	expect(not detour.is_empty(),"Roads find a detour around mountains")
	for pair in detour:
		expect(not r.cells[pair[0]].get("mountain",false) and not r.cells[pair[1]].get("mountain",false),"Detour edges avoid the mountain")
	var tiles := {}
	var container := Node3D.new()
	root.add_child(container)
	for coord in r.cells:
		var tile := Node3D.new()
		container.add_child(tile)
		tiles[coord] = tile
	var mock := {"cells":r.cells,"tile_nodes":tiles,"COLORS":r.Catalog.TERRAIN_COLORS.duplicate()}
	var renderer = Roads.new()
	renderer.sync(mock)
	var paint: MeshInstance3D = tiles[Vector2i.ZERO].get_node("RoadPaint")
	expect(paint.material_override.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL and not paint.material_override.disable_receive_shadows,"Roads use lighting and receive shadows")
	for color in paint.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		expect(road_color_matches(color,mock.COLORS[0].darkened(Roads.DARKENING)),"Roads use a darker version of the owning kingdom's terrain colour")
	for normal in paint.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]:
		expect(normal.dot(Vector3.UP) > 0.9999,"Flat roads have upward normals for correct lighting")
	for point in paint.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		expect(is_equal_approx(point.y,0.014),"Road paint is flat against the terrain surface")
	r.cells[Vector2i.ZERO].unit = 1
	renderer.sync(mock)
	expect(tiles[Vector2i.ZERO].get_node("RoadPaint") == paint,"Unit movement preserves existing road geometry")
	mock.COLORS[0] = Color("d79879")
	renderer.sync(mock)
	paint = tiles[Vector2i.ZERO].get_node("RoadPaint")
	for color in paint.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		expect(road_color_matches(color,mock.COLORS[0].darkened(Roads.DARKENING)),"Roads refresh when a custom kingdom palette changes")
	container.queue_free()
	await process_frame
	var board = load("res://src/rendering/board_view.gd").new()
	root.add_child(board)
	r = fixture()
	Sites.create(r,target,"comet",2)
	var layout = load("res://src/rendering/tile_layout.gd")
	for tier in [1,2,3]:
		r.cells[target].unit = tier
		board.render_cells(r.cells)
		var actor: Node3D = board.unit_actors[target]
		var landmark: Node3D = board.tile_nodes[target].get_node("Features/Landmark")
		expect(actor.position == layout.unit_offset(r.cells[target]),"Every garrison rank stands beside its landmark")
		expect(landmark.position == layout.LANDMARK_STRUCTURE_OFFSET,"Occupied landmarks make room for their garrison")
		expect(actor.position.distance_to(landmark.position) > 0.8,"Garrison and landmark have distinct ground positions")
	r.cells[target].unit = 0
	board.render_cells(r.cells)
	expect(board.tile_nodes[target].get_node("Features/Landmark").position == Vector3.ZERO,"Unoccupied landmarks return to the tile center")
	expect(not board.unit_actors.has(target),"Vacating a landmark removes its garrison")
	board.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Event site checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)

func landmark_bonus_checks() -> void:
	var r = fixture()
	var site := Vector2i(3, 0)
	for q in range(1, 6): r.cells[Vector2i(q, 0)].value = 2
	Sites.create(r, site, "builders_guild", 0, 0, false, {"development_discount":true})
	expect(r.development_cost(site) == 4 and r.development_cost(Vector2i(2, 0)) == 4, "Guild halves development cost on its province and friendly neighbors")
	expect(r.development_cost(Vector2i(1, 0)) == 8 and r.development_cost(Vector2i(4, 0)) == 8, "Guild discounts neither distant provinces nor enemy neighbors")
	var gold: int = r.kingdom_at(site).gold
	expect(r.develop(site, 0) and r.kingdom_at(site).gold == gold - 4 and r.cells[site].value == 3 and r.development_cost(site) == 9, "Development charges the discounted cost and recalculates after upgrading")
	Sites.create(r, Vector2i(2, 0), "builders_guild", 0, 0, false, {"development_discount":true})
	expect(r.development_cost(site) == 9, "Overlapping guild discounts do not stack")
	r.cells[site].owner = 1
	r.cells[Vector2i(2, 0)].owner = 1
	r.rebuild_kingdoms()
	expect(r.development_cost(Vector2i(1, 0)) == 8 and r.development_cost(Vector2i(4, 0)) == 4, "Guild discounts follow current ownership")
	r = fixture()
	var bonuses := {"soldier_discount":true, "scout_discount":true}
	for coord in [site, Vector2i(2, 0)]: Sites.create(r, coord, "combined_fixture", 0, 0, true, bonuses)
	expect(r.unit_upkeep(1, 0) == 2 and r.unit_upkeep(2, 0) == 6 and r.unit_upkeep(3, 0) == 27, "Wage reductions are Scout 50%, Soldier 50%, Knight 25% without stacking")
	expect(r.unit_upkeep(1, 1) == 4 and r.unit_upkeep(2, 1) == 12 and r.unit_upkeep(3, 1) == 36, "Wage landmarks affect only their owner")
	var simulation = Snapshot.simulation(r)
	expect(simulation.unit_upkeep(2, 0) == 6 and simulation.unit_upkeep(3, 0) == 27, "Simulation snapshots preserve new wage properties")
	r.cells[Vector2i(4, 0)].unit = 3
	expect(not r.perform_move(Vector2i(4, 0), site).is_empty(), "New property landmarks remain conquerable")
	expect(r.unit_upkeep(2, 1) == 6 and r.unit_upkeep(2, 0) == 6, "Each owner benefits from its own surviving wage landmark")
	r.cells[Vector2i(2, 0)].owner = 1
	r.rebuild_kingdoms()
	expect(r.unit_upkeep(2, 0) == 12 and r.unit_upkeep(1, 0) == 4 and r.unit_upkeep(3, 0) == 36, "Losing the last landmark removes all its wage benefits")
	r = fixture()
	Sites.create(r, Vector2i(2, 0), "watchtower", 0, 0, false, {"defense_aura":true})
	r.cells[site].unit = 2
	expect(r.defense(site) == 3 and r.defense(Vector2i(2, 0)) == 3, "Watchtower strengthens its own province and adjacent friendly units")
	expect(r.defense(Vector2i(1, 0)) == 1, "Empty neighboring provinces gain no defense aura")
	r.cells[site].unit = 3
	r.cells[Vector2i(4, 0)].unit = 3
	expect(r.defense(site) == 4 and not r.can_move(Vector2i(4, 0), site), "A protected Knight cannot be bypassed through an equal-rank duel")
	Sites.create(r, site, "watchtower", 0, 0, false, {"defense_aura":true})
	expect(r.defense(site) == 4, "Overlapping watchtowers and their own garrisons receive just one defense bonus")
	r.cells[Vector2i(1, 0)].unit = 2
	expect(r.defense(Vector2i(1, 0)) == 3 and r.defense(Vector2i.ZERO) == 2, "Boosted unit defense does not radiate to a second ring")
	r.cells[site].owner = 1
	r.cells[Vector2i(2, 0)].owner = 1
	r.rebuild_kingdoms()
	expect(r.defense(Vector2i(1, 0)) == 2 and r.defense(Vector2i(4, 0)) == 4, "Watchtower protection transfers on capture without helping former owners")
	r = fixture()
	Sites.create(r, Vector2i(2, 0), "watchtower", 0, 0, false, {"defense_aura":true})
	var bridge := Vector2i(2, 1)
	r.cells[bridge] = r.make_cell(-1)
	r.cells[bridge].building = "bridge"
	r.cells[bridge].unit = 2
	r.cells[bridge].unit_owner = 0
	expect(r.defense(bridge) == 3, "Adjacent friendly bridge garrisons receive the unit defense bonus")
	r.cells[bridge].unit_owner = 1
	expect(r.defense(bridge) == 2, "An enemy bridge garrison receives no aura from the other faction")
	r.cells[bridge].unit = 0
	expect(r.defense(bridge) == 0, "An empty neutral bridge receives no aura")
