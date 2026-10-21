extends RefCounted
## Completed games only: readable decision lines plus lossless compressed detail.
## Only authoritative rules opt in. AI search copies never inherit the recorder.
const Snapshots = preload("res://src/game/state_snapshot.gd")
const Summary = preload("res://src/game/replay_summary.gd")
const FORMAT := "slay-replay"
const VERSION := 2
const DIRECTORY := "user://replays"
const MAX_FILE_BYTES := 64 * 1024 * 1024
const MAX_DETAIL_BYTES := 256 * 1024 * 1024
var path := ""
var error := ""
var round_number := 1
var sequence := 0
var finished := false
var completed := false
var previous: Dictionary = {}
var transaction := false
var buffered: Array = []
var checkpoint: Dictionary = {}
var started := false
var destination := ""
var header: Dictionary = {}
var rows: Array[Dictionary] = []
# Legacy text is generated only for explicit inspection/tests, never per move.
var records: PackedStringArray:
	get: return inspection_records()

static func raw_position(model) -> Dictionary:
	return Snapshots.replay_position(model)

static func copy_index(source: Dictionary) -> Dictionary:
	var result := source.duplicate()
	for section in source:
		if source[section] is Dictionary: result[section] = source[section].duplicate()
	return result

func inspection_records() -> PackedStringArray:
	var result := PackedStringArray()
	if header.is_empty(): return result
	var first: Dictionary = encode(header)
	var state: Dictionary = first["initial"].duplicate(true)
	first["hash"] = fingerprint(state)
	result.append(JSON.stringify(first, "", true, true))
	for native_row in rows:
		var row: Dictionary = encode(native_row)
		apply_delta(state, row["delta"])
		row["hash"] = fingerprint(state)
		result.append(JSON.stringify(row, "", true, true))
	return result

static func encode(value):
	if value is Vector2i: return "@hex:%d,%d" % [value.x, value.y]
	if value is Dictionary:
		var result := {}
		for key in value:
			var encoded_key: String = encode(key) if key is Vector2i else "@int:%d" % key if key is int else str(key)
			result[encoded_key] = encode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(encode(item))
		return result
	return value

static func decode(value):
	if value is String and value.begins_with("@hex:"):
		var parts: PackedStringArray = value.substr(5).split(",")
		return Vector2i(int(parts[0]), int(parts[1]))
	if value is Dictionary:
		var result := {}
		for key in value:
			var decoded_key = int(key.substr(5)) if key.begins_with("@int:") else decode(key)
			result[decoded_key] = decode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(decode(item))
		return result
	# JSON parses all numbers as floats; game state only stores integer numbers.
	return int(value) if value is float else value

static func position(model) -> Dictionary:
	return encode(Snapshots.replay_position(model, false))

static func fingerprint(value: Dictionary) -> String:
	return JSON.stringify(encode(decode(value))).sha256_text()

static func economics(model) -> Array:
	var result: Array = []
	for bank in model.kingdoms.values():
		result.append({"capital":bank["capital"], "faction":bank["owner"],
			"gold":bank["gold"], "income":model.income(bank), "wages":model.upkeep(bank)})
	return result

func start(model, metadata: Dictionary = {}, target_path := "") -> bool:
	# No directories, temporary files or reserved filenames for an unfinished game.
	destination = target_path
	started = true
	var initial := raw_position(model)
	previous = copy_index(initial)
	append_record({"type":"header", "format":FORMAT, "version":1,
		"created_utc":Time.get_datetime_string_from_system(true), "seed":model.level_seed,
		"rules":model.rule_mode, "map_size":model.map_size, "factions":model.faction_count,
		"humans":model.human_factions.duplicate(), "names":model.faction_names.duplicate(), "metadata":metadata.duplicate(true),
		"balance":{"prices":model.Catalog.UNIT_PRICES, "wages":model.Catalog.MODERN_UPKEEP if model.is_modern() else model.Catalog.UPKEEP},
		"initial":initial, "economy":economics(model)})
	return error == ""

func append_record(row: Dictionary) -> void:
	if not started or error != "": return
	if row["type"] == "header": header = row
	else: rows.append(row)

static func brief(value):
	if value is float and value == floor(value): return int(value)
	if value is String and value.begins_with("@hex:"): return value.substr(5)
	if value is Array:
		var result: Array = []
		for item in value: result.append(brief(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value:
			if key != "path": result[key] = brief(value[key])
		return result
	return value

static func integer_numbers(value):
	if value is float and value == floor(value): return int(value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(integer_numbers(item))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = integer_numbers(value[key])
		return result
	return value

static func decision_line(row: Dictionary) -> Dictionary:
	return {row["action"]:[int(row["seq"]), int(row["round"]), int(row["faction"]), brief(row["args"])]}

static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func archive(source_records: PackedStringArray) -> PackedStringArray:
	var objects: Array = []
	for line in source_records: objects.append(integer_numbers(JSON.parse_string(line)))
	return archive_objects(objects)

static func archive_objects(objects: Array) -> PackedStringArray:
	var first: Dictionary = objects[0]
	var slim := PackedStringArray()
	for object in objects:
		var row: Dictionary = object.duplicate()
		# Position hashes are exactly derivable from the retained state tape.
		# The archive SHA-256 protects the compressed tape before reconstruction.
		row.erase("hash")
		slim.append(JSON.stringify(row, "", true, true))
	var raw := ("\n".join(slim) + "\n").to_utf8_buffer()
	if raw.size() > MAX_DETAIL_BYTES: return PackedStringArray()
	var result := PackedStringArray([JSON.stringify({"format":FORMAT, "version":VERSION,
		"seed":int(first["seed"]), "rules":first["rules"], "names":first["names"], "humans":brief(first["humans"]), "encoding":"gzip-base64",
		"columns":["sequence", "round", "faction", "arguments"], "derived_hashes":true, "sha256":digest(raw),
		"summary":Summary.from_records(first, objects.slice(1))})])
	# AI diagnostics are attached to the full record, not duplicated in the
	# human timeline. Every actual action still has exactly one readable line.
	for index in range(1, objects.size()):
		var row: Dictionary = objects[index]
		if row["action"] != "ai_decision": result.append(JSON.stringify(decision_line(row), "", true, true))
	result.append(JSON.stringify({"data":Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_GZIP))}))
	return result

func save_completed(model) -> void:
	if not completed or path != "": return
	error = ""
	var target := destination
	if target == "":
		target = DIRECTORY.path_join("%s-%s-%s.jsonl" % [Time.get_datetime_string_from_system().replace(":", "-"), model.level_seed, Time.get_ticks_usec()])
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
	if directory_error != OK:
		error = error_string(directory_error)
		return
	var temporary := target + ".tmp"
	var objects: Array = [encode(header)]
	for row in rows: objects.append(encode(row))
	var archive_lines := archive_objects(objects)
	if archive_lines.is_empty():
		error = "Replay details are too large"
		return
	var serialized := ("\n".join(archive_lines) + "\n").to_utf8_buffer()
	if serialized.size() > MAX_FILE_BYTES:
		error = "Replay file is too large"
		return
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null:
		error = error_string(FileAccess.get_open_error())
		return
	output.store_buffer(serialized)
	output.flush()
	var write_error := output.get_error()
	output.close()
	if write_error == OK: write_error = DirAccess.rename_absolute(temporary, target)
	if write_error != OK:
		error = error_string(write_error)
		DirAccess.remove_absolute(temporary)
		return
	path = target

static func changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var delta := {}
	for section in after:
		if before.get(section) == after[section]: continue
		if after[section] is Dictionary:
			var updated := {}
			var removed: Array = []
			var old: Dictionary = before.get(section, {})
			for key in after[section]:
				if not old.has(key) or old[key] != after[section][key]: updated[key] = after[section][key]
			for key in old:
				if not after[section].has(key): removed.append(key)
			delta[section] = {"set":updated, "erase":removed}
		else: delta[section] = {"value":after[section]}
	return delta

static func valid_encoding(value, depth := 0) -> bool:
	if depth > 64: return false
	if value is String and value.begins_with("@hex:"):
		var parts: PackedStringArray = value.substr(5).split(",")
		return parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int()
	if value is Dictionary:
		for key in value:
			if not key is String or not valid_encoding(key, depth + 1): return false
			if key.begins_with("@int:") and not key.substr(5).is_valid_int(): return false
			if not valid_encoding(value[key], depth + 1): return false
	elif value is Array:
		for item in value:
			if not valid_encoding(item, depth + 1): return false
	elif value is float and not is_finite(value): return false
	return true

static func valid_command(row) -> bool:
	if not row is Dictionary or row.get("type") != "command" or not row.get("action") is String or not row.get("args") is Dictionary or not row.get("delta") is Dictionary: return false
	for field in ["seq", "round", "faction"]:
		var value = row.get(field)
		if not (value is int or value is float) or not is_finite(float(value)) or value != floorf(float(value)): return false
	return row["seq"] >= 1 and row["round"] >= 1 and row["faction"] >= -1 and row["faction"] < 64

static func apply_delta(state: Dictionary, delta: Dictionary) -> bool:
	# Validate the complete patch before changing anything: callers must be able
	# to reject a bad record without a script error or a partially changed board.
	for section in delta:
		if not state.has(section): return false
		var patch = delta[section]
		if not patch is Dictionary: return false
		if patch.has("value"):
			if patch.size() != 1 or state[section] is Dictionary or typeof(patch["value"]) != typeof(state[section]) or not valid_encoding(patch["value"]): return false
		else:
			if patch.size() != 2 or not patch.get("erase") is Array or not patch.get("set") is Dictionary or not state.get(section) is Dictionary: return false
			if not valid_encoding(patch["set"]) or not valid_encoding(patch["erase"]): return false
			for key in patch["erase"]:
				if not key is String: return false
	for section in delta:
		var patch: Dictionary = delta[section]
		if patch.has("value"): state[section] = patch["value"]
		else:
			for key in patch["erase"]: state[section].erase(key)
			for key in patch["set"]: state[section][key] = patch["set"][key]
	return true

func capture_dictionary(section: String, live: Dictionary, delta: Dictionary) -> void:
	var old: Dictionary = previous[section]
	var updated := {}
	var removed: Array = []
	for key in live:
		if not old.has(key) or old[key] != live[key]:
			var value = live[key]
			# Only changed records are copied. Captured values are immutable from
			# this point: subsequent commands replace entries instead of editing them.
			if value is Dictionary or value is Array: value = value.duplicate(true)
			updated[key] = value
			old[key] = value
	for key in old:
		if not live.has(key): removed.append(key)
	for key in removed: old.erase(key)
	if not updated.is_empty() or not removed.is_empty(): delta[section] = {"set":updated, "erase":removed}

func capture_changes(model) -> Dictionary:
	var delta := {}
	capture_dictionary("cells", model.cells, delta)
	capture_dictionary("kingdoms", model.kingdoms, delta)
	capture_dictionary("mana", model.mana_by_faction, delta)
	capture_dictionary("effects", model.effects_by_faction, delta)
	capture_dictionary("capital_relocations", model.capital_relocations, delta)
	var values := {"events":model.pending_events, "rng":str(model.rng.state), "difficulty":model.ai_difficulty, "faction_count":model.faction_count}
	for section in values:
		if previous[section] == values[section]: continue
		var value = values[section]
		if value is Array: value = value.duplicate(true)
		delta[section] = {"value":value}
		previous[section] = value
	return delta

func record(model, kind: String, faction := -1, arguments: Dictionary = {}) -> void:
	if finished or not started or error != "": return
	var row := {"type":"command", "seq":sequence + buffered.size() + 1, "round":round_number,
		"faction":faction, "controller":"human" if faction in model.human_factions else "ai" if faction >= 0 else "world",
		"action":kind, "args":arguments.duplicate(true), "delta":{} if kind == "ai_decision" else capture_changes(model)}
	if kind in ["turn_start", "turn_end", "result"]: row["economy"] = economics(model)
	if transaction: buffered.append(row)
	else:
		sequence += 1
		append_record(row)

func begin_transaction() -> void:
	assert(not transaction)
	transaction = true
	checkpoint = copy_index(previous)

func fork_worker():
	assert(not transaction)
	var fork = get_script().new()
	fork.started = started
	fork.finished = finished
	fork.error = error
	fork.round_number = round_number
	fork.sequence = sequence
	fork.previous = copy_index(previous)
	return fork

func publish_worker(fork, expected_sequence: int) -> void:
	assert(sequence == expected_sequence and not transaction and not finished)
	previous = fork.previous
	sequence = fork.sequence
	round_number = fork.round_number
	rows.append_array(fork.rows)

func commit_transaction() -> void:
	for row in buffered:
		sequence += 1
		append_record(row)
	buffered.clear()
	checkpoint.clear()
	transaction = false

func cancel_transaction() -> void:
	if not transaction: return
	previous = checkpoint
	checkpoint = {}
	buffered.clear()
	transaction = false

func finish(model, outcome: String, winner := -1, completion: Dictionary = {}) -> void:
	if finished: return
	if outcome in ["completed", "victory", "defeat", "draw"]:
		if transaction: commit_transaction()
		var result := completion.duplicate(true)
		result.merge({"outcome":outcome, "winner":winner, "completed_utc":Time.get_datetime_string_from_system(true)}, true)
		record(model, "result", -1, result)
		completed = true
	else: cancel_transaction()
	finished = true
	if not completed:
		header.clear()
		rows.clear()
	buffered.clear()
	checkpoint.clear()
	previous.clear()

static func expand_archive(lines: PackedStringArray, derive_hashes := true, cancelled := Callable()) -> Dictionary:
	var parser := JSON.new()
	if lines.is_empty() or parser.parse(lines[0]) != OK: return {"error":"Invalid replay header"}
	var envelope = parser.data
	if not envelope is Dictionary: return {"error":"Invalid replay header"}
	if envelope.get("version") == 1: return {"error":"", "lines":lines}
	if envelope.get("format") != FORMAT or envelope.get("version") != VERSION or envelope.get("encoding") != "gzip-base64":
		return {"error":"Unsupported replay header"}
	if parser.parse(lines[-1]) != OK or not parser.data is Dictionary or not parser.data.get("data") is String:
		return {"error":"Missing compressed replay details"}
	var compressed := Marshalls.base64_to_raw(parser.data["data"])
	var raw := compressed.decompress_dynamic(MAX_DETAIL_BYTES, FileAccess.COMPRESSION_GZIP)
	if raw.is_empty() or digest(raw) != envelope.get("sha256"):
		return {"error":"Replay archive checksum mismatch"}
	var expanded := raw.get_string_from_utf8().strip_edges().split("\n")
	if derive_hashes and envelope.get("derived_hashes", false):
		var state := {}
		for index in range(expanded.size()):
			if cancelled.is_valid() and cancelled.call(): return {"error":"Replay loading cancelled"}
			if parser.parse(expanded[index]) != OK or not parser.data is Dictionary: return {"error":"Invalid compressed record"}
			var row: Dictionary = parser.data
			if index == 0:
				if not row.get("initial") is Dictionary or not valid_encoding(row["initial"]): return {"error":"Invalid initial position"}
				state = row["initial"].duplicate(true)
			else:
				if not valid_command(row) or not apply_delta(state, row["delta"]): return {"error":"Invalid compressed command"}
			row["hash"] = fingerprint(state)
			expanded[index] = JSON.stringify(integer_numbers(row), "", true, true)
	if parser.parse(expanded[0]) != OK or not parser.data is Dictionary or parser.data.get("seed") != envelope.get("seed") or parser.data.get("rules") != envelope.get("rules") or parser.data.get("names") != envelope.get("names") or parser.data.get("humans") != envelope.get("humans"):
		return {"error":"Replay metadata mismatch"}
	var detail_header: Dictionary = parser.data
	var detail_results: Array = []
	var timeline_index := 1
	for index in range(1, expanded.size()):
		if cancelled.is_valid() and cancelled.call(): return {"error":"Replay loading cancelled"}
		if parser.parse(expanded[index]) != OK or not valid_command(parser.data): return {"error":"Invalid compressed command"}
		var row: Dictionary = parser.data
		if not row.has_all(["seq", "round", "faction"]): return {"error":"Invalid compressed command"}
		if row.get("action") == "result": detail_results.append(row)
		if row.get("action") == "ai_decision": continue
		var expected := decision_line(row)
		if timeline_index >= lines.size() - 1 or parser.parse(lines[timeline_index]) != OK or brief(parser.data) != expected:
			return {"error":"Readable decision timeline mismatch"}
		timeline_index += 1
	if timeline_index != lines.size() - 1: return {"error":"Unexpected replay timeline lines"}
	if envelope.has("summary") and integer_numbers(envelope["summary"]) != integer_numbers(Summary.from_records(detail_header, detail_results)):
		return {"error":"Replay summary mismatch"}
	return {"error":"", "lines":expanded}

static func read_replay(source_path: String, for_playback := false, cancelled := Callable()) -> Dictionary:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null: return {"error":"Cannot open replay"}
	if source.get_length() > MAX_FILE_BYTES: return {"error":"Replay file is too large"}
	var lines := source.get_as_text().strip_edges().split("\n")
	# The archive checksum already authenticates the complete state tape. Playback
	# need not serialize/hash the entire board twice for every recorded command.
	var envelope = JSON.parse_string(lines[0]) if not lines.is_empty() else null
	var authenticated_tape: bool = for_playback and envelope is Dictionary and envelope.get("version") == VERSION and envelope.get("derived_hashes", false) == true
	var expanded := expand_archive(lines, not authenticated_tape, cancelled)
	if expanded["error"] != "": return expanded
	return read_records(expanded["lines"], not authenticated_tape, cancelled)

static func read_records(lines: PackedStringArray, verify_hashes := true, cancelled := Callable()) -> Dictionary:
	var parser := JSON.new()
	if lines.is_empty() or parser.parse(lines[0]) != OK: return {"error":"Invalid replay header"}
	var header = parser.data
	if not header is Dictionary or header.get("format") != FORMAT or header.get("version") != 1:
		return {"error":"Unsupported replay header"}
	if not header.get("initial") is Dictionary or not valid_encoding(header["initial"]): return {"error":"Invalid initial position"}
	var state: Dictionary = header["initial"].duplicate(true)
	if verify_hashes and fingerprint(state) != header.get("hash"): return {"error":"Initial position hash mismatch"}
	var commands: Array = []
	var incomplete := false
	for index in range(1, lines.size()):
		if cancelled.is_valid() and cancelled.call(): return {"error":"Replay loading cancelled"}
		var line := lines[index]
		if line.strip_edges() == "": continue
		var parse_error := parser.parse(line)
		if parse_error != OK and index == lines.size() - 1:
			incomplete = true
			break
		var row = parser.data if parse_error == OK else null
		if not valid_command(row) or row.get("seq") != commands.size() + 1:
			return {"error":"Invalid command at line %d" % (commands.size() + 2)}
		if not apply_delta(state, row["delta"]): return {"error":"Invalid delta at command %d" % row["seq"]}
		if verify_hashes and fingerprint(state) != row.get("hash"): return {"error":"Position hash mismatch at command %d" % row["seq"]}
		commands.append(row)
	return {"error":"", "header":header, "commands":commands, "position":decode(state), "incomplete_tail":incomplete}
