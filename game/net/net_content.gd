class_name NetContent
extends Node
## Who fetches which content (docs/NETWORKING.md §7, MP-05, D80). Clients fetch every car in the
## session they don't have, tier by tier for all cars at once: everyone's data first (physics
## and a placeholder of the right size), then each car's smallest LOD, then the full models. The
## server fetches each player's car from its owner as soon as it's picked and relays it; it may
## also send its own garage cars (the host's, AI cars), the track and the platform. Own engine
## recordings only travel when the server allows them. A car over the server's size cap stays a
## placeholder ("Car too large for this server").

## A car got a better tier here ("data", "preview", "full").
signal car_changed(car_hash: String)
## A car went over the size cap or failed to arrive.
signal car_refused(car_hash: String, reason: String)
## A platform or track file arrived.
signal file_ready(h: String)

const PRIORITY := { "data": 0, "preview": 10, "full": 20, "audio": 30 }
const TIER_ORDER := ["data", "preview", "full"]
## A track or platform file from a server is at most this big.
const FILE_CAP := 1 << 20

var is_server := false
var index := ContentIndex.new()
## peer -> NetTransfer
var links := {}
## Upload limits for links (bytes/s): whole link, each file.
var link_rate := 8192 * 1024
var file_rate := 2048 * 1024
## Own recordings travel.
var own_sounds := true
## Most bytes a car may be (all its files), or -1.
var car_cap := -1
## Highest tier fetched: "full", or "data" for bots and the dedicated server's AI-only checks.
var max_tier := "full"

var _local := {} # car hash -> package path here (garage, built-ins)
var _local_scanned := false
var _cars := {} # car hash -> {from (peer), tier, files: {rel: file hash}, bytes, refused}
var _wanted := {} # file hash -> [[car hash or "", rel or kind]]
var _send_control: Callable # (peer, type, data)
var _send_raw: Callable # (peer, bytes)


## `send_control(peer, type, data)` and `send_raw(peer, bytes)` reach the other side.
func setup(server_side: bool, send_control: Callable, send_raw: Callable) -> void:
	is_server = server_side
	_send_control = send_control
	_send_raw = send_raw


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -93


var _debug_time := 0.0


func _physics_process(delta: float) -> void:
	for t: NetTransfer in links.values():
		t.tick(delta)
	if Game.dev.has("net-debug"):
		_debug_time += delta
		if _debug_time >= 2.0:
			_debug_time = 0.0
			for peer: int in links:
				print("NETDEBUG %d %s" % [peer, links[peer].debug_line()])


func _exit_tree() -> void:
	for t: NetTransfer in links.values():
		t.close()
	index.close()


## The link to `peer` (made on first use).
func link(peer: int) -> NetTransfer:
	if not links.has(peer):
		var t := NetTransfer.new()
		t.index = index
		t.max_rate = link_rate
		t.file_rate = file_rate
		t.hold_unknown_s = 120.0 if is_server else 0.0
		t.send_control = func(type: int, d: Dictionary) -> void: _send_control.call(peer, type, d)
		t.send_raw = func(bytes: PackedByteArray) -> void: _send_raw.call(peer, bytes)
		t.received.connect(_on_received.bind(peer))
		t.failed.connect(_on_failed.bind(peer))
		links[peer] = t
	return links[peer]


func drop_link(peer: int) -> void:
	var t: NetTransfer = links.get(peer)
	if t:
		t.close()
		links.erase(peer)
	for h: String in _cars.keys():
		if _cars[h].from == peer and _cars[h].tier != "full":
			_cars[h].from = -1 # its owner left; another may still have it


func handle_control(peer: int, type: int, d: Dictionary) -> bool:
	if type < NetProtocol.Msg.WANT or type > NetProtocol.Msg.CANCEL:
		return false
	link(peer).handle_control(type, d)
	return true


func handle_raw(peer: int, bytes: PackedByteArray) -> bool:
	return links.has(peer) and links[peer].handle_raw(bytes)


## Cars on this machine (garage and built-ins), by hash.
func local_cars() -> Dictionary:
	if not _local_scanned:
		_local_scanned = true
		_local = ContentIndex.local_cars()
		if Game.dev.has("bot"): # a bot has only the built-ins (never this machine's garage)
			for h: String in _local.keys():
				if not String(_local[h]).begins_with("res://"):
					_local.erase(h)
	return _local


## Where to load `car_hash` from and how much of it is here: {path, tier, partial}, or {} if
## nothing is here yet (show a placeholder). A refused car gives {refused}.
func car(car_hash: String) -> Dictionary:
	var local := String(local_cars().get(car_hash, ""))
	if local:
		return { "path": local, "tier": "full", "partial": false }
	var c: Dictionary = _cars.get(car_hash, {})
	if c.get("refused", ""):
		return { "refused": c.refused }
	var tier := cached_tier(car_hash)
	if tier.is_empty():
		return {}
	return { "path": ContentStore.car_dir(car_hash), "tier": tier, "partial": tier != "full" }


## The highest tier of a cached car that's all here ("" if not even its data).
static func cached_tier(car_hash: String) -> String:
	var m := ContentStore.car_manifest(car_hash)
	if m.is_empty():
		return ""
	var tiers := ContentStore.tiers(m)
	var best := ""
	for tier: String in TIER_ORDER:
		if not ContentStore.car_missing(car_hash, tiers[tier]).is_empty():
			break
		best = tier
	return best


## Sends a car of ours (garage, built-in or cached) to anyone who asks.
func share_car(car_hash: String) -> void:
	var path := String(local_cars().get(car_hash, ""))
	if path.is_empty() and not ContentStore.car_manifest(car_hash).is_empty():
		path = ContentStore.car_dir(car_hash)
	if path and not index.has(car_hash):
		index.add_package(path)
		_index_changed()


## Sends a plain file (track, platform). Returns its hash.
func share_file(path: String) -> String:
	var h := index.add_file(path)
	_index_changed()
	return h


## Fetches `car_hash` from `peer` up to `tier` (if it isn't here already). `bytes`: what its
## owner says it weighs, checked against the cap.
func fetch_car(car_hash: String, peer: int, tier := "full", bytes := -1) -> void:
	if not ContentStore.valid_hash(car_hash) or local_cars().has(car_hash):
		return
	if TIER_ORDER.find(tier) > TIER_ORDER.find(max_tier):
		tier = max_tier
	var c: Dictionary = _cars.get(car_hash, {})
	if c.is_empty():
		c = { "from": peer, "tier": tier, "files": {}, "bytes": 0, "refused": "", "manifest": false }
		_cars[car_hash] = c
	else:
		if TIER_ORDER.find(tier) > TIER_ORDER.find(c.tier):
			c.tier = tier
		if c.from < 0 or not links.has(c.from):
			c.from = peer
	if c.refused:
		return
	if car_cap >= 0 and bytes > car_cap:
		_refuse(car_hash, "Car too large for this server")
		return
	var m := ContentStore.car_manifest(car_hash)
	if m.is_empty():
		_want(c.from, car_hash, car_hash, "manifest.json", PRIORITY.data)
	else:
		_want_tiers(car_hash, m)
	if is_server:
		share_car(car_hash) # whatever's cached already can go out


## How many files are still on their way.
func pending() -> int:
	var n := 0
	for t: NetTransfer in links.values():
		n += t.pending()
	return n


func _want(peer: int, h: String, car_hash: String, rel: String, priority: int) -> void:
	if peer < 0:
		return
	var list: Array = _wanted.get(h, [])
	var entry := [car_hash, rel]
	if not list.has(entry):
		list.append(entry)
	_wanted[h] = list
	var cap := (car_cap if car_cap >= 0 else -1) if car_hash else FILE_CAP
	link(peer).want(h, priority, cap)


func _want_tiers(car_hash: String, m: Dictionary) -> void:
	var c: Dictionary = _cars[car_hash]
	var tiers := ContentStore.tiers(m)
	var listed: Dictionary = m.files
	var wanted: Array = ["data"]
	for tier: String in ["preview", "full"]:
		if TIER_ORDER.find(tier) <= TIER_ORDER.find(c.tier):
			wanted.append(tier)
	if own_sounds and c.tier == "full":
		wanted.append("audio")
	for tier: String in wanted:
		for rel in ContentStore.car_missing(car_hash, tiers[tier]):
			if rel != "manifest.json":
				_want(c.from, String(listed[rel]), car_hash, rel, PRIORITY[tier])


func _on_received(h: String, bytes: PackedByteArray, _peer: int) -> void:
	var users: Array = _wanted.get(h, [])
	_wanted.erase(h)
	var changed := {}
	for entry: Array in users:
		var car_hash: String = entry[0]
		if car_hash.is_empty():
			if ContentStore.put_file(entry[1], h, bytes).is_empty():
				file_ready.emit(h)
			continue
		var c: Dictionary = _cars.get(car_hash, {})
		if c.is_empty() or c.refused:
			continue
		var before := cached_tier(car_hash)
		var err := ContentStore.put_car_file(car_hash, entry[1], bytes)
		if err:
			push_warning("Car %s: %s: %s" % [car_hash.left(16), entry[1], err])
			continue
		c.bytes += bytes.size()
		if car_cap >= 0 and c.bytes > car_cap:
			_refuse(car_hash, "Car too large for this server")
			continue
		if entry[1] == "manifest.json":
			_want_tiers(car_hash, ContentStore.car_manifest(car_hash))
		if cached_tier(car_hash) != before:
			changed[car_hash] = true
		if is_server:
			index.add_package(ContentStore.car_dir(car_hash))
	if is_server and not users.is_empty():
		_index_changed()
	for car_hash: String in changed:
		car_changed.emit(car_hash)


func _on_failed(h: String, reason: String, _peer: int) -> void:
	var users: Array = _wanted.get(h, [])
	_wanted.erase(h)
	for entry: Array in users:
		if entry[0] and reason == "Too large":
			_refuse(entry[0], "Car too large for this server")
		elif entry[0]:
			push_warning("Car %s: %s: %s" % [String(entry[0]).left(16), entry[1], reason])


func _refuse(car_hash: String, reason: String) -> void:
	var c: Dictionary = _cars.get(car_hash, {})
	if c.is_empty() or c.refused:
		return
	c.refused = reason
	for t: NetTransfer in links.values():
		for h: String in _wanted.keys():
			if _wanted[h].any(func(e: Array) -> bool: return e[0] == car_hash):
				t.unwant(h)
	for h: String in _wanted.keys():
		_wanted[h] = _wanted[h].filter(func(e: Array) -> bool: return e[0] != car_hash)
		if _wanted[h].is_empty():
			_wanted.erase(h)
	car_refused.emit(car_hash, reason)


func _index_changed() -> void:
	for t: NetTransfer in links.values():
		t.index_changed()


## Fetches a plain file (a track or platform) by hash from `peer`, unless it's cached.
func fetch_file(kind: String, h: String, peer: int) -> void:
	if ContentStore.has_file(kind, h):
		return
	_want(peer, h, "", kind, -10)


## The total size of a package's files (what PICK tells the server).
static func package_bytes(path: String) -> int:
	var source := PackageSource.open(path, PackageLoader.DEFAULT_LIMITS)
	var total := 0
	if not source.error:
		for rel in source.files():
			total += source.size_of(rel)
	source.close()
	return total
