extends RefCounted
## Board rules are independent of the UI so topology and economy can be tested.

const Grid = preload("res://src/game/hex_grid.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const DIRECTIONS = Grid.DIRECTIONS
const UNIT_COST = Catalog.UNIT_COST
const TOWER_COST = Catalog.TOWER_COST
const HOUSE_COST = Catalog.HOUSE_COST
const HOUSE_INCOME = Catalog.HOUSE_INCOME
const BRIDGE_COST = Catalog.BRIDGE_COST
const NONE = Grid.NONE
const Spells = preload("res://src/game/spell_catalog.gd")
const KingdomAI = preload("res://src/game/kingdom_ai.gd")
const MapGenerator = preload("res://src/game/map_generator.gd")
const MapSizes = preload("res://src/game/map_sizes.gd")
const Magic = preload("res://src/game/kingdom_magic.gd")
const Movement = preload("res://src/game/kingdom_movement.gd")
const Topology = preload("res://src/game/kingdom_topology.gd")
const Construction = preload("res://src/game/kingdom_construction.gd")
const MAX_VALUE := 6
const DEVELOPMENT_BASE_COST := 2

var cells: Dictionary = {}
var kingdoms: Dictionary = {}
var rng := RandomNumberGenerator.new()
var level_seed := -1
var rule_mode := "classic"
var mana_by_faction: Dictionary = {}
var map_size := "small"
var faction_count := 4
var initial_kingdom_count := 0
var ai_difficulty := "normal"
var ai_algorithm := "auto"
var incremental_kingdoms := true
var ai_revision := 0
var ai_last_decision: Dictionary = {}
const Events = preload("res://src/game/event_catalog.gd")
var effects_by_faction: Dictionary = {}
var capital_relocations: Dictionary = {}
var human_factions: Array = [0]
var faction_names: Array = Catalog.FACTIONS.duplicate()
var pending_events: Array[Dictionary] = []
var magic = Magic.new()
var replay_log

func record_replay(kind: String, faction := -1, arguments: Dictionary = {}) -> void:
	if replay_log != null: replay_log.record(self, kind, faction, arguments)

func bridge_bounds() -> Vector2:
	return MapSizes.generation_bounds(map_size) + Vector2(5.7, 6.0)

func is_modern() -> bool:
	return rule_mode == "modern"

func uses_strategic_ai() -> bool:
	# Whole-board beam simulations already become costly in Large midgames.
	# Use actual board size so editor maps receive the same protection too.
	return ai_algorithm == "strategic" or (ai_algorithm == "auto" and cells.size() >= 200)

func make_cell(owner := -1) -> Dictionary:
	return {"owner": owner, "unit": 0, "moved": false, "capital": -1,
		"tree": false, "grave": false, "building": "", "kingdom": NONE,
		"value": 1, "mana_source": false, "unit_owner": -1, "unit_home": NONE,
		"fortified": false, "fortified_by": -1, "mountain": false,
		"barrier_by": -1, "barrier_used": false, "event": ""}

func is_entrenched(coord: Vector2i) -> bool:
	return cells.has(coord) and cells[coord]["unit"] > 0 and cells[coord].get("entrenched_by", -1) == unit_faction(coord) and unit_faction(coord) >= 0

func can_entrench(coord: Vector2i, faction: int) -> bool:
	return is_modern() and cells.has(coord) and cells[coord]["unit"] > 0 and unit_faction(coord) == faction and not cells[coord]["moved"] and not is_entrenched(coord) and not is_mountain(coord) and not is_barrier(coord)

func entrench(coord: Vector2i, faction: int) -> bool:
	if not can_entrench(coord, faction): return false
	cells[coord]["entrenched_by"] = faction
	cells[coord]["moved"] = true
	record_replay("entrench", faction, {"coord":coord})
	return true

func is_mountain(coord: Vector2i) -> bool:
	return cells.has(coord) and cells[coord].get("mountain", false)

func is_bridge(coord: Vector2i) -> bool:
	return cells.has(coord) and cells[coord]["building"] == "bridge"

func unit_faction(coord: Vector2i) -> int:
	return cells[coord].get("unit_owner", -1) if is_bridge(coord) else cells[coord]["owner"]

func unit_kingdom(coord: Vector2i) -> Dictionary:
	var local := kingdom_at(coord)
	if not local.is_empty() or not is_modern():
		return local
	if cells[coord]["unit"] == 0:
		return {}
	var faction := unit_faction(coord)
	var routes := friendly_routes(coord)
	var home: Vector2i = cells[coord].get("unit_home", NONE)
	if routes.has(home) and kingdoms.has(home) and kingdoms[home]["owner"] == faction:
		return kingdoms[home]
	for next in routes:
		var kingdom := kingdom_at(next)
		if not kingdom.is_empty() and kingdom["owner"] == faction:
			return kingdom
	return {}

func clear_terrain(coord: Vector2i, kingdom: Dictionary) -> int:
	var reward := 1 if is_modern() and cells[coord]["tree"] else 0
	cells[coord]["tree"] = false
	cells[coord]["grave"] = false
	clamp_mana()
	if reward > 0 and not kingdom.is_empty():
		kingdom["gold"] += reward
	return reward

func distance(a: Vector2i, b: Vector2i) -> int:
	return Grid.distance(a, b)

func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in DIRECTIONS:
		var next: Vector2i = coord + direction
		if cells.has(next):
			result.append(next)
	return result

func shuffled(items: Array) -> Array:
	var result := items.duplicate()
	for index in range(result.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary = result[index]
		result[index] = result[other]
		result[other] = temporary
	return result

func inside_map(coord: Vector2i) -> bool:
	var position := Grid.to_world(coord)
	return Vector2(position.x, position.z).length() <= MapSizes.generation_bounds(map_size).x

func starting_land_connected() -> bool:
	return preload("res://src/game/archipelago.gd").starting_land_connected(self)

func connected_land() -> bool:
	return MapGenerator.new(self).connected_land()

func generate(seed_value: int = -1, size_id := "small", kingdom_count := 0) -> void:
	ai_revision = 0
	ai_last_decision.clear()
	effects_by_faction.clear()
	capital_relocations.clear()
	pending_events.clear()
	MapGenerator.new(self).generate(seed_value, size_id, kingdom_count)
	magic.generate_events(self)
	preload("res://src/game/treasure_placement.gd").generate(self)

func has_effect(faction: int, effect: String) -> bool:
	return magic.has_effect(self, faction, effect)

func set_effect(faction: int, effect: String, enabled: bool) -> void:
	magic.set_effect(self, faction, effect, enabled)

func spell_cost(spell: String, faction: int) -> int:
	return magic.spell_cost(self, spell, faction)

func is_barrier(coord: Vector2i) -> bool:
	return cells.has(coord) and cells[coord].get("barrier_by", -1) >= 0

func resolve_event(event: Dictionary, choice: int) -> String:
	var details := {"event":event.duplicate(true), "choice":choice}
	var result: String = magic.resolve_event(self, event, choice)
	if result != "": record_replay("event_choice", int(event.get("faction", -1)), details)
	return result

func event_definition(event: Dictionary) -> Dictionary:
	var result: Dictionary = magic.event_definition(self, event)
	record_replay("event_reveal", int(event.get("faction", -1)), {"event":event.duplicate(true)})
	return result

func passable_land_connected() -> bool:
	return MapGenerator.new(self).passable_land_connected()

func rebuild_kingdoms(affected_owners: Dictionary = {}) -> void:
	Topology.rebuild_kingdoms(self, affected_owners)

func replacement_capital(component: Array[Vector2i], owner: int) -> Vector2i:
	return Topology.replacement_capital(self, component, owner)

func kingdom_at(coord: Vector2i) -> Dictionary:
	if not cells.has(coord):
		return {}
	return kingdoms.get(cells[coord]["kingdom"], {})

func territory(faction: int) -> int:
	var total := 0
	for cell in cells.values():
		if cell["owner"] == faction:
			total += 1
	return total

func has_units(faction: int) -> bool:
	for coord in cells:
		if cells[coord]["unit"] > 0 and unit_faction(coord) == faction:
			return true
	return false

func mana_source_capacity(cell: Dictionary) -> int:
	return 2 if cell["capital"] >= 0 or cell["tree"] else 1

func mana_source_count(faction: int) -> int:
	var total := 0
	if is_modern():
		for cell in cells.values():
			if cell["owner"] == faction and cell.get("mana_source", false):
				total += 1
	return total

func mana_regeneration(faction: int) -> int:
	return 1 + floori(mana_source_count(faction) / 4.0) if is_modern() else 0

func mana_capacity(faction: int) -> int:
	var total := 0
	if is_modern():
		for cell in cells.values():
			if cell["owner"] == faction and cell.get("mana_source", false):
				total += mana_source_capacity(cell)
	return total

func get_mana(faction: int) -> int:
	return clampi(int(mana_by_faction.get(faction, 0)), 0, mana_capacity(faction))

func set_mana(faction: int, amount: int) -> void:
	mana_by_faction[faction] = clampi(amount, 0, mana_capacity(faction))

func mana_income(faction: int) -> int:
	return mini(mana_regeneration(faction), maxi(0, mana_capacity(faction) - get_mana(faction)))

func mana_summary(faction: int) -> Dictionary:
	var sources := 0
	var capacity := 0
	if is_modern():
		for cell in cells.values():
			if cell["owner"] == faction and cell.get("mana_source", false):
				sources += 1
				capacity += mana_source_capacity(cell)
	var regeneration := 1 + floori(sources / 4.0) if is_modern() else 0
	var amount := clampi(int(mana_by_faction.get(faction, 0)), 0, capacity)
	return {"amount": amount, "capacity": capacity, "regeneration": regeneration,
		"income": mini(regeneration, capacity - amount)}

func clamp_mana() -> void:
	var capacities: Dictionary = {}
	if is_modern():
		for cell in cells.values():
			if cell["owner"] >= 0 and cell.get("mana_source", false):
				var faction: int = cell["owner"]
				capacities[faction] = capacities.get(faction, 0) + mana_source_capacity(cell)
	for faction in mana_by_faction:
		mana_by_faction[faction] = clampi(int(mana_by_faction[faction]), 0, capacities.get(faction, 0))

func development_cost(coord: Vector2i) -> int:
	return Construction.development_cost(self, coord)

func capital_relocation_cost(faction: int) -> int:
	return Construction.capital_relocation_cost(self, faction)

func can_relocate_capital(coord: Vector2i, faction: int) -> bool:
	return Construction.can_relocate_capital(self, coord, faction)

func relocate_capital(coord: Vector2i, faction: int) -> bool:
	return Construction.relocate_capital(self, coord, faction)

func can_develop(coord: Vector2i, faction: int) -> bool:
	return Construction.can_develop(self, coord, faction)

func develop(coord: Vector2i, faction: int) -> bool:
	return Construction.develop(self, coord, faction)

func casting_kingdom(spell: String, coord: Vector2i, faction: int, capital := NONE) -> Dictionary:
	return magic.casting_kingdom(self, spell, coord, faction, capital)

func can_cast(spell: String, coord: Vector2i, faction: int, capital := NONE) -> bool:
	return magic.can_cast(self, spell, coord, faction, capital)

func cast_spell(spell: String, coord: Vector2i, faction: int, capital := NONE) -> bool:
	var success: bool = magic.cast_spell(self, spell, coord, faction, capital)
	if success: record_replay("spell", faction, {"spell":spell, "coord":coord, "capital":capital})
	return success

func spell_targets(spell: String, faction: int, capital := NONE) -> Dictionary:
	return magic.spell_targets(self, spell, faction, capital)

func construction_kingdom(coord: Vector2i, faction: int, capital := NONE) -> Dictionary:
	return Construction.construction_kingdom(self, coord, faction, capital)

func bridge_targets(faction: int, capital := NONE) -> Dictionary:
	return Construction.bridge_targets(self, faction, capital)

func castle_neighbors(source: Vector2i, target: Vector2i) -> Array[Vector2i]:
	return Movement.castle_neighbors(self, source, target)

func income(kingdom: Dictionary) -> int:
	var total := 0
	for coord in kingdom["hexes"]:
		var cell: Dictionary = cells[coord]
		if not cell["tree"] and not cell["grave"]:
			total += cell.get("value", 1) if is_modern() else 1
		if cell["building"] == "house":
			total += HOUSE_INCOME
	return maxi(0, total + magic.Encounters.income_adjustment(self, kingdom))

func unit_upkeep(tier: int, faction: int) -> int:
	return maxi(0, Catalog.unit_upkeep(tier, is_modern()) - (2 if tier == 3 and has_effect(faction, "stainless_steel") else 0))

func upkeep(kingdom: Dictionary) -> int:
	var total := 0
	for coord in kingdom["hexes"]:
		total += unit_upkeep(cells[coord]["unit"], kingdom["owner"])
	if is_modern():
		for coord in cells:
			if cells[coord]["unit"] > 0 and kingdom_at(coord).is_empty():
				var support := unit_kingdom(coord)
				if not support.is_empty() and support["capital"] == kingdom["capital"]:
					total += unit_upkeep(cells[coord]["unit"], kingdom["owner"])
	return total

func local_defense(coord: Vector2i) -> int:
	return Movement.local_defense(self, coord)

func defense(coord: Vector2i) -> int:
	return Movement.defense(self, coord)

func friendly_routes(source: Vector2i) -> Dictionary:
	return Movement.friendly_routes(self, source)

func knight_duel(source: Vector2i, target: Vector2i) -> bool:
	return Movement.knight_duel(self, source, target)

func reachable_targets(source: Vector2i) -> Dictionary:
	return Movement.reachable_targets(self, source)

func can_move(source: Vector2i, target: Vector2i) -> bool:
	return Movement.can_move(self, source, target)

func movement_path(source: Vector2i, target: Vector2i, known_targets: Dictionary = {}) -> Array[Vector2i]:
	return Movement.movement_path(self, source, target, known_targets)

func kill_unit(coord: Vector2i) -> void:
	Movement.kill_unit(self, coord)

func move_unit(source: Vector2i, target: Vector2i) -> bool:
	return Movement.move_unit(self, source, target)

func fortification_blocks_attack(source: Vector2i, target: Vector2i) -> bool:
	return Movement.fortification_blocks_attack(self, source, target)

func apply_move(source: Vector2i, target: Vector2i) -> void:
	Movement.apply_move(self, source, target)

func perform_move(source: Vector2i, target: Vector2i) -> Dictionary:
	return Movement.perform_move(self, source, target)

func recruit(coord: Vector2i, faction: int, requested_tier := 0, capital := NONE) -> bool:
	return Construction.recruit(self, coord, faction, requested_tier, capital)

func can_recruit(coord: Vector2i, faction: int, requested_tier := 0, capital := NONE) -> bool:
	return Construction.can_recruit(self, coord, faction, requested_tier, capital)

func recruitment_cost(coord: Vector2i, faction: int, requested_tier := 0, capital := NONE) -> int:
	return Construction.recruitment_cost(self, coord, faction, requested_tier, capital)

func can_build(coord: Vector2i, faction: int, kind: String, capital := NONE) -> bool:
	return Construction.can_build(self, coord, faction, kind, capital)

func build_structure(coord: Vector2i, faction: int, kind: String, capital := NONE) -> bool:
	return Construction.build_structure(self, coord, faction, kind, capital)

func begin_turn(faction: int) -> int:
	var mana := mana_summary(faction)
	mana_by_faction[faction] = mini(mana["capacity"], mana["amount"] + mana["regeneration"])
	# Graves left from a previous turn become trees. New deaths remain visible.
	for cell in cells.values():
		if cell.get("entrenched_by", -1) == faction: cell.erase("entrenched_by")
		if cell.get("barrier_by", -1) == faction:
			cell["barrier_by"] = -1
		if cell["owner"] == faction:
			cell["moved"] = false
			if cell["grave"]:
				cell["grave"] = false
				cell["tree"] = true
		if cell.get("fortified_by", -1) == faction:
			cell["fortified"] = false
			cell["fortified_by"] = -1
	for coord in cells:
		if is_bridge(coord) and unit_faction(coord) == faction:
			cells[coord]["moved"] = false
	var deaths := 0
	for coord in cells:
		if unit_faction(coord) == faction and cells[coord]["unit"] > 0 and unit_kingdom(coord).is_empty():
			kill_unit(coord)
			deaths += 1
	for kingdom in kingdoms.values():
		if kingdom["owner"] != faction:
			continue
		kingdom["gold"] += income(kingdom) - upkeep(kingdom)
		if kingdom["gold"] < 0:
			kingdom["gold"] = 0
			for coord in cells:
				var support := unit_kingdom(coord) if cells[coord]["unit"] > 0 else {}
				if not support.is_empty() and support["capital"] == kingdom["capital"]:
					kill_unit(coord)
					deaths += 1
	record_replay("turn_start", faction, {"starved":deaths})
	return deaths

func spread_trees() -> int:
	var growing: Dictionary = {}
	# Snapshot sources so a new tree cannot spread again in the same round.
	for coord in cells:
		if not cells[coord]["tree"] or rng.randf() >= 0.16:
			continue
		for next in shuffled(neighbors(coord)):
			var cell: Dictionary = cells[next]
			if not is_mountain(next) and not is_barrier(next) and cell["unit"] == 0 and cell["capital"] < 0 and cell["building"] == "" and not cell["tree"] and not cell["grave"]:
				growing[next] = true
				break
	for coord in growing:
		cells[coord]["tree"] = true
	if replay_log != null: replay_log.round_number += 1
	record_replay("tree_growth", -1, {"grown":growing.size()})
	return growing.size()

func prepare_ai_turn(faction: int) -> Array[Dictionary]:
	return KingdomAI.new(self).prepare_ai_turn(faction)

func ai_movements(faction: int) -> Array[Dictionary]:
	return KingdomAI.new(self).ai_movements(faction)

func ai_turn(faction: int) -> Array[Dictionary]:
	return KingdomAI.new(self).ai_turn(faction)


func starting_land_reachable() -> bool:
	return preload("res://src/game/archipelago.gd").starting_land_reachable(self)
