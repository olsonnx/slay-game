extends RefCounted
## Explicit isolated sources let combat fixtures fund spells within the real cap,
## without adding income, changing local kingdom topology or bypassing validation.
static func fund_mana(rules, faction: int, amount: int) -> void:
	if not rules.is_modern():
		return
	var needed: int = maxi(0, amount - rules.mana_capacity(faction))
	for index in range(needed):
		var coord := Vector2i(30 + faction * 200 + index * 3, 30)
		while rules.cells.has(coord):
			coord.x += 3
		rules.cells[coord] = rules.make_cell(faction)
		rules.cells[coord]["mana_source"] = true
	rules.set_mana(faction, amount)
