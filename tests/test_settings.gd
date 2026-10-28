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
	var gameplay = root.get_node("Gameplay")
	var sound = root.get_node("Sound")
	video.settings_path = "user://settings-video-test.cfg"
	gameplay.settings_path = "user://settings-gameplay-test.cfg"
	sound.settings_path = "user://settings-audio-test.cfg"
	video.set_preference(&"frame_limit",60,false)
	video.set_preference(&"background_frame_limit",120,false)
	video._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(Engine.max_fps == 60,"Losing focus cannot raise the active frame limit")
	video.set_preference(&"background_frame_limit",30,false)
	expect(Engine.max_fps == 30,"Unfocused frame limit reduces rendering work")
	video._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	expect(Engine.max_fps == 60,"Focus restores the foreground limit")
	video.set_preference(&"ui_scale",1.5,false)
	await process_frame
	await process_frame
	expect(root.get_visible_rect().size.y >= 619 and root.get_visible_rect().size.x >= 959,"UI scaling keeps the complete minimum-size interface accessible")
	video.set_preference(&"ui_scale",NAN,false)
	video.set_preference(&"frame_limit",-1,false)
	expect(video.ui_scale == 1.5 and video.frame_limit == 60,"Malformed scaling and frame limits are rejected")
	video.set_preference(&"tooltip_delay",0.25,false)
	expect(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec") == 0.25,"Tooltip timing applies immediately")
	video.flush_settings()
	var loaded = load("res://src/settings/video_settings.gd").new()
	loaded.load_settings(video.settings_path)
	expect(loaded.ui_scale == 1.5 and loaded.tooltip_delay == 0.25 and loaded.frame_limit == 60,"New display settings survive a saved-file round trip")
	loaded.free()
	gameplay.set_preference("camera_speed",1.5,false)
	gameplay.set_preference("invert_zoom",true,false)
	gameplay.set_preference("playback_speed",2.0,false)
	gameplay.flush_settings()
	var saved_gameplay = load("res://src/settings/gameplay_settings.gd").new()
	saved_gameplay.load_settings(gameplay.settings_path)
	expect(saved_gameplay.camera_speed == 1.5 and saved_gameplay.invert_zoom and saved_gameplay.playback_speed == 2.0,"Camera and playback preferences persist separately from match rules")
	saved_gameplay.free()
	var navigation = load("res://src/rendering/board_navigation.gd").new()
	root.add_child(navigation)
	var camera := Camera3D.new()
	root.add_child(camera)
	navigation.camera = camera
	gameplay.set_preference("camera_speed",1.0,false)
	navigation.pan(Vector2(1,0),0.1)
	var distance: float = navigation.focus.length()
	navigation.focus = Vector3.ZERO
	gameplay.set_preference("camera_speed",2.0,false)
	navigation.pan(Vector2(1,0),0.1)
	expect(is_equal_approx(navigation.focus.length(),distance*2.0),"Camera sensitivity changes actual pan distance")
	navigation.zoom = 10.0
	navigation.change_zoom(1)
	expect(navigation.zoom_target > navigation.zoom,"Inverting scroll changes the actual zoom direction")
	video.set_preference(&"depth_of_field",false,false)
	navigation.zoom = 8.0
	navigation.update_camera()
	expect(not camera.attributes.dof_blur_near_enabled and not camera.attributes.dof_blur_far_enabled,"Disabling depth of field removes near and far blur")
	video.set_preference(&"reduced_motion",true,false)
	navigation.smooth_pan_to(Vector3(1,0,1))
	expect(navigation.focus == Vector3(1,0,1),"Reduced motion skips automatic camera animation")
	sound.set_muted(false,false)
	sound.set_mute_unfocused(true,false)
	sound._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(sound.is_muted(),"Unfocused audio setting silences the master bus")
	sound.save_settings(sound.settings_path)
	var audio_file := ConfigFile.new()
	audio_file.load(sound.settings_path)
	expect(not audio_file.get_value("audio","muted"),"Temporary focus mute does not overwrite the user's mute preference")
	sound._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	expect(not sound.is_muted(),"Audio restores on return to the game")
	var options = load("res://src/ui/options_view.gd").new()
	root.add_child(options)
	expect(options.get_child(0).tab_count == 5 and options.interface_page != null,"Interface settings have their own tab")
	for page in [options.audio_page,options.video_page,options.gameplay_page,options.interface_page]:
		expect(page.get_child(0) is ScrollContainer,"Settings pages scroll instead of overflowing the options panel")
	gameplay.completed_tutorials["settings_test"] = true
	options.restore_tab(4)
	expect(video.ui_scale == 1.0 and not video.reduced_motion and gameplay.playback_speed == 2.0 and gameplay.completed_tutorials.has("settings_test"),"Interface reset preserves other categories and tutorial progress")
	options.restore_tab(2)
	expect(gameplay.playback_speed == 1.0 and gameplay.camera_speed == 1.0 and not gameplay.invert_zoom,"Gameplay reset restores camera and playback defaults")
	options.restore_tab(1)
	options.restore_tab(0)
	sound.stop_all()
	options.queue_free()
	navigation.queue_free()
	camera.queue_free()
	await process_frame
	await create_timer(1.2).timeout
	print("Settings checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
