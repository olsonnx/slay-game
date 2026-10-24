extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Spells = preload("res://src/game/spell_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func test_mana_scaling() -> void:
	var rules = Rules.new()
	rules.rule_mode = "modern"
	for index in range(9):
		var coord := Vector2i(index * 3, 0)
		rules.cells[coord] = rules.make_cell(0)
		rules.cells[coord]["mana_source"] = true
		expect(rules.mana_regeneration(0) == 1 + floori((index + 1) / 4.0), "Regeneration changes at four and eight sources, including disconnected land")
	rules.cells[Vector2i.ZERO]["capital"] = 0
	rules.cells[Vector2i.ZERO]["tree"] = true
	expect(rules.mana_capacity(0) == 10, "Capital and tree bonuses do not stack")
	rules.cells[Vector2i(3, 0)]["tree"] = true
	expect(rules.mana_capacity(0) == 11 and rules.mana_source_count(0) == 9, "Wooded sources raise capacity without adding to source count")
	rules.set_mana(0, 11)
	rules.clear_terrain(Vector2i(3, 0), {})
	expect(rules.get_mana(0) == 10, "Clearing a wooded source clamps stored mana to reduced capacity")
	rules.cells[Vector2i(3, 0)]["tree"] = true
	expect(rules.get_mana(0) == 10, "Tree regrowth does not restore discarded mana")
	rules.set_mana(0, 0)
	rules.begin_turn(0)
	expect(rules.get_mana(0) == 3, "Eight or more sources regenerate three mana in one faction turn")
	rules.set_mana(0, rules.mana_capacity(0) - 1)
	expect(rules.mana_income(0) == 1, "Forecast caps regeneration at remaining storage")

func test_knight_duels() -> void:
	for mode in ["modern"]:
		for tier in range(1, 4):
			var rules = Rules.new()
			rules.rule_mode = mode
			for x in range(4):
				rules.cells[Vector2i(x, 0)] = rules.make_cell(0 if x < 2 else 1)
			rules.cells[Vector2i.ZERO]["capital"] = 0
			rules.cells[Vector2i(2, 0)]["capital"] = 1
			rules.rebuild_kingdoms()
			var source := Vector2i(1, 0)
			var target := Vector2i(2, 0)
			rules.cells[source]["unit"] = tier
			rules.cells[target]["unit"] = tier
			if tier < 3:
				expect(not rules.can_move(source, target), "Equal Scouts and Soldiers cannot attack each other")
				continue
			var banks: Dictionary = rules.kingdoms.duplicate(true)
			var protected := Vector2i(1, 1)
			rules.cells[protected] = rules.make_cell(1)
			expect(rules.defense(protected) == 2 and rules.can_move(source, protected), "A Knight can breach another Knight's adjacent protection")
			rules.cells[source]["unit"] = 2
			expect(not rules.can_move(source, protected), "Knight protection still blocks Soldiers on adjacent provinces")
			rules.cells[source]["unit"] = 3
			rules.cells.erase(protected)
			rules.cells[target]["fortified"] = true
			rules.cells[target]["fortified_by"] = 1
			var blocked: Dictionary = rules.perform_move(source, target)
			expect(blocked["kind"] == "blocked_attack" and rules.cells[target]["unit"] == 3 and rules.cells[source]["unit"] == 3, "Ward absorbs Knight duel before either unit dies")
			rules.cells[source]["moved"] = false
			var action: Dictionary = rules.perform_move(source, target)
			expect(action["kind"] == "knight_duel" and not action["capture"] and action["annexed"].is_empty(), "Knight duel never records capture or surrender")
			expect(rules.cells[source]["unit"] == 0 and rules.cells[target]["unit"] == 0 and rules.cells[source]["grave"] and rules.cells[target]["grave"], "Both Knights die and leave graves")
			expect(rules.cells[source]["owner"] == 0 and rules.cells[target]["owner"] == 1 and rules.cells[target]["capital"] == 1 and rules.kingdoms == banks, "Knight duel preserves ownership, capitals and treasury")
	var bridge_rules = Rules.new()
	bridge_rules.rule_mode = "modern"
	bridge_rules.cells[Vector2i.ZERO] = bridge_rules.make_cell(0)
	bridge_rules.cells[Vector2i(1, 0)] = bridge_rules.make_cell()
	bridge_rules.cells[Vector2i.ZERO]["unit"] = 3
	bridge_rules.cells[Vector2i(1, 0)]["building"] = "bridge"
	bridge_rules.cells[Vector2i(1, 0)]["unit"] = 3
	bridge_rules.cells[Vector2i(1, 0)]["unit_owner"] = 1
	var bridge_duel: Dictionary = bridge_rules.perform_move(Vector2i.ZERO, Vector2i(1, 0))
	expect(bridge_duel["kind"] == "knight_duel" and bridge_rules.cells[Vector2i(1, 0)]["unit"] == 0, "Knights can mutually destroy hostile bridge garrisons")
	expect(bridge_rules.is_bridge(Vector2i(1, 0)) and bridge_rules.cells[Vector2i(1, 0)]["owner"] == -1 and not bridge_rules.cells[Vector2i(1, 0)]["grave"], "Bridge duel preserves neutral wood and leaves no bridge grave")

func run() -> void:
	test_mana_scaling()
	test_knight_duels()
	for seed_value in range(100):
		var rules = Rules.new()
		rules.rule_mode = "modern"
		rules.generate(seed_value)
		expect(rules.starting_land_reachable(), "Mountain generation preserves routes between all starting kingdoms and neutral objectives")
		var visited: Dictionary = {}
		var groups := 0
		for coord in rules.cells:
			if not rules.is_mountain(coord) or visited.has(coord):
				continue
			groups += 1
			var pending := [coord]
			var count := 0
			visited[coord] = true
			while not pending.is_empty():
				var peak: Vector2i = pending.pop_back()
				count += 1
				var cell: Dictionary = rules.cells[peak]
				expect(cell["owner"] == -1 and not cell["mana_source"] and not cell["tree"] and cell["value"] == 0, "Mountains are neutral, barren and preserve mana sources")
				for next in rules.neighbors(peak):
					if rules.is_mountain(next) and not visited.has(next):
						visited[next] = true
						pending.append(next)
			expect(count >= 2 and count <= 5, "Mountain ranges consist of two to five adjacent tiles")
		expect(groups <= 6, "Generated Modern maps contain a bounded number of mountain ridges")
		for faction in range(4):
			expect(rules.territory(faction) >= 6 and rules.territory(faction) <= 9 and rules.mana_capacity(faction) == 2 and rules.get_mana(faction) == 1 and rules.mana_income(faction) == 1, "Each faction starts with one mana and a two-capacity capital source")
	var rules = Rules.new()
	rules.rule_mode = "modern"
	for coord in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(4, 0), Vector2i(4, 1)]:
		rules.cells[coord] = rules.make_cell(0)
	rules.cells[Vector2i(1, 0)] = rules.make_cell()
	rules.cells[Vector2i(1, 0)]["mountain"] = true
	rules.cells[Vector2i(1, 0)]["value"] = 0
	rules.cells[Vector2i(2, 0)] = rules.make_cell()
	rules.cells[Vector2i(0, 0)]["mana_source"] = true
	rules.cells[Vector2i(4, 0)]["mana_source"] = true
	rules.rebuild_kingdoms()
	rules.set_mana(0, 1)
	for kingdom in rules.kingdoms.values():
		kingdom["gold"] = 100
	expect(rules.mana_capacity(0) == 4 and rules.get_mana(0) == 1, "Capacity includes capital sources across disconnected kingdoms")
	rules.begin_turn(0)
	expect(rules.get_mana(0) == 2, "Faction regenerates only one mana despite multiple kingdoms and sources")
	rules.begin_turn(0)
	expect(rules.get_mana(0) == 3, "Two sources still regenerate one mana per turn")
	rules.set_mana(0, 4)
	expect(rules.cast_spell("summon", Vector2i(0, 1), 0) and rules.get_mana(0) == 2, "Summon spends two from the shared faction pool")
	expect(rules.cast_spell("summon", Vector2i(4, 1), 0) and rules.get_mana(0) == 0, "A distant kingdom spends the same pool")
	expect(rules.cells[Vector2i(4, 1)]["unit"] == 1 and not rules.cells[Vector2i(4, 1)]["moved"] and rules.upkeep(rules.kingdom_at(Vector2i(4, 1))) == rules.Catalog.unit_upkeep(1), "Summoned Scouts are ready and have normal upkeep")
	expect(not rules.cast_spell("summon", Vector2i(0, 1), 0), "Summon cannot stack units on an occupied province")
	expect(not Spells.SPELLS.has("renewal") and not rules.can_cast("renewal", Vector2i(0, 0), 0), "Renewal is removed from the catalog and command API")
	rules.begin_turn(0)
	expect(rules.get_mana(0) == 1 and rules.mana_income(0) == 1, "Empty faction pool recovers one mana per turn")
	rules.begin_turn(0)
	rules.cells[Vector2i(4, 0)]["owner"] = 1
	rules.rebuild_kingdoms()
	expect(rules.mana_capacity(0) == 2 and rules.get_mana(0) == 2 and rules.mana_capacity(1) == 1 and rules.get_mana(1) == 0, "A lost capital source becomes an ordinary source; capture never creates stored mana")
	rules.cells[Vector2i(0, 0)]["owner"] = 1
	rules.rebuild_kingdoms()
	expect(rules.get_mana(0) == 0 and rules.mana_capacity(0) == 0, "Losing every source empties faction mana")
	rules.begin_turn(0)
	expect(rules.get_mana(0) == 0, "No sources means no usable regenerated mana")
	rules.cells[Vector2i(0, 0)]["owner"] = 0
	rules.rebuild_kingdoms()
	rules.set_mana(0, 1)
	rules.cells[Vector2i(0, 1)]["unit"] = 3
	var mountain := Vector2i(1, 0)
	var before: Dictionary = rules.cells[mountain].duplicate(true)
	expect(not rules.can_move(Vector2i(0, 1), mountain) and not rules.reachable_targets(Vector2i(0, 1)).has(Vector2i(2, 0)), "Mountains cannot be entered or crossed")
	expect(not rules.recruit(mountain, 0) and not rules.can_build(mountain, 0, "bridge") and not rules.can_develop(mountain, 0), "Mountains cannot recruit, develop or be replaced by bridges")
	for spell in Spells.SPELLS:
		expect(not rules.cast_spell(spell, mountain, 0), "Spells cannot summon on or destroy mountains")
	expect(rules.cells[mountain] == before, "Rejected actions leave mountain terrain unchanged")
	for value in range(1, 6):
		rules.cells[Vector2i(0, 0)]["value"] = value
		expect(rules.development_cost(Vector2i(0, 0)) == [2, 8, 18, 32, 50][value - 1], "Development uses much lower quadratic prices")
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	expect(game.mana_label.text == "1 / 2" and game.mana_income_label.text == "+1", "HUD shows capital capacity and effective regeneration")
	game.rules.set_mana(0, 2)
	game.refresh_ui()
	game.choose_spell("summon")
	var site := game.NONE as Vector2i
	for coord in game.valid_targets:
		site = coord
		break
	game.hovered = site
	game.refresh_ui()
	expect(game.view.intent_preview.has_node("GhostUnit"), "Summon previews its Scout on the target tile")
	game.click_hex(site)
	expect(game.cells[site]["unit"] == 1 and not game.cells[site]["moved"] and game.selected == site and game.mana_label.text == "0 / 2" and game.mana_income_label.text == "+1", "Player Summon creates, selects and readies a Scout and updates mana forecast")
	for coord in game.cells:
		if game.rules.is_mountain(coord):
			game.inspect_province(coord)
			expect(game.province_view.title.text == "Mountains" and not game.province_view.develop_button.visible, "Mountain inspector clearly exposes restrictions")
			var features: Node3D = game.view.tile_nodes[coord].get_node("Features")
			expect(features.get_child_count() > 0 and game.view.hex_at_screen(game.view.camera.unproject_position(game.view.coord_position(coord))) == coord, "Mountain terrain remains visible and pickable within its own hex")
			break
	var picking_fixture: Dictionary = {Vector2i.ZERO: game.rules.make_cell()}
	picking_fixture[Vector2i.ZERO]["mountain"] = true
	for neighbor in game.rules.DIRECTIONS:
		picking_fixture[neighbor] = game.rules.make_cell()
	game.view.render_cells(picking_fixture)
	for angle in [Vector2(0.18, 0.92), Vector2(1.3, 0.76), Vector2(-2.4, 0.44), Vector2(0, 1.569)]:
		game.view.yaw = angle.x
		game.view.pitch = angle.y
		game.view.update_camera()
		for neighbor in game.rules.DIRECTIONS:
			var screen: Vector2 = game.view.camera.unproject_position(game.view.coord_position(neighbor))
			expect(game.view.pick_at_screen(screen)["coord"] == neighbor, "A mountain cannot intercept clicks on neighboring land at any camera angle")
		expect(game.view.hex_at_screen(game.view.camera.unproject_position(Vector3.ZERO)) == Vector2i.ZERO, "Mountain's own tile can still be inspected at each angle")
	game.view.reset_camera()
	game.view.render_cells(game.cells)
	game.cancel_action()
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	game.rules.mana_by_faction.clear()
	for coord in [Vector2i(-1, 0), Vector2i(0, 0)]:
		game.cells[coord] = game.rules.make_cell(0)
	for coord in [Vector2i(1, 0), Vector2i(2, 0), Vector2i(5, 0)]:
		game.cells[coord] = game.rules.make_cell(1)
		game.cells[coord]["mana_source"] = true
	game.cells[Vector2i(-1, 0)]["capital"] = 0
	game.cells[Vector2i(-1, 0)]["mana_source"] = true
	game.cells[Vector2i(1, 0)]["capital"] = 1
	game.cells[Vector2i(0, 0)]["unit"] = 2
	game.rules.rebuild_kingdoms()
	game.rules.set_mana(0, 1)
	game.rules.set_mana(1, 3)
	game.active_hex = Vector2i(-1, 0)
	game.view.render_cells(game.cells)
	game.refresh_ui()
	game.click_hex(Vector2i(0, 0), "unit")
	game.click_hex(Vector2i(1, 0))
	expect(game.rules.get_mana(1) == 1 and game.rules.mana_capacity(0) == 4, "Castle capture transfers source capacity and clamps enemy shared mana")
	await create_timer(0.05).timeout
	game.cancel_action()
	await process_frame
	expect(game.rules.get_mana(1) == 3 and game.rules.mana_capacity(0) == 2 and game.rules.get_mana(0) == 1, "Cancelling a capture restores both factions' mana pools and source capacities")
	game.cancel_action()
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for x in range(4):
		game.cells[Vector2i(x, 0)] = game.rules.make_cell(0 if x < 2 else 1)
	game.cells[Vector2i.ZERO]["capital"] = 0
	game.cells[Vector2i(2, 0)]["capital"] = 1
	game.rules.rebuild_kingdoms()
	game.cells[Vector2i(1, 0)]["unit"] = 3
	game.cells[Vector2i(2, 0)]["unit"] = 3
	game.active_hex = Vector2i.ZERO
	game.view.render_cells(game.cells)
	game.refresh_ui()
	var duel_before: Dictionary = game.cells.duplicate(true)
	game.click_hex(Vector2i(1, 0), "unit")
	game.click_hex(Vector2i(2, 0))
	await create_timer(0.05).timeout
	game.cancel_action()
	await process_frame
	expect(game.cells == duel_before and not game.view.is_animating, "Cancelling Knight playback restores both Knights, territory and actions")
	var duel_stages: Dictionary = {}
	game.view.motion_stage.connect(func(action: Dictionary, stage: String):
		if action["kind"] == "knight_duel" and stage == "impact":
			duel_stages["impact"] = game.view.cells[Vector2i(1, 0)]["unit"] == 0 and game.view.cells[Vector2i(2, 0)]["unit"] == 0 and game.view.cells[Vector2i(2, 0)]["capital"] == 1)
	game.click_hex(Vector2i(1, 0), "unit")
	await game.click_hex(Vector2i(2, 0))
	expect(duel_stages.get("impact", false), "Knight playback removes both units at impact and preserves the defending castle")
	expect(game.view.cells == game.cells and not game.busy and not game.game_over, "Knight duel playback finishes in authoritative state without ending the game")
	game.view.configure_map("large", Vector2(40, 40))
	game.view.zoom = game.view.max_zoom
	game.view.pitch = 0.44
	game.view.update_camera()
	var backdrop: CanvasLayer = game.view.get_node("VoidBackdrop")
	expect(backdrop.layer < 0 and backdrop.get_child(0).mouse_filter == Control.MOUSE_FILTER_IGNORE, "Void backdrop stays behind the board and cannot intercept input")
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Resources and terrain checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
