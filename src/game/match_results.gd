extends RefCounted
## Inspect only recorded changes, once at completion. No extra per-move work.
static func unit_owner(cell: Dictionary) -> int:
	if cell.get("unit", 0) == 0: return -1
	return cell.get("unit_owner", -1) if cell.get("building", "") == "bridge" else cell.get("owner", -1)

static func summarize(replay) -> Dictionary:
	var totals := {}
	for faction in range(replay.header.get("factions", 0)):
		totals[faction] = {"slain":0, "lost":0, "tiles":0, "capitals":0}
	var cells: Dictionary = replay.header.get("initial", {}).get("cells", {}).duplicate()
	for row in replay.rows:
		var patch: Dictionary = row["delta"].get("cells", {})
		var updated: Dictionary = patch.get("set", {})
		var changed: Array = updated.keys()
		changed.append_array(patch.get("erase", []))
		var unit_balance := {}
		var actor: int = row["faction"]
		var action: String = row["action"]
		var gameplay: bool = action in ["move", "spell", "event_choice", "turn_start", "build", "develop", "recruit", "entrench"]
		for coord in changed:
			var before: Dictionary = cells.get(coord, {})
			var after: Dictionary = updated.get(coord, {})
			var old_unit := unit_owner(before)
			var new_unit := unit_owner(after)
			if old_unit >= 0: unit_balance[old_unit] = unit_balance.get(old_unit, 0) - 1
			if new_unit >= 0: unit_balance[new_unit] = unit_balance.get(new_unit, 0) + 1
			if gameplay and totals.has(actor) and after.get("owner", -1) == actor and before.get("owner", -1) != actor and after.get("building", "") != "bridge":
				totals[actor]["tiles"] += 1
				if before.get("capital", -1) >= 0: totals[actor]["capitals"] += 1
			if after.is_empty(): cells.erase(coord)
			else: cells[coord] = after
		# Merging consumes one friendly unit without a casualty; upgrades and
		# recruitment do not reduce the number of living units.
		if action == "move" and row["args"].get("outcome") == "merge":
			unit_balance[actor] = unit_balance.get(actor, 0) + 1
		if not gameplay: continue
		for faction in unit_balance:
			var deaths: int = maxi(0, -unit_balance[faction])
			if not totals.has(faction): continue
			totals[faction]["lost"] += deaths
			if faction != actor and totals.has(actor) and action in ["move", "spell", "event_choice"]:
				totals[actor]["slain"] += deaths
			if faction == actor and action == "move" and row["args"].get("outcome") == "knight_duel":
				for defender in unit_balance:
					if defender != actor and unit_balance[defender] < 0 and totals.has(defender):
						totals[defender]["slain"] += deaths
	return totals
