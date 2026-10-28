extends RefCounted
## Subject-based exercises. Only the final practice is a complete AI match.
const Loc = preload("res://src/localization/text.gd")
const Scenarios = preload("res://src/game/tutorial_scenarios.gd")
const Document = preload("res://src/tutorial_editor/tutorial_document.gd")
const NONE := Vector2i(999,999)
const IDS := ["armies","economy","construction","logistics","conquest","magic","exploration","practice"]

static func categories() -> Array:
	var result := [
		{"id":"armies","title":Loc.text("Armies and expansion"),"description":Loc.text("Learn 5/4/3 movement, ready recruits, merging and upgrades.")},
		{"id":"economy","title":Loc.text("Kingdoms and money"),"description":Loc.text("Understand income, wages and separate treasuries.")},
		{"id":"construction","title":Loc.text("Defences and upkeep"),"description":Loc.text("Plan permanent towers and pay for bridges and defences.")},
		{"id":"logistics","title":Loc.text("Cities and supply lines"),"description":Loc.text("Build forward cities, recruit nearby and connect useful roads.")},
		{"id":"conquest","title":Loc.text("Taking enemy territory"),"description":Loc.text("Capture defended cities, recruit nearby and take capitals.")},
		{"id":"magic","title":Loc.text("Mana and spells"),"description":Loc.text("Use Summon, Trailblaze and Shatter with shared mana.")},
		{"id":"exploration","title":Loc.text("Exploration and rewards"),"description":Loc.text("Collect treasure and try either encounter reward.")},
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
	var data: Dictionary = Scenarios.map_data(category) if category == "practice" else preload("res://src/game/logistics_tutorial.gd").map_data(category)
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
	if category == "practice":
		return [goal("win", Loc.text("Defeat the enemy kingdom"), Loc.text("Play a real match using cities, limited movement, roads and infrastructure upkeep. Expand, establish recruitment sites, and take the enemy capital."), "any", NONE, {}, {"exercise":"practice", "restrict_actions":false, "conditions":[{"type":"victory", "faction":-1}]})]
	var result: Array = preload("res://src/game/logistics_tutorial.gd").steps(category)
	for entry in result: entry.title = entry.task
	return result
