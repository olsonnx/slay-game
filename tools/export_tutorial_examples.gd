extends SceneTree
## Refresh or verify portable editor examples against the built-in chapters.
const Lessons = preload("res://src/game/tutorial_lessons.gd")
const Document = preload("res://src/tutorial_editor/tutorial_document.gd")

func _initialize() -> void:
	var update := "--update-examples" in OS.get_cmdline_user_args()
	for category in Lessons.IDS:
		var data: Dictionary = Document.encode({"format":"slay-tutorial", "version":1,
			"title":Lessons.category_title(category), "category":category,
			"opponent_mode":"ai" if category == "practice" else "scripted",
			"require_victory":category == "practice", "map":Lessons.Scenarios.map_data(category),
			"steps":Lessons.authored_steps(category)})
		var error := Document.validate(data)
		if error != "":
			push_error(category + ": " + error)
			quit(1)
			return
		var path := "res://tools/tutorial-editor/examples/%s.tutorial.json" % category
		var contents := JSON.stringify(data, "\t") + "\n"
		if update:
			var file := FileAccess.open(path, FileAccess.WRITE)
			file.store_string(contents)
			file.close()
		elif FileAccess.get_file_as_string(path) != contents:
			push_error("Outdated tutorial example: " + category)
			quit(1)
			return
	print("Tutorial examples: %d %s." % [Lessons.IDS.size(), "updated" if update else "verified"])
	quit()
