@tool
extends EditorExportPlugin
## JSON is not imported as a Godot resource, so include registered packs explicitly.

func _get_name() -> String:
	return "LocalizationPacks"

static func files_to_export(manifest_path := "res://localization/languages.json") -> PackedStringArray:
	var files := PackedStringArray([manifest_path, "res://localization/languages/en.json"])
	var manifest_file := FileAccess.open(files[0], FileAccess.READ)
	if manifest_file == null: return files
	var paths = JSON.parse_string(manifest_file.get_as_text())
	if not paths is Array: return files
	for path in paths:
		if path is String and path.begins_with("res://") and FileAccess.file_exists(path):
			if path not in files: files.append(path)
			var pack_file := FileAccess.open(path, FileAccess.READ)
			var pack = JSON.parse_string(pack_file.get_as_text())
			if pack is Dictionary and pack.get("font") is String:
				var font_path: String = pack["font"]
				if font_path.begins_with("res://") and FileAccess.file_exists(font_path) and font_path not in files:
					files.append(font_path)
	return files

func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	for path in files_to_export():
		if FileAccess.file_exists(path): add_file(path, FileAccess.get_file_as_bytes(path), false)
