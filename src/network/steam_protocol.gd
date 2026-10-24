extends RefCounted
## Bounded, object-free messages. Steam identities come from the transport only.
const VERSION := 2
const GAME := "slay-and-reign"
const CHANNEL := 17
const MAX_PACKET := 262144
const MAX_DECODED := 2097152

static func encode(lobby: int, kind: String, data: Dictionary) -> PackedByteArray:
	var raw := var_to_bytes({"game":GAME,"version":VERSION,"lobby":lobby,"kind":kind,"data":data})
	if raw.size() > MAX_DECODED: return PackedByteArray()
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	return packed if packed.size() <= MAX_PACKET else PackedByteArray()

static func decode(bytes: PackedByteArray, lobby: int) -> Dictionary:
	if bytes.is_empty() or bytes.size() > MAX_PACKET: return {}
	var raw := bytes.decompress_dynamic(MAX_DECODED, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty(): return {}
	var value = bytes_to_var(raw) # Objects are never permitted.
	if not value is Dictionary: return {}
	if value.get("game") != GAME or value.get("version") != VERSION or value.get("lobby") != lobby: return {}
	if not value.get("kind") is String or not value.get("data") is Dictionary: return {}
	return value
