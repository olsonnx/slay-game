extends RefCounted
## Account progression uses completed match settings, never time spent idling.
const DIFFICULTY := {"easy":0.75, "normal":1.0, "hard":1.4}
const MAP_SIZE := {"very_small":0.8, "small":1.0, "medium":1.25, "large":1.6, "very_large":2.0, "huge":2.5}
const OUTCOME := {"victory":1.5, "defeat":0.75, "draw":1.0}

static func threshold(level: int) -> int:
	var steps := maxi(0, level - 1)
	return 250 * steps + 50 * steps * (steps - 1)

static func progress(total_xp: int) -> Dictionary:
	total_xp = maxi(0, total_xp)
	var level := maxi(1, int(floor((sqrt(40000.0 + 200.0 * total_xp) - 200.0) / 100.0)) + 1)
	return {"level":level, "current":total_xp - threshold(level), "needed":250 + 100 * (level - 1), "total":total_xp}

static func reward(result: String, settings: Dictionary = {}) -> int:
	if result not in OUTCOME: return 0
	var difficulty: float = DIFFICULTY.get(settings.get("difficulty", "normal"), 1.0)
	var slots: Array = settings.get("slots", [])
	if not slots.is_empty():
		var weight := 0.0
		var opponents := 0
		for index in range(slots.size()):
			if index == settings.get("owner", 0): continue
			var seat: Dictionary = slots[index]
			weight += DIFFICULTY.get(seat.get("difficulty", "normal"), 1.0) if seat.get("controller") == "ai" else 1.0
			opponents += 1
		if opponents > 0: difficulty = weight / opponents
	var size_multiplier: float = MAP_SIZE.get(settings.get("size", "small"), 1.0)
	var count := clampi(int(settings.get("opponents", 3)), 1, 5)
	return maxi(1, roundi(100.0 * OUTCOME[result] * difficulty * size_multiplier * (1.0 + 0.1 * (count - 1))))
