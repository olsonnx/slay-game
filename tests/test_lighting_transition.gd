extends SceneTree
const Snapshot = preload("res://src/game/state_snapshot.gd")
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(message)
func energy(controller) -> float:
	var value := 0.0
	for light in controller.accents: value += light.light_energy
	return value
func run() -> void:
	root.get_node("Video").set_preference(&"level_transitions",false,false)
	root.get_node("Video").set_preference(&"atmospheric_lighting",true,false)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	await process_frame
	await process_frame
	var view = game.view
	var lighting = view.lighting
	view.zoom = 12
	view.focus = view.coord_position(game.rules.kingdoms.keys()[0])
	view.update_camera()
	lighting.advance(1.0)
	var state := Snapshot.capture(game.rules)
	var uploads: int = view.unit_batches.upload_count
	var rebuilds: int = view.static_batches.rebuild_count
	var full := energy(lighting)
	expect(full > 0.0,"Nearby accents reach their intended intensity")
	view.zoom = 30
	view.update_camera()
	expect(is_equal_approx(energy(lighting),full),"Zoom starts fading from existing intensity without a jump")
	lighting.advance(0.07)
	var partial := energy(lighting)
	expect(partial > 0 and partial < full,"Lights have intermediate fade-out intensity")
	view.zoom = 12
	view.update_camera()
	expect(is_equal_approx(energy(lighting),partial),"Reversing zoom preserves the current intensity")
	lighting.advance(0.07)
	expect(energy(lighting) > partial,"Lights reverse smoothly toward their original intensity")
	view.zoom = 24
	view.update_camera()
	lighting.advance(1.0)
	expect(energy(lighting) > 0 and energy(lighting) < full,"Zoom band has a continuously reduced settled intensity")
	view.zoom = 40
	view.update_camera()
	lighting.advance(1.0)
	expect(is_zero_approx(energy(lighting)) and not lighting.is_processing(),"Distant lights finish fading and the controller sleeps")
	view.zoom = 12
	lighting.sources.assign([{"position":view.focus+Vector3(0,0.6,0),"mana":true}])
	view.update_camera()
	lighting.advance(1.0)
	var light: OmniLight3D = lighting.accents[0]
	var position := light.position
	lighting.sources.assign([{"position":view.focus+Vector3(1,0.6,0),"mana":false}])
	lighting.update_camera()
	lighting.advance(0.07)
	expect(light.position == position and light.light_energy > 0,"A replaced light fades at its previous source before relocating")
	lighting.advance(0.3)
	expect(light.position != position,"A replacement source is assigned after fade-out")
	lighting.advance(1.0)
	expect(view.static_batches.rebuild_count == rebuilds and view.unit_batches.upload_count == uploads,"Zoom fades do not rebuild terrain or army buffers")
	view.value_heatmap.set_active(true)
	expect(is_zero_approx(energy(lighting)) or not light.visible,"Heatmap suppresses accents immediately")
	view.value_heatmap.set_active(false)
	view.zoom = 64
	view.update_camera()
	var before: float = view.sun.shadow_opacity
	lighting.advance(0.025)
	expect(view.sun.shadow_opacity < before and view.sun.shadow_opacity > lighting.shadow_target,"Shadows ease through intermediate strengths")
	expect(view.sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL,"The shadow projection stays stable")
	expect(Snapshot.capture(game.rules) == state,"Fades do not change gameplay or RNG")
	game.queue_free()
	await process_frame
	root.get_node("Sound").stop_all()
	await create_timer(1.1).timeout
	print("Lighting transition checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
