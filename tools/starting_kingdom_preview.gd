extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Starts = preload("res://src/game/starting_territories.gd")
class Overview extends Node2D:
	var examples := []
	func _draw():
		draw_rect(Rect2(0,0,1440,1000),Color("172b34"))
		draw_string(ThemeDB.fallback_font,Vector2(25,38),"Modern starting kingdoms · 11 income / +7 after Scout upkeep",HORIZONTAL_ALIGNMENT_LEFT,-1,25,Color("e6ebdf"))
		for index in range(examples.size()):
			var example: Dictionary = examples[index]
			var rules = example["rules"]
			var bank: Dictionary = example["bank"]
			var panel := Vector2(16 + (index % 3) * 474, 58 + (index / 3) * 302)
			draw_rect(Rect2(panel,Vector2(462,288)),Color("203945"))
			draw_string(ThemeDB.fallback_font,panel + Vector2(14,27),"%d tiles · seed %d" % [bank["hexes"].size(),rules.level_seed],HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("e6ebdf"))
			var origin := panel + Vector2(231,157)
			for coord in rules.cells:
				if rules.distance(coord,bank["capital"]) > 3: continue
				var at: Vector3 = Rules.Grid.to_world(coord-bank["capital"])
				var center: Vector2 = origin + Vector2(at.x,at.z)*24
				var polygon := PackedVector2Array()
				for corner in range(6):
					var angle := PI / 6.0 + corner * TAU / 6.0
					polygon.append(center + Vector2(cos(angle),sin(angle))*23)
				var owned: bool = coord in bank["hexes"]
				var color: Color = Rules.Catalog.TERRAIN_COLORS[bank["owner"]] if owned else Color("4e6666")
				if rules.is_mountain(coord): color = Color("77838c")
				draw_colored_polygon(polygon,color)
				if coord == bank["capital"]:
					draw_circle(center,6,Color("f5efdb"))
					draw_arc(center,6,0,TAU,20,Color("203039"),2)
				if owned:
					draw_string(ThemeDB.fallback_font,center + Vector2(-5,5),str(rules.cells[coord]["value"]),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("203039"))
		draw_string(ThemeDB.fallback_font,Vector2(25,988),"White dot: capital. Numbers: province income. Muted tiles: surrounding land. All starts have one Scout, 10 gold and 1 mana.",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("c4d2ce"))
func _initialize(): call_deferred("capture")
func capture():
	var overview := Overview.new()
	var seen := {}
	for seed_value in range(24):
		var rules = Rules.new()
		rules.rule_mode = "modern"
		rules.generate(seed_value,"large",6)
		for bank in rules.kingdoms.values():
			var offsets := []
			for coord in bank["hexes"]: offsets.append(coord-bank["capital"])
			var key := ""
			for orientation in range(12):
				var transformed: Array = Starts.footprint(Vector2i.ZERO,offsets,offsets.size(),orientation)
				transformed.sort()
				var candidate := str(transformed)
				if key == "" or candidate < key: key = candidate
			if not seen.has(key) and overview.examples.size() < 9:
				seen[key] = true
				overview.examples.append({"rules":rules,"bank":bank})
		if overview.examples.size() >= 9: break
	overview.examples.sort_custom(func(a,b): return a["bank"]["hexes"].size() < b["bank"]["hexes"].size())
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1440,1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(overview)
	await process_frame
	await RenderingServer.frame_post_draw
	var error := viewport.get_texture().get_image().save_png("res://artifacts/starting_kingdoms_v7.png")
	print("Starting kingdom overview: ",overview.examples.size()," distinct footprints; ",error_string(error))
	quit(error)
