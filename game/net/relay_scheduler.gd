class_name RelayScheduler
extends RefCounted
## Which car states the server sends each client, and when (D111): every car is due at a rate
## set by how near it is to that client's players (60 a second close by, down to 5 for a far
## player); each relay tick the most overdue fresh states go (time since it was last sent × its
## rate), up to a byte budget, so under load each car keeps a share in proportion to its rate.
## Traffic further than TRAFFIC_FAR_M from all of the client's players isn't sent at all (the
## client shows its lane-sim shadow). A placed car (teleport) always goes first.

const BUDGET_BPS := 56000
const TRAFFIC_FAR_M := 600.0
## [distance (m), states a second]: the first band a car is within sets its rate.
const RATES := [[150.0, 60.0], [400.0, 30.0], [800.0, 15.0]]
const FAR_RATE := 5.0

var _clock := {} # peer -> relay time
var _sent_at := {} # peer -> {car id -> relay time it was last sent}
var _sent := {} # peer -> {car id -> time of the state last sent}


## The states to send `peer` this tick, from `latest` (car id -> newest CarState), given its
## players' positions `near` and the car ids it owns `own` (never sent back), `dt` since the last
## tick. The budget is BUDGET_BPS × dt.
func pick(peer: int, latest: Dictionary, near: PackedVector3Array, own: Dictionary, positions: Dictionary, dt: float) -> Array[CarState]:
	var now := float(_clock.get(peer, 0.0)) + dt
	_clock[peer] = now
	var at: Dictionary = _sent_at.get(peer, {})
	var sent: Dictionary = _sent.get(peer, {})
	_sent_at[peer] = at
	_sent[peer] = sent
	var ready := []
	var given := not positions.is_empty()
	for id: int in latest:
		if own.has(id):
			continue
		var s: CarState = latest[id]
		if s.time <= float(sent.get(id, -1.0)):
			continue # nothing new
		var d := _nearest(near, positions.get(id, s.xform.origin) if given else s.xform.origin)
		var rate := FAR_RATE
		for band: Array in RATES:
			if d < band[0]:
				rate = band[1]
				break
		if id >= NetProtocol.FIRST_TRAFFIC_ID and d > TRAFFIC_FAR_M and not NetProtocol.is_endless_police(id):
			continue
		var due := (now - float(at.get(id, -INF))) * rate
		if s.flags & CarState.FLAG_TELEPORT:
			due += 1000.0
		if due >= 0.999: # a tick's worth at its rate (rounding)
			ready.append([due, id])
	ready.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var budget := int(BUDGET_BPS * dt)
	var out: Array[CarState] = []
	for r: Array in ready:
		if budget < CarState.SIZE and not out.is_empty():
			break
		var id: int = r[1]
		var s: CarState = latest[id]
		out.append(s)
		sent[id] = s.time
		at[id] = now
		budget -= CarState.SIZE
	return out


## Forgets a client (it left).
func drop(peer: int) -> void:
	_clock.erase(peer)
	_sent_at.erase(peer)
	_sent.erase(peer)


## Forgets a car (gone from the session).
func forget(id: int) -> void:
	for peer: int in _sent:
		(_sent_at[peer] as Dictionary).erase(id)
		(_sent[peer] as Dictionary).erase(id)


static func _nearest(points: PackedVector3Array, at: Vector3) -> float:
	var best := INF
	for p in points:
		best = minf(best, p.distance_squared_to(at))
	return sqrt(best)
