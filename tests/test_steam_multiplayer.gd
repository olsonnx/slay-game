extends SceneTree
const Protocol = preload("res://src/network/steam_protocol.gd")
const NetworkMatch = preload("res://src/network/network_match.gd")
const FakeConnection = preload("res://tests/fixtures/fake_steam_connection.gd")
const Snapshot = preload("res://src/game/state_snapshot.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(host, client, previous := -1) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while (host.revision <= previous or client.revision != host.revision or host.waiting or client.waiting or client.applying) and Time.get_ticks_msec() < deadline:
		await process_frame
	expect(host.revision > previous and client.revision == host.revision and not host.waiting and not client.waiting and not client.applying, "Reliable command and authoritative state settle on both peers")
	expect(Snapshot.capture(host.game.rules) == Snapshot.capture(client.game.rules), "Peers share exact cells, treasuries, events, effects and RNG state")

func make_game(config: Dictionary):
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(960, 620)
	root.add_child(viewport)
	var game = load("res://scenes/main.tscn").instantiate()
	game.initial_seed = 71
	game.initial_map_size = "very_small"
	game.initial_kingdom_count = 3
	game.initial_human_count = 2
	game.initial_match_config = config.duplicate(true)
	viewport.add_child(game)
	game.view.playback.set_speed_scale(6.0)
	return game

func run() -> void:
	Engine.max_fps = 120
	root.get_node("Sound").set_muted(true, false)
	root.get_node("Video").set_preference(&"level_transitions", false, false)
	test_adapter()
	var bytes := Protocol.encode(777, "command", {"kind":"move","coord":Vector2i(2, -3)})
	expect(Protocol.decode(bytes, 777).data.coord == Vector2i(2, -3), "Wire format preserves hex coordinates without object decoding")
	expect(Protocol.decode(bytes, 778).is_empty(), "Packets from another lobby are ignored")
	var oversized := PackedByteArray()
	oversized.resize(Protocol.MAX_PACKET + 1)
	expect(Protocol.decode(oversized, 777).is_empty(), "Oversized packets are rejected before decompression")
	var invalid := var_to_bytes({"game":"other","version":Protocol.VERSION,"lobby":777,"kind":"state","data":{}}).compress(FileAccess.COMPRESSION_DEFLATE)
	expect(Protocol.decode(invalid, 777).is_empty(), "Spacewar traffic must match this game's protocol")
	var huge_rules = load("res://src/game/kingdom_rules.gd").new()
	huge_rules.generate(71, "huge", 6)
	var huge_packet := Protocol.encode(777, "state", {"position":Snapshot.capture(huge_rules)})
	expect(not huge_packet.is_empty() and Protocol.decode(huge_packet, 777).data.position.cells == huge_rules.cells, "Largest supported maps fit the bounded compressed snapshot protocol")
	var config: Dictionary = load("res://src/game/match_setup.gd").normalize({"size":"very_small","seed":71,"count":3,"slots":[{"controller":"human"},{"controller":"human"},{"controller":"ai","difficulty":"easy"}]})
	var host_game = make_game(config)
	var client_game = make_game(config)
	client_game.rules.replay_log = null
	for kingdom in host_game.rules.kingdoms.values(): kingdom.gold = 500 if kingdom.owner == 0 else 100
	var host_connection := FakeConnection.new()
	var client_connection := FakeConnection.new()
	client_connection.local_id = 202
	host_connection.peers = {202:client_connection}
	client_connection.peers = {101:host_connection}
	root.add_child(host_connection)
	root.add_child(client_connection)
	var roster := [{"id":101,"name":"Host"},{"id":202,"name":"Friend"}]
	var host := NetworkMatch.new(host_connection, host_game, roster)
	var client := NetworkMatch.new(client_connection, client_game, roster)
	host_game.add_child(host)
	client_game.add_child(client)
	await settle(host, client)
	expect(not host.locked() and client.locked(), "Only the Steam identity owning the active seat can issue commands")
	var original := Snapshot.capture(host_game.rules)
	host.handle(202, {"kind":"end_turn","request":1,"revision":host.revision})
	host.handle(999, {"kind":"end_turn","request":1,"revision":host.revision})
	expect(Snapshot.capture(host_game.rules) == original and host_game.player_faction == 0, "Out-of-turn members and strangers cannot advance the game")
	var develop_coord: Vector2i = host_game.NONE
	for coord in host_game.cells:
		if host_game.rules.can_develop(coord, 0):
			develop_coord = coord
			break
	expect(develop_coord != host_game.NONE, "Fixture offers a legal development command")
	var previous: int = host.revision
	host.submit({"kind":"develop","coord":develop_coord})
	await settle(host, client, previous)
	var after_purchase := Snapshot.capture(host_game.rules)
	host.handle(101, {"kind":"develop","coord":develop_coord,"request":1,"revision":previous})
	expect(Snapshot.capture(host_game.rules) == after_purchase, "Duplicate and stale requests cannot charge a treasury twice")
	# Exercise each purchase/status command through the same public command path.
	for kind in ["recruit", "entrench", "house", "tower", "bridge", "spell", "relocate"]:
		var command := find_command(host_game, kind)
		expect(not command.is_empty(), "Fixture offers a legal online " + kind + " command")
		if command.is_empty(): continue
		var before := Snapshot.capture(host_game.rules)
		previous = host.revision
		host.submit(command)
		await settle(host, client, previous)
		expect(Snapshot.capture(host_game.rules) != before, "Online " + kind + " commits a rule change on the host")
	var malformed: Dictionary = host_connection.sent.back().data.duplicate(true)
	malformed.revision = client.revision + 1
	malformed.position.cells[malformed.position.cells.keys()[0]].unit = 99
	expect(not client.valid_state(malformed), "Malformed snapshot unit records are rejected before restoring live rules")
	previous = host.revision
	host.submit({"kind":"end_turn"})
	await settle(host, client, previous)
	expect(host_game.player_faction == 1 and client_game.player_faction == 1 and not client.locked() and host.locked(), "Ending a turn hands control to the remote Steam player")
	var source: Vector2i = client_game.NONE
	var target: Vector2i = client_game.NONE
	for coord in client_game.cells:
		if client_game.cells[coord].unit > 0 and client_game.rules.unit_faction(coord) == 1:
			for candidate in client_game.rules.reachable_targets(coord):
				source = coord
				target = candidate
				break
		if target != client_game.NONE: break
	expect(target != client_game.NONE, "Fixture offers a remote movement command")
	if target != client_game.NONE:
		previous = host.revision
		client.submit({"kind":"move","source":source,"coord":target,"capital":client_game.rules.unit_kingdom(source).get("capital",client_game.NONE)})
		while not host.executing and host.revision == previous: await process_frame
		var committed := Snapshot.capture(host_game.rules)
		host_game.cancel_action()
		expect(Snapshot.capture(host_game.rules) == committed, "Host input cannot roll back a remote player's accepted movement")
		await settle(host, client, previous)
		# Resolve any encounter reached by the selected legal move.
		if not client_game.shown_event.is_empty():
			previous = host.revision
			client.submit({"kind":"event","choice":0})
			await settle(host, client, previous)
	# Pending events cannot be bypassed with end-turn packets.
	var event_coord: Vector2i = host_game.NONE
	for coord in host_game.cells:
		if host_game.cells[coord].unit > 0 and host_game.rules.unit_faction(coord) == 1:
			event_coord = coord
			break
	if event_coord != host_game.NONE:
		host_game.rules.pending_events.append({"id":"gold","coord":event_coord,"faction":1})
		host_game.show_next_event()
		host.publish()
		await settle(host, client)
		expect(not host_game.event_shade.visible and client_game.event_shade.visible, "Only the remote decision-maker sees their encounter dialog")
		original = Snapshot.capture(host_game.rules)
		host.handle(202, {"kind":"end_turn","request":999,"revision":host.revision})
		expect(Snapshot.capture(host_game.rules) == original, "Unresolved encounters block end-turn commands")
		previous = host.revision
		client.submit({"kind":"event","choice":0})
		await settle(host, client, previous)
	previous = host.revision
	client.submit({"kind":"end_turn"})
	await settle(host, client, previous)
	expect(host_game.player_faction == 0 and host_game.round_number == 2, "Host runs the AI kingdom and world settlement before returning control")
	expect(host_connection.error == "" and client_connection.error == "", "No transport aborts occur during normal play")
	# Finish with a remote winner, using the production client without a recorder.
	for cell in host_game.cells.values():
		if cell.owner >= 0 and cell.owner != 1:
			cell.owner = 1
			cell.capital = -1
			cell.unit = 0
	host_game.rules.rebuild_kingdoms()
	host_game.rules.record_replay("move", 1, {"outcome":"move"})
	host_game.check_winner()
	previous = host.revision
	host.publish()
	await settle(host, client, previous)
	expect(client_game.game_over and client_game.winner_faction == 1 and client_game.message == "Victory for %s!" % client_game.NAMES[1], "A remote client receives the final winner announcement")
	expect(client_game.match_results == host_game.match_results and client_game.match_results[1].tiles > 0 and client_game.rules.replay_log == null, "Client results retain authoritative nonzero statistics without a replay recorder")
	malformed = host_connection.sent.back().data.duplicate(true)
	malformed.revision = client.revision + 1
	malformed.results[1].tiles = -1
	expect(not client.valid_state(malformed), "Invalid result counters are rejected before displaying a final state")
	host.terminate()
	client.terminate()
	expect(host.locked() and client.locked(), "Disconnect termination locks both peers")
	host_game.shutdown()
	client_game.shutdown()
	await process_frame
	host_game.get_parent().queue_free()
	client_game.get_parent().queue_free()
	host_connection.queue_free()
	client_connection.queue_free()
	await process_frame
	print("Steam multiplayer checks: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func find_command(game, kind: String) -> Dictionary:
	var faction: int = game.player_faction
	for capital in game.rules.kingdoms:
		if game.rules.kingdoms[capital].owner != faction: continue
		var targets: Dictionary = game.rules.bridge_targets(faction, capital) if kind == "bridge" else game.rules.spell_targets("trailblaze", faction, capital) if kind == "spell" else game.cells
		for coord in targets:
			var valid := false
			match kind:
				"recruit": valid = game.rules.can_recruit(coord, faction, 1, capital) and game.cells[coord].unit == 0
				"entrench": valid = game.rules.can_entrench(coord, faction)
				"relocate": valid = game.rules.can_relocate_capital(coord, faction)
				"house", "tower", "bridge": valid = game.rules.can_build(coord, faction, kind, capital)
				"spell": valid = game.rules.can_cast("trailblaze", coord, faction, capital)
			if valid: return {"kind":kind,"coord":coord,"capital":capital,"tier":1,"spell":"trailblaze"}
	return {}

func test_adapter() -> void:
	# The installed native extension must expose the exact API used in production.
	expect(Engine.has_singleton("Steam"), "Bundled GodotSteam extension loads on the test platform")
	if Engine.has_singleton("Steam"):
		var api = Engine.get_singleton("Steam")
		for method in ["steamInitEx", "run_callbacks", "createLobby", "joinLobby", "setLobbyData", "getLobbyData", "setLobbyMemberData", "getLobbyMemberData", "getNumLobbyMembers", "getLobbyMemberByIndex", "getFriendPersonaName", "getLobbyOwner", "sendMessageToUser", "receiveMessagesOnChannel", "acceptSessionWithUser", "closeSessionWithUser", "initRelayNetworkAccess", "activateGameOverlayInviteDialog", "leaveLobby", "setLobbyJoinable"]:
			expect(api.has_method(method), "Native Steam API includes " + method)
		for callback in ["lobby_created", "lobby_joined", "lobby_chat_update", "lobby_data_update", "join_requested", "network_messages_session_request", "network_messages_session_failed"]:
			expect(api.has_signal(callback), "Native Steam API includes callback " + callback)
	var adapter = load("res://src/network/steam_online.gd").new()
	root.add_child(adapter)
	var api = load("res://tests/fixtures/fake_steam_api.gd").new()
	adapter.api = api
	adapter.available = true
	adapter.local_id = 101
	adapter.phase = "creating"
	adapter._created(1, 777)
	adapter._joined(777, 0, false, 1)
	expect(adapter.is_host() and adapter.phase == "lobby" and api.left.is_empty(), "Lobby-created and lobby-joined callbacks do not leave the host's own lobby")
	expect(api.tags.game == Protocol.GAME and api.tags.protocol == str(Protocol.VERSION), "Spacewar lobbies advertise game identity and protocol")
	expect(not adapter.can_start(), "Host cannot start before every friend is ready")
	var client_adapter = load("res://src/network/steam_online.gd").new()
	root.add_child(client_adapter)
	var client_api = load("res://tests/fixtures/fake_steam_api.gd").new()
	client_api.tags = api.tags.duplicate()
	client_api.local_id = 202
	client_adapter.api = client_api
	client_adapter.available = true
	client_adapter.local_id = 202
	client_adapter.phase = "joining"
	client_adapter.pending_lobby = 777
	client_adapter._joined(777, 0, false, 1)
	expect(client_adapter.phase == "lobby" and client_adapter.host_id == 101 and not client_adapter.is_host(), "A compatible invite binds the client to the existing lobby owner")
	expect(client_api.ready[101] == "1" and client_api.ready[202] == "0", "Joining clients are unready without changing the host's ready flag")
	var received := [0]
	client_adapter.packet_received.connect(func(_sender, _kind, _data): received[0] += 1)
	client_adapter.phase = "match"
	client_api.incoming = [{"identity":303,"payload":Protocol.encode(777,"state",{})},{"identity":101,"payload":Protocol.encode(777,"state",{})}]
	client_adapter._process(0.0)
	expect(received[0] == 1, "Transport authenticates packet sender against Steam lobby membership")
	client_adapter.leave()
	client_api.tags.game = "unrelated-spacewar-game"
	client_adapter.phase = "joining"
	client_adapter.pending_lobby = 888
	client_adapter._joined(888, 0, false, 1)
	expect(client_adapter.phase == "idle" and 888 in client_api.left, "Unrelated Spacewar invitations are rejected and left")
	client_adapter.queue_free()
	api.ready[202] = "1"
	adapter.refresh_members()
	expect(adapter.can_start(), "A ready host and friend can launch")
	adapter._session_requested(202)
	adapter._session_requested(303)
	expect(api.accepted == [202] and api.closed == [303], "Steam networking sessions are accepted only for current lobby members")
	adapter.start({"size":"very_small","count":3})
	var start := Protocol.decode(api.sent[0].bytes, 777)
	expect(adapter.phase == "match" and not api.joinable and start.kind == "start" and start.data.config.seed >= 0 and start.data.config.slots[2].controller == "ai", "Host freezes membership and distributes one resolved seed, roster and AI seat configuration")
	api.owner = 202
	adapter.refresh_members()
	expect(adapter.phase == "idle" and adapter.lobby_id == 0 and not api.left.is_empty(), "Host loss ends the session instead of silently migrating authority")
	adapter.queue_free()
	content_reload_checks()

func content_reload_checks() -> void:
	var catalog = preload("res://src/game/event_catalog.gd")
	var original: Dictionary = catalog.EVENTS.duplicate(true)
	var adapter = load("res://src/network/steam_online.gd").new()
	root.add_child(adapter)
	var api = load("res://tests/fixtures/fake_steam_api.gd").new()
	adapter.api = api
	adapter.available = true
	adapter.local_id = 101
	var initial_hash: String = adapter.content_id
	catalog.EVENTS["gold"].text += " Updated story."
	expect(adapter.content_id != initial_hash, "Content identity follows the currently loaded catalog")
	adapter.phase = "creating"
	adapter._created(1,777)
	expect(api.tags.content == adapter.content_id, "New lobbies advertise reloaded event content")
	var peer = load("res://src/network/steam_online.gd").new()
	root.add_child(peer)
	var peer_api = load("res://tests/fixtures/fake_steam_api.gd").new()
	peer_api.tags = api.tags.duplicate()
	peer_api.local_id = 202
	peer.api = peer_api
	peer.available = true
	peer.local_id = 202
	peer.phase = "joining"
	peer.pending_lobby = 777
	peer._joined(777,0,false,1)
	expect(peer.phase == "lobby" and peer.lobby_content_id == adapter.lobby_content_id, "Peers with matching reloaded content can join the new lobby")
	peer.leave()
	peer.queue_free()
	api.ready[202] = "1"
	adapter.refresh_members()
	expect(adapter.can_start(), "A newly created lobby with reloaded content can start normally")
	catalog.EVENTS["gold"].text += " Another edit."
	expect(not adapter.can_start(), "Editing events immediately prevents a lobby from starting with stale content")
	adapter._process(3.0)
	expect(adapter.phase == "idle", "The heartbeat closes a lobby whose event library changed")
	# A peer with the current catalog rejects an older advertised library.
	adapter.phase = "joining"
	adapter.pending_lobby = 888
	adapter._joined(888,0,false,1)
	expect(adapter.phase == "idle" and 888 in api.left, "Joining compares current content against the host's frozen library")
	adapter.queue_free()
	catalog.EVENTS.assign(original)
