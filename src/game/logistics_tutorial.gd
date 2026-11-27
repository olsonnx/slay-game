extends RefCounted
## The experimental rules have their own short, playable teaching positions.
const Loc = preload("res://src/localization/text.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Level = preload("res://src/editor/level_document.gd")
const NONE := Vector2i(999, 999)

static func map_data(category: String, exercise := "") -> Dictionary:
	var doc := Level.new()
	doc.title = "Castles and logistics"
	doc.starting_gold = 100
	for q in range(-4, 1):
		for r in range(-1, 2):
			var cell: Dictionary = Rules.new().make_cell(0)
			cell.value = 2
			doc.cells[Vector2i(q, r)] = cell
	doc.cells[Vector2i(-4, 0)].capital = 0
	doc.cells[Vector2i(-4, 0)].mana_source = true
	doc.cells[Vector2i.ZERO].unit = 1
	for at in [Vector2i(1, 0), Vector2i(1, -1), Vector2i(1, 1)]: doc.cells[at] = Rules.new().make_cell(-1)
	for at in [Vector2i(2, 0), Vector2i(2, -1), Vector2i(3, 0)]: doc.cells[at] = Rules.new().make_cell(1)
	doc.cells[Vector2i(2, 0)].capital = 1
	if category == "magic":
		doc.cells[Vector2i(-1, 0)].building = "city"
		doc.cells[Vector2i(-1, 0)].mana_source = true
	if category == "economy":
		if exercise == "banks":
			for at in [Vector2i(4, 0), Vector2i(4, -1), Vector2i(5, -1)]:
				doc.cells[at] = Rules.new().make_cell(0)
				doc.cells[at].value = 2
			doc.cells[Vector2i(5, -1)].capital = 0
		else: doc.cells[Vector2i(-1, 0)].tree = true
	if category == "magic" and exercise == "shatter":
		doc.cells[Vector2i(1, 0)].building = "bridge"
		doc.cells[Vector2i(1, 0)].value = 0
	if category == "exploration":
		if exercise == "comet": doc.cells[Vector2i(1, 0)].event = "comet"
		else: doc.cells[Vector2i(1, 0)].treasure = 15
	if category in ["armies", "logistics"]:
		doc.cells[Vector2i(-4,0)].ore_source = true
		doc.cells[Vector2i(-4,0)].value = 6
	if category == "logistics":
		doc.cells[Vector2i(-3,0)].ore_source = true
		doc.cells[Vector2i(-3,0)].value = 6
	doc.player_start = Vector2i(-4, 0)
	if category == "logistics":
		for q in range(1, 6):
			for r in range(-1, 2):
				doc.cells[Vector2i(q, r)] = Rules.new().make_cell(0)
				doc.cells[Vector2i(q, r)].value = 2
		doc.cells[Vector2i.ZERO].unit = 0
		doc.cells[Vector2i(1, 1)].building = "tower"
		for at in [Vector2i(7, 0), Vector2i(8, 0)]: doc.cells[at] = Rules.new().make_cell(1)
		doc.cells[Vector2i(8, 0)].capital = 1
	return doc.state()

static func step(id: String, task: String, text: String, kind: String, target := NONE, details: Dictionary = {}) -> Dictionary:
	return {"id":id, "title":Loc.text("Castles and logistics"), "task":task, "text":text, "kind":kind, "target":target, "details":details, "exercise":"logistics"}

static func sequence(category: String, exercise: String, goals: Array) -> Array:
	for goal in goals: goal.exercise = exercise
	goals[0]["setup"] = map_data(category, exercise)
	return goals

static func reading(id: String, task: String, text: String, kind := "finance", target := NONE) -> Dictionary:
	var goal := step(id, task, text, kind, target)
	goal["confirm"] = true
	return goal

static func steps(category: String) -> Array:
	var result: Array
	match category:
		"construction": result = [
			step("first_tower", Loc.text("Build your first tower"), Loc.text("Open Build at the bottom left, choose Tower, then click the gold-ringed tile. It costs 15 G to build and 2 G per turn. Its tier-one strength-1 protection covers itself and neighboring friendly land, not neutral or enemy land. Towers cannot be dismantled."), "build", Vector2i(-2, 1), {"building":"tower"}),
			step("second_tower", Loc.text("Build a second tower"), Loc.text("Your next Tower costs 20 G. Each tower you control adds 5 G to the next one's price across all your kingdoms. Every tower still costs 2 G per turn."), "build", Vector2i(-3, 1), {"building":"tower"}),
			step("first_bridge", Loc.text("Build a bridge"), Loc.text("Choose Bridge in Build and place it on the marked water tile. Each segment costs 15 G plus 2 G per turn from its builder's treasury. Bridges are neutral crossings, so opponents can use them too."), "build", Vector2i(-1, 2), {"building":"bridge"}),
			step("second_bridge", Loc.text("Build another bridge segment"), Loc.text("Choose Bridge again and click the gold-ringed water tile. This segment also costs 15 G and 2 G per turn: bridge prices stay flat. The builder pays its upkeep even when an opponent uses the crossing."), "build", Vector2i(-2, 2), {"building":"bridge"}),
			step("bridge_mana", Loc.text("Prepare Shatter"), Loc.text("Bridges cannot be dismantled. End your turn to reach 2 mana for Shatter, the only way to remove a bridge. Roads and towers cannot be dismantled either."), "end_turn"),
			step("remove_bridge", Loc.text("Shatter the bridge"), Loc.text("Open Spells, choose Shatter, then click the gold-ringed bridge. Shatter costs 2 mana and removes the crossing without refunding its construction cost. Removing this segment stops its 2 G upkeep. Any unit on a shattered bridge is lost too."), "spell", Vector2i(-2, 2), {"spell":"shatter"}),
			reading("infrastructure_forecast", Loc.text("Check infrastructure upkeep"), Loc.text("Hover over gold in the bottom-left dock. The forecast now includes two towers and one bridge, plus your Scout's wages. Roads have no upkeep. Read the income, upkeep and net change, then click Continue."))]
		"logistics": result = [
			step("forward_city", Loc.text("Build a forward castle"), Loc.text("Choose Castle in Build, then the marked province. A castle costs 25 G and adds no income. Tier one recruits only on its own tile; upgrade to tier two for neighboring owned land. Captured castles survive and serve their new owner."), "build", Vector2i(3, 0), {"building":"city"}),
			step("ore_income", Loc.text("Collect Ore"), Loc.text("End turn to collect Ore from your sources. Each source gives 1 Ore per 3 development; storage is unlimited."), "end_turn"),
			step("upgrade_castle", Loc.text("Upgrade your Castle"), Loc.text("Inspect the marked Castle and upgrade to tier 2 for 2 Ore. It can now recruit on neighboring owned tiles."), "upgrade_building", Vector2i(3,0)),
			step("name_city", Loc.text("Give your castle a name"), Loc.text("Click the marked castle to open its details, then click its title and type a name. Press Enter or click away to save. Capitals can be named the same way; keyboard shortcuts and camera panning pause while you type."), "rename_settlement", Vector2i(3, 0)),
			step("rear_knight", Loc.text("Recruit beside your capital"), Loc.text("Choose Knight in Recruit. The green area marks legal recruitment and upgrade tiles. Recruit on the marked tile next to your capital. New recruits can move immediately; Knights normally move 3 hexes."), "recruit", Vector2i(-3, 0), {"tier":3}),
			step("supply_road", Loc.text("Connect your capital and castle"), Loc.text("Click the blue-ringed capital to open its details, then press the road icon. Hover over the gold-ringed castle to see the route and total cost; click to build. New pavement costs 1 G per tile, including the endpoints. Existing pavement is free. Roads cannot be removed."), "road", Vector2i(3, 0), {"source":Vector2i(-4, 0)}),
			step("road_march", Loc.text("March six hexes along the road"), Loc.text("Select your new Knight beside the capital and move it to the marked castle. Connected friendly road steps cost half a movement point, so this six-hex march fits the Knight's range of 3. Bridges and attacks still cost a full point."), "move", Vector2i(3, 0), {"source":Vector2i(-3, 0)}),
			step("forward_recruit", Loc.text("Recruit beside the forward castle"), Loc.text("Choose Scout and use the marked tile beside your castle. The recruitment area has expanded to this front. Castles provide a place to deploy, not extra income; development pays for your armies."), "recruit", Vector2i(4, 0), {"tier":1}),
			step("fresh_march", Loc.text("Move the fresh Scout"), Loc.text("Move the Scout you just recruited to the marked province. You do not need to end the turn first. Scouts move 5 hexes, Soldiers 4, and Knights 3; a normal move order spends the unit's action."), "move", Vector2i(5, 0), {"source":Vector2i(4, 0)}),
			step("road_junction", Loc.text("Connect a tower to the road"), Loc.text("Click the blue-ringed tower and press the road icon in its details. Hover over the gold-ringed road tile, check the cost, then click. A road starts at a friendly structure and ends at a friendly structure or existing road tile. Empty unpaved land is not an endpoint."), "road", Vector2i.ZERO, {"source":Vector2i(1, 1)})]
		"economy":
			result = sequence(category, "income", [
				reading("forecast_before", Loc.text("Read your treasury forecast"), Loc.text("Hover over gold in the bottom-left dock. Treasury is money you can spend now; income minus upkeep is next turn's net change. Your forest tile currently earns nothing. Read the forecast, then click Continue.")),
				step("inspect", Loc.text("Inspect a province"), Loc.text("Click the gold-ringed empty province to open its details. Its value is the gold it earns each turn while clear. Castles add recruitment sites, not an income bonus."), "inspect", Vector2i(-2, 0)),
				step("develop", Loc.text("Develop the province"), Loc.text("Click Develop in this province's details. Raising its value from 2 to 3 costs 8 G and adds 1 G to its income each turn. Further development costs more. The cost comes from this province's local treasury."), "develop", Vector2i(-2, 0)),
				step("clear_forest", Loc.text("Clear the forest"), Loc.text("Click the blue-ringed Scout, then the gold-ringed forest. Entering clears the tree, pays 1 G immediately, and restores this value-2 tile's 2 G income. Trees and graves block tile income; trees only grow on empty ground."), "move", Vector2i(-1, 0), {"source":Vector2i.ZERO}),
				reading("finance", Loc.text("Compare the new forecast"), Loc.text("Hover over gold again. Development added 1 G income and clearing the forest restored 2 G, so income is now 3 G higher. Upkeep is unchanged. Read the forecast and click Continue; the next exercise demonstrates separate treasuries."))])
			result.append_array(sequence(category, "banks", [
				reading("separate_bank", Loc.text("Select the other kingdom"), Loc.text("This new position has two disconnected friendly kingdoms. Click the gold-ringed province to select the right-hand treasury and open its details. Each kingdom keeps its own gold. Read the panel, then click Continue."), "inspect", Vector2i(4, -1)),
				step("develop_other_bank", Loc.text("Spend from the right-hand treasury"), Loc.text("Use Develop on this province. Its local treasury pays the 8 G cost; the disconnected kingdom on the left keeps all its gold. The two kingdoms share a color, not a treasury."), "develop", Vector2i(4, -1)),
				reading("bank_forecast", Loc.text("Read the selected kingdom's budget"), Loc.text("Hover over gold. This is the right-hand kingdom's remaining gold and forecast, not a faction-wide total. Selecting land in another connected kingdom changes the treasury you use. Click Continue when ready."))]))
		"magic":
			result = sequence(category, "summoning", [
				step("mana", Loc.text("End turn to gain mana"), Loc.text("The mana display is beside gold. You start with 1 mana; click End turn to gain another and afford Summon's 2-mana cost. Mana is shared by your faction, while mana sources increase its storage capacity."), "end_turn"),
				step("summon", Loc.text("Summon a Scout at the castle"), Loc.text("Open Spells, choose Summon, then click the gold-ringed castle. The green area shows its legal empty recruitment tiles on or beside castles and capitals. Summon costs 2 mana; the new Scout has normal upkeep and is ready immediately."), "spell", Vector2i(-1, 0), {"spell":"summon"}),
				step("march", Loc.text("Move the summoned Scout"), Loc.text("Click the blue-ringed summoned Scout, then the gold-ringed friendly tile. No End turn is needed first. Summon uses the same deployment area and readiness rules as paid recruits."), "move", Vector2i(-2, 1), {"source":Vector2i(-1, 0)})])
			result.append_array(sequence(category, "trailblaze", [
				step("bless", Loc.text("Prepare Trailblaze"), Loc.text("In this new position, open Spells and choose Trailblaze. Click the gold-ringed friendly tile to spend 1 mana. The blessing applies to the next unit you move, not only the unit on the spell's tile. Any valid move consumes it."), "spell", Vector2i.ZERO, {"spell":"trailblaze"}),
				step("trail_capture", Loc.text("Capture with the blessed Scout"), Loc.text("Click the blue-ringed Scout, then the gold-ringed neutral tile. Because this next move captures neutral land, Trailblaze leaves the Scout ready for another move."), "move", Vector2i(1, 0), {"source":Vector2i.ZERO}),
				step("trail_followup", Loc.text("Use the extra move"), Loc.text("Move that Scout from the blue ring to the gold-ringed neutral tile. This is a second capture in the same turn. Trailblaze was consumed by the first move, so the Scout is spent after this one."), "move", Vector2i(1, 1), {"source":Vector2i(1, 0)})]))
			result.append_array(sequence(category, "shatter", [
				step("shatter_mana", Loc.text("Prepare to destroy a crossing"), Loc.text("This new position has an empty neutral bridge beside your land. Click End turn to reach 2 mana. Shatter can remove an adjacent neutral structure, including a bridge; any unit on a destroyed bridge is lost too."), "end_turn"),
				step("shatter_bridge", Loc.text("Shatter the empty bridge"), Loc.text("Open Spells, choose Shatter, then click the gold-ringed bridge. The spell costs 2 mana and removes the crossing completely. It does not return construction gold."), "spell", Vector2i(1, 0), {"spell":"shatter"})]))
		"exploration":
			result = sequence(category, "treasure", [
				step("treasure", Loc.text("Collect the treasure chest"), Loc.text("Click the blue-ringed Scout, then the gold-ringed chest on neutral land. Capturing its tile collects 15 G immediately into the Scout's treasury. The chest disappears: this is a one-time reward, not recurring income."), "move", Vector2i(1, 0), {"source":Vector2i.ZERO}),
				reading("treasure_budget", Loc.text("Check the one-time reward"), Loc.text("Hover over gold. The chest added 15 G to stored money immediately; capturing its value-1 tile also added 1 G recurring income. Click Continue after reading the forecast to try an encounter on a new board."))])
			result.append_array(sequence(category, "comet", [
				step("encounter", Loc.text("Explore the marked encounter"), Loc.text("In this new position, click the blue-ringed Scout, then the gold-ringed encounter tile. Capturing it opens an event panel. Other encounters may require a particular unit or other conditions."), "move", Vector2i(1, 0), {"source":Vector2i.ZERO}),
				step("choice", Loc.text("Choose either Comet reward"), Loc.text("Choose either option in the event panel. The landmark adds 1 or 2 G per turn while you control it. Volunteers appear on or beside an available castle or capital, not necessarily on this encounter tile; they are ready immediately and have normal upkeep."), "event"),
				step("review_reward", Loc.text("Review your reward"), Loc.text("Your choice is now on the map: either a lasting income landmark on the captured tile or a new Scout near a recruitment hub. You may inspect provinces and the gold forecast. Click Continue when you are ready to finish."), "continue")]))
		_: result = [
			step("expand", Loc.text("Capture a neutral province"), Loc.text("Click the blue-ringed Scout, then the gold-ringed neutral tile. It becomes yours. Scouts move 5 hexes, Soldiers 4, and Knights 3; a capture spends the action. Right-click cancels a selection. The guided opponents wait; Your first match uses active AI."), "move", Vector2i(1, 0), {"source":Vector2i.ZERO}),
			step("recruit", Loc.text("Recruit at your capital"), Loc.text("Open Recruit at the bottom left, choose Scout, then click the gold-ringed capital. The green area shows legal deployment and upgrade tiles on or beside castles and capitals. Your new Scout is ready immediately."), "recruit", Vector2i(-4, 0), {"tier":1}),
			step("march", Loc.text("Move the new Scout forward"), Loc.text("Select your fresh Scout and move it to the marked friendly province. An ordinary move spends its action even if it uses only part of its 5-hex range."), "move", Vector2i(-3, 0), {"source":Vector2i(-4, 0)}),
			step("second_scout", Loc.text("Recruit another Scout"), Loc.text("Recruit a second Scout on your capital. Two equal-tier Scouts can merge into a Soldier, and two Soldiers into a Knight. Different tiers and Knights cannot merge."), "recruit", Vector2i(-4, 0), {"tier":1}),
			step("merge_scouts", Loc.text("Merge your two Scouts"), Loc.text("Move the Scout on your capital onto the marked Scout. Merging works within movement range, including road discounts. The result keeps the destination unit's spent or ready action; it does not grant an extra move."), "move", Vector2i(-3, 0), {"source":Vector2i(-4, 0), "outcome":"merge"}),
			step("army_ore", Loc.text("Collect Ore for the Knight"), Loc.text("End turn to collect Ore from your controlled deposit. A Knight costs 2 Ore once, in addition to gold."), "end_turn"),
			step("upgrade_soldier", Loc.text("Upgrade the Soldier to Knight"), Loc.text("Choose Knight in Recruit and click the marked Soldier beside your capital. Paid upgrades use the same recruitment area and charge the difference in purchase price. An upgrade never restores a spent action."), "recruit", Vector2i(-3, 0), {"tier":3}),
			step("refresh_army", Loc.text("End turn to ready the Knight"), Loc.text("End your turn to settle army wages and refresh all units. Your treasuries pay for armies and infrastructure, while controlled Ore deposits add to your shared reserve."), "end_turn"),
			step("knight_march", Loc.text("Move the Knight three hexes"), Loc.text("Move the Knight to the marked friendly province. Knights have the shortest range at 3, Soldiers move 4, and Scouts move 5. Use castles and roads to get slower armies to the right front."), "move", Vector2i.ZERO, {"source":Vector2i(-3, 0)})]
	if not result[0].has("setup"): result[0]["setup"] = map_data(category)
	return result
