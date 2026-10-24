extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
const Archipelago = preload("res://src/game/archipelago.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func lake_sizes(cells: Dictionary) -> Array:
	var low := Vector2i(100000, 100000)
	var high := -low
	for coord in cells:
		low = low.min(coord - Vector2i.ONE)
		high = high.max(coord + Vector2i.ONE)
	var seen := {}
	var result := []
	for q in range(low.x, high.x + 1):
		for r in range(low.y, high.y + 1):
			var start := Vector2i(q, r)
			if seen.has(start) or cells.has(start): continue
			var pending := [start]
			seen[start] = true
			var index := 0
			var enclosed := true
			while index < pending.size():
				var coord: Vector2i = pending[index]
				index += 1
				for direction in Rules.DIRECTIONS:
					var next: Vector2i = coord + direction
					if next.x < low.x or next.y < low.y or next.x > high.x or next.y > high.y:
						enclosed = false
						continue
					if not cells.has(next) and not seen.has(next):
						seen[next] = true
						pending.append(next)
			if enclosed: result.append(pending.size())
	return result

func verify_lake_carving() -> void:
	for seed_value in range(8):
		var rules = Rules.new()
		rules.rng.seed = seed_value
		for q in range(-12, 13):
			for r in range(-12, 13):
				var coord := Vector2i(q, r)
				if rules.distance(Vector2i.ZERO, coord) <= 12: rules.cells[coord] = rules.make_cell()
		var before: int = rules.cells.size()
		var generator = Rules.MapGenerator.new(rules)
		generator.lake_budget = 32
		generator.generate_lakes([], before - 32)
		var sizes := lake_sizes(rules.cells)
		expect(not sizes.is_empty() and sizes.size() <= 3, "Lake carving produces a few enclosed bodies of water")
		for count in sizes: expect(count >= 5, "Carving never commits a tiny partial lake")
		expect(rules.cells.size() >= before - 32 and rules.connected_land(), "Lake carving respects the land budget and leaves the shore connected")

func verify_ridges() -> void:
	var passes := 0
	var longest := 0
	for seed_value in range(8):
		var rules = Rules.new()
		rules.rule_mode = "modern"
		rules.rng.seed = seed_value
		for q in range(-12, 13):
			for r in range(-12, 13):
				var coord := Vector2i(q, r)
				if rules.distance(Vector2i.ZERO, coord) <= 12: rules.cells[coord] = rules.make_cell()
		rules.cells[Vector2i.ZERO]["owner"] = 0
		rules.cells[Vector2i(-6, 0)]["mana_source"] = true
		var generator = Rules.MapGenerator.new(rules)
		generator.protected_landings[Vector2i(6, 0)] = true
		generator.generate_mountains()
		expect(not rules.is_mountain(Vector2i.ZERO) and not rules.is_mountain(Vector2i(-6, 0)) and not rules.is_mountain(Vector2i(6, 0)), "Ridges preserve homes, mana objectives and bridge ports")
		expect(rules.passable_land_connected(), "Ridges leave all habitable terrain reachable")
		for coord in generator.protected_passes:
			var peaks := 0
			for next in rules.neighbors(coord):
				if rules.is_mountain(next): peaks += 1
			expect(not rules.is_mountain(coord) and peaks == 2 and rules.neighbors(coord).size() == 6, "Inland passes remain open between two ridge segments")
			passes += 1
		var mountains := {}
		for coord in rules.cells:
			if rules.is_mountain(coord): mountains[coord] = rules.cells[coord]
		for ridge in Archipelago.components(mountains):
			longest = maxi(longest, ridge.size())
			var ends := 0
			for coord in ridge:
				var degree := 0
				for next in rules.neighbors(coord):
					if rules.is_mountain(next): degree += 1
				expect(degree <= 2, "A ridge stays one tile wide without branches or blobs")
				if degree == 1: ends += 1
			expect(ends == 2, "Every ridge segment has open ends instead of closing into a ring")
		for coord in rules.cells:
			if not rules.is_mountain(coord): rules.cells[coord]["owner"] = 0
		for coord in generator.protected_passes:
			for direction in Rules.DIRECTIONS.slice(0, 3):
				var source: Vector2i = coord + direction
				var target: Vector2i = coord - direction
				if rules.is_mountain(source) or rules.is_mountain(target): continue
				rules.cells[source]["unit"] = 1
				var direct: Array = rules.movement_path(source, target)
				expect(direct.size() == 3 and coord in direct, "Scouts use the pass as a direct route across a ridge")
				rules.cells[coord]["mountain"] = true
				var detour: Array = rules.movement_path(source, target)
				expect(detour.size() > direct.size(), "Closing the shortcut requires a longer route around the ridge")
				rules.cells[coord]["mountain"] = false
				rules.cells[source]["unit"] = 0
				break
	expect(passes > 0 and longest >= 7, "Long winding ridges and usable passes both occur across seeds")

func run() -> void:
	verify_ridges()
	verify_lake_carving()
	var isolated = Rules.new()
	isolated.rule_mode = "modern"
	isolated.cells[Vector2i.ZERO] = isolated.make_cell()
	isolated.cells[Vector2i(3, 0)] = isolated.make_cell()
	expect(not isolated.starting_land_reachable(), "Two-water-hex gaps require more than one bridge and are rejected")
	isolated.cells.erase(Vector2i(3, 0))
	isolated.cells[Vector2i(2, 0)] = isolated.make_cell()
	expect(isolated.starting_land_reachable(), "A single water hex provides a bridge crossing")
	isolated.cells[Vector2i(2, 0)]["mountain"] = true
	expect(Archipelago.components(isolated.cells, true).size() == 1, "Mountains are excluded from reachable terrain")
	isolated.cells[Vector2i(2, 0)]["mountain"] = false
	isolated.cells[Vector2i(1, 0)] = isolated.make_cell()
	isolated.cells[Vector2i(1, 0)]["mountain"] = true
	expect(not isolated.starting_land_reachable(), "A mountain blocks the apparent crossing between two passable regions")
	isolated.cells.erase(Vector2i(1, 0))
	for size_id in Sizes.IDS:
		var vertical := 0
		var horizontal := 0
		var layouts := {}
		var balanced := false
		var inland_peaks := 0
		var long_ranges := 0
		var lakes := 0
		var largest_lake := 0
		var quiet_worlds := 0
		for mode in ["modern"]:
			for seed_value in range(16):
				var rules = Rules.new()
				rules.rule_mode = mode
				rules.generate(seed_value, size_id)
				var regions := Archipelago.components(rules.cells)
				var passable := Archipelago.components(rules.cells, true)
				expect(rules.starting_land_reachable(), "Every landmass remains reachable through passable land and bridges")
				expect(passable.size() == regions.size(), "Mountains never divide an island into inaccessible pockets")
				if mode == "modern":
					layouts[regions.size()] = true
					balanced = balanced or regions[0].size() <= rules.cells.size() * 0.6
					for coord in rules.cells:
						if rules.is_mountain(coord):
							var inland: bool = rules.neighbors(coord).size() == 6
							for next in rules.neighbors(coord): inland = inland and rules.neighbors(next).size() == 6
							if inland: inland_peaks += 1
					var sizes := lake_sizes(rules.cells)
					lakes += sizes.size()
					for count in sizes: largest_lake = maxi(largest_lake, count)
					if sizes.filter(func(count): return count >= 5).is_empty(): quiet_worlds += 1
					var peaks := {}
					for coord in rules.cells:
						if rules.is_mountain(coord): peaks[coord] = rules.cells[coord]
					expect(peaks.size() <= roundi(rules.cells.size() * 0.085), "Mountain cover stays within its moderate budget, including Huge maps")
					for coord in peaks:
						var degree := 0
						for next in rules.neighbors(coord):
							if rules.is_mountain(next): degree += 1
						expect(degree <= 2, "Mountains form thin ridges without dense junctions")
					for ridge in Archipelago.components(peaks):
						expect(ridge.size() >= 2 and ridge.size() <= clampi(roundi(sqrt(rules.cells.size()) * 0.55), 5, 18), "Mountain ranges respect size limits")
						if ridge.size() >= 4: long_ranges += 1
				expect(rules.cells.size() >= Sizes.spec(size_id)["min_land"], "Land budget includes offshore expansion space")
				expect(regions.size() <= 3, "Worlds have one, two or three landmasses")
				var membership := {}
				for index in range(regions.size()):
					for coord in regions[index]: membership[coord] = index
					if index > 0:
						expect(regions[index].size() >= Archipelago.MIN_ISLAND_TILES, "No offshore component has only one to twelve hexes")
						var source := false
						for coord in regions[index]: source = source or rules.cells[coord]["mana_source"]
						expect(source, "Each offshore landmass has a mana source")
				if mode == "modern" and regions.size() > 1:
					var occupied := {}
					for bank in rules.kingdoms.values(): occupied[membership[bank["capital"]]] = true
					expect(occupied.size() == regions.size(), "Kingdoms spawn on every generated landmass")
				var low := Vector2(INF, INF)
				var high := Vector2(-INF, -INF)
				for coord in rules.cells:
					var at: Vector3 = Rules.Grid.to_world(coord)
					var point := Vector2(at.x, at.z)
					low = low.min(point)
					high = high.max(point)
					expect(point.length() < Sizes.generation_bounds(size_id).x - 2.0, "Coastlines never reach the safety envelope and get clipped flat")
				if (high - low).y > (high - low).x: vertical += 1
				else: horizontal += 1
				var repeat = Rules.new()
				repeat.rule_mode = mode
				repeat.generate(seed_value, size_id)
				expect(repeat.cells == rules.cells and repeat.rng.state == rules.rng.state, "Seeded generation remains deterministic, including islands and resources")
				if mode == "modern" and regions.size() > 1: verify_crossing(rules, regions)
		expect(vertical >= 4 and horizontal >= 4, "Worlds can extend vertically or horizontally")
		expect(layouts.has(1), "Single-landmass worlds remain possible at every size")
		if size_id != "very_small":
			expect(layouts.has(2), "Even Small worlds can host island kingdoms")
		if size_id in ["medium", "large", "very_large", "huge"]:
			expect(layouts.has(3) and balanced, "Larger worlds can have three peers without a dominant mainland")
			expect(inland_peaks > 0 and lakes > 0 and long_ranges > 0 and largest_lake >= 6 and quiet_worlds > 0, "Larger worlds include inland mountains and enclosed lakes")
		if size_id in ["very_large", "huge"]:
			expect(largest_lake >= 20, "Large inland lakes exceed twenty water hexes on bigger worlds")
	for size_id in ["large", "huge"]:
		var rules = Rules.new()
		rules.rule_mode = "modern"
		rules.generate(42, size_id)
		var view = load("res://src/rendering/board_view.gd").new()
		root.add_child(view)
		view.set_process(false)
		view.configure_map(size_id, rules.bridge_bounds(), rules.cells)
		view.reset_camera()
		var screen: Rect2 = root.get_visible_rect().grow(-12.0)
		for coord in rules.cells:
			var at: Vector3 = Rules.Grid.to_world(coord)
			expect(screen.has_point(view.camera.unproject_position(at)) and screen.has_point(view.camera.unproject_position(at + Vector3.UP * 3.0)), "Initial camera fits tall, wide and offshore terrain with prop clearance")
		view.queue_free()
		await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("World generation checks: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)

func verify_crossing(original, regions: Array) -> void:
	var copy = Rules.new()
	copy.rule_mode = "modern"
	copy.map_size = original.map_size
	copy.cells = original.cells.duplicate(true)
	for cell in copy.cells.values():
		# Isolate geographic bridge access from optional combat objectives.
		for field in ["animal","animal_home","lair","lair_wait"]: cell.erase(field)
		cell["unit"] = 0
		cell["owner"] = -1
		cell["capital"] = -1
	var capital := Rules.NONE
	for coord in regions[0]:
		if copy.is_mountain(coord): continue
		copy.cells[coord]["owner"] = 0
		copy.cells[coord]["capital"] = -1
		copy.cells[coord]["unit"] = 0
		if capital == Rules.NONE: capital = coord
	copy.cells[capital]["capital"] = 0
	copy.rebuild_kingdoms()
	copy.kingdoms[capital]["gold"] = 100
	var offshore := {}
	for region in regions.slice(1):
		for coord in region: offshore[coord] = true
	for shore in regions[0]:
		if copy.is_mountain(shore): continue
		for direction in Rules.DIRECTIONS:
			var gap: Vector2i = shore + direction
			if copy.cells.has(gap): continue
			for edge in Rules.DIRECTIONS:
				var landing: Vector2i = gap + edge
				if not offshore.has(landing) or copy.is_mountain(landing): continue
				expect(copy.can_build(gap, 0, "bridge", capital) and copy.build_structure(gap, 0, "bridge", capital), "An offshore crossing is affordable and legal through authoritative bridge rules")
				copy.cells[shore]["unit"] = 1
				expect(copy.can_move(shore, landing), "A Scout can cross the new bridge and enter the offshore island")
				return
	expect(false, "A playable offshore crossing must exist")
