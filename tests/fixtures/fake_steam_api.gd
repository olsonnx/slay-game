extends RefCounted
var owner := 101
var local_id := 101
var ids := [101, 202]
var tags := {}
var ready := {101:"1",202:"0"}
var accepted := []
var closed := []
var left := []
var sent := []
var incoming := []
var joinable := true
var lobby_capacity := 0

func createLobby(_type: int, capacity: int) -> void: lobby_capacity = capacity

func getLobbyOwner(_lobby: int) -> int: return owner
func setLobbyData(_lobby: int, key: String, value: String) -> bool:
	tags[key] = value
	return true
func getLobbyData(_lobby: int, key: String) -> String: return tags.get(key, "")
func setLobbyMemberData(_lobby: int, key: String, value: String) -> void:
	if key == "ready": ready[local_id] = value
func getLobbyMemberData(_lobby: int, id: int, _key: String) -> String: return ready.get(id, "0")
func getNumLobbyMembers(_lobby: int) -> int: return ids.size()
func getLobbyMemberByIndex(_lobby: int, index: int) -> int: return ids[index]
func getFriendPersonaName(id: int) -> String: return "Player %d" % id
func setLobbyJoinable(_lobby: int, value: bool) -> bool:
	joinable = value
	return true
func sendMessageToUser(id: int, bytes: PackedByteArray, _flags: int, _channel: int) -> int:
	sent.append({"id":id,"bytes":bytes})
	return 1
func acceptSessionWithUser(id: int) -> bool:
	accepted.append(id)
	return true
func closeSessionWithUser(id: int) -> bool:
	closed.append(id)
	return true
func leaveLobby(id: int) -> void: left.append(id)
func run_callbacks() -> void: pass
func receiveMessagesOnChannel(_channel: int, _count: int) -> Array:
	var packets := incoming.duplicate()
	incoming.clear()
	return packets
