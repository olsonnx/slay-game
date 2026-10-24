extends RefCounted
## Subject-based exercises. Only the final practice is a complete AI match.
const Loc = preload("res://src/localization/text.gd")
const Scenarios = preload("res://src/game/tutorial_scenarios.gd")
const Document = preload("res://src/tutorial_editor/tutorial_document.gd")
const NONE := Vector2i(999,999)
const IDS := ["armies","economy","construction","conquest","magic","exploration","practice"]

static func categories() -> Array:
	var result := [
		{"id":"armies","title":Loc.text("Armies and expansion"),"description":Loc.text("Recruit, move, claim neutral land and learn every rank.")},
		{"id":"economy","title":Loc.text("Kingdoms and money"),"description":Loc.text("Understand income, wages and separate treasuries.")},
		{"id":"construction","title":Loc.text("Buildings and development"),"description":Loc.text("Learn what to build, where, and when it pays off.")},
		{"id":"conquest","title":Loc.text("Taking enemy territory"),"description":Loc.text("Find weak borders, cut connections and take capitals.")},
		{"id":"magic","title":Loc.text("Mana and spells"),"description":Loc.text("Use sources and all three spells with a purpose.")},
		{"id":"exploration","title":Loc.text("Exploration and rewards"),"description":Loc.text("Choose encounters, collect treasure and hunt lairs.")},
		{"id":"practice","title":Loc.text("Your first match"),"description":Loc.text("Play a small real match. Choose your own strategy.")},
	]
	for course in result:
		var document = installed(course.id)
		if document != null and document.data.get("description","") != "": course.description = document.data.description
	return result

static func category_title(category: String) -> String:
	return categories()[IDS.find(category) if category in IDS else 0].title

static func installed(category: String, folder := "res://tutorials"):
	if category not in IDS: return null
	var filename: String = folder + "/%s.json" % category
	if not FileAccess.file_exists(filename): return null
	var document := Document.new()
	var error := document.load_file(filename)
	if error != "":
		push_warning("Tutorial override ignored: " + error)
		return null
	return document

static func map_data(category := "armies") -> Dictionary:
	if category not in IDS: category = "armies"
	var document = installed(category)
	if document != null: return document.level_data()
	var data := Scenarios.map_data(category)
	data.merge({"tutorial":true,"tutorial_category":category,"tutorial_title":category_title(category),"tutorial_steps":builtin_lessons(category),"tutorial_require_victory":category == "practice","tutorial_opponent_mode":"ai" if category == "practice" else "scripted"})
	return data

static func lessons(category := "armies") -> Array:
	var document = installed(category)
	return document.runtime_steps() if document != null else builtin_lessons(category)

static func goal(id: String, task: String, text: String, kind: String, target := NONE, details: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	return {"id":id,"title":task,"task":task,"text":text,"kind":kind,"target":target,"details":details}.merged(options)

static func exercise(title: String, setup: String, goals: Array) -> Array:
	for step in goals:
		step["exercise"] = setup
		step["title"] = title
	goals[0]["setup"] = Scenarios.position(setup)
	return goals

static func builtin_lessons(category := "armies") -> Array:
	match category:
		"economy": return economy()
		"construction": return construction()
		"conquest": return conquest()
		"magic": return magic()
		"exploration": return exploration()
		"practice": return [goal("win",Loc.text("Defeat the enemy kingdom"),Loc.text("This is a normal small match against an Easy opponent: one Scout, 10 gold, and no prescribed moves. Expand into neutral land, fund the units you need, and take the enemy capital. Buildings and magic are tools, not compulsory purchases. Retry restarts this practice position."),"any",NONE,{}, {"exercise":"practice","restrict_actions":false,"conditions":[{"type":"victory","faction":-1}]})]
		_: return armies()

static func armies() -> Array:
	return exercise(Loc.text("Claim unowned land"),"opening",[
		goal("select",Loc.text("Select your starting Scout"),Loc.text("You command Fern, the green kingdom. Click your Scout. Highlighted destinations show where it can go through connected friendly land. Scroll to zoom; Controls explains camera movement."),"select",NONE,{}, {"criteria":{"unit":1}}),
		goal("neutral",Loc.text("Capture an empty neutral province"),Loc.text("Neutral land belongs to nobody. Click a highlighted empty neutral province. Claiming it adds recurring income; the income arrives next turn, rather than immediately."),"move",NONE,{}, {"criteria":{"owner_before":-1,"plain":true}}),
		goal("finances",Loc.text("Hover over your gold, bottom left"),Loc.text("Hover over your gold in the bottom-left dock. The tooltip separates treasury, income, army upkeep and net income. Your new province improved the forecast. This is where to check whether another army is affordable."),"finance"),
		goal("recruit",Loc.text("Recruit a second Scout"),Loc.text("Open Recruit, choose Scout, then click clear friendly land. It costs 10 gold now and 4 per turn. New armies are ready immediately, so this Scout can expand while the first rests."),"recruit",NONE,{"tier":1}),
		goal("expand",Loc.text("Capture one more neutral province"),Loc.text("Select the new Scout and capture another empty neutral province. Each army normally gets one action per turn; both Scouts will then have acted."),"move",NONE,{}, {"criteria":{"owner_before":-1,"plain":true}}),
		goal("ready_scouts",Loc.text("End turn to ready both Scouts"),Loc.text("Both Scouts have acted. Click End turn at the bottom right. Your kingdom collects income, pays wages, and your armies become ready again."),"end_turn"),
		goal("expand_again",Loc.text("Capture a third neutral province"),Loc.text("Select either ready Scout and capture another empty neutral province. Keep alternating useful captures with End turn when your armies are spent. Hover over gold whenever you need to check the resulting budget."),"move",NONE,{}, {"criteria":{"owner_before":-1,"plain":true}}),
	]) + exercise(Loc.text("Choose the right rank"),"ranks",[
		goal("soldier",Loc.text("Upgrade your Scout to a Soldier"),Loc.text("Scouts have strength 1 and cannot defeat another Scout. Choose Soldier in Recruit, then click your Scout. Pay the 10-gold difference for strength 2 and wages of 12 per turn."),"recruit",NONE,{"tier":2},{"criteria":{"unit_before":1}}),
		goal("soldier_attack",Loc.text("Defeat the enemy Scout"),Loc.text("Select your Soldier and attack the marked Scout. An attack normally needs higher strength than the province's defense. Armies lend up to strength 2 to adjacent land of the same owner; they do not protect enemy or neutral land."),"move",Vector2i(0,-1),{}, {"criteria":{"source_tier":2}}),
		goal("knight",Loc.text("Upgrade the Soldier to a Knight"),Loc.text("Choose Knight and click your Soldier. Upgrading costs 20 gold and raises wages to 36 per turn. You can upgrade after acting, but its action stays spent. Knights have strength 3 for Soldiers and Towers."),"recruit",NONE,{"tier":3},{"criteria":{"unit_before":2}}),
		goal("ready_knight",Loc.text("End turn before attacking again"),Loc.text("The upgrade did not give your army another action. Click End turn to ready the Knight before its next attack."),"end_turn"),
		goal("knight_attack",Loc.text("Defeat the enemy Soldier"),Loc.text("Your Knight is ready. Select it and attack the marked Soldier. A Soldier cannot beat defense 2; a Knight can. Use the least expensive rank that can do the job."),"move",Vector2i(0,1),{}, {"criteria":{"source_tier":3}}),
		goal("ready_tower_attack",Loc.text("End turn to ready the Knight"),Loc.text("The Soldier is defeated, but your Knight has spent its action. End turn before attacking the nearby Tower."),"end_turn"),
		goal("destroy_tower",Loc.text("Destroy the enemy Tower"),Loc.text("Attack the marked Tower with your Knight. Its strength-2 defense cannot stop strength 3. Directly capturing a Tower's province destroys the building; later you will learn how surrender can keep one intact."),"move",Vector2i(1,0),{}, {"criteria":{"source_tier":3}}),
	]) + exercise(Loc.text("Merge and protect armies"),"merge",[
		goal("merge",Loc.text("Merge the two Scouts"),Loc.text("The enemy Knight threatens the forward Scout. Move your rear Scout onto it to merge into a ready Soldier. Merging costs no gold, but wages rise from 8 for two Scouts to 12 for the Soldier."),"move",Vector2i(-2,-1),{"source":Vector2i(-3,0),"outcome":"merge"}),
		goal("entrench",Loc.text("Entrench the threatened Soldier"),Loc.text("The enemy Knight can still defeat a Soldier. Click the Soldier's ground and choose Entrench. This spends the action to absorb one attack on this province. It can buy time when a stronger army threatens a position you need to hold."),"entrench",Vector2i(-2,-1)),
		goal("entrench_turn",Loc.text("End turn and withstand the Knight"),Loc.text("End turn. The Knight will attack your entrenched Soldier. Watch the shield absorb the blow: your Soldier and province survive. One shield stops one attack; a second attacker could break through."),"end_turn",NONE,{}, {"opponent":[{"kind":"move","source":Vector2i(-1,-1),"target":Vector2i(-2,-1),"outcome":"blocked_attack"}]}),
		goal("held",Loc.text("Continue after the defended attack"),Loc.text("Your Soldier survived a stronger attacker and is ready again. The Knight spent its action, and the shield is gone. Entrenchment buys a turn; it does not make the army permanently stronger."),"continue"),
	]) + exercise(Loc.text("Equal Knights trade lives"),"duel",[
		goal("duel",Loc.text("Attack the enemy Knight"),Loc.text("Two Knights are the exception to the higher-strength rule: they can attack each other, but both die and the target's ownership stays unchanged. Try the exchange here before risking an expensive army in a match."),"move",Vector2i(0,0),{"source":Vector2i(-3,0),"outcome":"knight_duel"}),
		goal("duel_result",Loc.text("Continue after the exchange"),Loc.text("Both Knights died, but the province is still enemy land. Killing an equal Knight did not capture it. A follow-up army would need its own attack to claim the opening."),"continue"),
	])

static func economy() -> Array:
	return exercise(Loc.text("Read your next turn"),"budget",[
		goal("budget",Loc.text("Hover over your gold, bottom left"),Loc.text("Hover over gold to see this kingdom's treasury, income, upkeep and net income. Income minus wages settles at the start of your turn. A negative forecast spends savings; it does not automatically mean immediate bankruptcy."),"finance"),
		goal("tree",Loc.text("Clear the friendly forest"),Loc.text("Move your Scout onto the marked forest. Trees and graves block province income. Clearing a tree restores that income and also pays 1 gold immediately."),"move",Vector2i(-1,-1),{"source":Vector2i(-3,0)}),
		goal("tree_budget",Loc.text("Hover over gold to compare the forecast"),Loc.text("Check gold again: clearing paid 1 immediately and improved recurring income. A one-time payment and a higher forecast are different benefits."),"finance"),
		goal("collect",Loc.text("End turn and collect the balance"),Loc.text("Click End turn. Your treasury receives income minus wages, rather than the full gross income shown in the tooltip. Keep checking the forecast before adding more troops."),"end_turn"),
	]) + exercise(Loc.text("Separate kingdoms, separate gold"),"banks",[
		goal("first_bank",Loc.text("Check the western kingdom's gold"),Loc.text("Your disconnected kingdoms each have 10 gold. Hover over gold to check the selected western kingdom. Faction color does not make their treasuries shared."),"finance",NONE,{}, {"focus":Vector2i(0,0)}),
		goal("spend_west",Loc.text("Recruit in the western kingdom"),Loc.text("Recruit a Scout on the marked western province. Its 10-gold price empties only the western treasury. Gold held by the eastern kingdom cannot pay for this purchase."),"recruit",Vector2i(-2,0),{"tier":1}),
		goal("other_bank",Loc.text("Select the eastern kingdom"),Loc.text("Click the marked eastern province to select that kingdom's budget. You can switch the dock between kingdoms by selecting their land; opening a capital's details is not required."),"kingdom",Vector2i(1,0)),
		goal("east_budget",Loc.text("Check the eastern treasury"),Loc.text("Hover over gold. The eastern kingdom still has 10, even though you spent the western kingdom's gold. Each disconnected kingdom must fund its own armies."),"finance"),
		goal("connect",Loc.text("Capture the gap to join the kingdoms"),Loc.text("Select either western Scout and capture the marked neutral gap. This joins the two regions into one kingdom and pools the remaining gold. Reconnection can rescue land that could not support itself."),"move",Vector2i(0,0)),
		goal("joined_budget",Loc.text("Check the combined kingdom's budget"),Loc.text("Hover over gold: one connected kingdom now supports both regions. Its treasury contains the gold left from both banks, and the forecast includes their combined income and army wages."),"finance"),
	]) + exercise(Loc.text("Keep an expensive army paid"),"deficit",[
		goal("deficit",Loc.text("Read the shortfall in the gold tooltip"),Loc.text("This kingdom earns 39 per turn. A Knight and Scout cost 40, and savings are empty. You cannot dismiss armies to avoid wages: plan purchases carefully. Ending now would bankrupt this kingdom and kill its supported armies."),"finance",NONE,{}, {"focus":Vector2i(-1,1)}),
		goal("fund",Loc.text("Expand with the Scout to cover wages"),Loc.text("Use your cheaper, ready Scout to capture ordinary value-1 neutral land. Keep the Knight guarding your border. You do not need a rare rich province or another expensive unit: one extra connected income covers this small shortfall."),"move",NONE,{}, {"criteria":{"owner_before":-1,"plain":true,"source_tier":1}}),
		goal("funded_budget",Loc.text("Check that the forecast is no longer negative"),Loc.text("Hover over gold again. Income now covers both armies' wages. There is still little room for another purchase. Expanding with existing cheap armies is often better than buying the strongest rank everywhere."),"finance"),
		goal("survive",Loc.text("End turn with both armies paid"),Loc.text("End turn. Both armies survive because this connected kingdom can pay them. Savings can cover temporary deficits, but an army whose local treasury falls below zero will starve."),"end_turn"),
	])

static func construction() -> Array:
	return exercise(Loc.text("Cheap development first"),"house",[
		goal("develop",Loc.text("Develop a value-1 province"),Loc.text("Click any friendly value-1 province's ground and choose Develop. It costs 2 gold for +1 income per turn. No builder is required. The next development on that province will cost more."),"develop",NONE,{}, {"criteria":{"value_before":1}}),
		goal("house",Loc.text("Build a House on clear friendly land"),Loc.text("Open Build and choose House. Use highlighted clear land without an army, building or capital. It costs 20 gold for +4 income per turn and no wages. When cheap development is available, that can be the better first investment."),"build",NONE,{"building":"house"}),
		goal("house_budget",Loc.text("Compare income in the gold tooltip"),Loc.text("Hover over gold. Development added 1 income and the House added 4. Neither pays its recurring income immediately. Houses occupy building space and are destroyed if their province is directly captured."),"finance"),
	]) + exercise(Loc.text("Towers protect your land"),"tower",[
		goal("tower",Loc.text("Build the border Tower"),Loc.text("Build a Tower on the marked border tile for 15 gold and no wages. It gives defense 2 to itself and adjacent FRIENDLY land. It never protects nearby neutral or enemy provinces."),"build",Vector2i(-1,-1),{"building":"tower"}),
		goal("coverage",Loc.text("Click the Tower to see its coverage"),Loc.text("Click the Tower itself. Its coverage highlights show which friendly provinces are defended. The Soldier cannot capture these defense-2 provinces, but the neutral route below the Tower is outside its protection."),"inspect",Vector2i(-1,-1)),
		goal("flank",Loc.text("End turn: the enemy takes the neutral route"),Loc.text("End turn. The enemy Soldier cannot break the Tower, so it takes the neutral province below it. A neighboring Tower does not defend that neutral land."),"end_turn",NONE,{}, {"opponent":[{"kind":"move","source":Vector2i(0,0),"target":Vector2i(0,1)}]}),
		goal("flank_attack",Loc.text("End turn: the enemy reaches an uncovered border"),Loc.text("The Soldier now borders your lower province, two steps from the Tower. End turn to see it capture that uncovered land. Coverage and approach routes matter more than simply owning a Tower."),"end_turn",NONE,{}, {"opponent":[{"kind":"move","source":Vector2i(0,1),"target":Vector2i(-1,1)}]}),
	]) + exercise(Loc.text("Bridges open public routes"),"bridge",[
		goal("bridge",Loc.text("Build a Bridge across the channel"),Loc.text("Open Build and choose Bridge. This water crossing costs 15 gold. Bridges earn no income and stay neutral: every kingdom can use the route, including your opponents."),"build",Vector2i(0,0),{"building":"bridge"}),
		goal("land",Loc.text("Cross directly onto the opposite shore"),Loc.text("Select your Scout and click the marked neutral shore, beyond the Bridge. Crossing friendly land and empty bridges is part of the same move. When the landing is reachable, avoid wasting a turn stopping on the Bridge."),"move",Vector2i(1,0),{"source":Vector2i(-3,0)}),
		goal("shore",Loc.text("Continue after the crossing"),Loc.text("You crossed and captured shore in one action. The Bridge remains a public route. Your army needs a route back to a supporting treasury; expanding or reconnecting on the far shore makes a stronger foothold."),"continue"),
	]) + exercise(Loc.text("When a House is the better investment"),"investment",[
		goal("compare",Loc.text("Inspect a value-2 province's development cost"),Loc.text("Every friendly province here is already value 2. Click the marked province and look at Develop: the next +1 income costs 8 gold. Four such upgrades cost 32, while a House adds 4 income for 20."),"inspect",Vector2i(-2,0)),
		goal("invest",Loc.text("Build a House for the cheaper +4 income"),Loc.text("Choose House in Build and place it on any valid friendly tile. With the cheapest development already used, the House now buys income more efficiently. Compare costs instead of following a fixed build order."),"build",NONE,{"building":"house"}),
		goal("investment_budget",Loc.text("Check the House's added income"),Loc.text("Hover over gold. Gross income rose from 24 to 28 for a 20-gold investment. Future development, buildings and army purchases should be judged against what your position needs next."),"finance"),
	])

static func conquest() -> Array:
	return exercise(Loc.text("Capture a capital, keep its Tower"),"capital",[
		goal("strongpoint",Loc.text("Click the enemy Tower to see its defense"),Loc.text("The Tower protects adjacent ENEMY land, including its capital. It does not protect the neutral land or your provinces. The Scout above it lies outside its coverage and offers a weaker approach."),"inspect",Vector2i(1,0)),
		goal("weakpoint",Loc.text("Attack the unprotected Scout with your Soldier"),Loc.text("Your Soldier can beat this defense-1 Scout. Take its province to approach the capital. Against an unprotected capital, a Soldier would also be sufficient."),"move",Vector2i(0,-1),{"source":Vector2i(-3,0)}),
		goal("capital_knight",Loc.text("Upgrade for the Tower-protected capital"),Loc.text("This capital has defense 2 because of the neighboring Tower, so your Soldier needs a Knight upgrade. Pay 20 gold. Buying the rank does not restore its spent action."),"recruit",Vector2i(0,-1),{"tier":3}),
		goal("prepare_capital",Loc.text("End turn to ready the Knight"),Loc.text("End turn before the next attack. Your Knight will then be ready to break the capital's defense. Attack the capital itself rather than destroying the neighboring Tower."),"end_turn"),
		goal("capital",Loc.text("Capture the capital and its neighboring Tower"),Loc.text("Take the marked capital. Adjacent provinces in that kingdom surrender too. Their buildings remain, so the Tower becomes yours without paying to build one or destroying it in a direct attack."),"move",Vector2i(1,-1),{"source":Vector2i(0,-1)}),
		goal("captured_tower",Loc.text("Click your surrendered Tower"),Loc.text("Click the Tower: it is now yours and its coverage defends your new friendly land. Directly capturing a Tower destroys it; capturing its neighboring capital can win it intact. Victory depends on enemy capitals, not every isolated province."),"inspect",Vector2i(1,0)),
	]) + exercise(Loc.text("Cut off a single army"),"cut",[
		goal("cut",Loc.text("Capture the narrow connection"),Loc.text("The marked province is the exposed Scout's only connection to its treasury. Take it with your Soldier. A single isolated province has no kingdom bank to pay its army."),"move",Vector2i(0,1),{"source":Vector2i(-3,0)}),
		goal("starve",Loc.text("End turn to see the isolated Scout die"),Loc.text("End turn. The enemy Scout is cut off from all support and dies when its faction settles wages. Watch its death and the grave it leaves. Protect your own narrow connections too."),"end_turn"),
	]) + exercise(Loc.text("Bankrupt an entire pocket"),"cut_army",[
		goal("cut_army",Loc.text("Cut off the three enemy Soldiers"),Loc.text("The marked connection supports three Soldiers in the lower pocket. Use your Knight to take it. The pocket is large enough to form a new kingdom, but its poor land cannot pay 36 gold of wages."),"move",Vector2i(0,1),{"source":Vector2i(-3,0)}),
		goal("pocket_starve",Loc.text("End turn and starve the whole pocket"),Loc.text("End turn. The separated kingdom's savings cannot cover the shortfall, so all three supported Soldiers die together. You removed an expensive army with one capture rather than winning three direct fights."),"end_turn"),
	]) + exercise(Loc.text("Move a capital out of danger"),"relocate",[
		goal("relocate",Loc.text("Relocate the threatened border capital"),Loc.text("The enemy Soldier can capture your exposed border capital next turn. Click the marked rear province and choose Move capital. Confirm the 10-gold price. Relocation protects the treasury; later moves cost more. Cancelling spends nothing."),"relocate_capital",Vector2i(-4,0),{}, {"focus":Vector2i(-1,0)}),
		goal("old_capital_attack",Loc.text("End turn: the enemy takes the old capital tile"),Loc.text("End turn. The Soldier will capture the former capital's province. Because you moved the capital, this loses one province rather than surrendering its neighbors and destroying the kingdom's treasury."),"end_turn",NONE,{}, {"opponent":[{"kind":"move","source":Vector2i(0,0),"target":Vector2i(-1,0)}]}),
		goal("saved_bank",Loc.text("Check that your kingdom still has a treasury"),Loc.text("Hover over gold. Your rear capital and connected kingdom survived the attack. Relocation was useful because the capital was actually threatened; when the capital is safe, that gold might be better spent elsewhere."),"finance"),
	])

static func magic() -> Array:
	return exercise(Loc.text("Trailblaze keeps momentum"),"trail",[
		goal("trailblaze",Loc.text("Cast Trailblaze on friendly land"),Loc.text("Mana is shared across your kingdoms, unlike gold. The purple dock shows current mana, capacity and regeneration. Trailblaze costs 1 mana: your next neutral capture keeps its action. Any other valid move consumes the blessing without that extra action."),"spell",NONE,{"spell":"trailblaze"}),
		goal("source",Loc.text("Capture the neutral mana source"),Loc.text("Select your Scout and capture this neutral source. Sources increase maximum mana; every four controlled sources also add regeneration. Trailblaze leaves the Scout ready, so you can immediately use the new foothold."),"move",Vector2i(0,0),{"source":Vector2i(-3,0)}),
		goal("extra_capture",Loc.text("Capture another neutral province now"),Loc.text("The same Scout is still ready. Capture another highlighted neutral province without ending the turn. This is how a small mana investment can turn into more land and recurring income during ordinary expansion."),"move",NONE,{}, {"criteria":{"owner_before":-1}}),
	]) + exercise(Loc.text("Summon reinforcements"),"summon",[
		goal("regen",Loc.text("End turn to regenerate mana"),Loc.text("This kingdom has four sources, including its capital, for capacity 5 and regeneration 2. Start with 1 mana and end turn: it becomes 3. Regeneration cannot exceed capacity, so unused mana may stop growing."),"end_turn"),
		goal("summon",Loc.text("Summon a Scout on valid friendly land"),Loc.text("Choose Summon in Spells and click empty land in a friendly kingdom. It costs 2 mana instead of recruitment gold. The Scout is ready immediately, but its normal 4-gold wage still appears in that kingdom's forecast."),"spell",NONE,{"spell":"summon"}),
		goal("use_summon",Loc.text("Capture neutral land with the new Scout"),Loc.text("Use the summoned Scout before ending the turn. Summon is useful when another ready army can do something now; creating troops you cannot support just moves the cost into future wages."),"move",NONE,{}, {"criteria":{"owner_before":-1,"source_tier":1}}),
	]) + exercise(Loc.text("Shatter a neutral structure"),"shatter",[
		goal("shatter_mana",Loc.text("Regenerate enough mana for Shatter"),Loc.text("Shatter costs 2 mana. End turn to regenerate enough. Its targets are reachable neutral structures; it cannot erase an enemy-owned Tower or an impassable mountain."),"end_turn"),
		goal("bridge_details",Loc.text("Inspect the neutral Bridge"),Loc.text("This crossing could let either side approach. Destroying a bridge removes the route, and any army standing on it is lost. Check what depends on the crossing before spending mana to cut it."),"inspect",Vector2i(0,0)),
		goal("shatter",Loc.text("Shatter the marked Bridge"),Loc.text("Choose Shatter, then click the Bridge. This removes the crossing rather than capturing it. Income landmarks cannot be destroyed this way: their rewards change hands through conquest."),"spell",Vector2i(0,0),{"spell":"shatter"}),
	])

static func exploration() -> Array:
	return exercise(Loc.text("Treasure pays once"),"chest",[
		goal("collect_chest",Loc.text("Capture the 15-gold chest"),Loc.text("The marked chest pays 15 gold when captured. Move your Scout onto it. Immediate loot can fund another purchase this turn, while ordinary province income arrives on later turns."),"move",Vector2i(0,0),{"source":Vector2i(-3,0)}),
		goal("after_chest",Loc.text("Check the immediate treasury increase"),Loc.text("Hover over gold. The treasury gained 15 immediately, and the chest disappeared. The captured land also contributes ordinary income, but crossing it again cannot pay the chest reward twice."),"finance"),
	]) + exercise(Loc.text("Choose an encounter reward"),"event",[
		goal("discover",Loc.text("Explore the question mark"),Loc.text("Question marks reveal encounters when an army arrives. Their choices explain guaranteed rewards and any risks. Move onto this one, read both outcomes and think about immediate reinforcements versus lasting income."),"move",Vector2i(0,0),{"source":Vector2i(-3,0)}),
		goal("choose",Loc.text("Read the outcomes and choose either"),Loc.text("This encounter offers an income landmark or a ready Scout with normal wages. Both choices are valid here. Landmarks remain on the province; their benefits depend on keeping control of that land."),"event"),
	]) + exercise(Loc.text("Landmarks grant lasting benefits"),"landmark",[
		goal("discover_landmark",Loc.text("Discover the smith's invention"),Loc.text("Some encounters create structures with a lasting faction benefit. Move your Knight onto this question mark. This encounter appears only when you have a Knight and do not already control its landmark."),"move",Vector2i(0,0),{"source":Vector2i(-3,0)}),
		goal("create_landmark",Loc.text("Accept the stainless steel invention"),Loc.text("Accept the invention. It creates a landmark on this province. While your faction controls it, every Knight costs 2 less gold per turn. An opponent who captures it receives that benefit instead."),"event"),
		goal("steel_status",Loc.text("Hover over the S status icon below"),Loc.text("Hover over the S icon beside the bottom dock to check the active stainless steel benefit. Status icons explain ongoing bonuses. The landmark persists on the map; losing its province also loses its benefit."),"status",NONE,{"effect":"stainless_steel"}),
	]) + exercise(Loc.text("Stop a predator and its lair"),"lair",[
		goal("lair_spawn",Loc.text("End turn to see a Bear emerge"),Loc.text("The cave has a clear exit beside your border House. End turn to see it spawn a Bear. A newly emerged animal does not also move that turn, giving you time to recognize the threat."),"end_turn",NONE,{}, {"wildlife_turn":true,"highlight":Vector2i(0,1)}),
		goal("lair",Loc.text("Inspect the Bear and its threat range"),Loc.text("Click the Bear itself to see its threat range. Bears attack armies and buildings; wolves hunt exposed troops, and boars raid unguarded land and buildings. This Bear threatens your border House. Its cave can replace it after it dies."),"animal",Vector2i(0,0)),
		goal("bear_raid",Loc.text("End turn to see the Bear raid the House"),Loc.text("End turn and watch the Bear attack. It destroys the unprotected House and neutralizes the province. Predators can damage your economy even when you are not fighting another kingdom."),"end_turn",NONE,{}, {"wildlife_turn":true}),
		goal("kill_bear",Loc.text("Kill the Bear with your Knight"),Loc.text("Capture the Bear's province with your Knight. Bears have defense 2, so a Knight is required. Killing the predator removes the immediate threat, but a surviving cave can eventually spawn a replacement."),"move",NONE,{"source":Vector2i(-3,0)},{"criteria":{"animal_before":"bear"}}),
		goal("ready_hunt",Loc.text("End turn to ready the Knight"),Loc.text("End turn to ready the Knight. The cave's respawn delay gives you time to destroy it before a new Bear emerges."),"end_turn",NONE,{}, {"wildlife_turn":true}),
		goal("hunt",Loc.text("Destroy the cave before another Bear spawns"),Loc.text("Capture the cave with your Knight. This stops its respawns and leaves a permanent landmark worth +5 gold per turn to its connected kingdom. Wolf dens grant mana regeneration; boar burrows pay immediate gold and mana."),"move",Vector2i(0,1),{}, {"criteria":{"source_tier":3}}),
		goal("landmark",Loc.text("Hover over the G landmark status icon"),Loc.text("Hover over the G status icon beside the dock. Its breakdown names the Bear cave's +5 income bonus. Keep the landmark connected and controlled to receive that income; an enemy can capture and use it too."),"status",NONE,{"effect":"income_bonus"}),
	])
