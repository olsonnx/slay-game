extends SceneTree
## Native gallery built from the game's real tooltip callbacks and values.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(960, 620)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	root.get_node("Sound").set_muted(true, false)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_rule_mode = "modern"
	game.initial_seed = 42
	root.add_child(game)
	game.set_process(false)
	var capital: Vector2i = game.active_capital()
	game.cells[capital]["unit"] = 3
	game.view.render_cells(game.cells)
	game.refresh_ui()
	if "--native-hover" in OS.get_cmdline_user_args():
		game.open_shop("recruit")
		game.shop_panel.reveal = 1
		for frame in range(4):
			await process_frame
		var card: Button = game.shop_items.get_child(2)
		var motion := InputEventMouseMotion.new()
		motion.position = card.get_global_rect().get_center()
		motion.global_position = motion.position
		root.push_input(motion, true)
		await create_timer(1.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://artifacts/tooltip_native_hover.png")
		game.shutdown()
		game.queue_free()
		await process_frame
		quit()
		return
	var samples: Array[Control] = [game.gold_control._make_custom_tooltip(game.gold_control.tooltip_text), game.mana_control._make_custom_tooltip(game.mana_control.tooltip_text)]
	for kind in ["recruit", "build", "spells"]:
		game.open_shop(kind)
		var card: Button = game.shop_items.get_child(2 if kind == "recruit" else 1 if kind == "build" else 3)
		samples.append(card._make_custom_tooltip(card.tooltip_text))
	game.cancel_action()
	game.hovered = capital
	game.show_world_tip()
	samples.append(game.Tooltip.create(game.tip_label.get_parsed_text()))
	var backdrop := ColorRect.new()
	backdrop.color = Color("101d24")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.ui_root.add_child(backdrop)
	game.label_at(backdrop, "Compact tooltips", Vector2(24, 28), 24)
	for index in range(samples.size()):
		var frame := PanelContainer.new()
		frame.add_theme_stylebox_override("panel", game.UiTheme.style(Color("17252a"), 8, true))
		backdrop.add_child(frame)
		frame.add_child(samples[index])
		frame.position = Vector2(24 + (index % 3) * 312, 98 + (index / 3) * 240)
	for frame in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/tooltip_gallery.png")
	game.shutdown()
	game.queue_free()
	await process_frame
	quit()
