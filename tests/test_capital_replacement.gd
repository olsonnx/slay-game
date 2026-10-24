extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func line(mode: String, length: int):
	var state = Rules.new()
	state.rule_mode = mode
	for x in range(length): state.cells[Vector2i(x, 0)] = state.make_cell(0)
	return state

func run() -> void:
	for mode in ["modern"]:
		for incremental in [false, true]:
			var state = line(mode, 6)
			state.incremental_kingdoms = incremental
			for x in [-2, -1]: state.cells[Vector2i(x, 0)] = state.make_cell(1)
			state.cells[Vector2i.ZERO]["capital"] = 0
			state.cells[Vector2i(-2, 0)]["capital"] = 1
			state.cells[Vector2i(-1, 0)]["unit"] = 3
			state.rebuild_kingdoms()
			for bank in state.kingdoms.values(): bank["gold"] = 100
			expect(state.kingdom_at(Vector2i.ZERO)["capital"] == Vector2i.ZERO, "An existing capital stays in place even on a rival border")
			var rng_state: int = state.rng.state
			expect(state.move_unit(Vector2i(-1, 0), Vector2i.ZERO), "Enemy actually captures the old capital")
			var bank: Dictionary = state.kingdom_at(Vector2i(5, 0))
			var expected := Vector2i(3 if mode == "modern" else 2, 0)
			expect(bank["capital"] == expected, "Replacement avoids the new rival border after ordinary capture or Modern surrender")
			expect(bank["gold"] == 0, "A replacement does not recover the destroyed capital's treasury")
			expect(state.rng.state == rng_state, "Replacement selection never consumes random numbers")
			var snapshot: Dictionary = state.cells.duplicate(true)
			state.rebuild_kingdoms()
			expect(state.cells == snapshot and state.kingdom_at(Vector2i(5, 0))["gold"] == 0, "Repeated rebuilding preserves the new capital without generating money")
		# Empty approach hexes are less safe than an interior garrison.
		var garrison = line(mode, 3)
		for x in [-1, 3]: garrison.cells[Vector2i(x, 0)] = garrison.make_cell(1)
		garrison.cells[Vector2i.RIGHT]["unit"] = 3
		garrison.rebuild_kingdoms()
		expect(garrison.kingdom_at(Vector2i.ZERO)["capital"] == Vector2i.RIGHT and garrison.cells[Vector2i.RIGHT]["unit"] == 3, "A friendly garrison can share the safe replacement capital and survives")
		var border = line(mode, 2)
		for coord in [Vector2i(-1, 0), Vector2i(0, 1)]: border.cells[coord] = border.make_cell(1)
		border.rebuild_kingdoms()
		expect(border.kingdom_at(Vector2i.ZERO)["capital"] == Vector2i.RIGHT, "When every site borders rivals, choose the site with fewer rival neighbours")
		var neutral = line(mode, 2)
		neutral.cells[Vector2i(-1, 0)] = neutral.make_cell()
		neutral.rebuild_kingdoms()
		expect(neutral.kingdom_at(Vector2i.ZERO)["capital"] == Vector2i.ZERO, "Neutral land and missing water hexes do not count as rival borders")
		var buildings = line(mode, 3)
		for x in [-1, 3]: buildings.cells[Vector2i(x, 0)] = buildings.make_cell(1)
		buildings.cells[Vector2i.RIGHT]["building"] = "house"
		buildings.rebuild_kingdoms()
		expect(buildings.cells[Vector2i.RIGHT]["building"] == "house", "Capital placement preserves a house when a structure-free site exists")
		for x in range(3): buildings.cells[Vector2i(x, 0)]["building"] = "tower"
		for cell in buildings.cells.values(): cell["capital"] = -1
		buildings.rebuild_kingdoms()
		expect(buildings.kingdom_at(Vector2i.ZERO)["capital"] == Vector2i.RIGHT and buildings.cells[Vector2i.RIGHT]["building"] == "", "A kingdom still gets its safest capital if every site has a building")
		# Real split: a surviving capital retains money; the detached bank starts empty.
		var split = line(mode, 7)
		split.cells[Vector2i.ZERO]["capital"] = 0
		for coord in [Vector2i(3, -1), Vector2i(4, -1)]: split.cells[coord] = split.make_cell(1)
		split.cells[Vector2i(3, -1)]["capital"] = 1
		split.cells[Vector2i(4, -1)]["unit"] = 3
		split.rebuild_kingdoms()
		split.kingdom_at(Vector2i.ZERO)["gold"] = 57
		var full = Analysis.snapshot(split)
		full.incremental_kingdoms = false
		expect(split.move_unit(Vector2i(4, -1), Vector2i(3, 0)) and full.move_unit(Vector2i(4, -1), Vector2i(3, 0)), "Cutting the connecting province legally splits the kingdom")
		expect(split.kingdom_at(Vector2i.ZERO)["gold"] == 57 and split.kingdom_at(Vector2i(6, 0))["gold"] == 0, "Split treasury remains with its surviving capital")
		expect(split.kingdom_at(Vector2i(6, 0))["capital"] == Vector2i(5, 0), "A detached kingdom places its capital away from the cut border")
		expect(split.cells == full.cells and split.kingdoms == full.kingdoms, "Incremental and complete rebuilding choose identical capitals and banks")
	var bridge = line("modern", 4)
	bridge.cells[Vector2i.RIGHT]["owner"] = -1
	bridge.cells[Vector2i.RIGHT]["building"] = "bridge"
	bridge.cells[Vector2i.RIGHT]["unit"] = 3
	bridge.cells[Vector2i.RIGHT]["unit_owner"] = 1
	bridge.cells[Vector2i.ZERO]["owner"] = 1
	bridge.rebuild_kingdoms()
	expect(bridge.kingdom_at(Vector2i(3, 0))["capital"] == Vector2i(3, 0), "Replacement avoids an adjacent hostile bridge garrison and never spawns on the bridge")
	var mountain = line("modern", 2)
	mountain.cells[Vector2i(-1, 0)] = mountain.make_cell(1)
	mountain.cells[Vector2i(-1, 0)]["mountain"] = true
	mountain.rebuild_kingdoms()
	expect(mountain.kingdom_at(Vector2i.ZERO)["capital"] == Vector2i.ZERO, "Impassable mountains are not treated as hostile approaches")
	print("Capital replacement checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
