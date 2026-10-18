extends RefCounted
## Each course is one uninterrupted match, ending in an actual capital capture.
const Loc = preload("res://src/localization/text.gd")
const Scenarios = preload("res://src/game/tutorial_scenarios.gd")
const NONE := Vector2i(999,999)
const IDS := ["basics", "intermediate", "advanced"]

static func categories() -> Array:
	var result := [
		{"id":"basics", "title":Loc.text("Basics"), "description":Loc.text("Recruit, claim land, and win your first battle.")},
		{"id":"intermediate", "title":Loc.text("Intermediate"), "description":Loc.text("Fund an army, hold your border, and counterattack.")},
		{"id":"advanced", "title":Loc.text("Advanced"), "description":Loc.text("Cross the water and break a defense with magic.")},
	]
	for course in result:
		var document = installed(course.id)
		if document != null and document.data.get("description","") != "": course.description = document.data.description
	return result

static func category_title(category: String) -> String:
	return categories()[IDS.find(category) if category in IDS else 0]["title"]

static func installed(category: String, folder := "res://tutorials"):
	if category not in IDS: return null
	var filename: String = folder + "/%s.json" % category
	if not FileAccess.file_exists(filename): return null
	var document = preload("res://src/tutorial_editor/tutorial_document.gd").new()
	var error: String = document.load_file(filename)
	if error != "":
		push_warning("Tutorial override ignored: " + error)
		return null
	return document

static func map_data(category := "basics") -> Dictionary:
	var document = installed(category)
	return document.level_data() if document != null else Scenarios.map_data(category)

static func lesson(id: String, title: String, text: String, kind: String, target := NONE, details: Dictionary = {}, task := "") -> Dictionary:
	return {"id":id,"title":title,"text":text,"kind":kind,"target":target,"details":details,"task":task}

static func turn(id: String, title: String, text: String, opponent: Array = []) -> Dictionary:
	var step := lesson(id,title,text,"end_turn",NONE,{},Loc.text("End your turn"))
	step["opponent"] = opponent
	return step

static func lessons(category := "basics") -> Array:
	var document = installed(category)
	if document != null: return document.runtime_steps()
	return builtin_lessons(category)

static func builtin_lessons(category := "basics") -> Array:
	match category:
		"intermediate": return intermediate()
		"advanced": return advanced()
		_: return basics()

static func basics() -> Array:
	return [
		lesson("recruit",Loc.text("Your first Scout"),Loc.text("You are green. Spend your 10 G on a Scout."),"recruit",Vector2i(-2,0),{"tier":1},Loc.text("Recruit a Scout on the gold ring")),
		lesson("select",Loc.text("Take command"),Loc.text("Click the Scout itself to see where it can move."),"select",Vector2i(-2,0),{},Loc.text("Select your Scout")),
		lesson("expand",Loc.text("Make room to grow"),Loc.text("Claim the empty border province. More land earns more gold."),"move",Vector2i(0,0),{"source":Vector2i(-2,0)},Loc.text("Move from the cyan ring to the gold ring")),
		turn("income",Loc.text("Let the turn play out"),Loc.text("Your Scout has moved. End turn to collect income and watch your opponent advance."),[{"kind":"move","source":Vector2i(2,-1),"target":Vector2i(1,0)}]),
		lesson("upgrade",Loc.text("Meet the threat"),Loc.text("Their Scout guards the border. Upgrade yours: a Soldier beats a Scout."),"recruit",Vector2i(0,0),{"tier":2},Loc.text("Recruit a Soldier onto your Scout")),
		lesson("battle",Loc.text("Push them back"),Loc.text("Your Soldier is stronger. Take the guarded province."),"move",Vector2i(1,0),{"source":Vector2i(0,0),"outcome":"attack"},Loc.text("Attack the enemy Scout")),
		turn("ready",Loc.text("The capital is next"),Loc.text("One capture uses one action. Ready your Soldier for the final attack.")),
		lesson("victory",Loc.text("Finish the match"),Loc.text("Capture their capital. Its neighboring provinces will surrender."),"move",Vector2i(2,0),{"source":Vector2i(1,0),"outcome":"attack"},Loc.text("Take the enemy capital")),
	]

static func intermediate() -> Array:
	return [
		lesson("house",Loc.text("Invest before the war"),Loc.text("A border raid is coming. A House adds income without adding wages."),"build",Vector2i(-3,-1),{"building":"house"},Loc.text("Build a House on the gold ring")),
		turn("raid",Loc.text("The enemy advances"),Loc.text("Collect your income. Watch the enemy Soldier move toward your border."),[{"kind":"move","source":Vector2i(2,-1),"target":Vector2i(0,0)}]),
		lesson("tower",Loc.text("Hold the line"),Loc.text("A Tower protects its tile and friendly neighbors. Their Soldier cannot beat it."),"build",Vector2i(-1,0),{"building":"tower"},Loc.text("Build a Tower at the border")),
		turn("flank",Loc.text("Make them go around"),Loc.text("Your border is protected. Save another turn of income for a stronger army."),[{"kind":"move","source":Vector2i(0,0),"target":Vector2i(0,1)}]),
		lesson("knight",Loc.text("Fund the counterattack"),Loc.text("Your income now supports a Knight. Upgrade the Scout to break their advance."),"recruit",Vector2i(-3,0),{"tier":3},Loc.text("Upgrade your Scout to a Knight")),
		lesson("counter",Loc.text("Stop the raid"),Loc.text("They went around your Tower. Your Knight can reach them through friendly land."),"move",Vector2i(0,1),{"source":Vector2i(-3,0),"outcome":"attack"},Loc.text("Defeat the enemy Soldier")),
		turn("fortify",Loc.text("They fall back on defense"),Loc.text("Ready your Knight. The enemy will fortify the road to their capital."),[{"kind":"build","target":Vector2i(1,0),"building":"tower"}]),
		lesson("secure",Loc.text("Secure the border"),Loc.text("Clear the enemy foothold before marching on their capital."),"move",Vector2i(0,0),{"source":Vector2i(0,1)},Loc.text("Capture the enemy foothold")),
		turn("march",Loc.text("Prepare the assault"),Loc.text("Your border is safe. Ready your Knight to attack the Tower.")),
		lesson("breach",Loc.text("Break the strongpoint"),Loc.text("A Knight beats a Tower's defense. Capturing it also destroys the building."),"move",Vector2i(1,0),{"source":Vector2i(0,0),"outcome":"attack"},Loc.text("Capture the enemy Tower")),
		turn("ready",Loc.text("Keep the army paid"),Loc.text("Your House and land cover the Knight's wages. Ready the final attack.")),
		lesson("victory",Loc.text("Turn defense into victory"),Loc.text("Their defenses are gone. Take the capital and end the war."),"move",Vector2i(2,0),{"source":Vector2i(1,0),"outcome":"attack"},Loc.text("Take the enemy capital")),
	]

static func advanced() -> Array:
	return [
		lesson("bridge",Loc.text("Open a new front"),Loc.text("Water separates the armies. A Bridge gives your Knight a crossing."),"build",Vector2i(0,0),{"building":"bridge"},Loc.text("Build a Bridge on the gold ring")),
		lesson("cross",Loc.text("Cross the channel"),Loc.text("Bridges are neutral crossings. Move your Knight onto this one."),"move",Vector2i(0,0),{"source":Vector2i(-2,0)},Loc.text("Move your Knight onto the Bridge")),
		turn("dig_in",Loc.text("The garrison digs in"),Loc.text("Ready your Knight and regenerate mana. Watch the enemy entrench its border garrison."),[{"kind":"entrench","target":Vector2i(2,0)}]),
		lesson("trailblaze",Loc.text("Keep the momentum"),Loc.text("Trailblaze lets your next neutral capture keep its action."),"spell",Vector2i(-3,0),{"spell":"trailblaze"},Loc.text("Cast Trailblaze on your capital")),
		lesson("beachhead",Loc.text("Secure a beachhead"),Loc.text("Take the neutral shore. Watch your Knight stay ready after the capture."),"move",Vector2i(1,0),{"source":Vector2i(0,0)},Loc.text("Capture the neutral shore")),
		lesson("blocked",Loc.text("Break their entrenchment"),Loc.text("The garrison will absorb one attack. Use your extra action to wear it down."),"move",Vector2i(2,0),{"source":Vector2i(1,0),"outcome":"blocked_attack"},Loc.text("Attack the entrenched garrison")),
		lesson("summon",Loc.text("Bring up reinforcements"),Loc.text("Your Knight is spent. Summon a ready Scout using mana instead of gold."),"spell",Vector2i(-2,1),{"spell":"summon"},Loc.text("Summon a Scout on the gold ring")),
		lesson("flank",Loc.text("Widen your foothold"),Loc.text("Your Scout can use the crossing too. Claim more land while the Knight rests."),"move",Vector2i(1,-1),{"source":Vector2i(-2,1)},Loc.text("Capture the neutral flank with your Scout")),
		turn("recover",Loc.text("Ready the next strike"),Loc.text("Their entrenchment is gone. Next turn your Knight can defeat the garrison."),[{"kind":"build","target":Vector2i(4,0),"building":"house"}]),
		lesson("breach",Loc.text("Take the strongpoint"),Loc.text("Attack again. This time the garrison cannot absorb the hit."),"move",Vector2i(2,0),{"source":Vector2i(1,0),"outcome":"attack"},Loc.text("Defeat the enemy garrison")),
		turn("ready",Loc.text("The last push"),Loc.text("Your crossing is secure. Ready your Knight to finish the match.")),
		lesson("victory",Loc.text("Win across the water"),Loc.text("Your bridge, magic and reinforcements opened the way. Take their capital."),"move",Vector2i(3,0),{"source":Vector2i(2,0),"outcome":"attack"},Loc.text("Take the enemy capital")),
	]
