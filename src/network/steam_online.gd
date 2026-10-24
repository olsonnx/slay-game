extends Node
## Optional GodotSteam adapter. Offline/local play never initializes Steam.
const Loc = preload("res://src/localization/text.gd")
const Protocol = preload("res://src/network/steam_protocol.gd")
signal changed
signal failed(message: String)
signal match_requested(config: Dictionary, roster: Array)
signal packet_received(sender: int, kind: String, data: Dictionary)
signal peer_loaded
var api
var available := false
var status := ""
var lobby_id := 0
var host_id := 0
var local_id := 0
var members: Array = []
var phase := "idle"
var loaded_peers: Dictionary = {}
var last_seen: Dictionary = {}
var heartbeat_elapsed := 0.0
var pending_lobby := 0
var pending_since := 0
var invited_lobby := 0
var content_id: String:
	get: return JSON.stringify(preload("res://src/game/event_catalog.gd").EVENTS, "", true).sha256_text()
var lobby_content_id := ""
signal invitation_received

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	if DisplayServer.get_name() != "headless": call_deferred("initialize_if_running")
	var arguments := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for index in range(arguments.size() - 1):
		if arguments[index] == "+connect_lobby" and arguments[index + 1].is_valid_int():
			invited_lobby = int(arguments[index + 1])

func initialize_if_running() -> void:
	if not Engine.has_singleton("Steam"): return
	var steam = Engine.get_singleton("Steam")
	if steam.isSteamRunning(): initialize()

func initialize() -> bool:
	if available: return true
	if not Engine.has_singleton("Steam"):
		status = Loc.text("Steam support is unavailable in this build.")
		changed.emit()
		return false
	api = Engine.get_singleton("Steam")
	var app_id := int(ProjectSettings.get_setting("steam/initialization/app_data/app_id", 480))
	var result: Dictionary = api.steamInitEx(app_id, false)
	if result.get("status", -1) != 0:
		status = Loc.text("Start Steam and sign in, then try again.")
		changed.emit()
		return false
	available = true
	local_id = api.getSteamID()
	api.lobby_created.connect(_created)
	api.lobby_joined.connect(_joined)
	api.lobby_chat_update.connect(_members_changed)
	api.lobby_data_update.connect(_data_changed)
	api.join_requested.connect(_invite_requested)
	api.network_messages_session_request.connect(_session_requested)
	api.network_messages_session_failed.connect(_session_failed)
	api.initRelayNetworkAccess()
	set_process(true)
	status = Loc.text("Host a game or accept a friend's Steam invitation.")
	changed.emit()
	return true

func is_host() -> bool:
	return lobby_id != 0 and host_id == local_id

func player_display_name() -> String:
	if available and api != null:
		var value := str(api.getFriendPersonaName(local_id)).strip_edges()
		if not value.is_empty(): return value
	return Loc.text("Local player")

func host() -> void:
	if not initialize() or phase != "idle": return
	phase = "creating"
	pending_since = Time.get_ticks_msec()
	status = Loc.text("Creating lobby…")
	api.createLobby(1, 6) # Friends only; Steam ELobbyTypeFriendsOnly.
	changed.emit()

func join(id: int) -> void:
	if not initialize() or id <= 0 or phase != "idle": return
	pending_lobby = id
	phase = "joining"
	pending_since = Time.get_ticks_msec()
	status = Loc.text("Joining lobby…")
	api.joinLobby(id)
	changed.emit()

func invite() -> void:
	if lobby_id != 0 and phase == "lobby": api.activateGameOverlayInviteDialog(lobby_id)

func set_ready(value: bool) -> void:
	if phase != "lobby": return
	api.setLobbyMemberData(lobby_id, "ready", "1" if value else "0")
	refresh_members()

func refresh_members() -> void:
	if lobby_id == 0: return
	if api.getLobbyOwner(lobby_id) != host_id:
		abort(Loc.text("The host left. Return to multiplayer to start a new lobby."))
		return
	var previous := members.duplicate(true)
	members.clear()
	for index in range(api.getNumLobbyMembers(lobby_id)):
		var id: int = api.getLobbyMemberByIndex(lobby_id, index)
		members.append({"id":id,"name":api.getFriendPersonaName(id).left(18),"ready":api.getLobbyMemberData(lobby_id,id,"ready") == "1"})
	if phase == "match" and previous.size() != members.size():
		abort(Loc.text("A player disconnected. The online match has ended."))
		return
	changed.emit()

func can_start() -> bool:
	return is_host() and phase == "lobby" and lobby_content_id == content_id and members.size() >= 2 and members.all(func(member): return member.ready)

func start(config: Dictionary) -> void:
	if not can_start(): return
	var roster := members.duplicate(true)
	roster.sort_custom(func(a, b): return a.id == host_id and b.id != host_id)
	var setup: Dictionary = preload("res://src/game/match_setup.gd").normalize(config)
	setup.count = maxi(setup.count, roster.size())
	setup.slots = []
	for index in range(setup.count):
		setup.slots.append({"name":roster[index].name if index < roster.size() else preload("res://src/game/game_catalog.gd").FACTIONS[index],"controller":"human" if index < roster.size() else "ai","color":index,"difficulty":"normal"})
	setup = preload("res://src/game/match_setup.gd").normalize(setup)
	# Resolve random seeds once, on the host.
	if setup.seed < 0: setup.seed = int(Time.get_unix_time_from_system()) % 2147483647
	api.setLobbyJoinable(lobby_id, false)
	api.setLobbyData(lobby_id, "phase", "match")
	phase = "match"
	loaded_peers.clear()
	for member in members: last_seen[member.id] = Time.get_ticks_msec()
	broadcast("start", {"config":setup,"roster":roster})
	match_requested.emit(setup, roster)
	changed.emit()

func member_ids() -> Array:
	return members.map(func(member): return member.id)

func send_to(id: int, kind: String, data: Dictionary) -> bool:
	if not available or lobby_id == 0 or id not in member_ids(): return false
	var bytes := Protocol.encode(lobby_id, kind, data)
	if bytes.is_empty(): return false
	return api.sendMessageToUser(id, bytes, 8, Protocol.CHANNEL) == 1 # Reliable.

func broadcast(kind: String, data: Dictionary) -> void:
	for member in members:
		if member.id != local_id: send_to(member.id, kind, data)

func mark_loaded() -> void:
	loaded_peers[local_id] = true
	if is_host(): peer_loaded.emit()
	else: send_to(host_id, "loaded", {})

func leave() -> void:
	if lobby_id != 0 and available:
		broadcast("leave", {})
		for member in members:
			if member.id != local_id: api.closeSessionWithUser(member.id)
		api.leaveLobby(lobby_id)
	lobby_id = 0
	lobby_content_id = ""
	host_id = 0
	pending_lobby = 0
	phase = "idle"
	members.clear()
	loaded_peers.clear()
	last_seen.clear()
	status = Loc.text("Host a game or accept a friend's Steam invitation.")
	changed.emit()

func abort(message: String) -> void:
	leave()
	status = message
	changed.emit()
	failed.emit(message)

func _process(delta: float) -> void:
	api.run_callbacks()
	if phase in ["creating", "joining"] and Time.get_ticks_msec() - pending_since > 25000:
		abort(Loc.text("Steam did not respond. Please try again."))
	if lobby_id == 0: return
	for packet in api.receiveMessagesOnChannel(Protocol.CHANNEL, 32):
		var sender: int = packet.get("identity", 0)
		if sender not in member_ids() or sender == local_id: continue
		var message := Protocol.decode(packet.get("payload", PackedByteArray()), lobby_id)
		if message.is_empty(): continue
		last_seen[sender] = Time.get_ticks_msec()
		_receive(sender, message.kind, message.data)
	heartbeat_elapsed += delta
	if heartbeat_elapsed >= 3.0:
		heartbeat_elapsed = 0.0
		if not content_matches_lobby(): return
		broadcast("heartbeat", {})
		if phase == "match":
			for member in members:
				if member.id != local_id and Time.get_ticks_msec() - int(last_seen.get(member.id, 0)) > 45000:
					abort(Loc.text("Connection to a player was lost. The online match has ended."))
					break

func content_matches_lobby() -> bool:
	if lobby_id == 0 or lobby_content_id == content_id: return true
	abort(Loc.text("The event library changed. Start a new Steam lobby to use the updated events."))
	return false

func _receive(sender: int, kind: String, data: Dictionary) -> void:
	if kind == "leave":
		if phase == "match" or sender == host_id: abort(Loc.text("A player left the online game."))
	elif kind == "start" and sender == host_id and phase == "lobby":
		if not content_matches_lobby(): return
		if not data.get("config") is Dictionary or not data.get("roster") is Array: return
		var roster: Array = data.roster
		if roster.size() < 2 or roster.size() > 6 or roster.size() != members.size(): return
		var ids := []
		for member in roster:
			if not member is Dictionary or member.get("id") not in member_ids() or member.get("id") in ids: return
			ids.append(member.id)
		var setup: Dictionary = preload("res://src/game/match_setup.gd").normalize(data.config)
		if setup.count < roster.size(): return
		phase = "match"
		for member in members: last_seen[member.id] = Time.get_ticks_msec()
		match_requested.emit(setup, roster)
		changed.emit()
	elif kind == "loaded" and is_host() and phase == "match":
		loaded_peers[sender] = true
		peer_loaded.emit()
	elif phase == "match" and kind in ["command", "state", "rejected"]:
		packet_received.emit(sender, kind, data)

func _created(result: int, id: int) -> void:
	if id == lobby_id and is_host(): return
	if phase != "creating":
		if result == 1: api.leaveLobby(id)
		return
	if result != 1:
		abort(Loc.text("Could not create a Steam lobby. Please try again."))
		return
	lobby_id = id
	host_id = local_id
	lobby_content_id = content_id
	api.setLobbyData(id, "game", Protocol.GAME)
	api.setLobbyData(id, "protocol", str(Protocol.VERSION))
	api.setLobbyData(id, "content", lobby_content_id)
	api.setLobbyData(id, "phase", "lobby")
	phase = "lobby"
	api.setLobbyMemberData(id, "ready", "1")
	status = Loc.text("Invite friends, then start when everyone is ready.")
	refresh_members()

func _joined(id: int, _permissions: int, _locked: bool, response: int) -> void:
	if id == lobby_id and is_host(): return
	if phase == "creating" and response == 1 and api.getLobbyOwner(id) == local_id:
		_created(1, id)
		return
	if phase != "joining" or id != pending_lobby:
		if response == 1: api.leaveLobby(id)
		return
	if response != 1:
		abort(Loc.text("Could not join this lobby. It may be full or already playing."))
		return
	if api.getLobbyData(id, "game") != Protocol.GAME or api.getLobbyData(id, "protocol") != str(Protocol.VERSION) or api.getLobbyData(id, "content") != content_id or api.getLobbyData(id, "phase") != "lobby":
		api.leaveLobby(id)
		abort(Loc.text("This invitation is for a different game or incompatible version."))
		return
	lobby_id = id
	host_id = api.getLobbyOwner(id)
	lobby_content_id = content_id
	phase = "lobby"
	api.setLobbyMemberData(id, "ready", "0")
	status = Loc.text("Choose Ready when you want to start.")
	refresh_members()

func _members_changed(id: int, _user: int, _actor: int, _state: int) -> void:
	if id == lobby_id: refresh_members()

func _data_changed(success: int, id: int, _member: int) -> void:
	if success and id == lobby_id: refresh_members()

func _invite_requested(id: int, _friend: int) -> void:
	# Do not discard an existing match when an invitation arrives.
	if phase == "idle":
		invited_lobby = id
		invitation_received.emit()

func _session_requested(id: int) -> void:
	if id in member_ids(): api.acceptSessionWithUser(id)
	else: api.closeSessionWithUser(id)

func _session_failed(_reason: int, id: int, _connection_state: int, _debug: String) -> void:
	if phase == "match" and id in member_ids(): abort(Loc.text("The Steam connection failed. The online match has ended."))
