extends SceneTree

const Rules = preload("res://src/game/kingdom_rules.gd")
var board = Rules.new()
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func fixture(owners: Dictionary) -> void:
	board.cells.clear()
	board.kingdoms.clear()
	board.ore_by_faction = {0:100,1:100,2:100,3:100}
	for coord in owners:
		board.cells[coord] = board.make_cell(owners[coord])
	board.rebuild_kingdoms()
	for kingdom in board.kingdoms.values():
		kingdom["gold"] = 100

func validate_board() -> void:
	for coord in board.cells:
		var cell: Dictionary = board.cells[coord]
		expect(cell["owner"] >= -1 and cell["owner"] <= 3, "Owner in range")
		expect(cell["unit"] >= 0 and cell["unit"] <= 3, "Unit tier in range")
		expect(not (cell["unit"] > 0 and (cell["grave"] or cell["tree"])), "Units never overlap graves or trees")
		var kingdom: Dictionary = board.kingdom_at(coord)
		if cell["owner"] == -1:
			expect(kingdom.is_empty(), "Neutral land has no kingdom")
		elif kingdom.is_empty():
			var connected := false
			for next in board.neighbors(coord):
				connected = connected or board.cells[next]["owner"] == cell["owner"]
			expect(not connected, "Only singletons lack a kingdom")
		else:
			expect(kingdom["owner"] == cell["owner"] and coord in kingdom["hexes"], "Kingdom membership matches owner")
	for capital in board.kingdoms:
		var kingdom: Dictionary = board.kingdoms[capital]
		expect(kingdom["gold"] >= 0, "Local gold never goes negative")
		expect(kingdom["hexes"].size() >= 2, "Kingdoms have at least two hexes")
		expect(board.cells[capital]["capital"] == kingdom["owner"], "Every kingdom has its own capital")
		var capital_count := 0
		for coord in kingdom["hexes"]:
			if board.cells[coord]["capital"] >= 0:
				capital_count += 1
		expect(capital_count == 1, "Exactly one capital per connected kingdom")

func run() -> void:
	# Many deterministic maps: shape bounds, equal starts, neutral expansion, variety.
	var layouts := {}
	for seed_value in range(100):
		board.generate(seed_value)
		expect(board.starting_land_reachable(), "Generated islands have bridge-reachable routes")
		expect(board.cells.size() >= 65, "Island has enough expansion space")
		expect(board.territory(-1) > board.cells.size() / 2, "Most starting land is neutral")
		expect(board.kingdoms.size() == 4, "Each faction starts with one kingdom")
		for coord in board.cells:
			expect(board.inside_map(coord), "Map fits the screen")
		for faction in range(4):
			expect(board.territory(faction) >= 6 and board.territory(faction) <= 9, "Starting territories contain six to nine provinces")
		var keys: Array = board.cells.keys()
		keys.sort()
		layouts[str(keys)] = true
		validate_board()
	expect(layouts.size() > 95, "Seeds produce varied layouts")
	board.generate(1234)
	var same: Dictionary = board.cells.duplicate(true)
	board.generate(1234)
	expect(same == board.cells, "Seed reproduces map and start")

	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var d := Vector2i(3, 0)
	var e := Vector2i(4, 0)
	# Long movement through a kingdom, then one border capture; no enemy shortcuts.
	fixture({a: 0, b: 0, c: 0, d: 0, e: -1, Vector2i(5, 0): -1})
	board.cells[a]["unit"] = 1
	expect(board.can_move(a, d), "Unit crosses multiple friendly hexes in one turn")
	expect(board.can_move(a, e), "Unit can capture a distant kingdom border")
	expect(not board.can_move(a, Vector2i(5, 0)), "Cannot chain through multiple neutral hexes")
	var path: Array = board.movement_path(a, e)
	expect(path.size() == 5 and path[0] == a and path[-1] == e, "Path preview traces friendly route and capture")
	board.cells[d]["tree"] = true
	expect(board.move_unit(a, d), "Long move succeeds")
	expect(not board.cells[d]["tree"] and board.cells[d]["moved"], "Landing clears a tree and spends action")
	expect(not board.move_unit(d, e), "Unit cannot act twice")
	fixture({a: 0, b: -1, c: 0, d: 0})
	board.cells[a]["unit"] = 1
	expect(not board.can_move(a, c), "Cannot jump across neutral land into disconnected friendly land")
	fixture({a: 0, b: 1, c: 0, d: 0})
	board.cells[a]["unit"] = 1
	expect(not board.can_move(a, c), "Cannot jump across enemy land")
	fixture({a: 0, Vector2i(0, 1): 0, Vector2i(1, 1): 0, c: 0, d: 0})
	board.cells[a]["unit"] = 1
	path = board.movement_path(a, d)
	expect(path.size() > 3, "Friendly route detours around a missing water hex")
	for index in range(path.size() - 1):
		expect(board.distance(path[index], path[index + 1]) == 1, "Every path step uses adjacent land")

	# Split treasury stays with the old capital; cut-off kingdoms start at zero.
	fixture({a: 0, b: 0, c: 0, d: 0, e: 0})
	var capital: Vector2i = board.kingdom_at(a)["capital"]
	board.kingdom_at(a)["gold"] = 37
	board.cells[c]["owner"] = 1
	board.rebuild_kingdoms()
	expect(board.kingdom_at(capital)["gold"] == 37, "Original capital retains treasury after split")
	var detached: Vector2i = e if capital.x < 2 else a
	expect(board.kingdom_at(detached)["gold"] == 0, "Detached kingdom starts without another kingdom's funds")
	expect(not board.recruit(detached, 0), "Detached kingdom cannot spend old treasury")
	board.kingdom_at(detached)["gold"] = 13
	board.cells[c]["owner"] = 0
	board.rebuild_kingdoms()
	expect(board.kingdoms.size() == 1 and board.kingdom_at(a)["gold"] == 50, "Reconnect merges treasuries exactly once")
	board.rebuild_kingdoms()
	expect(board.kingdom_at(a)["gold"] == 50, "Repeated topology update never duplicates money")

	# Actual capture severs a bridge, and a stranded soldier leaves a grave next turn.
	fixture({a: 0, b: 0, c: 0, Vector2i(1, -1): 1, Vector2i(2, -1): 1})
	board.cells[c]["unit"] = 1
	board.cells[Vector2i(1, -1)]["unit"] = 3
	expect(board.move_unit(Vector2i(1, -1), b), "Bridge can be captured by a stronger attacker")
	expect(board.kingdom_at(c).is_empty() and board.cells[c]["unit"] == 1, "Cut-off unit survives until its turn")
	expect(board.begin_turn(0) == 1, "Isolated soldier dies on next turn")
	expect(board.cells[c]["grave"] and board.cells[c]["unit"] == 0, "Death leaves a visible grave")
	board.begin_turn(0)
	expect(board.cells[c]["tree"] and not board.cells[c]["grave"], "Uncleared grave becomes a tree next owner turn")

	# Capital capture destroys stored money, while replacements keep the kingdom alive.
	fixture({a: 0, b: 0, c: 0, d: 0, Vector2i(0, -1): 1, Vector2i(1, -1): 1})
	# Author an exposed capital explicitly; automatic placement now avoids it.
	for coord in [a, b, c]: board.cells[coord]["capital"] = -1
	board.cells[a]["capital"] = 0
	board.rebuild_kingdoms()
	capital = board.kingdom_at(a)["capital"]
	board.kingdom_at(a)["gold"] = 47
	board.cells[Vector2i(0, -1)]["unit"] = 3
	expect(board.move_unit(Vector2i(0, -1), capital), "Capital can be captured")
	expect(board.kingdom_at(c)["gold"] == 0, "Captured capital's treasury is lost")
	expect(board.kingdom_at(c)["capital"] != capital, "Surviving connected land gets replacement capital")

	# Bankruptcy is local: another kingdom of the same faction can stay solvent.
	fixture({a: 0, b: 0, e: 0, Vector2i(5, 0): 0})
	board.cells[a]["unit"] = 3
	board.cells[b]["unit"] = 3
	board.kingdom_at(a)["gold"] = 0
	board.kingdom_at(e)["gold"] = 31
	expect(board.begin_turn(0) == 2, "Only unaffordable kingdom units starve")
	expect(board.cells[a]["grave"] and board.cells[b]["grave"], "Bankrupt units leave graves")
	expect(board.kingdom_at(e)["gold"] == 33, "Other kingdom keeps its funds and income")

	# Graves suppress income and can be removed by landing or recruitment.
	fixture({a: 0, b: 0, c: 0, d: 0})
	board.cells[b]["building"] = "city"
	board.cells[b]["building_tier"] = 2 # Forward hub covers the clearing/upgrade site.
	board.cells[b]["grave"] = true
	board.cells[c]["tree"] = true
	expect(board.income(board.kingdom_at(a)) == 2, "Trees and graves do not earn income")
	board.cells[d]["unit"] = 1
	expect(board.move_unit(d, b) and not board.cells[b]["grave"], "Unit clears a grave by landing")
	expect(board.recruit(c, 0) and not board.cells[c]["tree"], "Recruitment can clear a tree")
	expect(board.kingdom_at(c)["gold"] == 91, "Recruit charges local treasury and rewards clearing the tree")
	board.cells[b]["moved"] = false
	expect(board.move_unit(b, c) and board.cells[c]["unit"] == 2, "Distant equal units merge")
	expect(not board.cells[c]["moved"] and board.can_move(c, d), "Merged unit is ready to move again")
	board.cells[c]["moved"] = false
	expect(board.recruit(c, 0) and board.cells[c]["unit"] == 3, "Upgrade reaches tier three")
	expect(not board.cells[c]["moved"] and board.can_move(c, d), "Upgraded unmoved unit remains ready to move")
	expect(not board.recruit(c, 0), "Tier three cannot upgrade further")
	fixture({a: 0, b: 0, c: 0, d: 0})
	board.cells[c]["building"] = "city" # Covers the later direct Knight deployment.
	board.cells[c]["building_tier"] = 2
	expect(board.recruit(b, 0, 2), "Soldier can be recruited directly from shop")
	expect(board.cells[b]["unit"] == 2 and board.kingdom_at(b)["gold"] == 80, "Direct Soldier purchase costs twenty gold")
	expect(board.recruit(b, 0, 3) and board.kingdom_at(b)["gold"] == 60, "Knight upgrade charges the twenty-gold price difference")
	expect(board.move_unit(b, c), "Soldier upgraded to Knight can move immediately")
	expect(not board.move_unit(c, d), "Upgrade does not grant a second movement")
	expect(board.recruit(d, 0, 3) and board.kingdom_at(d)["gold"] == 20, "Direct Knight purchase costs forty gold")
	expect(not board.recruit(a, 0, 4) and not board.recruit(a, 0, -1), "Invalid shop tiers are rejected")
	board.kingdom_at(a)["gold"] = 9
	expect(not board.recruit(a, 0, 1), "Direct recruitment checks local funds")
	fixture({a: 0, b: 0, c: 0, d: 0})
	board.cells[b]["building"] = "city"
	board.cells[b]["building_tier"] = 2
	board.cells[b]["unit"] = 1
	expect(board.recruit(b, 0, 2) and board.move_unit(b, c), "Scout upgraded to Soldier can move in the same turn")
	var upgrade_gold: int = board.kingdom_at(c)["gold"]
	expect(board.recruit(c, 0, 3) and board.cells[c]["unit"] == 3 and board.kingdom_at(c)["gold"] == upgrade_gold - 20, "A moved Soldier can upgrade for the normal twenty-gold difference")
	expect(board.cells[c]["moved"] and board.reachable_targets(c).is_empty(), "Upgrading a moved Soldier preserves its spent action")
	for mode in ["modern"]:
		board.rule_mode = mode
		for tier in [1, 2]:
			for on_bridge in [false, true]:
				if on_bridge and mode == "classic":
					continue
				for receiver_moved in [false, true]:
					fixture({a: 0, b: 0, c: 0, d: 0})
					board.cells[b]["unit"] = tier
					board.cells[c]["unit"] = tier
					board.cells[c]["moved"] = receiver_moved
					if on_bridge:
						board.cells[c]["building"] = "bridge"
						board.cells[c]["owner"] = -1
						board.cells[c]["unit_owner"] = 0
						board.rebuild_kingdoms()
					if receiver_moved:
						expect(not board.can_move(c, b), "Moved unit cannot initiate a merge")
					expect(board.move_unit(b, c) and board.cells[c]["unit"] == tier + 1, "Ready unit merges into an equal-tier ally on land or bridge in " + mode)
					expect(board.cells[b]["unit"] == 0 and board.cells[c]["moved"] == receiver_moved and board.can_move(c, d) == not receiver_moved, "Merge consumes source and preserves the receiving unit's movement status")
	board.rule_mode = "modern"

	# Construction, adjacent defense, strict strength, and captured building removal.
	fixture({a: 0, b: 0, c: 0, d: 1, e: 1, Vector2i(5, 0): 1})
	expect(board.build_structure(b, 0, "city"), "City can be built on clear land")
	expect(board.income(board.kingdom_at(a)) == 3, "City provides recruitment without an income bonus")
	expect(board.kingdom_at(a)["gold"] == 75, "City costs twenty-five local gold")
	expect(not board.build_structure(b, 0, "tower"), "Cannot stack buildings")
	expect(board.can_recruit(b, 0), "Cities allow recruitment on their own tile")
	expect(not board.build_structure(a, 0, "city"), "Cannot build over a capital")
	board.cells[c]["tree"] = true
	expect(not board.build_structure(c, 0, "tower"), "Trees must be cleared before construction")
	board.cells[c]["tree"] = false
	board.cells[c]["grave"] = true
	expect(not board.build_structure(c, 0, "city"), "Graves must be cleared before construction")
	board.cells[c]["grave"] = false
	expect(not board.build_structure(e, 0, "city"), "Cannot construct on enemy land")
	expect(board.build_structure(c, 0, "tower"), "Tower can be built")
	expect(board.upgrade_building(c, 0), "Tier-two tower provides Knight-level protection")
	expect(board.defense(b) == 2 and board.defense(c) == 2, "Tower protects self and adjacent friendly hexes")
	board.cells[d]["unit"] = 2
	expect(not board.can_move(d, c), "Equal strength cannot capture tower")
	board.cells[d]["unit"] = 3
	expect(board.move_unit(d, c) and board.cells[c]["building"] == "", "Stronger unit captures and destroys tower")
	board.cells[c]["moved"] = false
	expect(board.move_unit(c, b) and board.cells[b]["building"] == "city", "Captured city survives as a recruitment hub")

	# Tree spread cannot overwrite graves, units, buildings or capitals.
	fixture({a: -1, b: -1, c: -1, d: -1, Vector2i(0, 1): 0, Vector2i(1, 1): 0})
	board.cells[a]["tree"] = true
	board.cells[c]["building"] = "city"
	board.cells[d]["grave"] = true
	board.cells[Vector2i(1, 1)]["unit"] = 1
	for iteration in range(50):
		board.spread_trees()
	expect(board.cells[b]["tree"], "Trees eventually spread into eligible neighboring land")
	expect(not board.cells[c]["tree"] and not board.cells[d]["tree"], "Spread respects buildings and graves")
	expect(not board.cells[Vector2i(0, 1)]["tree"] and not board.cells[Vector2i(1, 1)]["tree"], "Spread respects capitals and units")

	# Full automated games exercise captures, splits, new capitals and economic changes.
	for seed_value in range(5):
		board.generate(seed_value + 2000)
		for turn in range(40):
			for faction in range(4):
				board.ai_turn(faction)
			board.spread_trees()
			validate_board()

	# Exercise the actual scene's interaction modes and asynchronous turn flow.
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	expect(game.view.camera is Camera3D and game.view.tile_nodes.size() == game.cells.size(), "Scene has a 3D camera and one 3D tile per hex")
	expect(not game.stats_shade.visible and not game.shop_panel.visible and not game.world_tip.visible, "Main screen starts without expanded panels or tooltips")
	game.recruit_button.pressed.emit()
	expect(game.shop_panel.visible and game.shop_items.get_child_count() == 3, "Recruit button opens all three unit choices")
	for button in game.shop_items.get_children():
		expect(not button.tooltip_text.is_empty(), "Every unit card provides a cost and description tooltip")
	game.shop_items.get_child(1).pressed.emit()
	expect(game.action_mode == "recruit" and game.recruit_tier == 2 and not game.shop_panel.visible, "Selecting Soldier activates placement and closes its list")
	game.cancel_action()
	game.build_button.pressed.emit()
	expect(game.shop_panel.visible and game.shop_items.get_child_count() == 3, "Build button opens tower, city and bridge choices")
	game.shop_items.get_child(0).pressed.emit()
	expect(game.action_mode == "tower" and not game.shop_panel.visible, "Tower card activates building placement")
	game.cancel_action()
	game.toggle_stats()
	expect(game.stats_shade.visible and not game.view.controls_enabled, "Stats menu opens separately and blocks camera movement")
	game.toggle_stats()
	expect(not game.stats_shade.visible and game.view.controls_enabled, "Closing stats returns to play")
	var old_yaw: float = game.view.yaw
	var old_pitch: float = game.view.pitch
	var old_zoom: float = game.view.zoom
	var rotation_press := InputEventMouseButton.new()
	rotation_press.button_index = MOUSE_BUTTON_RIGHT
	rotation_press.pressed = true
	game._input(rotation_press)
	game._unhandled_input(rotation_press)
	var rotation_drag := InputEventMouseMotion.new()
	rotation_drag.relative = Vector2(80, 35)
	game._input(rotation_drag)
	expect(game.view.rotating and game.view.yaw != old_yaw and game.view.pitch != old_pitch, "Right-drag rotates and tilts camera")
	rotation_press.pressed = false
	game._input(rotation_press)
	expect(not game.view.rotating, "Right release always ends orbit")
	var scroll_event := InputEventMouseButton.new()
	scroll_event.button_index = MOUSE_BUTTON_WHEEL_UP
	scroll_event.pressed = true
	game._unhandled_input(scroll_event)
	game.view.navigation._process(0.1)
	expect(game.view.zoom < old_zoom, "Scroll wheel smoothly zooms in")
	game.view.pan(Vector2(1, -1), 0.1)
	expect(game.view.focus != Vector3.ZERO, "Camera pans relative to its orientation")
	var focus_before: Vector3 = game.view.focus
	var zoom_before: float = game.view.zoom
	var yaw_before: float = game.view.yaw
	game.toggle_view()
	expect(game.view.top_down and game.view.pitch > 1.56, "Top-down button restores overhead view")
	expect(game.view.focus == focus_before and game.view.zoom == zoom_before, "Top-down preserves camera position and zoom")
	game.toggle_view()
	expect(not game.view.top_down and game.view.yaw == yaw_before, "Returning to 3D restores previous camera angle")
	for angle in [Vector2(0.0, 0.92), Vector2(1.3, 0.76), Vector2(-2.4, 1.1), Vector2(0.0, 1.569)]:
		game.view.yaw = angle.x
		game.view.pitch = angle.y
		game.view.update_camera()
		for unit in game.view.units:
			var projected: Vector2 = game.view.camera.unproject_position(unit.global_position)
			expect(game.view.hex_at_screen(projected) == unit.get_parent().get_meta("hex"), "Billboard unit picks correctly from rotated and top-down cameras")
	game.center_camera()
	expect(game.view.focus == game.view.map_center and game.view.zoom == game.view.default_zoom, "Center button restores framing fitted to the generated world")
	var view_rect: Rect2 = game.view_button.get_global_rect()
	expect(view_rect.position.x > 800 and view_rect.end.x <= 1280, "Camera buttons fit at top right")
	expect(game.recruit_button.get_global_rect().position.y > 650 and game.end_button.get_global_rect().position.x > 1000, "Recruitment and turn buttons occupy opposite bottom corners")
	game.toggle_action("tower")
	expect(game.action_mode == "tower", "Tower action is exposed in UI")
	game.toggle_action("city")
	expect(game.action_mode == "city", "City action replaces tower action")
	game.toggle_action("city")
	expect(game.action_mode == "", "Repeating action cancels it")
	var owned: Array = game.active_kingdom()["hexes"]
	game.active_kingdom()["gold"] = 16
	game.toggle_action("tower")
	var tower_hex := Rules.NONE
	for coord in owned:
		if game.rules.can_build(coord, 0, "tower"):
			tower_hex = coord
			game.click_hex(coord)
			break
	expect(tower_hex != Rules.NONE and game.cells[tower_hex]["building"] == "tower", "Tower can be built through a UI action")
	expect(game.active_kingdom()["gold"] == 1, "Construction UI spends selected kingdom funds")
	var roof_point: Vector2 = game.view.camera.unproject_position(game.view.coord_position(tower_hex) + Vector3(0, 0.98, 0))
	expect(game.view.hex_at_screen(roof_point) == tower_hex, "Clicking the visible tower roof selects its hex")
	game.active_kingdom()["gold"] = 25
	game.toggle_action("city")
	var city_hex := Rules.NONE
	for coord in owned:
		if game.rules.can_build(coord, 0, "city"):
			city_hex = coord
			game.click_hex(coord)
			break
	expect(city_hex != Rules.NONE and game.cells[city_hex]["building"] == "city", "City can be built through a UI action")
	expect(game.money_label.text == "0 G", "UI reflects local treasury after construction")
	roof_point = game.view.camera.unproject_position(game.view.coord_position(city_hex) + Vector3(0, 0.90, 0))
	expect(game.view.hex_at_screen(roof_point) == city_hex, "Clicking the visible city roof selects its hex")
	var scout := Rules.NONE
	for coord in owned:
		if game.cells[coord]["unit"] > 0:
			scout = coord
	game.click_hex(scout)
	expect(game.selected == scout and not game.valid_targets.is_empty(), "Clicking a scout exposes reachable targets")
	game.active_kingdom()["gold"] = 10
	game.choose_unit(2)
	game.click_hex(scout)
	expect(game.cells[scout]["unit"] == 2 and not game.cells[scout]["moved"], "UI upgrade preserves Scout's movement")
	expect(game.selected == scout and game.action_mode == "" and not game.valid_targets.is_empty(), "UI upgrade immediately selects the ready Soldier")
	var before: int = game.rules.territory(0)
	for target in game.valid_targets:
		if game.cells[target]["owner"] == -1 and game.cells[target].get("event", "") == "":
			await game.click_hex(target)
			break
	expect(game.rules.territory(0) == before + 1, "UI click captures neutral territory")
	await game.end_turn()
	expect(game.round_number == 2 and not game.busy, "Opponent turns return control to player")
	game.new_game()
	expect(game.round_number == 1 and not game.game_over and game.action_mode == "", "Restart resets UI and game state")
	for cell in game.cells.values():
		if cell["owner"] > 0:
			cell["owner"] = -1
	game.check_winner()
	expect(game.game_over and game.message.contains("Victory"), "Defeating rivals wins even with neutral land remaining")
	for mode in ["modern"]:
		game.new_game()
		game.rules.rule_mode = mode
		game.rules.faction_count = 6
		game.rules.cells.clear()
		game.rules.kingdoms.clear()
		for coord in [Vector2i.ZERO, Vector2i(0, 1)]:
			game.cells[coord] = game.rules.make_cell(0)
		for faction in range(1, 6):
			var singleton := Vector2i(faction * 4, 0)
			game.cells[singleton] = game.rules.make_cell(faction)
			game.cells[singleton]["unit"] = 1
		game.cells[Vector2i(20, 1)] = game.rules.make_cell(5)
		game.rules.rebuild_kingdoms()
		game.check_winner()
		expect(not game.game_over, "One remaining enemy capital prevents victory in either ruleset, including the sixth faction")
		game.cells.erase(Vector2i(20, 1))
		game.rules.rebuild_kingdoms()
		game.check_winner()
		expect(game.game_over and game.message.contains("Victory") and game.rules.territory(1) == 1 and game.rules.has_units(5), "Enemy singletons and stranded troops cannot prevent victory once all enemy capitals are gone")
	for mode in ["modern"]:
		for building in ["", "city", "tower", "monument"]:
			game.new_game()
			game.rules.rule_mode = mode
			game.cells.clear()
			game.rules.kingdoms.clear()
			game.cells[Vector2i.ZERO] = game.rules.make_cell(0)
			game.cells[Vector2i.ZERO]["building"] = building
			for coord in [Vector2i(4, 0), Vector2i(5, 0)]:
				game.cells[coord] = game.rules.make_cell(1)
			game.rules.rebuild_kingdoms()
			game.check_winner()
			expect(game.game_over and game.message.contains("fallen") and game.rules.territory(0) == 1, "An isolated province cannot prevent defeat, including a remaining %s in %s" % [building, mode])
		game.new_game()
		game.rules.rule_mode = mode
		game.cells.clear()
		game.rules.kingdoms.clear()
		for coord in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(4, 0), Vector2i(5, 0)]:
			game.cells[coord] = game.rules.make_cell(0 if coord.x < 2 else 1)
		game.rules.rebuild_kingdoms()
		game.check_winner()
		expect(not game.game_over and game.rules.has_capital(0), "A surviving two-province kingdom keeps the player alive in %s" % mode)
	game.new_game()
	for cell in game.cells.values():
		if cell["owner"] == 0:
			cell["owner"] = -1
	game.check_winner()
	expect(game.game_over and game.message.contains("fallen"), "Losing all owned land triggers defeat")
	print("Game checks: %d passed, %d failed" % [checks - failures, failures])
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	# Let the audio mixing thread release stopped ambience and one-shot playback.
	await create_timer(1.20).timeout
	quit(1 if failures else 0)
