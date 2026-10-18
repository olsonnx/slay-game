extends Node
## Preferences are applied at startup so an ongoing match never loses its state.
signal changed
signal save_failed(error: Error)
const Text = preload("res://src/localization/text.gd")
const DEFAULT_PATH := "user://language_settings.cfg"
const MANIFEST := "res://localization/languages.json"
var settings_path := DEFAULT_PATH
var selected_locale := "en"
var active_locale := "en"
var languages: Array[Dictionary] = []
var translations: Array[Translation] = []
var diagnostics: Array[String] = []
var source_messages: Dictionary = {}
var active_font: Font

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload_languages()
	load_settings()
	apply_selected_language()

func read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return null
	var json := JSON.new()
	if json.parse(file.get_as_text().trim_prefix("\ufeff")) != OK: return null
	return json.data

func reload_languages(manifest_path := MANIFEST) -> void:
	for translation in translations: TranslationServer.remove_translation(translation)
	translations.clear()
	languages.clear()
	diagnostics.clear()
	source_messages.clear()
	var manifest = read_json(manifest_path)
	if not manifest is Array:
		diagnostics.append("Language manifest must be an array of pack paths.")
		manifest = []
	# English must exist even when the manifest or a translation is broken.
	var english = read_json("res://localization/languages/en.json")
	if english is Dictionary and english.get("messages") is Dictionary:
		source_messages = english["messages"]
	languages.append({"locale":"en", "name":"English", "font":""})
	for path in manifest:
		if not path is String:
			diagnostics.append("Language pack path must be a string.")
			continue
		var pack = read_json(path)
		if not pack is Dictionary or not pack.get("locale") is String or not pack.get("name") is String or not pack.get("messages") is Dictionary:
			diagnostics.append("Invalid language pack: %s" % path)
			continue
		var locale: String = TranslationServer.standardize_locale(pack["locale"])
		var locale_pattern := RegEx.new()
		locale_pattern.compile("^[a-z]{2,3}(?:_[A-Za-z0-9]+)*$")
		if locale_pattern.search(locale) == null or pack["name"].strip_edges().is_empty():
			diagnostics.append("Invalid language code or display name: %s" % path)
			continue
		if locale == "en": continue
		if languages.any(func(item: Dictionary): return item["locale"] == locale):
			diagnostics.append("Duplicate language: %s" % locale)
			continue
		var translation := Translation.new()
		translation.locale = locale
		for key in pack["messages"]:
			var value = pack["messages"][key]
			if not value is String:
				diagnostics.append("Non-text translation in %s: %s" % [locale, key])
				continue
			if value.is_empty(): continue
			if not source_messages.has(key):
				diagnostics.append("Unknown translation key in %s: %s" % [locale, key])
				continue
			if not Text.valid_translation(key, value):
				diagnostics.append("Placeholder mismatch in %s: %s" % [locale, key])
				continue
			translation.add_message(key, value)
		translations.append(translation)
		TranslationServer.add_translation(translation)
		var font_path = pack.get("font", "")
		languages.append({"locale":locale, "name":pack["name"], "font":font_path if font_path is String else ""})
	changed.emit()

func has_locale(locale: String) -> bool:
	return languages.any(func(item: Dictionary): return item["locale"] == locale)

func load_settings(path := "") -> Error:
	var config := ConfigFile.new()
	var error := config.load(settings_path if path.is_empty() else path)
	var saved = config.get_value("language", "locale", "en") if error == OK else "en"
	selected_locale = saved if saved is String and has_locale(saved) else "en"
	return error

func set_language(locale: String, persist := true) -> void:
	if not has_locale(locale): return
	selected_locale = locale
	if persist: flush_settings()
	changed.emit()

func flush_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("language", "locale", selected_locale)
	var error := config.save(settings_path)
	if error != OK: save_failed.emit(error)
	return error

func apply_selected_language() -> void:
	active_locale = selected_locale if has_locale(selected_locale) else "en"
	TranslationServer.set_locale(active_locale)
	active_font = null
	for language in languages:
		if language["locale"] == active_locale and not language["font"].is_empty():
			var font_path: String = language["font"]
			if font_path.get_extension().to_lower() in ["ttf", "otf"] and FileAccess.file_exists(font_path):
				var font_file := FontFile.new()
				font_file.data = FileAccess.get_file_as_bytes(font_path)
				if not font_file.get_font_name().is_empty(): active_font = font_file
			elif ResourceLoader.exists(font_path): active_font = load(font_path) as Font
			if active_font == null: diagnostics.append("Could not load font: %s" % language["font"])
	if active_font != null and is_inside_tree():
		var root_theme := get_tree().root.theme.duplicate() as Theme if get_tree().root.theme != null else Theme.new()
		root_theme.default_font = active_font
		get_tree().root.theme = root_theme
	changed.emit()

func restart_required() -> bool:
	return selected_locale != active_locale
