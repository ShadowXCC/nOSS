class_name NetPlayer
extends RefCounted
## One player in an online session (MP-03, LOC-05): a person at some connection, which may bring
## up to four local players. Ids are unique in the server's lifetime (1-255, then reused).
## The server's own players (a listen server's host) are on peer 1.

## Devices a player can say they drive with.
const DEVICES := ["keyboard", "xbox", "playstation", "wheel"]

var id := 0
## The connection that owns this player (1: the server itself).
var peer := 0
## Which local player on that connection (0-3).
var local_index := 0
var name := "Player"
var color := Color.WHITE
var fingerprint := ""
var admin := false
## The car: its package hash ("sha256:…"), shown name and family; "" until picked.
var car := ""
var car_name := ""
var family := ""
## A kart session's class this player picked (D149), "" for the server's.
var kart_class := ""
## Why the car can't be shown ("Car too large for this server"), or "".
var car_note := ""
var ready := false
## What they drive with: "keyboard", "xbox", "playstation" (a controller's glyphs), "wheel", or "".
var device := ""
## The assists they have on (AssistRules ids: "abs", "tcs"...), for the lobby's roster.
var assists := PackedStringArray()
## Round trip to the server in ms (0 for the server's own players).
var ping := 0


## What everyone sees (fingerprints are shortened).
func to_dict() -> Dictionary:
	return {
		"id": id, "peer": peer, "local": local_index, "name": name, "color": color.to_html(false),
		"fp": NetIdentity.short(fingerprint) if fingerprint else "", "admin": admin,
		"car": car, "car_name": car_name, "family": family, "class": kart_class, "car_note": car_note, "ready": ready,
		"device": device, "assists": Array(assists), "ping": ping,
	}


## A player from a server's list, or null if it's malformed.
static func from_dict(d: Dictionary) -> NetPlayer:
	if not NetProtocol.has_fields(d, {
		"id": TYPE_INT, "peer": TYPE_INT, "local": TYPE_INT, "name": [TYPE_STRING, NetProtocol.MAX_NAME],
		"color": [TYPE_STRING, 8], "fp": [TYPE_STRING, 24], "admin": TYPE_BOOL, "car": [TYPE_STRING, 80],
		"car_name": [TYPE_STRING, 64], "family": [TYPE_STRING, 16], "class": [TYPE_STRING, 64], "car_note": [TYPE_STRING, 64], "ready": TYPE_BOOL,
		"device": [TYPE_STRING, 16], "assists": [TYPE_ARRAY, 16], "ping": TYPE_INT,
	}):
		return null
	var p := NetPlayer.new()
	p.id = d.id
	p.peer = d.peer
	p.local_index = d.local
	p.name = NetProtocol.clean_name(d.name)
	p.color = Color.from_string(d.color, Color.WHITE)
	p.fingerprint = d.fp
	p.admin = d.admin
	p.car = d.car
	p.car_name = d.car_name
	p.family = d.family
	p.kart_class = d["class"]
	p.car_note = d.car_note
	p.ready = d.ready
	p.device = d.device if d.device in DEVICES else ""
	p.assists = clean_assists(d.assists)
	p.ping = clampi(d.ping, 0, 9999)
	return p


## The known assist ids in `list`, each once.
static func clean_assists(list: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if list is Array:
		for a: Variant in list:
			if a is String and a in AssistRules.ALL and not a in out:
				out.append(a)
	return out
