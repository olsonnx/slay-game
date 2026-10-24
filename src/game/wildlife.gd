extends RefCounted
## Neutral predators. Optional scalar cell fields participate in normal snapshots/replays.
const Grid = preload("res://src/game/hex_grid.gd")
const SIGHT := 3
const ROAM_RADIUS := 2
const CHASE_RADIUS := 6
const HOME_CLEARANCE := 4
const LAIR_SPACING := 8
# Rare wilderness objectives: map area grows much faster than their count.
const LAIR_BUDGETS := {"very_small":0,"small":1,"medium":1,"large":2,"very_large":3,"huge":4}
const RESPAWN_TURNS := 3
const KINDS := ["bear", "wolf", "boar"]
const DEFINITIONS := {
	"bear":{"name":"Bear","lair":"Bear cave","defense":2,"attack":3,"reward":"Landmark: +5 G / turn to its kingdom while controlled"},
	"wolf":{"name":"Wolf","lair":"Wolf den","defense":1,"attack":2,"reward":"Landmark: +1 mana / turn to its owner"},
	"boar":{"name":"Boar","lair":"Boar burrow","defense":1,"attack":3,"reward":"20 G and 2 mana"}}

static func present(cell: Dictionary) -> bool:
	return cell.get("animal", "") != "" or cell.get("lair", "") != ""

static func defense(cell: Dictionary) -> int:
	var animal: String = cell.get("animal", "")
	var lair: String = cell.get("lair", "")
	return maxi(int(DEFINITIONS.get(animal, {}).get("defense",0)),int(DEFINITIONS.get(lair, {}).get("defense",0)))

static func generate(state) -> void:
	var wanted: int = LAIR_BUDGETS.get(state.map_size,1)
	if wanted <= 0: return
	# Separate placement RNG preserves existing resources, encounters and turn RNG.
	var random := RandomNumberGenerator.new()
	random.seed = hash([state.level_seed,"wildlife-v1"])
	var homes := []
	for coord in state.cells:
		if state.cells[coord].owner >= 0: homes.append(coord)
	var sites := []
	for coord in state.cells:
		var cell: Dictionary = state.cells[coord]
		if cell.owner >= 0 or state.is_mountain(coord) or state.is_bridge(coord) or cell.mana_source or cell.event != "" or cell.get("treasure",0) > 0: continue
		var nearest := 100000
		for home in homes: nearest = mini(nearest,state.distance(coord,home))
		if nearest < HOME_CLEARANCE: continue
		var neighbors := 0
		for next in state.neighbors(coord):
			if not state.is_mountain(next) and not state.is_bridge(next): neighbors += 1
		if neighbors >= 2: sites.append({"coord":coord,"score":nearest+random.randf()})
	sites.sort_custom(func(a,b):return a.score > b.score)
	var placed := []
	var offset := random.randi_range(0,2)
	for site in sites:
		var coord: Vector2i = site.coord
		var clear := true
		for other in placed:
			if state.distance(coord,other) < LAIR_SPACING: clear = false
		if not clear: continue
		var cell: Dictionary = state.cells[coord]
		cell["lair"] = KINDS[(placed.size()+offset)%3]
		cell["lair_wait"] = 0
		cell.tree = false
		cell.grave = false
		placed.append(coord)
		if placed.size() >= wanted: break

static func kill(state, coord: Vector2i) -> void:
	var cell: Dictionary = state.cells[coord]
	var home: Vector2i = cell.get("animal_home",Grid.NONE)
	cell.erase("animal")
	cell.erase("animal_home")
	cell.erase("animal_target")
	if state.cells.has(home) and state.cells[home].get("lair", "") != "":
		state.cells[home]["lair_wait"] = RESPAWN_TURNS

static func destroy_lair(state, coord: Vector2i, faction: int, bank: Dictionary) -> void:
	var cell: Dictionary = state.cells[coord]
	var kind: String = cell.get("lair", "")
	if kind == "" or bank.is_empty(): return
	# Erase before granting anything: revisits and reconnections cannot pay again.
	cell.erase("lair")
	cell.erase("lair_wait")
	var sites = preload("res://src/game/event_sites.gd")
	sites.create(state,coord,kind,5 if kind == "bear" else 0,1 if kind == "wolf" else 0)
	if kind == "boar":
		bank.gold += 20
		state.set_mana(faction,state.get_mana(faction)+2)

static func attack_kind(state, coord: Vector2i, kind: String) -> String:
	var cell: Dictionary = state.cells[coord]
	# Buildings shelter their occupants from wolves, just as troops shield
	# their province from boars. Every successful raid can then neutralize land.
	if kind == "wolf" and (cell.building != "" or cell.capital >= 0): return ""
	if cell.unit > 0:
		return "unit" if kind != "boar" else ""
	if cell.building != "" or cell.capital >= 0:
		return "building" if kind != "wolf" else ""
	return "tile" if cell.owner >= 0 else ""

static func can_attack(state, coord: Vector2i, kind: String) -> bool:
	return attack_kind(state,coord,kind) != "" and int(DEFINITIONS[kind].attack) > state.defense(coord)

static func enterable(state, coord: Vector2i, kind: String, home: Vector2i, source: Vector2i) -> bool:
	if not state.cells.has(coord) or state.is_mountain(coord) or state.is_bridge(coord) or state.is_barrier(coord): return false
	var cell: Dictionary = state.cells[coord]
	if coord != source and cell.get("animal", "") != "": return false
	if cell.get("lair", "") != "": return false
	if state.distance(coord,home) > CHASE_RADIUS: return false
	if cell.unit > 0 or cell.building != "" or cell.capital >= 0 or cell.owner >= 0:
		return can_attack(state,coord,kind)
	return true

static func route(state, source: Vector2i, target: Vector2i, kind: String, home: Vector2i) -> Array:
	var parents := {source:Grid.NONE}
	var pending := [source]
	var head := 0
	while head < pending.size():
		var coord: Vector2i = pending[head]
		head += 1
		if coord == target: break
		for next in state.neighbors(coord):
			if parents.has(next) or not enterable(state,next,kind,home,source): continue
			parents[next] = coord
			pending.append(next)
	if not parents.has(target): return []
	var path := [target]
	var cursor: Vector2i = target
	while cursor != source:
		cursor = parents[cursor]
		path.push_front(cursor)
	return path

static func decision(state, source: Vector2i, kind: String, home: Vector2i) -> Dictionary:
	var targets := []
	for target in state.cells:
		if target == source or state.distance(source,target) > SIGHT or not enterable(state,target,kind,home,source): continue
		var action := attack_kind(state,target,kind)
		if action == "": continue
		var score: int = 100 if action == "unit" else 60 if action == "building" else 20
		score += int(state.cells[target].get("value",1))*2-state.distance(source,target)*3
		targets.append({"coord":target,"score":score})
	targets.sort_custom(func(a,b):return a.score > b.score)
	for target in targets:
		var path := route(state,source,target.coord,kind,home)
		if path.size() >= 2: return {"step":path[1],"prey":target.coord}
	# Lost prey: return toward the home range before resuming local wandering.
	if state.distance(source,home) > ROAM_RADIUS:
		var shortest := []
		for near_home in state.neighbors(home):
			var path := route(state,source,near_home,kind,home)
			if path.size() >= 2 and (shortest.is_empty() or path.size() < shortest.size()): shortest = path
		if not shortest.is_empty(): return {"step":shortest[1],"prey":Grid.NONE}
	var options := []
	for next in state.neighbors(source):
		if state.distance(next,home) <= ROAM_RADIUS and enterable(state,next,kind,home,source): options.append(next)
	return {"step":source if options.is_empty() else options[state.rng.randi_range(0,options.size()-1)],"prey":Grid.NONE}

static func step_target(state, source: Vector2i, kind: String, home: Vector2i) -> Vector2i:
	return decision(state,source,kind,home).step

static func raid(state, target: Vector2i, kind: String) -> String:
	var cell: Dictionary = state.cells[target]
	var action := attack_kind(state,target,kind)
	if action == "":
		var forest: bool = cell.tree
		cell.tree = false
		return "attack" if forest else "move"
	if cell.get("fortified",false) or state.is_entrenched(target):
		cell.erase("entrenched_by")
		cell.fortified = false
		cell.fortified_by = -1
		return "blocked"
	if cell.unit > 0: state.kill_unit(target)
	cell.tree = false
	var owner: int = cell.owner
	cell.owner = -1
	cell.capital = -1
	if not preload("res://src/game/event_sites.gd").protected(cell): cell.building = ""
	cell.erase("entrenched_by")
	cell.fortified = false
	cell.fortified_by = -1
	if owner >= 0: state.rebuild_kingdoms({owner:true})
	state.clamp_mana()
	return "attack"

static func command(state, before: Dictionary, source: Vector2i, target: Vector2i, kind: String, outcome: String, home: Vector2i, extra := {}) -> Dictionary:
	var changes := {}
	for coord in state.cells:
		if before.get(coord) != state.cells[coord]: changes[coord] = state.cells[coord].duplicate(true)
	var result := {"kind":outcome,"source":source,"target":target,"animal":kind,"home":home,"changes":changes}
	result.merge(extra)
	var args := {"source":source,"target":target,"animal":kind,"home":home}
	args.merge(extra)
	state.record_replay("wildlife_"+outcome,-1,args)
	return result

static func spawn_site(state, home: Vector2i) -> Vector2i:
	var sites := []
	for coord in state.neighbors(home):
		var cell: Dictionary = state.cells[coord]
		if state.is_mountain(coord) or state.is_bridge(coord) or state.is_barrier(coord): continue
		if cell.owner >= 0 or cell.unit > 0 or cell.capital >= 0 or cell.building != "" or present(cell): continue
		if cell.grave or cell.mana_source or cell.event != "" or cell.get("treasure",0) > 0: continue
		sites.append(coord)
	var clear_sites := sites.filter(func(coord):return not state.cells[coord].tree)
	if not clear_sites.is_empty(): sites = clear_sites
	return Grid.NONE if sites.is_empty() else sites[state.rng.randi_range(0,sites.size()-1)]

static func world_turn(state) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	# Snapshot actors: new spawns never also move/attack on their emergence turn.
	var animals := []
	var occupied_homes := {}
	for coord in state.cells:
		var cell: Dictionary = state.cells[coord]
		if cell.get("animal", "") != "":
			animals.append(coord)
			occupied_homes[cell.animal_home] = true
	for home in state.cells:
		var lair: Dictionary = state.cells[home]
		if lair.get("lair", "") == "" or occupied_homes.has(home): continue
		var before: Dictionary = state.cells.duplicate(true)
		lair["lair_wait"] = maxi(0,int(lair.get("lair_wait",0))-1)
		if lair.lair_wait == 0 and lair.unit == 0 and lair.get("animal", "") == "":
			var target := spawn_site(state,home)
			# Blocked exits delay emergence; spawning never overwrites a province
			# occupant or also grants the animal an immediate attack.
			if target == Grid.NONE: continue
			state.cells[target]["animal"] = lair.lair
			state.cells[target]["animal_home"] = home
			state.cells[target].tree = false
			result.append(command(state,before,home,target,lair.lair,"spawn",home))
	for initial_source in animals:
		var source: Vector2i = initial_source
		for action_index in range(2):
			var cell: Dictionary = state.cells[source]
			if cell.get("animal", "") == "": break
			var kind: String = cell.animal
			var home: Vector2i = cell.animal_home
			var before: Dictionary = state.cells.duplicate(true)
			cell.tree = false
			var choice := decision(state,source,kind,home)
			var target: Vector2i = choice.step
			var prey: Vector2i = choice.prey
			var alert: bool = prey != Grid.NONE and cell.get("animal_target",Grid.NONE) != prey
			if prey == Grid.NONE: cell.erase("animal_target")
			else: cell["animal_target"] = prey
			if target == source:
				if before[source] != cell: result.append(command(state,before,source,source,kind,"calm",home))
				continue
			var outcome := raid(state,target,kind)
			if outcome != "blocked":
				cell.erase("animal")
				cell.erase("animal_home")
				cell.erase("animal_target")
				state.cells[target]["animal"] = kind
				state.cells[target]["animal_home"] = home
				if prey != Grid.NONE and target != prey: state.cells[target]["animal_target"] = prey
				else: state.cells[target].erase("animal_target")
			result.append(command(state,before,source,target,kind,outcome,home,{"alert":alert,"aggro_target":prey}))
			if outcome != "blocked": source = target
	return result
