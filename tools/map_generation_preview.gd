extends SceneTree
## Render a reproducible overview of six Large starts, using actual generated cells.
const Rules = preload("res://src/game/kingdom_rules.gd")
const Grid = preload("res://src/game/hex_grid.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const Sizes = preload("res://src/game/map_sizes.gd")

class Overview extends Node2D:
	var maps: Array = []
	var size_id := "large"

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 1000), Color("172b34"))
		draw_string(ThemeDB.fallback_font, Vector2(30, 42), "%s worlds · six different seeds" % Sizes.spec(size_id)["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("e6ebdf"))
		for index in range(maps.size()):
			var rules = maps[index]
			var panel := Vector2(20 + (index % 3) * 475, 65 + (index / 3) * 460)
			draw_rect(Rect2(panel, Vector2(460, 445)), Color("203945"))
			draw_string(ThemeDB.fallback_font, panel + Vector2(16, 30), "Seed %d · %d provinces" % [rules.level_seed, rules.cells.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color("d8e4dd"))
			var origin := panel + Vector2(230, 238)
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			for coord in rules.cells:
				var at: Vector3 = Grid.to_world(coord)
				low = low.min(Vector2(at.x, at.z))
				high = high.max(Vector2(at.x, at.z))
			var center_world := (low + high) * 0.5
			var span := high - low + Vector2.ONE * 3.0
			var scale := minf(420.0 / span.x, 350.0 / span.y)
			for coord in rules.cells:
				var world := Grid.to_world(coord)
				var center := origin + (Vector2(world.x, world.z) - center_world) * scale
				var polygon := PackedVector2Array()
				for corner in range(6):
					var angle := PI / 6.0 + corner * TAU / 6.0
					polygon.append(center + Vector2(cos(angle), sin(angle)) * scale * 0.96)
				var cell: Dictionary = rules.cells[coord]
				var color: Color = Color("8b9980") if cell["owner"] < 0 else Catalog.TERRAIN_COLORS[cell["owner"]]
				if cell["mountain"]:
					color = Color("596b74")
				draw_colored_polygon(polygon, color)
				if cell["capital"] >= 0:
					draw_circle(center, 3.5, Color("f5efdb"))
					draw_arc(center, 3.5, 0, TAU, 16, Color("203039"), 1.2)
		draw_string(ThemeDB.fallback_font, Vector2(30, 987), "White dots: capitals. Colors: starting kingdoms. Gray: mountains.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("c4d2ce"))

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var overview := Overview.new()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size=") and argument.substr(7) in Sizes.IDS: overview.size_id = argument.substr(7)
	for seed_value in [12, 42, 83, 127, 205, 319]:
		var rules = Rules.new()
		rules.rule_mode = "modern"
		rules.generate(seed_value, overview.size_id)
		overview.maps.append(rules)
	viewport.add_child(overview)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var error := viewport.get_texture().get_image().save_png("res://artifacts/map_generation_%s.png" % overview.size_id)
	print("Map overview saved: ", error_string(error))
	quit(error)
