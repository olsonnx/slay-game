extends SceneTree
## Exercise the real GUI hover timer, beyond the configured tooltip delay.
var frame_gaps: Array[float] = []
var previous_frame := 0
var sampling := false

func _initialize() -> void: call_deferred("run")

func frame_sample() -> void:
	var now := Time.get_ticks_usec()
	if sampling and previous_frame > 0: frame_gaps.append((now - previous_frame) / 1000.0)
	previous_frame = now

func visible_windows(node: Node) -> int:
	var count := 1 if node is Window and node.visible else 0
	for child in node.get_children(true): count += visible_windows(child)
	return count

func run() -> void:
	root.size = Vector2i(960, 620)
	process_frame.connect(frame_sample)
	var viewer = load("res://src/ui/replay_viewer.gd").new()
	# Real filename shapes, without reading or modifying player recordings.
	var source := "res://artifacts/replay-hover-tests"
	DirAccess.make_dir_recursive_absolute(source)
	for index in range(5):
		var fixture := FileAccess.open(source.path_join("2026-10-18T19-10-35-1971005964-299112073%d.jsonl" % index), FileAccess.WRITE)
		fixture.store_string("{}")
	viewer.replay_directory = source
	root.add_child(viewer)
	while viewer.library_loading: await process_frame
	await create_timer(0.5).timeout
	var baseline_windows := visible_windows(root)
	var samples: Array = []
	var failures := 0 if viewer.list.item_count >= 5 else 1
	for index in range(mini(5, viewer.list.item_count)):
		var item: Rect2 = viewer.list.get_item_rect(index)
		var point: Vector2 = viewer.list.global_position + item.get_center()
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		motion.relative = Vector2(1, 1)
		frame_gaps.clear()
		previous_frame = 0
		sampling = true
		root.push_input(motion, true)
		await create_timer(1.0).timeout
		sampling = false
		var max_gap := 0.0
		for gap in frame_gaps: max_gap = maxf(max_gap, gap)
		var sample := {"index":index, "frames":frame_gaps.size(), "max_frame_ms":max_gap,
			"hovered_list":root.gui_get_hovered_control() == viewer.list,
			"tooltip_enabled":viewer.list.is_item_tooltip_enabled(index),
			"new_popup_windows":visible_windows(root) - baseline_windows,
			"replay_loaded":viewer.view != null or viewer.worker != null}
		if not sample["hovered_list"] or sample["tooltip_enabled"] or sample["new_popup_windows"] != 0 or sample["replay_loaded"] or max_gap > 500.0: failures += 1
		samples.append(sample)
		print(JSON.stringify(sample))
	var file := FileAccess.open("res://artifacts/replay_hover_probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(samples, "\t"))
	viewer.free()
	await process_frame
	print("Replay hover checks: %d passed, %d failed" % [samples.size() - failures, failures])
	quit(1 if failures else 0)
