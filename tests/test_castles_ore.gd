extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Snapshot = preload("res://src/game/state_snapshot.gd")
const Layout = preload("res://src/rendering/tile_layout.gd")
const Document = preload("res://src/editor/level_document.gd")
const Replay = preload("res://src/game/replay_log.gd")
const ManaResources = preload("res://src/game/mana_resources.gd")
const Timeline = preload("res://src/game/replay_timeline.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func fixture():
	var state = Rules.new()
	state.faction_count = 2
	for q in range(-3, 6):
		for r in range(-2, 3): state.cells[Vector2i(q,r)] = state.make_cell(0)
	state.cells[Vector2i(-3,0)].capital = 0
	state.cells[Vector2i(6,0)] = state.make_cell(1)
	state.cells[Vector2i(7,0)] = state.make_cell(1)
	state.cells[Vector2i(7,0)].capital = 1
	state.rebuild_kingdoms()
	for bank in state.kingdoms.values(): bank.gold = 1000
	state.ore_by_faction[0] = 20
	return state
func run() -> void:
	var state = fixture()
	var at := Vector2i.ZERO
	state.cells[at].ore_source = true
	for value in range(1,7):
		state.cells[at].value = value
		expect(state.ore_income(0) == [0, 0, 1, 1, 1, 2][value - 1], "Ore yields one per three development, rounded down per source")
	state.cells[at].value = 2
	state.cells[Vector2i(1,0)].ore_source = true
	state.cells[Vector2i(1,0)].value = 2
	expect(state.ore_income(0) == 0, "Each source rounds down separately; two development-two deposits yield no Ore")
	state.cells[at].value = 6
	state.cells[Vector2i(1,0)].ore_source = true
	state.cells[Vector2i(1,0)].value = 3
	state.ore_by_faction[0] = 1000
	state.begin_turn(0)
	expect(state.get_ore(0) == 1003, "Ore accumulates without a cap and sums sources")
	state.cells[at].owner = 1
	expect(state.ore_income(0) == 1 and state.ore_income(1) == 2, "Capture transfers source income, not the stored balance")
	expect(state.get_ore(0) == 1003, "Losing sources does not clamp stored Ore")
	state = fixture()
	state.cells[at].building = "city"
	for tier in range(1,4):
		state.cells[at].building_tier = tier
		for distance in range(0,4):
			var coord := Vector2i(distance,0)
			expect(state.can_recruit(coord,0,1) == (distance <= tier-1), "Castle recruitment range is 0 / 1 / 2")
	state.cells[at].building_tier = 1
	state.ore_by_faction[0] = 1
	expect(not state.can_upgrade_building(at,0), "An upgrade cannot overspend Ore")
	state.ore_by_faction[0] = 6
	expect(state.upgrade_building(at,0) and state.get_ore(0) == 4 and state.building_tier(at) == 2, "Tier two costs 2 Ore")
	expect(state.upgrade_building(at,0) and state.get_ore(0) == 0 and state.building_tier(at) == 3, "Tier three costs 4 Ore")
	expect(not state.upgrade_building(at,0), "No upgrade beyond tier three")
	expect(not state.upgrade_building(at,1), "Enemy cannot upgrade a building")
	state.cells[Vector2i(1,0)].building = "bridge"
	expect(not state.can_upgrade_building(Vector2i(1,0),0), "Bridge mechanics stay unchanged")
	state = fixture()
	var capital := Vector2i(-3,0)
	for tier in range(1,4):
		state.cells[capital].capital_tier = tier
		expect(state.can_recruit(Vector2i(-1,0),0,1) == (tier >= 2), "Capital tier two adds one recruitment ring")
		expect(state.local_defense(capital) == (1 if tier == 1 else 2), "Capital tiers require Soldier / Knight / Knight")
	state.cells[capital].capital_tier = 3
	state.cells[capital].value = 2
	state.cells[Vector2i(-2,0)].value = 2
	expect(state.development_cost(capital) == 4 and state.development_cost(Vector2i(-2,0)) == 4, "Tier-three Capital halves local and adjacent development cost")
	state.cells[Vector2i(-1,0)].value = 2
	expect(state.development_cost(Vector2i(-1,0)) == 8, "Discount stops outside the adjacent ring")
	state.cells[Vector2i(-2,0)].owner = 1
	expect(state.development_cost(Vector2i(-2,0)) == 8, "Capital discount does not benefit enemies")
	expect(state.relocate_capital(Vector2i(1,0),0), "Upgraded Capital can relocate")
	expect(state.cells[Vector2i(1,0)].capital_tier == 3 and state.cells[capital].capital_tier == 1, "Relocation transfers Capital tier")
	state = fixture()
	state.ore_by_faction[0] = 1
	expect(not state.can_recruit(capital,0,3), "Knight recruitment needs 2 Ore")
	state.ore_by_faction[0] = 2
	expect(state.recruit(capital,0,3) and state.get_ore(0) == 0, "Knight recruitment pays Ore once")
	state.begin_turn(0)
	expect(state.get_ore(0) == 0, "Knight upkeep does not charge Ore")
	state = fixture()
	state.cells[capital].unit = 2
	state.ore_by_faction[0] = 2
	expect(state.recruit(capital,0,3) and state.get_ore(0) == 0, "Soldier-to-Knight upgrade also pays Ore")
	state = fixture()
	state.cells[at].building = "tower"
	for tier in range(1,4):
		state.cells[at].building_tier = tier
		expect(state.local_defense(at) == (1 if tier == 1 else 2), "Tower defense follows its tier")
	# Two separate attackers strike a tier-three tower. First hit consumes the ward.
	state.cells[at].owner = 1
	state.cells[at].building_tier = 3
	state.cells[Vector2i(-1,0)].unit = 3
	state.cells[Vector2i(0,-1)].unit = 3
	state.rebuild_kingdoms()
	expect(state.structure_entrenched(at), "Tier-three tower starts with a ward")
	expect(state.move_unit(Vector2i(-1,0),at), "First Knight can strike tower")
	expect(state.cells[at].owner == 1 and state.cells[at].building == "tower" and not state.structure_entrenched(at), "First strike leaves tower intact and consumes ward")
	expect(state.cells[Vector2i(-1,0)].moved, "First attacker spends its action")
	state.begin_turn(1)
	expect(state.structure_entrenched(at), "Ward returns at owner's next turn")
	state.cells[Vector2i(-1,0)].moved = false
	expect(state.move_unit(Vector2i(-1,0),at) and state.move_unit(Vector2i(0,-1),at), "Two valid strikes destroy tier-three tower")
	expect(state.cells[at].owner == 0 and state.cells[at].building == "", "Second hit captures tile and removes tower")
	# Snapshot copies and replay patches include the new currency.
	state = fixture()
	var snapshot := Snapshot.capture(state)
	state.ore_by_faction[0] = 0
	Snapshot.restore(state,snapshot)
	expect(state.get_ore(0) == 20, "Undo snapshot restores Ore")
	var copy = Snapshot.simulation(state)
	copy.ore_by_faction[0] = 0
	expect(state.get_ore(0) == 20, "AI simulation owns a separate Ore balance")
	var replay = Replay.new()
	replay.start(state)
	state.replay_log = replay
	state.cells[at].building = "city"
	state.upgrade_building(at,0)
	expect(replay.previous.ore[0] == 18, "Replay captures Ore spending")
	state.replay_log = null
	var document = Document.new()
	document.cells = state.cells.duplicate(true)
	document.cells[at].ore_source = true
	document.cells[at].building_tier = 3
	document.player_start = capital
	var saved := document.state()
	var loaded = Document.new()
	expect(loaded.read_data(JSON.parse_string(JSON.stringify(saved))) == "", "New map schema validates")
	expect(loaded.cells[at].ore_source and loaded.cells[at].building_tier == 3, "Map round-trip preserves Ore deposits and building tiers")
	expect(loaded.state() == saved, "JSON round-trip preserves numeric tier types")
	for row in saved.cells:
		for field in ["ore_source", "building_tier", "capital_tier"]: row.erase(field)
	expect(loaded.read_data(saved) == "" and not loaded.cells[at].ore_source and loaded.cells[at].building_tier == 1, "Old authored maps default safely")
	for seed_value in range(12):
		state = Rules.new()
		state.generate(seed_value, "small", 4)
		var mana := 0
		var ore := 0
		for coord in state.cells:
			var cell: Dictionary = state.cells[coord]
			if cell.mana_source: mana += 1
			if cell.ore_source:
				ore += 1
				expect(not state.is_mountain(coord) and not state.is_bridge(coord) and not state.has_wildlife(coord), "Generated Ore source is usable")
		expect(ore == ceili(mana * Rules.Catalog.ORE_SOURCE_MULTIPLIER) and ore > mana, "Ore is slightly more common than mana")
		copy = Rules.new()
		copy.generate(seed_value,"small",4)
		expect(state.cells == copy.cells, "Ore maps are deterministic")
	for sample in [[0,0], [50,1], [149,1], [150,2], [300,3], [750,6], [10000,6]]:
		expect(ManaResources.extra_source_budget(sample[0]) == sample[1], "Land-area source bonus grows gradually and is capped")
	state = Rules.new()
	state.level_seed = 87
	state.rng.seed = 1234
	for q in range(-10,11):
		for r in range(-10,11): state.cells[Vector2i(q,r)] = state.make_cell()
	state.cells[Vector2i.ZERO].mana_source = true
	state.cells[Vector2i(1,0)].owner = 0
	state.cells[Vector2i(2,0)].event = "gold"
	state.cells[Vector2i(3,0)]["treasure"] = 10
	state.cells[Vector2i(4,0)]["lair"] = "wolf"
	var random_before: int = state.rng.state
	var added := ManaResources.generate(state)
	expect(added == ManaResources.extra_source_budget(440), "Spacious maps receive their bounded source bonus")
	expect(state.rng.state == random_before, "Bonus placement leaves gameplay RNG untouched")
	var mana_sites: Array = []
	for coord in state.cells:
		if not state.cells[coord].mana_source: continue
		mana_sites.append(coord)
		if coord != Vector2i.ZERO:
			expect(state.cells[coord].owner == -1 and state.cells[coord].event == "" and state.cells[coord].get("treasure",0) == 0 and not state.has_wildlife(coord), "Extra sources are neutral objectives without replacing encounters")
	for first in range(mana_sites.size()):
		for second in range(first + 1, mana_sites.size()):
			expect(state.distance(mana_sites[first],mana_sites[second]) >= 3, "Extra mana sources retain three-hex spacing")
	for size_id in ["small", "large", "huge"]:
		state = Rules.new()
		state.generate(42, size_id, 4)
		copy = Rules.new()
		copy.generate(42, size_id, 4)
		expect(state.cells == copy.cells and state.rng.state == copy.rng.state, "Resource scaling is deterministic on every map size")
	# Independently check all roof corners against pointy-top hex inequalities.
	# Include every allowed rotation and the extreme random displacements.
	for site in Layout.DEVELOPMENT_OFFSETS:
		for angle in range(-28,29):
			var rotation := Basis(Vector3.UP, deg_to_rad(float(angle)))
			for dx in [-0.022,0.022]:
				for dz in [-0.022,0.022]:
					var wanted: Vector3 = site + Vector3(dx,0,dz)
					var fitted: Vector3 = Layout.constrain_house_position(wanted, deg_to_rad(float(angle)))
					for x in [-1.0,1.0]:
						for z in [-1.0,1.0]:
							var corner: Vector3 = fitted + rotation * Vector3(x * 0.39,0,z * 0.35) * Layout.DEVELOPMENT_HOUSE_SCALE
							expect(absf(corner.x) <= sqrt(3.0) * 0.968 / 2.0 and absf(corner.z) <= 0.968 - absf(corner.x) / sqrt(3.0), "Every rotated roof corner stays inside its own hex")
	var safe := Vector3(0.2,0,0.1)
	expect(Layout.constrain_house_position(safe,0.2).is_equal_approx(safe), "Safe displacement is preserved")
	var paired_four := false
	var paired_two := false
	var split_two := false
	for q in range(-8,9):
		var coord := Vector2i(q, q * 3)
		var cell: Dictionary = Rules.new().make_cell(0)
		var previous: Array[int] = []
		for value in range(1,7):
			cell.value = value
			var slots: Array[int] = Layout.development_house_slots(coord, cell)
			expect(slots.size() == [0, 0, 1, 2, 3, 4][value - 1], "Development 1–2 has no houses; levels 3–6 show one through four")
			expect(slots == Layout.development_house_slots(coord, cell), "House distribution stays stable across redraws")
			expect(slots.slice(0, previous.size()) == previous, "Development keeps existing houses in place")
			var counts := [0, 0, 0]
			for slot in slots: counts[slot % 3] += 1
			expect(counts.max() <= 2, "Each corner holds at most two houses")
			if value == 6 and counts.count(2) == 2: paired_four = true
			if value == 4:
				if counts.max() == 2: paired_two = true
				else: split_two = true
			previous = slots
		cell.owner = -1
		expect(Layout.development_house_slots(coord, cell).is_empty(), "Neutral provinces never show development houses")
	expect(paired_four, "Four houses can occupy two paired corners")
	expect(paired_two and split_two, "Two houses can share a corner or occupy different corners")
	expect(Layout.landmark_offset({"unit":3}) == Layout.LANDMARK_STRUCTURE_OFFSET and Layout.landmark_scale({"unit":3}) == 0.8, "Occupied buildings shift slightly and shrink")
	expect(Layout.landmark_offset({"unit":0}) == Vector3.ZERO and Layout.landmark_scale({"unit":0}) == 1.0, "Vacant buildings return to their centered full size")
	for kind in ["", "city", "tower", "monument"]:
		expect(Layout.unit_scale({"unit":3,"building":kind,"capital":0}) == 1.0, "Buildings never shrink their garrison")
	expect(Layout.unit_offset({"building":"city"}) == Layout.LANDMARK_UNIT_OFFSET, "Garrison stands beside the smaller building")
	print("0.3.0 checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
