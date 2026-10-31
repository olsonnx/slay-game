extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Logistics = preload("res://src/game/logistics.gd")
const Queries = preload("res://src/game/ai_queries.gd")
const Snapshot = preload("res://src/game/state_snapshot.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Document = preload("res://src/editor/level_document.gd")
const Actions = preload("res://src/tutorial_editor/tutorial_actions.gd")
var checks := 0
var failures := 0
class Host:
	extends RefCounted
	var local_id := 7
	func is_host() -> bool: return true
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture():
	var state = Rules.new()
	state.faction_count = 2
	state.human_factions = [0, 1]
	for q in range(12): state.cells[Vector2i(q, 0)] = state.make_cell(0)
	state.cells[Vector2i.ZERO].capital = 0
	state.cells[Vector2i(12, 0)] = state.make_cell(1)
	state.cells[Vector2i(13, 0)] = state.make_cell(1)
	state.cells[Vector2i(13, 0)].capital = 1
	state.rebuild_kingdoms()
	for bank in state.kingdoms.values(): bank.gold = 500
	return state

func movement_checks() -> void:
	for tier in [1, 2, 3]:
		var state = fixture()
		state.cells[Vector2i.ZERO].unit = tier
		var range_limit: int = Rules.Catalog.MOVEMENT[tier]
		expect(state.can_move(Vector2i.ZERO, Vector2i(range_limit, 0)), "Each rank reaches its ordinary range")
		expect(not state.can_move(Vector2i.ZERO, Vector2i(range_limit + 1, 0)), "Each rank stops at its ordinary range")
		for coord in state.cells:
			if state.cells[coord].owner == 0: state.cells[coord].road = true
		expect(state.can_move(Vector2i.ZERO, Vector2i(range_limit * 2, 0)), "A continuous friendly road doubles travel range")
		expect(not state.can_move(Vector2i.ZERO, Vector2i(range_limit * 2 + 1, 0)), "Roads still obey a finite budget")
		state.cells[Vector2i(1, 0)].erase("road")
		expect(not state.can_move(Vector2i.ZERO, Vector2i(range_limit * 2, 0)), "Missing a road tile charges full entry and exit costs")
	var state = fixture()
	state.cells[Vector2i.ZERO].unit = 3
	state.cells[Vector2i(2, 0)].owner = -1
	state.rebuild_kingdoms()
	expect(state.can_move(Vector2i.ZERO, Vector2i(2, 0)) and not state.can_move(Vector2i.ZERO, Vector2i(3, 0)), "Capturing ends movement and cannot pass through neutral land")
	state = fixture()
	state.cells[Vector2i(6, 0)].unit = 3
	for q in range(6, 12): state.cells[Vector2i(q, 0)].road = true
	state.cells[Vector2i(12, 0)].road = true
	expect(not state.can_move(Vector2i(6, 0), Vector2i(12, 0)), "Capturing enemy road costs a full point")
	state.cells[Vector2i(11, 0)].unit = 3
	expect(not state.can_move(Vector2i(6, 0), Vector2i(11, 0)), "Knights cannot merge beyond the maximum tier")
	# A longer paved route is cheaper than the direct unpaved route.
	state = fixture()
	state.cells[Vector2i.ZERO].unit = 3
	for coord in [Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 0)]:
		if not state.cells.has(coord): state.cells[coord] = state.make_cell(0)
		state.cells[coord].road = true
	state.rebuild_kingdoms()
	var path: Array = state.movement_path(Vector2i.ZERO, Vector2i(3, 0))
	expect(path.size() == 5 and Vector2i(1, 1) in path, "Weighted pathfinding chooses the cheaper road detour")
	expect(state.can_move(Vector2i.ZERO, Vector2i(4, 0)) and not state.can_move(Vector2i.ZERO, Vector2i(5, 0)), "Half movement is charged exactly without rounding each step")
	state.cells[Vector2i(1, 1)].mountain = true
	expect(not state.can_move(Vector2i.ZERO, Vector2i(4, 0)), "Road flags cannot bypass impassable mountains")
	state = fixture()
	state.cells[Vector2i.ZERO].unit = 1
	state.cells[Vector2i(1, 0)].building = "bridge"
	state.cells[Vector2i(1, 0)].owner = -1
	state.cells[Vector2i(1, 0)].road = true
	expect(Logistics.step_cost(state, Vector2i.ZERO, Vector2i(1, 0), 0) == 2, "Bridges never receive a road discount")

func road_checks() -> void:
	var state = fixture()
	var home := Vector2i.ZERO
	var city := Vector2i(4, 0)
	var tower := Vector2i(8, 0)
	state.cells[city].building = "city"
	state.cells[tower].building = "tower"
	var gold: int = state.kingdom_at(home).gold
	expect(state.road_targets(home, 0)[city].cost == 5, "A new connection quotes every newly paved tile including both structures")
	expect(not state.build_structure(Vector2i(1, 0), 0, "road"), "Road tiles cannot be purchased through ordinary construction")
	expect(not state.build_road(home, Vector2i(2, 0), 0) and not state.build_road(Vector2i(1, 0), city, 0), "Both endpoints must be structures")
	expect(not state.build_road(home, Vector2i(13, 0), 0), "Roads cannot terminate at an enemy structure")
	expect(state.build_road(home, city, 0) and state.kingdom_at(home).gold == gold - 5, "Road construction charges the full route once")
	for q in range(4):
		expect(Logistics.step_cost(state, Vector2i(q, 0), Vector2i(q + 1, 0), 0) == 1, "Every connected road segment provides half-cost movement")
	expect(state.road_targets(home, 0)[tower].cost == 4, "Extending a route reuses its paved section for free")
	state.kingdom_at(home).gold = 3
	var before: Dictionary = state.cells.duplicate(true)
	expect(not state.build_road(home, tower, 0) and state.cells == before and state.kingdom_at(home).gold == 3, "An unaffordable connection makes no partial changes")
	state.kingdom_at(home).gold = 100
	expect(state.build_road(home, tower, 0) and state.kingdom_at(home).gold == 96, "Only four new tiles are charged for an extension")
	var roads = load("res://src/rendering/kingdom_roads.gd")
	expect(roads.network(state.cells).size() == 8, "The clean road drawing follows only the purchased segments")
	var side := Vector2i(3, 1)
	state.cells[side] = state.make_cell(0)
	state.cells[side].road = true
	state.cells[side].road_links = []
	expect(roads.network(state.cells).size() == 8 and Logistics.step_cost(state, side, Vector2i(3, 0), 0) == 2, "Adjacent paved routes do not grow unwanted branches")
	state.cells[Vector2i(2, 0)].owner = 1
	expect(Logistics.step_cost(state, Vector2i(1, 0), Vector2i(2, 0), 0) == 2, "Capturing a road province interrupts the friendly speed bonus")
	expect(state.road_targets(home, 0).is_empty(), "Road planning cannot cross enemy territory")
	state = fixture()
	state.cells[city].building = "city"
	state.cells[Vector2i(1, 0)].building = "bridge"
	state.cells[Vector2i(1, 0)].owner = -1
	state.rebuild_kingdoms()
	expect(state.road_targets(home, 0)[city].cost == 4 and state.build_road(home, city, 0), "A road can cross an existing bridge without charging to pave its deck")
	expect(Logistics.step_cost(state, home, Vector2i(1, 0), 0) == 2, "A connected bridge still uses normal movement")
	state = fixture()
	state.cells[city].building = "city"
	state.cells[tower].building = "tower"
	state.build_road(home, city, 0)
	var junction := Vector2i(2, 0)
	expect(state.road_targets(tower, 0).has(junction), "An existing road tile is a destination without a structure")
	expect(not state.road_targets(junction, 0).has(tower), "Road construction still starts from a structure")
	gold = state.kingdom_at(tower).gold
	expect(state.build_road(tower, junction, 0) and state.kingdom_at(tower).gold == gold - 4, "Connecting to a road tile charges only newly paved land")
	state.cells[junction].owner = 1
	expect(not state.build_road(tower, junction, 0), "Enemy road tiles are not friendly connection targets")

func merge_checks() -> void:
	for tier in [1, 2]:
		var state = fixture()
		var source := Vector2i(5, 0)
		var target := Vector2i(6, 0)
		state.cells[source].unit = tier
		state.cells[target].unit = tier
		expect(state.can_move(source, target), "Equal ranks can merge in the field away from recruitment hubs")
		expect(state.move_unit(source, target) and state.cells[target].unit == tier + 1 and state.cells[source].unit == 0, "Merging consumes two equal ranks and creates the next rank")
		expect(not state.cells[target].moved, "Merging into a ready unit preserves the target action")
		state = fixture()
		state.cells[source].unit = tier
		state.cells[target].unit = tier
		state.cells[target].moved = true
		expect(state.move_unit(source, target) and state.cells[target].moved, "Merging cannot restore a spent target action")
		state = fixture()
		state.cells[source].unit = tier
		state.cells[target].unit = tier
		state.cells[source].moved = true
		expect(not state.can_move(source, target), "Spent units cannot initiate a merge")
		state.cells[source].moved = false
		state.cells[target].unit = 3 - tier
		expect(not state.can_move(source, target), "Different ranks cannot merge")
	var state = fixture()
	state.cells[Vector2i.ZERO].unit = 2
	state.cells[Vector2i(5, 0)].unit = 2
	expect(not state.can_move(Vector2i.ZERO, Vector2i(5, 0)), "Merging obeys ordinary movement range")
	for q in range(6): state.cells[Vector2i(q, 0)].road = true
	expect(state.move_unit(Vector2i.ZERO, Vector2i(5, 0)), "Connected roads extend merge range at half movement cost")

func settlement_checks() -> void:
	var state = fixture()
	var home := Vector2i.ZERO
	var city := Vector2i(4, 0)
	state.cells[city].building = "city"
	var gold: int = state.kingdom_at(home).gold
	expect(state.rename_settlement(home, 0, "  Crown's Reach  ") and state.cells[home].settlement_name == "Crown's Reach", "Capitals accept trimmed custom names")
	expect(state.rename_settlement(city, 0, "Łódź") and state.cells[city].settlement_name == "Łódź", "Cities accept Unicode names")
	expect(state.kingdom_at(home).gold == gold, "Renaming is free")
	expect(not state.rename_settlement(city, 1, "Stolen") and not state.rename_settlement(Vector2i(2, 0), 0, "Field"), "Only the owner can rename cities and capitals")
	expect(not state.rename_settlement(home, 0, "x".repeat(41)) and not state.rename_settlement(home, 0, "Bad\nName"), "Names reject excessive length and control characters")
	var restored = Snapshot.simulation(state)
	expect(restored.cells[city].settlement_name == "Łódź", "Settlement names survive state snapshots")
	var document = Document.new()
	document.cells = state.cells.duplicate(true)
	document.player_start = home
	var data: Dictionary = document.state()
	var copy = Document.new()
	expect(copy.read_data(data) == "" and copy.cells[city].settlement_name == "Łódź", "Settlement names round trip through level documents")
	var replay = Replay.new()
	replay.start(state, {"seed":1})
	state.replay_log = replay
	state.rename_settlement(city, 0, "New Harbour")
	var recorded: Dictionary = Replay.read_records(replay.records)
	expect(replay.rows[-1].action == "rename_settlement" and recorded.position.cells[city].settlement_name == "New Harbour", "Renaming records a replay state change")
	expect(state.rename_settlement(city, 0, " ") and not state.cells[city].has("settlement_name"), "An empty name restores the default label")
	state.replay_log = null

func tree_growth_checks() -> void:
	var occupied := [
		{"building":"city"}, {"building":"tower"}, {"building":"bridge"},
		{"building":"monument"}, {"capital":0}, {"unit":1},
		{"treasure":15}, {"road":true}, {"mana_source":true}, {"event":"comet"},
		{"mountain":true}, {"barrier_by":1}, {"animal":"wolf"}, {"lair":"wolf"}]
	for attributes in occupied:
		var state = Rules.new()
		state.cells[Vector2i.ZERO] = state.make_cell(0)
		state.cells[Vector2i.ZERO].tree = true
		var target := Vector2i(1, 0)
		state.cells[target] = state.make_cell(0)
		state.cells[target].merge(attributes, true)
		expect(not state.can_grow_tree(target), "Occupied tiles reject new trees: " + str(attributes))
		for round_index in range(100): state.spread_trees()
		expect(not state.cells[target].tree, "Forest spread preserves occupied tiles: " + str(attributes))
		state.cells[target].grave = true
		state.begin_turn(0)
		expect(not state.cells[target].tree, "Aging graves cannot create trees over objects: " + str(attributes))
	var state = Rules.new()
	state.cells[Vector2i.ZERO] = state.make_cell(0)
	state.cells[Vector2i(1, 0)] = state.make_cell(0)
	state.cells[Vector2i.ZERO].tree = true
	for round_index in range(100): state.spread_trees()
	expect(state.cells[Vector2i(1, 0)].tree, "Trees still spread onto genuinely empty ground")
	state.cells[Vector2i(1, 0)].tree = false
	state.cells[Vector2i(1, 0)].grave = true
	state.begin_turn(0)
	expect(state.cells[Vector2i(1, 0)].tree and not state.cells[Vector2i(1, 0)].grave, "Graves on empty ground still become trees")

func infrastructure_ai_checks() -> void:
	var candidates = preload("res://src/game/ai_candidates.gd")
	for algorithm in ["legacy", "strategic"]:
		var state = fixture()
		state.ai_algorithm = algorithm
		state.prepare_ai_turn(0)
		var cities := []
		for coord in state.cells:
			if state.cells[coord].building == "city": cities.append(coord)
		expect(not cities.is_empty(), "Both AI backends build a forward city for a distant front")
		for coord in cities: expect(coord.x >= 10, "The forward city is close to the front rather than the rear")
		state = fixture()
		state.ai_algorithm = algorithm
		state.kingdom_at(Vector2i.ZERO).gold = 0
		state.prepare_ai_turn(0)
		expect(state.kingdom_at(Vector2i.ZERO).gold == 12, "The AI saves income toward a needed city instead of spending it all")
	var state = fixture()
	state.cells[Vector2i(10, 0)].building = "city"
	var options: Array = candidates.preparation(state, 0)
	var roads: Array = options.filter(func(action): return action.kind == "road")
	expect(not roads.is_empty(), "A rear hub can propose a road to a forward recruitment city")
	for road in roads:
		expect(road.source == Vector2i.ZERO and road.coord == Vector2i(10, 0), "AI roads connect recruitment hubs toward the front")
	state.build_road(Vector2i.ZERO, Vector2i(10, 0), 0)
	options = candidates.preparation(state, 0)
	expect(options.filter(func(action): return action.kind == "road").is_empty(), "A completed supply connection generates no redundant roads to pavement")
	state.cells[Vector2i(10, 0)].building = "tower"
	options = candidates.preparation(state, 0)
	expect(options.filter(func(action): return action.kind == "road").is_empty(), "Unneeded tower and road endpoints do not cause road spam")

func construction_checks() -> void:
	var state = fixture()
	var home := Vector2i.ZERO
	var city := Vector2i(4, 0)
	expect(not state.can_recruit(city, 0, 1), "Clear land is not a recruitment hub")
	var before: int = state.kingdom_at(home).gold
	expect(state.build_structure(city, 0, "city") and state.kingdom_at(home).gold == before - 25, "Cities cost 25 gold")
	var income: int = state.income(state.kingdom_at(home))
	expect(income == 12 and state.can_recruit(city, 0, 1), "Cities add recruitment without passive income")
	expect(state.recruit(city, 0, 1) and not state.cells[city].moved and not state.reachable_targets(city).is_empty(), "City recruits can move immediately")
	expect(state.recruit(home, 0, 1) and not state.cells[home].moved, "Capital recruits can move immediately")
	state.begin_turn(0)
	expect(not state.cells[city].moved and not state.reachable_targets(city).is_empty(), "Recruits ready at their owner's next turn")
	state.cells[city].moved = true
	expect(state.recruit(city, 0, 2) and state.cells[city].moved, "An upgrade cannot restore an action already spent")
	state.cells[Vector2i(3, 0)].unit = 1
	expect(state.can_recruit(Vector2i(3, 0), 0, 2), "Owned neighbors of cities permit recruitment and upgrades")
	expect(not state.can_recruit(Vector2i(2, 0), 0, 1), "Recruitment cannot extend two steps from a hub")
	expect(state.recruit(Vector2i(1, 0), 0, 1) and not state.cells[Vector2i(1, 0)].moved, "Recruits beside a capital can move immediately")
	state.cells[home].unit = 0
	state.cells[home].mana_source = true
	state.mana_by_faction[0] = 2
	expect(not state.can_cast("summon", Vector2i(6, 0), 0), "Summon cannot bypass recruitment locations")
	expect(state.cast_spell("summon", home, 0) and not state.cells[home].moved, "Summon produces a ready recruit")
	state.cells[home].unit = 0
	expect(Logistics.recruitment_zone(state, state.magic.Encounters.recruit_site(state, state.kingdom_at(home)), 0), "Event recruits choose a hub")
	state = fixture()
	state.cells[Vector2i(11, 0)].unit = 2
	state.cells[Vector2i(12, 0)].building = "city"
	expect(not state.perform_move(Vector2i(11, 0), Vector2i(12, 0)).is_empty() and state.cells[Vector2i(12, 0)].building == "city", "Captured cities survive and transfer recruitment rights")
	state.cells[Vector2i(12, 0)].unit = 0
	expect(state.can_recruit(Vector2i(12, 0), 0, 1), "New owners can use their captured city")

func dismantle_rejected(state, coord: Vector2i, faction: int) -> bool:
	var before: Dictionary = Snapshot.capture(state)
	var result: Dictionary = Actions.apply(state,{"kind":"dismantle","target":coord},faction)
	return not result.ok and Snapshot.capture(state) == before

func economy_checks() -> void:
	var state = fixture()
	var home := Vector2i.ZERO
	expect(state.tower_cost(0) == 15 and state.build_structure(Vector2i(2, 0), 0, "tower"), "First tower costs 15")
	expect(state.tower_cost(0) == 20 and state.tower_cost(1) == 15, "Tower prices rise for the owner only")
	expect(state.build_structure(Vector2i(3, 0), 0, "tower") and state.tower_cost(0) == 25, "Every controlled tower adds five to construction cost")
	expect(state.upkeep(state.kingdom_at(home)) == 4, "Tower upkeep remains two per tower")
	var bridge := Vector2i(0, 1)
	expect(state.build_structure(bridge, 0, "bridge", home), "A bridge can be built beside the selected kingdom")
	expect(state.cells[bridge].bridge_owner == 0 and state.cells[bridge].owner == -1 and state.upkeep(state.kingdom_at(home)) == 6, "Neutral bridge retains sponsorship and bills its builder")
	expect(Queries.new(state).bank_summary(state.kingdom_at(home)).upkeep == 6, "AI includes infrastructure in its budget")
	var visible = load("res://src/game/visible_economy.gd").project(state, state.cells, state.kingdoms, state.mana_by_faction, 0, home)
	expect(visible.upkeep(visible.kingdom_at(home)) == 6, "Displayed finances include infrastructure")
	var gold: int = state.kingdom_at(home).gold
	state.begin_turn(0)
	expect(state.kingdom_at(home).gold == gold + state.income(state.kingdom_at(home)) - 6, "Turn settlement charges infrastructure exactly once")
	expect(dismantle_rejected(state,Vector2i(2, 0),0) and state.tower_cost(0) == 25 and state.upkeep(state.kingdom_at(home)) == 6, "Towers are a permanent upkeep and construction-price commitment")
	expect(dismantle_rejected(state,bridge,1), "Another faction cannot dismantle the builder's bridge")
	state.cells[bridge].unit = 1
	state.cells[bridge].unit_owner = 0
	expect(dismantle_rejected(state,bridge,0), "Occupied bridges cannot be dismantled under a unit")
	state.cells[bridge].unit = 0
	expect(dismantle_rejected(state,bridge,0) and state.cells.has(bridge), "Even the sponsor cannot dismantle an empty bridge through an authored command")
	state.cells[home].mana_source = true
	state.mana_by_faction[0] = 2
	var before_shatter: int = state.kingdom_at(home).gold
	expect(state.cast_spell("shatter",bridge,0) and not state.cells.has(bridge) and state.get_mana(0) == 0 and state.kingdom_at(home).gold == before_shatter and state.upkeep(state.kingdom_at(home)) == 4, "Shatter spends mana, removes the bridge and upkeep, and gives no construction refund")
	gold = state.kingdom_at(home).gold
	expect(state.build_road(home, Vector2i(3, 0), 0) and state.kingdom_at(home).gold == gold - 4, "A structure connection costs one gold for each newly paved tile")
	expect(not state.build_road(home, Vector2i(3, 0), 0), "An already connected route cannot be purchased twice")
	var before_road: Dictionary = state.cells.duplicate(true)
	expect(dismantle_rejected(state,home,0) and state.cells == before_road, "Road removal is rejected without changing the network")
	state = fixture()
	state.build_structure(bridge, 0, "bridge", home)
	state.relocate_capital(Vector2i(2, 0), 0)
	expect(Logistics.bridge_bank(state, state.cells[bridge]).capital == Vector2i(2, 0), "Bridge bills follow capital relocation")
	var copy = Snapshot.simulation(state)
	expect(copy.upkeep(copy.kingdom_at(Vector2i(2, 0))) == 2, "Snapshots retain infrastructure sponsorship")

func replay_editor_checks() -> void:
	var state = fixture()
	state.cells[Vector2i.ZERO].mana_source = true
	state.mana_by_faction[0] = 2
	state.replay_log = Replay.new()
	state.replay_log.start(state)
	state.build_structure(Vector2i(3, 0), 0, "city")
	state.build_road(Vector2i.ZERO, Vector2i(3, 0), 0)
	state.build_structure(Vector2i(0, 1), 0, "bridge", Vector2i.ZERO)
	expect(state.cast_spell("shatter",Vector2i(0, 1),0), "A sponsored bridge is removed through Shatter for replay coverage")
	var replay: Dictionary = Replay.read_records(state.replay_log.records)
	expect(replay.error == "" and replay.position.cells == state.cells, "Replays preserve cities, roads, sponsorship and shattered bridges")
	var document := Document.new()
	document.cells = fixture().cells
	document.player_start = Vector2i.ZERO
	document.cells[Vector2i(3, 0)].building = "city"
	document.cells[Vector2i(3, 0)].unit = 1
	document.cells[Vector2i(3, 0)].road = true
	document.cells[Vector2i(3, 0)].road_links = [Vector2i(2, 0)]
	var restored := Document.new()
	expect(restored.read_data(document.state()) == "" and restored.cells[Vector2i(3, 0)].road and restored.cells[Vector2i(3, 0)].building == "city", "Editor round-trips a city garrison on a road")
	expect(restored.cells[Vector2i(3, 0)].road_links == [Vector2i(2, 0)], "Authored maps preserve explicit road connections")
	var rows: Dictionary = document.state()
	for row in rows.cells:
		row.erase("road")
		row.erase("road_links")
		if row.building == "city": row.building = "house"
	expect(restored.read_data(rows) == "" and restored.cells[Vector2i(3, 0)].building == "city", "Old authored houses migrate to cities and absent roads default off")

func ai_checks() -> void:
	for algorithm in ["legacy", "strategic"]:
		for difficulty in ["easy", "normal", "hard"]:
			var state = fixture()
			state.ai_difficulty = difficulty
			state.ai_algorithm = algorithm
			state.cells[Vector2i.ZERO].unit = 1
			var advanced := false
			var captured := false
			for turn in range(12):
				state.prepare_ai_turn(0)
				var queries := Queries.new(state)
				for bank in state.kingdoms.values():
					expect(queries.bank_summary(bank).upkeep == state.upkeep(bank), "AI budget agrees with real wages and infrastructure")
				for source in state.cells:
					if state.unit_faction(source) != 0 or state.cells[source].unit == 0: continue
					expect(queries.candidate_targets(source) == state.reachable_targets(source).keys(), "AI targets honor each unit's finite range")
				state.ai_movements(0)
				for coord in state.cells:
					if state.cells[coord].unit > 0 and state.unit_faction(coord) == 0 and coord.x >= 5: advanced = true
				if state.cells[Vector2i(12, 0)].owner == 0: captured = true
			expect(advanced, "Every difficulty can march from a distant recruitment hub")
			expect(captured, "Every difficulty can eventually attack beyond its initial movement range")

func run() -> void:
	movement_checks()
	merge_checks()
	settlement_checks()
	tree_growth_checks()
	infrastructure_ai_checks()
	road_checks()
	construction_checks()
	economy_checks()
	replay_editor_checks()
	ai_checks()
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.open_shop("build")
	expect(scene.shop_items.get_child_count() == 3, "Build menu exposes only towers, cities and bridges")
	var home: Vector2i = scene.NONE
	for bank in scene.rules.kingdoms.values():
		if bank.owner == scene.player_faction: home = bank.capital
	var site: Vector2i = scene.NONE
	for coord in scene.rules.kingdom_at(home).hexes:
		if coord != home and scene.rules.cells[coord].unit == 0 and scene.rules.cells[coord].capital < 0:
			site = coord
			break
	scene.rules.cells[site].building = "city"
	scene.rules.cells[site].tree = false
	scene.rules.cells[site].grave = false
	scene.rules.kingdom_at(home).gold = 100
	scene.view.render_cells(scene.rules.cells)
	var gameplay = root.get_node("Gameplay")
	var original_indicators: bool = gameplay.clear_indicators
	for clear_indicators in [true, false]:
		gameplay.set_clear_indicators(clear_indicators, false)
		scene.choose_unit(1)
		scene.update_hover(scene.NONE, 0.0)
		var recruitment: Node = scene.view.overlay_root.get_node_or_null("RecruitmentArea")
		expect(recruitment != null and recruitment.get_meta("recruitable") == scene.valid_targets.keys(), "Recruitment has a complete area indicator even with no hovered tile")
		expect(not scene.view.overlay_root.has_node("KingdomOutline") and not scene.view.overlay_root.has_node("ReachableArea"), "Recruitment shows its own boundary instead of kingdom or movement range")
		var region_id: int = recruitment.get_instance_id()
		scene.update_hover(site, 0.0)
		expect(scene.view.overlay_root.get_node("RecruitmentArea").get_instance_id() == region_id, "Hovering retains the recruitment-area geometry")
		expect(recruitment.get_meta("boundary_edges") == scene.view.overlays.area_edges(scene.valid_targets), "Recruitment draws exterior and hole edges without internal borders")
		scene.cancel_action()
		expect(not scene.view.overlay_root.has_node("RecruitmentArea"), "Cancelling recruitment clears its range")
	gameplay.set_clear_indicators(original_indicators, false)
	scene.rules.kingdom_at(home).gold = 0
	scene.choose_unit(1)
	expect(not scene.view.overlay_root.has_node("RecruitmentArea"), "Unaffordable recruitment does not advertise illegal deployment tiles")
	scene.cancel_action()
	scene.rules.kingdom_at(home).gold = 100
	scene.rules.cells[home].mana_source = true
	scene.rules.mana_by_faction[scene.player_faction] = 2
	scene.choose_spell("summon")
	expect(scene.view.overlay_root.has_node("RecruitmentArea"), "Summon displays its legal recruitment area too")
	scene.cancel_action()
	scene.inspect_province(home)
	expect(scene.province_view.name_input.visible, "Capital details expose the name editor")
	scene.province_view.name_input.grab_focus()
	var typing := InputEventKey.new()
	typing.keycode = KEY_R
	typing.pressed = true
	scene._input(typing)
	scene._unhandled_input(typing)
	expect(not scene.shop_panel.visible and scene.action_mode == "", "Typing a settlement name does not trigger gameplay shortcuts")
	var before_pan: Vector3 = scene.view.focus
	scene.view.pan(Vector2.UP, 0.1)
	expect(scene.view.focus == before_pan, "Keyboard pan requests cannot move the camera while editing a name")
	scene.province_view.name_input.release_focus()
	scene.view.pan(Vector2.UP, 0.1)
	expect(scene.view.focus != before_pan, "Camera keyboard controls resume after leaving the name field")
	scene.province_view.name_input.grab_focus()
	scene.province_view.name_input.text = "Crown's Reach"
	scene.province_view.name_input.text_submitted.emit("Crown's Reach")
	expect(scene.rules.cells[home].settlement_name == "Crown's Reach" and scene.province_view.name_input.position.y < 20 and not scene.province_view.title.visible, "The capital name is edited directly in its title")
	scene.inspect_province(site)
	scene.province_view.name_input.grab_focus()
	scene.province_view.name_input.text = "Harbour"
	scene.province_view.name_input.text_submitted.emit("Harbour")
	expect(scene.rules.cells[site].settlement_name == "Harbour", "Enter submits a city name")
	scene.province_view.name_input.grab_focus()
	scene.province_view.name_input.text = "New Harbour"
	var click_away := InputEventMouseButton.new()
	click_away.pressed = true
	click_away.button_index = MOUSE_BUTTON_LEFT
	click_away.position = Vector2(900, 10)
	scene._input(click_away)
	expect(scene.rules.cells[site].settlement_name == "New Harbour" and not scene.province_view.name_input.has_focus(), "Clicking away saves the title even when the clicked control does not take focus")
	scene.province_view.name_input.grab_focus()
	scene.province_view.name_input.text = "Old Harbour"
	scene.inspect_province(home)
	expect(scene.rules.cells[site].settlement_name == "Old Harbour" and scene.rules.cells[home].settlement_name == "Crown's Reach", "Changing province commits the previous city's name to the correct tile")
	expect(scene.province_view.road_button.visible and not scene.province_view.road_button.disabled, "A structure exposes its road connection icon")
	scene.province_view.road_button.pressed.emit()
	expect(scene.action_mode == "road" and scene.selected == home and scene.valid_targets.has(site), "The road icon starts structure-to-structure targeting")
	scene.update_hover(site, 0.0)
	expect(scene.world_tip.visible and scene.tip_label.get_parsed_text().contains("Build road · %d G" % scene.valid_targets[site].cost), "Road hover immediately shows the exact total cost without a tooltip delay")
	expect(scene.session.selection.preview_path.size() >= 2, "Hovering a destination previews the complete route")
	var preview: Node = scene.view.overlay_root.get_node_or_null("RoadPreview")
	expect(preview != null and not scene.view.overlay_root.has_node("MovementRoute"), "A road-shaped preview replaces the movement arrow")
	var preview_meshes := {}
	if preview != null:
		for surface in preview.find_children("RoadPreviewSurface*", "MeshInstance3D", true, false):
			preview_meshes[surface.get_meta("hex")] = surface.mesh
			expect(surface.material_override == scene.view.roads.material, "Road preview uses the real shared road material")
	expect(not preview_meshes.is_empty(), "The preview contains the proposed paved surfaces")
	scene.show_world_tip()
	expect(scene.tip_label.get_parsed_text().contains("Build road"), "The hovered structure shows the connection price")
	var unbuilt: Vector2i = scene.NONE
	for coord in scene.rules.kingdom_at(home).hexes:
		if coord != home and scene.rules.cells[coord].capital < 0 and scene.rules.cells[coord].building == "":
			unbuilt = coord
			break
	var treasury: int = scene.rules.kingdom_at(home).gold
	scene.update_hover(unbuilt, 0.0)
	expect(scene.session.selection.preview_path.is_empty() and not scene.view.overlay_root.has_node("RoadPreview") and not scene.world_tip.visible, "Moving to an invalid endpoint clears the route and its price")
	scene.update_hover(site, 0.0)
	expect(scene.view.overlay_root.has_node("RoadPreview") and scene.world_tip.visible, "Moving back restores road geometry and cost without a full UI refresh")
	await scene.click_hex(unbuilt)
	expect(scene.action_mode == "road" and scene.rules.kingdom_at(home).gold == treasury, "Choosing empty land cannot construct or charge for a road")
	scene.cancel_action()
	expect(scene.action_mode == "" and scene.selected == scene.NONE and scene.session.selection.preview_path.is_empty(), "Cancelling road targeting clears its source and preview")
	expect(not scene.view.overlay_root.has_node("RoadPreview"), "Cancelling removes the road-shaped preview")
	scene.inspect_province(home)
	scene.province_view.road_button.pressed.emit()
	var cached_meshes: int = scene.view.roads.mesh_cache.size()
	await scene.click_hex(site)
	expect(scene.action_mode == "" and scene.view.tile_nodes[home].has_node("RoadPaint"), "Choosing a structure builds and renders the connection")
	for coord in preview_meshes:
		expect(scene.view.tile_nodes[coord].get_node("RoadPaint").mesh == preview_meshes[coord], "Placed roads reuse exactly the previewed geometry")
	expect(scene.view.roads.mesh_cache.size() == cached_meshes, "Placement needs no new road meshes after previewing")
	expect(scene.view.tile_nodes[home].get_node("Features").has_node("CapitalCastle"), "Capital uses the new castle model")
	scene.inspect_province(home)
	expect(scene.province_view.find_children("*","Button",false).all(func(button): return not button.text.to_lower().contains("dismantle")), "Province details do not expose dismantling")
	scene.rules.cells[home].erase("road")
	scene.rules.cells[home].erase("road_links")
	var peer = load("res://src/network/network_match.gd").new(Host.new(), scene, [{"id":7}])
	peer.revision = 0
	var rename_command := {"kind":"rename", "coord":home, "name":"Network Capital", "revision":0, "request":1}
	expect(peer.valid_command(7, rename_command), "Host accepts settlement renaming from its owner")
	rename_command.name = 5
	expect(not peer.valid_command(7, rename_command), "Host rejects malformed rename payloads")
	rename_command.name = "x".repeat(41)
	expect(not peer.valid_command(7, rename_command), "Host rejects oversized rename payloads")
	rename_command.name = "Valid"
	rename_command.coord = Vector2i(100, 100)
	expect(not peer.valid_command(7, rename_command), "Host rejects renaming nonexistent settlements")
	var command := {"kind":"road", "source":home, "coord":site, "revision":0, "request":1}
	expect(peer.valid_command(7, command), "The host validates structure-to-structure road commands")
	command.source = Vector2i(100, 100)
	expect(not peer.valid_command(7, command), "Clients cannot invent a road source")
	scene.rules.build_road(home, site, 0)
	command = {"kind":"dismantle", "coord":site, "revision":0, "request":1}
	expect(not peer.valid_command(7, command) and not peer.valid_command(8, command), "The host rejects road removal even from its owner")
	scene.rules.cells[site].building = "tower"
	expect(not peer.valid_command(7, command), "The host rejects tower removal")
	var crossings: Array = scene.rules.bridge_targets(0,home).keys()
	var crossing: Vector2i = crossings[0] if not crossings.is_empty() else scene.NONE
	expect(scene.rules.build_structure(crossing,0,"bridge",home), "The network rejection fixture includes an empty sponsored bridge")
	command.coord = crossing
	var bridge_before: Dictionary = scene.cells[crossing].duplicate(true)
	expect(not peer.valid_command(7,command), "The host rejects bridge dismantling even from its sponsor")
	await peer.handle(7,command)
	expect(scene.cells[crossing] == bridge_before, "Rejected dismantling leaves the bridge intact")
	scene.network_match = null
	scene.session.online = false
	peer.free()
	scene.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Logistics checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
