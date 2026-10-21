extends RefCounted
const Loc = preload("res://src/localization/text.gd")
## Gestures and shortcuts; the controller retains all game state and mutations.
var game

func _init(controller) -> void:
	game = controller

func _input(event: InputEvent) -> void:
	if not game.pending_capital_relocation.is_empty() and game.event_shade.visible:
		if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or Keys.matches(event, "cancel")) or event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			game.resolve_capital_relocation(1)
			game.get_viewport().set_input_as_handled()
		return
	if game.input_suspended():
		return
	# Tab must reach gameplay before Godot's default focus navigation.
	if event is InputEventKey and event.pressed and not event.echo and Keys.matches(event, "view") and not game.hud.stats_shade.visible and game.can_navigate():
		game.activate_ui(game.toggle_view)
		game.get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and Keys.matches(event, "develop") and game.province_view.visible and game.session.selection.inspected_hex != game.NONE and not game.hud.stats_shade.visible and not game.commands_locked():
		game.activate_ui(game.develop_province)
		game.get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		game.mmb_down = false
	if event is InputEventMouseMotion and game.mmb_down:
		if game.view.controls_enabled and game.can_navigate():
			game.view.drag_pan(event.relative)
			game.get_viewport().set_input_as_handled()
	# Track release globally, including over UI; distinguish a click from an orbit.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			game.rmb_down = true
			game.rmb_dragged = false
			game.rmb_can_rotate = false
			game.rmb_travel = Vector2.ZERO
		else:
			var cancel_click: bool = game.rmb_down and not game.rmb_dragged
			game.rmb_down = false
			game.rmb_can_rotate = false
			game.view.rotating = false
			if cancel_click and not game.view.level_transitioning and not game.inspecting_results_map:
				game.cancel_action()
				game.get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and game.rmb_down:
		var was_dragged: bool = game.rmb_dragged
		game.rmb_travel += event.relative
		game.rmb_dragged = game.rmb_dragged or game.rmb_travel.length() >= game.ROTATE_THRESHOLD
		if game.rmb_can_rotate and game.rmb_dragged:
			game.view.rotating = true
			game.view.orbit(event.relative if was_dragged else game.rmb_travel)
			game.refresh_view_button()
			game.get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_instance_valid(game.view):
		reset_camera_gesture()

func _unhandled_input(event: InputEvent) -> void:
	if game.input_suspended():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				game.mmb_down = game.view.controls_enabled and game.can_navigate()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				game.rmb_can_rotate = not game.hud.stats_shade.visible and game.can_navigate()
				if game.rmb_can_rotate: game.view.zoom_reference = event.position
		elif event.pressed and not game.hud.stats_shade.visible and game.can_navigate():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				game.view.change_zoom(1, event.position)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				game.view.change_zoom(-1, event.position)
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if game.inspecting_results_map: return
				var hit: Dictionary = game.view.pick_at_screen(event.position, game.session.selection.action_mode == "bridge")
				game.click_hex(hit["coord"], hit["kind"])
	if event is InputEventKey and event.pressed and not event.echo:
		if game.inspecting_results_map:
			if event.keycode == KEY_ESCAPE or Keys.matches(event, "cancel"):
				game.open_pause()
				game.get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE or Keys.matches(event, "cancel"):
			if game.has_cancellable_action():
				game.cancel_action()
			else:
				game.activate_ui(game.open_pause)
			game.get_viewport().set_input_as_handled()
		elif not game.hud.stats_shade.visible and game.can_navigate():
			if select_shop_choice(event):
				game.get_viewport().set_input_as_handled()
			elif Keys.matches(event, "recruit"):
				game.activate_ui(game.open_shop.bind("recruit"))
			elif Keys.matches(event, "build"):
				game.activate_ui(game.open_shop.bind("build"))
			elif Keys.matches(event, "spells") and game.rules.is_modern():
				game.activate_ui(game.open_shop.bind("spells"))
			elif Keys.matches(event, "view"):
				game.activate_ui(game.toggle_view)
			elif Keys.matches(event, "heatmap"):
				game.activate_ui(game.toggle_value_heatmap)
			elif Keys.matches(event, "end_turn") and not game.busy and not game.game_over:
				game.activate_ui(game.end_turn)

func select_shop_choice(event: InputEventKey) -> bool:
	if not game.hud.shop_panel.visible or game.commands_locked():
		return false
	for slot in range(3):
		if not Keys.matches(event, "choice_%d" % (slot + 1)):
			continue
		var index: int = slot
		if (game.hud.shop_kind == "spells" or slot < 3) and index < game.hud.shop_items.get_child_count():
			game.hud.shop_items.get_child(index).pressed.emit()
		return true
	return false

func begin_view_press() -> void:
	game.view_press_held = true
	game.view_press_consumed = false
	game.view_press_time = 0.0
	game.hud.view_hold_indicator.progress = 0.0

func end_view_press() -> void:
	game.view_press_held = false
	game.hud.view_hold_indicator.progress = 0.0

func cancel_view_press() -> void:
	game.view_press_held = false
	game.view_press_consumed = true
	game.hud.view_hold_indicator.progress = 0.0

func advance_view_press(delta: float) -> void:
	if not game.view_press_held:
		return
	if game.hud.view_button.disabled or game.get_tree().paused:
		cancel_view_press()
		return
	if game.view_press_consumed:
		return
	game.view_press_time += delta
	game.hud.view_hold_indicator.progress = game.view_press_time / game.VIEW_HOLD_SECONDS
	if game.view_press_time >= game.VIEW_HOLD_SECONDS:
		game.view_press_consumed = true
		game.activate_ui(game.center_camera)

func view_button_activated() -> void:
	if not game.view_press_consumed and not game.hud.view_button.disabled and not game.get_tree().paused:
		game.activate_ui(game.toggle_view)

func reset_camera_gesture() -> void:
	game.mmb_down = false
	cancel_view_press()
	game.rmb_down = false
	game.rmb_can_rotate = false
	game.rmb_dragged = false
	game.rmb_travel = Vector2.ZERO
	game.view.rotating = false
