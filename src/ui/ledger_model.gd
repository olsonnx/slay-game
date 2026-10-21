extends RefCounted
## Aggregate existing turn records by faction, across capital moves and splits.
static func histories(recorder, round_number: int, faction_count: int) -> Dictionary:
	var snapshots := {}
	if recorder != null:
		if recorder.header.has("economy") and round_number > 1: snapshots[1] = recorder.header.economy
		for row in recorder.rows:
			if row.has("economy") and int(row.round) < round_number:
				snapshots[int(row.round)] = row.economy
	var result := {}
	for owner in range(faction_count): result[owner] = []
	var rounds: Array = snapshots.keys()
	rounds.sort()
	for turn in rounds:
		var totals := {}
		for owner in range(faction_count): totals[owner] = 0
		for bank in snapshots[turn]:
			if totals.has(int(bank.faction)): totals[int(bank.faction)] += int(bank.income)
		for owner in result: result[owner].append(Vector2(turn, totals[owner]))
	return result

static func build(rules, round_number: int) -> Dictionary:
	var factions := {}
	var by_capital := {}
	var history := histories(rules.replay_log, round_number, rules.faction_count)
	var max_income := 1
	for owner in range(-1, rules.faction_count):
		factions[owner] = {"hexes":0, "units":0, "gold":0, "income":0, "costs":0, "profit":0,
			"capital":rules.NONE, "capital_size":0, "tiers":[0,0,0], "points":[]}
	for bank in rules.kingdoms.values():
		var faction: Dictionary = factions[bank.owner]
		faction.gold += bank.gold
		faction.income += rules.income(bank)
		by_capital[bank.capital] = bank.owner
		# The largest territory provides a useful single navigation target.
		if bank.hexes.size() > faction.capital_size or (bank.hexes.size() == faction.capital_size and bank.capital < faction.capital):
			faction.capital = bank.capital
			faction.capital_size = bank.hexes.size()
	for coord in rules.cells:
		var cell: Dictionary = rules.cells[coord]
		factions[cell.owner].hexes += 1
		if cell.unit <= 0: continue
		var owner: int = rules.unit_faction(coord)
		factions[owner].units += 1
		factions[owner].tiers[cell.unit-1] += 1
		var support: Dictionary = rules.unit_kingdom(coord)
		if not support.is_empty() and by_capital.has(support.capital):
			factions[support.owner].costs += rules.unit_upkeep(cell.unit, support.owner)
	for owner in range(rules.faction_count):
		var faction: Dictionary = factions[owner]
		faction.profit = faction.income-faction.costs
		faction.points = history[owner]
		faction.points.append(Vector2(round_number, faction.income))
		for point in faction.points: max_income = maxi(max_income, int(point.y))
	return {"factions":factions, "max_income":max_income}
