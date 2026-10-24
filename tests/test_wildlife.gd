extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Wildlife = preload("res://src/game/wildlife.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Timeline = preload("res://src/game/replay_timeline.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func fixture():
	var s = Rules.new()
	s.rule_mode = "modern"
	s.rng.seed = 42
	for q in range(-8,9):
		for r in range(-8,9):
			var c := Vector2i(q,r)
			if s.distance(c,Vector2i.ZERO) <= 8: s.cells[c] = s.make_cell()
	for c in [Vector2i(-6,0),Vector2i(-5,0),Vector2i(-6,1)]: s.cells[c].owner = 0
	for c in [Vector2i(6,0),Vector2i(5,0),Vector2i(6,-1)]: s.cells[c].owner = 1
	s.cells[Vector2i(-6,0)].capital = 0
	s.cells[Vector2i(6,0)].capital = 1
	s.cells[Vector2i(-6,0)].mana_source = true
	s.cells[Vector2i(6,0)].mana_source = true
	s.rebuild_kingdoms()
	for bank in s.kingdoms.values(): bank.gold = 200
	return s

func animal(s, kind: String, coord := Vector2i.ZERO, home := Vector2i.ZERO) -> void:
	s.cells[coord]["animal"] = kind
	s.cells[coord]["animal_home"] = home

func count_animals(s) -> int:
	var count := 0
	for cell in s.cells.values(): count += int(cell.get("animal", "") != "")
	return count

func combat() -> void:
	var source := Vector2i(-5,0)
	var target := Vector2i(-4,0)
	for kind in Wildlife.KINDS:
		for tier in [1,2,3]:
			for is_lair in [false,true]:
				var s = fixture()
				s.cells[source].unit = tier
				if is_lair: s.cells[target]["lair"] = kind
				else: animal(s,kind,target)
				var possible: bool = tier > int(Wildlife.DEFINITIONS[kind].defense)
				expect(s.can_move(source,target) == possible,"Correct species/rank movement threshold")
				var moved: bool = s.move_unit(source,target)
				expect(moved == possible,"Combat command enforces species/rank threshold")
				if moved:
					expect(not s.has_wildlife(target) and s.cells[target].unit == tier,"Winning hunter occupies the cleared tile")
	var s = fixture()
	s.cells[source].unit = 1
	animal(s,"bear",target)
	s.cells[Vector2i(-3,0)].owner = 0
	s.cells[Vector2i(-3,0)].unit = 3
	expect(not s.can_move(source,Vector2i(-2,0)),"Friendly routes cannot pass through an animal")
	# A wolf can be hunted on friendly land without friendly defenders shielding it.
	s = fixture()
	s.cells[source].unit = 2
	animal(s,"wolf",Vector2i(-6,0))
	expect(s.can_move(source,Vector2i(-6,0)),"An animal occupying friendly land remains attackable")
	expect(not s.can_recruit(Vector2i(-6,0),0,3) and not s.can_develop(Vector2i(-6,0),0),"Purchases cannot overwrite wildlife")
	expect(not s.can_cast("summon",Vector2i(-6,0),0),"Summon cannot overwrite an animal")
	s = fixture()
	s.cells[source].unit = 2
	s.cells[target].owner = 1
	s.cells[target].capital = 1
	s.cells[Vector2i(-3,0)].owner = 1
	s.cells[Vector2i(-3,0)].unit = 3
	animal(s,"wolf",target)
	s.rebuild_kingdoms()
	expect(not s.can_move(source,target),"An animal cannot bypass the defenses of an enemy province")
	var query = s.KingdomAI.Analysis.Queries.new(s)
	expect(target not in query.candidate_targets(source),"AI candidates respect enemy defenses beneath wildlife")
	s.cells[source].unit = 3
	expect(s.move_unit(source,target) and s.cells[Vector2i(-3,0)].owner == 0,"Hunting at an enemy castle still follows normal castle capture rules")

func spawning() -> void:
	var s = fixture()
	s.cells[Vector2i.ZERO]["lair"] = "wolf"
	expect(count_animals(s) == 0,"No animal exists before the first World turn")
	var actions: Array = s.world_turn()
	expect(count_animals(s) == 1 and actions.size() == 1 and s.cells[actions[0].target].get("animal") == "wolf" and s.distance(actions[0].target,Vector2i.ZERO) == 1,"First World turn emerges on a neighboring province")
	expect(s.cells[Vector2i.ZERO].get("animal", "") == "" and actions[0].source == Vector2i.ZERO,"The lair remains separate from its animal")
	expect(actions.size() == 1 and actions[0].kind == "spawn","Emergence does not also move or attack")
	Wildlife.kill(s,actions[0].target)
	for turn in range(1,4):
		s.world_turn()
		expect(count_animals(s) == (1 if turn == 3 else 0),"Respawn occurs exactly three World turns after death")
		if turn == 3:
			for coord in s.cells:
				if s.cells[coord].get("animal", "") != "": expect(s.distance(coord,Vector2i.ZERO) == 1,"Replacement animals also emerge beside the lair")
	for turn in range(12):
		s.world_turn()
		expect(count_animals(s) <= 1,"A living animal prevents duplicate lair spawns")
		expect(s.cells[Vector2i.ZERO].get("animal", "") == "","Roaming animals never return onto a lair")
	var blocked = fixture()
	blocked.cells[Vector2i.ZERO]["lair"] = "wolf"
	for coord in blocked.neighbors(Vector2i.ZERO): blocked.cells[coord].unit = 3
	blocked.world_turn()
	expect(count_animals(blocked) == 0,"A blocked lair waits instead of overwriting a neighboring unit")
	var exit: Vector2i = blocked.neighbors(Vector2i.ZERO)[0]
	blocked.cells[exit].unit = 0
	var emerged: Array = blocked.world_turn()
	expect(count_animals(blocked) == 1 and emerged[0].target == exit,"Emergence retries when an exit becomes free")
	# With no prey, wandering never leaves the home range.
	s = fixture()
	for cell in s.cells.values(): cell.owner = -1; cell.capital = -1
	s.kingdoms.clear()
	s.cells[Vector2i.ZERO]["lair"] = "bear"
	for turn in range(50):
		s.world_turn()
		for coord in s.cells:
			if s.cells[coord].get("animal", "") != "": expect(s.distance(coord,Vector2i.ZERO) <= Wildlife.ROAM_RADIUS,"Idle animals stay in their home range")
	# A predator returning from a chase routes toward the home ring, without
	# using the now-inaccessible cave itself as its pathfinding destination.
	s = fixture()
	for cell in s.cells.values(): cell.owner = -1; cell.capital = -1
	s.kingdoms.clear()
	s.cells[Vector2i.ZERO]["lair"] = "bear"
	animal(s,"bear",Vector2i(5,0),Vector2i.ZERO)
	for turn in range(8): s.world_turn()
	for coord in s.cells:
		if s.cells[coord].get("animal", "") != "": expect(s.distance(coord,Vector2i.ZERO) <= Wildlife.ROAM_RADIUS and coord != Vector2i.ZERO,"Returning animals reach their home range without entering the cave")

func behavior() -> void:
	for kind in Wildlife.KINDS:
		var s = fixture()
		animal(s,kind)
		var prey := Vector2i(1,0)
		s.cells[prey].owner = 1
		s.cells[prey].unit = 1
		var building := Vector2i(0,1)
		s.cells[building].owner = 1
		s.cells[building].building = "house"
		var actions: Array = s.world_turn()
		var target: Vector2i = building if kind == "boar" else prey
		expect(actions.size() == 2 and actions[0].target == target,"Species chooses its allowed preferred target")
		expect(s.cells[target].owner == -1,"Raids turn attacked provinces neutral")
		if kind == "boar": expect(s.cells[prey].unit == 1 and s.cells[building].building == "","Boars destroy buildings and spare units")
		else: expect(actions[0].changes[prey].unit == 0 and (s.cells[building].building == "" if kind == "bear" else s.cells[building].building == "house"),"Hunters kill the unit first; bears may raze the house with their second action")
	var s = fixture()
	animal(s,"wolf")
	var target := Vector2i(1,0)
	s.cells[target].owner = 1
	s.cells[target].building = "house"
	s.world_turn()
	expect(s.cells[target].building == "house" and s.cells[target].owner == 1,"Wolves neither raze buildings nor neutralize their sites")
	s.cells[target].unit = 1
	s.world_turn()
	expect(s.cells[target].unit == 1 and s.cells[target].owner == 1,"Buildings shelter their occupants from wolves")
	s = fixture()
	animal(s,"bear")
	s.cells[target].owner = 1
	s.cells[target].unit = 3
	s.world_turn()
	expect(s.cells[target].unit == 3,"A Knight survives bear aggression")
	# Entrenchment absorbs a legal animal attack and keeps the predator in place.
	s = fixture()
	animal(s,"bear")
	s.cells[target].owner = 1
	s.cells[target].unit = 1
	expect(s.entrench(target,1),"Fixture defender can entrench")
	var blocked: Array = s.world_turn()
	expect(blocked.size() == 2 and blocked[0].kind == "blocked" and blocked[0].changes[target].unit == 1 and blocked[1].kind == "attack" and s.cells[target].unit == 0,"Entrenchment absorbs the first attack, then the second attack breaks through")
	s.world_turn()
	expect(s.cells[target].owner == -1 and s.cells[target].unit == 0,"A subsequent unblocked attack kills and neutralizes")
	# An attack on a linking province uses ordinary kingdom split/treasury rules.
	s = fixture()
	for x in range(1,6): s.cells[Vector2i(x,0)].owner = 1
	s.rebuild_kingdoms()
	s.kingdom_at(Vector2i(6,0)).gold = 75
	animal(s,"boar",Vector2i(2,-1),Vector2i(2,-1))
	Wildlife.raid(s,Vector2i(2,0),"boar")
	expect(s.cells[Vector2i(2,0)].owner == -1 and s.kingdom_at(Vector2i(6,0)).gold == 75,"Neutralization preserves gold at the surviving capital")
	# Pursuit is one adjacent hop, never an unlimited kingdom move.
	s = fixture()
	animal(s,"wolf")
	s.cells[Vector2i(3,0)].owner = 1
	s.cells[Vector2i(3,0)].unit = 1
	var chase: Array = s.world_turn()
	expect(chase.size() == 2 and s.distance(chase[0].source,chase[0].target) == 1 and chase[1].source == chase[0].target and s.distance(chase[1].source,chase[1].target) == 1,"Visible prey triggers two consecutive adjacent steps")

func rewards_and_replays() -> void:
	for kind in Wildlife.KINDS:
		var s = fixture()
		var source := Vector2i(-5,0)
		var target := Vector2i(-4,0)
		s.cells[source].unit = 3
		s.cells[target]["lair"] = kind
		var before := Snapshots.capture(s)
		var bank: Dictionary = s.kingdom_at(source)
		var gold: int = bank.gold
		var base_income: int = s.income(bank)
		var base_regen: int = s.mana_regeneration(0)
		s.set_mana(0,0)
		var recorder = Replay.new()
		s.replay_log = recorder
		recorder.start(s)
		expect(not s.perform_move(source,target).is_empty(),"Lair can be destroyed through normal recorded movement")
		bank = s.kingdom_at(target)
		var reward_replay := Replay.read_records(recorder.records)
		expect(reward_replay.error == "" and reward_replay.position.effects == s.effects_by_faction,"Reward replays preserve source names as well as amounts")
		if kind == "bear": expect(s.income(bank) == base_income+1+5,"Bear cave grants permanent income on top of captured land")
		if kind == "wolf": expect(s.mana_regeneration(0) == base_regen+1 and s.mana_summary(0).regeneration == base_regen+1,"Wolf den updates authoritative regeneration and forecast")
		if kind == "boar": expect(bank.gold == gold+20 and s.get_mana(0) == 2,"Boar burrow grants local gold and capped mana")
		var income: int = s.income(bank)
		var regen: int = s.mana_regeneration(0)
		var paid: int = bank.gold
		s.cells[target].moved = false
		s.move_unit(target,source)
		s.cells[source].moved = false
		s.move_unit(source,target)
		expect(s.income(s.kingdom_at(target)) == income and s.mana_regeneration(0) == regen and s.kingdom_at(target).gold == paid,"Revisiting a destroyed lair cannot pay twice")
		var snapshot = Analysis_copy(s)
		expect(snapshot.effects_by_faction == s.effects_by_faction,"AI simulations preserve permanent wildlife rewards")
		Snapshots.restore(s,before)
		expect(s.cells == before.cells and s.effects_by_faction == before.effects,"Cancellation restores lairs, rewards and unit state")
	var s = fixture()
	s.cells[Vector2i.ZERO]["lair"] = "bear"
	var recorder = Replay.new()
	s.replay_log = recorder
	recorder.start(s)
	s.world_turn()
	s.world_turn()
	var decoded := Replay.read_records(recorder.records)
	expect(decoded.error == "" and decoded.position.cells == s.cells,"Replays preserve World spawns, moves, and optional wildlife fields")
	var timeline = Timeline.new()
	expect(timeline.open(decoded) == "","Wildlife replay opens in viewer timeline")
	timeline.seek(timeline.steps.size()-1)
	expect(timeline.position.cells == s.cells,"Replay seeking reconstructs the final wildlife state")

func Analysis_copy(s): return s.KingdomAI.Analysis.snapshot(s)

func forests_and_aggro() -> void:
	var origin := Vector2i.ZERO
	var forest := Vector2i(1,0)
	for kind in Wildlife.KINDS:
		for owned in [false,true]:
			var s = fixture()
			animal(s,kind)
			for coord in s.neighbors(origin):
				if coord != forest: s.cells[coord].mountain = true
			s.cells[forest].tree = true
			s.cells[forest].owner = 1 if owned else -1
			var actions: Array = Wildlife.world_turn(s)
			expect(actions.size() == 2 and actions[0].target == forest and actions[0].kind == "attack","Every species visibly destroys a forest on entry")
			expect(not s.cells[forest].tree and s.cells[forest].owner == -1 and actions[0].changes[forest].get("animal") == kind,"Forests are cleared, and owned forests become neutral")
			expect(actions[0].alert == owned,"Owned territory triggers aggression; ordinary neutral-forest trampling does not")
			expect(s.kingdom_at(Vector2i(-6,0)).gold == 200,"Animal tree clearing never grants a player's clearing reward")
	# Trees cannot permanently seal a cave. Existing clear exits are preferred,
	# but an entirely forested ring can be trampled during emergence.
	var s = fixture()
	s.cells[origin]["lair"] = "wolf"
	for coord in s.neighbors(origin): s.cells[coord].tree = true
	var spawned: Array = Wildlife.world_turn(s)
	expect(spawned.size() == 1 and spawned[0].kind == "spawn" and not s.cells[spawned[0].target].tree,"A surrounded lair emerges through a forest without becoming stuck")
	# Fortification protects a forest until the successful follow-up raid.
	s = fixture()
	animal(s,"wolf")
	s.cells[forest].tree = true
	s.cells[forest].owner = 1
	s.cells[forest].fortified = true
	var blocked: Array = Wildlife.world_turn(s)
	expect(blocked[0].kind == "blocked" and blocked[0].changes[forest].tree and blocked[0].changes[forest].owner == 1 and blocked[1].kind == "attack","A blocked raid preserves both the forest and ownership")
	Wildlife.world_turn(s)
	expect(not s.cells[forest].tree and s.cells[forest].owner == -1,"A later successful raid clears the protected forest")
	# Target acquisition persists across pursuit, alerts once, and survives
	# snapshots and replay playback without running decision logic again.
	s = fixture()
	for cell in s.cells.values(): cell.owner = -1; cell.capital = -1
	s.kingdoms.clear()
	animal(s,"wolf")
	var prey := Vector2i(3,0)
	s.cells[prey].owner = 1
	s.cells[prey].unit = 1
	s.cells[forest].tree = true
	var recorder = Replay.new()
	s.replay_log = recorder
	recorder.start(s)
	var first: Array = Wildlife.world_turn(s)
	expect(first[0].alert and first[0].aggro_target == prey and s.cells[first[-1].target].animal_target == prey,"First sight of prey records an alert and persistent pursuit target")
	expect(not s.cells[forest].tree,"An animal clears a neutral forest while pursuing a different target")
	var saved := Snapshots.capture(s)
	var copy = Analysis_copy(s)
	expect(copy.cells[first[-1].target].animal_target == prey,"AI simulation snapshots preserve aggression")
	var next: Array = Wildlife.world_turn(s)
	expect(not next[0].alert and next[0].aggro_target == prey,"Continuing the same pursuit does not repeat the alert animation")
	expect(next[0].kind == "attack" and s.cells[prey].unit == 0 and not s.cells[prey].has("animal_target"),"Reaching and defeating prey ends pursuit")
	var decoded := Replay.read_records(recorder.records)
	var timeline = Timeline.new()
	expect(decoded.error == "" and timeline.open(decoded) == "","Aggression records and optional target fields remain replay compatible")
	for index in range(1,timeline.steps.size()):
		var before: Dictionary = timeline.position.cells
		timeline.seek(index)
		var event: Dictionary = timeline.wildlife_action(before)
		if event.get("alert",false): expect(event.aggro_target == prey,"Replay animations reconstruct the original alert target")
	Snapshots.restore(s,saved)
	expect(s.cells[first[-1].target].animal_target == prey,"Snapshot restoration restores pursuit after later attacks")
	s.cells[prey].unit = 0
	s.cells[prey].owner = -1
	var calm: Array = Wildlife.world_turn(s)
	expect(calm.size() == 2 and calm[0].aggro_target == s.NONE,"Losing a target ends aggression")
	for cell in s.cells.values():
		if cell.get("animal", "") != "": expect(not cell.has("animal_target"),"Roaming does not retain a stale target")
	# Killing an alerted animal leaves no animal metadata under its hunter.
	s = fixture()
	var hunter := Vector2i(-5,0)
	var victim := Vector2i(-4,0)
	s.cells[hunter].unit = 2
	animal(s,"wolf",victim)
	s.cells[victim]["animal_target"] = origin
	expect(s.move_unit(hunter,victim) and not s.cells[victim].has("animal_target"),"Hunting removes the dead animal's pursuit metadata")

func raid_matrix() -> void:
	var target := Vector2i(1,0)
	for kind in Wildlife.KINDS:
		for feature in ["scout","soldier","knight","house","tower","capital","province"]:
			var s = fixture()
			animal(s,kind)
			for coord in s.neighbors(Vector2i.ZERO):
				if coord != target: s.cells[coord].mountain = true
			s.cells[target].owner = 1
			s.cells[Vector2i(2,0)].owner = 1
			if feature != "capital": s.cells[Vector2i(2,0)].capital = 1
			if feature in ["scout","soldier","knight"]: s.cells[target].unit = ["scout","soldier","knight"].find(feature)+1
			elif feature in ["house","tower"]: s.cells[target].building = feature
			elif feature == "capital": s.cells[target].capital = 1
			s.rebuild_kingdoms()
			var expected: bool = feature == "province" or kind != "wolf" and feature in ["house","tower","capital"] or kind != "boar" and (feature == "scout" or feature == "soldier" and kind == "bear")
			var before: Dictionary = s.cells[target].duplicate(true)
			var actions: Array = Wildlife.world_turn(s)
			if expected:
				expect(actions.size() == 2 and actions[0].target == target and s.cells[target].owner == -1 and s.cells[target].unit == 0 and s.cells[target].building == "" and s.cells[target].capital < 0,"%s raids %s under the species and defense rules" % [kind,feature])
			else:
				expect(actions.is_empty() and s.cells[target] == before,"%s leaves protected or excluded %s targets intact" % [kind,feature])

func world_invariants() -> void:
	for size in ["large","huge"]:
		for seed_value in [7,42,123]:
			var s = Rules.new()
			s.rule_mode = "modern"
			s.generate(seed_value,size,6)
			for turn in range(40):
				# Exercise replacement cycles as well as sustained roaming/raiding.
				if turn in [12,28]:
					for coord in s.cells:
						if s.cells[coord].get("animal", "") != "": Wildlife.kill(s,coord)
				s.world_turn()
				var homes := {}
				for coord in s.cells:
					var cell: Dictionary = s.cells[coord]
					if cell.get("animal", "") == "": continue
					var home: Vector2i = cell.animal_home
					expect(not homes.has(home),"Long World simulations maintain one animal per lair")
					homes[home] = true
					expect(not cell.tree and cell.unit == 0 and cell.building == "" and cell.owner == -1,"Simulated animals never overlap forests, units, buildings or owned land")
					expect(cell.get("lair", "") == "" and not s.is_bridge(coord) and not s.is_mountain(coord) and not s.is_barrier(coord),"Simulated movement respects every terrain exclusion")
					expect(s.distance(coord,home) <= Wildlife.CHASE_RADIUS,"Extended chases remain tethered to the lair")
					if cell.has("animal_target"): expect(cell.animal_target is Vector2i and s.cells.has(cell.animal_target),"Persisted pursuit targets reference real provinces")
				expect(homes.size() <= Wildlife.LAIR_BUDGETS[size],"Respawns never exceed map wildlife density budgets")
				for faction in range(s.faction_count): s.begin_turn(faction)

func ai_hunting() -> void:
	var planner = preload("res://src/game/ai_planner.gd")
	var strategy = preload("res://src/game/ai_strategist.gd")
	var candidates = preload("res://src/game/ai_candidates.gd")
	for kind in Wildlife.KINDS:
		var s = Rules.new()
		s.rule_mode = "modern"
		s.ai_difficulty = "hard"
		for q in [-2,-1,0,5,6]: s.cells[Vector2i(q,0)] = s.make_cell(0 if q < 0 else 1 if q >= 5 else -1)
		s.cells[Vector2i(-2,0)].capital = 0
		s.cells[Vector2i(5,0)].capital = 1
		s.cells[Vector2i(-1,0)].unit = 3 if kind == "bear" else 2
		s.cells[Vector2i.ZERO]["lair"] = kind
		s.rebuild_kingdoms()
		for bank in s.kingdoms.values(): bank.gold = 100
		for backend in [planner,strategy]:
			var action: Dictionary = backend.new(s,0).run()
			expect(action.get("kind") == "move" and action.get("coord") == Vector2i.ZERO,"Both AI backends recognize a profitable reachable lair")
			var copy = Analysis_copy(s)
			expect(not action.is_empty() and candidates.apply(copy,action,0),"AI lair-hunting commands pass authoritative validation")
			expect(not copy.has_wildlife(Vector2i.ZERO),"AI clears the lair and receives its reward through normal movement")

func generation() -> void:
	var standard_lairs := 0
	var kinds := {}
	for size in ["small","medium","large","very_large","huge"]:
		for seed_value in range(8):
			var s = Rules.new()
			s.rule_mode = "modern"
			s.generate(seed_value,size,6)
			var lairs := []
			for coord in s.cells:
				var cell: Dictionary = s.cells[coord]
				if cell.get("lair", "") == "": continue
				lairs.append(coord)
				kinds[cell.lair] = true
				expect(cell.owner == -1 and not cell.tree and not cell.mana_source and cell.event == "" and not s.is_mountain(coord) and not s.is_bridge(coord),"Lairs occupy clear neutral land, excluding other objectives")
				for owned in s.cells:
					if s.cells[owned].owner >= 0: expect(s.distance(coord,owned) >= Wildlife.HOME_CLEARANCE,"Lairs maintain clearance from every starting province")
			if size == "large": standard_lairs += lairs.size()
			expect(lairs.size() <= Wildlife.LAIR_BUDGETS[size],"Lairs obey the map-size budget rather than scaling with every tile")
			if size == "huge": expect(lairs.size() <= 4,"Huge maps never exceed four lairs")
			for a in range(lairs.size()):
				for b in range(a): expect(s.distance(lairs[a],lairs[b]) >= Wildlife.LAIR_SPACING,"Lairs are spaced apart")
			var cells: Dictionary = s.cells.duplicate(true)
			var rng_state: int = s.rng.state
			s.generate(seed_value,size,6)
			expect(s.cells == cells and s.rng.state == rng_state,"Restart reproduces lair placement and game RNG")
	expect(standard_lairs > 0 and kinds.size() == 3,"Standard maps can contain lairs, and all three species appear")
	print("Wildlife generation: Standard lairs across eight seeds = ",standard_lairs)

func run() -> void:
	combat()
	spawning()
	behavior()
	rewards_and_replays()
	ai_hunting()
	forests_and_aggro()
	raid_matrix()
	world_invariants()
	generation()
	print("Wildlife checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures > 0 else 0)
