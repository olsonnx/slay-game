extends RefCounted
## One authoritative rules path for authored opponent orders and offline previews.
static func apply(rules, order: Dictionary, faction: int) -> Dictionary:
	var target: Vector2i = order.get("target",rules.NONE)
	var ok := false
	var moves: Array = []
	match order.get("kind",""):
		"move":
			var source: Vector2i = order.get("source",rules.NONE)
			if not rules.cells.has(source) or rules.unit_faction(source) != faction: return {"ok":false,"moves":[]}
			var record: Dictionary = rules.perform_move(source,target)
			ok = not record.is_empty()
			if ok:
				moves.append(record)
				if order.has("outcome"): ok = record.kind == order.outcome
		"recruit": ok = rules.recruit(target,faction,int(order.get("tier",1)))
		"build": ok = rules.build_structure(target,faction,order.get("building","house"))
		"spell": ok = rules.cast_spell(order.get("spell","trailblaze"),target,faction)
		"entrench": ok = rules.entrench(target,faction)
		"develop": ok = rules.develop(target,faction)
		"relocate_capital": ok = rules.relocate_capital(target,faction)
		"event":
			if not rules.pending_events.is_empty(): ok = rules.resolve_event(rules.pending_events[0],int(order.get("choice",0))) != ""
		"any": return {"ok":false,"moves":[]}
		"continue","select","inspect","view","heatmap","stats","finance","status","kingdom","animal": ok = true
	return {"ok":ok,"moves":moves}
