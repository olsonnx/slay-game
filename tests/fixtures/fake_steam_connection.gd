extends Node
const Protocol = preload("res://src/network/steam_protocol.gd")
signal packet_received(sender: int, kind: String, data: Dictionary)
signal peer_loaded
var local_id := 101
var host_id := 101
var lobby_id := 777
var phase := "match"
var peers: Dictionary = {}
var loaded_peers: Dictionary = {}
var sent: Array = []
var error := ""

func is_host() -> bool:
	return local_id == host_id

func send_to(id: int, kind: String, data: Dictionary) -> bool:
	if not peers.has(id): return false
	sent.append({"id":id,"kind":kind,"data":data.duplicate(true)})
	call_deferred("deliver", id, Protocol.encode(lobby_id, kind, data))
	return true

func deliver(id: int, bytes: PackedByteArray) -> void:
	if not is_instance_valid(peers.get(id)): return
	var message := Protocol.decode(bytes, lobby_id)
	if message.is_empty(): return
	var peer = peers[id]
	if message.kind == "loaded":
		peer.loaded_peers[local_id] = true
		peer.peer_loaded.emit()
	else: peer.packet_received.emit(local_id, message.kind, message.data)

func broadcast(kind: String, data: Dictionary) -> void:
	for id in peers: send_to(id, kind, data)

func mark_loaded() -> void:
	loaded_peers[local_id] = true
	if is_host(): peer_loaded.emit()
	else: send_to(host_id, "loaded", {})

func abort(message: String) -> void:
	error = message
