extends Node
## Standalone sandbox. Changes affect only this board and one lab save file.
const Board = preload("res://src/rendering/board_view.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const DOF = preload("res://src/rendering/depth_of_field.gd")
const SAVE_PATH := "user://lighting_lab.cfg"
var board
var fields: Dictionary = {}
var rows: VBoxContainer
var status: Label
var preset: OptionButton
var saved_a: Dictionary = {}
var rebuilding := false
var zoom_status: Label
var slider_captions: Dictionary = {}
var dof_heading: Label
var panel_scroll: ScrollContainer

func _ready() -> void:
	board = Board.new()
	add_child(board)
	board.controls_enabled = true
	var model = Rules.new()
	model.rule_mode = "modern"
	model.generate(71, "large", 6)
	board.configure_map(model.map_size, model.bridge_bounds(), model.cells)
	board.render_cells(model.cells)
	board.focus = board.coord_position(model.kingdoms.keys()[0])
	board.zoom = 18.0
	board.update_camera()
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -340
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	panel_scroll = scroll
	panel.add_child(scroll)
	rows = VBoxContainer.new()
	rows.custom_minimum_size.x = 315
	rows.add_theme_constant_override("separation", 9)
	scroll.add_child(rows)
	label("LIGHTING LAB", 24)
	label("Live preview • your real game map", 15)
	label("Drag: pan • Right drag: orbit\nWheel: zoom • sliders update immediately", 14)
	preset = OptionButton.new()
	for title in ["Atmospheric", "Daylight", "Simple"]: preset.add_item(title)
	rows.add_child(preset)
	preset.item_selected.connect(func(index): apply_preset(["atmospheric", "daylight", "simple"][index]))
	button("Reset selected preset", func(): apply_preset(["atmospheric", "daylight", "simple"][preset.selected]))
	button("Depth of field controls", func(): scroll.scroll_vertical = roundi(dof_heading.position.y))
	slider("sun_energy", "Sun strength", 0, 3, 0.02)
	slider("sun_pitch", "Sun elevation", -89, -5, 1)
	slider("sun_yaw", "Sun direction", -180, 180, 1)
	color_picker("sun_color", "Sun color")
	slider("ambient_energy", "Ambient / shadow fill", 0, 1.5, 0.01)
	color_picker("ambient_color", "Ambient color")
	check("shadows", "Cast shadows")
	slider("shadow_opacity", "Shadow darkness", 0, 1, 0.01)
	slider("softness", "Sun angular size", 0, 3, 0.05)
	check("sprites", "Light pixel characters")
	slider("normal_strength", "Scout normal strength (0 = original)", 0, 1, 0.01)
	check("normal_invert_y", "Invert scout normal Y")
	button("Inspect scout", inspect_scout)
	check("adjustments", "Color adjustments")
	slider("brightness", "Brightness", 0.5, 1.5, 0.01)
	slider("contrast", "Contrast", 0.5, 1.5, 0.01)
	slider("saturation", "Saturation", 0, 1.8, 0.01)
	check("grade", "Atmospheric color grading")
	check("ao", "Ambient occlusion (Forward+)")
	slider("ao_strength", "Occlusion strength", 0, 2, 0.02)
	dof_heading = label("DIORAMA DEPTH OF FIELD", 18)
	label("Lower zoom numbers mean a closer view.\nBlur fades in between the two zoom limits.", 13)
	check("dof_enabled", "Enable depth of field")
	slider("dof_clear_zoom", "Blur starts below zoom", 9, 40, 0.5)
	slider("dof_full_zoom", "Full blur below zoom", 8, 25, 0.5)
	slider("dof_amount", "Maximum blur", 0, 0.3, 0.005)
	slider("dof_sharp_band", "Sharp focus band", 0.1, 0.8, 0.01)
	slider("dof_transition", "Blur falloff", 0.2, 1.5, 0.05)
	slider("preview_zoom", "Preview zoom", 8, maxf(40, board.max_zoom), 0.1)
	zoom_status = label("", 14)
	button("Copy DOF settings", copy_dof_settings)
	board.navigation.changed.connect(sync_camera_controls)
	button("Close view", func(): board.zoom = 12; board.update_camera())
	button("Whole map", func(): board.focus = board.map_center; board.zoom = board.max_zoom; board.update_camera())
	button("Remember A", func(): saved_a = capture(); status.text = "A remembered for this session.")
	button("Swap A / current", swap_a)
	button("Save experiment", save_experiment)
	button("Load experiment", load_experiment)
	button("Copy settings", func(): DisplayServer.clipboard_set(JSON.stringify(capture(), "\t")); status.text = "Settings copied to clipboard.")
	status = label("Experiments do not change game defaults.", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	apply_preset("atmospheric")
	# The lab owns shadow opacity; normal gameplay fades it with zoom.
	board.lighting.set_process(false)
	if "--lab-smoke" in OS.get_cmdline_user_args(): smoke.call_deferred()

func label(text: String, size: int) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	rows.add_child(node)
	return node

func button(text: String, action: Callable) -> void:
	var node := Button.new()
	node.text = text
	node.pressed.connect(action)
	rows.add_child(node)

func slider(key: String, title: String, low: float, high: float, step: float) -> void:
	var caption := label(title, 14)
	var node := HSlider.new()
	node.min_value = low
	node.max_value = high
	node.step = step
	rows.add_child(node)
	fields[key] = node
	slider_captions[key] = [caption, title]
	node.value_changed.connect(func(value): caption.text = "%s  %.2f" % [title, value]; update_lighting())

func color_picker(key: String, title: String) -> void:
	label(title, 14)
	var node := ColorPickerButton.new()
	node.edit_alpha = false
	node.custom_minimum_size.y = 28
	rows.add_child(node)
	fields[key] = node
	node.color_changed.connect(func(_value): update_lighting())

func check(key: String, title: String) -> void:
	var node := CheckBox.new()
	node.text = title
	rows.add_child(node)
	fields[key] = node
	node.toggled.connect(func(_value): update_lighting())

func capture() -> Dictionary:
	var result := {"preset": preset.selected}
	for key in fields:
		var node = fields[key]
		result[key] = node.color.to_html() if node is ColorPickerButton else node.button_pressed if node is CheckBox else node.value
	return result

func restore(values: Dictionary) -> void:
	rebuilding = true
	for key in fields:
		if not values.has(key): continue
		var node = fields[key]
		if node is ColorPickerButton: node.color = Color(values[key])
		elif node is CheckBox: node.button_pressed = values[key]
		else: node.value = values[key]
	rebuilding = false
	update_lighting()

func apply_preset(style: String) -> void:
	board.lighting.apply_style(style)
	var sun: DirectionalLight3D = board.sun
	var env: Environment = board.background_environment
	restore({"sun_energy": sun.light_energy, "sun_pitch": sun.rotation_degrees.x, "sun_yaw": sun.rotation_degrees.y,
		"sun_color": sun.light_color.to_html(), "ambient_energy": env.ambient_light_energy, "ambient_color": env.ambient_light_color.to_html(),
		"shadows": sun.shadow_enabled, "shadow_opacity": 1.0, "softness": sun.light_angular_distance,
		"normal_strength": 0.65, "normal_invert_y": false, "sprites": style == "atmospheric", "adjustments": env.adjustment_enabled, "brightness": 1.0,
		"contrast": env.adjustment_contrast, "saturation": env.adjustment_saturation, "grade": style == "atmospheric",
		"ao": env.ssao_enabled, "ao_strength": env.ssao_intensity,
		"dof_enabled": DOF.DEFAULTS.enabled, "dof_clear_zoom": DOF.DEFAULTS.clear_zoom,
		"dof_full_zoom": DOF.DEFAULTS.full_zoom, "dof_amount": DOF.DEFAULTS.amount,
		"dof_sharp_band": DOF.DEFAULTS.sharp_band, "dof_transition": DOF.DEFAULTS.transition,
		"preview_zoom": board.zoom})

func update_lighting() -> void:
	if rebuilding: return
	var v := capture()
	var sun: DirectionalLight3D = board.sun
	var env: Environment = board.background_environment
	sun.light_energy = v.sun_energy
	sun.rotation_degrees = Vector3(v.sun_pitch, v.sun_yaw, 0)
	sun.light_color = Color(v.sun_color)
	sun.shadow_enabled = v.shadows
	sun.shadow_opacity = v.shadow_opacity
	sun.light_angular_distance = v.softness
	env.ambient_light_energy = v.ambient_energy
	env.ambient_light_color = Color(v.ambient_color)
	env.adjustment_enabled = v.adjustments
	env.adjustment_brightness = v.brightness
	env.adjustment_contrast = v.contrast
	env.adjustment_saturation = v.saturation
	env.adjustment_color_correction = preload("res://src/rendering/lighting_style.gd").color_grade() if v.grade else null
	env.ssao_enabled = v.ao and RenderingServer.get_current_rendering_method() == "forward_plus"
	env.ssao_intensity = v.ao_strength
	board.sprite_lighting.set_normal_options(v.normal_strength, v.normal_invert_y)
	board.sprite_lighting.set_enabled(v.sprites)
	board.unit_batches.refresh_sprite_lighting()
	# Keep the two limits ordered even while dragging either control.
	if v.dof_full_zoom >= v.dof_clear_zoom:
		v.dof_clear_zoom = v.dof_full_zoom + 0.5
		fields.dof_clear_zoom.set_value_no_signal(v.dof_clear_zoom)
	board.camera.set_meta("dof_settings", {
		"enabled": v.dof_enabled, "clear_zoom": v.dof_clear_zoom,
		"full_zoom": v.dof_full_zoom, "amount": v.dof_amount,
		"sharp_band": v.dof_sharp_band, "transition": v.dof_transition})
	board.stop_camera_pan()
	board.zoom = v.preview_zoom
	board.update_camera()
	for key in slider_captions:
		slider_captions[key][0].text = "%s  %.2f" % [slider_captions[key][1], fields[key].value]

func sync_camera_controls() -> void:
	if not fields.has("preview_zoom"): return
	fields.preview_zoom.set_value_no_signal(board.zoom)
	slider_captions.preview_zoom[0].text = "Preview zoom  %.1f" % board.zoom
	var amount: float = board.camera.attributes.dof_blur_amount
	var maximum: float = fields.dof_amount.value
	zoom_status.text = "Zoom %.1f | Blur %d%%" % [board.zoom, roundi(amount / maximum * 100.0) if maximum > 0 else 0]

func copy_dof_settings() -> void:
	DisplayServer.clipboard_set(JSON.stringify({"depth_of_field": board.camera.get_meta("dof_settings"), "preview_zoom": board.zoom}, "\t"))
	status.text = "DOF settings copied. Paste them in chat."

func swap_a() -> void:
	if saved_a.is_empty(): status.text = "Use Remember A first."; return
	var current := capture()
	select_and_restore(saved_a)
	saved_a = current
	status.text = "Swapped A and current lighting."

func select_and_restore(values: Dictionary) -> void:
	preset.select(clampi(int(values.get("preset", 0)), 0, 2))
	apply_preset(["atmospheric", "daylight", "simple"][preset.selected])
	restore(values)

func save_experiment() -> void:
	var config := ConfigFile.new()
	config.set_value("lighting", "settings", capture())
	var error := config.save(SAVE_PATH)
	status.text = "Experiment saved. Load it next time." if error == OK else "Save failed: %s" % error_string(error)

func load_experiment() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK: status.text = "No saved experiment yet."; return
	var values = config.get_value("lighting", "settings", {})
	if not values is Dictionary: status.text = "Invalid experiment file."; return
	select_and_restore(values)
	status.text = "Saved experiment loaded."

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT: board.orbit(event.relative)
		elif event.button_mask & MOUSE_BUTTON_MASK_LEFT: board.drag_pan(event.relative)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: board.change_zoom(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: board.change_zoom(-1)

func _process(_delta: float) -> void:
	# Accent lights still fade normally; keep the user's shadow setting fixed.
	if board != null:
		board.lighting.shadow_target = fields.shadow_opacity.value if fields.has("shadow_opacity") else 1.0
		board.sun.shadow_opacity = board.lighting.shadow_target

func smoke() -> void:
	for style in ["simple", "daylight", "atmospheric"]: apply_preset(style)
	fields.preview_zoom.value = 19.0
	assert(is_zero_approx(board.camera.attributes.dof_blur_amount))
	fields.dof_clear_zoom.value = 23.0
	assert(board.camera.attributes.dof_blur_amount > 0.0)
	fields.dof_amount.value = 0.22
	fields.sun_energy.value = 1.7
	saved_a = capture()
	fields.sun_energy.value = 0.4
	fields.dof_amount.value = 0.05
	swap_a()
	assert(is_equal_approx(board.sun.light_energy, 1.7))
	assert(is_equal_approx(fields.dof_amount.value, 0.22))
	save_experiment()
	fields.sun_energy.value = 0.2
	fields.dof_clear_zoom.value = 16.0
	load_experiment()
	assert(is_equal_approx(board.sun.light_energy, 1.7))
	assert(is_equal_approx(fields.dof_clear_zoom.value, 23.0) and board.camera.attributes.dof_blur_amount > 0.0)
	fields.dof_enabled.button_pressed = false
	assert(not board.camera.attributes.dof_blur_near_enabled and not board.camera.attributes.dof_blur_far_enabled)
	fields.dof_enabled.button_pressed = true
	fields.preview_zoom.value = 12.0
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.5).timeout
		panel_scroll.scroll_vertical = roundi(dof_heading.position.y)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/lighting-lab.png")
	print("Lighting lab checks passed")
	root_cleanup()

func root_cleanup() -> void:
	get_tree().root.get_node("Sound").stop_all()
	await get_tree().create_timer(1.1).timeout
	get_tree().quit()



func inspect_scout() -> void:
	for coord in board.unit_actors:
		var actor: Node3D = board.unit_actors[coord]
		if actor.get_node("UnitAnimation").tier == 1:
			board.stop_camera_pan()
			board.focus = board.coord_position(coord)
			board.zoom = 8.0
			board.update_camera()
			return
