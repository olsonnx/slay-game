extends Node
## Local, durable discovery progress. Event IDs never own a painting's identity.
const Events = preload("res://src/game/event_catalog.gd")
const DEFAULT_PATH := "user://painting_collection.cfg"
signal changed
signal save_failed(error: Error)
var settings_path := DEFAULT_PATH
var seen: Dictionary = {}
var dirty := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()

func entries() -> Array[Dictionary]:
	var unique := {}
	add_entry(unique, Events.DEFAULT_PAINTING)
	for definition in Events.EVENTS.values(): add_entry(unique, Events.artwork(definition))
	var result: Array[Dictionary] = []
	for entry in unique.values(): result.append(entry)
	result.sort_custom(func(a, b): return (a.artist + ":" + a.title + ":" + a.path).naturalnocasecmp_to(b.artist + ":" + b.title + ":" + b.path) < 0)
	return result

func add_entry(target: Dictionary, artwork: Dictionary) -> void:
	var path := String(artwork.get("painting", "")).simplify_path()
	if not valid_path(path) or target.has(path): return
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path): return
	target[path] = {"path":path,"title":String(artwork.get("painting_title", "")).strip_edges(),"artist":String(artwork.get("painting_artist", "")).strip_edges()}
	if target[path].title.is_empty(): target[path].title = path.get_file().get_basename().replace("_", " ")

static func valid_path(path: String) -> bool:
	return path.begins_with("res://assets/paintings/") and path.length() <= 1024 and path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "svg"]

func is_collected(path: String) -> bool:
	return seen.get(path.simplify_path(), false)

func discover(definition: Dictionary) -> bool:
	var artwork: Dictionary = Events.artwork(definition)
	var path := String(artwork.get("painting", "")).simplify_path()
	if not valid_path(path) or Events.painting_texture(path) == null: return false
	if is_collected(path):
		if dirty: flush_settings()
		return false
	seen[path] = true
	dirty = true
	flush_settings()
	changed.emit()
	return true

func collected_count() -> int:
	var count := 0
	for entry in entries(): count += int(is_collected(entry.path))
	return count

func load_settings(path := "") -> Error:
	var config := ConfigFile.new()
	var error := config.load(settings_path if path.is_empty() else path)
	seen.clear()
	dirty = false
	if error != OK: return error
	var saved = config.get_value("collection", "paintings", {})
	if saved is Dictionary and saved.size() <= 10000:
		for key in saved:
			if key is String and valid_path(key.simplify_path()) and saved[key] is bool and saved[key]: seen[key.simplify_path()] = true
	return OK

func flush_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("collection", "paintings", seen)
	var error := config.save(settings_path)
	dirty = error != OK
	if error != OK: save_failed.emit(error)
	return error
