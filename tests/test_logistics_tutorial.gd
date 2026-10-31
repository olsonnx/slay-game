extends SceneTree
const Lessons = preload("res://src/game/tutorial_lessons.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	expect(Lessons.IDS.size() == 8 and "logistics" in Lessons.IDS, "The course includes a dedicated cities and supply-lines chapter")
	for category in Lessons.IDS:
		if category == "practice": continue
		var game = load("res://scenes/main.tscn").instantiate()
		game.initial_level_data = Lessons.map_data(category)
		root.add_child(game)
		game.tutorial = load("res://src/game/tutorial.gd").new(game)
		game.add_child(game.tutorial)
		game.playback_speed.speed_held = true
		await process_frame
		var count := 0
		while not game.tutorial.completed and count < 60:
			count += 1
			if game.tutorial.exercise_done:
				game.tutorial.continue_lesson()
				await process_frame
				continue
			if game.tutorial.reading_substeps():
				game.tutorial.continue_lesson()
				await process_frame
				continue
			var step: Dictionary = game.tutorial.current()
			var index: int = game.tutorial.index
			var target: Vector2i = step.target
			match step.kind:
				"move":
					var source: Vector2i = game.NONE
					for coord in game.cells:
						if step.details.has("source") and step.details.source != coord: continue
						if game.rules.unit_faction(coord) == 0 and game.rules.can_move(coord, target):
							source = coord
							break
					expect(source != game.NONE, "The teaching move is legal: " + category + "/" + step.id)
					if source == game.NONE: break
					await game.click_hex(source, "unit")
					await game.click_hex(target)
				"recruit":
					await game.click_hex(target, "terrain")
					game.choose_unit(step.details.tier)
					expect(game.view.overlay_root.has_node("RecruitmentArea"), "The lesson shows legal recruitment areas: " + category + "/" + step.id)
					await game.click_hex(target)
				"build":
					game.choose_building(step.details.building)
					await game.click_hex(target)
				"road":
					game.inspect_province(step.details.source)
					game.province_view.road_button.pressed.emit()
					game.update_hover(target, 0.0)
					expect(game.view.overlay_root.has_node("RoadPreview") and game.hud.world_tip.visible, "The lesson shows the road shape and price: " + step.id)
					await game.click_hex(target)
				"rename_settlement":
					game.inspect_province(target)
					game.province_view.name_input.grab_focus()
					game.province_view.name_input.text = "   "
					game.province_view.name_input.text_submitted.emit("   ")
					expect(game.tutorial.index == index, "A blank reset cannot complete the city-naming lesson")
					game.province_view.name_input.grab_focus()
					game.province_view.name_input.text = "Forward City"
					game.province_view.name_input.text_submitted.emit("Forward City")
				"spell":
					game.choose_spell(step.details.spell)
					await game.click_hex(target)
				"end_turn": await game.end_turn()
				"inspect": await game.click_hex(target, "terrain")
				"develop": game.develop_province()
				"finance":
					var tip = game.hud.gold_control._make_custom_tooltip(game.hud.gold_control.tooltip_text)
					tip.free()
				"event": game.resolve_shown_event(0)
				"continue": game.tutorial.continue_lesson()
			if game.tutorial.awaiting_confirmation:
				expect(game.tutorial.index == index, "Reading objectives wait for acknowledgement: " + step.id)
				game.tutorial.continue_button.pressed.emit()
			await process_frame
			if step.id == "road_march": expect(game.rules.cells[target].unit == 3 and game.rules.cells[target].moved, "The supply-line lesson completes a six-hex Knight move using half-cost roads")
			if step.id == "merge_scouts": expect(game.rules.cells[target].unit == 2 and game.rules.cells[target].moved, "The army lesson preserves a spent action through merging")
			if step.id == "upgrade_soldier": expect(game.rules.cells[target].unit == 3 and game.rules.cells[target].moved, "The army lesson preserves a spent action through upgrading")
			expect(game.tutorial.index != index or game.tutorial.completed or game.tutorial.exercise_done, "The objective advances through real commands: " + category + "/" + step.id)
			if game.tutorial.index == index and not game.tutorial.completed and not game.tutorial.exercise_done: break
		expect(game.tutorial.completed, "The experimental lesson is playable: " + category)
		game.queue_free()
		await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Logistics tutorial checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
