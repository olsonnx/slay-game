extends SceneTree
const Rules = preload("res://src/game/kingdom_rules.gd")
const Replay = preload("res://src/game/replay_log.gd")
const Analysis = preload("res://src/game/ai_analysis.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func malformed_record_checks() -> void:
	var initial := {"cells":{}}
	var header := {"format":Replay.FORMAT, "version":1, "seed":42, "rules":"modern", "names":["Fern"], "humans":[0], "initial":initial, "hash":Replay.fingerprint(initial)}
	for delta in [{"cells":{}}, {"cells":{"set":{}, "erase":false}}, {"missing":{"set":{}, "erase":[]}}, {"cells":null}, {"cells":{"value":{}, "set":{}}}, {"cells":{"value":[]}}]:
		var row := {"type":"command", "seq":1, "round":1, "faction":0, "action":"move", "args":{}, "delta":delta, "hash":Replay.fingerprint(initial)}
		var result := Replay.read_records(PackedStringArray([JSON.stringify(header), JSON.stringify(row)]))
		expect(result["error"] != "", "Malformed deltas are rejected without engine errors")
		expect(Replay.expand_archive(Replay.archive_objects([header, row]))["error"] != "", "Compressed archives reject malformed deltas before deriving hashes")
	var authored_row := {"type":"command", "seq":1, "round":1, "faction":11, "action":"turn_end", "args":{}, "delta":{}, "hash":Replay.fingerprint(initial)}
	expect(Replay.read_records(PackedStringArray([JSON.stringify(header), JSON.stringify(authored_row)]))["error"] == "", "Twelfth-kingdom editor playtests retain valid replays")
	var unchanged := initial.duplicate(true)
	expect(not Replay.apply_delta(unchanged, {"cells":{"set":{"a":1},"erase":[]}, "bad":{}}) and unchanged == initial, "Delta validation is atomic across sections")
	for position in [[], {"cells":{"@hex:broken":{}}}, {"cells":{"@int:no":{}}}]:
		header["initial"] = position
		expect(Replay.read_records(PackedStringArray([JSON.stringify(header)]))["error"] != "", "Invalid initial encodings are rejected before decoding")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func reconstruct(model, path: String) -> Dictionary:
	var loaded: Dictionary = Replay.read_records(model.replay_log.records) if model.replay_log != null and not model.replay_log.finished else Replay.read_replay(path)
	expect(loaded["error"] == "", "Replay validates every command hash: " + loaded["error"])
	if loaded["error"] == "":
		expect(Replay.encode(loaded["position"]) == Replay.position(model), "Replay reconstructs the complete authoritative position")
	return loaded

func runtime_budget_checks() -> void:
	var model = Rules.new()
	for q in range(40):
		for r in range(25): model.cells[Vector2i(q,r)] = model.make_cell(0)
	model.cells[Vector2i.ZERO]["capital"] = 0
	model.rebuild_kingdoms()
	var recorder := Replay.new()
	recorder.start(model)
	var moves: Array = []
	var annotations: Array = []
	for sample in range(25):
		model.cells[Vector2i.ZERO]["moved"] = not model.cells[Vector2i.ZERO]["moved"]
		var started := Time.get_ticks_usec()
		recorder.record(model,"fixture_step",0)
		moves.append(Time.get_ticks_usec() - started)
		started = Time.get_ticks_usec()
		recorder.record(model,"ai_decision",0,{"score":1.25})
		annotations.append(Time.get_ticks_usec() - started)
	moves.sort()
	annotations.sort()
	# Generous median budgets tolerate slower hosts while catching the old
	# 90+ ms full-world conversion/hash repeated for every command/annotation.
	expect(moves[12] < 20000, "Thousand-province recording stays within the live capture budget")
	expect(annotations[12] < 2000, "AI annotations remain cheap regardless of board size")
	print("Replay capture budget: moves %.3f ms, annotations %.3f ms" % [moves[12]/1000.0,annotations[12]/1000.0])
	recorder.finish(model,"closed")

func run() -> void:
	malformed_record_checks()
	root.get_node("Sound").set_muted(true, false)
	var model = Rules.new()
	model.rule_mode = "modern"
	model.generate(42, "very_small", 2)
	var original_rng: int = model.rng.state
	var initial_position := Replay.position(model)
	var path := "res://artifacts/replay-fixture.jsonl"
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var replay := Replay.new()
	expect(replay.start(model, {"difficulty":"normal"}, path), "Replay starts with a complete initial position")
	model.replay_log = replay
	expect(not FileAccess.file_exists(path) and replay.path == "", "Starting a game creates no replay file")
	replay.save_completed(model)
	expect(not FileAccess.file_exists(path), "An unfinished game cannot be saved as a completed replay")
	expect(model.rng.state == original_rng, "Recording never consumes game RNG")
	var bank: Dictionary = model.kingdom_at(model.kingdoms.keys()[0])
	var capital: Vector2i = bank["capital"]
	var faction: int = bank["owner"]
	# A single explicit fixture setup is logged as well, before exercising commands.
	bank["gold"] = 500
	model.set_mana(faction, model.mana_capacity(faction))
	model.record_replay("fixture_setup", faction)
	var invalid_count := replay.sequence
	expect(not model.recruit(Vector2i(900,900), faction, 3), "Illegal recruitment is rejected")
	expect(replay.sequence == invalid_count, "Rejected commands do not enter the replay")
	expect(model.develop(capital, faction), "Development command executes")
	var first_development_sequence := replay.sequence
	var first_development_position := Replay.position(model)
	expect(model.develop(capital, faction), "A later command can update the same province")
	var history := Replay.read_records(replay.records.slice(0, first_development_sequence + 1))
	expect(history["error"] == "" and Replay.encode(history["position"]) == first_development_position, "Later province changes cannot rewrite earlier captured positions")
	var opening := Replay.read_records(replay.records.slice(0, 1))
	expect(opening["error"] == "" and Replay.encode(opening["position"]) == initial_position, "Initial position is immutable while the match changes")
	var diagnostic := {"action":{"kind":"test", "coord":capital}, "score":1.25}
	replay.record(model,"ai_decision",faction,diagnostic)
	var diagnostic_sequence := replay.sequence
	diagnostic["action"]["kind"] = "changed_later"
	var diagnostic_history := Replay.read_records(replay.records)
	expect(diagnostic_history["commands"][diagnostic_sequence - 1]["args"]["action"]["kind"] == "test", "Later AI diagnostics cannot mutate recorded decisions")
	var site: Vector2i = model.NONE
	for coord in bank["hexes"]:
		if model.can_build(coord, faction, "house", capital):
			site = coord
			break
	expect(site != model.NONE and model.build_structure(site, faction, "house", capital), "Construction command executes")
	expect(model.recruit(capital, faction, 3), "Recruitment command executes")
	var encounter := {"id":"gold", "coord":capital, "faction":faction}
	if model.Events.EVENTS.gold.has("authored"):
		model.magic.Encounters.Authored.prepare(model, model.Events.EVENTS.gold.authored, encounter)
	model.pending_events.append(encounter)
	model.record_replay("fixture_setup", faction)
	model.event_definition(encounter)
	var disclosed: int = encounter["gold_reward"]
	var gold_before: int = bank["gold"]
	model.resolve_event(encounter, 0)
	expect(bank["gold"] == gold_before + disclosed, "Replay captures the disclosed random gold reward")
	reconstruct(model, path)
	var bridges: Dictionary = model.bridge_targets(faction, capital)
	expect(not bridges.is_empty(), "Fixture has a bridge construction site")
	if not bridges.is_empty():
		var crossing: Vector2i = bridges.keys()[0]
		expect(model.build_structure(crossing, faction, "bridge", capital), "Added bridge cells are recorded")
		model.set_mana(faction, model.mana_capacity(faction))
		model.set_effect(faction, "free_spell", true)
		model.record_replay("fixture_setup", faction)
		expect(model.cast_spell("shatter", crossing, faction, capital), "Bridge destruction spell is recorded")
		expect(not model.cells.has(crossing), "Shatter deletes the recorded bridge")
		reconstruct(model, path)
	model.begin_turn(faction)
	model.spread_trees()
	var moves: Dictionary = model.reachable_targets(capital)
	expect(not moves.is_empty(), "Fixture has legal movements")
	if not moves.is_empty():
		var saved: Dictionary = Replay.decode(Replay.position(model))
		var count_before := replay.sequence
		replay.begin_transaction()
		model.perform_move(capital, moves.keys()[0])
		expect(replay.sequence == count_before, "Uncommitted animation is not written to disk")
		model.cells = saved["cells"]
		model.kingdoms = saved["kingdoms"]
		model.mana_by_faction = saved["mana"]
		model.effects_by_faction = saved["effects"]
		model.pending_events.assign(saved["events"])
		model.rng.state = int(saved["rng"])
		replay.cancel_transaction()
		reconstruct(model, path)
		replay.begin_transaction()
		model.perform_move(capital, moves.keys()[0])
		replay.commit_transaction()
		expect(replay.sequence == count_before + 1, "Committed movement is recorded once")
	var copy = Analysis.snapshot(model)
	expect(copy.replay_log == null, "AI search snapshots cannot write replay files")
	var before_planning := replay.sequence
	var ai = model.KingdomAI.new(model)
	ai.prepare_ai_turn(1)
	expect(replay.sequence > before_planning, "AI preparation records actual commands")
	ai.ai_movements(1)
	var loaded := reconstruct(model, path)
	if loaded["error"] == "": expect(int(loaded["position"]["rng"]) == model.rng.state, "64-bit RNG state survives JSON exactly")
	var has_ai := false
	var has_turn := false
	if loaded["error"] == "":
		for command in loaded["commands"]:
			if command["action"] == "ai_decision": has_ai = true
			if command["action"] == "turn_start" and command.has("economy"): has_turn = true
	expect(has_ai and has_turn, "Replay includes AI search annotations and settlement finances")
	var expected_records := Replay.read_records(replay.records)
	replay.finish(model, "completed", faction)
	expect(not FileAccess.file_exists(path), "Completion keeps the replay in memory until the player saves")
	replay.save_completed(model)
	loaded = reconstruct(model, path)
	if loaded["error"] == "":
		expect(loaded["header"] == expected_records["header"], "Compaction preserves every original metadata field")
		for index in range(expected_records["commands"].size()):
			expect(loaded["commands"][index] == expected_records["commands"][index], "Compaction preserves all fields and diagnostics at command %d" % (index + 1))
	var final_count := replay.sequence
	replay.finish(model, "closed")
	expect(replay.sequence == final_count, "Closing a completed game never duplicates its result")
	if loaded["error"] == "": expect(loaded["commands"][-1]["action"] == "result", "Replay has a final result")
	var corrupt := FileAccess.open("res://artifacts/replay-corrupt.jsonl", FileAccess.WRITE)
	var contents := FileAccess.get_file_as_string(path)
	corrupt.store_string(contents.replace('"develop":[', '"tampered":['))
	corrupt.close()
	expect(Replay.read_replay("res://artifacts/replay-corrupt.jsonl")["error"] != "", "Out-of-order or corrupted records are rejected")
	var partial := FileAccess.open("res://artifacts/replay-partial.jsonl", FileAccess.WRITE)
	var legacy_lines: PackedStringArray = Replay.expand_archive(contents.strip_edges().split("\n"))["lines"]
	var legacy_file := FileAccess.open("res://artifacts/replay-legacy-fixture.jsonl", FileAccess.WRITE)
	legacy_file.store_string("\n".join(legacy_lines) + "\n")
	legacy_file.close()
	var legacy_result := Replay.read_replay("res://artifacts/replay-legacy-fixture.jsonl")
	expect(legacy_result["error"] == "" and legacy_result["commands"] == loaded["commands"], "Legacy and compact readers return identical records")
	partial.store_string("\n".join(legacy_lines) + '\n{"type":"command"')
	partial.close()
	var recovered := Replay.read_replay("res://artifacts/replay-partial.jsonl")
	expect(recovered["error"] == "" and recovered["incomplete_tail"], "A crash-truncated final line preserves every complete command")
	if recovered["error"] == "": expect(Replay.encode(recovered["position"]) == Replay.position(model), "Recovered complete prefix still reconstructs exactly")
	# Exercise the real controller, including the cancellation path and restarts.
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	await process_frame
	expect(game.rules.replay_log != null and game.rules.replay_log.path == "", "Ordinary unfinished games only record in memory")
	var first_log = game.rules.replay_log
	var source: Vector2i = game.NONE
	for coord in game.cells:
		if game.cells[coord]["owner"] == 0 and game.cells[coord]["unit"] > 0:
			source = coord
			break
	var target: Vector2i = game.rules.reachable_targets(source).keys()[0]
	await game.click_hex(source, "unit")
	game.click_hex(target)
	expect(game.busy and game.rules.replay_log.transaction, "Player animation starts a replay transaction")
	game.cancel_action()
	await process_frame
	expect(not game.busy and not game.rules.replay_log.transaction, "Cancellation ends the replay transaction")
	loaded = reconstruct(game.rules, "")
	expect(loaded["error"] == "" and loaded["commands"].is_empty(), "Cancelled player movement leaves no replay command")
	game.new_game(43)
	expect(game.rules.replay_log != first_log, "Restarted games get an independent recording buffer")
	expect(first_log.finished and first_log.path == "" and first_log.records.is_empty(), "Restart discards its unfinished recording without creating a file")
	var abandoned_log = game.rules.replay_log
	game.shutdown()
	expect(abandoned_log.finished and abandoned_log.path == "" and abandoned_log.records.is_empty(), "Leaving an unfinished game discards the recording")
	game.queue_free()
	await process_frame
	await process_frame
	for outcome in ["restarted", "left_game", "closed", "round_limit"]:
		var discarded := Replay.new()
		discarded.start(model, {}, "res://artifacts/should-not-exist-%s.jsonl" % outcome)
		discarded.finish(model, outcome)
		expect(discarded.path == "" and discarded.records.is_empty(), "Unfinished recording is discarded: " + outcome)
		expect(not FileAccess.file_exists(discarded.destination), "Unfinished game creates no file: " + outcome)
	for victory in [true, false]:
		var completed_game = load("res://scenes/main.tscn").instantiate()
		completed_game.initial_rule_mode = "modern"
		completed_game.initial_seed = 42
		root.add_child(completed_game)
		completed_game.set_process(false)
		await process_frame
		var completed_path := "res://artifacts/replay-controller-%s.jsonl" % ("win" if victory else "loss")
		if FileAccess.file_exists(completed_path): DirAccess.remove_absolute(completed_path)
		completed_game.rules.replay_log.destination = completed_path
		expect(not FileAccess.file_exists(completed_path), "No controller replay file exists before a result")
		for cell in completed_game.cells.values():
			if (cell["owner"] > 0 if victory else cell["owner"] == 0):
				cell["owner"] = -1
				cell["capital"] = -1
				cell["unit"] = 0
		completed_game.rules.rebuild_kingdoms()
		completed_game.check_winner()
		expect(completed_game.game_over and not FileAccess.file_exists(completed_path), "Natural victory/defeat does not automatically save a replay")
		completed_game.rules.replay_log.save_completed(completed_game.rules)
		expect(FileAccess.file_exists(completed_path), "Player can explicitly save a finished replay")
		reconstruct(completed_game.rules, completed_path)
		var saved_path: String = completed_game.rules.replay_log.path
		completed_game.shutdown()
		expect(FileAccess.file_exists(saved_path), "Leaving after a result preserves its replay")
		completed_game.queue_free()
		await process_frame
	runtime_budget_checks()
	print("Replay checks: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
