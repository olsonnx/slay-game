extends SceneTree
## Refresh the shipped editor examples explicitly from the live templates.
func _initialize() -> void:
	if not "--update-examples" in OS.get_cmdline_user_args():
		push_error("Pass --update-examples to overwrite the built-in example pack.")
		quit(1)
		return
	var examples: Array = []
	for id in preload("res://src/game/event_catalog.gd").BUILTIN_EVENTS:
		var data: Dictionary = preload("res://src/event_editor/event_templates.gd").template(id)
		data.id = id + "_example"
		examples.append(data)
	var file := FileAccess.open("res://tools/event-editor/examples/builtin-templates.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"events":examples}, "\t") + "\n")
	file.close()
	print("Exported %d event examples." % examples.size())
	quit()
