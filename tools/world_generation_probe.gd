extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
const Archipelago = preload("res://src/game/archipelago.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for size_id in Sizes.IDS:
		var total := 0
		var layouts := {}
		var offshore := 0
		var vertical := 0
		var smallest := 100000
		var started := Time.get_ticks_usec()
		for seed_value in range(24):
			var rules = Rules.new()
			rules.rule_mode = "modern"
			rules.generate(seed_value, size_id)
			var regions := Archipelago.components(rules.cells)
			layouts[regions.size()] = layouts.get(regions.size(), 0) + 1
			for index in range(1, regions.size()): smallest = mini(smallest, regions[index].size())
			offshore += regions.size() - 1
			total += rules.cells.size()
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			for coord in rules.cells:
				var at: Vector3 = Rules.Grid.to_world(coord)
				low = low.min(Vector2(at.x, at.z))
				high = high.max(Vector2(at.x, at.z))
			if (high - low).y > (high - low).x: vertical += 1
			assert(rules.starting_land_reachable())
		print(size_id, ": tiles=", total / 24.0, "; layouts=", layouts, "; islands=", offshore, "; min_island=", smallest, "; vertical=", vertical, "; ms=", (Time.get_ticks_usec() - started) / 1000.0)
	quit()
