extends Node
## Owns settled actors, sprites and hover tweens. Playback borrows actors by hex.
## Metadata written here: unit_role, unit_state, hex, image, base_modulate, HoverOutline.
const Assets = preload("res://src/rendering/board_assets.gd")
const Sprites = preload("res://src/rendering/unit_sprite_library.gd")
const SPENT_COLOR := Color("a8b2ae")
var assets: Assets
var tile_nodes: Dictionary
var unit_batches
var units: Array[Sprite3D] = []
var unit_actors: Dictionary = {}
var hovered_unit: Sprite3D
var unit_hover_tweens: Dictionary = {}
var turn_faction := -2 # Standalone map/editor views have no turn restriction.
var idle_elapsed := 0.0
var idle_tick := 0
var idle_units: Dictionary = {}

func is_ready(cell: Dictionary) -> bool:
	var faction: int = cell.get("unit_owner", -1) if cell.get("building", "") == "bridge" else cell["owner"]
	return cell["unit"] > 0 and not cell["moved"] and (turn_faction == -2 or faction == turn_faction)

func set_turn(faction: int) -> void:
	if turn_faction == faction: return
	turn_faction = faction
	clear_unit_hover()
	var changed := {}
	for coord in unit_actors:
		var actor: Node3D = unit_actors[coord]
		if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not assets.cells.has(coord): continue
		if actor.get_meta("unit_ready", false) != is_ready(assets.cells[coord]):
			apply_readiness(actor, assets.cells[coord])
			changed[coord] = true
	if unit_batches != null and not changed.is_empty():
		unit_batches.queue_sync(changed, false)
		unit_batches.sync(true)

func apply_readiness(actor: Node3D, cell: Dictionary) -> void:
	var animator = actor.get_node("UnitAnimation")
	var ready := is_ready(cell)
	actor.set_meta("unit_ready", ready)
	animator.sprite.set_meta("unit_ready", ready)
	animator.sprite.set_meta("idle_texture", assets.soldier_texture(animator.tier, animator.faction_id))
	var base: Color = Color.WHITE if ready else SPENT_COLOR
	animator.sprite.set_meta("base_modulate", base)
	animator.sprite.modulate = base
	if ready: idle_units[actor] = animator
	else: idle_units.erase(actor)
	if animator.animation == "idle":
		animator.show_idle_frame(idle_tick % int(Sprites.clip(animator.tier,"idle")[1]) if ready else 0)
	if unit_batches != null: unit_batches.tint(animator.sprite, base)

func _process(delta: float) -> void:
	if not assets.active: return
	idle_elapsed += delta
	var tick := floori(idle_elapsed * 8.0)
	if tick == idle_tick: return
	idle_tick = tick
	for actor in idle_units.keys():
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			idle_units.erase(actor)
			continue
		var animator = idle_units[actor]
		if actor.get_meta("sprite_action_active", false): continue
		animator.show_idle_frame(tick % int(Sprites.clip(animator.tier,"idle")[1]))
		if animator.sprite == hovered_unit:
			animator.sprite.get_node("HoverOutline").texture = assets.soldier_hover_outline(animator.tier, animator.faction_id, animator.frame_index)
	if unit_batches != null: unit_batches.animate_idle(tick)
	assets.invalidate_pick()

func _init(factory: Assets, tiles: Dictionary) -> void:
	assets = factory
	tile_nodes = tiles

func remove_unit(coord: Vector2i) -> void:
	if unit_actors.has(coord):
		var actor: Node3D = unit_actors[coord]
		idle_units.erase(actor)
		for sprite in units.duplicate():
			if not is_instance_valid(sprite) or actor.is_ancestor_of(sprite):
				units.erase(sprite)
		if is_instance_valid(actor) and not actor.is_queued_for_deletion():
			actor.queue_free()
		unit_actors.erase(coord)

func settle_unit(actor: Node3D, source: Vector2i, target: Vector2i, cells: Dictionary) -> void:
	# The traveler already owns its sprite, assets.shadow and rank markers. Retain them
	# when it settles instead of allocating another complete actor after each move.
	var previous: Node3D = unit_actors.get(target)
	if is_instance_valid(previous) and previous != actor: remove_unit(target)
	if unit_actors.get(source) == actor: unit_actors.erase(source)
	actor.reparent(tile_nodes[target], true)
	actor.set_meta("hex", target)
	unit_actors[target] = actor
	actor.get_node("UnitAnimation").play("idle")
	refresh_unit(target, cells[target])

func refresh_unit(coord: Vector2i, cell: Dictionary) -> void:
	var actor: Node3D = unit_actors.get(coord)
	if is_instance_valid(actor) and (actor.is_queued_for_deletion() or actor.get_parent() != tile_nodes[coord]):
		remove_unit(coord)
		actor = null
	if cell["unit"] == 0:
		remove_unit(coord)
		return
	if actor == null:
		unit_actors[coord] = add_unit(tile_nodes[coord], cell["unit"], cell.get("unit_owner", -1) if cell["building"] == "bridge" else cell["owner"], cell["moved"], cell["capital"] >= 0)
		return
	var owner: int = cell.get("unit_owner", -1) if cell["building"] == "bridge" else cell["owner"]
	var state := [cell["unit"], owner, cell["moved"], cell["capital"] >= 0]
	var position_wanted := Vector3(0.35, 0, 0.30) if cell["capital"] >= 0 else Vector3.ZERO
	if actor.get_meta("unit_state", []) == state and actor.position == position_wanted:
		return
	actor.get_node("UnitAnimation").configure(cell["unit"],owner)
	actor.set_meta("unit_state", state)
	actor.position = position_wanted
	for child in actor.get_children():
		if child is Sprite3D:
			child.texture = assets.soldier_texture(cell["unit"], owner)
			child.set_meta("image", assets.image_cache[Vector2i(cell["unit"], owner)])
			child.modulate = Color("a8b2ae") if cell["moved"] else Color.WHITE
			child.set_meta("base_modulate", child.modulate)
			child.get_node("HoverOutline").texture = assets.soldier_hover_outline(cell["unit"], owner)
			child.get_node("HoverOutline").pixel_size = child.pixel_size
	var pips := actor.get_node("Pips")
	if pips.get_child_count() != cell["unit"]:
		for child in pips.get_children():
			pips.remove_child(child)
			child.queue_free()
		for index in range(cell["unit"]):
			assets.cylinder(pips, Vector3((index - (cell["unit"] - 1) * 0.5) * 0.11, 0.045, 0.40), 0.035, 0.035, 0.025, Color("f0dba3"), 8)
	apply_readiness(actor, cell)

func add_unit(parent: Node3D, tier: int, owner: int, moved: bool, on_capital: bool) -> Node3D:
	var offset := Vector3(0.35, 0, 0.30) if on_capital else Vector3.ZERO
	var actor := Node3D.new()
	actor.name = "Unit"
	actor.set_meta("unit_role", true)
	actor.set_meta("unit_state", [tier, owner, moved, on_capital])
	actor.position = offset
	actor.set_meta("hex", parent.get_meta("hex"))
	parent.add_child(actor)
	assets.shadow(actor, Vector3.ZERO, 0.9)
	var unit := Sprite3D.new()
	unit.texture = assets.soldier_texture(tier, owner)
	unit.set_meta("image", assets.image_cache[Vector2i(tier, owner)])
	unit.pixel_size = preload("res://src/rendering/unit_sprite_library.gd").pixel_size(tier)
	unit.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	unit.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	unit.shaded = false
	unit.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	unit.position = Vector3(0, preload("res://src/rendering/unit_sprite_library.gd").height(tier), 0)
	unit.modulate = Color("a8b2ae") if moved else Color.WHITE
	unit.set_meta("base_modulate", unit.modulate)
	unit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	actor.add_child(unit)
	units.append(unit)
	var hover_outline := Sprite3D.new()
	hover_outline.name = "HoverOutline"
	hover_outline.texture = assets.soldier_hover_outline(tier, owner)
	hover_outline.pixel_size = unit.pixel_size
	hover_outline.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hover_outline.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	hover_outline.modulate.a = 0
	hover_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	unit.add_child(hover_outline)
	hover_outline.hide()
	var animator := preload("res://src/rendering/unit_sprite_animation.gd").new(assets,unit,tier,owner)
	animator.name = "UnitAnimation"
	actor.add_child(animator)
	animator.play("idle")
	var pips := Node3D.new()
	pips.name = "Pips"
	actor.add_child(pips)
	for index in range(tier):
		assets.cylinder(pips, Vector3((index - (tier - 1) * 0.5) * 0.11, 0.045, 0.40), 0.035, 0.035, 0.025, Color("f0dba3"), 8)
	apply_readiness(actor, {"unit":tier,"owner":owner,"moved":moved})
	return actor

func set_unit_hover(coord: Vector2i, enabled: bool) -> void:
	var next: Sprite3D
	if enabled and unit_actors.has(coord):
		for child in unit_actors[coord].get_children():
			if child is Sprite3D and child.is_visible_in_tree():
				next = child
				break
	if next == hovered_unit:
		return
	if is_instance_valid(hovered_unit):
		fade_unit_hover(hovered_unit, false)
	hovered_unit = next
	if is_instance_valid(next):
		var animator = next.get_parent().get_node("UnitAnimation")
		next.get_node("HoverOutline").texture = assets.soldier_hover_outline(animator.tier,animator.faction_id,animator.frame_index)
		fade_unit_hover(next, true)

func fade_unit_hover(unit: Sprite3D, highlighted: bool) -> void:
	var previous: Tween = unit_hover_tweens.get(unit)
	if previous != null and previous.is_valid():
		previous.kill()
	var base: Color = unit.get_meta("base_modulate")
	var target := base * Color(1.18, 1.14, 1.06, 1) if highlighted else base
	var tween := unit.create_tween()
	unit_hover_tweens[unit] = tween
	var outline: Sprite3D = unit.get_node("HoverOutline")
	outline.show()
	tween.set_parallel(true)
	tween.tween_property(unit, "modulate", target, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(color: Color): unit_batches.tint(unit, color), unit.modulate, target, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(outline, "modulate:a", 0.80 if highlighted else 0.0, 0.12)
	tween.chain().tween_callback(func():
		if not highlighted:
			outline.hide()
		if unit_hover_tweens.get(unit) == tween:
			unit_hover_tweens.erase(unit)
		unit_batches.tint(unit, unit.modulate))

func clear_unit_hover() -> void:
	for unit in unit_hover_tweens:
		var tween: Tween = unit_hover_tweens[unit]
		if tween.is_valid():
			tween.kill()
		if is_instance_valid(unit):
			unit.modulate = unit.get_meta("base_modulate")
			unit_batches.tint(unit, unit.modulate)
			unit.get_node("HoverOutline").hide()
			unit.get_node("HoverOutline").modulate.a = 0
	unit_hover_tweens.clear()
	if is_instance_valid(hovered_unit):
		hovered_unit.modulate = hovered_unit.get_meta("base_modulate")
		unit_batches.tint(hovered_unit, hovered_unit.modulate)
		hovered_unit.get_node("HoverOutline").hide()
		hovered_unit.get_node("HoverOutline").modulate.a = 0
	hovered_unit = null
