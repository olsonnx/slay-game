extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.get_node("Sound").set_muted(true,false)
	root.get_node("Video").set_preference(&"depth_of_field",false,false)
	if "--fullscreen" in OS.get_cmdline_user_args():
		root.get_node("Video").set_preference(&"resolution",Vector2i(1920,1080),false)
		root.get_node("Video").set_preference(&"fullscreen",true,false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	for frame in range(4): await process_frame
	var buttons: Array = app.menus.main_utilities.duplicate()
	buttons.append(app.menus.main_panel.get_children().filter(func(child): return child is Button and child.text == "Quick Play")[0])
	buttons.append(app.menus.campaign_button)
	buttons.append(app.menus.profile_button)
	for index in range(buttons.size()):
		var button: Button = buttons[index]
		var motion := InputEventMouseMotion.new()
		motion.position = button.get_global_rect().get_center()
		motion.global_position = motion.position
		root.push_input(motion,true)
		await create_timer(0.9).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/menu-tooltip-%d.png" % index)
		for window in root.find_children("*","Window",true,false):
			if not window.visible: continue
			print("Popup for ",button.tooltip_text,": ",window.name," size ",window.size)
			for label in window.find_children("*","RichTextLabel",true,false):
				print("Text: ",label.text," size ",label.size," visible ",label.is_visible_in_tree()," height ",label.get_content_height())
	app.queue_free()
	await process_frame
	quit()
