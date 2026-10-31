extends SceneTree
## Income investment coverage migrated from houses to province development.
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
func investments(model) -> Array:
	return Candidates.preparation(model, 0).filter(func(action): return action.kind == "develop")
func fixture():
	var model = Rules.new()
	for x in range(3): model.cells[Vector2i(x,0)] = model.make_cell(0)
	model.cells[Vector2i(3,0)] = model.make_cell()
	model.cells[Vector2i.ZERO].capital = 0
	model.rebuild_kingdoms()
	model.kingdom_at(Vector2i.ZERO).gold = 500
	return model
func run() -> void:
	var model = fixture()
	var options := investments(model)
	expect(not options.is_empty(), "AI can invest in province income under current rules")
	var bank: Dictionary = model.kingdom_at(Vector2i.ZERO)
	var income: int = model.income(bank)
	var gold: int = bank.gold
	var cost: int = model.development_cost(options[0].coord)
	expect(Candidates.apply(model,options[0],0) and model.income(bank) == income+1 and bank.gold == gold-cost,"Income investment uses the authoritative development price and reward")
	for cell in model.cells.values(): cell.value = model.MAX_VALUE
	expect(investments(model).is_empty(), "AI stops development at the province value cap")
	model = fixture()
	model.cells[Vector2i(1,0)].unit = 3
	model.kingdom_at(Vector2i.ZERO).gold = 22
	expect(investments(model).is_empty(), "Income investment cannot consume the wages needed for settlement")
	for difficulty in ["easy","normal","hard"]:
		model = fixture()
		model.ai_difficulty = difficulty
		for purchase in range(12):
			options = investments(model)
			if options.is_empty(): break
			expect(Candidates.apply(model,options[0],0),"Repeated investments remain legal on "+difficulty)
		for cell in model.cells.values():
			expect(cell.building == "" and cell.value <= model.MAX_VALUE,"Development preserves deployment space and obeys the value cap")
		expect(model.can_recruit(Vector2i.ZERO,0,1),"Income investment leaves recruitment legal on "+difficulty)
	model = fixture()
	bank = model.kingdom_at(Vector2i.ZERO)
	income = model.income(bank)
	expect(not model.build_structure(Vector2i(1,0),0,"house"),"Retired houses are rejected by current construction rules")
	expect(model.build_structure(Vector2i(1,0),0,"city") and model.income(bank) == income,"Recruitment cities do not replace the retired house income bonus")
	print("AI housing checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
