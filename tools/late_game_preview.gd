extends SceneTree
## Staged late-game state on a normally generated island; uses production rendering.
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1600,1000)
	var video = root.get_node("Video")
	video.set_preference(&"level_transitions",false,false)
	video.set_preference(&"atmospheric_lighting",true,false)
	var rules = load("res://src/game/kingdom_rules.gd").new()
	rules.rule_mode = "modern"
	rules.generate(71,"large",4)
	var queue: Array = []
	var owners := {}
	for bank in rules.kingdoms.values():
		queue.append(bank.capital)
		owners[bank.capital] = bank.owner
	var cursor := 0
	while cursor < queue.size():
		var coord: Vector2i = queue[cursor]
		cursor += 1
		for next in rules.neighbors(coord):
			if owners.has(next) or rules.is_mountain(next) or rules.is_bridge(next): continue
			owners[next] = owners[coord]
			queue.append(next)
	var sites = load("res://src/game/event_sites.gd")
	var landmark_count := 0
	var house_count := 0
	var tower_count := 0
	var unit_count := 0
	for coord in rules.cells:
		var cell: Dictionary = rules.cells[coord]
		if not owners.has(coord): continue
		cell.owner = owners[coord]
		cell.unit = 0
		cell.unit_owner = -1
		cell.unit_home = rules.NONE
		cell.tree = false
		cell.grave = false
		cell.value = 3+posmod(coord.x*11+coord.y*7,4)
		cell.erase("treasure")
		for key in ["animal","animal_home","animal_target"]: cell.erase(key)
		var event: String = cell.get("event", "")
		cell.event = ""
		if cell.get("lair", "") != "":
			var kind: String = cell.lair
			cell.erase("lair")
			cell.erase("lair_wait")
			sites.create(rules,coord,kind,5 if kind == "bear" else 0,1 if kind == "wolf" else 0)
			landmark_count += 1
		elif event != "" and landmark_count < 10:
			var choice := landmark_count%4
			sites.create(rules,coord,["comet","economist","stainless_steel","wolf"][choice],[2,-1,0,0][choice],1 if choice == 3 else 0,choice == 2)
			landmark_count += 1
		if cell.capital >= 0 or cell.building != "": continue
		var border := false
		for next in rules.neighbors(coord):
			if owners.has(next) and owners[next] != cell.owner: border = true
		var roll := posmod(coord.x*29+coord.y*17,100)
		if border and roll < 35:
			cell.building = "tower"
			tower_count += 1
		elif roll < 19:
			cell.building = "house"
			house_count += 1
		elif roll < 34:
			cell.unit = 3 if border and roll%3 == 0 else 2 if border or roll%2 == 0 else 1
			cell.unit_owner = cell.owner
			cell.moved = roll%3 == 0
			unit_count += 1
		elif roll > 96 and not border: cell.tree = true
	for coord in rules.cells:
		if rules.cells[coord].building == "monument":
			rules.cells[coord].unit = 1+unit_count%3
			rules.cells[coord].unit_owner = rules.cells[coord].owner
			unit_count += 1
	rules.rebuild_kingdoms()
	var board = load("res://src/rendering/board_view.gd").new()
	root.add_child(board)
	board.configure_map("large",load("res://src/game/map_sizes.gd").spec("large").bounds)
	board.render_cells(rules.cells)
	board.lighting.apply_style("atmospheric")
	var minimum := Vector3(1000,0,1000)
	var maximum := Vector3(-1000,0,-1000)
	for coord in rules.cells:
		var point: Vector3 = board.coord_position(coord)
		minimum.x = minf(minimum.x,point.x)
		minimum.z = minf(minimum.z,point.z)
		maximum.x = maxf(maximum.x,point.x)
		maximum.z = maxf(maximum.z,point.z)
	board.focus = (minimum+maximum)*0.5
	board.pitch = 1.04
	board.yaw = 0.12
	board.zoom = maxf((maximum.x-minimum.x)*0.72,(maximum.z-minimum.z)*1.08)+4.0
	board.update_camera()
	await create_timer(1.4).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/late-game-roads-overview.png")
	var close: Vector2i = rules.kingdoms.keys()[0]
	var best := -1
	for coord in rules.cells:
		if rules.cells[coord].building != "monument": continue
		var score := 0
		for other in rules.cells:
			if rules.distance(coord,other) <= 4 and rules.cells[other].building != "": score += 1
		if score > best:
			best = score
			close = coord
	board.focus = board.coord_position(close)
	board.pitch = 0.88
	board.zoom = 17.0
	board.update_camera()
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/late-game-roads-detail.png")
	print("Late-game preview: %d tiles, %d houses, %d towers, %d landmarks, %d armies" % [rules.cells.size(),house_count,tower_count,landmark_count,unit_count])
	board.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit()
