extends SceneTree
## Runs only in the isolated projects created by run_rebalance_lab.ps1.
const Rules = preload("res://src/game/kingdom_rules.gd")
var checks := 0
var failures := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func fortress():
	var s = Rules.new()
	s.rule_mode = "modern"
	for q in range(-2, 3):
		for r in range(-2, 3):
			var c := Vector2i(q, r)
			var d: int = s.distance(c, Vector2i.ZERO)
			if d <= 2:
				s.cells[c] = s.make_cell(0 if d <= 1 else 1)
				s.cells[c]["value"] = 2
	s.cells[Vector2i.ZERO]["capital"] = 0
	s.cells[Vector2i.ZERO]["unit"] = 3
	s.cells[Vector2i(2, 0)]["unit"] = 3
	s.cells[Vector2i(2, -1)]["unit"] = 3
	s.rebuild_kingdoms()
	for bank in s.kingdoms.values(): bank["gold"] = 100
	return s

func tactics() -> Dictionary:
	var s = fortress()
	var source := Vector2i(2, 0)
	var edge := Vector2i(1, 0)
	var cap: bool = s.defense(edge) == 2
	expect(s.defense(Vector2i.ZERO) == 3, "Knight keeps full defence on its own hex")
	expect(not s.can_move(source, Vector2i.ZERO), "No attack skips enemy territory")
	var breach_targets := 0
	for target in s.reachable_targets(source):
		if s.cells[target]["owner"] == 0: breach_targets += 1
	expect(breach_targets == (6 if cap else 0), "Six protected frontier targets with cap; none without")
	var breached: bool = s.move_unit(source, edge)
	var duel := false
	if breached:
		duel = s.move_unit(Vector2i(2, -1), Vector2i.ZERO)
		expect(duel and s.cells[Vector2i.ZERO]["unit"] == 0, "Second Knight can trade with the exposed defender")
		expect(s.cells[Vector2i.ZERO]["owner"] == 0 and s.cells[Vector2i.ZERO]["capital"] == 0, "Duel preserves ownership and capital")
		s.cells[Vector2i(-2, 0)]["unit"] = 2
		expect(s.move_unit(Vector2i(-2, 0), Vector2i.ZERO) and s.cells[Vector2i.ZERO]["owner"] == 1, "A third ready unit can capture the exposed capital via the breach")
	# Even a fully developed seven-hex island can fund one Knight at every tested wage.
	var rich = fortress()
	for c in rich.cells:
		if rich.cells[c]["owner"] == 0: rich.cells[c]["value"] = 6
	var deaths := 0
	for turn in range(100): deaths += rich.begin_turn(0)
	expect(rich.cells[Vector2i.ZERO]["unit"] == 3, "Wages alone cannot break a wealthy protected Knight")
	# Defence still makes lower tiers unable to invade the protected ring.
	var held = fortress()
	held.cells[source]["unit"] = 2
	expect(not held.can_move(source, edge), "Soldiers cannot take Knight-protected territory")
	held.cells[source]["unit"] = 1
	expect(not held.can_move(source, edge), "Scouts cannot take Knight-protected territory")
	var structure = fortress()
	structure.cells[Vector2i.ZERO]["unit"] = 0
	structure.cells[Vector2i.ZERO]["building"] = "tower"
	expect(structure.defense(edge) == 2, "Towers still protect neighbouring land at strength two")
	var ward = fortress()
	ward.cells[Vector2i.ZERO]["unit"] = 0
	ward.cells[edge]["building"] = "tower"
	ward.cells[edge]["fortified"] = true
	expect(ward.move_unit(source, edge) and ward.cells[edge]["owner"] == 0 and ward.cells[source]["moved"], "Ward still absorbs a legal attack and spends the attacker")
	var overlap = fortress()
	overlap.cells[Vector2i(0, 1)]["unit"] = 3
	expect(overlap.defense(edge) == (2 if cap else 3), "Multiple supporters do not add their defence")
	overlap.cells[edge]["unit"] = 3
	expect(overlap.move_unit(source, edge) and overlap.cells[edge]["unit"] == 0, "Occupied border Knights still require a duel even with overlapping support")
	return {"frontier_targets": breach_targets, "breach": breached, "followup_duel": duel,
		"rich_fortress_survives_100_turns": rich.cells[Vector2i.ZERO]["unit"] == 3}

func finance() -> Array:
	var rows: Array = []
	for gross in [7, 10, 14, 20, 30, 42]:
		for tier in [2, 3]:
			for reserve in [0, 10, 30]:
				var s = fortress()
				var bank: Dictionary = s.kingdom_at(Vector2i.ZERO)
				var remaining: int = gross
				for c in bank["hexes"]:
					s.cells[c]["value"] = mini(6, remaining)
					remaining -= s.cells[c]["value"]
				s.cells[Vector2i.ZERO]["unit"] = tier
				bank["gold"] = reserve
				var wages: int = s.upkeep(bank)
				var expected: int = 0 if gross >= wages else floori(float(reserve) / (wages - gross)) + 1
				var death_turn := 0
				for turn in range(1, 101):
					if s.begin_turn(0) > 0:
						death_turn = turn
						break
				expect(death_turn == expected, "Bankruptcy agrees with reserve/deficit threshold")
				rows.append({"gross": gross, "tier": tier, "reserve": reserve, "wages": wages, "death_turn": death_turn})
	return rows

func invest(s, faction: int) -> void:
	for c in s.cells:
		if s.cells[c]["owner"] == faction and s.cells[c]["value"] == 1 and not s.cells[c]["tree"]:
			s.develop(c, faction)
	for c in s.cells:
		if s.cells[c]["owner"] == faction: s.build_structure(c, faction, "house")

func economy() -> Array:
	var rows: Array = []
	for seed_value in range(20):
		for policy in ["save", "rush_knight", "invest_then_knight", "sustainable_knight"]:
			var s = Rules.new()
			s.rule_mode = "modern"
			s.generate(seed_value, "small", 4)
			var first_knight := 0
			var deaths := 0
			for turn in range(1, 21):
				# Solo opening has no player settlement; subsequent turns do.
				if turn > 1: deaths += s.begin_turn(0)
				var bank: Dictionary = s.kingdom_at(s.kingdoms.keys()[0])
				for b in s.kingdoms.values():
					if b["owner"] == 0: bank = b
				if policy == "invest_then_knight": invest(s, 0)
				if policy == "sustainable_knight":
					for c in bank["hexes"]:
						if s.cells[c]["value"] == 1 and not s.cells[c]["tree"]: s.develop(c, 0)
				if policy != "save":
					for c in bank["hexes"]:
						if s.cells[c]["unit"] > 0 and s.cells[c]["unit"] < 3:
							if policy == "sustainable_knight" and s.income(bank) < s.Catalog.unit_upkeep(3, true): continue
							if s.recruit(c, 0, 3) and first_knight == 0: first_knight = turn
				if policy == "sustainable_knight":
					for c in bank["hexes"]: s.build_structure(c, 0, "house")
			var gold := 0
			var gross := 0
			var wages := 0
			for bank in s.kingdoms.values():
				if bank["owner"] == 0:
					gold += bank["gold"]
					gross += s.income(bank)
					wages += s.upkeep(bank)
			rows.append({"seed": seed_value, "policy": policy, "first_knight": first_knight,
				"gold": gold, "income": gross, "wages": wages, "deaths": deaths})
	return rows

func two_knight_budget() -> Dictionary:
	var s = fortress()
	s.cells[Vector2i(1, 0)]["unit"] = 3
	var bank: Dictionary = s.kingdom_at(Vector2i.ZERO)
	bank["gold"] = 100
	var houses := 0
	for c in bank["hexes"]:
		if s.build_structure(c, 0, "house"): houses += 1
	var gross: int = s.income(bank)
	var wages: int = s.upkeep(bank)
	expect(houses == 5 and gross == 34, "Seven value-two hexes fit five houses and two Knights")
	bank["gold"] = 30
	var death_turn := 0
	for turn in range(1, 101):
		if s.begin_turn(0) > 0:
			death_turn = turn
			break
	return {"houses": houses, "gross": gross, "wages": wages, "net": gross - wages, "reserve": 30, "death_turn": death_turn}

func matches() -> Array:
	var rows: Array = []
	var seed_start := 4 if "--extended" in OS.get_cmdline_user_args() else 0
	var seed_count := 4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="): seed_count = int(arg.trim_prefix("--seeds="))
	for size_id in ["very_small", "small"]:
		for seed_value in range(seed_start, seed_start + seed_count):
			var s = Rules.new()
			s.rule_mode = "modern"
			s.ai_difficulty = "normal"
			s.human_factions = []
			s.generate(seed_value, size_id, 4)
			var winner := -1
			var rounds := 0
			var starvation := 0
			var knight_samples := 0
			var scout_samples := 0
			var soldier_samples := 0
			var first_knight_round := 0
			var deficit_samples := 0
			var bank_samples := 0
			var captures := 0
			var duels := 0
			var idle_rounds := 0
			for round_index in range(30):
				rounds = round_index + 1
				var before_owners: Array = []
				for cell in s.cells.values(): before_owners.append(cell["owner"])
				for faction in range(4):
					# Match solo opening: faction zero skips its initial settlement.
					var ai = s.KingdomAI.new(s)
					var preparation: Array
					if round_index == 0 and faction == 0:
						# Same planner and spending budget, omit begin_turn only.
						var before: Dictionary = s.cells.duplicate(true)
						for purchase in range(8):
							var planner = ai.Planner.new(s, faction, true)
							var action: Dictionary = planner.run()
							if action.is_empty() or not ai.Candidates.apply(s, action, faction): break
						preparation = ai.preparation_records(before, faction)
					else: preparation = ai.prepare_ai_turn(faction)
					for action in preparation:
						if action["kind"] == "death": starvation += 1
					var wave: Array = ai.ai_movements(faction)
					while not wave.is_empty():
						for action in wave:
							if action["kind"] == "knight_duel": duels += 1
							if action["before_target"]["owner"] != action["after_target"]["owner"]: captures += 1
						wave = ai.ai_movements(faction)
					if first_knight_round == 0:
						for cell in s.cells.values():
							if cell["unit"] == 3: first_knight_round = rounds
					var living: Dictionary = {}
					for bank in s.kingdoms.values(): living[bank["owner"]] = true
					if living.size() == 1:
						winner = living.keys()[0]
						break
				for cell in s.cells.values():
					if cell["unit"] == 3: knight_samples += 1
					if cell["unit"] == 1: scout_samples += 1
					if cell["unit"] == 2: soldier_samples += 1
				for bank in s.kingdoms.values():
					bank_samples += 1
					if s.income(bank) < s.upkeep(bank): deficit_samples += 1
				var after_owners: Array = []
				for cell in s.cells.values(): after_owners.append(cell["owner"])
				idle_rounds = idle_rounds + 1 if before_owners == after_owners else 0
				if winner >= 0: break
				s.spread_trees()
			var row := {"size": size_id, "seed": seed_value, "winner": winner, "rounds": rounds,
				"starvation_deaths": starvation, "knight_round_samples": knight_samples,
				"scout_round_samples": scout_samples, "soldier_round_samples": soldier_samples, "first_knight_round": first_knight_round,
				"deficit_bank_samples": deficit_samples, "bank_samples": bank_samples,
				"captures": captures, "duels": duels, "final_idle_rounds": idle_rounds}
			var settlement_count = s.get("lab_settlement_deaths")
			if settlement_count != null: row["settlement_deaths"] = settlement_count
			rows.append(row)
			print("MATCH ", JSON.stringify(row))
			await process_frame
	return rows

func run() -> void:
	if "--extended" in OS.get_cmdline_user_args():
		var extended := {"matches": await matches()}
		var extended_file := FileAccess.open("res://extended.json", FileAccess.WRITE)
		extended_file.store_string(JSON.stringify(extended, "\t"))
		quit()
		return
	var result := {"tactics": tactics(), "finance": finance(), "economy": economy(), "two_knight_budget": two_knight_budget()}
	print("PROBES DONE")
	var supplement: bool = "--supplement" in OS.get_cmdline_user_args()
	if not supplement: result["matches"] = await matches()
	result["checks"] = checks
	result["failures"] = failures
	var file := FileAccess.open("res://supplement.json" if supplement else "res://results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("Rebalance checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
