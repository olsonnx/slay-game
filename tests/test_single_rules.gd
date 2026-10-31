extends SceneTree

const Rules = preload("res://src/game/kingdom_rules.gd")
const Document = preload("res://src/editor/level_document.gd")
const Setup = preload("res://src/game/match_setup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(description)

func run() -> void:
	var model = Rules.new()
	model.rule_mode = "classic"
	expect(model.rule_mode == "modern" and model.unit_upkeep(3, 0) == 36, "Retired rules identifiers cannot change the economy")
	model.generate(42, "small", 4)
	for bank in model.kingdoms.values():
		expect(bank.gold == 10 and model.income(bank) - model.upkeep(bank) == 7, "Every new kingdom uses the current opening economy")
	expect(Setup.normalize({"rules":"classic"}).rules == "modern", "Older multiplayer preferences normalize to the current rules")
	var settings = root.get_node("Gameplay")
	var old_path: String = settings.settings_path
	var path := "res://artifacts/single-rules-settings.cfg"
	var saved := ConfigFile.new()
	saved.set_value("gameplay", "rules", "classic")
	saved.set_value("gameplay", "difficulty", "hard")
	saved.set_value("gameplay", "clear_indicators", false)
	saved.save(path)
	expect(settings.load_settings(path) == OK and settings.rule_mode == "modern" and settings.difficulty == "hard" and not settings.clear_indicators, "Old rules preferences are ignored while unrelated preferences survive")
	settings.settings_path = path
	settings.flush_settings()
	saved.clear()
	saved.load(path)
	expect(not saved.has_section_key("gameplay", "rules"), "New settings no longer store a rules choice")
	settings.settings_path = old_path
	DirAccess.remove_absolute(path)
	var doc = Document.new()
	doc.generate("small", "classic", true)
	expect(doc.rule_mode == "modern" and doc.starting_gold == 10, "Legacy editor generation uses the current starting economy")
	doc.generate("small", "modern", true)
	for x in [0, 1, 4, 5]: doc.paint(Vector2i(x, 0), "Land", 0 if x < 2 else 1, 2)
	doc.paint(Vector2i.ZERO, "Player start", 0, 2)
	doc.paint(Vector2i(1, 0), "City", 0, 2)
	var legacy: Dictionary = doc.state()
	legacy.rules = "classic"
	for row in legacy.cells:
		if row.q == 1 and row.r == 0: row.building = "house"
	var loaded = Document.new()
	expect(loaded.read_data(legacy) == "" and loaded.state() == doc.state(), "Older authored maps retain their serialized layout with houses migrated to cities")
	var playtest = loaded.build_rules()
	expect(playtest.unit_upkeep(2, 0) == 12, "Migrated maps use the same wages as Quick Play")
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await process_frame
	expect("rules_choice" not in app.menus.options_view and "rules_choice" not in app.menus.multiplayer_panel, "Options and multiplayer contain no rules selector")
	app.open_editor()
	expect("mode_choice" not in app.editor.ui, "The editor contains no rules selector")
	app.close_editor()
	await app.start_new_game(42)
	expect(app.game.spell_button.visible and app.game.mana_control.visible, "Quick Play always exposes spells and mana")
	await app.return_to_main_menu()
	app.queue_free()
	await process_frame
	print("Single rules checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
