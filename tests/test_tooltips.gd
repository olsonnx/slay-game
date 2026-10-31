extends SceneTree
const Tooltip = preload("res://src/ui/compact_tooltip.gd")
const Widgets = preload("res://src/ui/tooltip_widgets.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func hover(button: Button) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = button.get_global_rect().get_center()
	motion.global_position = motion.position
	root.push_input(motion,true)
	await create_timer(0.8).timeout
	await process_frame
func popups() -> Array:
	return root.find_children("*","PopupPanel",true,false).filter(func(panel): return panel.visible)
func run() -> void:
	for value in ["", "   ", "\n\t"]:
		expect(Tooltip.create(value) == null and Tooltip.create(value,true) == null,"Blank tooltip text creates no content, including event outcomes")
	var controls: Array = [preload("res://src/ui/tooltip_button.gd").new(),preload("res://src/ui/tooltip_control.gd").new(),Widgets.Choice.new(),Widgets.Toggle.new(),Widgets.Checkbox.new(),Widgets.RangeSlider.new()]
	for control in controls:
		var shown := [0]
		if control.has_signal("tooltip_shown"): control.tooltip_shown.connect(func(): shown[0] += 1)
		expect(control._make_custom_tooltip("") == null,"Shared tooltip controls suppress empty callbacks")
		expect(shown[0] == 0,"Empty hover does not count as inspecting a tooltip")
		var content: Control = control._make_custom_tooltip("Useful help")
		expect(content != null and content.get_child(0).get_parsed_text() == "Useful help","Nonempty tooltip text remains visible")
		if control.has_signal("tooltip_shown"): expect(shown[0] == 1,"Real tooltip still emits the inspection signal")
		content.free()
		control.free()
	root.get_node("Sound").set_muted(true,false)
	root.get_node("Video").set_preference(&"depth_of_field",false,false)
	var app = load("res://scenes/app.tscn").instantiate()
	app.onboarding_enabled = false
	root.add_child(app)
	await app.startup_finished
	await process_frame
	var quick: Button = app.menus.main_panel.get_children().filter(func(child): return child is Button and child.text == "Quick Play")[0]
	await hover(quick)
	expect(popups().is_empty(),"Actual Quick Play hover shows no empty popup")
	await hover(app.menus.campaign_button)
	var panels := popups()
	expect(panels.size() == 1,"Disabled Campaign button still shows its explanation")
	if panels.size() == 1:
		var labels: Array = panels[0].find_children("*","RichTextLabel",true,false)
		expect(labels.size() == 1 and labels[0].get_parsed_text() == app.menus.campaign_button.tooltip_text,"Campaign tooltip contains its coming-update explanation")
	await hover(quick)
	expect(popups().is_empty(),"Moving from Campaign to Quick Play dismisses the explanation without a blank replacement")
	await hover(app.menus.main_utilities[0])
	panels = popups()
	expect(panels.size() == 1,"Icon-only menu button retains its tooltip")
	if panels.size() == 1:
		var labels: Array = panels[0].find_children("*","RichTextLabel",true,false)
		expect(labels.size() == 1 and labels[0].get_parsed_text() == "Level editor","Menu icon tooltip keeps its readable label")
	app.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.2).timeout
	print("Tooltip checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
