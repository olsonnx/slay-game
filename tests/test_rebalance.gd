extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Queries = preload("res://src/game/ai_queries.gd")
const Strategy = preload("res://src/game/ai_strategist.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var economy = Rules.new()
	economy.rule_mode = "modern"
	for x in range(5):
		economy.cells[Vector2i(x, 0)] = economy.make_cell(0)
		economy.cells[Vector2i(x, 0)]["value"] = 6 if x < 4 else 4
	economy.rebuild_kingdoms()
	economy.cells[Vector2i.ZERO]["unit"] = 3
	economy.cells[Vector2i.RIGHT]["unit"] = 1
	var economy_bank: Dictionary = economy.kingdom_at(Vector2i.ZERO)
	economy_bank["gold"] = 13
	expect(economy.income(economy_bank) == 28 and economy.upkeep(economy_bank) == 40, "Knight plus Scout cost forty gold per turn under the 4/12/36 schedule")
	expect(economy.begin_turn(0) == 0 and economy_bank["gold"] == 1, "A reserve covers the first twelve-gold deficit")
	expect(economy.begin_turn(0) == 2 and economy_bank["gold"] == 0, "The same army bankrupts on the next settlement without additional income")
	var summon = Rules.new()
	summon.rule_mode = "modern"
	summon.ai_difficulty = "normal"
	for x in range(4):
		summon.cells[Vector2i(x, 0)] = summon.make_cell(0 if x < 3 else -1)
		summon.cells[Vector2i(x, 0)]["value"] = 2 if x < 2 else 1
	summon.cells[Vector2i.ZERO]["capital"] = 0
	summon.cells[Vector2i.ZERO]["mana_source"] = true
	summon.cells[Vector2i.ZERO]["unit"] = 1
	summon.rebuild_kingdoms()
	summon.set_mana(0, 2)
	expect(summon.can_cast("summon", Vector2i.RIGHT, 0), "Players can still choose a mana-funded Scout despite tight upkeep")
	var unsafe_summon := false
	for action in Candidates.preparation(summon, 0):
		if action.get("spell", "") == "summon": unsafe_summon = true
	expect(not unsafe_summon, "Normal AI rejects Summon when spare income cannot pay its four-gold wage")
	for mode in ["modern"]:
		for source_tier in [0, 1, 2]:
			var s = Rules.new()
			s.rule_mode = mode
			s.cells[Vector2i.ZERO] = s.make_cell(0)
			s.cells[Vector2i.RIGHT] = s.make_cell(0)
			s.rebuild_kingdoms()
			var bank: Dictionary = s.kingdom_at(Vector2i.ZERO)
			s.cells[Vector2i.ZERO]["unit"] = source_tier
			var cost: int = [40, 30, 20][source_tier]
			bank["gold"] = cost - 1
			expect(not s.recruit(Vector2i.ZERO, 0, 3) and bank["gold"] == cost - 1 and s.cells[Vector2i.ZERO]["unit"] == source_tier, "Insufficient Knight funds reject without mutating unit or treasury")
			bank["gold"] = cost
			expect(s.recruit(Vector2i.ZERO, 0, 3) and bank["gold"] == 0 and s.cells[Vector2i.ZERO]["unit"] == 3, "Knight direct purchase and upgrades pay the full price difference in both rulesets")
			expect(s.Catalog.unit_tooltip(3).contains("Cost 40 G"), "Knight tooltip shows authoritative purchase price")
		# Reproduce the formerly invulnerable seven-hex pocket in both modes.
		var s = Rules.new()
		s.rule_mode = mode
		for q in range(-2, 3):
			for r in range(-2, 3):
				var c := Vector2i(q, r)
				var d: int = s.distance(c, Vector2i.ZERO)
				if d <= 2: s.cells[c] = s.make_cell(0 if d <= 1 else 1)
		s.cells[Vector2i.ZERO]["capital"] = 0
		s.cells[Vector2i.ZERO]["unit"] = 3
		s.cells[Vector2i(2, 0)]["unit"] = 3
		s.cells[Vector2i(2, -1)]["unit"] = 3
		s.rebuild_kingdoms()
		expect(s.defense(Vector2i.ZERO) == 3 and s.defense(Vector2i.RIGHT) == 2, "Knight keeps full local defence and caps adjacent protection")
		expect(not s.can_move(Vector2i(2, 0), Vector2i.ZERO), "Attacker must first breach territory")
		var cached = Queries.new(s)
		expect(cached.candidate_targets(Vector2i(2, 0)).has(Vector2i.RIGHT), "AI cached targets include the legal breach")
		var strategy = Strategy.new(s, 0)
		expect(strategy.defence_without(Vector2i(-1, 0), Vector2i.RIGHT) == 2, "Strategic AI caps neighbouring Knight support")
		expect(strategy.defence_without(Vector2i(-1, 0), Vector2i.ZERO) == 3, "Strategic AI keeps a Knight's own defence")
		expect(s.move_unit(Vector2i(2, 0), Vector2i.RIGHT), "First Knight breaches the protective ring")
		expect(s.move_unit(Vector2i(2, -1), Vector2i.ZERO) and s.cells[Vector2i.ZERO]["unit"] == 0 and s.cells[Vector2i.ZERO]["capital"] == 0, "Second Knight removes the defender by a duel without capturing the capital")
		s.cells[Vector2i(-2, 0)]["unit"] = 2
		expect(not s.can_move(Vector2i(-2,0),Vector2i.ZERO),"An opposite-side follower cannot shortcut through unbreached enemy territory")
		s.cells[Vector2i(2,-2)]["unit"] = 2
		expect(s.move_unit(Vector2i(2,-2), Vector2i.ZERO) and s.cells[Vector2i.ZERO]["owner"] == 1, "A ready follower within range captures the capital through the breached ring")
	print("Rebalance checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
