class_name EndlessNet
extends Node
## An endless drive online (D159, docs/NETWORKING.md §12). Every game makes the same road and the
## same traffic schedule from the session's seed and the server's clock, and keeps its own floating
## origin round its own players, so little needs sending:
## - which game drives each physics traffic car (its owner): a game with a player near a car asks
##   for it and drives it meanwhile; the first to ask keeps it, the others show it from the owner's
##   states; when the owner lets it go, the next game still asking takes it over where it is;
## - slots used up: a car knocked out of its slot is never drawn again, on any game;
## - where on the road every player is (once a second), for Join and for where a joiner starts;
## - checksums of the road chunks each game made, checked against the server's own.
##   ENDLESS, client -> server: {want, drop, gone: [slots], at: {car id: [distance, speed]}, sums: {chunk: checksum}}
##   ENDLESS_STATE, server -> clients: {owners: {slot: car id, or -1: nobody}, gone: [slots], at: {car id: [distance, time, speed]}, full}

const REPORT_S := 1.0
## Most slots, players' spots and checksums in one report.
const MOST := 64
## Slots used up the server remembers (the oldest are let go: long since out of everyone's range).
const GONE_KEEP := 4096

var session: TrackSession
## The session's traffic (null with traffic off).
var traffic: EndlessTraffic
## Slot id -> the car id of a player in the game that drives that slot's car.
var owners := {}
## Car id -> [road distance (m), server time it was there, speed (m/s)].
var at := {}
## Server: road chunks games made, checked against the server's; those that weren't the same.
var checked := 0
var mismatches := 0
## Owners that changed hands (a game let a car go, another took it on).
var handovers := 0

var _want := {} # this game: slots to ask for, drop and mark used up
var _drop := {}
var _gone := {}
var _report := 0.0
var _car_slot := {} # car id -> slot (the slots with owners)
var _wants := {} # server: slot -> [car ids asking, oldest first]
var _gone_order := PackedInt64Array() # server: slots used up, oldest first
var _gone_set := {}
var _owners_out := {} # server: owner changes not yet sent
var _gone_out := PackedInt64Array()
var _full_sent := {} # server: peer -> true once it has the whole state
var _stats_time := 0.0


func _ready() -> void:
	name = "EndlessNet"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -57 # after the traffic (-58)
	if is_server():
		Net.host_logic.endless_reported.connect(_on_report)
	Net.endless_state.connect(_on_state)


func _exit_tree() -> void:
	if Net.host_logic and Net.host_logic.endless_reported.is_connected(_on_report):
		Net.host_logic.endless_reported.disconnect(_on_report)
	if Net.endless_state.is_connected(_on_state):
		Net.endless_state.disconnect(_on_state)


func is_server() -> bool:
	return Net.server != null and Net.host_logic != null


func is_mine(owner: int) -> bool:
	return owner >= 0 and owner in Net.my_ids


## The game that drives traffic car `car_id` (by a player's car id), or -1.
func owner_of_car(car_id: int) -> int:
	var slot: Variant = _car_slot.get(car_id)
	return int(owners.get(slot, -1)) if slot != null else -1


## Every traffic car with an owner (car ids).
func owned_cars() -> Array:
	return _car_slot.keys()


# --- this game's traffic -------------------------------------------------------------------------


## Asks to drive slot `slot`'s car (a player here is near it).
func want(slot: int) -> void:
	_drop.erase(slot)
	_want[slot] = true


## No player here is near slot `slot`'s car any more.
func drop(slot: int) -> void:
	_want.erase(slot)
	_drop[slot] = true


## Slot `slot`'s car left its slot for good.
func gone(slot: int) -> void:
	_gone[slot] = true


func _physics_process(delta: float) -> void:
	_report -= delta
	var report := _report <= 0.0
	if report:
		_report = REPORT_S
	if not (_want.is_empty() and _drop.is_empty() and _gone.is_empty()) or report:
		var d := { "want": _take(_want), "drop": _take(_drop), "gone": _take(_gone), "at": {}, "sums": {} }
		if report:
			for r: Racer in session.players:
				if r.vehicle and r.net_id > 0:
					d.at[r.net_id] = [r.distance, r.speed]
			var sums: Dictionary = session.endless_world.sums
			for k: int in sums.keys().slice(0, MOST):
				d.sums[k] = sums[k]
				sums.erase(k)
		if is_server():
			_on_report(1, d)
		elif Net.client and Net.client.state == NetClient.State.JOINED:
			Net.request(NetProtocol.Msg.ENDLESS, d)
	if is_server():
		_server_tick(report)


static func _take(d: Dictionary) -> PackedInt64Array:
	var out := PackedInt64Array(d.keys().slice(0, MOST))
	for k in out:
		d.erase(k)
	return out


## The server's word: who drives which car, slots used up, where everyone is.
func _on_state(d: Dictionary) -> void:
	if is_server():
		return # the server keeps its own
	var o: Variant = d.get("owners")
	if o is Dictionary and (o as Dictionary).size() <= GONE_KEEP:
		if d.get("full", false):
			for slot: int in owners.keys():
				if not (o as Dictionary).has(slot):
					_set_owner(slot, -1)
		for slot: Variant in o:
			if slot is int and o[slot] is int:
				_set_owner(slot, o[slot])
	var g: Variant = d.get("gone")
	if g is PackedInt64Array and g.size() <= GONE_KEEP and traffic:
		for slot in g:
			traffic.mark_gone(slot)
	var a: Variant = d.get("at")
	if a is Dictionary and (a as Dictionary).size() <= NetProtocol.MAX_PLAYERS:
		at.clear()
		for id: Variant in a:
			var v: Variant = a[id]
			if id is int and v is Array and (v as Array).size() == 3 and (v as Array).all(func(x: Variant) -> bool: return x is float or x is int):
				at[id] = [float(v[0]), float(v[1]), float(v[2])]


func _set_owner(slot: int, owner: int) -> void:
	var before := int(owners.get(slot, -1))
	if owner < 0:
		owners.erase(slot)
		_car_slot.erase(EndlessTraffic.car_id_of(slot))
	else:
		owners[slot] = owner
		_car_slot[EndlessTraffic.car_id_of(slot)] = slot
	if before >= 0 and owner >= 0 and before != owner:
		handovers += 1
	if traffic and before != owner:
		traffic.set_driver(slot, owner)


## Where car `id` is on the road now (m, from its game's last word), or NAN.
func distance_of(id: int) -> float:
	var v: Array = at.get(id, [])
	if v.is_empty():
		return NAN
	return float(v[0]) + float(v[2]) * clampf(session.net.now() - float(v[1]), 0.0, 5.0) if session.net else float(v[0])


# --- the server ----------------------------------------------------------------------------------


## A game's report (`peer` 1: this one's own players).
func _on_report(peer: int, d: Dictionary) -> void:
	var mine: Array[NetPlayer] = Net.server.players_of(peer)
	if mine.is_empty():
		return
	var rep := mine[0].id
	if not _full_sent.has(peer) and peer != 1:
		_full_sent[peer] = true
		Net.server.send(peer, NetProtocol.Msg.ENDLESS_STATE, { "owners": owners, "gone": _gone_order, "at": at, "full": true })
	for key: String in ["want", "drop", "gone"]:
		if not (d.get(key) is PackedInt64Array and (d[key] as PackedInt64Array).size() <= MOST):
			return
	for slot: int in d.want:
		var asking: Array = _wants.get(slot, [])
		if not rep in asking:
			asking.append(rep)
		_wants[slot] = asking
		if not owners.has(slot):
			_give(slot, rep)
		elif int(owners[slot]) != rep and peer != 1:
			Net.server.send(peer, NetProtocol.Msg.ENDLESS_STATE, { "owners": { slot: owners[slot] } })
	for slot: int in d.drop:
		var asking: Array = _wants.get(slot, [])
		asking.erase(rep)
		if asking.is_empty():
			_wants.erase(slot)
		if int(owners.get(slot, -1)) == rep:
			_give(slot, int(asking[0]) if not asking.is_empty() else -1)
	for slot: int in d.gone:
		if not _gone_set.has(slot):
			_gone_set[slot] = true
			_gone_order.append(slot)
			_gone_out.append(slot)
			if traffic:
				traffic.mark_gone(slot)
	if _gone_order.size() > GONE_KEEP:
		for slot in _gone_order.slice(0, _gone_order.size() - GONE_KEEP):
			_gone_set.erase(slot)
		_gone_order = _gone_order.slice(_gone_order.size() - GONE_KEEP)
	var a: Variant = d.get("at")
	if a is Dictionary and (a as Dictionary).size() <= NetProtocol.MAX_LOCAL:
		for id: Variant in a:
			var v: Variant = a[id]
			if id is int and mine.any(func(p: NetPlayer) -> bool: return p.id == id) and v is Array and (v as Array).size() == 2 \
					and (v as Array).all(func(x: Variant) -> bool: return (x is float or x is int) and is_finite(float(x))):
				at[id] = [float(v[0]), session.net.now() if session.net else 0.0, float(v[1])]
	var sums: Variant = d.get("sums")
	if sums is Dictionary and (sums as Dictionary).size() <= MOST:
		for k: Variant in sums:
			if k is int and sums[k] is int and k >= 0:
				checked += 1
				var c := session.endless_world.gen.chunk(k)
				if int(c.get("checksum", 0)) != int(sums[k]):
					mismatches += 1
					if mismatches <= 5:
						Net.host_logic.log_line.emit("Road differs: chunk %d from %s" % [k, mine[0].name])


func _give(slot: int, owner: int) -> void:
	_set_owner(slot, owner)
	_owners_out[slot] = owner


func _server_tick(report: bool) -> void:
	_stats_time += 1.0 / Engine.physics_ticks_per_second
	if Game.dev.has("net-stats") and _stats_time >= 5.0: # the checks (net_check)
		_stats_time = 0.0
		print("NETCHECK_ENDLESS_SERVER " + JSON.stringify({ "checked": checked, "mismatches": mismatches, "owners": owners.size(),
			"handovers": handovers, "gone": _gone_order.size(), "players": at.size() }))
	if report:
		# Owners whose game has gone: the next game asking, or nobody.
		for slot: int in owners.keys():
			if _peer_of(int(owners[slot])) < 0:
				var asking: Array = (_wants.get(slot, []) as Array).filter(func(id: int) -> bool: return _peer_of(id) >= 0)
				_wants[slot] = asking
				_give(slot, int(asking[0]) if not asking.is_empty() else -1)
		for id: int in at.keys():
			if _peer_of(id) < 0:
				at.erase(id)
		for peer: int in _full_sent.keys():
			if not Net.server.peers.has(peer):
				_full_sent.erase(peer)
		if Net.host_logic:
			Net.host_logic.endless_at = at.duplicate(true)
	if _owners_out.is_empty() and _gone_out.is_empty() and not report:
		return
	var d := { "owners": _owners_out, "gone": _gone_out }
	if report:
		d.at = at
	Net.server.broadcast(NetProtocol.Msg.ENDLESS_STATE, d)
	_owners_out = {}
	_gone_out = PackedInt64Array()


func _peer_of(id: int) -> int:
	var p: NetPlayer = Net.server.players.get(id)
	return p.peer if p else -1
