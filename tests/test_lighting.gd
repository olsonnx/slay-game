extends SceneTree
const Snapshot = preload("res://src/game/state_snapshot.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func run() -> void:
	root.size = Vector2i(960,620)
	var video = root.get_node("Video")
	video.set_preference(&"level_transitions",false,false)
	video.set_preference(&"atmospheric_lighting",true,false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	var view = game.view
	var before := Snapshot.capture(game.rules)
	var tiles: Dictionary = view.tile_nodes.duplicate()
	var unit_uploads: int = view.unit_batches.upload_count
	var scene_env: Environment = view.background_environment
	var options = load("res://src/ui/options_view.gd").new()
	options.theme = preload("res://src/ui/ui_theme.gd").create_theme()
	root.add_child(options)
	await process_frame
	video.set_preference(&"atmospheric_lighting", false, false)
	expect(not video.atmospheric_lighting and view.lighting.style == "simple","Options switches the live board to Simple immediately")
	expect(view.sun.rotation_degrees.is_equal_approx(Vector3(-52,-32,0)) and is_equal_approx(view.sun.light_energy,0.94) and is_equal_approx(scene_env.ambient_light_energy,0.48) and scene_env.ambient_light_color == Color("b8c8d1") and not scene_env.adjustment_enabled,"Simple uses the brighter sun and ambient fill without atmospheric grading")
	expect(view.unit_batches.shadow_material.albedo_texture == view.shadow_texture,"Simple restores original unit contact shadows")
	video.set_preference(&"atmospheric_lighting", true, false)
	expect(video.atmospheric_lighting and scene_env.adjustment_enabled and scene_env.adjustment_color_correction != null and scene_env.ambient_light_energy < 0.42,"Atmospheric restores directional contrast and shared colour grading")
	expect(view.unit_batches.shadow_material.albedo_texture != view.shadow_texture,"Atmospheric uses deeper contact shadows")
	expect(Snapshot.capture(game.rules) == before and tiles == view.tile_nodes and view.unit_batches.upload_count == unit_uploads,"Switching styles preserves gameplay, tiles, RNG and army instance buffers")
	view.zoom = 12
	view.focus = view.coord_position(game.rules.kingdoms.keys()[0])
	view.update_camera()
	view.lighting.refresh_sources()
	view.lighting.advance(1.0)
	var lit := 0
	for light in view.lighting.accents:
		lit += int(light.visible)
		expect(not light.shadow_enabled,"Accent lights add no shadow passes")
	expect(lit > 0 and lit <= 3,"Close view has a bounded number of nearby accents")
	view.zoom = 45
	view.update_camera()
	view.lighting.advance(1.0)
	for light in view.lighting.accents: expect(not light.visible,"Overview disables small light accents")
	view.zoom = 12
	view.update_camera()
	view.value_heatmap.set_active(true)
	for light in view.lighting.accents: expect(not light.visible,"Heatmap disables local lighting accents")
	view.value_heatmap.set_active(false)
	view.set_active(false)
	for light in view.lighting.accents: expect(not light.visible,"Inactive boards disable their accents")
	video.set_preference(&"atmospheric_lighting",false,false)
	view.set_active(true)
	expect(view.lighting.style == "simple","Reactivating a board applies preferences changed while hidden")
	var decor = load("res://src/rendering/decorative_map.gd").new()
	decor.initial_seed = 42
	root.add_child(decor)
	decor.apply_background()
	expect(is_equal_approx(decor.sun.light_energy,0.94),"Menu scenery uses Simple too")
	video.set_preference(&"atmospheric_lighting",true,false)
	decor.apply_background()
	expect(decor.environment.adjustment_enabled and is_equal_approx(decor.sun.light_energy,view.sun.light_energy),"Menu and board share the same atmospheric art direction")
	var window = view.material(Color("f9d892"))
	expect(window.emission_enabled,"Atmospheric windows emit a restrained warm highlight")
	video.set_preference(&"atmospheric_lighting",false,false)
	expect(not window.emission_enabled,"Simple also restores original window materials")
	for material in view.static_batches.materials.values():
		if material.get_meta("lighting_role","") == "window": expect(not material.emission_enabled,"Batched windows switch back to Simple too")
	var preferences_path := "res://artifacts/test-lighting-settings.cfg"
	var original_path: String = video.settings_path
	video.settings_path = preferences_path
	expect(video.flush_settings() == OK,"Simple preference saves successfully")
	video.set_preference(&"atmospheric_lighting",true,false)
	expect(video.load_settings(preferences_path) == OK and not video.atmospheric_lighting,"Saved Simple preference survives a reload")
	video.settings_path = original_path
	DirAccess.remove_absolute(preferences_path)
	video.set_preference(&"atmospheric_lighting",true,false)
	video.set_preference(&"atmospheric_lighting","invalid",false)
	expect(video.atmospheric_lighting,"Invalid lighting preferences are rejected")
	decor.queue_free()
	options.queue_free()
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Lighting checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
