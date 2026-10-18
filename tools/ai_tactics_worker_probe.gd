extends SceneTree
const Fixture = preload("res://tools/heavy_strain_probe.gd")
class Host extends Node:
	var closing := false
	var frames := 0
	func _process(_delta: float) -> void: frames += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var output := "res://artifacts/ai-tactics-worker.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			var label := arg.trim_prefix("--label=")
			assert(label.is_valid_filename())
			output = "res://artifacts/ai-%s-worker.json" % label
	var results := []
	var host := Host.new()
	root.add_child(host)
	for count in [120,300,600]:
		var model = Fixture.crowded("huge",71,count)
		model.ai_difficulty = "hard"
		var opponent = model.KingdomAI.new(model)
		for preparation in [true,false]:
			var frames := host.frames
			var start := Time.get_ticks_usec()
			var planner = await opponent.search_async(host,1,preparation)
			var result := {"units":count,"preparation":preparation,"wall_ms":(Time.get_ticks_usec()-start)/1000.0,"frames_serviced":host.frames-frames,"max_worker_step_ms":planner.max_step_usec/1000.0,"evaluated":planner.evaluated,"orders":planner.best_sequence.size()}
			results.append(result)
			print(JSON.stringify(result))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	host.queue_free()
	quit()
