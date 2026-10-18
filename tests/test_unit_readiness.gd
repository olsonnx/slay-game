extends SceneTree
var checks := 0
var failures := 0
var game

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for x in range(10):
		var coord := Vector2i(x,0)
		game.cells[coord] = game.rules.make_cell(0 if x < 5 else 1)
	game.rules.rebuild_kingdoms()
	for kingdom in game.rules.kingdoms.values(): kingdom.gold = 1000
	var source := Vector2i(1,0)
	var spent := Vector2i(2,0)
	var enemy := Vector2i(6,0)
	var bridge := Vector2i(4,1)
	game.cells[source].unit = 1
	game.cells[spent].unit = 2
	game.cells[spent].moved = true
	game.cells[enemy].unit = 3
	game.cells[bridge] = game.rules.make_cell(-1)
	game.cells[bridge].building = "bridge"
	game.cells[bridge].unit = 1
	game.cells[bridge].unit_owner = 0
	game.rules.human_factions = [0,1]
	game.rules.faction_count = 2
	game.turn_order = [0,1]
	game.active_faction = 0
	game.player_faction = 0
	game.active_hex = source
	game.view.render_cells(game.cells)
	game.refresh_ui()
	await process_frame
	await process_frame
	var presentation = game.view.unit_presentation
	var animator = game.view.unit_actors[source].get_node("UnitAnimation")
	var spent_animation = game.view.unit_actors[spent].get_node("UnitAnimation")
	var enemy_animation = game.view.unit_actors[enemy].get_node("UnitAnimation")
	expect(animator.sprite.get_meta("unit_ready") and animator.sprite.modulate == Color.WHITE, "Unspent active troops are bright and ready")
	expect(not spent_animation.sprite.get_meta("unit_ready") and spent_animation.sprite.modulate != Color.WHITE, "Moved troops are still and dim")
	expect(not enemy_animation.sprite.get_meta("unit_ready") and enemy_animation.sprite.modulate != Color.WHITE, "Inactive kingdoms are dim even when their troops never moved")
	expect(game.view.unit_actors[bridge].get_meta("unit_ready"), "Bridge readiness follows the soldier's faction")
	var before: Texture2D = animator.sprite.texture
	var spent_before: Texture2D = spent_animation.sprite.texture
	var enemy_before: Texture2D = enemy_animation.sprite.texture
	var uploads: int = game.view.unit_batches.upload_count
	await create_timer(0.20).timeout
	expect(animator.sprite.texture != before, "Ready units play their idle frames")
	expect(spent_animation.sprite.texture == spent_before and enemy_animation.sprite.texture == enemy_before, "Spent and inactive units keep their resting pose")
	expect(game.view.unit_batches.upload_count == uploads and animator.sprite.layers == 0, "Idle frames animate inside existing army batches without instance uploads")
	var slot: Array = game.view.unit_batches.sprite_slots[animator.sprite.get_instance_id()]
	expect(slot[0].get_ref().material_override.albedo_texture == animator.sprite.texture, "Rendered batch and pixel picking use the same idle frame")
	presentation.set_unit_hover(source,true)
	await create_timer(0.20).timeout
	expect(animator.sprite.get_node("HoverOutline").texture == game.view.soldier_hover_outline(1,0,animator.frame_index), "Hover outlines follow the animated silhouette")
	game.view.clear_unit_hover()
	var frame: int = animator.frame_index
	paused = true
	await create_timer(0.20,true).timeout
	expect(animator.frame_index == frame, "Pause freezes the shared idle clock")
	paused = false
	await game.end_turn()
	expect(game.player_faction == 1 and not game.cells[source].moved, "Ending a turn preserves the unused troop's authoritative move record")
	expect(not animator.sprite.get_meta("unit_ready") and animator.sprite.modulate != Color.WHITE and animator.frame_index == 0, "An unused troop stops idling and darkens when its turn ends")
	expect(enemy_animation.sprite.get_meta("unit_ready") and enemy_animation.sprite.modulate == Color.WHITE, "The next kingdom's available troops become bright and animate")
	expect(not game.view.unit_actors[bridge].get_meta("unit_ready"), "Unused bridge troops also darken after their turn")
	await game.end_turn()
	expect(game.player_faction == 0 and animator.sprite.get_meta("unit_ready"), "Readiness returns on the troop's next turn")
	expect(not game.cells[spent].moved and spent_animation.sprite.get_meta("unit_ready"), "Previously moved troops regain idle animation at the next turn")
	game.view.unit_batches.enabled = false
	game.view.unit_batches.sync()
	before = animator.sprite.texture
	await create_timer(0.20).timeout
	expect(animator.sprite.layers != 0 and animator.sprite.texture != before, "Idle animation also works without army batching")
	game.shutdown()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(0.3).timeout
	print("Unit readiness checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
