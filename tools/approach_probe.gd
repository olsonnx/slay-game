extends SceneTree
## Three distinct spending/objective policies on unchanged Standard Modern rules.
const Rules = preload("res://src/game/kingdom_rules.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const BasePlanner = preload("res://src/game/ai_strategist.gd")
const PolicyPlanner = preload("res://tools/approach_planner.gd")
const AI = preload("res://src/game/kingdom_ai.gd")
const Snapshot = preload("res://src/game/state_snapshot.gd")
const STYLES := ["economic","defensive","aggressive"]
var options := {"seed_start":"0","seeds":"4","rotations":"0,1,2,3,4,5","rounds":"80","threshold":"1.5","output":"res://artifacts/approach-results.json","mode":"matches"}
var output := {"matches":[],"checks":0,"failures":0,"options":{}}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var bits := argument.trim_prefix("--").split("=",true,1)
			options[bits[0]] = bits[1]
	call_deferred("run")

func expect(ok: bool, message: String) -> void:
	output.checks += 1
	if not ok:
		output.failures += 1
		push_error(message)
		assert(ok,message)
		quit(1)

func fresh(seed_value: int):
	var s = Rules.new()
	s.rule_mode = "modern"
	s.ai_difficulty = "normal"
	s.generate(seed_value,"large",6)
	s.human_factions = []
	return s

func totals(s, faction: int) -> Dictionary:
	var result := {"gold":0,"income":0,"upkeep":0,"land":s.territory(faction),"capitals":0,"units":0,"knights":0,"houses":0,"towers":0,"entrenched":0}
	for bank in s.kingdoms.values():
		if bank.owner == faction:
			result.gold += bank.gold
			result.income += s.income(bank)
			result.upkeep += s.upkeep(bank)
			result.capitals += 1
	for c in s.cells:
		var cell: Dictionary = s.cells[c]
		if cell.unit > 0 and s.unit_faction(c) == faction:
			result.units += 1
			result.knights += int(cell.unit == 3)
			result.entrenched += int(s.is_entrenched(c))
		if cell.owner == faction:
			result.houses += int(cell.building == "house")
			result.towers += int(cell.building == "tower")
	return result

func hostile_near(s, coord: Vector2i, faction: int) -> bool:
	for next in s.neighbors(coord):
		if s.cells[next].owner >= 0 and s.cells[next].owner != faction: return true
	return false

func permanent_defense(s, coord: Vector2i, faction: int) -> int:
	var result: int = 1 if s.cells[coord].capital >= 0 else 0
	for next in [coord] + s.neighbors(coord):
		if s.cells[next].owner == faction and s.cells[next].building == "tower": result = 2
	return result

func recruitment_opportunity(copy, queries, coord: Vector2i, tier: int, war_ready: bool, danger: Dictionary) -> float:
	var faction: int = copy.cells[coord].owner
	var old_rank: int = copy.cells[coord].unit
	if war_ready: return queries.recruitment_value(coord,tier)
	var value := 0.0
	var jobs: Dictionary = queries.recruitment_jobs(coord)
	for target in jobs:
		if copy.cells[target].owner != -1 or copy.is_bridge(target): continue
		var defense: int = queries.defense(target)
		if tier > defense and old_rank <= defense:
			value = maxf(value,queries.capture_value(target,faction) * (1.0 if tier == defense+1 else 0.25))
	# The same immediate capital/territory defense is available before war.
	for next in [coord] + copy.neighbors(coord):
		if copy.cells[next].owner != faction or not Analysis.endangered(copy,next,danger): continue
		var strength: int = tier if next == coord else mini(tier,2)
		if strength >= danger[next].strength:
			value = maxf(value,70.0 if copy.cells[next].capital >= 0 else 18.0)
	return value

func purchase_options(s, faction: int, style: String, war_ready: bool) -> Array:
	var copy = Analysis.snapshot(s)
	var q = Analysis.Queries.new(copy)
	var danger: Dictionary = q.defense_needs(faction)
	var result := []
	# Retain shared spell opportunities, adding a common sustainable wage guard.
	for action in Candidates.preparation(copy,faction,q):
		if action.kind != "spell": continue
		if action.spell == "summon":
			var bank: Dictionary = copy.kingdom_at(action.coord)
			var finance: Dictionary = q.bank_summary(bank)
			var ratio := 0.90 if style == "aggressive" else 0.60 if style == "economic" else 0.50
			if finance.upkeep + copy.unit_upkeep(1,faction) > finance.income * ratio: continue
			if recruitment_opportunity(copy,q,action.coord,1,war_ready,danger) <= 0: continue
		if action.spell == "shatter" and not war_ready:
			if not copy.is_bridge(action.coord) or copy.cells[action.coord].unit == 0: continue
		result.append(action)
	for bank in copy.kingdoms.values():
		if bank.owner != faction: continue
		var finance: Dictionary = q.bank_summary(bank)
		var endangered_capital: bool = Analysis.endangered(copy,bank.capital,danger)
		var open := 0
		for c in bank.hexes:
			if copy.cells[c].building == "" and copy.cells[c].capital < 0: open += 1
		var frontier: Dictionary = q.frontier(bank.capital)
		for c in bank.hexes:
			var cell: Dictionary = copy.cells[c]
			var urgent: bool = Analysis.endangered(copy,c,danger)
			for tier in range(cell.unit+1,4):
				var cost: int = copy.recruitment_cost(c,faction,tier,bank.capital)
				if cost < 0 or cell.moved and cell.unit > 0: continue
				var added: int = copy.unit_upkeep(tier,faction)-copy.unit_upkeep(cell.unit,faction)
				# Every policy must remain solvent without betting on this turn's captures.
				if finance.income < finance.upkeep+added: continue
				var ratio := 0.90 if style == "aggressive" else 0.60 if style == "economic" else 0.50
				if finance.upkeep+added > finance.income*ratio and not endangered_capital and not urgent: continue
				var utility := recruitment_opportunity(copy,q,c,tier,war_ready,danger) - added*0.85-cost*0.16
				if utility <= 0: continue
				utility *= 1.6 if style == "aggressive" else 0.8 if style == "economic" else 0.85
				if urgent:
					var protects: int = tier
					if protects >= danger[c].strength: utility += 80.0 if cell.capital >= 0 else 15.0
				if endangered_capital and copy.distance(c,bank.capital) <= 1 and mini(tier,2) >= int(danger[bank.capital].strength): utility += 80.0
				Candidates.add(result,"recruit",c,utility,{"tier":tier,"capital":bank.capital})
			if copy.can_develop(c,faction) and not cell.tree and not cell.grave and not urgent:
				var cost: int = copy.development_cost(c)
				if bank.gold-cost+finance.income+1-finance.upkeep >= 0:
					var roi: float = 16.0 / cost
					Candidates.add(result,"develop",c,roi*(1.0 if style == "economic" else 0.9 if style == "defensive" else 0.45),{"capital":bank.capital})
			if open > maxi(3,ceili(bank.hexes.size()*0.25)) and copy.can_build(c,faction,"house") and not urgent and bank.gold-copy.HOUSE_COST+finance.income+copy.HOUSE_INCOME-finance.upkeep >= 0:
				var value := 3.2 * (1.0 if style == "economic" else 0.9 if style == "defensive" else 0.45)
				Candidates.add(result,"house",c,value,{"capital":bank.capital})
			if copy.can_build(c,faction,"tower") and bank.gold-copy.TOWER_COST+finance.income-finance.upkeep >= 0:
				var coverage := 0.0
				for protected in [c] + copy.neighbors(c):
					if copy.cells[protected].owner != faction or permanent_defense(copy,protected,faction) >= 2: continue
					if Analysis.endangered(copy,protected,danger) and danger[protected].strength <= 2:
						coverage += 90.0 if copy.cells[protected].capital >= 0 else 20.0
					elif style == "defensive" and hostile_near(copy,protected,faction):
						coverage += 4.0 if copy.cells[protected].capital >= 0 else 2.0
				if coverage > 0 and open > 2:
					Candidates.add(result,"tower",c,coverage*(1.4 if style == "defensive" else 1.0),{"capital":bank.capital})
			if copy.can_entrench(c,faction) and urgent:
				var score := 100.0 if cell.capital >= 0 else 30.0 if style == "defensive" else 18.0
				Candidates.add(result,"entrench",c,score,{"capital":bank.capital})
		if not frontier.is_empty():
			for site in copy.bridge_targets(faction,bank.capital):
				if bank.gold < copy.BRIDGE_COST+10: continue
				if bank.gold-copy.BRIDGE_COST+finance.income-finance.upkeep < 0: continue
				var value: float = q.bridge_value(site,bank.capital)+q.bridge_campaign(site,bank.capital)-copy.BRIDGE_COST*0.16
				if value > 0: Candidates.add(result,"bridge",site,value,{"capital":bank.capital})
	result.sort_custom(func(a,b):
		if a.priority != b.priority: return a.priority > b.priority
		if a.coord.x != b.coord.x: return a.coord.x < b.coord.x
		return a.coord.y < b.coord.y)
	return result

func war_advantage(s, faction: int, threshold: float) -> bool:
	var mine: int = totals(s,faction).income
	var enemy_total := 0
	var enemies := 0
	for other in range(s.faction_count):
		if other == faction: continue
		var row := totals(s,other)
		if row.capitals == 0: continue
		enemy_total += row.income
		enemies += 1
	return enemies == 0 or mine >= maxf(1.0,float(enemy_total)/enemies)*threshold

func turn(s, faction: int, style: String, ready: bool) -> Dictionary:
	var row := {"active_turns":1,"deaths":0,"bankruptcies":0,"unsupported_deaths":0,"deficit_at_end":0,"develop":0,"house":0,"tower":0,"recruit":0,"entrench":0,"neutral_captures":0,"hostile_captures":0,"attacks":0,"paid":0,"plans":0}
	for bank in s.kingdoms.values():
		if bank.owner == faction and bank.gold+s.income(bank)-s.upkeep(bank) < 0: row.bankruptcies += 1
	for c in s.cells:
		if s.cells[c].unit > 0 and s.unit_faction(c) == faction and s.unit_kingdom(c).is_empty(): row.unsupported_deaths += 1
	row.deaths = s.begin_turn(faction)
	for purchase in range(8):
		var pool := purchase_options(s,faction,style,ready)
		if pool.is_empty() or pool[0].priority <= 0: break
		var action: Dictionary = pool[0]
		var before_gold: int = totals(s,faction).gold
		expect(Candidates.apply(s,action,faction),"Selected policy purchase must be legal")
		if row.has(action.kind): row[action.kind] += 1
		row.paid += maxi(0,before_gold-int(totals(s,faction).gold))
		s.ai_revision += 1
	var guard := 0
	while true:
		var planner = PolicyPlanner.new(s,faction)
		planner.approach = style
		planner.war_ready = ready
		planner.run()
		row.plans += 1
		if planner.best_sequence.is_empty(): break
		var ai = AI.new(s)
		ai.pending_orders = planner.best_sequence.duplicate(true)
		var moved := false
		while not ai.pending_orders.is_empty():
			var batch: Array = ai.commit_strategic(planner)
			if batch.is_empty(): break
			moved = true
			for command in batch:
				var before: Dictionary = command.before_target
				if before.owner == -1 and not s.is_bridge(command.target): row.neutral_captures += 1
				if before.owner >= 0 and before.owner != faction:
					row.attacks += 1
					if s.cells[command.target].owner == faction: row.hostile_captures += 1
		if not moved: break
		guard += 1
		expect(guard < 1000,"Policy movement must terminate")
	# Holding ready units can entrench; moved units cannot get a free second action.
	for c in s.cells:
		if s.can_entrench(c,faction) and (hostile_near(s,c,faction) or s.is_bridge(c)):
			expect(s.entrench(c,faction),"Stationary entrench must be legal")
			row.entrench += 1
	for bank in s.kingdoms.values():
		if bank.owner == faction and bank.gold+s.income(bank)-s.upkeep(bank) < 0: row.deficit_at_end += 1
	return row

func validate() -> void:
	var s = fresh(71)
	expect(s.map_size == "large" and s.faction_count == 6,"Actual Standard map and six factions")
	var a = BasePlanner.new(s,0)
	var b = PolicyPlanner.new(s,0)
	b.approach = "neutral"
	b.war_ready = true
	a.run()
	b.run()
	expect(a.best_sequence == b.best_sequence,"Unmodified objectives preserve the real strategic planner")
	var first := purchase_options(s,0,"economic",false)
	expect(not first.is_empty(),"Economic policy has investment/expansion opportunities")
	var neutral_only = PolicyPlanner.new(s,0)
	neutral_only.approach = "economic"
	neutral_only.war_ready = false
	neutral_only.run()
	for action in neutral_only.best_sequence:
		expect(s.cells[action.coord].owner in [-1,0] or neutral_only.defensive_target(action.coord),"Economic movement waits for income advantage")
	print("Approach policy validation passed; board cells: ",s.cells.size())

func save() -> void:
	output.options = options
	FileAccess.open(options.output,FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))

func match_run(seed_value: int, rotation: int) -> Dictionary:
	var s = fresh(seed_value)
	var policies := []
	var ready := []
	var unlocked := []
	var telemetry := []
	for faction in range(6):
		var index := posmod(faction+rotation%3,3)
		if rotation >= 3: index = posmod(-index,3)
		policies.append(STYLES[index])
		ready.append(STYLES[index] == "aggressive")
		unlocked.append(1 if ready[-1] else 0)
		telemetry.append({})
	var history := []
	var winner := -1
	var started := Time.get_ticks_msec()
	for round_index in range(int(options.rounds)):
		for faction in range(6):
			var status := totals(s,faction)
			if status.capitals == 0 and status.units == 0: continue
			if not ready[faction] and war_advantage(s,faction,float(options.threshold)):
				ready[faction] = true
				unlocked[faction] = round_index+1
			var tel := turn(s,faction,policies[faction],ready[faction])
			for key in tel: telemetry[faction][key] = int(telemetry[faction].get(key,0))+int(tel[key])
			expect(s.faction_count == 6,"AI encounter policy must not leave an unplayed rebel faction")
			var alive := {}
			for bank in s.kingdoms.values(): alive[bank.owner] = true
			if alive.size() == 1:
				winner = alive.keys()[0]
				break
		var checkpoint := []
		for faction in range(6): checkpoint.append(totals(s,faction))
		history.append(checkpoint)
		if (round_index+1)%10 == 0: print("Progress seed=",seed_value," rotation=",rotation," round=",round_index+1," alive=",checkpoint.map(func(x):return x.capitals))
		if winner >= 0: break
		s.spread_trees()
		await process_frame
	var row := {"seed":seed_value,"rotation":rotation,"policies":policies,"winner":winner,"winning_style":policies[winner] if winner >= 0 else "unfinished","rounds":history.size(),"unlocked":unlocked,"telemetry":telemetry,"history":history,"ms":Time.get_ticks_msec()-started,"board_cells":s.cells.size()}
	print("MATCH ",JSON.stringify({"seed":seed_value,"rotation":rotation,"winner":row.winning_style,"rounds":row.rounds,"ms":row.ms}))
	return row

func run() -> void:
	validate()
	if output.failures > 0: return
	for seed_value in range(int(options.seed_start),int(options.seed_start)+int(options.seeds)):
		for rotation in options.rotations.split(","):
			output.matches.append(await match_run(seed_value,int(rotation)))
			save()
	save()
	print("APPROACH COMPLETE ",output.matches.size()," matches; checks=",output.checks," failures=",output.failures)
	quit(1 if output.failures > 0 else 0)
