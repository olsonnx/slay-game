extends RefCounted
## Authored starting positions. Objectives never replace the evolving board.
const Rules = preload("res://src/game/kingdom_rules.gd")

static func map_data(category: String) -> Dictionary:
	if category not in ["basics","intermediate","advanced"]: category = "basics"
	var doc = preload("res://src/editor/level_document.gd").new()
	doc.title = "Tutorial: " + category.capitalize()
	doc.map_size = "small"
	doc.rule_mode = "modern"
	doc.seed_value = 73015
	doc.starting_gold = {"basics":10,"intermediate":20,"advanced":50}[category]
	var rules := Rules.new()
	var value: int = {"basics":2,"intermediate":3,"advanced":5}[category]
	for q in range(-4 if category == "intermediate" else -3,0):
		for r in range(-1,2):
			doc.cells[Vector2i(q,r)] = rules.make_cell(0)
			doc.cells[Vector2i(q,r)]["value"] = value
	doc.cells[Vector2i(-3,0)]["capital"] = 0
	var offset := 1 if category == "advanced" else 0
	for coord in [Vector2i(1,0),Vector2i(1,1),Vector2i(2,0),Vector2i(2,-1),Vector2i(2,1),Vector2i(3,0)]:
		var target: Vector2i = coord + Vector2i(offset,0)
		doc.cells[target] = rules.make_cell(1)
		doc.cells[target]["value"] = value
	doc.cells[Vector2i(2+offset,0)]["capital"] = 1
	if category == "advanced":
		doc.cells[Vector2i(-2,0)]["unit"] = 3
		doc.cells[Vector2i(2,0)]["unit"] = 2
		doc.cells[Vector2i(3,-1)]["building"] = "tower"
		for coord in [Vector2i(-3,0),Vector2i(-3,-1),Vector2i(-3,1),Vector2i(-2,-1)]: doc.cells[coord]["mana_source"] = true
		for coord in [Vector2i(1,0),Vector2i(1,-1)]:
			doc.cells[coord] = rules.make_cell(-1)
			doc.cells[coord]["value"] = 3
	else:
		doc.cells[Vector2i(0,0)] = rules.make_cell(-1)
		doc.cells[Vector2i(0,0)]["value"] = value
		doc.cells[Vector2i(2,-1)]["unit"] = 1 if category == "basics" else 2
		if category == "intermediate":
			for coord in [Vector2i(-4,-1),Vector2i(-4,0),Vector2i(-4,1)]: doc.cells[coord]["value"] = 2
			doc.cells[Vector2i(-3,0)]["capital"] = -1
			doc.cells[Vector2i(-4,0)]["capital"] = 0
			doc.cells[Vector2i(-3,0)]["unit"] = 1
			doc.cells[Vector2i(0,1)] = rules.make_cell(-1)
			doc.cells[Vector2i(0,1)]["value"] = value
	var data: Dictionary = doc.state()
	data["tutorial"] = true
	data["tutorial_category"] = category
	return data
