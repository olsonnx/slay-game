extends SceneTree

var game
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func right_click(drag := Vector2.ZERO) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	game._input(event)
	game._unhandled_input(event)
	if drag != Vector2.ZERO:
		var motion := InputEventMouseMotion.new()
		motion.relative = drag
		game._input(motion)
	event.pressed = false
	game._input(event)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var reference := Vector2(420, 310)
	var moved_cursor := Vector2(610, 390)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.position = reference
	right.pressed = true
	game._input(right)
	game._unhandled_input(right)
	var rotation := InputEventMouseMotion.new()
	rotation.position = moved_cursor
	rotation.relative = moved_cursor - reference
	game._input(rotation)
	var anchor: Vector3 = game.view.navigation._ground_at(reference)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.position = moved_cursor
	wheel.pressed = true
	game._unhandled_input(wheel)
	game.view.navigation._process(0.02)
	expect(game.view.navigation.zoom_cursor == reference and game.view.camera.unproject_position(anchor).distance_to(reference) < 0.05, "RMB zoom uses the original press position after dragging")
	game._input(rotation)
	expect(game.view.navigation.zooming, "Orbit motion keeps smooth zoom running")
	anchor = game.view.navigation._ground_at(reference)
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	game._unhandled_input(wheel)
	game.view.navigation._process(0.1)
	expect(game.view.camera.unproject_position(anchor).distance_to(reference) < 0.05, "RMB zoom-out also uses the original press position")
	right.pressed = false
	game._input(right)
	game._unhandled_input(wheel)
	expect(game.view.navigation.zoom_cursor == moved_cursor, "Releasing RMB restores zoom at the current cursor")
	right.pressed = true
	game._input(right)
	game._unhandled_input(right)
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect(game.view.zoom_reference == Vector2(-1, -1), "Focus loss clears the held zoom reference")
	game.center_camera()
	var middle := InputEventMouseButton.new()
	middle.button_index = MOUSE_BUTTON_MIDDLE
	middle.pressed = true
	game.choose_unit(1)
	for top_down in [false, true]:
		game.center_camera()
		if top_down:
			game.toggle_view()
		game._unhandled_input(middle)
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(48, 32)
		var before: Vector2 = game.view.camera.unproject_position(Vector3.ZERO)
		game._input(motion)
		var after: Vector2 = game.view.camera.unproject_position(Vector3.ZERO)
		expect((after - before).is_equal_approx(motion.relative) and game.action_mode == "recruit", "Middle drag moves the map with the pointer in both views without cancelling placement")
		middle.pressed = false
		game._input(middle)
		expect(not game.mmb_down, "Middle release stops panning even when consumed by UI")
		middle.pressed = true
	game._unhandled_input(middle)
	game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	expect(not game.mmb_down, "Losing window focus clears middle-mouse gesture")
	game.cancel_action()
	game.center_camera()
	game.view_button.button_down.emit()
	game.advance_view_press(0.1)
	expect(game.view_hold_indicator.visible and game.view_hold_indicator.progress > 0 and game.view_hold_indicator.progress < 1, "Hold border shows progress before the reset threshold")
	game.view_button.button_up.emit()
	expect(not game.view_hold_indicator.visible, "Releasing a short hold clears the border")
	game.view_button.pressed.emit()
	expect(game.view.top_down and game.view_button.text == "" and game.view_button.icon == game.VIEW_TOP_ICON, "Short view press switches mode and its icon")
	game.view.focus = Vector3(4, 0, 3)
	game.view.zoom = 12
	game.view_button.button_down.emit()
	game.advance_view_press(0.6)
	expect(game.view_hold_indicator.progress == 1 and game.view_hold_indicator.visible, "Completed camera reset fills the entire hold border")
	expect(game.view.focus == game.view.map_center and game.view.zoom == game.view.default_zoom and not game.view.top_down and game.view_button.icon == game.VIEW_3D_ICON, "Holding the view button restores fitted world-center framing")
	game.view_button.button_up.emit()
	game.view_button.pressed.emit()
	expect(not game.view.top_down, "Releasing a long press does not also switch views")
	game.view_button.button_down.emit()
	game.cancel_view_press()
	expect(not game.view_hold_indicator.visible, "Cancelled hold clears its indicator")
	game.advance_view_press(1)
	game.view_button.pressed.emit()
	expect(not game.view.top_down, "Leaving the held view control cancels its gesture")
	expect(game.level_label.text == "Level 1" and game.round_label.text.contains("Quick Play") and not game.round_label.text.contains("Classic"), "HUD identifies the current level and Quick Play mode")
	game.busy = true
	game.active_faction = 1
	game.refresh_ui()
	var spinner_rotation: float = game.turn_spinner.rotation
	await create_timer(0.08).timeout
	expect(game.turn_spinner.visible and game.turn_spinner.rotation != spinner_rotation and not game.end_button.disabled, "Opponent processing displays a spinning indicator and permits holding the turn button")
	paused = true
	spinner_rotation = game.turn_spinner.rotation
	await create_timer(0.08, true).timeout
	expect(game.turn_spinner.rotation == spinner_rotation, "Turn spinner pauses with gameplay")
	paused = false
	game.busy = false
	game.active_faction = 0
	game.refresh_ui()
	expect(not game.turn_spinner.visible, "Turn spinner hides after processing finishes")
	var owned: Array = game.active_kingdom()["hexes"]
	var unit := game.NONE as Vector2i
	var empty := game.NONE as Vector2i
	for coord in owned:
		if game.cells[coord]["unit"] > 0:
			unit = coord
		elif game.cells[coord]["capital"] < 0:
			empty = coord
	game.active_kingdom()["gold"] = 100
	game.click_hex(unit)
	var yaw: float = game.view.yaw
	right_click(Vector2(1, 1))
	expect(game.selected == game.NONE and game.valid_targets.is_empty(), "RMB click with small jitter cancels movement selection")
	expect(game.view.yaw == yaw, "Cancellation click does not rotate the camera")
	game.choose_unit(1)
	right_click()
	expect(game.action_mode == "" and game.recruit_tier == 0, "RMB cancels recruitment")
	game.choose_building("house")
	right_click()
	expect(game.action_mode == "", "RMB cancels building placement")
	game.open_shop("build")
	right_click()
	expect(not game.shop_panel.visible, "RMB closes an open action menu")
	game.choose_unit(2)
	right_click(Vector2(50, 15))
	expect(game.action_mode == "recruit" and game.view.yaw != yaw and not game.view.rotating, "RMB drag rotates without cancelling placement and release stops orbit")
	game.click_hex(game.NONE)
	expect(game.action_mode == "" and game.selected == game.NONE, "Click off map cancels placement")
	game.click_hex(unit)
	game.click_hex(game.NONE)
	expect(game.selected == game.NONE, "Click off map deselects a unit")
	game.click_hex(unit)
	game.hovered = empty
	game.refresh_ui()
	expect(game.view.intent_preview.get_meta("kind") == "move" and game.view.intent_preview.get_meta("valid"), "Hovered movement tile shows a valid arrow preview")
	game.choose_unit(2)
	game.hovered = empty
	game.refresh_ui()
	expect(game.view.intent_preview.has_node("GhostUnit") and game.view.intent_preview.get_meta("kind") == "recruit", "Recruitment previews a ghost unit on the hovered tile")
	game.hovered = unit
	game.refresh_ui()
	expect(game.view.intent_preview.get_meta("kind") == "upgrade" and game.view.intent_color(game.tile_intent(unit)) == game.view.intent_color({"kind": "merge", "valid": true}), "Recruitment upgrades use the same purple color as merging")
	expect(not game.view.intent_preview.has_node("GhostUnit") and game.view.intent_preview.has_node("UpgradeIndicator"), "Upgrade shows a rank badge instead of an overlapping soldier sprite")
	var indicator: Label3D = game.view.intent_preview.get_node("UpgradeIndicator")
	for overhead in [false, true]:
		if game.view.top_down != overhead:
			game.view.toggle_top_down()
		var head: Vector2 = game.view.camera.unproject_position(game.view.unit_actors[unit].global_position + Vector3(0, 0.87, 0))
		var badge: Vector2 = game.view.camera.unproject_position(indicator.global_position)
		expect(badge.y < head.y - 35, "Upgrade badge remains above the soldier in angled and overhead views")
	game.view.toggle_top_down()
	game.hovered = empty
	var count_before: int = game.view.unit_actors.size()
	game.choose_building("tower")
	game.refresh_ui()
	expect(game.view.intent_preview.has_node("GhostBuilding") and game.view.intent_preview.get_meta("kind") == "tower", "Tower placement previews a 3D ghost building")
	var tower_ghost: Node3D = game.view.intent_preview.get_node("GhostBuilding")
	var tower_material: Material = tower_ghost.get_child(0).material_override
	game.view.overlays.invalidate()
	game.refresh_ui()
	expect(game.view.intent_preview.get_node("GhostBuilding") == tower_ghost and tower_ghost.get_child(0).material_override == tower_material, "Hover refresh retains preview meshes and materials")
	game.choose_building("house")
	game.refresh_ui()
	expect(game.view.intent_preview.has_node("GhostBuilding") and game.view.intent_preview.get_meta("kind") == "house", "House placement previews the selected building")
	expect(tower_ghost.get_parent() == game.view.overlays.building_storage and tower_ghost.get_child(0).layers == 0, "Inactive previews return to their hidden cache")
	expect(game.view.unit_actors.size() == count_before and game.cells[empty]["building"] == "", "Previews never mutate gameplay or register as real units")
	game.hovered = unit
	game.refresh_ui()
	expect(not game.view.intent_preview.get_meta("valid") and not game.view.intent_preview.has_node("GhostBuilding"), "Invalid building destination shows a red marker without a ghost")
	game.cancel_action()
	expect(game.view.intent_preview == null, "Cancellation clears the intent preview immediately")
	game.hovered = empty
	game.choose_building("tower")
	game.refresh_ui()
	expect(game.view.intent_preview.get_node("GhostBuilding") == tower_ghost, "Reselecting a building reuses its original preview")
	expect(game.view.overlays.building_ghosts.size() == 3, "Preview retention is bounded to the three building kinds")
	game.cancel_action()

	var previous_mode: String = game.rules.rule_mode
	game.rules.rule_mode = "modern"
	game.cells[empty]["animal"] = "wolf"
	game.cells[empty]["animal_home"] = empty
	game.cells[empty]["animal_target"] = unit
	game.view.render_cells(game.cells)
	game.inspect_province(empty)
	expect(game.province_view.visible, "Province panel starts open before selecting wildlife")
	await game.click_hex(empty, "wildlife")
	expect(not game.province_view.visible and game.session.selection.inspected_hex == game.NONE, "Clicking wildlife closes province information")
	expect(game.session.selection.inspected_animal == empty and game.selected == game.NONE, "Wildlife is inspected independently from its province")
	var animal_region: Dictionary = game.view.overlays.inspection_region(game.session.selection.inspected_animal)
	expect(animal_region.get("kind") == "vision" and animal_region.get("target") == unit, "Animal selection retains its vision and chased target")
	var animal: Sprite3D = game.view.wildlife.sprite_for(game.view.wildlife.actors[empty])
	game.view.set_unit_hover(empty, "wildlife")
	game.view.wildlife._process(0.12)
	var animal_outline: Sprite3D = animal.get_node("HoverOutline")
	expect(animal_outline.visible and animal_outline.texture != null and animal.modulate.r > 1.0, "Hovering wildlife outlines and brightens the animal")
	var cached_outline: Texture2D = animal_outline.texture
	game.view.wildlife._process(0.0)
	expect(animal_outline.texture == cached_outline and animal_outline.pixel_size == animal.pixel_size, "Animal outlines reuse cached frames at the original pixel scale")
	game.view.set_unit_hover(game.NONE)
	game.view.wildlife._process(0.12)
	expect(not animal_outline.visible and animal.modulate == Color.WHITE, "Moving off wildlife restores its normal appearance")
	game.view.set_unit_hover(empty, "wildlife")
	game.view.wildlife._process(0.12)
	game.view.clear_unit_hover()
	expect(not animal_outline.visible and animal.modulate == Color.WHITE, "Clearing unit hover also clears wildlife highlights")
	game.cancel_action()
	expect(game.session.selection.inspected_animal == game.NONE, "Cancellation clears animal inspection")
	for key in ["animal", "animal_home", "animal_target"]: game.cells[empty].erase(key)
	game.view.render_cells(game.cells)

	game.rules.rule_mode = previous_mode
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	var c := Vector2i(2, 0)
	var d := Vector2i(3, 0)
	game.rules.cells.clear()
	game.rules.kingdoms.clear()
	for coord in [a, b, c, d]:
		game.rules.cells[coord] = game.rules.make_cell(0 if coord.x < 2 else 1)
	game.rules.rebuild_kingdoms()
	game.cells[b]["unit"] = 2
	game.cells[c]["unit"] = 1
	for kingdom in game.rules.kingdoms.values():
		kingdom["gold"] = 100
	game.active_hex = a
	game.view.render_cells(game.cells)
	game.click_hex(b)
	game.hovered = c
	game.refresh_ui()
	expect(game.view.intent_preview.get_meta("kind") == "attack", "Enemy unit tile indicates an attack")
	var before_cells: Dictionary = game.cells.duplicate(true)
	var before_kingdoms: Dictionary = game.rules.kingdoms.duplicate(true)
	game.click_hex(c)
	await create_timer(0.29).timeout
	expect(game.busy and game.cells[c]["owner"] == 0, "Attack is committed while its animation is still playing")
	right_click()
	expect(not game.busy and game.cells == before_cells and game.rules.kingdoms == before_kingdoms, "RMB restores units, ownership, capitals, and treasuries after cancelling an unfinished attack")
	await create_timer(0.35).timeout
	expect(game.cells == before_cells and game.view.cells == before_cells and game.view.active_motions.is_empty(), "Cancelled tweens and coroutine cannot later reapply the attack")
	game.click_hex(b)
	game.click_hex(c)
	await create_timer(0.06).timeout
	game.click_hex(game.NONE)
	expect(not game.busy and game.cells == before_cells, "Clicking off map also cancels a traveling player unit")
	await process_frame
	game.click_hex(b)
	await game.click_hex(c)
	expect(not game.busy and game.cells[c]["owner"] == 0, "A fresh move still completes after prior moves were cancelled")
	print("Input and preview checks: %d passed, %d failed" % [checks - failures, failures])
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.20).timeout
	quit(1 if failures else 0)
