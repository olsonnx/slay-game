extends Node
## Bound to the board lifetime: concurrent movement, impacts and surrender effects.
const STEP_SECONDS := 0.22
const PLACEMENT_COLOR := Color("ead29e")
const Sprites = preload("res://src/rendering/unit_sprite_library.gd")
var board
var active_motions: Dictionary = {}
var is_animating := false
var animation_revision := 0
var preparation_tween: Tween
var speed_scale := 1.0
var scaled_tweens: Array[Tween] = []

func set_speed_scale(value: float) -> void:
	if speed_scale == value:
		return
	speed_scale = value
	prune_tweens()
	for tween in scaled_tweens:
		tween.set_speed_scale(value)

func prune_tweens() -> void:
	for index in range(scaled_tweens.size() - 1, -1, -1):
		if not scaled_tweens[index].is_valid():
			scaled_tweens.remove_at(index)

func scaled_tween(owner: Node) -> Tween:
	prune_tweens()
	var tween := owner.create_tween().set_speed_scale(speed_scale)
	scaled_tweens.append(tween)
	return tween

func _init(view) -> void:
	board = view

func action_marker(coord: Vector2i, color: Color) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "ActionRipple"
	marker.mesh = board.outline_mesh
	marker.position = board.coord_position(coord) + Vector3(0, 0.07, 0)
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	marker.material_override = mat
	board.animation_root.add_child(marker)
	var tween := scaled_tween(marker).set_parallel(true)
	tween.tween_property(marker, "scale", Vector3(1.25, 1, 1.25), 0.30)
	tween.tween_property(mat, "albedo_color", Color(color, 0), 0.30)
	tween.chain().tween_callback(marker.queue_free)

func play_preparation(actions: Array, new_cells: Dictionary) -> void:
	# Retain dying troops until their final pose, including starvation deaths.
	var displayed: Dictionary = new_cells.duplicate()
	var deaths: Array[Vector2i] = []
	var seconds := 0.34
	for action in actions:
		var coord: Vector2i = action["coord"]
		if action["kind"] == "death" and board.unit_actors.has(coord) and displayed.has(coord):
			displayed[coord] = board.cells[coord].duplicate(true)
			deaths.append(coord)
	board.render_cells(displayed)
	if actions.is_empty():
		return
	is_animating = true
	animation_revision += 1
	var revision := animation_revision
	for coord in deaths:
		var animator = board.unit_actors[coord].get_node("UnitAnimation")
		animator.play("death", false, true)
		seconds = maxf(seconds, Sprites.duration(animator.tier, "death"))
	if not deaths.is_empty():
		board.unit_batches.queue_sync()
		board.unit_batches.sync(true)
	for action in actions:
		board.action_started.emit(action)
		if action["kind"] in ["recruit", "upgrade"]:
			seconds = maxf(seconds, board.spawn_unit_effect(action["coord"], new_cells[action["coord"]]["unit"]))
		else:
			action_marker(action["coord"], Color("da9077") if action["kind"] == "death" else Color("bda2fa") if action["kind"] == "spell" else PLACEMENT_COLOR)
	preparation_tween = scaled_tween(self)
	preparation_tween.tween_interval(seconds)
	while preparation_tween != null and preparation_tween.is_valid() and preparation_tween.is_running():
		await get_tree().process_frame
		if revision != animation_revision:
			return
	if revision != animation_revision:
		return
	preparation_tween = null
	if not deaths.is_empty(): board.render_cells(new_cells, true)
	for action in actions:
		board.action_finished.emit(action)
	is_animating = false

func animate_moves(actions: Array, final_cells: Dictionary) -> void:
	board.clear_unit_hover()
	if actions.is_empty():
		return
	is_animating = true
	animation_revision += 1
	var revision := animation_revision
	# Freeze only the command's changes, including distant kingdom/capital edits.
	# Actions and rules can advance while tweens run; these records remain private.
	var final_snapshot: Dictionary = {}
	for coord in final_cells:
		if board.cells.get(coord, {}) != final_cells[coord]:
			final_snapshot[coord] = final_cells[coord].duplicate(true)
	for action in actions:
		for coord in [action["source"], action["target"], action.get("landing", action["target"])]:
			final_snapshot[coord] = final_cells[coord].duplicate(true)
	var actors_before: Dictionary = board.unit_actors.duplicate()
	# Every tween is launched before waiting: an entire faction moves concurrently.
	for action in actions:
		var actor: Node3D = actors_before.get(action["source"])
		if not is_instance_valid(actor):
			continue
		var defender: Node3D = actors_before.get(action["target"]) if action["before_target"]["unit"] > 0 else null
		actor.reparent(board.animation_root, true)
		start_motion(actor, defender, action)
	board.unit_batches.queue_sync(board.dirty_tiles, false)
	board.unit_batches.sync(true)
	while not active_motions.is_empty():
		await get_tree().process_frame
		if revision != animation_revision:
			return
	if revision != animation_revision:
		return
	is_animating = false
	board.render_cells(final_snapshot, true)

func cancel_motion(restored_cells: Dictionary) -> void:
	animation_revision += 1
	board.unit_spawn_effects.clear()
	if preparation_tween != null and preparation_tween.is_valid():
		preparation_tween.kill()
	preparation_tween = null
	for motion in active_motions.values():
		var tween: Tween = motion["tween"]
		if tween.is_valid():
			tween.kill()
		var wave: Tween = motion.get("annex_tween")
		if wave != null and wave.is_valid():
			wave.kill()
	active_motions.clear()
	is_animating = false
	for actor in board.unit_actors.values():
		if is_instance_valid(actor):
			actor.get_node("UnitAnimation").play("idle")
			actor.show()
	board.render_cells(restored_cells)

func start_motion(actor: Node3D, defender: Node3D, action: Dictionary) -> void:
	board.dirty_tiles[action["source"]] = true
	board.dirty_tiles[action["target"]] = true
	var tween := scaled_tween(actor)
	active_motions[action["source"]] = {"actor": actor, "action": action, "tween": tween}
	board.action_started.emit(action)
	board.motion_stage.emit(action, "travel")
	var path: Array = action["path"]
	var end: Vector3 = board.coord_position(action["target"])
	if action["after_target"]["capital"] >= 0:
		end += Vector3(0.35, 0, 0.30)
	var attacking: bool = action["kind"] in ["attack", "blocked_attack", "knight_duel"]
	var animator = actor.get_node("UnitAnimation")
	animator.play("charge" if attacking and animator.tier == 3 else "run", true)
	var last_step: int = path.size() - 1
	for index in range(1, path.size()):
		if attacking and index == last_step:
			break
		var point: Vector3 = end if index == last_step else board.coord_position(path[index])
		tween.tween_callback(animator.face.bind(point))
		tween.tween_property(actor, "global_position", point, STEP_SECONDS).set_trans(Tween.TRANS_LINEAR)
	if attacking:
		var before_target: Vector3 = board.coord_position(path[last_step - 1])
		var direction: Vector3 = (end - before_target).normalized()
		# Leave room for the new silhouettes and their weapon reach.
		var approach: Vector3 = end - direction * 1.40
		var jab: Vector3 = end - direction * 1.05
		tween.tween_callback(animator.face.bind(end))
		tween.tween_property(actor, "global_position", approach, 0.16).set_trans(Tween.TRANS_LINEAR)
		tween.tween_callback(animator.play.bind("attack", false, true))
		tween.tween_callback(func(): board.motion_stage.emit(action, "jab"))
		tween.tween_property(actor, "global_position", jab, Sprites.impact_time(animator.tier)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_callback(impact.bind(defender, action))
		var recovery: float = Sprites.duration(animator.tier, "attack") - Sprites.impact_time(animator.tier)
		if is_instance_valid(defender):
			recovery = maxf(recovery, Sprites.duration(defender.get_node("UnitAnimation").tier, "hurt" if action["kind"] == "blocked_attack" else "death"))
		if action["kind"] == "knight_duel":
			recovery = maxf(recovery, Sprites.duration(animator.tier, "death"))
		tween.tween_interval(recovery)
		if is_instance_valid(defender) and action["kind"] == "attack":
			tween.tween_callback(defender.hide)
		if action["kind"] != "knight_duel":
			tween.tween_property(actor, "global_position", approach, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			tween.tween_callback(animator.play.bind("run", true))
		if action["kind"] == "blocked_attack":
			var landing: Vector2i = action.get("landing", action["source"])
			var stop_index: int = maxi(0, path.find(landing))
			for index in range(path.size() - 2, stop_index - 1, -1):
				var retreat: Vector3 = board.coord_position(path[index])
				if index == stop_index and action.get("after_landing", action["before_source"])["capital"] >= 0:
					retreat += Vector3(0.35, 0, 0.30)
				tween.tween_callback(animator.face.bind(retreat))
				tween.tween_property(actor, "global_position", retreat, STEP_SECONDS).set_trans(Tween.TRANS_LINEAR)
		elif action["kind"] != "knight_duel":
			tween.tween_callback(animator.face.bind(end))
			tween.tween_property(actor, "global_position", end, 0.17).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(finish_motion.bind(actor, defender, action))

func impact(defender: Node3D, action: Dictionary) -> void:
	if is_instance_valid(defender):
		var animator = defender.get_node("UnitAnimation")
		animator.face(active_motions[action["source"]]["actor"].global_position)
		animator.play("hurt" if action["kind"] == "blocked_attack" else "death", false, action["kind"] != "blocked_attack")
		board.unit_batches.queue_sync({action["target"]: true}, false)
		board.unit_batches.sync(true)
	if action["kind"] == "blocked_attack":
		board.cells[action["target"]].erase("entrenched_by")
		board.cells[action["target"]]["fortified"] = false
		board.cells[action["target"]]["fortified_by"] = -1
		var ward: Node3D = board.tile_nodes[action["target"]].get_node_or_null("Fortification")
		if ward != null:
			ward.hide()
			board.dirty_tiles[action["target"]] = true
			board.unit_batches.queue_sync({action["target"]: true}, false)
			board.unit_batches.sync(true)
		action_marker(action["target"], Color("91e2ef"))
		board.notify_visible_board_changed()
		board.motion_stage.emit(action, "blocked")
		return
	if action["kind"] == "knight_duel":
		var actor: Node3D = active_motions[action["source"]]["actor"]
		actor.get_node("UnitAnimation").play("death", false, true)
		board.cells[action["source"]] = action["after_source"].duplicate(true)
		board.cells[action["target"]] = action["after_target"].duplicate(true)
		board.notify_visible_board_changed()
		board.motion_stage.emit(action, "impact")
		return
	if is_instance_valid(defender):
		board.cells[action["target"]]["unit"] = 0
	if action["before_target"]["capital"] >= 0 or action["before_target"]["building"] != "":
		clear_features(action["target"])
		board.cells[action["target"]]["building"] = ""
		board.cells[action["target"]]["capital"] = -1
	action_marker(action["target"], Color("f4bc8a"))
	board.notify_visible_board_changed()
	board.motion_stage.emit(action, "impact")

func clear_features(coord: Vector2i) -> void:
	var features: Node3D = board.tile_nodes[coord].get_node("Features")
	for child in features.get_children():
		features.remove_child(child)
		child.queue_free()
	board.mark_batch_dirty(coord)

func finish_motion(actor: Node3D, defender: Node3D, action: Dictionary) -> void:
	if not active_motions.has(action["source"]): return
	var revision := animation_revision
	if action["kind"] == "knight_duel":
		# Board synchronization owns removal of both registered actors.
		actor.hide()
		if is_instance_valid(defender): defender.hide()
		active_motions.erase(action["source"])
		board.action_finished.emit(action)
		return
	if action["kind"] == "blocked_attack":
		var landing: Vector2i = action.get("landing", action["source"])
		board.cells[action["source"]] = action["after_source"].duplicate(true)
		if landing != action["source"]:
			board.cells[landing] = action["after_landing"].duplicate(true)
			board.dirty_tiles[landing] = true
		for child in actor.get_children():
			if child is Sprite3D:
				child.modulate = Color("a8b2ae")
		board.settle_unit(actor, action["source"], landing)
		active_motions.erase(action["source"])
		board.notify_visible_board_changed()
		board.action_finished.emit(action)
		return
	if is_instance_valid(defender):
		defender.hide()
	var target: Vector2i = action["target"]
	var cell: Dictionary = action["after_target"]
	board.cells[action["source"]]["unit"] = 0
	board.cells[target] = cell.duplicate(true)
	actor.set_meta("hex", target)
	if action["capture"]:
		var color: Color = board.COLORS[cell["owner"]]
		color = color.lightened(0.045 * sin(float(target.x * 7 + target.y * 13)))
		var surface: MeshInstance3D = board.tile_nodes[target].get_meta("surface")
		surface.material_override = board.material(color)
		action_marker(target, color.lightened(0.25))
	clear_features(target)
	if cell["unit"] == 0:
		# An encounter can kill an opponent's unit immediately on arrival.
		actor.hide()
		board.motion_stage.emit(action, "occupy")
		active_motions.erase(action["source"])
		board.notify_visible_board_changed()
		board.action_finished.emit(action)
		return
	if cell["capital"] >= 0:
		board.add_capital(board.tile_nodes[target].get_node("Features"), Vector3(-0.20, 0, -0.12), board.COLORS[cell["owner"]])
	for child in actor.get_children():
		if child is Sprite3D:
			var faction: int = cell.get("unit_owner", -1) if cell["building"] == "bridge" else cell["owner"]
			child.texture = board.soldier_texture(cell["unit"], faction)
			child.set_meta("image", board.image_cache[Vector2i(cell["unit"], faction)])
			child.modulate = Color("a8b2ae") if cell["moved"] else Color.WHITE
	var pips: Node3D = actor.get_node("Pips")
	actor.get_node("UnitAnimation").configure(cell["unit"], cell.get("unit_owner", -1) if cell["building"] == "bridge" else cell["owner"])
	if pips.get_child_count() != cell["unit"]:
		for child in pips.get_children():
			pips.remove_child(child)
			child.queue_free()
		for index in range(cell["unit"]):
			board.cylinder(pips, Vector3((index - (cell["unit"] - 1) * 0.5) * 0.11, 0.045, 0.40), 0.035, 0.035, 0.025, Color("f0dba3"), 8)
	board.motion_stage.emit(action, "occupy")
	board.notify_visible_board_changed()
	if not action.get("annexed", {}).is_empty():
		await play_castle_surrender(action)
		if revision != animation_revision:
			return
	if revision != animation_revision: return
	board.settle_unit(actor, action["source"], target)
	if action["kind"] == "merge": board.spawn_unit_effect(target, cell["unit"])
	active_motions.erase(action["source"])
	board.notify_visible_board_changed()
	board.action_finished.emit(action)

func play_castle_surrender(action: Dictionary) -> void:
	var wave := scaled_tween(self)
	active_motions[action["source"]]["annex_tween"] = wave
	action_marker(action["target"], Color("ffe5a2"))
	# An expanding ring connects the fallen castle to its surrendering provinces.
	var ring := MeshInstance3D.new()
	ring.name = "CastleWave"
	ring.mesh = board.outline_mesh
	ring.position = board.coord_position(action["target"]) + Vector3(0, 0.10, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Animated materials must not mutate the shared static material cache.
	var mat: StandardMaterial3D = board.material(Color("ffe5a2"), true).duplicate()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	board.animation_root.add_child(ring)
	wave.set_parallel(true)
	wave.tween_property(ring, "scale", Vector3(2.9, 1, 2.9), 0.40).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	wave.tween_property(mat, "albedo_color", Color("ffe5a200"), 0.40)
	wave.tween_callback(func():
		for coord in action["annexed"]:
			board.cells[coord] = action["annexed"][coord].duplicate(true)
			board.dirty_tiles[coord] = true
			var tile: Node3D = board.tile_nodes[coord]
			for effect_name in ["Barrier", "Fortification"]:
				var effect := tile.get_node_or_null(effect_name)
				if effect != null:
					tile.remove_child(effect)
					effect.queue_free()
			preload("res://src/rendering/terrain_tile.gd").refresh(board, tile, coord, board.cells[coord], preload("res://src/rendering/terrain_tile.gd").joined_mask(board.cells, coord))
			board.populate_tile_decorations(tile, board.cells[coord])
			board.refresh_unit(coord, board.cells[coord])
			board.mark_batch_dirty(coord)
			action_marker(coord, board.COLORS[action["faction"]].lightened(0.25))
		# Compute joins only after the entire surrender has changed ownership.
		var joins: Dictionary = action["annexed"].duplicate()
		for coord in action["annexed"]:
			for direction in board.Grid.DIRECTIONS:
				if board.cells.has(coord + direction): joins[coord + direction] = true
		for coord in joins:
			var terrain = preload("res://src/rendering/terrain_tile.gd")
			terrain.update_join(board, board.tile_nodes[coord], board.cells[coord], terrain.joined_mask(board.cells, coord))
			board.mark_batch_dirty(coord)
		board.notify_visible_board_changed()
		board.motion_stage.emit(action, "surrender")).set_delay(0.16)
	var revision := animation_revision
	while wave.is_valid() and wave.is_running():
		await get_tree().process_frame
		if revision != animation_revision:
			return
	if is_instance_valid(ring):
		ring.queue_free()

