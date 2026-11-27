extends RefCounted
## Schema for authoritative state. UI selection and recorder ownership stay outside it.
## Replay fields are append-only; faction count is positional because encounters can spawn kingdoms.
const VERSION := 1
const POSITION_FIELDS := {
	"cells": "cells", "kingdoms": "kingdoms", "mana": "mana_by_faction",
	"effects": "effects_by_faction", "capital_relocations": "capital_relocations",
	"events": "pending_events", "rng": "rng", "difficulty": "ai_difficulty", "faction_count": "faction_count", "ore": "ore_by_faction"
}
const CONFIGURATION := ["human_factions", "faction_names", "rule_mode", "map_size",
	"level_seed", "faction_count", "initial_kingdom_count", "ai_algorithm",
	"incremental_kingdoms", "ai_revision"]
const PRESENTATION := ["faction_names", "rule_mode", "map_size", "faction_count", "capital_relocations", "effects_by_faction"]

static func owned(value):
	return value.duplicate(true) if value is Dictionary or value is Array else value

static func replay_position(model, copy_records := true) -> Dictionary:
	var result := {}
	for key in POSITION_FIELDS:
		var value = str(model.rng.state) if key == "rng" else model.get(POSITION_FIELDS[key])
		result[key] = owned(value) if copy_records else value
	return result

static func capture(model) -> Dictionary:
	var result := replay_position(model)
	result["snapshot_version"] = VERSION
	result["configuration"] = {}
	for field in CONFIGURATION:
		result["configuration"][field] = owned(model.get(field))
	result["ai_last_decision"] = owned(model.ai_last_decision)
	return result

static func restore(model, snapshot: Dictionary) -> void:
	assert(snapshot.get("snapshot_version") == VERSION, "Unsupported internal snapshot schema")
	for key in POSITION_FIELDS:
		if key == "rng": model.rng.state = int(snapshot[key])
		else: model.set(POSITION_FIELDS[key], owned(snapshot[key]))
	for field in CONFIGURATION:
		model.set(field, owned(snapshot["configuration"][field]))
	model.ai_last_decision = owned(snapshot["ai_last_decision"])

static func simulation(model):
	var copy = model.get_script().new()
	for field in CONFIGURATION:
		copy.set(field, owned(model.get(field)))
	copy.ai_difficulty = model.ai_difficulty
	# Scalar cell records use a shallow per-record copy in this hot path. Events
	# are deliberately hidden; pending encounters, telemetry and recorder stay fresh.
	for coord in model.cells:
		var cell: Dictionary = model.cells[coord].duplicate()
		cell["event"] = ""
		copy.cells[coord] = cell
	for key in ["kingdoms", "mana", "ore", "effects", "capital_relocations"]:
		copy.set(POSITION_FIELDS[key], owned(model.get(POSITION_FIELDS[key])))
	copy.rng.seed = 0
	return copy

static func presentation_metadata(source, destination) -> void:
	for field in PRESENTATION:
		destination.set(field, owned(source.get(field)))

static func analysis_view(model):
	# A synchronous read-only planner can borrow worker-owned records. Mutation
	# resumes only after planning ends; legacy branch simulations still copy fully.
	var copy = model.get_script().new()
	for field in CONFIGURATION: copy.set(field, owned(model.get(field)))
	copy.ai_difficulty = model.ai_difficulty
	copy.cells = model.cells.duplicate()
	for coord in copy.cells:
		if copy.cells[coord].get("event", "") != "":
			copy.cells[coord] = copy.cells[coord].duplicate()
			copy.cells[coord]["event"] = ""
	for key in ["kingdoms", "mana", "ore", "effects", "capital_relocations"]:
		copy.set(POSITION_FIELDS[key], model.get(POSITION_FIELDS[key]))
	copy.rng.seed = 0
	return copy

static func worker_input(model) -> Dictionary:
	# Read-only lease: callers lock commands and await the worker before publishing.
	# Indexes belong to the packet; records are only read until copied on the worker.
	var packet := {"script":model.get_script(), "configuration":{}, "position":{}, "ai_last_decision":owned(model.ai_last_decision)}
	for field in CONFIGURATION: packet["configuration"][field] = owned(model.get(field))
	for key in POSITION_FIELDS:
		var value = str(model.rng.state) if key == "rng" else model.get(POSITION_FIELDS[key])
		packet["position"][key] = value.duplicate() if value is Dictionary or value is Array else value
	return packet

static func update_worker(model, packet: Dictionary) -> void:
	# Keep the worker's unchanged private records, copying only incoming changes.
	for key in POSITION_FIELDS:
		var incoming = packet["position"][key]
		if key == "rng": model.rng.state = int(incoming)
		elif incoming is Dictionary:
			var current: Dictionary = model.get(POSITION_FIELDS[key])
			var ordered := {}
			for coord in incoming:
				ordered[coord] = current[coord] if current.has(coord) and current[coord] == incoming[coord] else owned(incoming[coord])
			model.set(POSITION_FIELDS[key], ordered)
		else: model.set(POSITION_FIELDS[key], owned(incoming))
	for field in CONFIGURATION: model.set(field, owned(packet["configuration"][field]))
	model.ai_last_decision = owned(packet["ai_last_decision"])

static func worker_result(model, packet: Dictionary) -> Dictionary:
	var result := {"cells":{}, "removed":[], "fields":{}, "ai_revision":model.ai_revision, "ai_last_decision":owned(model.ai_last_decision)}
	var before: Dictionary = packet["position"]["cells"]
	for coord in model.cells:
		if not before.has(coord) or before[coord] != model.cells[coord]: result["cells"][coord] = owned(model.cells[coord])
	for coord in before:
		if not model.cells.has(coord): result["removed"].append(coord)
	for key in POSITION_FIELDS:
		if key == "cells": continue
		var value = str(model.rng.state) if key == "rng" else model.get(POSITION_FIELDS[key])
		if value != packet["position"][key]: result["fields"][key] = owned(value)
	return result

static func publish_worker(model, result: Dictionary) -> void:
	# Ownership of the prepared patch passes to the main thread. Worker state and
	# replay rows own separate records, so later computation cannot alter playback.
	for coord in result["removed"]: model.cells.erase(coord)
	for coord in result["cells"]: model.cells[coord] = result["cells"][coord]
	for key in result["fields"]:
		if key == "rng": model.rng.state = int(result["fields"][key])
		else: model.set(POSITION_FIELDS[key], result["fields"][key])
	model.ai_revision = result["ai_revision"]
	model.ai_last_decision = result["ai_last_decision"]
