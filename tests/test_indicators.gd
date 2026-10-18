extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func marked(view) -> Array:
	if view.overlay_root.has_node("ReachableArea"):
		return view.overlay_root.get_node("ReachableArea").get_meta("reachable")
	var result: Array = []
	for child in view.overlay_root.get_children():
		if child.get_meta("movement_role", "") == "reachable":
			result.append(child.get_meta("hex"))
	return result

func run() -> void:
	var sound = root.get_node("Sound")
	var original_mute: bool = sound.is_muted()
	sound.set_muted(true, false)
	var gameplay = root.get_node("Gameplay")
	var original: bool = gameplay.clear_indicators
	gameplay.set_clear_indicators(true, false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var grid_fixture = preload("res://src/game/hex_grid.gd")
	var ring: Dictionary = {}
	for coord in grid_fixture.DIRECTIONS:
		ring[coord] = true
	expect(game.view.overlays.area_edges(ring).size() == 24, "Ring region preserves the six edges of its unreachable central hole")
	ring[Vector2i.ZERO] = true
	expect(game.view.overlays.area_edges(ring).size() == 18, "Filling the hole removes its six inner edges")
	expect(game.view.overlays.area_edges({Vector2i.ZERO: true, Vector2i(1, 0): true}).size() == 10, "Two touching tiles omit their shared edge")
	expect(game.view.overlays.area_edges({Vector2i.ZERO: true, Vector2i(5, 0): true}).size() == 12, "Disconnected reachable patches keep separate perimeters")
	for mode in ["classic", "modern"]:
		game.rules.rule_mode = mode
		for seed_value in [42, 71, 123]:
			game.new_game(seed_value)
			for coord in game.cells:
				if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] > 0:
					game.click_hex(coord)
					break
			var targets: Dictionary = game.valid_targets.duplicate(true)
			var protection: Dictionary = preload("res://src/game/kingdom_movement.gd").unit_protection(game.view.cells, game.selected)
			expect(game.view.overlay_root.get_node("UnitProtection").get_meta("protected") == protection.keys(), "Selected unit marks exactly its defensive coverage")
			expect(game.view.overlay_root.get_node("UnitProtection").get_meta("boundary_edges") == game.view.overlays.area_edges(protection), "Protection uses one area perimeter with no internal tile borders")
			var protection_id: int = game.view.overlay_root.get_node("UnitProtection").get_instance_id()
			game.refresh_overlays()
			expect(game.view.overlay_root.get_node("UnitProtection").get_instance_id() == protection_id, "Unchanged selection retains protection geometry")
			var state: Dictionary = game.cells.duplicate(true)
			var marks: Array = marked(game.view)
			expect(marks.size() == targets.size(), "Reachable area contains every legal destination")
			var region := targets.duplicate()
			region[game.selected] = true
			var expected_edges: Array = []
			var grid = preload("res://src/game/hex_grid.gd")
			for coord in region:
				for edge in range(6):
					if not region.has(coord + grid.DIRECTIONS[edge]):
						expected_edges.append([coord, edge])
			expect(game.view.overlay_root.get_node("ReachableArea").get_meta("boundary_edges") == expected_edges, "Only exterior and hole edges are drawn, with no shared tile borders")
			for coord in marks:
				expect(targets.has(coord), "No illegal tile is advertised as reachable")
			var longest: Array = []
			for coord in targets:
				var path: Array = game.rules.movement_path(game.selected, coord, targets)
				if path.size() > longest.size():
					longest = path
			game.hovered = longest[-1]
			game.refresh_ui()
			expect(game.preview_path == longest, "Preview follows the authoritative route")
			expect(game.view.overlay_root.has_node("MovementRoute"), "Continuous route is visible")
			expect(game.view.overlay_root.get_node("MovementRoute").get_meta("arrowheads") == 1 and not game.view.overlay_root.has_node("RouteDirection"), "Route has exactly one terminal head and no intermediate arrows")
			var first_id: int = game.view.overlay_root.get_node("MovementRoute").get_instance_id()
			game.refresh_overlays()
			expect(game.view.overlay_root.get_node("MovementRoute").get_instance_id() == first_id, "Unchanged hover retains route geometry")
			game.toggle_view()
			expect(marked(game.view).size() == targets.size(), "Overhead camera retains legal reach")
			gameplay.set_clear_indicators(false, false)
			expect(game.view.overlay_root.has_node("UnitProtection"), "Protection remains available with the original movement style")
			expect(marked(game.view).is_empty() and not game.view.overlay_root.has_node("MovementRoute"), "Original indicators apply immediately")
			expect(game.valid_targets == targets and game.preview_path == longest and game.cells == state, "Style toggle preserves selection, route and rules state")
			gameplay.set_clear_indicators(true, false)
			expect(marked(game.view).size() == targets.size(), "Clear indicators restore immediately")
			game.toggle_value_heatmap()
			expect(not game.view.overlay_root.visible, "Value filter hides action indicators")
			game.toggle_value_heatmap()
			expect(game.view.overlay_root.visible and marked(game.view).size() == targets.size(), "Exiting filter restores reach")
			expect(game.view.overlay_root.has_node("UnitProtection"), "Exiting filter restores protection")
			game.hovered = game.NONE
			game.refresh_ui()
			expect(not game.view.overlay_root.has_node("MovementRoute") and marked(game.view).size() == targets.size(), "Leaving hover clears route and retains reach")
			game.cancel_action()
			expect(marked(game.view).is_empty(), "Cancellation clears reach")
			expect(not game.view.overlay_root.has_node("UnitProtection"), "Cancellation clears protection")
	# Round trip preferences through an isolated file, preserving the user's settings.
	game.new_game(42)
	for coord in game.cells:
		if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] > 0:
			game.click_hex(coord)
			break
	for coord in game.cells:
		game.hovered = coord
		game.refresh_ui()
		var intent: Dictionary = game.presenter.tile_intent(coord)
		if game.valid_targets.has(coord):
			expect(game.view.overlays.destination_color(coord) == game.view.intent_color(intent), "Reach color agrees with hovered action")
		elif coord != game.selected:
			expect(not marked(game.view).has(coord), "Blocked destination never receives a reach marker")
			expect(game.view.intent_preview != null and not game.view.intent_preview.get_meta("valid"), "Blocked hover retains the invalid action marker")
	var target := game.NONE as Vector2i
	for coord in game.valid_targets:
		if game.cells[coord]["owner"] == 0:
			target = coord
			break
	if target != game.NONE:
		game.cells[target]["unit"] = 1
		game.cells[target]["moved"] = false
		game.hovered = target
		game.view.render_cells(game.cells)
		game.refresh_ui()
		expect(game.valid_targets.has(target) and marked(game.view).has(target), "Ready friendly merge is highlighted")
		expect(game.view.overlays.destination_color(target) == game.view.intent_color({"kind": "merge"}), "Merge reach uses purple")
		game.cells[target]["moved"] = true
		game.view.render_cells(game.cells)
		game.refresh_ui()
		expect(game.valid_targets.has(target) and marked(game.view).has(target), "Moved friendly merge is highlighted")
		expect(game.presenter.tile_intent(target)["kind"] == "merge" and game.presenter.tile_intent(target)["valid"], "Moved friendly destination previews a legal merge")
		game.cells[target]["building"] = "bridge"
		game.cells[target]["owner"] = -1
		game.cells[target]["unit_owner"] = 0
		game.view.render_cells(game.cells)
		expect(game.view.overlays.destination_color(target) == game.view.intent_color({"kind": "merge"}), "Friendly bridge garrison uses merge color")
		game.cells[target]["unit_owner"] = 1
		game.view.render_cells(game.cells)
		expect(game.view.overlays.destination_color(target) == game.view.intent_color({"kind": "attack"}), "Hostile bridge garrison uses attack color")
	var saved_path: String = gameplay.settings_path
	gameplay.settings_path = "res://artifacts/test_indicator_settings.cfg"
	gameplay.set_clear_indicators(false)
	gameplay.clear_indicators = true
	gameplay.load_settings(gameplay.settings_path)
	expect(not gameplay.clear_indicators, "Original style persists across preference reload")
	gameplay.set_clear_indicators(true)
	gameplay.clear_indicators = false
	gameplay.load_settings(gameplay.settings_path)
	expect(gameplay.clear_indicators, "Clear style persists across preference reload")
	gameplay.settings_path = saved_path
	var movement = preload("res://src/game/kingdom_movement.gd")
	var origin := Vector2i.ZERO
	var friendly := Vector2i(1, 0)
	var hostile := Vector2i(-1, 0)
	var neutral := Vector2i(0, 1)
	var distant := Vector2i(2, 0)
	var fixture: Dictionary = {}
	for coord in [origin, friendly, hostile, neutral, distant]:
		fixture[coord] = game.rules.make_cell(1 if coord == hostile else -1 if coord == neutral else 0)
	fixture[origin]["unit"] = 2
	fixture[origin]["moved"] = true
	fixture[friendly]["unit"] = 3
	expect(movement.unit_protection(fixture, origin) == {origin: true, friendly: true}, "Coverage includes self and same-owner neighbours even after moving and when a stronger defender overlaps")
	var model = game.Rules.new()
	model.cells = fixture
	fixture[friendly]["unit"] = 0
	for coord in fixture:
		expect((model.defense(coord) == 2) == movement.unit_protection(fixture, origin).has(coord), "Protection agrees with actual attack defence on adjacent, hostile, neutral and distant tiles")
	fixture[origin]["owner"] = -1
	fixture[origin]["building"] = "bridge"
	fixture[origin]["unit_owner"] = 0
	expect(movement.unit_protection(fixture, origin) == {origin: true}, "A friendly neutral-bridge garrison protects only its own bridge")
	fixture[origin]["unit"] = 0
	expect(movement.unit_protection(fixture, origin).is_empty() and movement.unit_protection(fixture, game.NONE).is_empty(), "Empty and missing source tiles have no unit protection")
	for mode in ["classic", "modern"]:
		game.rules.rule_mode = mode
		game.new_game(42)
		var own := game.NONE as Vector2i
		var enemy := game.NONE as Vector2i
		for coord in game.cells:
			if game.cells[coord]["unit"] > 0:
				if game.rules.unit_faction(coord) == 0:
					own = coord
				elif enemy == game.NONE:
					enemy = coord
		game.cells[own]["moved"] = true
		game.view.render_cells(game.cells)
		game.click_hex(own, "unit")
		expect(game.selected == own and game.valid_targets.is_empty() and game.view.overlay_root.has_node("UnitProtection"), "A spent friendly unit can still show protection without offering moves")
		game.cancel_action()
		var snapshot: Dictionary = game.cells.duplicate(true)
		game.click_hex(enemy, "unit")
		expect(game.selected == game.NONE and game.inspected_unit == enemy and game.valid_targets.is_empty(), "Enemy protection inspection never selects enemy movement commands")
		expect(game.view.overlay_root.get_node("UnitProtection").get_meta("protected") == movement.unit_protection(game.view.cells, enemy).keys() and game.cells == snapshot, "Enemy click shows its actual coverage without changing game state")
		game.choose_unit(1)
		expect(not game.view.overlay_root.has_node("UnitProtection"), "Choosing a placement action clears inspected enemy protection")
		game.cancel_action()
		game.click_hex(enemy, "unit")
		game.new_game(71)
		expect(game.inspected_unit == game.NONE and not game.view.overlay_root.has_node("UnitProtection"), "New game clears transient enemy protection")
	gameplay.set_clear_indicators(original, false)
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(0.1).timeout
	sound.set_muted(original_mute, false)
	print("Movement indicator checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
