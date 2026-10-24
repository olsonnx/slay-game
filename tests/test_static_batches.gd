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

func batch_instances(manager) -> int:
	var total := 0
	for chunk in manager.chunks.values():
		for render in chunk["root"].get_children():
			total += render.get_meta("represented_sources", render.multimesh.instance_count)
	return total

func verify_uploaded_instances(manager) -> void:
	# Dummy rendering does not retain GPU instance data for readback.
	if DisplayServer.get_name() == "headless":
		return
	for chunk in manager.chunks.values():
		for key in chunk["batches"]:
			var render: MultiMeshInstance3D = chunk["batches"][key]
			if key.begins_with("terrain:"):
				expect(render.multimesh.instance_count == 1 and render.multimesh.mesh.get_surface_count() == 1, "Settled terrain uses one merged mesh per chunk")
				continue
			var records: Array = chunk["signature"].filter(func(record): return record[1] == key)
			for index in range(records.size()):
				expect(render.multimesh.get_instance_transform(index).is_equal_approx(records[index][2]), "Retained batch preserves each instance transform")
				var actual: Color = render.multimesh.get_instance_color(index)
				var expected: Color = records[index][3]
				# Compatibility stores components with 16-bit precision.
				expect(absf(actual.r - expected.r) < 0.001 and absf(actual.g - expected.g) < 0.001 and absf(actual.b - expected.b) < 0.001 and absf(actual.a - expected.a) < 0.001, "Retained batch preserves each instance colour")

func run() -> void:
	var sound = root.get_node("Sound")
	var muted: bool = sound.is_muted()
	sound.set_muted(true, false)
	var video = root.get_node("Video")
	var transitions: bool = video.level_transitions
	video.set_preference(&"level_transitions", false, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 42
	game.initial_rule_mode = "modern"
	game.initial_map_size = "large"
	game.initial_kingdom_count = 6
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var manager = game.view.static_batches
	expect(manager.instance_count > game.cells.size() * 2 and manager.chunks.size() > 1, "Large map batches terrain and props into spatial chunks")
	expect(batch_instances(manager) == manager.instance_count, "Every suppressed source has exactly one rendered instance")
	verify_uploaded_instances(manager)
	for record in manager.suppressed.values():
		expect(record[0].layers == 0 and record[0].is_visible_in_tree(), "Source scene visibility remains intact while duplicate rendering is suppressed")
	for kind in ["bark", "foliage", "rock", "snow"]:
		var finish: StandardMaterial3D = game.view.scenery_material(Color.WHITE, kind)
		expect(finish.albedo_texture == null and not finish.normal_enabled, "Scenery finishes have no grain or surface noise")
	var rebuilds: int = manager.rebuild_count
	game.view.refresh_static_batches()
	expect(manager.rebuild_count == rebuilds, "Unchanged sync retains all chunk geometry")
	var coord: Vector2i = game.active_capital()
	var tile: Node3D = game.view.tile_nodes[coord]
	var surface: MeshInstance3D = tile.get_meta("surface")
	var original: Material = surface.material_override
	var chunk_key := Vector2i(floori(float(coord.x) / manager.chunk_size), floori(float(coord.y) / manager.chunk_size))
	var retained_root: Node3D = manager.chunks[chunk_key]["root"]
	var retained_renderers: Dictionary = manager.chunks[chunk_key]["batches"].duplicate()
	var changed: StandardMaterial3D = original.duplicate()
	changed.albedo_color = Color("ff00ff")
	surface.material_override = changed
	game.view.refresh_static_batches()
	expect(manager.rebuild_count == rebuilds + 1, "A changed tile rebuilds only its chunk")
	expect(manager.chunks[chunk_key]["root"] == retained_root, "A changed colour retains its chunk node")
	for key in retained_renderers:
		expect(manager.chunks[chunk_key]["batches"].get(key) == retained_renderers[key], "Existing batch renderers survive colour updates")
	verify_uploaded_instances(manager)
	var found_color := false
	for chunk in manager.chunks.values():
		for record in chunk["signature"]:
			if record[3].is_equal_approx(Color("ff00ff")):
				found_color = true
	expect(found_color and changed.albedo_color == Color("ff00ff"), "Instance color preserves tint without mutating the source material")
	surface.material_override = original
	game.view.refresh_static_batches()
	var syncs: int = manager.sync_count
	surface.material_override = changed
	game.view.mark_batch_dirty(coord)
	for event in range(3):
		game.view.notify_visible_board_changed()
	game.view.flush_batch_update()
	expect(manager.sync_count == syncs + 1, "Simultaneous capture notifications share one incremental batch sync")
	game.view.flush_batch_update()
	expect(manager.sync_count == syncs + 1, "Flushing an already completed capture update does no work")
	verify_uploaded_instances(manager)
	surface.material_override = original
	game.view.mark_batch_dirty(coord)
	game.view.notify_visible_board_changed()
	game.view.flush_batch_update()
	var actor: Node3D
	for value in game.view.unit_actors.values():
		actor = value
		break
	for child in actor.get_node("Pips").get_children():
		expect(child.layers == 0 and not manager.suppressed.has(child.get_instance_id()), "Settled rank markers use the independent army batches")
	var actor_parent := actor.get_parent()
	actor.reparent(game.view.animation_root, true)
	game.view.unit_batches.sync()
	for child in actor.get_node("Pips").get_children():
		expect(child.layers != 0, "Moving rank markers restore their individual render layers")
	actor.reparent(actor_parent, true)
	game.view.unit_batches.sync()
	var source_count: int = manager.instance_count
	game.view.value_heatmap.set_active(true)
	expect(surface.material_override != original and surface.layers == 0, "Heatmap tints the batched surface")
	expect(batch_instances(manager) == manager.instance_count and manager.instance_count < source_count, "Filtered hidden detail is removed from batches")
	var filtered_syncs: int = manager.sync_count
	game.view.notify_visible_board_changed()
	game.view.flush_batch_update()
	expect(manager.sync_count == filtered_syncs, "An unchanged filtered playback notification does not rescan static sources")
	game.view.value_heatmap.set_active(false)
	expect(surface.material_override == original and manager.instance_count == source_count, "Leaving the filter restores original batching and materials")
	var scans: int = manager.material_scan_count
	var cached_materials: int = manager.source_material_keys.size()
	var muted_materials: int = game.view.value_heatmap.prop_materials.size()
	var render_nodes: int = manager.get_child_count(true)
	var warmed_rebuilds: int = manager.rebuild_count
	var warmed_syncs: int = manager.sync_count
	var toggle_key := InputEventKey.new()
	toggle_key.keycode = root.get_node("Keys").bindings["heatmap"]
	toggle_key.pressed = true
	for cycle in range(60):
		game._unhandled_input(toggle_key)
		expect(game.view.value_heatmap.active and manager.instance_count < source_count, "Repeated shortcut enables the filtered batches")
		game._unhandled_input(toggle_key)
		expect(not game.view.value_heatmap.active and surface.material_override == original and manager.instance_count == source_count, "Repeated shortcut restores the original materials and instances")
	expect(manager.material_scan_count == scans, "Spamming the heatmap shortcut reuses material features without rescanning")
	expect(manager.rebuild_count == warmed_rebuilds and manager.sync_count == warmed_syncs and manager.presentation_banks.size() == 1, "Unchanged switches reuse exactly two prepared views without rescanning or rebuilding")
	expect(manager.source_material_keys.size() == cached_materials and game.view.value_heatmap.prop_materials.size() == muted_materials, "Repeated filter switches keep material caches bounded")
	expect(manager.get_child_count(true) == render_nodes and batch_instances(manager) == source_count, "Repeated filter switches retain chunks without duplicate instances")
	# Cached feature keys must not own a discarded material resource.
	var transient := StandardMaterial3D.new()
	var transient_id := transient.get_instance_id()
	manager.material_key(transient)
	var reference: WeakRef = weakref(transient)
	transient = null
	expect(reference.get_ref() == null, "Material feature cache does not keep discarded resources alive")
	game.view.refresh_static_batches()
	expect(not manager.source_material_keys.has(transient_id), "Batch synchronization removes expired material feature keys")
	manager.set_enabled(false)
	expect(surface.layers == 1 and not manager.visible and manager.suppressed.is_empty(), "Fallback restores source layers and hides all batches")
	manager.set_enabled(true)
	game.view.refresh_static_batches()
	expect(surface.layers == 0 and manager.visible, "Reenabling returns to retained static batching")
	video.set_preference(&"level_transitions", true, false)
	game.view.start_level_transition(true)
	expect(manager.suspended and not manager.visible and surface.layers == 0 and game.view.island_transition.moving_batches.source_count > 0, "Island transition instances the moving tile geometry")
	game.view.cancel_level_transition()
	expect(not manager.suspended and manager.visible and surface.layers == 0, "Cancelled transition restores static geometry at the original positions")
	# Tooltip content rebuilds only after a meaningful change, while position follows.
	game.hovered = coord
	game.show_world_tip()
	var signature: Array = game.presenter.tip_signature.duplicate(true)
	var text_value: String = game.tip_label.text
	game.show_world_tip()
	expect(game.presenter.tip_signature == signature and game.tip_label.text == text_value, "Stationary hover retains tooltip content")
	game.rules.cells[coord]["value"] += 1
	game.view.value_heatmap.set_active(true)
	game.show_world_tip()
	expect(game.tip_label.get_parsed_text().contains("Value %d" % game.cells[coord]["value"]), "Changed province value and mode refresh tooltip contents")
	game.view.value_heatmap.set_active(false)
	game.rules.kingdoms[coord]["gold"] += 13
	game.refresh_ui()
	game.show_world_tip()
	expect(game.tip_label.get_parsed_text().contains("Kingdom %d G" % game.rules.kingdoms[coord]["gold"]), "Economy refresh invalidates cached tooltip content")
	# Removing a visible source subtree must immediately remove its batch instances.
	var features := tile.get_node("Features")
	var before: int = manager.instance_count
	features.hide()
	game.view.visible_board_changed.emit()
	expect(manager.instance_count < before, "Hidden/removed prop subtrees disappear from retained rendering")
	features.show()
	game.view.visible_board_changed.emit()
	expect(manager.instance_count == before, "Restored subtree renders exactly once")
	game.shutdown()
	game.queue_free()
	await process_frame
	video.set_preference(&"level_transitions", transitions, false)
	sound.stop_all()
	sound.set_muted(muted, false)
	print("Static batching checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
