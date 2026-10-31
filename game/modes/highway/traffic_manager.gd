class_name TrafficManager
extends Node
## A highway session's traffic (D108-D110, D120): the lane sim (NossTraffic) stepped 20 times a
## second; distant traffic drawn from it, one MultiMesh per type; traffic near players turned into
## physics cars (TrafficCar) and back into the lane sim when nobody is near; wrecks left where they
## stopped until towed; stand-in boxes for lane cars right next to a player that aren't physics
## cars (yet); a cap on physics cars that drops when physics gets slow; and garage cars in the
## traffic (D239: GarageModels), each car's pick fixed for the session.
##
## Offline this game decides everything (authority); online the server does (HighwayNet, D109):
## its events land a little ahead (`lead`) so they reach every game in time, and each game's lane
## sim, stepped by the server's clock, takes them at the same tick. A promoted car's physics run
## on its owner's game (the nearest player's, or the server's); the others show a proxy.

## Lane cars this close to a player (or police) become physics cars; physics cars this far from
## everyone go back to the lane sim. A wreck stays until nobody is within R_OUT, then it's towed.
const R_IN := 150.0
const R_OUT := 200.0
## A physics car nobody has been near for this long goes back even off its lane's line (where its
## shadow is).
const FORCE_BACK_S := 3.0
## A proxy within this of a car this game drives moves every tick (see TrafficCar.FAR_EVERY).
const NEAR_DRIVEN_M := 80.0
## Physics cars at most: in each game, and near one player, by the traffic's count (D238: the
## busier the road, the more cars near a player): [cars from, per game, per player, stand-in
## boxes]. This game's own cap (`cap`) drops from its per-game cap when its physics gets slow;
## online it limits only the cars this game drives.
const CAPS := [[0, 24, 12, 16], [400, 32, 16, 16], [650, 48, 24, 24]]
const CAP_GAME := 24
const CAP_PLAYER := 12
const CAP_MIN := 4
## Physics this slow (ms a frame) for 2 s trims the cap by 2; under half of it for 10 s, it grows
## back by 1.
const SLOW_MS := 6.0
## Stand-in boxes for lane cars this close to a player (at most `boxes` of them).
const BOX_M := 40.0
const BOXES := 16
## Distant traffic is drawn this far from a camera.
const VIEW_M := 1500.0
const DECIDE_S := 0.25
## Online: a physics car hands over to another player's game once that player has been clearly
## nearer this long (its owner's player beyond HAND_FAR_M, or HAND_RATIO times as far and more
## than HAND_MIN_M away, the other within HAND_NEAR_M), and not again for HAND_AGAIN_S. Players
## driving together keep their cars where they are.
const HAND_FAR_M := 220.0
const HAND_RATIO := 2.5
const HAND_MIN_M := 50.0
const HAND_NEAR_M := 120.0
const HAND_S := 1.0
const HAND_AGAIN_S := 5.0
## The lane sim's ticks a second (native traffic_sim.h TICK_HZ).
const TICK_HZ := 20
## Garage cars in the traffic (D239): a car's pick holds for the session (the same cars come round
## again). Looked at every STREAM_S: its far view loads while it's within GARAGE_FAR_M of a camera,
## its whole model while within GARAGE_NEAR_M of a player here, the nearest MOST_WHOLE at most (on
## a loop nearly every car comes within 600 m). What a car is drawn as only changes while it's out
## of sight (VIEW_M + 50 m from every camera), or in the first SETTLE_S while the views are made.
## A physics car that started as the stock car (its model wasn't here yet) becomes its garage car
## once it is, while no player's camera sees it (D241): SWAPS_PER_STREAM at most a time. Offline
## every car's loaded before the drive (D246), so none starts as a stand-in; a stand-in is an
## online car not in by the start.
const STREAM_S := 0.5
const GARAGE_FAR_M := VIEW_M + 500.0
const GARAGE_NEAR_M := 400.0
const MOST_WHOLE := 24
const SETTLE_S := 5.0
const SWAPS_PER_STREAM := 2
## Ids members() gives racers (their index added).
const RACER_ID := 10000
## Event kinds (NossTraffic, D109). HANDOVER moves a physics car to another game; the lane sim
## never sees it.
const PROMOTE := 1
const DEMOTE := 2
const HANDOVER := 3
const WRECK := 4
const TOW := 5
const CLOSE := 6
const OPEN := 7
const RESHADOW := 8
## Lane-sim car flags.
const ACTIVE := 1
const AWAY := 2
const SHADOW := 4
const WRECK_FLAG := 8

var session: TrackSession
var sim: NossTraffic
## This game decides promotions (offline, and the server online).
var authority := true
var cap := CAP_GAME
## The caps for this traffic's count (CAPS).
var cap_game := CAP_GAME
var cap_player := CAP_PLAYER
var boxes := BOXES
## Car index -> TrafficCar (its physics car, or a proxy of another game's).
var cars := {}
## Online (null offline): the network side; events land this many ticks ahead.
var net: HighwayNet
var lead := 0
## A client's lane sim waits for the server's (TRAFFIC_FULL) before it runs.
var synced := true
## Car index -> its owner: a player's car id (that player's game drives it) or 0 (this game
## offline; the server online). Promoted cars, and those about to be.
var owners := {}
## Totals since the session began (checks).
var promotions := 0
var demotions := 0
var tows := 0
var wrecks := 0
## Garage cars (D239): their models, and for the dev log those seen as themselves.
var models: GarageModels
var garage_seen := {}

var _types: Array[Dictionary] = []
var _car_type := PackedInt32Array()
var _packages := {} # type -> VehiclePackage (copied for each physics car)
var _platforms := {} # type -> PlatformLoader.Result
var _pool := {} # Vector2i(type, garage car; -1 the stock one) -> [Vehicle] parked, ready
var _views: Array[MultiMeshInstance3D] = []
var _boxes: Array[AnimatableBody3D] = []
var _time := 0.0
var _decide := 0.0
var _seq := 0
var _members := PackedFloat32Array()
var _members_frame := -1
var _driven := PackedVector3Array()
var _driven_frame := -1
var _slow_time := 0.0
var _fast_time := 0.0
var _blink := 0.0
## Events this game's physics cars wait on: [tick, seq, kind, car, owner], by tick.
var _due: Array = []
## Cars a DEMOTE, TOW or WRECK has been sent for (not again until it lands).
var _asked := {}
var _promoter_ids := PackedInt32Array()
var _hand := {} # car -> seconds another player has been clearly nearer
var _hand_at := {} # car -> session time of its last handover
var _clock := 0.0
var _closure_id := 0
var _sirens: Array = []
var _sirens_frame := -1
var _seed := 1
var _garage_of := PackedInt32Array() # car -> its garage car (-1: stock), for the session
var _paint_roll := PackedInt64Array() # car -> its paint draw
var _garage_count := {} # garage index -> cars that pick it
var _garage_views := {} # garage index -> MultiMeshInstance3D (its own far mesh)
var _view_now := PackedInt32Array() # car -> the bucket it's drawn in now (-1: its type's)
var _color_now := PackedColorArray() # car -> its colour now (alpha 0: its type's palette)
var _tint := PackedColorArray() # car -> its garage car's paint colour, once known (alpha 0: not yet)
var _stream_in := 0.0


func _init() -> void:
	models = GarageModels.new()
	models.most_whole = MOST_WHOLE
	add_child(models)
	models.view_made.connect(_on_view_made)
	models.view_gone.connect(_on_view_gone)
	models.whole_gone.connect(_on_whole_gone)


## The lane sim for `track`'s highway: `count` cars from `seed`, patrol cars among them with
## `patrols` (D192). False (and why, pushed) if it can't be set up.
func setup(track: TrackData, seed: int, count: int, patrols := false) -> bool:
	_types = TrafficTypes.list()
	for c: Array in CAPS:
		if count >= int(c[0]):
			cap_game = c[1]
			cap_player = c[2]
			boxes = c[3]
	cap = cap_game
	_seed = seed
	sim = TrafficTypes.sim(track, seed, count, patrols)
	if sim == null:
		return false
	var palettes := []
	for t in _types.size():
		palettes.append(PackedColorArray(TrafficTypes.colors(t)))
	sim.set_palettes(palettes)
	_car_type.resize(sim.get_count())
	for i in sim.get_count():
		_car_type[i] = int(sim.car(i).type)
	_garage_of.resize(sim.get_count())
	_garage_of.fill(-1)
	return true


func _ready() -> void:
	process_physics_priority = -58 # after the fields, before drivers (-50)
	if sim == null:
		return
	var draws := not (session.dedicated or Game.dev.has("bot"))
	models.draws = draws
	models.platforms = _platforms
	for t in _types.size():
		_platforms[t] = PlatformLoader.load_official(String(_types[t].platform))
		_pool[Vector2i(t, -1)] = []
		var pkg := PackageLoader.load_package("res://content/traffic/" + String(_types[t].model), {}, {} if draws else { "models": "none", "audio": false })
		if pkg.ok():
			_packages[t] = pkg
	prebuild.call_deferred()
	if draws:
		_make_views()
		var sound := TrafficSound.new()
		sound.name = "TrafficSound"
		sound.manager = self
		add_child(sound)
	for i in boxes:
		var body := AnimatableBody3D.new()
		body.name = "TrafficBox%d" % i
		body.sync_to_physics = false
		body.collision_layer = Vehicle.LAYER_VEHICLES
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		body.add_child(shape)
		body.process_mode = Node.PROCESS_MODE_DISABLED
		body.position = Vector3(0, -1000.0 - i * 10.0, 0)
		add_child(body)
		_boxes.append(body)


func _exit_tree() -> void:
	for t: int in _packages:
		(_packages[t] as VehiclePackage).free_scenes()


func _physics_process(delta: float) -> void:
	if sim == null:
		return
	_clock += delta
	if net:
		if not synced:
			return
		sim.step_to(net.tick_now())
	else:
		_time += delta
		sim.step_to(int(_time * TICK_HZ))
	_run_due()
	if authority:
		_decide -= delta
		if _decide <= 0.0:
			_decide += DECIDE_S
			_promotions()
	_place_boxes()
	_adapt(delta)
	_stream_in -= delta
	if _stream_in <= 0.0 and not models.cars.is_empty():
		_stream_in = STREAM_S
		_stream()


func _process(delta: float) -> void:
	_blink = fmod(_blink + delta * Vehicle.BLINK_HZ, 1.0)
	if not _views.is_empty():
		_draw()


## How far the sim is into its next tick (0..1), for drawing between ticks.
func alpha() -> float:
	var t := net.tick_float() if net else (_time + Engine.get_physics_interpolation_fraction() / Engine.physics_ticks_per_second) * TICK_HZ
	return clampf(t - sim.get_tick(), 0.0, 1.0)


## Server time (online) for proxies' states; the session's own clock offline.
func now() -> float:
	return session.net.now() if session.net else _clock


## Lane-sim car `car` drawn now (or in `pose`, the lane sim's poses): {xform (its ground
## reference, centred), velocity}, or {}.
func shadow_pose(car: int, pose := PackedFloat32Array()) -> Dictionary:
	if pose.is_empty():
		pose = sim.poses(alpha())
	if car * 8 + 7 >= pose.size():
		return {}
	var t: Dictionary = _types[_car_type[car]]
	var fwd := Vector3(pose[car * 8 + 3], 0.0, pose[car * 8 + 4]).normalized()
	var front := Vector3(pose[car * 8], pose[car * 8 + 1], pose[car * 8 + 2])
	var v := float(sim.car(car).get("v", 0.0))
	return { "xform": Transform3D(Basis(Vector3(fwd.z, 0.0, -fwd.x), Vector3.UP, fwd), front - fwd * float(t.length_m) / 2.0), "velocity": fwd * v }


## True if another car is where `tc`'s car is (it spawned on top of it).
func overlaps(tc: TrafficCar) -> bool:
	var at := tc.vehicle.global_position
	var reach := tc.vehicle.fitted.envelope.size.z / 2.0 + 1.0 if tc.vehicle.fitted else 3.0
	var m := members()
	for i in range(0, m.size(), 9):
		if int(m[i]) != tc.car and Vector3(m[i + 1], m[i + 2], m[i + 3]).distance_to(at) < reach + m[i + 7]:
			return true
	return false


## Whether `owner` is this game: offline always; online, one of this game's cars (or 0 on the
## server).
func is_local(owner: int) -> bool:
	if session.net == null:
		return true
	if owner == 0:
		return session.net.is_server()
	return session.net.owned.has(owner)


# --- physics cars ---------------------------------------------------------------------------


## Every physics car near traffic, for the lane driver: 9 floats each (id, x, y, z, heading x,
## heading z, speed, half length, half width). Racers' ids are RACER_ID + their index, traffic
## cars' their car index. Once a physics tick.
func members() -> PackedFloat32Array:
	var frame := Engine.get_physics_frames()
	if frame == _members_frame:
		return _members
	_members_frame = frame
	_members = PackedFloat32Array()
	for i in session.racers.size():
		var r := session.racers[i]
		if r.vehicle and is_instance_valid(r.vehicle) and not r.waiting:
			_add_member(RACER_ID + i, r.vehicle)
	for car: int in cars:
		_add_member(car, (cars[car] as TrafficCar).vehicle)
	return _members


## True if a car this game drives (its players, its police, its own physics traffic) is within
## `radius` of `pos`: a proxy there must move every tick to be hit (or seen) right.
func near_driven(pos: Vector3, radius := NEAR_DRIVEN_M) -> bool:
	var frame := Engine.get_physics_frames()
	if frame != _driven_frame:
		_driven_frame = frame
		_driven = PackedVector3Array()
		for r in session.racers:
			if r.vehicle and is_instance_valid(r.vehicle) and not r.vehicle.remote and not r.waiting:
				_driven.append(r.vehicle.global_position)
		for tc: TrafficCar in cars.values():
			if not tc.remote and tc.vehicle:
				_driven.append(tc.vehicle.global_position)
	for at in _driven:
		if at.distance_squared_to(pos) < radius * radius:
			return true
	return false


func member_id(r: Racer) -> int:
	return RACER_ID + session.racers.find(r)


func _add_member(id: int, v: Vehicle) -> void:
	var e := v.fitted.envelope
	var f := v.global_basis.z
	var p := v.global_position
	_members.append_array([id, p.x, p.y, p.z, f.x, f.z, v.speed(), e.size.z / 2.0, e.size.x / 2.0])


## The traffic round car `v` (score attack, D114) as NearMiss rows: [id, gap (m, hull to hull),
## along (m, its centre ahead of `v`'s), left (m), how much faster `v` is (m/s), half lengths
## added]. Physics cars and proxies by their hulls; lane cars from the lane sim. Ids: the
## lane-sim index either way.
func near_rows(v: Vehicle, radius: float) -> Array:
	var out := []
	var env := v.fitted.envelope if v.fitted else AABB(Vector3(-0.9, 0, -2.2), Vector3(1.8, 1.4, 4.4))
	var me := v.global_transform * env.get_center()
	var fwd := Vector3(v.global_basis.z.x, 0.0, v.global_basis.z.z).normalized()
	var left := Vector3(fwd.z, 0.0, -fwd.x)
	var half := Vector2(env.size.z / 2.0, env.size.x / 2.0)
	var speed := v.speed()
	for car: int in cars:
		var o := (cars[car] as TrafficCar).vehicle
		if o == v:
			continue
		var oe := o.fitted.envelope if o.fitted else env
		var oc := o.global_transform * oe.get_center()
		var d := oc - me
		if Vector2(d.x, d.z).length() > radius:
			continue
		var of := Vector3(o.global_basis.z.x, 0.0, o.global_basis.z.z).normalized()
		var oh := Vector2(oe.size.z / 2.0, oe.size.x / 2.0)
		var gap := NossTraffic.box_gap(me, fwd, half, oc, of, oh)
		out.append([car, gap, d.dot(fwd), d.dot(left), speed - o.speed() * of.dot(fwd), half.x + oh.x])
	var lane := sim.gaps(me, fwd, half, speed, radius)
	for k in range(0, lane.size(), 5):
		var car := int(lane[k])
		var t: Dictionary = _types[_car_type[car]]
		out.append([car, lane[k + 1], lane[k + 2], lane[k + 3], -lane[k + 4], half.x + float(t.length_m) / 2.0])
	return out


## Closes direction `dir`'s lane `lane` for `length` m from main-road distance `from_d` on, the
## way it drives (a run's traffic break, a roadblock): traffic stops before it or moves over.
## `soft` (a siren coming through, D192): traffic moves over, but players and police drive on.
## Returns the closure's id (for open_lanes), or -1.
func close_lane(dir: int, lane: int, from_d: float, length: float, soft := false) -> int:
	var h := session.track.highway
	var at := sim.locate(session.track.transform_at(from_d, h.lane_lateral(dir, lane)).origin + Vector3.UP * 0.5)
	if int(at.get("lane", -1)) < 0:
		return -1
	_closure_id += 1
	_event(CLOSE, _closure_id, int(at.lane), float(at.s), length, 0, 1 if soft else 0)
	return _closure_id


## Opens closure `id` again.
func open_lanes(id: int) -> void:
	_event(OPEN, id)


## Units with their sirens on (D192): [Vehicle], once a physics tick.
func sirens() -> Array:
	var frame := Engine.get_physics_frames()
	if frame != _sirens_frame:
		_sirens_frame = frame
		_sirens = []
		for r in session.racers:
			if r is PoliceRacer and not r.waiting and r.vehicle and is_instance_valid(r.vehicle) and r.vehicle.siren:
				_sirens.append(r.vehicle)
	return _sirens


## Whether a unit with its siren on is coming up behind `v`, its way, within `reach` m.
func siren_behind(v: Vehicle, reach: float) -> bool:
	var fwd := v.global_basis.z
	for s: Vehicle in sirens():
		var rel := v.global_position - s.global_position
		if rel.dot(fwd) > 0.0 and rel.length() < reach and s.global_basis.z.dot(fwd) > 0.5:
			return true
	return false


## Patrol cars within `radius` of `pos` (D192): [{car, xform, velocity}], physics cars where they
## are, lane cars where the lane sim has them.
func patrols_near(pos: Vector3, radius: float) -> Array:
	var out := []
	var poses := sim.poses(0.0)
	for car in sim.get_count():
		if not _types[_car_type[car]].get("patrol", false) or int(poses[car * 8 + 5]) & ACTIVE == 0:
			continue
		var at: Dictionary
		if cars.has(car):
			var v := (cars[car] as TrafficCar).vehicle
			at = { "xform": v.ground_reference(), "velocity": v.remote_velocity if v.remote else v.linear_velocity }
		else:
			at = shadow_pose(car, poses)
		if not at.is_empty() and (at.xform as Transform3D).origin.distance_to(pos) < radius:
			at.car = car
			out.append(at)
	return out


## Takes car `car` off the road (a patrol that becomes a chasing unit where it was): towed away,
## back in a while as any car is.
func retire(car: int) -> void:
	if owners.has(car):
		if not _asked.has(car):
			_ask(car, TOW)
	else:
		_event(TOW, car, -1, 0.0, 0.0)


## Where physics cars matter: every player's car (police come in M7's police step). Their car
## ids (owners online) go in _promoter_ids.
func promoters() -> PackedVector3Array:
	var out := PackedVector3Array()
	_promoter_ids.clear()
	for r in session.racers:
		if r.vehicle and is_instance_valid(r.vehicle) and not r.waiting and (r is SessionPlayer or r.is_human):
			out.append(r.vehicle.global_position)
			_promoter_ids.append(r.net_id if session.net else 0)
	return out


func _promotions() -> void:
	var promoters := promoters()
	# Physics cars: back into the lane sim, wrecked, towed, the lane sim told where they are, or
	# handed to another game.
	for car: int in cars.keys():
		var tc: TrafficCar = cars[car]
		if _asked.has(car):
			continue # waiting for its event to land
		if tc.remote:
			tc.observe()
		var near := _nearest(promoters, tc.vehicle.global_position)
		if tc.wrecked:
			if near > R_OUT:
				_ask(car, TOW)
				tows += 1
			continue
		if tc.crashed():
			tc.wrecked = true
			wrecks += 1
			_event(WRECK, car, maxi(tc.lane, 0), tc.s, 0.0)
			continue
		tc.alone = tc.alone + DECIDE_S if near > R_OUT else 0.0
		if near > R_OUT and (tc.lane_ok() or tc.alone > FORCE_BACK_S):
			if tc.lane_ok():
				_ask(car, DEMOTE, tc.lane, tc.s, maxf(tc.vehicle.speed(), 0.0))
			else:
				_ask(car, DEMOTE) # back where its shadow is
			demotions += 1
			continue
		if tc.drifted(DECIDE_S):
			_event(RESHADOW, car, tc.lane, tc.s, maxf(tc.vehicle.speed(), 0.0))
		if session.net:
			_handover(car, tc, promoters)
	# Lane cars near someone: nearest first, up to the caps (online, each game's own).
	if promoters.is_empty() or (session.net == null and owners.size() >= cap):
		return
	var poses := sim.poses(0.0)
	var candidates := []
	var per := {} # owner -> physics cars
	var games := {} # game (peer) -> physics cars
	for car: int in owners:
		per[owners[car]] = int(per.get(owners[car], 0)) + 1
		var game := _peer_of(owners[car])
		games[game] = int(games.get(game, 0)) + 1
	for i in sim.get_count():
		var flags := int(poses[i * 8 + 5])
		if flags & ACTIVE == 0 or flags & SHADOW != 0 or owners.has(i):
			continue
		var at := Vector3(poses[i * 8], poses[i * 8 + 1], poses[i * 8 + 2])
		var who := _nearest_index(promoters, at)
		var d := promoters[who].distance_to(at)
		if d < R_IN:
			candidates.append([d, i, _promoter_ids[who] if session.net else who])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for c: Array in candidates:
		var owner: int = c[2]
		var game := _peer_of(owner) if session.net else 1
		if int(per.get(owner, 0)) >= cap_player or int(games.get(game, 0)) >= (cap if game == 1 else cap_game):
			continue
		if _promote(c[1], owner if session.net else 0, poses):
			per[owner] = int(per.get(owner, 0)) + 1
			games[game] = int(games.get(game, 0)) + 1


## Lane car `car` becomes a physics car (its owner's; a proxy elsewhere) where the lane sim has
## it when the event lands. False if its spot is taken by another car (it tries again later).
func _promote(car: int, owner: int, poses: PackedFloat32Array) -> bool:
	var type := _car_type[car]
	if not _packages.has(type):
		return false
	var t: Dictionary = _types[type]
	var front := Vector3(poses[car * 8], poses[car * 8 + 1], poses[car * 8 + 2])
	var fwd := Vector3(poses[car * 8 + 3], 0.0, poses[car * 8 + 4]).normalized()
	var centre := front - fwd * float(t.length_m) / 2.0
	for i in range(0, members().size(), 9):
		if Vector3(_members[i + 1], _members[i + 2], _members[i + 3]).distance_to(centre) < float(t.length_m) / 2.0 + 4.0:
			return false
	owners[car] = owner
	_event(PROMOTE, car, -1, 0.0, 0.0, owner)
	promotions += 1
	return true


func _peer_of(owner: int) -> int:
	if owner == 0 or not Net.server:
		return 1
	var p: NetPlayer = Net.server.players.get(owner)
	return p.peer if p else -1


## Online: car `car` goes to the game of a player who's been clearly nearer than its owner's for
## a while (or whose owner left).
func _handover(car: int, tc: TrafficCar, promoters: PackedVector3Array) -> void:
	var owner: int = owners.get(car, 0)
	var at := tc.vehicle.global_position
	var own := INF
	var best := -1
	var best_d := INF
	for i in promoters.size():
		var d := promoters[i].distance_to(at)
		if _promoter_ids[i] == owner:
			own = minf(own, d)
		elif d < best_d:
			best_d = d
			best = _promoter_ids[i]
	var gone := owner != 0 and own == INF
	var better := best >= 0 and best_d < HAND_NEAR_M and (own > HAND_FAR_M or (own > HAND_RATIO * best_d and own > HAND_MIN_M))
	_hand[car] = float(_hand.get(car, 0.0)) + DECIDE_S if better else 0.0
	var again := _clock - float(_hand_at.get(car, -INF)) > HAND_AGAIN_S
	if gone or (better and _hand[car] >= HAND_S and again):
		var to := best if best >= 0 and best_d < R_OUT else 0
		if to == owner:
			return
		_hand[car] = 0.0
		_hand_at[car] = _clock
		_event(HANDOVER, car, -1, 0.0, 0.0, to)


## Asks for an event that ends the car's time as a physics car (DEMOTE, TOW): once.
func _ask(car: int, kind: int, lane := -1, s := 0.0, v := 0.0) -> void:
	_asked[car] = kind
	_event(kind, car, lane, s, v)


## A physics car for traffic type `type` (as garage car `g`, whose whole model is loaded; -1 the
## stock one): one from the pool, or a new one.
func _take_vehicle(type: int, g := -1) -> Vehicle:
	var key := Vector2i(type, g)
	if not _pool.has(key):
		_pool[key] = []
	var pool: Array = _pool[key]
	if not pool.is_empty():
		var v: Vehicle = pool.pop_back()
		v.process_mode = Node.PROCESS_MODE_INHERIT
		v.freeze = false
		v.visible = true
		v.collision_layer = Vehicle.LAYER_VEHICLES
		v.collision_mask = Vehicle.LAYER_WORLD | Vehicle.LAYER_VEHICLES
		v.add_to_group(&"vehicles")
		return v
	return _build_vehicle(type, g)


## A new physics car for traffic type `type` (as garage car `g`; -1 the stock one), in the session:
## 20-40 ms of work, so the drive's start makes those it needs (prebuild).
func _build_vehicle(type: int, g := -1) -> Vehicle:
	var platform: PlatformLoader.Result = _platforms[type]
	if not platform.ok() or (g >= 0 and not models.pkgs.has(g)) or (g < 0 and not _packages.has(type)):
		return null
	var v := Vehicle.create(platform, PackageLoader.copy(models.pkgs[g] if g >= 0 else _packages[type]))
	v.name = "TrafficVehicle"
	v.visual_every_frame = true
	session.add_child(v)
	return v


## Before the first frame (D246): one physics car of each kind the traffic has (each type's stock
## car, and each loaded garage car in each type it's picked for), parked in the pool, so the drive
## makes none of them in a physics frame.
func prebuild() -> void:
	if sim == null or session == null or not is_inside_tree():
		return
	var kinds := {}
	for i in _car_type.size():
		var g := garage_of(i)
		kinds[Vector2i(_car_type[i], g if g >= 0 and models.pkgs.has(g) else -1)] = true
	for key: Vector2i in kinds:
		if not _pool.has(key):
			_pool[key] = []
		if not (_pool[key] as Array).is_empty():
			continue
		var v := _build_vehicle(key.x, key.y)
		if v:
			_park(v, key)


## Physics car (or proxy) `car` goes back into the pool.
func _release(car: int) -> void:
	if not cars.has(car):
		return
	var tc: TrafficCar = cars[car]
	cars.erase(car)
	if session.net:
		session.net.drop_traffic(NetProtocol.FIRST_TRAFFIC_ID + car)
	tc.queue_free()
	_park(tc.vehicle, Vector2i(_car_type[car], tc.garage))


## Physics car `v` out of the way, into its pool (`key`: its type and garage car), or freed if
## that has gone.
func _park(v: Vehicle, key: Vector2i) -> void:
	v.traffic_id = -1
	v.indicators = 0
	v.set_ghost(false)
	v.set_remote(false)
	v.freeze = true
	v.visible = false
	v.collision_layer = 0
	v.collision_mask = 0
	v.global_position = Vector3(0, -2000.0, 0)
	v.process_mode = Node.PROCESS_MODE_DISABLED
	v.remove_from_group(&"vehicles") # what looks at every car (weather, tire tracks) passes it by
	if _pool.has(key):
		(_pool[key] as Array).append(v)
	else:
		v.queue_free() # its garage model has gone meanwhile


## Car `car`'s physics car or proxy, where the lane sim has it now: driven here if `owner` is
## this game, a proxy of the owner's states otherwise.
func _spawn(car: int, owner: int) -> void:
	if cars.has(car):
		return
	var type := _car_type[car]
	if not _packages.has(type):
		return
	var at := shadow_pose(car)
	# Its garage car once its whole model is here (D239); till then the stock car, in its paint.
	var g := _garage_of[car]
	var own := g if g >= 0 and models.pkgs.has(g) else -1
	var v := _take_vehicle(type, own)
	if v == null or at.is_empty():
		return
	v.traffic_id = car
	if v.visual:
		if own >= 0:
			v.visual.apply_choice(models.paint_of(own, _paint_roll[car]))
			garage_seen[own] = true
		else:
			v.visual.set_paint("primary", _color_of(car), "metallic")
	var tc := TrafficCar.new()
	tc.name = "Traffic%d" % car
	tc.manager = self
	tc.car = car
	tc.garage = own
	tc.vehicle = v
	tc.wrecked = int(sim.car(car).flags) & WRECK_FLAG != 0 # a wreck in the lane sim stays one
	_drive_here(tc, is_local(owner), at.xform, at.velocity)
	add_child(tc)
	cars[car] = tc
	if overlaps(tc):
		tc.ghost_time = TrafficCar.GHOST_S
		v.set_ghost(true, false)


## Makes `tc` driven here (a physics car) or shown from its owner's states (a proxy), from
## `xform` at `velocity`.
func _drive_here(tc: TrafficCar, local: bool, xform: Transform3D, velocity: Vector3) -> void:
	var v := tc.vehicle
	tc.remote = not local
	tc.buffer = MotionBuffer.new()
	tc.remote_flags = 0
	v.set_remote(not local)
	if local:
		v.reset_to(xform, velocity)
	else:
		v.move_remote(xform, velocity, Vector3.ZERO, true)
	if session.net:
		var id := NetProtocol.FIRST_TRAFFIC_ID + tc.car
		if local:
			session.net.own_traffic(id, tc)
		else:
			session.net.drop_traffic(id)


## Ownership of `car` moves to `owner` (HANDOVER): a proxy here becomes this game's physics car
## where it is, at its speed, or this game's physics car becomes a proxy.
func _set_owner(car: int, owner: int) -> void:
	if not owners.has(car):
		return
	owners[car] = owner
	if net:
		net.handovers += 1
	var tc: TrafficCar = cars.get(car)
	if tc == null:
		return
	var local := is_local(owner)
	if local != not tc.remote:
		var v := tc.vehicle
		var velocity := v.remote_velocity if tc.remote else v.linear_velocity
		_drive_here(tc, local, v.ground_reference(), velocity)


## Schedules an event (offline now; online `lead` ticks on, and sent to every game).
func _event(kind: int, car: int, lane := -1, s := 0.0, v := 0.0, owner := 0, bits := 0) -> void:
	_seq = (_seq + 1) % 65536
	var record := NossTraffic.pack_event(kind, _seq, sim.get_tick() + lead, car, owner, lane, s, v, -1, 0, bits, 0)
	receive(record)
	if net:
		net.send_events(record)


## Events (24-byte records) from the server, or this game's own: into the lane sim (rolling it
## back if they're late), and noted for when they land. HANDOVER happens at once. False if one
## came too late to replay (this game needs the server's traffic again).
func receive(records: PackedByteArray) -> bool:
	var ok := true
	var list := NossTraffic.unpack_events(records)
	for k in list.size():
		var e: Dictionary = list[k]
		var car := int(e.car)
		if int(e.kind) == HANDOVER:
			_set_owner(car, int(e.owner))
			continue
		if int(e.tick) < sim.get_tick() and net:
			net.late += 1
		if not sim.schedule(records.slice(k * 24, k * 24 + 24)):
			ok = false
			continue
		if int(e.kind) == PROMOTE:
			owners[car] = int(e.owner)
		_due.append([int(e.tick), int(e.seq), int(e.kind), car, int(e.owner)])
	_due.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return ok


## Events the lane sim has reached: their physics cars come and go.
func _run_due() -> void:
	while not _due.is_empty() and int(_due[0][0]) < sim.get_tick():
		var e: Array = _due.pop_front()
		var car: int = e[3]
		match int(e[2]):
			PROMOTE:
				if owners.has(car):
					_spawn(car, int(owners[car]))
			DEMOTE, TOW:
				_release(car)
				owners.erase(car)
				_asked.erase(car)
			WRECK:
				if cars.has(car):
					(cars[car] as TrafficCar).wrecked = true


## A client takes the server's traffic as it is (joining, or out of step): the lane sim at
## `tick`, the events still to land, and who owns each physics car.
func load_full(state: PackedByteArray, tick: int, events: PackedByteArray, owner_pairs: PackedInt32Array) -> bool:
	if not sim.load_full_state(state) or sim.get_tick() != tick:
		return false
	_due.clear()
	var keep := {}
	for k in range(0, owner_pairs.size() - 1, 2):
		keep[owner_pairs[k]] = owner_pairs[k + 1]
	for car: int in cars.keys():
		if not keep.has(car):
			_release(car)
	owners = keep
	for car: int in owners:
		if cars.has(car):
			_set_owner(car, owners[car])
		elif int(sim.car(car).flags) & SHADOW != 0:
			_spawn(car, owners[car]) # its PROMOTE landed already (else it's in `events`)
	if not events.is_empty():
		receive(events)
	synced = true
	return true


static func _nearest(points: PackedVector3Array, at: Vector3) -> float:
	var best := INF
	for p in points:
		best = minf(best, p.distance_to(at))
	return best


static func _nearest_index(points: PackedVector3Array, at: Vector3) -> int:
	var best := INF
	var out := 0
	for i in points.size():
		var d := points[i].distance_to(at)
		if d < best:
			best = d
			out = i
	return out


## Lane cars right beside a player that aren't physics cars get a solid box where the lane sim has
## them, so nobody drives through traffic while the cap is reached.
func _place_boxes() -> void:
	var players := PackedVector3Array()
	for p in session.players:
		if p.vehicle and is_instance_valid(p.vehicle):
			players.append(p.vehicle.global_position)
	var used := 0
	var pose := PackedFloat32Array()
	for p in players:
		for car in sim.cars_near(p, BOX_M):
			if used >= _boxes.size():
				break
			if cars.has(car) or int(sim.car(car).flags) & SHADOW != 0:
				continue
			if pose.is_empty():
				pose = sim.poses(alpha())
			var t: Dictionary = _types[_car_type[car]]
			var fwd := Vector3(pose[car * 8 + 3], 0.0, pose[car * 8 + 4]).normalized()
			var centre := Vector3(pose[car * 8], pose[car * 8 + 1], pose[car * 8 + 2]) - fwd * float(t.length_m) / 2.0
			var body := _boxes[used]
			body.process_mode = Node.PROCESS_MODE_INHERIT
			((body.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = Vector3(float(t.width_m), 1.4, float(t.length_m))
			body.global_transform = Transform3D(Basis(Vector3(fwd.z, 0.0, -fwd.x), Vector3.UP, fwd), centre + Vector3.UP * 0.9)
			body.set_meta(&"noss_traffic", car)
			used += 1
	for i in range(used, _boxes.size()):
		if _boxes[i].process_mode != Node.PROCESS_MODE_DISABLED:
			_boxes[i].process_mode = Node.PROCESS_MODE_DISABLED
			_boxes[i].global_position = Vector3(0, -1000.0 - i * 10.0, 0)



## Fewer physics cars while physics runs slow (over SLOW_MS a frame for 2 s), more again once
## there's room (under half that for 10 s), up to the count's cap.
func _adapt(delta: float) -> void:
	adapt_to(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, delta)


func adapt_to(ms: float, delta: float) -> void:
	_slow_time = _slow_time + delta if ms > SLOW_MS else 0.0
	_fast_time = _fast_time + delta if ms < SLOW_MS / 2.0 else 0.0
	if _slow_time > 2.0:
		_slow_time = 0.0
		cap = maxi(CAP_MIN, cap - 2)
	elif _fast_time > 10.0:
		_fast_time = 0.0
		cap = mini(cap_game, cap + 1)


# --- drawing --------------------------------------------------------------------------------


func _make_views() -> void:
	var counts := PackedInt32Array()
	counts.resize(_types.size())
	for t in _car_type:
		counts[t] += 1
	for t in _types.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = TrafficModels.far_mesh(t)
		mm.instance_count = maxi(counts[t], 1)
		mm.visible_instance_count = 0
		var view := MultiMeshInstance3D.new()
		view.name = "Traffic_" + String(_types[t].id)
		view.multimesh = mm
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		view.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
		add_child(view)
		_views.append(view)


func _draw() -> void:
	var bufs := sim.buffers(alpha(), _cameras(), VIEW_M, _blink < 0.5)
	for t in _views.size():
		_fill(_views[t].multimesh, bufs[t])
	for g: int in _garage_views:
		var bucket := _types.size() + g
		var mm := (_garage_views[g] as MultiMeshInstance3D).multimesh
		if bucket < bufs.size():
			_fill(mm, bufs[bucket])
			if int(bufs[bucket][1]) > 0:
				garage_seen[g] = true
		else:
			mm.visible_instance_count = 0


func _fill(mm: MultiMesh, buf_count: Array) -> void:
	var buf: PackedFloat32Array = buf_count[0]
	var count := mini(int(buf_count[1]), mm.instance_count)
	buf.resize(mm.instance_count * 20)
	mm.buffer = buf
	mm.visible_instance_count = count


func _cameras() -> PackedVector3Array:
	var cameras := PackedVector3Array()
	for c in _camera_nodes():
		cameras.append(c.global_position)
	return cameras


## The players' cameras here (none on a server or a bot).
func _camera_nodes() -> Array[Camera3D]:
	var out: Array[Camera3D] = []
	if session == null:
		return out
	for p in session.players:
		if p.cameras and p.cameras.camera:
			out.append(p.cameras.camera)
	return out


## True if a ball at `pos` (`radius` m) is outside every one of `frustums` (Camera3D.get_frustum()
## planes, facing out); with none, nobody sees it.
static func _out_of_view(frustums: Array, pos: Vector3, radius: float) -> bool:
	for planes: Array in frustums:
		var inside := true
		for plane: Plane in planes:
			if plane.distance_to(pos) > radius:
				inside = false
				break
		if inside:
			return false
	return true


# --- garage cars ------------------------------------------------------------------------------


## Offline: every car of `pool` (EndlessTraffic.garage_pool) in the traffic (D239). Each one's
## paint is read now (a stand-in wears it); its models load as it comes near.
func set_garage(pool: Array[Dictionary]) -> void:
	var weighted := EndlessTraffic.weighted_types()
	var mine: Array[Dictionary] = []
	for d: Dictionary in pool:
		var e := d.duplicate()
		e.fits = _type_indexes((d.fits as Array).map(func(i: int) -> String: return String(weighted[i].id)))
		mine.append(e)
	models.set_pool(mine)
	_deal_picks(PackedInt32Array(range(mine.size())))
	# Loaded before the drive (D246): each drives and is drawn as itself from the start.
	models.adopt_loaded()
	_apply_views(true)


## Online: the server's set (Net.endless_garage, D239): its cars, each fetched in full now (one
## not here yet drives as a stock car in its paint), and each car's pick from them.
func use_garage(sets: EndlessGarage) -> void:
	var registry := {}
	for g: int in sets.cars:
		var d: Dictionary = sets.cars[g]
		registry[g] = { "car": String(d.car), "path": "", "fits": _type_indexes(Array(d.fits)), "paint": {} }
	models.cars = registry
	for g: int in registry:
		models.car_here(String(registry[g].car))
		if String(registry[g].path).is_empty() and Net.content:
			Net.content.fetch_car(String(registry[g].car), 1, Net.content.max_tier)
	_deal_picks(sets.sets.get(sets.k, PackedInt32Array()))


## TrafficTypes indexes of the type ids `ids` (patrols never).
func _type_indexes(ids: Array) -> Array[int]:
	var out: Array[int] = []
	for id: Variant in ids:
		var i := TrafficTypes.index_of(String(id))
		if i >= 0 and not _types[i].get("patrol", false) and not i in out:
			out.append(i)
	return out


## Each car's garage car from the cars of `set` (registry indexes, in order) that fit its type:
## three draws from the seed and the car, so every game with the same set picks the same.
func _deal_picks(set: PackedInt32Array) -> void:
	var by_type := {} # type index -> [garage index]
	for g: int in set:
		if not models.cars.has(g):
			continue
		for t: int in models.cars[g].fits:
			if not by_type.has(t):
				by_type[t] = []
			(by_type[t] as Array).append(g)
	_garage_count = {}
	_paint_roll.resize(_car_type.size())
	_view_now.resize(_car_type.size())
	_view_now.fill(-1)
	_color_now.resize(_car_type.size())
	_color_now.fill(Color(0, 0, 0, 0))
	_tint.resize(_car_type.size())
	_tint.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	for i in _car_type.size():
		rng.seed = (_seed * 1000003 + i * 7919 + 0x5bd1e995) & 0x7FFFFFFFFFFFFFFF
		var share := rng.randf()
		var roll := rng.randi()
		_paint_roll[i] = rng.randi()
		var fits: Array = by_type.get(_car_type[i], [])
		_garage_of[i] = int(fits[roll % fits.size()]) if share < GarageModels.GARAGE_SHARE and not fits.is_empty() else -1
		if _garage_of[i] >= 0:
			_garage_count[_garage_of[i]] = int(_garage_count.get(_garage_of[i], 0)) + 1
	_apply_views(true)


## Car `car`'s garage car (-1: a stock car).
func garage_of(car: int) -> int:
	return _garage_of[car] if car >= 0 and car < _garage_of.size() else -1


## For checks: every car's pick as one number, the same on every game whose sets agree.
func picks_check() -> String:
	var sum := 0
	for g in _garage_of:
		sum = (sum * 31 + g + 1) & 0xFFFFFFF
	return "%07x" % sum


## Online: some of garage car `h` (a hash) is here now.
func car_here(h: String) -> void:
	models.car_here(h)


## Car `car`'s colour: its stock one, or its garage car's main paint once that's known.
func _color_of(car: int) -> Color:
	var colors := TrafficTypes.colors(_car_type[car])
	var stock := colors[int(sim.car(car).color) % colors.size()]
	var tint := _tint_of(car)
	return tint if tint.a > 0.0 else stock


## Car `car`'s garage car's paint colour, worked out once its paint is here (alpha 0 till then, or
## for a stock car).
func _tint_of(car: int) -> Color:
	var g := _garage_of[car]
	if g < 0 or car >= _tint.size():
		return Color(0, 0, 0, 0)
	if _tint[car].a == 0.0 and models.has_paint(g):
		var colors := TrafficTypes.colors(_car_type[car])
		var c := models.tint_of(g, _paint_roll[car], colors[int(sim.car(car).color) % colors.size()])
		c.a = 1.0
		_tint[car] = c
	return _tint[car]


## Wants each garage car's models where its cars are, and lets go of the rest (GarageModels).
func _stream() -> void:
	var at := _clock
	var eyes := _cameras()
	var near := PackedVector3Array()
	for p in session.players:
		if p.vehicle and is_instance_valid(p.vehicle):
			near.append(p.vehicle.global_position)
	if eyes.is_empty():
		eyes = near
	var poses := sim.poses(0.0)
	for i in _garage_of.size():
		var g := _garage_of[i]
		if g < 0 or int(poses[i * 8 + 5]) & ACTIVE == 0:
			continue
		var pos := Vector3(poses[i * 8], poses[i * 8 + 1], poses[i * 8 + 2])
		var seen := _nearest(eyes, pos)
		if seen > GARAGE_FAR_M:
			continue
		var d := _nearest(near, pos)
		models.want(g, at, d if d < GARAGE_NEAR_M else INF, seen)
	var driven := {}
	for car: int in cars:
		driven[(cars[car] as TrafficCar).garage] = true
	models.sweep(at, driven)
	_swaps()
	_apply_views(_clock < SETTLE_S, poses)


## Stock physics cars whose garage car's whole model is here now become it where no player's
## camera sees them, SWAPS_PER_STREAM at most. Online each game swaps its own physics cars and
## proxies (what a car looks like differs between games anyway, D239).
func _swaps() -> void:
	var frustums := _camera_nodes().map(func(c: Camera3D) -> Array: return c.get_frustum())
	var n := 0
	for car: int in cars:
		var tc: TrafficCar = cars[car]
		var g := _garage_of[car]
		if tc.garage >= 0 or g < 0 or not models.pkgs.has(g) or tc.wrecked or _asked.has(car) or tc.vehicle.fitted == null:
			continue
		var e := tc.vehicle.fitted.envelope
		if _out_of_view(frustums, tc.vehicle.global_transform * e.get_center(), e.size.length() / 2.0 + 1.0) and _swap(tc, g):
			n += 1
			if n >= SWAPS_PER_STREAM:
				return


## Physics car (or proxy) `tc` becomes garage car `g` where it is, at its speed: its stock car
## goes back to the pool. False if it can't be made.
func _swap(tc: TrafficCar, g: int) -> bool:
	var type := _car_type[tc.car]
	var old := tc.vehicle
	var v := _take_vehicle(type, g)
	if v == null:
		return false
	var xform := old.ground_reference()
	var velocity := old.remote_velocity if tc.remote else old.linear_velocity
	_park(old, Vector2i(type, -1))
	v.traffic_id = tc.car
	if v.visual:
		v.visual.apply_choice(models.paint_of(g, _paint_roll[tc.car]))
	v.set_remote(tc.remote)
	if tc.remote:
		v.move_remote(xform, velocity, Vector3.ZERO, true)
	else:
		v.reset_to(xform, velocity)
	tc.garage = g
	tc.use_vehicle(v)
	garage_seen[g] = true
	if tc.ghost_time > 0.0 or overlaps(tc):
		tc.ghost_time = maxf(tc.ghost_time, TrafficCar.GHOST_S)
		v.set_ghost(true, false)
	return true


## Each garage car drawn as itself once its far view is made, in its paint once that's known; a
## change only while the car's out of sight (or with `now`). `poses`: the lane sim's, if made.
func _apply_views(now: bool, poses := PackedFloat32Array()) -> void:
	if _view_now.is_empty():
		return
	var eyes := _cameras()
	if not now and not eyes.is_empty() and poses.is_empty():
		poses = sim.poses(0.0)
	var changed := false
	for i in _garage_of.size():
		var g := _garage_of[i]
		if g < 0:
			continue
		var view := _types.size() + g if _garage_views.has(g) else -1
		var color := _tint_of(i)
		if view == _view_now[i] and color == _color_now[i]:
			continue
		if not now and not eyes.is_empty() and _nearest(eyes, Vector3(poses[i * 8], poses[i * 8 + 1], poses[i * 8 + 2])) < VIEW_M + 50.0:
			continue
		_view_now[i] = view
		_color_now[i] = color
		changed = true
	if changed:
		sim.set_views(_view_now, _color_now)


func _on_view_made(g: int, mesh: ArrayMesh) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = maxi(int(_garage_count.get(g, 0)), 1)
	mm.visible_instance_count = 0
	var view := MultiMeshInstance3D.new()
	view.name = "Traffic_garage_%d" % g
	view.multimesh = mm
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.custom_aabb = AABB(Vector3(-1e5, -1e3, -1e5), Vector3(2e5, 2e3, 2e5))
	add_child(view)
	_garage_views[g] = view


## A far view goes (nobody's been near its cars for a while): its cars back to their type's.
func _on_view_gone(g: int) -> void:
	var changed := false
	for i in _garage_of.size():
		if _garage_of[i] == g and _view_now[i] >= 0:
			_view_now[i] = -1
			changed = true
	if changed:
		sim.set_views(_view_now, _color_now)
	var view: Node = _garage_views.get(g)
	if view:
		view.queue_free()
	_garage_views.erase(g)


## A whole model goes: the physics cars waiting in the pool on it go too.
func _on_whole_gone(g: int) -> void:
	for key: Vector2i in _pool.keys():
		if key.y == g:
			for v: Vehicle in _pool[key]:
				v.queue_free()
			_pool.erase(key)
