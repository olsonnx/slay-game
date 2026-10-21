extends Node
## Standalone sandbox. Changes affect only this board and one lab save file.
const Board = preload("res://src/rendering/board_view.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const SAVE_PATH := "user://lighting_lab.cfg"
var board
var fields: Dictionary = {}
var rows: VBoxContainer
var status: Label
var preset: OptionButton
var saved_a: Dictionary = {}
var rebuilding := false

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
		"ao": env.ssao_enabled, "ao_strength": env.ssao_intensity})

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
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: board.change_zoom(-1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: board.change_zoom(1)

func _process(_delta: float) -> void:
	# Accent lights still fade normally; keep the user's shadow setting fixed.
	if board != null:
		board.lighting.shadow_target = fields.shadow_opacity.value if fields.has("shadow_opacity") else 1.0
		board.sun.shadow_opacity = board.lighting.shadow_target

func smoke() -> void:
	for style in ["simple", "daylight", "atmospheric"]: apply_preset(style)
	fields.sun_energy.value = 1.7
	saved_a = capture()
	fields.sun_energy.value = 0.4
	swap_a()
	assert(is_equal_approx(board.sun.light_energy, 1.7))
	save_experiment()
	fields.sun_energy.value = 0.2
	load_experiment()
	assert(is_equal_approx(board.sun.light_energy, 1.7))
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://artifacts/lighting-lab.png")
	print("Lighting lab checks passed")
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
