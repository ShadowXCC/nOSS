class_name KartNet
extends Node
## Kart items online (D141, D142, docs/NETWORKING.md §11). The server is the authority: it rolls
## what a box gives, rules on each use and hit, and keeps a battle's lives. A game takes boxes and
## is hit on the cars it drives, and says so; a use shows at once on the user's game (its Bolt
## flies before the server's word comes back) and every game flies each item from where and when
## it was let go. Five times a second the server sends how things stand (boxes, slots, lives,
## what's out), which heals drift and brings a joiner up to date. A hit the server clearly saw
## and nobody reported in time is forced (the backstop).
##   [106][time u32][boxes u16 + bitmask][cars u8 × 8 B][entities u8 × 28 B]   KART_STATE, server -> clients, 5 Hz
## An entity: id u16 · kind u8 · owner u16 · target u16 · pos i32 ×3 (mm) · vel f16 ×3 ·
## bounces u8 · age u16 (ms): compared at the same age, items agree whatever each game's clock.
##   [111][32-byte records…]   KART_EVENTS, server -> clients, reliable
##   [112][32-byte records…]   KART_REPORT, client -> server, reliable
## A record: kind u8 · seq u16 · time u32 (ms) · entity u16 · car u16 · other u16 · item u8 ·
## extra u8 · pos i32 ×3 (mm) · yaw i16 · pitch i16 · spare u8.

const MSG_STATE := 106
const MSG_EVENTS := 111
const MSG_REPORT := 112
const RECORD := 32
const CAR_BYTES := 8
const ENTITY_BYTES := 28
const STATE_HZ := 5.0
enum Ev { SPAWN = 1, GONE, BOX_TAKEN, BOX_BACK, GOT, HIT, USE, PULSE, LIFE, OUT, REJECT, PICK }
## extra bits: HIT
const HIT_BLOCKED := 1
const HIT_FORCED := 2
## extra bits: USE
const USE_BACK := 1
## The server's checks.
const PICK_M := 6.0
const USE_RATE_S := 0.25
const USE_NEAR_M := 8.0
const USE_CLOCK_S := 0.5
const HIT_NEAR_M := 3.0
const BACKSTOP_CHECKS := 2
const BACKSTOP_SLACK_S := 0.25
## A client's entities this far from the server's are put where the server has them.
const CORRECT_M := 2.0
## Entity ids: the server's below PREDICTED, a client's own (until the server's word) from there.
const PREDICTED := 40000
const MAX_CATCH_UP_S := 1.0

var session: TrackSession
var kart: KartControl
## Counters (net_check): reports turned down (picks: often two karts at one box; uses; hits),
## forced hits, corrections, hits validated.
var rejected := 0
## Hits on an item the server had just ruled had hit another kart: two karts' games each saw it
## hit theirs, the server's first word stands (not a disagreement).
var contested := 0
var rejected_picks := 0
var rejected_uses := 0
var forced := 0
var corrections := 0
var validated := 0
## How far (m) this client's items were from the server's, last snapshot (net_check): Bolts and
## Slicks, whose paths are set when they're let go; and Seekers and the Hunter, which home on each
## game's own view of their target (corrected past CORRECT_M).
var entity_errors: Array[float] = []
var chaser_errors: Array[float] = []

var _seq := 0
var _next_server_id := 1
var _next_predicted := PREDICTED
var _predicted := {} # client: "car:seq" -> local entity id
var _applied := {} # client: entity id -> true (each hits this game's car at most once)
var _last_use := {} # server: car id -> time
var _overlaps := {} # server: "entity:car" -> {checks, since}
var _reported := {} # server: entity id -> time a hit on it was reported
var _hit_gone := {} # server: entity id -> time a hit took it
var _state_time := 0.0
var _states: Array[PackedByteArray] = [] # client: snapshots in, read at its next tick


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -56 # after KartItems moves what's out (-57): states as of this tick
	kart.items.net = self
	if is_server():
		Net.server.raw.connect(_on_server_raw)
		kart.items.got.connect(_on_got)
		kart.boxes.changed.connect(_on_box)
		if session.battle:
			session.battle.life_lost.connect(func(r: Racer, lives: int) -> void: _broadcast([_record(Ev.LIFE, 0, 0, r.net_id, 0, 0, lives)]))
			session.battle.knocked_out.connect(func(r: Racer) -> void: _broadcast([_record(Ev.OUT, 0, 0, r.net_id)]))
	else:
		Net.client.raw.connect(_on_client_raw)
		if session.battle:
			session.battle.authority = false


func _exit_tree() -> void:
	if Net.server and Net.server.raw.is_connected(_on_server_raw):
		Net.server.raw.disconnect(_on_server_raw)
	if Net.client and Net.client.raw.is_connected(_on_client_raw):
		Net.client.raw.disconnect(_on_client_raw)


func is_server() -> bool:
	return Net.server != null


func now() -> float:
	return session.net.now() if session and session.net else ClockSync.local_now()


func _physics_process(delta: float) -> void:
	if not is_server():
		# The newest snapshot, compared with this game's items as of this same tick.
		if not _states.is_empty():
			_on_state(_states.back())
			_states.clear()
		return
	_state_time += delta
	if _state_time >= 1.0 / STATE_HZ:
		_state_time = 0.0
		var p := pack_state()
		for peer: int in Net.server.peers:
			if peer != 1:
				Net.server.send_raw(peer, p, NetProtocol.CH_STATE)
	_backstop()


# --- what KartItems asks (this game's cars) -----------------------------------------------

## Client: one of this game's cars drove through box `box` (the server decides what it gives).
func report_pick(r: Racer, box: int) -> void:
	_report([_record(Ev.PICK, 0, box, r.net_id, 0, 0, 0, r.com())])


## Client: a use of `item`, from `pos` along `dir`; `e` the entity shown at once ({} for none).
func report_use(r: Racer, item: String, pos: Vector3, dir: Vector3, back: bool, e: Dictionary) -> void:
	_seq = (_seq + 1) & 0xFFFF
	if not e.is_empty():
		_predicted["%d:%d" % [r.net_id, _seq]] = int(e.id)
	_report([_record(Ev.USE, _seq, int(e.get("id", 0)), r.net_id, _target_id(e), _item_code(item), USE_BACK if back else 0, pos, dir)])


## Client: entity `e` hit this game's car `r` (the effect is already on it).
func report_hit(r: Racer, e: Dictionary, kind: String, blocked: bool) -> void:
	_applied[int(e.get("id", 0))] = true
	_report([_record(Ev.HIT, 0, int(e.get("id", 0)), r.net_id, 0, _item_code(kind), HIT_BLOCKED if blocked else 0, r.com())])


## A new client-side entity id, until the server's word.
func predict_id() -> int:
	_next_predicted += 1
	if _next_predicted > 0xFFFF:
		_next_predicted = PREDICTED + 1
	return _next_predicted


## A new server entity id.
func server_id() -> int:
	_next_server_id += 1
	if _next_server_id >= PREDICTED:
		_next_server_id = 1
	return _next_server_id


## Server: entity `e` was let go by car `owner` (its use number `seq`, 0 for the server's own
## cars) at `at_time` (-1: now), from where it is now: every game flies it from there and then.
func spawned(e: Dictionary, owner: Racer, seq: int, at_time := -1.0) -> void:
	var vel: Vector3 = e.vel
	var dir := vel.normalized() if vel.length() > 0.01 else owner.vehicle.global_basis.z if owner.vehicle else Vector3.FORWARD
	var extra := 1 if e.has("fly") else 0
	_broadcast([_record(Ev.SPAWN, seq, int(e.id), owner.net_id, _target_id(e), _item_code(String(e.kind)), extra,
		e.get("from", e.pos) if e.has("fly") else e.pos, dir, at_time)])


## Server: entity `id` is gone (a hit, a crash into another item, its time up).
func gone(id: int, by_hit := true) -> void:
	if by_hit:
		_hit_gone[id] = now()
	_broadcast([_record(Ev.GONE, 0, id)])


## Server: an EMP from `owner` at `pos` reached `victims` (in the server's view).
func pulse(owner: Racer, pos: Vector3, victims: Array) -> void:
	var recs: Array = [_record(Ev.PULSE, 0, 0, owner.net_id, 0, _item_code("emp"), 0, pos)]
	for v: Racer in victims:
		recs.append(_record(Ev.HIT, 0, 0, v.net_id, owner.net_id, _item_code("emp"), HIT_FORCED, v.com()))
	_broadcast(recs)


# --- the server -----------------------------------------------------------------------------

func _on_server_raw(peer: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty() or bytes[0] != MSG_REPORT or (bytes.size() - 1) % RECORD != 0 or bytes.size() > 1 + RECORD * 32:
		return
	for k in (bytes.size() - 1) / RECORD:
		var rec := read(bytes, 1 + k * RECORD, now())
		var r: Racer = session.net.racers.get(int(rec.car))
		if r == null or session.net._peer_of(r.net_id) != peer:
			continue # only for its own cars
		match int(rec.kind):
			Ev.PICK:
				_server_pick(r, int(rec.entity), rec.pos)
			Ev.USE:
				_server_use(peer, r, rec)
			Ev.HIT:
				_server_hit(r, rec)


func _server_pick(r: Racer, box: int, pos: Vector3) -> void:
	var boxes := kart.boxes
	if box < 0 or box >= boxes.count() or not boxes.alive[box] or pos.distance_to(boxes.points[box]) > PICK_M \
			or r.com().distance_to(boxes.points[box]) > PICK_M + 4.0:
		rejected_picks += 1
		return
	boxes.take(box)
	kart.items.pick(r, box)


func _server_use(peer: int, r: Racer, rec: Dictionary) -> void:
	var items := kart.items
	var item := _item_of(int(rec.item))
	var t := now()
	var ok := item != "" and items.item_of(r) == item and t - float(_last_use.get(r.net_id, -INF)) >= USE_RATE_S \
		and absf(float(rec.time) - t) <= USE_CLOCK_S + Net.server.rtt_ms(peer) / 1000.0 and (rec.pos as Vector3).distance_to(r.com()) <= USE_NEAR_M
	if not ok:
		rejected_uses += 1
		_why("use of %s by car %d turned down" % [item, r.net_id])
		_send(peer, [_record(Ev.REJECT, int(rec.seq), int(rec.entity), r.net_id, 0, int(rec.item))])
		return
	_last_use[r.net_id] = t
	var target: Racer = session.net.racers.get(int(rec.other))
	items.use_from(r, rec.pos, rec.dir, int(rec.extra) & USE_BACK != 0, int(rec.seq), target, float(rec.time))


func _server_hit(r: Racer, rec: Dictionary) -> void:
	var items := kart.items
	var kind := _item_of(int(rec.item))
	var blocked := int(rec.extra) & HIT_BLOCKED != 0
	var id := int(rec.entity)
	if kind == "emp":
		return # EMPs are the server's to call (pulse)
	var e: Dictionary = kart.entities.list.get(id, {})
	if e.is_empty():
		if _hit_gone.has(id):
			contested += 1
			return
		rejected += 1
		_why("hit on car %d by entity %d (%s): gone here" % [r.net_id, id, kind])
		return
	var slack := HIT_NEAR_M + r.vehicle.linear_velocity.length() * 0.1 if r.vehicle else HIT_NEAR_M
	if (e.pos as Vector3).distance_to(r.com()) > slack + float(e.radius) + KartEntities.KART_RADIUS:
		rejected += 1
		_why("hit on car %d by %s: %.1f m apart here" % [r.net_id, kind, (e.pos as Vector3).distance_to(r.com())])
		return
	_reported[id] = now()
	_hit_gone[id] = now()
	validated += 1
	kart.entities.remove(id)
	items.land(r, e.owner, kind, blocked)
	_broadcast([_record(Ev.HIT, 0, id, r.net_id, e.owner.net_id if e.owner else 0, int(rec.item), int(rec.extra), r.com())])


## A hit the server sees clearly twice running that its victim's game hasn't reported within its
## round trip and a margin: forced, the owner's game applies it.
func _backstop() -> void:
	var t := now()
	var seen := {}
	for r in session.racers:
		if r.vehicle == null or r.towed or r.out or session.net.owned.has(r.net_id):
			continue
		var peer := session.net._peer_of(r.net_id)
		if peer <= 1:
			continue
		for e in kart.entities.touching(r, r.com()):
			var key := "%d:%d" % [int(e.id), r.net_id]
			seen[key] = true
			var o: Dictionary = _overlaps.get(key, { "checks": 0, "since": t })
			o.checks = int(o.checks) + 1
			_overlaps[key] = o
			var wait := Net.server.rtt_ms(peer) / 1000.0 + BACKSTOP_SLACK_S
			if int(o.checks) >= BACKSTOP_CHECKS and t - float(o.since) > wait and not _reported.has(int(e.id)):
				forced += 1
				_hit_gone[int(e.id)] = t
				var kind := String(e.kind)
				kart.entities.remove(int(e.id))
				kart.items.land(r, e.owner, kind, kart.items.slot(r).shield > 0.0)
				_broadcast([_record(Ev.HIT, 0, int(e.id), r.net_id, e.owner.net_id if e.owner else 0, _item_code(kind), HIT_FORCED, r.com())])
				_overlaps.erase(key)
	for key: String in _overlaps.keys():
		if not seen.has(key):
			_overlaps.erase(key)
	for id: int in _reported.keys():
		if t - float(_reported[id]) > 5.0:
			_reported.erase(id)
	for id: int in _hit_gone.keys():
		if t - float(_hit_gone[id]) > 5.0:
			_hit_gone.erase(id)


## Why a report was turned down (the server's log under --net-stats).
func _why(text: String) -> void:
	if Game.dev.has("net-stats"):
		print("KART_REJECT " + text)


func _on_got(r: Racer, item: String) -> void:
	_broadcast([_record(Ev.GOT, 0, 0, r.net_id, 0, _item_code(item))])


func _on_box(i: int, on: bool) -> void:
	_broadcast([_record(Ev.BOX_BACK if on else Ev.BOX_TAKEN, 0, i)])


## How things stand (KART_STATE).
func pack_state() -> PackedByteArray:
	var p := PackedByteArray([MSG_STATE])
	p.resize(5)
	p.encode_u32(1, int(now() * 1000.0) & 0xFFFFFFFF)
	var boxes := kart.boxes
	var n := mini(boxes.count(), 0xFFFF)
	var head := p.size()
	p.resize(head + 2 + (n + 7) / 8)
	p.encode_u16(head, n)
	for i in n:
		if boxes.alive[i]:
			p[head + 2 + i / 8] |= 1 << (i % 8)
	var cars := session.racers.filter(func(r: Racer) -> bool: return r.vehicle != null).slice(0, 255)
	head = p.size()
	p.resize(head + 1 + cars.size() * CAR_BYTES)
	p[head] = cars.size()
	for k in cars.size():
		var r: Racer = cars[k]
		var at := head + 1 + k * CAR_BYTES
		var s := kart.items.slot(r)
		p.encode_u16(at, r.net_id)
		p[at + 2] = _item_code(String(s.item))
		p[at + 3] = clampi(int(s.count), 0, 255)
		p[at + 4] = clampi(session.battle.lives(r), 0, 255) if session.battle else 0
		p[at + 5] = clampi(session.battle.hits(r), 0, 255) if session.battle else 0
		p[at + 6] = clampi(roundi(float(s.shield) * 10.0), 0, 255)
		p[at + 7] = (1 if r.out else 0) | (2 if float(s.roulette) > 0.0 else 0)
	var ents := kart.entities.list.values().slice(0, 255)
	head = p.size()
	p.resize(head + 1 + ents.size() * ENTITY_BYTES)
	p[head] = ents.size()
	for k in ents.size():
		var e: Dictionary = ents[k]
		var at := head + 1 + k * ENTITY_BYTES
		p.encode_u16(at, int(e.id))
		p[at + 2] = _item_code(String(e.kind))
		p.encode_u16(at + 3, e.owner.net_id if e.owner and is_instance_valid(e.owner) else 0)
		p.encode_u16(at + 5, e.target.net_id if e.target and is_instance_valid(e.target) else 0)
		var pos: Vector3 = e.pos
		for c in 3:
			p.encode_s32(at + 7 + c * 4, clampi(roundi(pos[c] * 1000.0), -2147483647, 2147483647))
		var vel: Vector3 = e.vel
		for c in 3:
			p.encode_half(at + 19 + c * 2, vel[c])
		p[at + 25] = clampi(int(e.bounces), 0, 255)
		p.encode_u16(at + 26, clampi(roundi(float(e.age) * 1000.0), 0, 65535))
	return p


# --- a client -------------------------------------------------------------------------------

func _on_client_raw(bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	match bytes[0]:
		MSG_EVENTS:
			if (bytes.size() - 1) % RECORD != 0:
				return
			for k in (bytes.size() - 1) / RECORD:
				_on_event(read(bytes, 1 + k * RECORD, now()))
		MSG_STATE:
			_states.append(bytes)


func _on_event(rec: Dictionary) -> void:
	var items := kart.items
	var r: Racer = session.net.racers.get(int(rec.car))
	match int(rec.kind):
		Ev.SPAWN:
			if r == null:
				return
			var key := "%d:%d" % [r.net_id, int(rec.seq)]
			if _predicted.has(key):
				# Ours: the shown one takes the server's id.
				kart.entities.rekey(int(_predicted[key]), int(rec.entity))
				_predicted.erase(key)
				return
			if kart.entities.list.has(int(rec.entity)):
				return
			var kind := _item_of(int(rec.item))
			if kind == "":
				return
			var e := kart.entities.spawn(kind, r, rec.pos, rec.dir, session.net.racers.get(int(rec.other)), int(rec.entity), int(rec.extra) & 1 != 0)
			kart.entities.advance(e, clampf(now() - float(rec.time), 0.0, MAX_CATCH_UP_S))
		Ev.GONE:
			kart.entities.remove(int(rec.entity))
		Ev.BOX_TAKEN:
			kart.boxes.take(int(rec.entity))
		Ev.BOX_BACK:
			kart.boxes.set_alive(int(rec.entity), true)
		Ev.GOT:
			if r:
				items.give(r, _item_of(int(rec.item)))
		Ev.HIT:
			var id := int(rec.entity)
			kart.entities.remove(id)
			var mine := r != null and items.local(r)
			if mine and (id == 0 or not _applied.has(id)):
				# Forced (or an EMP, id 0): this game's car takes it now, once.
				_applied[id] = true
				items.hit_by(r, _item_of(int(rec.item)), session.net.racers.get(int(rec.other)))
			elif r and not mine:
				items.land(r, session.net.racers.get(int(rec.other)), _item_of(int(rec.item)), int(rec.extra) & HIT_BLOCKED != 0)
		Ev.PULSE:
			if r:
				items.pulse_shown.emit(r, rec.pos)
		Ev.LIFE:
			if r and session.battle:
				session.battle.apply_net(r, int(rec.item), session.battle.hits(r), r.out)
		Ev.OUT:
			if r and session.battle:
				session.battle.apply_net(r, 0, session.battle.hits(r), true)
		Ev.REJECT:
			# Not ours to use after all: the shown item goes, the slot is the server's again.
			var key := "%d:%d" % [int(rec.car), int(rec.seq)]
			if _predicted.has(key):
				kart.entities.remove(int(_predicted[key]))
				_predicted.erase(key)


func _on_state(bytes: PackedByteArray) -> void:
	if bytes.size() < 8:
		return
	var age := clampf(now() - _unwrap(bytes.decode_u32(1)), 0.0, MAX_CATCH_UP_S)
	var at := 5
	var n := bytes.decode_u16(at)
	at += 2
	var mask := bytes.slice(at, at + (n + 7) / 8)
	at += (n + 7) / 8
	var boxes := kart.boxes
	if n == boxes.count() and mask.size() == (n + 7) / 8:
		for i in n:
			var on := mask[i / 8] & (1 << (i % 8)) != 0
			if bool(boxes.alive[i]) != on:
				boxes.set_alive(i, on)
	if at >= bytes.size():
		return
	var cars := bytes[at]
	at += 1
	if bytes.size() < at + cars * CAR_BYTES + 1:
		return
	for k in cars:
		var c := at + k * CAR_BYTES
		var r: Racer = session.net.racers.get(bytes.decode_u16(c))
		if r == null:
			continue
		var s := kart.items.slot(r)
		if not kart.items.local(r):
			s.item = _item_of(bytes[c + 2])
			s.count = bytes[c + 3]
			s.shield = bytes[c + 6] / 10.0
		if session.battle:
			session.battle.apply_net(r, bytes[c + 4], bytes[c + 5], bytes[c + 7] & 1 != 0)
	at += cars * CAR_BYTES
	var count := bytes[at]
	at += 1
	if bytes.size() != at + count * ENTITY_BYTES:
		return
	var seen := {}
	entity_errors.clear()
	chaser_errors.clear()
	for k in count:
		var c := at + k * ENTITY_BYTES
		var id := bytes.decode_u16(c)
		seen[id] = true
		var pos := Vector3(bytes.decode_s32(c + 7), bytes.decode_s32(c + 11), bytes.decode_s32(c + 15)) / 1000.0
		var vel := Vector3(bytes.decode_half(c + 19), bytes.decode_half(c + 21), bytes.decode_half(c + 23))
		var server_age := bytes.decode_u16(c + 26) / 1000.0
		var e: Dictionary = kart.entities.list.get(id, {})
		# Where the server's would be at this one's age (a joiner's: at the snapshot's age now).
		pos += vel * ((float(e.age) - server_age) if not e.is_empty() else age)
		if e.is_empty():
			# A joiner's, or a spawn that came late: here from now on.
			var kind := _item_of(bytes[c + 2])
			var owner: Racer = session.net.racers.get(bytes.decode_u16(c + 3))
			if kind != "" and owner and not _applied.has(id):
				e = kart.entities.spawn(kind, owner, pos, vel if vel.length() > 0.01 else Vector3.FORWARD, session.net.racers.get(bytes.decode_u16(c + 5)), id)
				e.vel = vel
				e.age = server_age + age # as old as the server's, now
				e.bounces = bytes[c + 25]
			continue
		if int(e.bounces) != bytes[c + 25]:
			continue # a wall between the two (moving one on to the other's age crosses a bounce)
		var err := (e.pos as Vector3).distance_to(pos)
		(chaser_errors if e.kind in ["seeker", "leader_hunter"] else entity_errors).append(err)
		if err > 1.0 and Game.dev.has("kart-debug"):
			print("KARTDBG %s id %d err %.1f age %.2f/%.2f bounces %d/%d owner %s here %s server %s" % [e.kind, id, err, float(e.age), server_age,
				int(e.bounces), bytes[c + 25], e.owner.display_name if e.owner and is_instance_valid(e.owner) else "?", (e.pos as Vector3).snapped(Vector3.ONE * 0.1), pos.snapped(Vector3.ONE * 0.1)])
		if err > CORRECT_M:
			corrections += 1
			e.pos = pos
			e.vel = vel
			e.bounces = bytes[c + 25]
			if e.kind == "oil_slick" and not e.has("fly"):
				kart.entities.place_on_road(e)
			if e.kind in ["seeker", "leader_hunter"] and session.track.arena == null:
				# A chaser goes by its place along the road: that moves too.
				var proj := session.track.project(pos)
				e.s = float(proj.distance)
				e.lat = float(proj.lateral)
	# Gone on the server (a hit its word of was lost): gone here too. Ours not yet confirmed stay.
	for id: int in kart.entities.list.keys():
		if id < PREDICTED and not seen.has(id):
			kart.entities.remove(id)


# --- records --------------------------------------------------------------------------------

func _record(kind: int, seq := 0, entity := 0, car := 0, other := 0, item := 0, extra := 0, pos := Vector3.ZERO, dir := Vector3.ZERO, at_time := -1.0) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(RECORD)
	b[0] = kind
	b.encode_u16(1, seq & 0xFFFF)
	b.encode_u32(3, int((at_time if at_time >= 0.0 else now()) * 1000.0) & 0xFFFFFFFF)
	b.encode_u16(7, entity & 0xFFFF)
	b.encode_u16(9, car & 0xFFFF)
	b.encode_u16(11, other & 0xFFFF)
	b[13] = item & 0xFF
	b[14] = extra & 0xFF
	for c in 3:
		b.encode_s32(15 + c * 4, clampi(roundi(pos[c] * 1000.0), -2147483647, 2147483647))
	var flat := Vector2(dir.x, dir.z)
	b.encode_s16(27, roundi(wrapf(atan2(dir.x, dir.z), -PI, PI) / PI * 32767.0) if flat.length() > 1e-4 else 0)
	b.encode_s16(29, roundi(clampf(atan2(dir.y, maxf(flat.length(), 1e-6)), -PI / 2.0, PI / 2.0) / PI * 32767.0))
	return b


## A record at `at` in `bytes` ({kind, seq, time (server s), entity, car, other, item, extra, pos,
## dir}); `time_base` unwraps the 32-bit milliseconds.
static func read(bytes: PackedByteArray, at: int, time_base := 0.0) -> Dictionary:
	var ms := bytes.decode_u32(at + 3)
	var base_ms := int(time_base * 1000.0)
	var full := (base_ms & ~0xFFFFFFFF) | ms
	if full - base_ms > 0x7FFFFFFF:
		full -= 0x100000000
	elif base_ms - full > 0x7FFFFFFF:
		full += 0x100000000
	var yaw := bytes.decode_s16(at + 27) / 32767.0 * PI
	var pitch := bytes.decode_s16(at + 29) / 32767.0 * PI
	return {
		"kind": bytes[at], "seq": bytes.decode_u16(at + 1), "time": full / 1000.0, "entity": bytes.decode_u16(at + 7),
		"car": bytes.decode_u16(at + 9), "other": bytes.decode_u16(at + 11), "item": bytes[at + 13], "extra": bytes[at + 14],
		"pos": Vector3(bytes.decode_s32(at + 15), bytes.decode_s32(at + 19), bytes.decode_s32(at + 23)) / 1000.0,
		"dir": Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)),
	}


func _broadcast(recs: Array) -> void:
	if recs.is_empty():
		return
	var p := PackedByteArray([MSG_EVENTS])
	for r: PackedByteArray in recs:
		p.append_array(r)
	for peer: int in Net.server.peers:
		if peer != 1:
			Net.server.send_raw(peer, p, NetProtocol.CH_EVENTS, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _send(peer: int, recs: Array) -> void:
	var p := PackedByteArray([MSG_EVENTS])
	for r: PackedByteArray in recs:
		p.append_array(r)
	Net.server.send_raw(peer, p, NetProtocol.CH_EVENTS, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


func _report(recs: Array) -> void:
	var p := PackedByteArray([MSG_REPORT])
	for r: PackedByteArray in recs:
		p.append_array(r)
	Net.client.send_raw(p, NetProtocol.CH_EVENTS, MultiplayerPeer.TRANSFER_MODE_RELIABLE)


## The full server time of a 32-bit millisecond stamp, nearest now.
func _unwrap(ms: int) -> float:
	var base_ms := int(now() * 1000.0)
	var full := (base_ms & ~0xFFFFFFFF) | ms
	if full - base_ms > 0x7FFFFFFF:
		full -= 0x100000000
	elif base_ms - full > 0x7FFFFFFF:
		full += 0x100000000
	return full / 1000.0


static func _item_code(item: String) -> int:
	return ItemOdds.ITEMS.find(item) + 1


static func _item_of(code: int) -> String:
	return ItemOdds.ITEMS[code - 1] if code >= 1 and code <= ItemOdds.ITEMS.size() else ""


func _target_id(e: Dictionary) -> int:
	var t: Variant = e.get("target")
	return (t as Racer).net_id if t is Racer and is_instance_valid(t) else 0
