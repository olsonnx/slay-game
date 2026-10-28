extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var video = root.get_node("Video")
	var original_resolution: Vector2i = video.resolution
	var original_fullscreen: bool = video.fullscreen
	for value in video.RESOLUTIONS:
		expect(value.x * 9 == value.y * 16, "Every offered resolution has a 16:9 aspect ratio")
	video.set_preference(&"fullscreen", true, false)
	video.set_preference(&"resolution", Vector2i(1280,720), false)
	expect(is_equal_approx(video.render_scale(Vector2i(1920,1080)), 2.0/3.0), "720p fullscreen lowers scene resolution on a 1080p display")
	video.set_preference(&"resolution", Vector2i(1920,1080), false)
	expect(video.render_scale(Vector2i(1920,1080)) == 1.0, "Native fullscreen resolution restores full scene quality")
	var options = load("res://src/ui/options_view.gd").new()
	root.add_child(options)
	expect(not options.resolution_choice.disabled, "Resolution remains available in fullscreen")
	options.resolution_choice.item_selected.emit(1)
	expect(video.resolution == Vector2i(1600,900) and video.fullscreen, "Changing the fullscreen dropdown applies without leaving fullscreen")
	expect(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Wide screens gain visible space instead of black bars")
	video.set_preference(&"fullscreen", false, false)
	expect(root.scaling_3d_scale == 1.0, "Windowed rendering resets the fullscreen scale")
	var settings := ConfigFile.new()
	var path := "user://video-display-test.cfg"
	for legacy in [Vector2i(960,620), Vector2i(1280,820)]:
		settings.set_value("video", "resolution", legacy)
		settings.save(path)
		var migrated = load("res://src/settings/video_settings.gd").new()
		migrated.load_settings(path)
		expect(migrated.resolution == Vector2i(1280,720), "Old non-widescreen settings migrate to 720p")
		migrated.free()
	options.queue_free()
	await process_frame
	await process_frame
	# Dropdown actions save automatically; stop the timer before restoring state.
	video.save_timer.stop()
	video.set_preference(&"resolution", original_resolution, false)
	video.set_preference(&"fullscreen", original_fullscreen, false)
	print("Video display checks: %d passed, %d failed" % [checks-failures, failures])
	quit(1 if failures else 0)
