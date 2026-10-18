extends SceneTree
## Validate the installed packs without opening a match or modifying preferences.
func _initialize() -> void: call_deferred("run")

func run() -> void:
	var languages = root.get_node("Languages")
	print("Translation source messages: %d" % languages.source_messages.size())
	for language in languages.languages:
		print("Language: %s (%s)" % [language["name"], language["locale"]])
	for diagnostic in languages.diagnostics: print("Invalid translation: ", diagnostic)
	print("Translation validation: %d issue(s)" % languages.diagnostics.size())
	quit(0 if languages.diagnostics.is_empty() else 1)
