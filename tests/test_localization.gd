extends SceneTree
const Loc = preload("res://src/localization/text.gd")
const Catalog = preload("res://src/game/game_catalog.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
const Ui = preload("res://src/ui/ui_theme.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func write_json(path: String, value) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))

func run() -> void:
	var languages = root.get_node("Languages")
	var original_path: String = languages.settings_path
	var original_selected: String = languages.selected_locale
	var original_active: String = languages.active_locale
	var original_server_locale := TranslationServer.get_locale()
	var original_root_theme: Theme = root.theme
	var dir := "user://localization-tests"
	DirAccess.make_dir_recursive_absolute(dir)
	var pack_path := dir + "/test.json"
	var manifest_path := dir + "/languages.json"
	var settings_path := dir + "/settings.cfg"
	# Synthetic markers exercise translation; these are not a shipped language.
	var unit_template := "%s · strength %d\nCost %d G · upkeep −%d G / turn\n%s\nMove %d hexes · roads cost half\nRecruit on or beside cities / capitals; ready immediately"
	write_json(pack_path, {"locale":"eo", "name":"TEST LANGUAGE Ω", "messages":{
		"Quick Play":"TEST::PLAY Ω", "Language":"TEST::LANGUAGE", "Knight":"TEST::KNIGHT",
		"City":"TEST::CITY",
		"Save":"TEST::SAVE", "Space":"TEST::SPACE",
		"Level %d":"TEST::LEVEL %d", "Tiny":"TEST::TINY", "%s · ~%s tiles":"TEST::MAP %s %s",
		"Build":"", "Recruit":42, "Income %+d G / turn":"TEST::BROKEN %s", "UNKNOWN_TEST_KEY":"TEST::UNKNOWN",
		unit_template:"TEST::UNIT %s %d %d %d %s %d"}})
	write_json(manifest_path, [pack_path])
	languages.settings_path = settings_path
	languages.reload_languages(manifest_path)
	languages.set_language("en", false)
	languages.apply_selected_language()
	expect(languages.languages.size() == 2 and languages.languages[1]["name"] == "TEST LANGUAGE Ω", "Pack registration exposes its supplied display name without inventing a translation")
	expect(languages.diagnostics.size() == 3, "Bad types, unknown messages and mismatched placeholders are reported and skipped")
	expect(Loc.text("Quick Play") == "Quick Play", "English is the default even when another pack exists")
	var options = load("res://src/ui/options_view.gd").new()
	root.add_child(options)
	await process_frame
	expect(options.language_choice.item_count == 2 and options.language_choice.get_item_metadata(1) == "eo", "Gameplay options list installed languages using locale metadata")
	options.language_choice.select(1)
	options.language_choice.item_selected.emit(1)
	expect(languages.selected_locale == "eo" and languages.active_locale == "en" and languages.restart_required(), "Selecting a language persists it and leaves the current session in its original language")
	expect(options.language_note.text.contains("Restart"), "Options explains that the selection applies after restart")
	var config := ConfigFile.new()
	expect(config.load(settings_path) == OK and config.get_value("language", "locale") == "eo", "Language preference is saved independently of match/rules settings")
	languages.selected_locale = "en"
	languages.load_settings()
	expect(languages.selected_locale == "eo", "Saved language is restored on the next launch")
	options.queue_free()
	await process_frame
	languages.apply_selected_language()
	expect(Loc.text("Quick Play") == "TEST::PLAY Ω", "UTF-8 translations reach the native TranslationServer")
	expect(Loc.text("Level %d") % 12 == "TEST::LEVEL 12", "Dynamic messages translate before formatting")
	expect(Loc.text("Build") == "Build" and Loc.text("Recruit") == "Recruit", "Blank and invalid entries fall back to readable English")
	expect(Loc.text("Income %+d G / turn") % 3 == "Income +3 G / turn", "Rejected placeholders cannot break numeric formatting")
	expect(Catalog.unit_tooltip(3).begins_with("TEST::UNIT TEST::KNIGHT 3 40 36"), "Unit descriptions translate their template and rank while retaining actual prices and wages")
	expect(Sizes.choice_label("small") == "TEST::MAP TEST::TINY 80", "Data-driven names are translated before being inserted into a caption")
	var keys = root.get_node("Keys")
	var key_code: int = keys.bindings["end_turn"]
	keys.bindings["end_turn"] = KEY_SPACE
	expect(keys.key_name("end_turn") == "TEST::SPACE", "Special key names can be translated without changing physical key codes")
	keys.bindings["end_turn"] = key_code
	var native_dialog := FileDialog.new()
	root.add_child(native_dialog)
	native_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	expect(native_dialog.tr("Save") == "TEST::SAVE", "Native file dialog messages use the registered translation domain")
	native_dialog.queue_free()
	var document = load("res://src/editor/level_document.gd").new()
	document.paint(Vector2i.ZERO, "Land", 0, 2)
	document.paint(Vector2i.ZERO, "City", 0, 2)
	expect(Loc.text("City") == "TEST::CITY" and document.cells[Vector2i.ZERO]["building"] == "city", "Translated tool captions do not change editor command IDs or saved data")
	expect(not languages.source_messages.has("choice_%d"), "Keyboard action IDs are excluded from the translation catalogue")
	var export_script = load("res://addons/localization_export/export_plugin.gd")
	var export_files: PackedStringArray = export_script.files_to_export()
	expect("res://localization/languages.json" in export_files and "res://localization/languages/en.json" in export_files and "res://localization/template.json" not in export_files, "Export includes runtime translation files without the editable template")
	var export_dir := "res://artifacts/localization-export-fixture"
	DirAccess.make_dir_recursive_absolute(export_dir)
	var export_pack := export_dir + "/pack.json"
	var export_manifest := export_dir + "/languages.json"
	var pack_data = languages.read_json(pack_path)
	write_json(export_pack, pack_data)
	write_json(export_manifest, [export_pack])
	expect(export_pack in export_script.files_to_export(export_manifest), "Export bundles registered language packs even though JSON is not an imported resource")
	# Reuse the engine's embedded font bytes; no downloaded or copied third-party asset.
	var font = ThemeDB.fallback_font
	if font is FontVariation: font = font.base_font
	if font is FontFile and not font.data.is_empty():
		var font_path := export_dir + "/font.ttf"
		var font_output := FileAccess.open(font_path, FileAccess.WRITE)
		font_output.store_buffer(font.data)
		font_output.close()
		pack_data["font"] = font_path
		write_json(export_pack, pack_data)
		expect(font_path in export_script.files_to_export(export_manifest), "Export bundles the font specified by a language pack")
		languages.reload_languages(export_manifest)
		languages.set_language("eo", false)
		languages.apply_selected_language()
		expect(languages.active_font != null and Ui.create_theme().default_font == languages.active_font, "A raw font loads without editor import and reaches shared UI themes")
	var parent := Control.new()
	root.add_child(parent)
	var label := Ui.label_at(parent, "Quick Play", Vector2.ZERO)
	expect(label.text == "TEST::PLAY Ω", "Shared label creation uses the selected language")
	Ui.fit_text(label, "Quick Play", 80)
	expect(label.text == "TEST::PLAY Ω" and label.size.y >= label.get_minimum_size().y, "Text measurement uses the displayed translation")
	parent.queue_free()
	expect(Loc.valid_translation("Value %d / %s", "TEST %d / %s"), "Matching ordered printf placeholders are accepted")
	expect(not Loc.valid_translation("Value %d", "TEST %s") and not Loc.valid_translation("Value %d", "TEST 100% %d"), "Broken types and unescaped percent signs in formatted translations are rejected")
	expect(Loc.valid_translation("{unit} owns {place}", "{place} :: {unit}"), "Named placeholders can be reordered")
	expect(not Loc.valid_translation("{unit} owns {place}", "{unit}"), "Missing named placeholders are rejected")
	languages.set_language("not-installed", false)
	expect(languages.selected_locale == "eo", "Unknown selections cannot enter saved state")
	config.set_value("language", "locale", 123)
	config.save(settings_path)
	languages.load_settings()
	expect(languages.selected_locale == "en", "Corrupt saved preferences fall back to English")
	write_json(manifest_path, [pack_path, pack_path, dir + "/missing.json"])
	languages.reload_languages(manifest_path)
	expect(languages.languages.size() == 2 and languages.diagnostics.size() == 5, "Duplicate and missing packs do not prevent startup")
	write_json(manifest_path, {"invalid":"manifest"})
	languages.reload_languages(manifest_path)
	expect(languages.languages.size() == 1 and languages.has_locale("en"), "Malformed manifests retain the English recovery option")
	# Restore the real application registry and preference path, never its files.
	languages.settings_path = original_path
	languages.reload_languages()
	languages.set_language(original_active, false)
	languages.apply_selected_language()
	languages.selected_locale = original_selected
	root.theme = original_root_theme
	TranslationServer.set_locale(original_server_locale)
	for path in [export_pack, export_manifest, export_dir + "/font.ttf"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("Localization checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
