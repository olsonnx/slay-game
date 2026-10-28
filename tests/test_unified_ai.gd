extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Strategy = preload("res://src/game/ai_strategist.gd")
const Snapshots = preload("res://src/game/state_snapshot.gd")
const Fixture = preload("res://tools/heavy_strain_probe.gd")
var checks := 0
var failures := 0
class Host extends Node:
	var closing := false
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var host := Host.new()
	root.add_child(host)
	for size_id in Rules.MapSizes.IDS:
		for difficulty in ["easy","normal","hard"]:
			var model = Fixture.crowded(size_id,71,30 if size_id in ["small","medium"] else 60)
			model.ai_difficulty = difficulty
			# Old automatic metadata and new explicit defaults both use one policy.
			if difficulty == "normal": model.ai_algorithm = "auto"
			var opponent = model.KingdomAI.new(model)
			var before := Snapshots.capture(model)
			var planner = await opponent.search_async(host,1)
			expect(planner is Strategy, "%s/%s selects strategic AI on the search worker" % [size_id,difficulty])
			expect(Snapshots.capture(model) == before, "Unified search preserves the live position and RNG")
			var repeated = opponent.run_planner(1)
			expect(repeated is Strategy and planner.best_sequence == repeated.best_sequence, "Serial and worker execution produce the same unified plan")
			var destinations := {}
			for order in planner.best_sequence:
				expect(model.can_move(order.source,order.coord), "Unified assignments are authoritative-legal")
				expect(not destinations.has(order.coord), "Unified assignments reserve unique destinations")
				destinations[order.coord] = true
			var cap := 16 if difficulty == "easy" else 40 if difficulty == "normal" else 64
			expect(planner.evaluated <= planner.units.size() * cap, "Every map size retains the difficulty's bounded tactical budget")
			await opponent.prepare_async(host,1)
			var finished := false
			for batch in range(128):
				var records: Array = await opponent.movements_async(host,1)
				if records.is_empty():
					finished = true
					break
				expect(model.ai_last_decision.get("algorithm") == "strategic", "Live simulation commits strategic decisions at every map size")
			expect(finished, "Unified AI completes its faction turn within a bounded number of batches")
	# Historical replay playback is driven by recorded deltas, not by replanning.
	# Keep its explicit legacy override available only to reference diagnostics.
	var reference = Rules.new()
	reference.ai_algorithm = "legacy"
	expect(not reference.uses_strategic_ai(), "Reference diagnostics remain explicitly selectable")
	host.queue_free()
	print("Unified AI checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
