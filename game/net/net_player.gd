class_name NetPlayer
extends RefCounted
## One player in an online session (MP-03, LOC-05): a person at some connection, which may bring
## up to four local players. Ids are unique in the server's lifetime (1-255, then reused).
## The server's own players (a listen server's host) are on peer 1.

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
var ready := false


## What everyone sees (fingerprints are shortened).
func to_dict() -> Dictionary:
	return {
		"id": id, "peer": peer, "local": local_index, "name": name, "color": color.to_html(false),
		"fp": NetIdentity.short(fingerprint) if fingerprint else "", "admin": admin,
		"car": car, "car_name": car_name, "family": family, "ready": ready,
	}


## A player from a server's list, or null if it's malformed.
static func from_dict(d: Dictionary) -> NetPlayer:
	if not NetProtocol.has_fields(d, {
		"id": TYPE_INT, "peer": TYPE_INT, "local": TYPE_INT, "name": [TYPE_STRING, NetProtocol.MAX_NAME],
		"color": [TYPE_STRING, 8], "fp": [TYPE_STRING, 24], "admin": TYPE_BOOL, "car": [TYPE_STRING, 80],
		"car_name": [TYPE_STRING, 64], "family": [TYPE_STRING, 16], "ready": TYPE_BOOL,
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
	p.ready = d.ready
	return p
