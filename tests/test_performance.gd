extends SceneTree
## Correctness and retained-object checks; no machine-dependent timing thresholds.
const Rules = preload("res://src/game/kingdom_rules.gd")
const Picker = preload("res://src/rendering/board_picker.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	for mode in ["classic", "modern"]:
		for size_id in ["very_small", "small", "medium", "large"]:
			var rules = Rules.new()
			rules.rule_mode = mode
			rules.generate(42, size_id)
			var queries = Analysis.Queries.new(rules)
			for faction in range(rules.faction_count):
				expect(queries.threats(faction) == scalar_threats(rules, faction), "Memoized AI threats equal independent per-unit routes")
				for bank in rules.kingdoms.values():
					if bank["owner"] == faction:
						expect(queries.frontier(bank["capital"]) == Analysis.frontier(rules, bank["capital"]), "Query context preserves frontier membership")
					expect(queries.bank_summary(bank) == {"income": rules.income(bank), "upkeep": rules.upkeep(bank)}, "Single-pass immutable bank accounting matches authoritative economy")
			for coord in rules.cells:
				if rules.cells[coord]["unit"] > 0:
					expect(queries.reachable_targets(coord) == rules.reachable_targets(coord), "Memoized targets retain their source-rooted route graph")
			for faction in range(rules.faction_count):
				var summary: Dictionary = rules.mana_summary(faction)
				expect(summary["amount"] == rules.get_mana(faction) and summary["capacity"] == rules.mana_capacity(faction) and summary["regeneration"] == rules.mana_regeneration(faction) and summary["income"] == rules.mana_income(faction), "Single-pass mana agrees with public queries")
			for free in [false, true]:
				rules.set_effect(0, "free_spell", free)
				for spell in rules.Spells.SPELLS:
					var expected: Dictionary = {}
					for coord in rules.cells:
						if rules.can_cast(spell, coord, 0):
							expected[coord] = true
					expect(rules.spell_targets(spell, 0) == expected, "Batched spell targets equal scalar validation: " + spell)
			# Direct fixture edits must be reflected immediately, without stale mana caches.
			for cell in rules.cells.values():
				if cell["owner"] == 0:
					cell["mana_source"] = true
					cell["tree"] = true
			rules.set_mana(0, 999)
			var capacity: int = rules.mana_capacity(0)
			for cell in rules.cells.values():
				cell["tree"] = false
			rules.clamp_mana()
			expect(rules.get_mana(0) <= capacity and rules.get_mana(0) == rules.mana_capacity(0), "Single-pass clamping respects direct source/terrain edits")
	await scene_checks()
	bridge_query_checks()
	root.get_node("Sound").stop_all()
	await create_timer(1.20).timeout
	print("Performance regression checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func bridge_query_checks() -> void:
	var rules = Rules.new()
	rules.rule_mode = "modern"
	for q in range(8):
		var coord := Vector2i(q, 0)
		rules.cells[coord] = rules.make_cell(0 if q < 3 else 1 if q > 4 else -1)
		if q in [3, 4]:
			rules.cells[coord]["building"] = "bridge"
	rules.cells[Vector2i(4, 0)]["unit"] = 1
	rules.cells[Vector2i(4, 0)]["unit_owner"] = 0
	rules.cells[Vector2i(5, 0)]["unit"] = 1
	rules.cells[Vector2i(7, 0)]["unit"] = 2
	rules.rebuild_kingdoms()
	var queries = Analysis.Queries.new(rules)
	for bank in rules.kingdoms.values():
		expect(queries.bank_summary(bank) == {"income": rules.income(bank), "upkeep": rules.upkeep(bank)}, "Single-pass bank accounting assigns supported bridge garrisons correctly")
	for faction in [0, 1]:
		expect(queries.threats(faction) == scalar_threats(rules, faction), "Region memoization preserves hostile-garrison bridge threats")
	for source in [Vector2i(4, 0), Vector2i(5, 0), Vector2i(7, 0)]:
		expect(queries.reachable_targets(source) == rules.reachable_targets(source), "Different source routes keep exact bridge movement graphs")
	rules.cells[Vector2i(4, 0)]["unit_owner"] = 1
	expect(Analysis.threats(rules, 0) == scalar_threats(rules, 0), "A fresh analysis observes direct bridge ownership edits")
	rules.cells[Vector2i(2, 0)]["barrier_by"] = 0
	expect(Analysis.threats(rules, 0) == scalar_threats(rules, 0), "A fresh analysis observes changed barrier routes")

func scalar_threats(model, faction: int) -> Dictionary:
	var result: Dictionary = {}
	for source in model.cells:
		if model.cells[source]["unit"] == 0 or model.unit_faction(source) == faction:
			continue
		var routes: Dictionary = model.friendly_routes(source)
		var destinations: Dictionary = {}
		for coord in routes:
			for next in model.neighbors(coord):
				if not routes.has(next) and not model.is_mountain(next) and not model.is_barrier(next):
					destinations[next] = true
		for target in destinations:
			if model.cells[target]["owner"] != faction and model.unit_faction(target) != faction:
				continue
			if not result.has(target):
				result[target] = {"strength": 0, "sources": []}
			result[target]["strength"] = maxi(result[target]["strength"], model.cells[source]["unit"])
			result[target]["sources"].append(source)
	return result

func scene_checks() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	game.initial_map_size = "large"
	root.add_child(game)
	game.set_process(false)
	await process_frame
	game.rules.set_effect(0, "trailblaze", true)
	game.rules.set_effect(0, "free_spell", true)
	game.refresh_ui()
	var overlay: Node = game.view.overlay_root.get_child(0)
	for repeat in range(5):
		game.refresh_ui()
	expect(game.view.overlay_root.get_child(0) == overlay, "Unchanged HUD refresh retains selection overlays")
	game.view.visible_board_changed.emit()
	game.refresh_ui()
	expect(game.view.overlay_root.get_child(0) != overlay, "Board changes invalidate retained overlays")
	var plain: StandardMaterial3D = game.view.material(Color("4b6667"))
	var double_sided: StandardMaterial3D = game.view.material(Color("4b6667"), false, true)
	expect(plain != double_sided and plain.cull_mode == BaseMaterial3D.CULL_BACK and double_sided.cull_mode == BaseMaterial3D.CULL_DISABLED, "Material cull modes have separate immutable cache entries")
	var prop := Node3D.new()
	game.view.add_capital(prop, Vector3.ZERO, Color("80ad86"))
	expect(plain.cull_mode == BaseMaterial3D.CULL_BACK, "Creating a double-sided roof cannot mutate a cached plain material")
	prop.free()
	expect(game.view.intent_arrow_mesh() == game.view.intent_arrow_mesh(), "Identical command arrows reuse their mesh")
	var first: Button = game.effect_row.get_child(0)
	var second: Button = game.effect_row.get_child(1)
	for repeat in range(10):
		game.refresh_ui()
	expect(first == game.effect_row.get_child(0) and second == game.effect_row.get_child(1), "Unchanged HUD refresh retains icon controls")
	game.rules.set_effect(0, "trailblaze", false)
	game.refresh_ui()
	expect(game.effect_row.get_child_count() == 1 and game.effect_row.get_child(0) == second, "Removing one effect retains the other's hover target")
	var mesh: Mesh
	var markers := 0
	for coord in game.view.tile_nodes:
		var relief: Node = game.view.tile_nodes[coord].get_node_or_null("Features/EventRelief")
		if relief != null:
			markers += 1
			expect(relief is MeshInstance3D and relief.get_child_count() == 0 and relief.mesh.get_surface_count() == 2, "Each marker is one mesh instance with two materials")
			if mesh == null: mesh = relief.mesh
			else: expect(mesh == relief.mesh, "Markers share their immutable mesh")
	expect(markers > 0, "Fixture contains markers")
	var capital: Vector2i = game.active_capital()
	for top_down in [false, true]:
		if game.view.top_down != top_down:
			game.toggle_view()
		var screen: Vector2 = game.view.camera.unproject_position(game.view.coord_position(capital))
		var direct: Dictionary = Picker.pick_at_screen(game.view, screen)
		expect(game.view.pick_at_screen(screen) == direct and game.view.pick_at_screen(screen) == direct, "Cached picking agrees with live query in both views")
		var returned: Dictionary = game.view.pick_at_screen(screen)
		returned["coord"] = game.NONE
		expect(game.view.pick_at_screen(screen) == direct, "Callers cannot mutate cached pick")
		game.view.change_zoom(1)
		expect(game.view.pick_at_screen(screen) == Picker.pick_at_screen(game.view, screen), "Camera change invalidates pick")
	game.cells[capital]["unit"] = 1
	game.view.render_cells(game.cells)
	var screen: Vector2 = game.view.camera.unproject_position(game.view.unit_actors[capital].global_position + Vector3(0, 0.87, 0))
	expect(game.view.pick_at_screen(screen) == Picker.pick_at_screen(game.view, screen), "Board synchronization invalidates pick")
	game.view.playback.is_animating = true
	var sprite: Sprite3D
	for child in game.view.unit_actors[capital].get_children():
		if child is Sprite3D:
			sprite = child
			break
	game.view.pick_at_screen(screen)
	sprite.position.x += 2.0
	expect(game.view.pick_at_screen(screen) == Picker.pick_at_screen(game.view, screen), "Moving actors bypass the cache")
	game.view.playback.is_animating = false
	game.queue_free()
	await process_frame
