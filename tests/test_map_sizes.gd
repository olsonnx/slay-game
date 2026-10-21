extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
var checks := 0
var failures := 0
var starting_sizes := {}
var non_ring_starts := {"classic":0, "modern":0}
var mixed_size_maps := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func starting_shape_checks(rules) -> void:
	var sizes_on_map := {}
	for bank in rules.kingdoms.values():
		var capital: Vector2i = bank["capital"]
		var owned := {}
		var expansion := {}
		var inner_neighbors := 0
		var non_ring := false
		for coord in bank["hexes"]:
			owned[coord] = rules.cells[coord]
			if rules.distance(coord, capital) > 1: non_ring = true
			for next in rules.neighbors(coord):
				if rules.cells[next]["owner"] == -1 and not rules.is_mountain(next): expansion[next] = true
			for other in rules.cells:
				if rules.cells[other]["owner"] >= 0 and rules.cells[other]["owner"] != bank["owner"]:
					expect(rules.distance(coord, other) >= 3, "Actual kingdom borders retain two intervening hexes, even for elongated starts")
		for next in rules.neighbors(capital):
			if rules.cells[next]["owner"] == bank["owner"]: inner_neighbors += 1
		expect(inner_neighbors >= 3, "The capital has defensive depth rather than occupying a tip")
		expect(expansion.size() >= 2, "Every starting shape has multiple neutral expansion tiles")
		expect(preload("res://src/game/archipelago.gd").components(owned).size() == 1, "Different footprints form one connected kingdom")
		for removed in owned:
			var rest := owned.duplicate()
			rest.erase(removed)
			expect(preload("res://src/game/archipelago.gd").components(rest).size() == 1, "Starting shapes avoid single-tile necks and fragile tendrils")
		var income: int = rules.income(bank)
		expect(income == (11 if rules.is_modern() else 7) and income - rules.upkeep(bank) == (7 if rules.is_modern() else 6), "Different starting areas preserve eleven Modern gross income and seven net income")
		sizes_on_map[owned.size()] = true
		if rules.is_modern(): starting_sizes[owned.size()] = starting_sizes.get(owned.size(), 0) + 1
		if non_ring: non_ring_starts[rules.rule_mode] += 1
	if sizes_on_map.size() > 1: mixed_size_maps += 1

func run() -> void:
	expect(Sizes.IDS == ["small", "medium", "large", "very_large", "huge"], "New maps offer Tiny, Small, Standard, Large and Huge")
	expect(Sizes.spec("large")["name"] == "Standard" and Sizes.APPROX_TILES["large"] == 250 and Sizes.spec("large")["min_land"] == 210, "Standard retains the old Large generation budget")
	expect(Sizes.spec("very_large")["name"] == "Large" and Sizes.APPROX_TILES["very_large"] == 500, "Large retains the old Very Large generation budget")
	independent_count_checks()
	var averages: Dictionary = {}
	for size_id in Sizes.IDS:
		var counts: Dictionary = {}
		var total := 0
		for mode in ["classic", "modern"]:
			var positions: Dictionary = {}
			var distances: Dictionary = {}
			var silhouettes: Dictionary = {}
			var quadrants: Dictionary = {}
			for seed_value in range(24):
				var rules = Rules.new()
				rules.rule_mode = mode
				rules.generate(seed_value, size_id)
				starting_shape_checks(rules)
				var profile := Sizes.spec(size_id)
				counts[rules.faction_count] = true
				total += rules.cells.size()
				expect(rules.faction_count >= profile["min_factions"] and rules.faction_count <= profile["max_factions"], "Size determines the kingdom count")
				expect(rules.starting_land_reachable(), "All kingdoms have passable routes or buildable bridge crossings")
				expect(rules.kingdoms.size() == rules.faction_count and rules.territory(-1) > 0, "All factions have a starting kingdom with neutral land to capture")
				var capitals: Array = []
				for faction in range(rules.faction_count):
					for kingdom in rules.kingdoms.values():
						if kingdom["owner"] == faction:
							capitals.append(kingdom["capital"])
				positions[str(capitals)] = true
				var point: Vector3 = rules.Grid.to_world(capitals[0])
				quadrants[Vector2i(1 if point.x >= 0 else -1, 1 if point.z >= 0 else -1)] = true
				var pair_distances: Array = []
				for first in range(capitals.size()):
					for second in range(first + 1, capitals.size()):
						var distance: int = rules.distance(capitals[first], capitals[second])
						pair_distances.append(distance)
						expect(distance >= 5, "Starting borders retain at least two intervening hexes")
				pair_distances.sort()
				distances[str(pair_distances)] = true
				# Coarse occupancy detects outline changes rather than single coastal specks.
				var bins: Dictionary = {}
				for coord in rules.cells:
					var world: Vector3 = rules.Grid.to_world(coord)
					bins[Vector2i(floori(world.x / 4.0), floori(world.z / 4.0))] = true
				var outline: Array = bins.keys()
				outline.sort()
				silhouettes[str(outline)] = true
				for faction in range(rules.faction_count):
					var sources := 0
					var value := 0
					var scouts := 0
					for cell in rules.cells.values():
						if cell["owner"] == faction:
							sources += int(cell["mana_source"])
							value += cell["value"]
							scouts += int(cell["unit"] == 1)
					for kingdom in rules.kingdoms.values():
						if kingdom["owner"] == faction:
							expect(kingdom["gold"] == (10 if mode == "modern" else 16) and (kingdom["hexes"].size() >= 6 and kingdom["hexes"].size() <= 9 if mode == "modern" else kingdom["hexes"].size() == 7) and scouts == 1, "Every kingdom receives a valid territory size with equal gold and one Scout")
					if mode == "modern":
						expect(value == 11 and sources == 1 and rules.get_mana(faction) == 1, "Modern starts retain balanced value and mana on every size")
				for coord in rules.cells:
					expect(rules.inside_map(coord) and rules.cells[coord]["owner"] < rules.faction_count, "Generated tiles and owners stay within the selected profile")
				var repeat = Rules.new()
				repeat.rule_mode = mode
				repeat.generate(seed_value, size_id)
				expect(repeat.cells == rules.cells and repeat.kingdoms == rules.kingdoms and repeat.rng.state == rules.rng.state and repeat.mana_by_faction == rules.mana_by_faction, "Seed and size reproduce the entire starting state")
			expect(positions.size() >= 20, "Kingdom locations vary across seeds on " + size_id)
			expect(distances.size() >= 8, "Inter-kingdom distances vary across seeds on " + size_id)
			expect(silhouettes.size() >= 16, "Overall island silhouettes vary across seeds on " + size_id)
			expect(quadrants.size() == 4, "Player faction can start in every screen quadrant on " + size_id)
		averages[size_id] = total / 48.0
		expect(counts.has(Sizes.spec(size_id)["min_factions"]) and counts.has(Sizes.spec(size_id)["max_factions"]), "Variable profiles generate both supported kingdom counts")
	print("Average tiles by size: ", averages)
	for index in range(1, Sizes.IDS.size()):
		expect(averages[Sizes.IDS[index - 1]] < averages[Sizes.IDS[index]], "Larger profiles generate larger maps")
	var original = Rules.new()
	original.generate(42)
	var explicit = Rules.new()
	explicit.generate(42, "small")
	expect(original.cells == explicit.cells and original.rng.state == explicit.rng.state, "Default generation remains Small")
	explicit.generate(42, "unknown")
	expect(explicit.map_size == "small" and explicit.cells == original.cells, "Unknown profile safely defaults to Small")
	var video = root.get_node("Video")
	var transitions: bool = video.level_transitions
	video.set_preference(&"level_transitions", false, false)
	var app = load("res://scenes/app.tscn").instantiate()
	root.add_child(app)
	await process_frame
	for child in app.menus.main_panel.get_children():
		if child is Button and child.text == "Quick Play":
			child.pressed.emit()
	expect(app.menus.screen == app.menus.Screen.SETUP and app.menus.size_choice.get_selected_metadata() == "small", "New Game opens size selection with Small selected")
	expect(app.menus.kingdom_choice.get_selected_metadata() == 4 and app.menus.size_choice.get_item_text(Sizes.IDS.find("small")) == Sizes.choice_label("small"), "Map size and kingdom count have separate controls")
	expect(app.menus.size_choice.item_count == 5, "Quick Play offers the five revised map sizes")
	for index in range(Sizes.IDS.size()):
		expect(app.menus.size_choice.get_popup().get_item_tooltip(index) == Sizes.tile_tooltip(Sizes.IDS[index]), "Every size explains its approximate tile count")
	app.menus.kingdom_choice.select(4)
	app.menus.size_choice.select(0)
	app.menus.size_choice.item_selected.emit(0)
	expect(app.menus.kingdom_choice.item_count == 5 and app.menus.kingdom_choice.get_selected_metadata() == 6, "Small retains all six selected kingdoms")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	app.menus._unhandled_input(escape)
	expect(app.menus.screen == app.menus.Screen.MAIN and app.game == null, "Escape leaves setup without starting a session")
	app.menus.show_screen(app.menus.Screen.SETUP)
	app.menus.size_choice.select(Sizes.IDS.find("large"))
	app.menus.size_choice.item_selected.emit(Sizes.IDS.find("large"))
	app.menus.kingdom_choice.select(4)
	app.menus.setup_start_button.pressed.emit()
	while app.transitioning:
		await process_frame
	var game = app.game
	expect(game.rules.map_size == "large" and game.rules.faction_count == 6, "Selected size reaches the gameplay rules")
	expect(game.view.default_zoom >= 38.0 and game.view.navigation_limits.x >= game.rules.bridge_bounds().x, "Large camera frames the actual map and can reach all bridge sites")
	game.toggle_stats()
	expect(game.stats_rows.get_child_count() == 7, "Stats lists six factions and neutral land")
	game.toggle_stats()
	var initial_cells: Dictionary = game.cells.duplicate(true)
	var initial_seed: int = game.rules.level_seed
	var initial_rng: int = game.rules.rng.state
	app.pause_game()
	app.restart_current_level()
	while app.transitioning:
		await process_frame
	expect(app.game.rules.map_size == "large" and app.game.rules.faction_count == 6 and app.game.rules.level_seed == initial_seed and app.game.cells == initial_cells and app.game.rules.rng.state == initial_rng, "Restart reproduces the selected size, factions, seed and map")
	var phases: Array = []
	app.game.faction_started.connect(func(faction: int): phases.append(faction))
	app.game.end_turn()
	while app.game.busy:
		await process_frame
	expect(phases == [1, 2, 3, 4, 5] and app.game.round_number == 2, "All five opposing kingdoms take their turn in order on Large")
	var preferences = root.get_node("Gameplay")
	var old_path: String = preferences.settings_path
	var old_mode: String = preferences.rule_mode
	preferences.settings_path = "res://artifacts/map_sizes_gameplay_test.cfg"
	app.change_rules("classic" if old_mode == "modern" else "modern")
	while app.transitioning:
		await process_frame
	expect(app.game.rules.map_size == "large" and app.game.rules.level_seed != initial_seed and app.game.rules.faction_count == 6, "Changing rules generates a fresh level while retaining map size")
	preferences.set_rules(old_mode, false)
	preferences.settings_path = old_path
	for cell in app.game.cells.values():
		if cell["owner"] in [1, 2, 3]:
			cell["owner"] = -1
	app.game.rules.rebuild_kingdoms()
	app.game.check_winner()
	expect(not app.game.game_over, "Surviving fifth and sixth kingdoms prevent premature victory")
	app.return_to_main_menu()
	while app.retiring_games > 0:
		await process_frame
	await process_frame
	await app.start_new_game(123, "large", "normal", 2)
	expect(app.game.rules.faction_count == 2 and app.game.rules.map_size == "large" and app.game.view.default_zoom >= 38.0, "Large supports an explicitly selected two-kingdom game")
	var sparse_cells: Dictionary = app.game.cells.duplicate(true)
	await app.restart_current_level()
	expect(app.game.rules.faction_count == 2 and app.game.rules.initial_kingdom_count == 2 and app.game.cells == sparse_cells, "Restart preserves the separately selected count and exact island")
	await app.return_to_main_menu()
	for size_id in ["very_large", "huge"]:
		await app.start_new_game(71, size_id, "normal", 4)
		expect(app.game.rules.map_size == size_id and app.game.rules.faction_count == 4 and app.game.cells.size() >= Sizes.spec(size_id)["min_land"], "New larger presets reach gameplay with the chosen kingdom count")
		expect(app.game.view.default_zoom >= Sizes.spec(size_id)["zoom"] and is_equal_approx(app.game.view.max_zoom, app.game.view.default_zoom * 1.08), "Larger presets fit the generated layout and keep a modest margin at maximum zoom")
		var larger_cells: Dictionary = app.game.cells.duplicate(true)
		await app.restart_current_level()
		expect(app.game.rules.map_size == size_id and app.game.cells == larger_cells, "Restart reproduces the new larger preset")
		await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	video.set_preference(&"level_transitions", transitions, false)
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	for count in [6,7,8,9]: expect(starting_sizes.has(count), "All four Modern starting sizes occur across generated maps")
	expect(non_ring_starts["classic"] > 0 and non_ring_starts["modern"] > 0 and mixed_size_maps > 0, "Both rulesets vary their shapes and Modern can mix sizes in the same match")
	print("Modern starting-size distribution: ", starting_sizes, "; non-ring starts: ", non_ring_starts, "; mixed-size maps: ", mixed_size_maps)
	print("Map size checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func independent_count_checks() -> void:
	for size_id in Sizes.IDS:
		var anchors: Array = Sizes.fallback_sites(size_id)
		for index in range(anchors.size()):
			var bounds = Rules.new()
			bounds.map_size = size_id
			for direction in Rules.DIRECTIONS:
				expect(bounds.inside_map(anchors[index] + direction), "Fallback homes stay within the size bounds")
			for other in range(index + 1, anchors.size()):
				expect(Rules.Grid.distance(anchors[index], anchors[other]) >= 5, "Bounded fallback preserves kingdom separation")
		for mode in ["classic", "modern"]:
			for count in range(2, Sizes.MAX_KINGDOMS[size_id] + 1):
				for seed_value in range(8):
					var rules = Rules.new()
					rules.rule_mode = mode
					rules.generate(seed_value, size_id, count)
					starting_shape_checks(rules)
					expect(rules.faction_count == count and rules.initial_kingdom_count == count and rules.map_size == size_id, "Explicit kingdom count is independent of map size")
					expect(rules.starting_land_reachable() and rules.territory(-1) >= 10, "Every supported count retains reachable land and expansion space")
					var capitals: Array = []
					for kingdom in rules.kingdoms.values():
						capitals.append(kingdom["capital"])
						var scouts := 0
						var value := 0
						var sources := 0
						for coord in kingdom["hexes"]:
							scouts += int(rules.cells[coord]["unit"] == 1)
							value += rules.cells[coord]["value"]
							sources += int(rules.cells[coord]["mana_source"])
						expect((kingdom["hexes"].size() >= 6 and kingdom["hexes"].size() <= 9 if mode == "modern" else kingdom["hexes"].size() == 7) and scouts == 1 and kingdom["gold"] == (10 if mode == "modern" else 16), "Independent counts preserve valid territory sizes and equal gold and units")
						if mode == "modern":
							expect(value == 11 and sources == 1 and rules.get_mana(kingdom["owner"]) == 1, "Independent counts preserve Modern resources")
					for index in range(capitals.size()):
						for other in range(index + 1, capitals.size()):
							expect(rules.distance(capitals[index], capitals[other]) >= 5, "Every selected count retains the minimum border gap")
					var repeat = Rules.new()
					repeat.rule_mode = mode
					repeat.generate(seed_value, size_id, count)
					expect(repeat.cells == rules.cells and repeat.kingdoms == rules.kingdoms and repeat.rng.state == rules.rng.state, "Seed, size and explicit count reproduce the whole starting state")
	var invalid = Rules.new()
	invalid.generate(42, "very_small", 99)
	expect(invalid.faction_count == 4 and invalid.initial_kingdom_count == 4, "Unsupported dense combinations clamp to a feasible count")
