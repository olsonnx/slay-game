extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
func houses(model) -> Array:
	return Candidates.preparation(model, 0).filter(func(action): return action["kind"] == "house")
func fixture(length: int):
	var model = Rules.new()
	model.rule_mode = "modern"
	for x in range(length): model.cells[Vector2i(x,0)] = model.make_cell(0)
	model.cells[Vector2i(length,0)] = model.make_cell()
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.rebuild_kingdoms()
	model.kingdom_at(Vector2i.ZERO)["gold"] = 500
	return model
func run() -> void:
	var model = fixture(7)
	expect(not houses(model).is_empty(), "AI can still invest in housing when it needs reinforcement income")
	model.cells[Vector2i(1,0)]["building"] = "house"
	model.cells[Vector2i(2,0)]["building"] = "house"
	expect(houses(model).is_empty(), "AI stops housing once its reinforcement income target is met")
	model = fixture(7)
	for x in range(1,5): model.cells[Vector2i(x,0)]["building"] = "house"
	model.cells[Vector2i(5,0)]["unit"] = 3
	model.cells[Vector2i(6,0)]["unit"] = 3
	expect(houses(model).is_empty(), "Even a wage deficit cannot consume the final deployment sites")
	model = fixture(12)
	for x in range(1,9): model.cells[Vector2i(x,0)]["building"] = "house"
	model.cells[Vector2i(9,0)]["unit"] = 3
	model.cells[Vector2i(10,0)]["unit"] = 3
	model.cells[Vector2i(11,0)]["unit"] = 3
	expect(houses(model).is_empty(), "Occupied reserved sites do not justify filling the last open site")
	for difficulty in ["easy", "normal", "hard"]:
		model = fixture(7)
		model.ai_difficulty = difficulty
		for purchase in range(12):
			var options := houses(model)
			if options.is_empty(): break
			Candidates.apply(model, options[0], 0)
		var available := 0
		for cell in model.cells.values():
			if cell["owner"] == 0 and cell["building"] == "": available += 1
		expect(available >= 2, "Repeated housing preserves deployment space on " + difficulty)
		expect(model.can_recruit(Vector2i.ZERO, 0, 1), "Housing leaves recruitment legal on " + difficulty)
	print("AI housing checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
