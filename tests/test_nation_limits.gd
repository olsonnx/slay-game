extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
const Setup = preload("res://src/game/match_setup.gd")
const Grid = preload("res://src/game/hex_grid.gd")
var checks := 0
var failures := 0

class FallbackGenerator extends "res://src/game/map_generator.gd":
	func starting_sites() -> Array:
		return state.shuffled(MapSizes.fallback_sites(state.map_size,state.faction_count)).slice(0,state.faction_count)

func _initialize() -> void: call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	for size_id in Sizes.IDS:
		var maximum: int = Sizes.MAX_KINGDOMS[size_id]
		var total_land := 0
		var total_neutral := 0
		var total_passable := 0
		var minimum_gap := 100
		for seed_value in [0,1,7,42,71,123]:
			var rules = Rules.new()
			rules.generate(seed_value,size_id,maximum)
			expect(rules.faction_count == maximum and rules.kingdoms.size() == maximum,"Maximum roster creates every nation and capital")
			var capitals := []
			var owned := 0
			for kingdom in rules.kingdoms.values():
				capitals.append(kingdom.capital)
				owned += kingdom.hexes.size()
				var value := 0
				var scouts := 0
				var expansion := {}
				for coord in kingdom.hexes:
					value += rules.cells[coord].value
					scouts += int(rules.cells[coord].unit == 1)
					for next in rules.neighbors(coord):
						if rules.cells[next].owner == -1 and not rules.is_mountain(next): expansion[next] = true
				expect(kingdom.hexes.size() >= 6 and kingdom.hexes.size() <= 9 and value == 11 and scouts == 1 and kingdom.gold == 10,"Crowded starts retain equal economy and one Scout")
				expect(expansion.size() >= 2,"Every nation retains two passable expansion options")
			for index in range(capitals.size()):
				for other in range(index):
					minimum_gap = mini(minimum_gap,Grid.distance(capitals[index],capitals[other]))
			total_land += rules.cells.size()
			total_neutral += rules.cells.size()-owned
			for coord in rules.cells:
				total_passable += int(not rules.is_mountain(coord))
			if seed_value == 42:
				var repeat = Rules.new()
				repeat.generate(seed_value,size_id,maximum)
				expect(repeat.cells == rules.cells and repeat.rng.state == rules.rng.state,"Maximum-roster generation remains deterministic")
		expect(minimum_gap >= 5,"Maximum rosters retain five-hex capital separation")
		var fallback := Sizes.fallback_sites(size_id,maximum)
		expect(fallback.size() >= maximum,"Bounded fallback has enough homes for every supported nation")
		var bounds = Rules.new()
		bounds.map_size = size_id
		for index in range(fallback.size()):
			for direction in Grid.DIRECTIONS: expect(bounds.inside_map(fallback[index]+direction),"Fallback home rings stay inside generation bounds")
			for other in range(index): expect(Grid.distance(fallback[index],fallback[other]) >= 5,"Fallback home rings remain separated")
		if maximum > 6:
			var forced = Rules.new()
			FallbackGenerator.new(forced).generate(42,size_id,maximum,false)
			expect(forced.kingdoms.size() == maximum,"Forced fallback generation produces the complete crowded roster")
		var setup := Setup.normalize({"size":size_id,"count":99})
		expect(setup.count == maximum and setup.slots.size() == maximum,"Setup enforces each size's limit")
		var quick := Setup.quick_play(size_id,maximum,"normal",11,42,"modern")
		var colors := {}
		for slot in quick.slots: colors[slot.color] = true
		expect(quick.count == maximum and colors.size() == maximum,"Quick Play supplies unique colours for every nation")
		print("Nation capacity %s: max=%d, mean land=%.1f, passable=%.1f, neutral=%.1f, min capital gap=%d" % [size_id,maximum,total_land/6.0,total_passable/6.0,total_neutral/6.0,minimum_gap])
	expect(Setup.normalize({"size":"small","map_path":"authored.json","count":10}).count == 10,"Authored maps accept ten seats independently of generated size")
	print("Nation limit checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
