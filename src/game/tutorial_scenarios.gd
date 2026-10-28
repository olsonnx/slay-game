extends RefCounted
## Small authored practice positions. Each exercise declares its own starting board.
const Rules = preload("res://src/game/kingdom_rules.gd")
const Level = preload("res://src/editor/level_document.gd")
const FIRST := {"armies":"opening","economy":"budget","construction":"city","conquest":"capital","magic":"trail","exploration":"chest","practice":"practice"}

static func map_data(category: String) -> Dictionary:
	if category != "practice": return preload("res://src/game/logistics_tutorial.gd").map_data(category)
	return position(FIRST.get(category,"opening"))

static func add(doc, at: Vector2i, owner: int, value := 1, fields: Dictionary = {}) -> void:
	var cell: Dictionary = Rules.new().make_cell(owner)
	cell.value = value
	cell.merge(fields,true)
	doc.cells[at] = cell

static func position(id: String) -> Dictionary:
	var doc := Level.new()
	doc.title = "Practice: " + id.capitalize()
	doc.map_size = "small"
	doc.seed_value = 73021
	doc.starting_gold = 30
	for q in range(-4,0):
		for r in range(-1,2): add(doc,Vector2i(q,r),0,1)
	doc.cells[Vector2i(-4,0)].capital = 0
	for at in [Vector2i(2,0),Vector2i(2,-1),Vector2i(3,0),Vector2i(3,-1)]: add(doc,at,1,2)
	doc.cells[Vector2i(3,0)].capital = 1
	for q in range(0,2):
		for r in range(-1,2): add(doc,Vector2i(q,r),-1,1)
	doc.cells[Vector2i(-3,0)].unit = 1
	match id:
		"opening":
			doc.cells.clear()
			for at in [Vector2i(-3,0),Vector2i(-3,-1),Vector2i(-3,1),Vector2i(-2,0),Vector2i(-2,-1),Vector2i(-1,0),Vector2i(-1,-1)]: add(doc,at,0,1)
			for at in [Vector2i(-3,0),Vector2i(-3,-1),Vector2i(-3,1),Vector2i(-2,-1)]: doc.cells[at].value = 2
			doc.cells[Vector2i(-3,0)].capital = 0
			doc.cells[Vector2i(-2,0)].unit = 1
			for q in range(0,3):
				for r in range(-1,2): add(doc,Vector2i(q,r),-1,1)
			for at in [Vector2i(4,0),Vector2i(4,-1),Vector2i(5,-1)]: add(doc,at,1,1)
			doc.cells[Vector2i(4,0)].capital = 1
			doc.starting_gold = 10
		"ranks","merge","duel","lair","cut_army":
			for cell in doc.cells.values():
				if cell.owner == 0: cell.value = 4
			doc.starting_gold = 60
			if id == "ranks":
				add(doc,Vector2i(0,-1),1,1,{"unit":1})
				add(doc,Vector2i(0,1),1,1,{"unit":2})
				for at in [Vector2i(1,-1),Vector2i(1,0),Vector2i(1,1)]: add(doc,at,1,1)
				add(doc,Vector2i(1,0),1,1,{"building":"tower"})
			elif id == "merge":
				doc.cells[Vector2i(-2,-1)].unit = 1
				add(doc,Vector2i(-1,-1),1,1,{"unit":3})
				for at in [Vector2i(0,-1),Vector2i(1,-1)]: add(doc,at,1,1)
			elif id == "duel":
				doc.cells[Vector2i(-3,0)].unit = 3
				add(doc,Vector2i(0,0),1,1,{"unit":3})
				add(doc,Vector2i(1,0),1,1)
			elif id == "lair":
				doc.cells[Vector2i(-3,0)].unit = 3
				doc.cells[Vector2i(-1,0)].building = "city"
				add(doc,Vector2i(0,0),-1,1)
				add(doc,Vector2i(0,1),-1,1,{"lair":"bear"})
				# One clear exit makes the first normal emergence easy to follow.
				for at in [Vector2i(1,1),Vector2i(1,0),Vector2i(-1,2),Vector2i(0,2)]: add(doc,at,-1,0,{"mountain":true})
			elif id == "cut_army":
				doc.cells[Vector2i(-3,0)].unit = 3
				for at in [Vector2i(0,1),Vector2i(1,0)]: add(doc,at,1,1)
				for at in [Vector2i(-1,2),Vector2i(0,2),Vector2i(-1,3)]: add(doc,at,1,1,{"unit":2})
				doc.starting_gold = 30
		"budget":
			doc.cells[Vector2i(-1,-1)].tree = true
			doc.starting_gold = 10
		"banks":
			for at in [Vector2i(1,0),Vector2i(1,-1),Vector2i(2,-1)]: add(doc,at,0,2)
			doc.cells[Vector2i(2,-1)].capital = 0
			doc.starting_gold = 10
		"deficit":
			for cell in doc.cells.values():
				if cell.owner == 0: cell.value = 3
			for at in [Vector2i(-4,-1),Vector2i(-4,0),Vector2i(-4,1)]: doc.cells[at].value = 4
			doc.cells[Vector2i(-3,0)].unit = 0
			doc.cells[Vector2i(-1,1)].unit = 3
			doc.cells[Vector2i(-2,0)].unit = 1
			add(doc,Vector2i(0,1),1,2,{"unit":2})
			add(doc,Vector2i(1,1),1,2)
			doc.starting_gold = 0
		"city","investment":
			doc.cells[Vector2i(-3,0)].unit = 0
			doc.starting_gold = 30 if id == "city" else 20
			if id == "investment":
				for cell in doc.cells.values():
					if cell.owner == 0: cell.value = 2
		"tower":
			add(doc,Vector2i(0,0),1,2,{"unit":2})
			add(doc,Vector2i(1,0),1,2)
			add(doc,Vector2i(1,1),-1,1)
			doc.starting_gold = 20
		"bridge":
			for r in range(-1,2): doc.cells.erase(Vector2i(0,r))
			doc.starting_gold = 20
		"capital":
			for cell in doc.cells.values():
				if cell.owner == 0: cell.value = 3
			doc.cells[Vector2i(-3,0)].unit = 2
			doc.cells[Vector2i(3,0)].capital = -1
			add(doc,Vector2i(0,-1),1,1,{"unit":1})
			add(doc,Vector2i(1,0),1,1,{"building":"tower"})
			add(doc,Vector2i(1,-1),1,1,{"capital":1})

			# This is one small kingdom; remote land would create another capital.
			for at in [Vector2i(2,0),Vector2i(2,-1),Vector2i(3,0),Vector2i(3,-1)]: doc.cells.erase(at)
		"cut":
			doc.cells[Vector2i(-3,0)].unit = 2
			for at in [Vector2i(0,1),Vector2i(1,1),Vector2i(1,0)]: add(doc,at,1,2)
			add(doc,Vector2i(-1,2),1,1,{"unit":1})
		"relocate":
			doc.cells[Vector2i(-4,0)].capital = -1
			doc.cells[Vector2i(-1,0)].capital = 0
			add(doc,Vector2i(0,0),1,2,{"unit":2})
			add(doc,Vector2i(1,0),1,2)
			doc.starting_gold = 20
		"trail","summon","shatter":
			for at in [Vector2i(-4,0),Vector2i(-4,-1),Vector2i(-4,1),Vector2i(-3,-1)]: doc.cells[at].mana_source = true
			if id == "trail": doc.cells[Vector2i(0,0)].mana_source = true
			if id == "summon": doc.cells[Vector2i(-3,0)].unit = 0
			if id == "shatter": add(doc,Vector2i(0,0),-1,0,{"building":"bridge"})
		"chest": doc.cells[Vector2i(0,0)]["treasure"] = 15
		"event": doc.cells[Vector2i(0,0)].event = "comet"
		"landmark":
			for cell in doc.cells.values():
				if cell.owner == 0: cell.value = 4
			doc.cells[Vector2i(-3,0)].unit = 3
			doc.cells[Vector2i(0,0)].event = "stainless_steel"
		"practice":
			var rules := Rules.new()
			rules.generate(73021,"small",2)
			doc.cells = rules.cells.duplicate(true)
			doc.starting_gold = 10
	return doc.state()
