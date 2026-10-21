extends SceneTree
## Native A/B/C benchmark; identical seeded maps, camera paths and video settings.
const Rules = preload("res://src/game/kingdom_rules.gd")
var game
var results: Array = []
var duration := 3.0
var compare_sprites := false
var capture_resolution := Vector2i.ZERO
var output_prefix := ""
func _initialize() -> void: call_deferred("run")
func percentile(values: Array, amount: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size()-1,int(ceil(sorted.size()*amount))-1)]
func crowded():
	var model = Rules.new()
	model.rule_mode = "modern"
	model.generate(71,"huge",6)
	var queue: Array = []
	var owners := {}
	for bank in model.kingdoms.values(): queue.append(bank.capital); owners[bank.capital] = bank.owner
	var head := 0
	while head < queue.size():
		var coord: Vector2i = queue[head]
		head += 1
		for next in model.neighbors(coord):
			if not owners.has(next) and not model.is_mountain(next): owners[next] = owners[coord]; queue.append(next)
	var count := 0
	for coord in model.cells:
		var cell: Dictionary = model.cells[coord]
		cell.unit = 0
		for field in ["animal","animal_home","animal_target","lair","lair_wait"]: cell.erase(field)
		if not owners.has(coord): continue
		cell.owner = owners[coord]
		cell.event = ""
		cell.erase("treasure")
		cell.value = 6
		if posmod(hash(coord),3) == 0 and count < 300:
			cell.unit = 3 if count%10 == 0 else 2 if count%3 == 0 else 1
			cell.tree = false
			cell.building = ""
			count += 1
	model.rebuild_kingdoms()
	for bank in model.kingdoms.values(): bank.gold = 300
	return model
func sample(style: String, size_id: String, close: bool, repetition: int) -> void:
	game.view.lighting.apply_style("atmospheric" if compare_sprites else style)
	if compare_sprites:
		game.view.sprite_lighting.set_enabled(style == "lit")
		game.view.unit_batches.refresh_sprite_lighting()
	game.view.pitch = 0.82
	game.view.yaw = 0.35
	game.view.zoom = 12.0 if close else game.view.max_zoom
	game.view.focus = game.view.coord_position(game.rules.kingdoms.keys()[0]) if close else game.view.map_center
	game.view.update_camera()
	await create_timer(0.65).timeout
	if repetition == 0:
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		capture_resolution = capture.get_size()
		capture.save_png("res://artifacts/%s-%s-%s-%s.png" % [output_prefix,size_id,"close" if close else "overview",style])
	var frames: Array = []
	var gpu: Array = []
	var cpu: Array = []
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec()-started < duration*1000000:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		frames.append((now-previous)/1000.0)
		previous = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	var row := {"map":size_id,"view":"close" if close else "overview","style":style,"repeat":repetition,"tiles":game.cells.size(),"units":game.view.unit_actors.size(),"fps":frames.size()*1000000.0/(previous-started),"median_ms":percentile(frames,0.5),"p95_ms":percentile(frames,0.95),"gpu_ms":percentile(gpu,0.5),"render_cpu_ms":percentile(cpu,0.5),"draws":RenderingServer.viewport_get_render_info(root.get_viewport_rid(),0,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)}
	results.append(row)
	print(JSON.stringify(row))
	var file := FileAccess.open("res://artifacts/%s-comparison.json" % output_prefix,FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"engine":Engine.get_version_info().string,"requested_resolution":"1920x1080","render_resolution":str(capture_resolution),"root_texture_resolution":str(root.get_texture().get_size()),"window_resolution":str(DisplayServer.window_get_size()),"msaa":root.get_node("Video").antialiasing,"duration":duration,"results":results},"\t"))
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(1); return
	for argument in OS.get_cmdline_user_args():
		if argument == "--sprite-lighting": compare_sprites = true
		if argument.begins_with("--duration="): duration = argument.trim_prefix("--duration=").to_float()
		if argument.begins_with("--output-prefix="): output_prefix = argument.trim_prefix("--output-prefix=").validate_filename()
	if output_prefix == "": output_prefix = "sprite-lighting" if compare_sprites else "lighting"
	var video = root.get_node("Video")
	video.set_preference(&"resolution",Vector2i(1920,1080),false)
	video.set_preference(&"vsync",false,false)
	video.set_preference(&"shadows",true,false)
	video.set_preference(&"antialiasing",2,false)
	video.set_preference(&"level_transitions",false,false)
	root.get_node("Sound").set_muted(true,false)
	Engine.max_fps = 0
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.camera_follow_suspended = true
	await process_frame
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for size_id in ["large","huge"]:
		var model = crowded() if size_id == "huge" else Rules.new()
		if size_id == "large": model.rule_mode = "modern"; model.generate(71,"large",6)
		game.rules = model
		game.new_game(71,true,false)
		game.view.cancel_level_transition()
		game.view.stop_camera_pan()
		game.view.controls_enabled = false
		game.view.birds.set_process(false)
		game.cancel_action()
		game.refresh_ui()
		await create_timer(0.5).timeout
		for close in [false,true]:
			for repetition in range(2):
				var styles := ["simple","daylight","atmospheric"] if repetition == 0 else ["atmospheric","daylight","simple"]
				if compare_sprites: styles = ["unlit","lit"] if repetition == 0 else ["lit","unlit"]
				for style in styles: await sample(style,size_id,close,repetition)
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	quit()
