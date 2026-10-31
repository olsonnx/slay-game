extends SceneTree
const Setup = preload("res://src/game/match_setup.gd")
const Document = preload("res://src/editor/level_document.gd")
const Rules = preload("res://src/game/kingdom_rules.gd")
const Protocol = preload("res://src/network/steam_protocol.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var host = root.get_node("SteamOnline")
	var api = load("res://tests/fixtures/fake_steam_api.gd").new()
	api.ids = range(101,111)
	for id in api.ids: api.ready[id] = "1"
	host.api = api
	host.available = true
	host.local_id = 101
	host.host()
	expect(api.lobby_capacity == 10,"Steam creates a lobby with capacity for ten friends")
	host._created(1,777)
	var panel = load("res://src/ui/steam_lobby.gd").new()
	root.add_child(panel)
	await process_frame
	expect(panel.size_choice.get_selected_metadata() == "very_large" and panel.count_choice.get_selected_id() == 10,"A ten-person lobby selects a map and count large enough for everyone")
	expect(panel.size_choice.is_item_disabled(0) and panel.size_choice.is_item_disabled(2),"Online maps that cannot hold the roster are disabled")
	expect(panel.roster_label.text.split("\n").size() == 10,"Online roster retains all ten names")
	host.start({"size":"small","count":10})
	expect(host.phase == "lobby" and api.joinable,"Transport refuses an undersized map before starting")
	var starts := []
	host.match_requested.connect(func(config,roster): starts.append({"config":config,"roster":roster}))
	host.start({"size":"very_large","count":10,"seed":42})
	expect(starts.size() == 1 and starts[0].config.slots.size() == 10 and starts[0].roster.size() == 10,"Host distributes all ten human seats")
	var client = load("res://src/network/steam_online.gd").new()
	root.add_child(client)
	client.api = api
	client.available = true
	client.lobby_id = 777
	client.host_id = 101
	client.local_id = 102
	client.lobby_content_id = client.content_id
	client.members = host.members.duplicate(true)
	client.phase = "lobby"
	var received := []
	client.match_requested.connect(func(config,_roster): received.append(config))
	client._receive(101,"start",starts[0])
	expect(client.phase == "match" and received.size() == 1 and received[0].count == 10,"Clients accept a valid ten-seat start")
	var old_wire := var_to_bytes({"game":Protocol.GAME,"version":2,"lobby":777,"kind":"start","data":starts[0]}).compress(FileAccess.COMPRESSION_DEFLATE)
	expect(Protocol.decode(old_wire,777).is_empty(),"Older clients with six-seat assumptions cannot share the new protocol")
	var document = Document.new()
	document.title = "Ten nations"
	document.map_size = "very_small"
	for index in range(10):
		var capital := Vector2i((index % 5)*4-8,(index/5)*4-2)
		for coord in [capital,capital+Vector2i(1,0)]:
			document.cells[coord] = Rules.new().make_cell(index)
		document.cells[capital].capital = index
	var path := "user://ten-nation-map.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(document.state()))
	file.close()
	var loaded := Setup.read_level(path)
	expect(loaded.error == "" and loaded.factions.size() == 10,"Authored maps can import ten active nations")
	panel.queue_free()
	client.queue_free()
	host.leave()
	await process_frame
	print("Nation lobby checks: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
