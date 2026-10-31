extends SceneTree
## Build lightweight event banners; retain the untouched Collection originals.
const Events = preload("res://src/game/event_catalog.gd")
const SIZE := Vector2i(1024,512)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/paintings/previews")
	DirAccess.make_dir_recursive_absolute("res://assets/paintings/thumbnails")
	var definitions: Array = Events.EVENTS.values()
	definitions.append(Events.DEFAULT_PAINTING)
	var records := {}
	for definition in definitions:
		var artwork := Events.artwork(definition)
		if not artwork.has("painting"): continue
		var focus := Events.painting_focus(artwork)
		var key: String = artwork.painting+"|%d,%d" % [roundi(focus.x*100),roundi(focus.y*100)]
		if records.has(key): continue
		var source := Image.load_from_file(artwork.painting)
		if source == null or source.is_empty():
			push_error("Could not read painting: "+artwork.painting)
			quit(1)
			return
		var height := mini(source.get_height(),source.get_width()/2)
		var crop_size := Vector2i(height*2,height)
		var origin := Vector2i((Vector2(source.get_size())*focus-Vector2(crop_size)*0.5).round())
		origin = origin.clamp(Vector2i.ZERO,source.get_size()-crop_size)
		var image := source.get_region(Rect2i(origin,crop_size))
		image.resize(SIZE.x,SIZE.y,Image.INTERPOLATE_LANCZOS)
		var path: String = "res://assets/paintings/previews/"+key.sha256_text().substr(0,16)+".webp"
		var error := image.save_webp(path,true,0.90)
		if error != OK:
			push_error("Could not save event preview: "+error_string(error))
			quit(1)
			return
		var thumbnail := source.duplicate() as Image
		var thumbnail_scale := minf(1.0,512.0/maxi(source.get_width(),source.get_height()))
		thumbnail.resize(maxi(1,roundi(source.get_width()*thumbnail_scale)),maxi(1,roundi(source.get_height()*thumbnail_scale)),Image.INTERPOLATE_LANCZOS)
		var thumbnail_path: String = "res://assets/paintings/thumbnails/"+String(artwork.painting).sha256_text().substr(0,16)+".webp"
		if thumbnail.save_webp(thumbnail_path,true,0.90) != OK:
			push_error("Could not save gallery thumbnail")
			quit(1)
			return
		records[key] = {"source":artwork.painting,"focus":[roundi(focus.x*100),roundi(focus.y*100)],"preview":path,"thumbnail":thumbnail_path}
		print("Prepared event banner: ",artwork.get("painting_title",artwork.painting))
	var file := FileAccess.open("res://resources/art/event_previews.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"size":[SIZE.x,SIZE.y],"quality":0.90,"paintings":records},"\t")+"\n")
	print("Event previews built: ",records.size())
	quit()
