extends RefCounted
## Resumable bounded beam search. A step evaluates one independent candidate.
const Analysis = preload("res://src/game/ai_analysis.gd")
const Candidates = preload("res://src/game/ai_candidates.gd")
var state
var faction: int
var spending: bool
var baseline: float
var profile: Dictionary
var beam: Array = []
var children: Array = []
var stopping: Array = []
var pending: Array = []
var pending_head := 0
var depth := 0
var best: Dictionary = {}
var best_sequence: Array = []
var best_score := 0.25
var evaluated := 0
var done := false
var replies: Array = []
var reply_index := 0
var reply_model
var reply_options: Array = []
var reply_head := 0
var reply_worst
var reply_worst_value := 0.0
var reply_offset := 1
var reply_baseline := 0.0
var reply_prepared := false
var max_step_usec := 0
var started_usec := Time.get_ticks_usec()

func _init(model, owner: int, preparation := false, owns_snapshot := false) -> void:
	state = model
	faction = owner
	spending = preparation
	profile = Analysis.profile(model)
	var copy = model if owns_snapshot else Analysis.snapshot(model)
	var queries = Analysis.Queries.new(copy)
	baseline = 0.0 if spending else Analysis.evaluate(copy, faction, queries)
	beam = [{"model": copy, "queries": queries, "first": {}, "score": 0.0, "cost": 0.0, "sequence": []}]
	var queued_at := Time.get_ticks_usec()
	queue_layer()
	if spending: max_step_usec = Time.get_ticks_usec() - queued_at

func queue_layer() -> void:
	pending.clear()
	pending_head = 0
	for node in beam:
		var options: Array = Candidates.preparation(node["model"], faction, node["queries"]) if spending else Candidates.movements(node["model"], faction, node["queries"])
		if spending:
			# Both backends use the same opportunity/defence/affordability policy.
			# It evaluates what the purchase enables without board-copying each
			# deployment square or charging wages before seeing its purpose.
			evaluated = options.size()
			if not options.is_empty() and options[0]["priority"] > best_score:
				best = options[0]
				best_score = best["priority"]
				best_sequence = [best]
			done = true
			return
		if options.is_empty() and state.ai_difficulty == "hard" and not node["first"].is_empty():
			# A short finished sequence still needs the same reply test as a
			# depth-five sequence; keep it competing within the existing beam.
			children.append(node)
		for action in options:
			pending.append({"parent": node, "action": action})

func step() -> bool:
	var started := Time.get_ticks_usec()
	var finished := advance()
	max_step_usec = maxi(max_step_usec, Time.get_ticks_usec() - started)
	return finished

func advance() -> bool:
	if done:
		return true
	if not replies.is_empty():
		return reply_step()
	if pending_head < pending.size():
		var work: Dictionary = pending[pending_head]
		pending[pending_head] = null
		pending_head += 1
		var copy = Analysis.snapshot(work["parent"]["model"])
		var action: Dictionary = work["action"]
		var cost: float = work["parent"]["cost"]
		if copy.knight_duel(action["source"], action["coord"]):
			cost += 3.0
		if Candidates.apply(copy, action, faction):
			evaluated += 1
			var queries = Analysis.Queries.new(copy)
			var value: float = Analysis.evaluate(copy, faction, queries) - baseline - cost
			if action["kind"] == "move":
				value -= (depth + 1) * 0.12
				value += Analysis.variation(state, action["source"], action["coord"])
				if work["parent"]["model"].cells[action["coord"]]["owner"] >= 0 and work["parent"]["model"].cells[action["coord"]]["owner"] != faction:
					var disruption: float = work["parent"]["queries"].cut_value(action["coord"])
					var opportunity: float = disruption * 0.6 + work["parent"]["queries"].campaign_value(action["coord"],faction) * 0.35
					cost -= opportunity
					value += opportunity
			var first: Dictionary = action if work["parent"]["first"].is_empty() else work["parent"]["first"]
			var sequence: Array = work["parent"]["sequence"] + [action]
			children.append({"model": copy, "queries": queries, "first": first, "score": value, "cost": cost, "sequence": sequence})
			if value > best_score:
				best_score = value
				best = first
				best_sequence = sequence
		return false
	depth += 1
	children.sort_custom(func(a, b): return a["score"] > b["score"])
	beam = children.slice(0, int(profile["width"]))
	if state.ai_difficulty == "hard":
		# Ending after any useful prefix is legal. Keep a separate bounded set
		# so stops cannot crowd every continuing branch out of the beam.
		stopping.append_array(beam)
		stopping.sort_custom(func(a, b): return a["score"] > b["score"])
		stopping = stopping.slice(0, int(profile["width"]))
	children = []
	if spending or depth >= int(profile["depth"]) or beam.is_empty() or pending.is_empty():
		if not spending and state.ai_difficulty == "hard" and not beam.is_empty():
			# Compare the strongest sequences against holding with the same replies.
			var held = Analysis.snapshot(state)
			best = {}
			best_sequence = []
			best_score = 0.25
			replies = [{"model": held, "first": {}, "cost": 0.0, "sequence": []}]
			for node in stopping + beam:
				if not replies.any(func(other): return other["sequence"] == node["sequence"]): replies.append(node)
			# At most 2 * width + 1 reply positions, including holding.
		else:
			done = true
	else:
		queue_layer()
	return done

func reply_step() -> bool:
	# One branch per step keeps even Hard's reply checks interruptible.
	var node: Dictionary = replies[reply_index]
	if reply_model == null:
		reply_model = Analysis.snapshot(node["model"])
		reply_model.ai_difficulty = "normal"
		reply_offset = 1
	if reply_offset >= reply_model.faction_count:
		var value: float = Analysis.evaluate(reply_model, faction)
		if reply_index == 0:
			reply_baseline = value
		elif value - reply_baseline - node["cost"] > best_score:
			best_score = value - reply_baseline - node["cost"]
			best = node["first"]
			best_sequence = node["sequence"]
		reply_index += 1
		reply_model = null
		reply_prepared = false
		done = reply_index == replies.size()
		return done
	var opponent: int = (faction + reply_offset) % reply_model.faction_count
	if not reply_prepared:
		var queries = Analysis.Queries.new(reply_model)
		var relevant := false
		for threat in queries.threats(faction).values():
			for source in threat["sources"]:
				if reply_model.unit_faction(source) == opponent:
					relevant = true
					break
			if relevant: break
		if not relevant:
			# Its own barriers expire at settlement and can reopen a route that
			# the current threat map cannot see. Keep that opponent in the sample.
			for cell in reply_model.cells.values():
				if cell["barrier_by"] == opponent:
					relevant = true
					break
		if not relevant:
			reply_offset += 1
			return false
		# Settlement precedes retaliation. Do not let an army bankrupted by the
		# planned cut make a fictional counterattack, or ignore a rival's income.
		reply_model.begin_turn(opponent)
		queries = Analysis.Queries.new(reply_model)
		reply_worst = reply_model
		reply_worst_value = Analysis.evaluate(reply_model, faction, queries)
		reply_options = Candidates.movements(reply_model, opponent, queries).slice(0, 2)
		reply_head = 0
		reply_prepared = true
		return false
	if reply_head < reply_options.size():
		var action: Dictionary = reply_options[reply_head]
		reply_options[reply_head] = null
		reply_head += 1
		var branch = Analysis.snapshot(reply_model)
		if Candidates.apply(branch, action, opponent):
			evaluated += 1
			var value: float = Analysis.evaluate(branch, faction)
			if value < reply_worst_value:
				reply_worst_value = value
				reply_worst = branch
		return false
	reply_model = reply_worst
	reply_offset += 1
	reply_prepared = false
	return false

func run() -> Dictionary:
	while not step():
		pass
	return best
