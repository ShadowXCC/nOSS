class_name PoliceHeliControl
extends Node
## The police helicopters (D251): one over every player wanted at heat 5 that this game can see,
## its own players and (online) everyone else's. Purely for show: each game makes its own, from
## what it knows of each player's heat (TrackSession.heat_state: the police's own word, the
## server's news, or a remote car's state flags, CarState.FLAG_HELI and FLAG_SEARCH). None on a
## dedicated server or a bot. Looked at every LOOK_S. Only the MOST_LIT nearest a camera here
## cast real light; the rest show their beams.

const LOOK_S := 0.25
const MOST_LIT := 4

var session: TrackSession
## Racer -> PoliceHeli: the ones over a player now.
var helis := {}
## Ones flying off (still heard, and on the HUD's sound arrows till they're gone).
var leaving: Array[PoliceHeli] = []
var _left := 0.0


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0:
		return
	_left = LOOK_S
	update()


## Who's wanted at heat 5 now, and their helicopters to match.
func update() -> void:
	var want := wanted()
	for r: Variant in helis.keys():
		if not is_instance_valid(helis[r]):
			helis.erase(r)
			continue
		var h: PoliceHeli = helis[r]
		if not is_instance_valid(r) or not want.has(r):
			h.leave()
			leaving.append(h)
			helis.erase(r)
	var still: Array[PoliceHeli] = []
	for h: Variant in leaving:
		if is_instance_valid(h) and not (h as PoliceHeli).is_queued_for_deletion():
			still.append(h)
	leaving = still
	for r: Racer in want:
		if not helis.has(r):
			var h := PoliceHeli.new()
			h.session = session
			h.target = r
			h.searching = bool(want[r])
			session.add_child(h)
			helis[r] = h
		(helis[r] as PoliceHeli).searching = bool(want[r])
	_light_nearest()


## Racer -> whether they're getting away, for everyone wanted at heat 5.
func wanted() -> Dictionary:
	var out := {}
	for r in session.racers:
		if r is PoliceRacer or r.vehicle == null or not is_instance_valid(r.vehicle) or r.waiting:
			continue
		if not (r is SessionPlayer or (r is NetRacer and r.is_human)):
			continue
		var hs := session.heat_state(r)
		if hs.x >= Heat.LEVELS.size():
			out[r] = hs.y != 0
	return out


## Every helicopter about, leaving ones too (the HUD's sound arrows).
func all() -> Array[PoliceHeli]:
	var out: Array[PoliceHeli] = []
	for h: Variant in helis.values():
		if is_instance_valid(h):
			out.append(h)
	for h: Variant in leaving:
		if is_instance_valid(h) and not (h as PoliceHeli).is_queued_for_deletion():
			out.append(h)
	return out


## Real light for the MOST_LIT nearest any camera here.
func _light_nearest() -> void:
	var cams: Array[Vector3] = []
	for p in session.players:
		if p.cameras and p.cameras.camera:
			cams.append(p.cameras.camera.global_position)
	var list := all()
	var near := func(h: PoliceHeli) -> float:
		var best := INF
		for c in cams:
			best = minf(best, c.distance_to(h.global_position))
		return best
	list.sort_custom(func(a: PoliceHeli, b: PoliceHeli) -> bool: return near.call(a) < near.call(b))
	for i in list.size():
		list[i].real_light = i < MOST_LIT
