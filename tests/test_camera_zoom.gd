extends SceneTree

const Rules = preload("res://src/game/kingdom_rules.gd")
const Grid = preload("res://src/game/hex_grid.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func finish_zoom(nav) -> void:
	for frame in range(90):
		nav._process(1.0 / 60.0)

func run() -> void:
	# This standalone SceneTree is parsed before the Gameplay autoload exists.
	var navigation = load("res://src/rendering/board_navigation.gd")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 800)
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	viewport.add_child(camera)
	var nav = navigation.new()
	nav.camera = camera
	viewport.add_child(nav)
	nav.set_process(false)
	await process_frame
	for size_id in ["small", "medium", "large", "very_large", "huge"]:
		var rules := Rules.new()
		rules.generate(71, size_id)
		for dimensions in [Vector2i(1200, 800), Vector2i(800, 1200)]:
			viewport.size = dimensions
			nav.configure_map(size_id, Vector2(100, 100), rules.cells)
			nav.reset_camera()
			for overhead in [false, true]:
				if overhead:
					nav.toggle_top_down()
				var screen := Vector2(dimensions) * Vector2(0.72, 0.63)
				var point: Vector3 = nav._ground_at(screen)
				var before: float = nav.zoom
				nav.change_zoom(1, screen)
				expect(nav.zoom == before, "Wheel input starts a smooth transition")
				nav._process(1.0 / 60.0)
				expect(nav.zoom < before and nav.zoom > nav.zoom_target, "Zoom advances gradually toward its target")
				expect(camera.unproject_position(point).distance_to(screen) < 0.05, "Pointer anchor stays fixed during zoom")
				finish_zoom(nav)
				expect(camera.unproject_position(point).distance_to(screen) < 0.05, "Pointer anchor stays fixed after zoom")
				nav.change_zoom(2, screen)
				nav.change_zoom(2, screen)
				expect(is_equal_approx(nav.zoom_target, maxf(8.0, nav.zoom * pow(0.88, 4))), "Fast wheel events accumulate smoothly")
				finish_zoom(nav)
				nav.focus += Vector3(10, 0, -7)
				nav.update_camera()
				nav.change_zoom(-100, screen)
				finish_zoom(nav)
				expect(is_equal_approx(nav.zoom, nav.max_zoom) and nav.focus.is_equal_approx(nav.map_center), "Maximum zoom-out centres the complete map")
				var fits := true
				var safe_rect := Rect2(Vector2(dimensions) * 0.04, Vector2(dimensions) * 0.92)
				for coord in rules.cells:
					for corner in [Vector3(-1, 0, -1), Vector3(1, 0, 1), Vector3(0, 2, 0)]:
						fits = fits and safe_rect.has_point(camera.unproject_position(Grid.to_world(coord) + corner))
				expect(fits, "Entire %s map has safe screen margins in %s, overhead=%s" % [size_id, dimensions, overhead])
				nav.change_zoom(1, screen)
				nav.reset_camera()
				finish_zoom(nav)
				expect(nav.zoom == nav.default_zoom and nav.focus == nav.map_center, "Reset cancels pending zoom")
	# Resize an existing map and rotate to a diagonal, shallow view.
	viewport.size = Vector2i(700, 1000)
	nav._process(0.016)
	nav.orbit(Vector2(120, -80))
	nav.change_zoom(-100, Vector2(300, 400))
	finish_zoom(nav)
	expect(nav.max_zoom >= nav._fit_zoom(nav.yaw, nav.pitch), "Zoom limit follows viewport size and orbit angle")
	for overhead in [false, true]:
		for steps in [3.0, -3.0]:
			for dragging in [false, true]:
				nav.reset_camera()
				if overhead: nav.toggle_top_down()
				nav.zoom = nav.max_zoom * 0.65
				nav.update_camera()
				var initial_zoom: float = nav.zoom
				var initial_focus: Vector3 = nav.focus
				nav.change_zoom(steps, Vector2(viewport.size) * 0.5)
				for frame in range(10):
					if dragging: nav.drag_pan(Vector2(3, 1))
					else: nav.pan(Vector2.RIGHT, 1.0 / 60.0)
					nav._process(1.0 / 60.0)
				expect(nav.zooming and not is_equal_approx(nav.zoom, initial_zoom), "Smooth zoom continues during keyboard and drag panning in both views")
				expect(nav.focus.distance_to(initial_focus) > 0.1, "Camera pans while zooming in either direction")
				var moved_focus: Vector3 = nav.focus
				finish_zoom(nav)
				expect(nav.focus.distance_to(moved_focus) < 0.001 and is_equal_approx(nav.zoom, nav.zoom_target), "Zoom finishes without pulling the manually moved camera back to centre")
	var reference_zoom := 0.0
	var reference_focus := Vector3.ZERO
	for fps in [30, 60, 120, 1500]:
		nav.reset_camera()
		nav.change_zoom(3, Vector2(450, 600))
		for frame in range(fps / 5):
			nav._process(1.0 / fps)
		if fps == 30:
			reference_zoom = nav.zoom
			reference_focus = nav.focus
		expect(absf(nav.zoom - reference_zoom) < 0.001 and nav.focus.distance_to(reference_focus) < 0.001, "Zoom duration and anchor are consistent at %d FPS" % fps)
	nav.change_zoom(100, Vector2(450, 600))
	finish_zoom(nav)
	expect(nav.zoom == 8.0, "Closest zoom retains its limit after rapid scrolling")
	viewport.queue_free()
	await process_frame
	print("Camera zoom checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
