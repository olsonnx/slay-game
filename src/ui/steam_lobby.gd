extends Panel
const Loc = preload("res://src/localization/text.gd")
const Hud = preload("res://src/ui/game_hud.gd")
const Sizes = preload("res://src/game/map_sizes.gd")
signal back_requested
var connection
var status_label: Label
var roster_label: Label
var host_button: Button
var invite_button: Button
var ready_button: Button
var start_button: Button
var leave_button: Button
var size_choice: OptionButton
var count_choice: OptionButton

func _ready() -> void:
	connection = get_tree().root.get_node("SteamOnline")
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -300
	offset_right = 300
	offset_top = -280
	offset_bottom = 280
	add_theme_stylebox_override("panel", Hud.style(Color("17252a"), 13, true))
	Hud.label_at(self, "Steam multiplayer", Vector2(24, 20), 28)
	status_label = Hud.label_at(self, "", Vector2(24, 70), 16, Color("c5cdbb"))
	status_label.size = Vector2(552, 66)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var roster_scroll := ScrollContainer.new()
	roster_scroll.position = Vector2(24,142)
	roster_scroll.size = Vector2(552,170)
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(roster_scroll)
	roster_label = Hud.label_at(roster_scroll, "", Vector2.ZERO, 17)
	roster_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Hud.label_at(self, "Map size", Vector2(24, 322), 14)
	size_choice = OptionButton.new()
	size_choice.position = Vector2(24, 348)
	size_choice.size = Vector2(268, 38)
	for id in Sizes.IDS:
		size_choice.add_item(Sizes.choice_label(id))
		size_choice.set_item_metadata(size_choice.item_count - 1, id)
	size_choice.select(Sizes.IDS.find("small"))
	add_child(size_choice)
	Sound.bind_button(size_choice)
	Hud.label_at(self, "Kingdoms (unused seats are AI)", Vector2(308, 322), 14)
	count_choice = OptionButton.new()
	count_choice.position = Vector2(308, 348)
	count_choice.size = Vector2(268, 38)
	add_child(count_choice)
	size_choice.item_selected.connect(func(_index): refresh())
	Sound.bind_button(count_choice)
	host_button = action("Host friends-only game", Rect2(24, 404, 268, 42), connection.host)
	invite_button = action("Invite friends…", Rect2(24, 404, 268, 42), connection.invite)
	ready_button = action("Ready", Rect2(308, 404, 268, 42), toggle_ready)
	start_button = action("Start game", Rect2(308, 462, 268, 42), start_match)
	leave_button = action("Leave lobby", Rect2(24, 462, 268, 42), connection.leave)
	action("Back", Rect2(24, 516, 552, 32), exit_lobby)
	connection.changed.connect(refresh)
	refresh()

func action(text_value: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = Loc.text(text_value)
	button.position = rect.position
	button.size = rect.size
	Hud.UiTheme.style_button(button)
	Sound.bind_button(button)
	button.pressed.connect(callback)
	add_child(button)
	return button

func enter() -> void:
	connection.initialize()
	refresh()

func exit_lobby() -> void:
	connection.leave()
	back_requested.emit()

func refresh() -> void:
	if not is_instance_valid(status_label): return
	status_label.text = connection.status if connection.status != "" else Loc.text("Host a game or accept a friend's Steam invitation.")
	var lines := PackedStringArray()
	for member in connection.members:
		var title: String = Loc.text("Host") if member.id == connection.host_id else Loc.text("Ready") if member.ready else Loc.text("Not ready")
		lines.append("%s   ·   %s" % [member.name, title])
	roster_label.text = "\n".join(lines)
	var in_lobby: bool = connection.phase == "lobby"
	host_button.visible = not in_lobby
	host_button.disabled = connection.phase != "idle"
	invite_button.visible = in_lobby
	ready_button.disabled = not in_lobby
	var mine: Array = connection.members.filter(func(member): return member.id == connection.local_id)
	ready_button.text = Loc.text("Not ready") if not mine.is_empty() and mine[0].ready else Loc.text("Ready")
	start_button.disabled = not connection.can_start()
	start_button.visible = connection.is_host()
	leave_button.visible = connection.lobby_id != 0
	size_choice.disabled = not connection.is_host() or not in_lobby
	count_choice.disabled = size_choice.disabled
	for index in range(size_choice.item_count):
		size_choice.set_item_disabled(index, Sizes.MAX_KINGDOMS[size_choice.get_item_metadata(index)] < connection.members.size())
	if Sizes.MAX_KINGDOMS[size_choice.get_selected_metadata()] < connection.members.size():
		for index in range(size_choice.item_count):
			if Sizes.MAX_KINGDOMS[size_choice.get_item_metadata(index)] >= connection.members.size():
				size_choice.select(index)
				break
	var previous := count_choice.get_selected_id() if count_choice.item_count else Sizes.DEFAULT_KINGDOMS
	var maximum: int = Sizes.MAX_KINGDOMS[size_choice.get_selected_metadata()]
	count_choice.clear()
	for count in range(2,maximum+1):
		count_choice.add_item(str(count),count)
		count_choice.set_item_disabled(count_choice.item_count-1,count < connection.members.size())
	count_choice.select(clampi(maxi(previous,connection.members.size()),2,maximum)-2)

func toggle_ready() -> void:
	for member in connection.members:
		if member.id == connection.local_id:
			connection.set_ready(not member.ready)
			return

func start_match() -> void:
	connection.start({"size":size_choice.get_selected_metadata(),"count":count_choice.get_selected_id()})
