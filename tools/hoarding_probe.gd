extends SceneTree
## Diagnostic only: authoritative rules, unmodified tactical AI, matched saving policies.
const Rules = preload("res://src/game/kingdom_rules.gd")
const AI = preload("res://src/game/kingdom_ai.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
const Planner = preload("res://src/game/ai_planner.gd")
const Strategist = preload("res://src/game/ai_strategist.gd")
var options := {"seeds":"4", "sizes":"small,medium", "seats":"0,1,2,3", "policies":"baseline,reserve40,reserve100,save5,save10", "rounds":"30", "output":"res://artifacts/hoarding-results.json", "mode":"all", "difficulty":"normal"}
var results := {"matches":[], "economy":[], "checks":0}

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--") and argument.contains("="):
			var parts := argument.trim_prefix("--").split("=",true,1)
			options[parts[0]] = parts[1]
	call_deferred("run")

func fresh(seed_value: int, size_id: String):
	var s = Rules.new()
	s.rule_mode = "modern"
	s.ai_difficulty = options.difficulty
	s.generate(seed_value,size_id,4)
	s.human_factions = []
	return s

func check(ok: bool, message: String) -> void:
	results.checks += 1
	if not ok:
		push_error(message)
		quit(1)
		assert(ok,message)

func totals(s, faction: int) -> Dictionary:
	var row := {"gold":0,"income":0,"upkeep":0,"land":s.territory(faction),"capitals":0,"units":0,"knights":0,"houses":0}
	for bank in s.kingdoms.values():
		if bank.owner == faction:
			row.gold += bank.gold
			row.income += s.income(bank)
			row.upkeep += s.upkeep(bank)
			row.capitals += 1
	for c in s.cells:
		if s.unit_faction(c) == faction and s.cells[c].unit > 0:
			row.units += 1
			row.knights += int(s.cells[c].unit == 3)
		if s.cells[c].owner == faction and s.cells[c].building == "house": row.houses += 1
	return row

func action_cost(s, action: Dictionary, faction: int) -> int:
	match action.kind:
		"recruit": return s.recruitment_cost(action.coord,faction,action.tier,action.capital)
		"develop": return s.development_cost(action.coord)
		"house": return s.HOUSE_COST
		"tower": return s.TOWER_COST
		"bridge": return s.BRIDGE_COST
	return 0

func allowed(s, action: Dictionary, faction: int, policy: String, round_number: int, danger: Dictionary) -> bool:
	if policy == "late100": policy = "baseline" if round_number <= 5 else "reserve100"
	var cost := action_cost(s,action,faction)
	if cost == 0 or policy == "baseline": return true
	if policy.begins_with("save"):
		return round_number > int(policy.trim_prefix("save"))
	var bank: Dictionary = s.kingdoms[action.capital]
	# Emergency release only for paid defence at an endangered capital/bank.
	var emergency: bool = Analysis.endangered(s,bank.capital,danger)
	if emergency and action.kind in ["recruit","tower"]: return true
	return bank.gold - cost >= int(policy.trim_prefix("reserve"))

func take_turn(s, faction: int, policy: String, round_number: int) -> Dictionary:
	var telemetry := {"deaths":s.begin_turn(faction),"blocked":0,"purchases":0,"spent":0,"lost_gold":{}}
	for purchase in range(int(Analysis.profile(s).spending)):
		var planner = Strategist.new(s,faction,true) if s.uses_strategic_ai() else Planner.new(s,faction,true)
		var action: Dictionary = planner.run()
		if action.is_empty(): break
		if policy != "baseline":
			var copy = Analysis.snapshot(s)
			var queries = Analysis.Queries.new(copy)
			var danger: Dictionary = queries.defense_needs(faction)
			if not allowed(copy,action,faction,policy,round_number,danger):
				telemetry.blocked += 1
				action = {}
				for candidate in Candidates.preparation(copy,faction,queries):
					if candidate.priority > 0.25 and allowed(copy,candidate,faction,policy,round_number,danger):
						action = candidate
						break
		if action.is_empty(): break
		var cost := action_cost(s,action,faction)
		check(cost >= 0,"Candidate cost must be legal")
		check(Candidates.apply(s,action,faction),"Selected purchase must succeed")
		telemetry.spent += cost
		telemetry.purchases += int(cost > 0)
		# This is the only simulation-relevant mutation in record_decision.
		s.ai_revision += 1
	var ai = AI.new(s)
	var guard := 0
	while true:
		var before := {}
		for capital in s.kingdoms:
			var bank: Dictionary = s.kingdoms[capital]
			if bank.owner != faction: before[capital] = {"owner":bank.owner,"gold":bank.gold}
		var wave: Array = ai.ai_movements(faction)
		for capital in before:
			if s.cells[capital].owner != before[capital].owner:
				var victim: int = before[capital].owner
				telemetry.lost_gold[victim] = int(telemetry.lost_gold.get(victim,0)) + before[capital].gold
		if wave.is_empty(): break
		guard += 1
		check(guard < 1000,"Movement loop must terminate")
	return telemetry

func parity() -> void:
	for size_id in ["small","medium"]:
		var a = fresh(71,size_id)
		var b = fresh(71,size_id)
		for faction in range(4):
			a.ai_turn(faction)
			take_turn(b,faction,"baseline",1)
			for field in ["cells","kingdoms","mana_by_faction","effects_by_faction","ai_revision"]:
				check(a.get(field) == b.get(field),"Baseline parity: " + size_id + "/" + field)
			check(a.rng.state == b.rng.state,"Baseline RNG parity")
	print("Baseline parity passed")

func invest(s, reserve: int) -> void:
	for attempt in range(100):
		var best := {}
		var ratio := INF
		for bank in s.kingdoms.values():
			if bank.owner != 0: continue
			for c in bank.hexes:
				if s.cells[c].tree or s.cells[c].grave: continue
				var cost: int = s.development_cost(c)
				if s.can_develop(c,0) and bank.gold-cost >= reserve and cost < ratio:
					ratio = cost
					best = {"kind":"develop","coord":c}
				if s.can_build(c,0,"house") and bank.gold-s.HOUSE_COST >= reserve and float(s.HOUSE_COST)/s.HOUSE_INCOME < ratio:
					ratio = float(s.HOUSE_COST)/s.HOUSE_INCOME
					best = {"kind":"house","coord":c,"capital":bank.capital}
		if best.is_empty(): break
		check(Candidates.apply(s,best,0),"Investment must succeed")

func knight_shock(s, wait_collections := 0) -> Dictionary:
	var copy = Analysis.snapshot(s)
	for collection in range(wait_collections): copy.begin_turn(0)
	var bought := false
	for c in copy.cells:
		if copy.cells[c].owner == 0 and copy.cells[c].unit == 1:
			bought = copy.recruit(c,0,3)
			break
	var death_at := 0
	if bought:
		for turn in range(1,31):
			if copy.begin_turn(0) > 0:
				death_at = turn
				break
	return {"purchased":bought,"death_settlement":death_at,"survived_30":bought and death_at == 0}

func economy() -> void:
	for seed_value in range(20):
		for policy in ["save","invest","reserve20","reserve40","save5","save10"]:
			var s = fresh(seed_value,"small")
			var samples := []
			for collections in range(21):
				# Equal opening settlement, matching current hotseat rules.
				s.begin_turn(0)
				if policy == "invest" or policy.begins_with("reserve") or policy == "save5" and collections >= 5 or policy == "save10" and collections >= 10:
					invest(s,int(policy.trim_prefix("reserve")) if policy.begins_with("reserve") else 0)
				if collections in [0,3,5,8,10,15,20]:
					var row := totals(s,0)
					row["turn"] = collections + 1
					row["knight_shock"] = knight_shock(s)
					row["knight_after_one_collection"] = knight_shock(s,1)
					samples.append(row)
			results.economy.append({"seed":seed_value,"policy":policy,"samples":samples})

func match_run(seed_value: int, size_id: String, seat: int, policy: String) -> Dictionary:
	var s = fresh(seed_value,size_id)
	var history := []
	var spent := [0,0,0,0]
	var deaths := [0,0,0,0]
	var lost_gold := [0,0,0,0]
	var winner := -1
	var elimination := [0,0,0,0]
	var blocked := 0
	var turns := 0
	var started := Time.get_ticks_msec()
	for round_index in range(int(options.rounds)):
		for faction in range(4):
			var tel := take_turn(s,faction,policy if faction == seat else "baseline",round_index+1)
			turns += 1
			spent[faction] += tel.spent
			deaths[faction] += tel.deaths
			blocked += tel.blocked
			for victim in tel.lost_gold: lost_gold[victim] += tel.lost_gold[victim]
			var surviving := {}
			for bank in s.kingdoms.values(): surviving[bank.owner] = true
			for owner in range(4):
				if not surviving.has(owner) and elimination[owner] == 0: elimination[owner] = round_index+1
			if surviving.size() == 1:
				winner = surviving.keys()[0]
				break
		var snapshot := []
		for faction in range(4): snapshot.append(totals(s,faction))
		history.append(snapshot)
		if winner >= 0: break
		s.spread_trees()
	var row := {"seed":seed_value,"size":size_id,"seat":seat,"policy":policy,"winner":winner,"rounds":history.size(),"turns":turns,"elimination":elimination,"history":history,"spent":spent,"settlement_deaths":deaths,"destroyed_treasury":lost_gold,"blocked":blocked,"ms":Time.get_ticks_msec()-started}
	print(JSON.stringify({"seed":seed_value,"size":size_id,"seat":seat,"policy":policy,"winner":winner,"rounds":history.size(),"ms":row.ms}))
	return row

func save() -> void:
	results["options"] = options
	FileAccess.open(options.output,FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))

func burst_tactics() -> void:
	# A legal one-turn breach, Knight trade, then capital capture. Recruitment
	# is paid immediately; the surviving army's wages are due only next turn.
	results["tactics"] = []
	for gold in [20,40,60,80,100]:
		var s = Rules.new()
		s.rule_mode = "modern"
		for q in range(-2,3):
			for r in range(-2,3):
				var c := Vector2i(q,r)
				var distance: int = s.distance(c,Vector2i.ZERO)
				if distance <= 2: s.cells[c] = s.make_cell(0 if distance <= 1 else 1)
		s.cells[Vector2i.ZERO].capital = 0
		s.cells[Vector2i.ZERO].unit = 3
		s.cells[Vector2i(-2,0)].capital = 1
		s.rebuild_kingdoms()
		s.kingdom_at(Vector2i.ZERO).gold = 100
		s.kingdom_at(Vector2i(-2,0)).gold = gold
		var a := Vector2i(2,0)
		var b := Vector2i(2,-1)
		var c := Vector2i(1,1)
		var recruited := [s.recruit(a,1,3),s.recruit(b,1,3),s.recruit(c,1,2)]
		var moves := [s.move_unit(a,Vector2i(1,0)),s.move_unit(b,Vector2i.ZERO),s.move_unit(c,Vector2i.ZERO)]
		var won: bool = s.cells[Vector2i.ZERO].owner == 1
		check(won == (gold == 100),"100 G funds the complete immediate breach/trade/capture")
		var attacker := totals(s,1)
		var next_deaths: int = s.begin_turn(1)
		if won: check(next_deaths == 2,"The burst army is insolvent if play continues")
		results.tactics.append({"gold":gold,"recruited":recruited,"moves":moves,"captured_capital":won,"attacker":attacker,"next_settlement_deaths_if_play_continues":next_deaths})

func run() -> void:
	parity()
	if options.mode in ["all","tactics"]: burst_tactics()
	if options.mode in ["all","economy"]: economy()
	if options.mode in ["all","matches"]:
		for size_id in options.sizes.split(","):
			for seed_value in range(int(options.seeds)):
				for policy in options.policies.split(","):
					for seat_text in options.seats.split(","):
						if policy == "baseline" and int(seat_text) != int(options.seats.split(",")[0]): continue
						results.matches.append(match_run(seed_value,size_id,int(seat_text),policy))
						save()
						await process_frame
	save()
	print("HOARDING COMPLETE ",results.matches.size()," matches; ",results.economy.size()," economy runs; ",results.checks," checks")
	quit()
