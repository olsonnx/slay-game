extends SceneTree
const Events = preload("res://src/game/event_catalog.gd")
var dialog
func _initialize() -> void: call_deferred("run")
func button(parent,caption,rect,callback,_tooltip,_primary):
	var node := Button.new()
	node.text = caption
	node.position = rect.position
	node.size = rect.size
	node.pressed.connect(callback)
	parent.add_child(node)
	return node
func run() -> void:
	var optimized := "--optimized" in OS.get_cmdline_user_args()
	var stage := "after" if optimized else "before"
	var layer := CanvasLayer.new()
	root.add_child(layer)
	dialog = load("res://src/ui/event_dialog.gd").new(button)
	layer.add_child(dialog)
	if optimized:
		var warmup = load("res://src/ui/event_art_warmup.gd").new()
		root.add_child(warmup)
		await warmup.prepare()
	for frame in range(5): await process_frame
	var results := []
	for id in Events.EVENTS:
		var start := Time.get_ticks_usec()
		dialog.present(Events.EVENTS[id],func(_choice): pass)
		var present_ms := (Time.get_ticks_usec()-start)/1000.0
		var worst := 0.0
		var last := Time.get_ticks_usec()
		for frame in range(5):
			await process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst,(now-last)/1000.0)
			last = now
		results.append({"event":id,"present_ms":present_ms,"max_frame_ms":worst})
		dialog.close_dialog()
		await process_frame
	var file := FileAccess.open("res://artifacts/event-art-performance-"+stage+".json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t")+"\n")
	print("Event art performance ",stage,": ",JSON.stringify(results))
	quit()
