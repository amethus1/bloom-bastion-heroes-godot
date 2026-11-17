class_name NetCommon
extends RefCounted
## Packet encoding shared by the LAN host and clients. Every packet is a
## Dictionary sent with var_to_bytes; big ones (snapshots) are zstd-compressed.

const PLAIN := 1
const PACKED := 2
const MAX_UNPACKED := 8 * 1024 * 1024


static func encode(d: Dictionary, compress := false) -> PackedByteArray:
	var body := var_to_bytes(d)
	var out := PackedByteArray()
	if compress:
		out.append(PACKED)
		var size := body.size()
		out.append_array(PackedByteArray([size & 0xFF, (size >> 8) & 0xFF, (size >> 16) & 0xFF, (size >> 24) & 0xFF]))
		out.append_array(body.compress(FileAccess.COMPRESSION_ZSTD))
	else:
		out.append(PLAIN)
		out.append_array(body)
	return out


static func decode(b: PackedByteArray) -> Dictionary:
	if b.size() < 2:
		return {}
	var body: PackedByteArray
	if b[0] == PACKED:
		var size := b[1] | (b[2] << 8) | (b[3] << 16) | (b[4] << 24)
		if size <= 0 or size > MAX_UNPACKED:
			return {}
		body = b.slice(5).decompress(size, FileAccess.COMPRESSION_ZSTD)
	else:
		body = b.slice(1)
	var v = bytes_to_var(body)  # never allows objects, so it is safe on a LAN
	return v if typeof(v) == TYPE_DICTIONARY else {}


static func clean_name(s: String) -> String:
	var t := s.strip_edges().substr(0, 16)
	return t if t != "" else "Player"
