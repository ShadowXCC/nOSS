class_name NetProtocol
extends RefCounted
## The wire format (docs/NETWORKING.md §2, D78). Every message is raw bytes sent with
## SceneMultiplayer.send_auth or send_bytes: one type byte, then the payload. There are no RPCs.
## Control messages carry a Dictionary made by var_to_bytes (never objects): its size is checked
## before decoding, its fields after. Car states and content chunks have their own packed formats.

## Bumped whenever messages change: a client and server must match.
const VERSION := 1
const DEFAULT_PORT := 47800
## Channels beyond Godot's channel 0 (which carries reliable control messages).
const EXTRA_CHANNELS := 2
const CH_CONTROL := 0
## Car states: unreliable, alone on their channel (ENet holds unreliable packets behind reliable
## ones on the same channel).
const CH_STATE := 1
## Content chunks: unreliable, with their own acks (Transfer).
const CH_CONTENT := 2
const MAX_AUTH_BYTES := 4096
const MAX_CONTROL_BYTES := 65536
## Most local players one connection brings (LOC-05), and most players on a server (MP-03).
const MAX_LOCAL := 4
const MAX_PLAYERS := 16
const MAX_NAME := 24
## Message types from here up are packed binary (car states, content), not control messages.
const RAW_FIRST := 100

enum Msg {
	# Auth, through send_auth.
	CHALLENGE = 1, ## server: {protocol, game, nonce, password, name}
	HELLO = 2, ## client: {protocol, game, key, signature, proof, players: [{name, color}]}
	ACCEPT = 3, ## server: {name, players: [ids for the client's players], admin, motd}
	REJECT = 4, ## server: {reason}
	# Control, reliable on channel 0.
	BYE = 10, ## server: {reason} just before it disconnects the client
}


static func game_version() -> String:
	return ProjectSettings.get_setting("application/config/version")


## A message: the type byte, then `payload` (var_to_bytes, no objects).
static func encode(type: int, payload: Dictionary) -> PackedByteArray:
	var out := PackedByteArray([type])
	out.append_array(var_to_bytes(payload))
	return out


## {type, data}, or {} if the bytes are too long, empty, or don't hold a Dictionary.
static func decode(bytes: PackedByteArray, max_bytes := MAX_CONTROL_BYTES) -> Dictionary:
	# A var_to_bytes Dictionary starts with its type; anything else is junk (no engine errors).
	if bytes.size() < 5 or bytes.size() > max_bytes or bytes.decode_u16(1) != TYPE_DICTIONARY:
		return {}
	var data: Variant = bytes_to_var(bytes.slice(1))
	if not data is Dictionary:
		return {}
	return { "type": bytes[0], "data": data }


## Whether `d` has each field of `spec` with the right type: spec maps a key to a Variant type
## or to [type, most] (characters for strings, bytes for byte arrays, items for arrays).
## Numbers may be int or float where a float is asked for. Fields not in `spec` are ignored.
static func has_fields(d: Dictionary, spec: Dictionary) -> bool:
	for key: String in spec:
		var want: Variant = spec[key]
		var type: int = want[0] if want is Array else want
		var most: int = want[1] if want is Array else -1
		if not d.has(key):
			return false
		var v: Variant = d[key]
		var t := typeof(v)
		if t != type and not (type == TYPE_FLOAT and t == TYPE_INT):
			return false
		if most >= 0:
			match t:
				TYPE_STRING:
					if (v as String).length() > most:
						return false
				TYPE_PACKED_BYTE_ARRAY:
					if (v as PackedByteArray).size() > most:
						return false
				TYPE_ARRAY:
					if (v as Array).size() > most:
						return false
	return true


## A player name as shown to others: printable, trimmed, at most MAX_NAME characters.
static func clean_name(text: String) -> String:
	var out := ""
	for c in text.strip_edges():
		if c.unicode_at(0) >= 32 and c.unicode_at(0) != 127:
			out += c
	out = out.strip_edges().left(MAX_NAME)
	return out if out else "Player"


## "host:port" or "host" (the default port); IPv6 in brackets: "[::1]:47800".
static func parse_address(text: String) -> Dictionary:
	var s := text.strip_edges()
	var port := DEFAULT_PORT
	if s.begins_with("["):
		var end := s.find("]")
		if end < 0:
			return {}
		if s.substr(end + 1).begins_with(":"):
			port = int(s.substr(end + 2))
		s = s.substr(1, end - 1)
	elif s.count(":") == 1:
		port = int(s.get_slice(":", 1))
		s = s.get_slice(":", 0)
	if s.is_empty() or port <= 0 or port > 65535:
		return {}
	return { "host": s, "port": port }
