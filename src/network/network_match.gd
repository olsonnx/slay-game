extends Node
## Host-authoritative commands; clients only select targets and render snapshots.
const Loc = preload("res://src/localization/text.gd")
const Snapshot = preload("res://src/game/state_snapshot.gd")
var transport
var game
var seats: Dictionary = {}
var local_faction := -1
var revision := -1
var request_id := 0
var last_requests: Dictionary = {}
var waiting := true
var executing := false
var applying := false
var terminated := false
var local_paused := false
var remote_busy := false
var states: Array = []
var movement := {}

func _init(connection, controller, roster: Array) -> void:
	transport = connection
	game = controller
	for index in range(roster.size()): seats[roster[index].id] = index
	local_faction = seats.get(transport.local_id, -1)
	game.network_match = self
	game.session.online = true
	if transport.is_host() and game.rules.replay_log != null:
		game.rules.replay_log.header.metadata["mode"] = "steam_online"
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	transport.packet_received.connect(_packet)
	transport.peer_loaded.connect(_loaded)
	game.view.action_started.connect(_capture_movement)
	activate()

func activate() -> void:
	while game.view.level_transitioning and not game.closing and not terminated:
		await get_tree().process_frame
	if game.closing or terminated: return
	transport.mark_loaded()
	game.refresh_ui()

func is_local_turn() -> bool:
	return not terminated and game.player_faction == local_faction

func locked() -> bool:
	return not executing and (waiting or applying or remote_busy or local_paused or not is_local_turn())

func route_click(coord: Vector2i) -> bool:
	if executing: return false
	if locked(): return true
	var selection = game.session.selection
	var mode: String = selection.action_mode
	var kind := ""
	if mode in ["recruit", "spell", "city", "tower", "bridge", "road"]: kind = mode
	elif selection.selected != coord and selection.valid_targets.has(coord): kind = "move"
	if kind == "": return false # Pure local selection/inspection.
	submit({"kind":kind,"coord":coord,"source":selection.selected,"capital":game.active_capital(),"tier":selection.recruit_tier,"spell":selection.chosen_spell})
	return true

func submit(command: Dictionary) -> void:
	if terminated or waiting or applying or remote_busy or local_paused or not is_local_turn(): return
	request_id += 1
	command = command.duplicate(true)
	command["revision"] = revision
	command["request"] = request_id
	waiting = true
	game.refresh_ui()
	if transport.is_host(): handle(transport.local_id, command)
	elif not transport.send_to(transport.host_id, "command", command):
		transport.abort(Loc.text("Could not send your action to the host."))

func _loaded() -> void:
	if not transport.is_host() or revision >= 0 or terminated: return
	for id in seats:
		if not transport.loaded_peers.get(id, false): return
	waiting = false
	publish()
	game.refresh_ui()

func _packet(sender: int, kind: String, data: Dictionary) -> void:
	if terminated or game.closing: return
	if kind == "command" and transport.is_host(): handle(sender, data)
	elif sender == transport.host_id and not transport.is_host():
		if kind == "state":
			states.append(data)
			if states.size() > 16:
				transport.abort(Loc.text("The connection could not keep up with the match."))
				return
			if not applying: apply_states()
		elif kind == "rejected":
			waiting = false
			game.announce(Loc.text("That action is no longer available. Please try again."))
			game.refresh_ui()

func valid_command(sender: int, command: Dictionary) -> bool:
	if sender not in seats or seats[sender] != game.player_faction or game.busy or game.game_over or game.closing or executing or revision < 0: return false
	if not command.get("request") is int or command.request <= int(last_requests.get(sender, 0)): return false
	if not command.get("revision") is int or command.revision != revision: return false
	var kind = command.get("kind")
	if kind not in ["move", "recruit", "spell", "city", "tower", "road", "bridge", "develop", "entrench", "relocate", "dismantle", "rename", "event", "end_turn"]: return false
	if kind == "event":
		if game.shown_event.is_empty() or not command.get("choice") is int: return false
		var definition: Dictionary = game.rules.event_definition(game.shown_event)
		return command.choice >= 0 and command.choice < definition.get("choices", []).size()
	if not game.rules.pending_events.is_empty(): return false
	if kind == "end_turn": return true
	if not command.get("coord") is Vector2i: return false
	var coord: Vector2i = command.coord
	if absi(coord.x) > 200 or absi(coord.y) > 200: return false
	if kind == "road":
		return command.get("source") is Vector2i and game.rules.road_targets(command.source, game.player_faction).has(coord)
	if kind == "move":
		return command.get("source") is Vector2i and game.cells.has(command.source) and game.rules.unit_faction(command.source) == game.player_faction and game.rules.can_move(command.source, coord)
	if kind in ["recruit", "spell", "city", "tower", "bridge"]:
		if not command.get("capital") is Vector2i: return false
		if game.rules.kingdoms.get(command.capital, {}).get("owner", -1) != game.player_faction: return false
	match kind:
		"rename":
			if not command.get("name") is String or command.name.length() > 40: return false
			for index in range(command.name.length()):
				if command.name.unicode_at(index) < 32 or command.name.unicode_at(index) == 127: return false
			return game.rules.can_rename_settlement(coord, game.player_faction)
		"recruit": return command.get("tier") is int and command.tier in [1, 2, 3] and game.rules.can_recruit(coord, game.player_faction, command.tier, command.capital)
		"spell": return command.get("spell") is String and game.Spells.SPELLS.has(command.spell) and game.rules.spell_targets(command.spell, game.player_faction, command.capital).has(coord)
		"city", "tower", "bridge": return game.rules.can_build(coord, game.player_faction, kind, command.capital)
		"dismantle": return game.rules.can_dismantle(coord, game.player_faction)
		"develop": return game.rules.can_develop(coord, game.player_faction)
		"entrench": return game.rules.can_entrench(coord, game.player_faction)
		"relocate": return game.rules.can_relocate_capital(coord, game.player_faction)
	return false

func handle(sender: int, command: Dictionary) -> void:
	if not valid_command(sender, command):
		if sender == transport.local_id:
			waiting = false
			game.refresh_ui()
		else: transport.send_to(sender, "rejected", {})
		return
	last_requests[sender] = command.request
	executing = true
	movement = {}
	var kind: String = command.kind
	match kind:
		"end_turn": await game.end_turn()
		"rename": game.rules.rename_settlement(command.coord, game.player_faction, command.name)
		"event": game.resolve_shown_event(command.choice)
		"develop", "entrench", "relocate", "dismantle":
			if kind == "relocate":
				game.rules.relocate_capital(command.coord, game.player_faction)
				game.view.render_cells(game.cells)
			else:
				game.inspect_province(command.coord)
				if kind == "dismantle": game.dismantle_province()
				elif kind == "develop": game.develop_province()
				else: game.entrench_province()
		_:
			game.session.selection.active_hex = command.get("capital", game.NONE)
			game.session.selection.selected = command.get("source", game.NONE)
			game.session.selection.action_mode = "" if kind == "move" else kind
			game.session.selection.chosen_spell = command.get("spell", "")
			game.session.selection.recruit_tier = command.get("tier", 0)
			game.refresh_targets()
			await game.click_hex(command.coord)
	if game.closing or terminated: return
	game.sync_event_factions()
	game.check_winner()
	executing = false
	waiting = false
	if kind == "end_turn": movement = {}
	publish()
	game.refresh_ui()

func publish() -> void:
	revision += 1
	transport.broadcast("state", {"revision":revision,"position":Snapshot.capture(game.rules),"active":game.active_faction,"player":game.player_faction,"round":game.round_number,"turn_order":game.turn_order.duplicate(),"over":game.game_over,"winner":game.winner_faction,"results":game.match_results.duplicate(true),"movement":movement})
	movement = {}

func valid_state(data: Dictionary) -> bool:
	if not data.get("revision") is int or data.revision <= revision: return false
	for key in ["active", "player", "round", "winner"]:
		if not data.get(key) is int: return false
	if data.player not in seats.values() or not data.get("over") is bool or not data.get("turn_order") is Array or not data.get("movement") is Dictionary: return false
	var position = data.get("position")
	if not position is Dictionary or position.get("snapshot_version") != Snapshot.VERSION: return false
	for field in Snapshot.POSITION_FIELDS:
		if not position.has(field): return false
	for key in ["cells", "kingdoms", "mana", "effects", "capital_relocations", "configuration", "ai_last_decision"]:
		if not position.get(key) is Dictionary: return false
	if not position.get("events") is Array or position.cells.size() > 5000: return false
	for field in Snapshot.CONFIGURATION:
		if not position.configuration.has(field): return false
	if not position.rng is String or not position.rng.is_valid_int() or position.difficulty not in ["easy", "normal", "hard"]: return false
	if not position.faction_count is int or position.faction_count < 2 or position.faction_count > 64: return false
	if data.winner < -1 or data.winner >= position.faction_count: return false
	if not data.get("results") is Dictionary or data.results.size() > 64: return false
	for faction in data.results:
		if not faction is int or faction < 0 or faction >= position.faction_count or not data.results[faction] is Dictionary: return false
		for key in ["slain", "lost", "tiles", "capitals"]:
			var amount = data.results[faction].get(key)
			if not amount is int or amount < 0: return false
	var config: Dictionary = position.configuration
	for key in ["level_seed", "faction_count", "initial_kingdom_count", "ai_revision"]:
		if not config[key] is int: return false
	if config.faction_count != position.faction_count or not config.incremental_kingdoms is bool: return false
	if not config.human_factions is Array or not config.faction_names is Array or config.faction_names.size() > 64: return false
	for faction in config.human_factions:
		if not faction is int or faction < 0 or faction >= position.faction_count: return false
	for title in config.faction_names:
		if not title is String or title.length() > 200: return false
	if not config.rule_mode is String or not config.map_size is String or not config.ai_algorithm is String: return false
	if not preload("res://src/game/map_sizes.gd").SPECS.has(config.map_size): return false
	for coord in position.cells:
		if not coord is Vector2i or absi(coord.x) > 200 or absi(coord.y) > 200: return false
		var cell = position.cells[coord]
		if not cell is Dictionary: return false
		for key in ["owner", "capital", "unit", "value"]:
			if not cell.get(key) is int: return false
		if cell.owner < -1 or cell.owner >= position.faction_count or cell.capital < -1 or cell.capital >= position.faction_count or cell.unit < 0 or cell.unit > 3: return false
		for key in ["tree", "grave", "moved"]:
			if not cell.get(key) is bool: return false
		if cell.get("building") not in ["", "city", "tower", "road", "bridge", "monument"] or not cell.get("kingdom") is Vector2i: return false
		if cell.get("animal", "") not in ["", "bear", "wolf", "boar"] or cell.get("lair", "") not in ["", "bear", "wolf", "boar"]: return false
	for capital in position.kingdoms:
		var kingdom = position.kingdoms[capital]
		if not capital is Vector2i or not kingdom is Dictionary: return false
		if not kingdom.get("capital") is Vector2i or not kingdom.get("owner") is int or not kingdom.get("gold") is int or not kingdom.get("hexes") is Array: return false
		for coord in kingdom.hexes:
			if not coord is Vector2i or not position.cells.has(coord): return false
	for event in position.events:
		if not event is Dictionary or not event.get("coord") is Vector2i or not event.get("faction") is int or not preload("res://src/game/event_catalog.gd").EVENTS.has(event.get("id")): return false
	for faction in data.turn_order:
		if not faction is int or faction < 0 or faction >= position.faction_count: return false
	if data.turn_order.size() > 64 or data.round < 1 or data.active < 0 or data.active >= position.faction_count: return false
	if not data.movement.is_empty():
		var action: Dictionary = data.movement
		if action.get("kind") not in ["move", "attack", "merge", "blocked_attack", "knight_duel"]: return false
		for key in ["source", "target"]:
			if not action.get(key) is Vector2i: return false
		if not action.get("path") is Array or action.path.size() < 2 or action.path.size() > 5000: return false
		for coord in action.path:
			if not coord is Vector2i: return false
		for key in ["before_source", "before_target"]:
			if not action.get(key) is Dictionary: return false
	return true

func apply_states() -> void:
	applying = true
	while not states.is_empty() and not game.closing and not terminated:
		var data: Dictionary = states.pop_front()
		if data.get("revision") is int and data.revision <= revision: continue
		if not valid_state(data):
			terminate()
			transport.abort(Loc.text("Received an incompatible game state. Use the same game build as the host."))
			break
		var changed_turn: bool = game.player_faction != data.player
		Snapshot.restore(game.rules, data.position)
		game.active_faction = data.active
		game.player_faction = data.player
		game.round_number = data.round
		game.turn_order = data.turn_order.duplicate()
		game.game_over = data.over
		game.winner_faction = data.winner
		game.match_results = data.results.duplicate(true)
		revision = data.revision
		game.close_event_ui()
		game.shown_event.clear()
		if changed_turn: game.begin_local_turn()
		game.session.selection.action_mode = ""
		game.session.selection.selected = game.NONE
		# Animate only against an existing source; authoritative state is already
		# committed, and clients never rerun moves or consume their own game RNG.
		if not data.movement.is_empty() and game.view.unit_actors.has(data.movement.get("source")):
			await game.view.animate_moves([data.movement], game.cells)
		else: game.view.render_cells(game.cells)
		waiting = false
		game.show_next_event()
		game.refresh_ui()
		if game.game_over:
			if game.winner_faction >= 0: game.announce(Loc.text("Victory for %s!") % game.NAMES[game.winner_faction])
			elif game.cells.values().any(func(cell): return cell["capital"] >= 0): game.announce(Loc.text("Defeat — all local kingdoms have fallen."))
			else: game.announce(Loc.text("Draw — no kingdoms remain."))
			game.begin_completion_exit()
	applying = false
	if not game.closing: game.refresh_ui()

func _capture_movement(action: Dictionary) -> void:
	if executing and action.get("kind") in ["move", "attack", "merge", "blocked_attack", "knight_duel"]:
		movement = action.duplicate(true)

func terminate() -> void:
	terminated = true
	waiting = true
	states.clear()

func _exit_tree() -> void:
	if transport.packet_received.is_connected(_packet): transport.packet_received.disconnect(_packet)
	if transport.peer_loaded.is_connected(_loaded): transport.peer_loaded.disconnect(_loaded)
