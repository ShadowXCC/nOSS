class_name KartControl
extends Node
## Kart sessions (D129): added next to an ordinary session when the class's mode has the
## kart_arcade layer. Here: the tow drone (D132), slipstream, and the items (KartItems) with
## their boxes (KartBoxes) and what's out on the track (KartEntities).

const SLIP_HZ := 30.0
const SLIP_MIN_SPEED := 10.0 # m/s: the car ahead must be going
const TOW_LIFT := 6.0 # m above the higher end, at the middle of the carry
const GHOST_AFTER_TOW := 1.0
## Beached (upright, no wheel down, yet neither rising nor falling: on another kart's back, on
## an edge) this long: the tow. A flight off a jump keeps changing its vertical speed.
const BEACHED_S := 2.0
const BEACHED_VY := 1.0

var session: TrackSession
var arcade := {}
## Racers being carried: racer -> {t, from: Transform3D, to: Transform3D, drone: Node3D, freeze_mode}.
var _tows := {}
var _slip_time := 0.0
var _beached := {} # racer -> seconds
## Magnet (items): racer -> how many times stronger its slipstream is (D139).
var slip_boost := {}
var layout: KartLayout
var items: KartItems
var boxes: KartBoxes
var entities: KartEntities


func _ready() -> void:
	process_physics_priority = -57 # after the race field, before the drivers (-50)
	var visual := not Game.dedicated and not Game.dev.has("bot")
	# A track's own pieces and rows, or automatic rows on any other track (D136).
	layout = session.track.kart if session.track.kart else KartLayout.build(session.track, {})
	boxes = KartBoxes.new()
	boxes.name = "ItemBoxes"
	add_child(boxes)
	boxes.setup(layout.box_points() if session.event.items else PackedVector3Array(), visual)
	entities = KartEntities.new()
	entities.name = "ItemsOut"
	entities.session = session
	entities.visual = visual
	add_child(entities)
	items = KartItems.new()
	items.name = "Items"
	items.control = self
	items.session = session
	items.boxes = boxes
	items.entities = entities
	items.odds = ItemOdds.load_default()
	items.odds.cycle = Game.dev.get("odds", "") == "cycle"
	if Game.dev.has("seed"):
		items.rng.seed = int(Game.dev.seed)
	add_child(items)
	if visual:
		var effects := KartEffects.new()
		effects.name = "Effects"
		effects.session = session
		add_child(effects)
		var hud := KartHud.new()
		hud.name = "Hud"
		hud.session = session
		add_child(hud)
		var sounds := KartSounds.new()
		sounds.name = "Sounds"
		sounds.session = session
		add_child(sounds)


## Drops the kart classes' shared meshes, materials and sounds (a session's end: nothing holds
## them at exit).
static func clear_caches() -> void:
	KartBoxes._mesh = null
	KartBoxes._material = null
	KartEffects._materials.clear()
	KartEntities._meshes.clear()
	KartSounds._streams.clear()
	StuntBuilder._materials.clear()
	ArenaNav._cache.clear()


## `r` uses its item (its player's button, the AI or the item assist).
func use(r: Racer, back := false) -> void:
	items.use(r, back)


## A drone lifts the kart and carries it back to the last valid spot on the road, then puts it
## down rolling (D132): falling off costs the time, the lap still counts.
func tow(r: Racer) -> void:
	if _tows.has(r) or r.vehicle == null or r.waiting:
		return
	var v := r.vehicle
	var to := r.last_valid_xform if session.track.arena else layout.tow_spot(r.last_valid)
	_tows[r] = { "t": 0.0, "from": v.global_transform, "to": to, "freeze_mode": v.freeze_mode, "drone": _drone(v) }
	r.towed = true
	v.kart_bits |= CarState.KART_TOWED
	v.sim.kart_effect(VehicleSim.KART_CANCEL, 0.0)
	v.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	v.freeze = true
	r.set_ghost(true)
	r.notify("Tow", 1.5)


func towing(r: Racer) -> bool:
	return _tows.has(r)


func _physics_process(delta: float) -> void:
	for r: Racer in _tows.keys():
		_carry(r, delta)
	_check_beached(delta)
	_slip_time += delta
	if _slip_time >= 1.0 / SLIP_HZ:
		_slip_time = 0.0
		_slipstream()


## Karts this game drives that rest on something with no wheel down are towed (D132).
func _check_beached(delta: float) -> void:
	for r: Racer in session.racers:
		var v := r.vehicle
		if v == null or v.remote or r.towed or r.waiting or r.held:
			_beached.erase(r)
			continue
		# (Upright: one on its roof or side is the righting's to deal with.)
		if v.kart_flags() & VehicleSim.KART_FLAG_AIRBORNE and absf(v.linear_velocity.y) < BEACHED_VY and v.global_basis.y.y > 0.5:
			_beached[r] = float(_beached.get(r, 0.0)) + delta
			if _beached[r] >= BEACHED_S:
				_beached.erase(r)
				tow(r)
		else:
			_beached.erase(r)


func _carry(r: Racer, delta: float) -> void:
	var tow: Dictionary = _tows[r]
	var v := r.vehicle
	if v == null or not is_instance_valid(v):
		_tows.erase(r)
		return
	tow.t += delta / float(arcade.tow.s)
	var from: Transform3D = tow.from
	var to: Transform3D = tow.to
	var k := smoothstep(0.0, 1.0, minf(tow.t, 1.0))
	var ground := to.origin - to.basis.y * v.fitted.ground_y
	var p := from.origin.lerp(ground, k) + Vector3.UP * TOW_LIFT * sin(PI * minf(tow.t, 1.0))
	var b := from.basis.orthonormalized().slerp(to.basis.orthonormalized(), k)
	v.global_transform = Transform3D(b, p)
	if tow.t < 1.0:
		return
	_tows.erase(r)
	if is_instance_valid(tow.drone):
		tow.drone.queue_free()
	v.freeze = false
	v.freeze_mode = tow.freeze_mode
	var speed: float = v.sim.get_geared_top() * float(arcade.tow.speed)
	v.reset_to(to, to.basis.z * speed)
	v.kart_bits &= ~CarState.KART_TOWED
	r.towed = false
	if session.track.arena == null:
		var proj := session.track.project(to.origin)
		r.last_valid = float(proj.distance)
		r.distance = r.last_valid
		r.track_index = -1
		r.timer.teleported(r.lap_pos(r.last_valid))
	r.ghost_for(GHOST_AFTER_TOW)


## A small quadcopter on a cable above the kart (made in code, original). None on a server.
func _drone(v: Vehicle) -> Node3D:
	if Game.dedicated or Game.dev.has("bot"):
		return null
	var root := Node3D.new()
	root.name = "TowDrone"
	var top := v.fitted.envelope.end.y if v.fitted else 1.0
	root.position = Vector3(0, top + 1.6, 0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.14)
	var light := StandardMaterial3D.new()
	light.albedo_color = Color(0.95, 0.75, 0.15)
	var b := MeshBatch.new()
	b.box(Vector3.ZERO, Basis(), Vector3(0.5, 0.14, 0.5))
	for x in [-1, 1]:
		for z in [-1, 1]:
			b.box(Vector3(0.38 * x, 0.04, 0.38 * z), Basis(), Vector3(0.36, 0.02, 0.36))
	var body := MeshInstance3D.new()
	body.mesh = b.mesh()
	body.material_override = dark
	root.add_child(body)
	var cable := MeshInstance3D.new()
	var cb := MeshBatch.new()
	cb.box(Vector3(0, -0.8, 0), Basis(), Vector3(0.03, 1.6, 0.03))
	cable.mesh = cb.mesh()
	cable.material_override = light
	root.add_child(cable)
	v.add_child(root)
	return root


## Slipstream (D139): close behind a car, inside its width, the drag drops.
func _slipstream() -> void:
	var s: Dictionary = arcade.slipstream
	var reach: float = s.range_m
	var half: float = s.half_width_m
	for r in session.racers:
		var v := r.vehicle
		if v == null or v.remote or v.arcade.is_empty() or r.waiting or r.towed:
			continue
		var fwd := v.global_basis.z
		var left := v.global_basis.x
		var best := 0.0
		for o in session.racers:
			if o == r or o.vehicle == null or o.waiting or o.towed or absf(o.speed) < SLIP_MIN_SPEED:
				continue
			var rel := o.vehicle.global_position - v.global_position
			var along := rel.dot(fwd)
			if along <= 0.0 or along > reach or absf(rel.dot(left)) > half:
				continue
			best = maxf(best, 1.0 - along / reach)
		var cut := minf(float(s.drag_cut) * best * float(slip_boost.get(r, 1.0)), 0.9)
		v.sim.set_kart_drag(1.0 - cut)
