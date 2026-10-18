extends RefCounted
## Worker-owned rules; no scene nodes or renderer access from this job.
var rules = preload("res://src/game/kingdom_rules.gd").new()
var generation_ms := 0.0

func generate(seed_value: int, size_id: String, mode: String, kingdom_count := 0) -> void:
	rules.rule_mode = mode
	var started := Time.get_ticks_usec()
	rules.generate(seed_value, size_id, kingdom_count)
	generation_ms = (Time.get_ticks_usec() - started) / 1000.0
