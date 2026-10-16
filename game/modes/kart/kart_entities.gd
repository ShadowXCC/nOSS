class_name KartEntities
extends Node3D
## Kart items out on the track (D139): Bolts along the ground, bouncing off walls; Seekers and the
## Leader Hunter along the road (the racing line, for the Hunter) and then straight at their
## target; Oil Slicks lying where they fell. Every game moves them from where and when they were
## spawned (D141); a Bolt meets a Seeker, a Bolt or a Slick and both go.

const SPEC := {
	"bolt": { "speed": 42.0, "life": 8.0, "radius": 0.9, "height": 0.45 },
	"seeker": { "speed": 40.0, "life": 10.0, "radius": 0.9, "height": 0.6, "home_m": 25.0 },
	"leader_hunter": { "speed": 55.0, "life": 40.0, "radius": 1.2, "height": 0.8, "home_m": 30.0 },
	"oil_slick": { "speed": 0.0, "life": 25.0, "radius": 1.0, "height": 0.03 },
}
const MAX_BOUNCES := 3
## A kart's reach for hits, added to an entity's radius.
const KART_RADIUS := 1.0
## Its owner can't be hit by its own Slick for this long, nor by its own Seeker.
const OWNER_SAFE_S := 1.0
const THROW_S := 0.6 # a Slick thrown ahead flies this long
const THROW_M := 15.0
const LATERAL_RATE := 3.0 # m/s a Seeker moves across the road toward its target
const GRAVITY := 9.81

## Entities by id: {id, kind, owner: Racer, target: Racer, pos, vel, s, lat, bounces, age, life,
## radius, landing (thrown Slicks), node}.
var list := {}
var session: TrackSession
var visual := true
var _next_id := 1


## A new entity from `owner` at `pos`, moving along `dir` (ground plane). `id` 0 picks the next.
func spawn(kind: String, owner: Racer, pos: Vector3, dir: Vector3, target: Racer = null, id := 0, thrown := false) -> Dictionary:
	var spec: Dictionary = SPEC[kind]
	var e := { "id": id if id > 0 else _next_id, "kind": kind, "owner": owner, "target": target, "pos": pos,
		"vel": dir.normalized() * float(spec.speed), "s": 0.0, "lat": 0.0, "bounces": 0, "age": 0.0,
		"life": float(spec.life), "radius": float(spec.radius), "node": null }
	_next_id = maxi(_next_id, int(e.id)) + 1
	var t := session.track
	if kind in ["seeker", "leader_hunter"] and t.arena == null:
		var proj := t.project(pos)
		e.s = float(proj.distance)
		e.lat = float(proj.lateral)
	if kind == "oil_slick":
		e.vel = Vector3.ZERO
		if thrown:
			e.from = pos
			e.landing = _ground(pos + dir.normalized() * THROW_M, pos.y)
			e.fly = THROW_S
		else:
			e.pos = _ground(pos, pos.y)
	list[e.id] = e
	if visual:
		e.node = _node(kind)
		add_child(e.node)
		_place(e)
	return e


## Entity `old` (shown at once on its user's game) takes the server's id `new` (KartNet).
func rekey(old: int, new: int) -> void:
	var e: Dictionary = list.get(old, {})
	if e.is_empty() or old == new:
		return
	list.erase(old)
	if list.has(new):
		remove(new)
	e.id = new
	list[new] = e


## Moves `e` on by `seconds` (one let go a moment ago on another game), in physics-tick steps.
func advance(e: Dictionary, seconds: float) -> void:
	var dt := 1.0 / Engine.physics_ticks_per_second
	var t := 0.0
	while t + dt * 0.5 <= seconds and list.has(e.id): # to the nearest tick
		e.age = float(e.age) + dt
		_step_one(e, dt)
		t += dt
	if visual and list.has(e.id):
		_place(e)


func remove(id: int) -> void:
	var e: Dictionary = list.get(id, {})
	if e.is_empty():
		return
	if e.node:
		(e.node as Node).queue_free()
	list.erase(id)


func count(kind: String) -> int:
	var n := 0
	for e: Dictionary in list.values():
		n += 1 if e.kind == kind else 0
	return n


## Entities touching `racer`'s car at `pos` that may hit it.
func touching(racer: Racer, pos: Vector3) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in list.values():
		if e.has("fly"):
			continue
		if (e.pos as Vector3).distance_to(pos) > float(e.radius) + KART_RADIUS:
			continue
		if e.owner == racer:
			match String(e.kind):
				"bolt":
					if e.bounces == 0:
						continue # its shooter only after it bounced
				"oil_slick", "seeker":
					if e.age < OWNER_SAFE_S:
						continue
				"leader_hunter":
					continue
		if e.kind == "leader_hunter" and e.target != racer:
			continue # it passes the rest
		out.append(e)
	return out


func step(delta: float) -> void:
	for e: Dictionary in list.values():
		e.age += delta
		if e.age >= float(e.life):
			remove(e.id)
			continue
		_step_one(e, delta)
	_collide()
	if visual:
		for e: Dictionary in list.values():
			_place(e)


func _step_one(e: Dictionary, delta: float) -> void:
	match String(e.kind):
		"bolt":
			_bolt(e, delta)
		"seeker", "leader_hunter":
			_chaser(e, delta)
		"oil_slick":
			_slick(e, delta)


func _bolt(e: Dictionary, delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var vel: Vector3 = e.vel
	var pos: Vector3 = e.pos
	var to := pos + vel * delta
	var q := PhysicsRayQueryParameters3D.create(pos, to + vel.normalized() * float(e.radius) * 0.5, Vehicle.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if not hit.is_empty() and absf((hit.normal as Vector3).y) < 0.5:
		var n: Vector3 = hit.normal
		n.y = 0.0
		n = n.normalized()
		e.vel = (vel - 2.0 * vel.dot(n) * n)
		e.bounces += 1
		if e.bounces > MAX_BOUNCES:
			remove(e.id)
			return
		to = (hit.position as Vector3) + n * float(e.radius) * 0.5
	e.pos = _ground(to, pos.y, float(SPEC.bolt.height), e, delta)


## Seekers and the Leader Hunter: along the road (the Hunter on the racing line) until close,
## then straight at the target. In an arena, straight at it from the start.
func _chaser(e: Dictionary, delta: float) -> void:
	var spec: Dictionary = SPEC[e.kind]
	var target: Racer = e.target
	var t := session.track
	var aim := Vector3.INF
	if target and is_instance_valid(target) and target.vehicle and not target.towed:
		aim = target.com()
	var pos: Vector3 = e.pos
	if t.arena or (aim != Vector3.INF and pos.distance_to(aim) < float(spec.get("home_m", 0.0))):
		var dir := (aim - pos) if aim != Vector3.INF else (e.vel as Vector3)
		dir.y = 0.0
		e.vel = dir.normalized() * float(spec.speed)
		e.pos = _ground(pos + (e.vel as Vector3) * delta, pos.y, float(spec.height), e, delta)
		if t.arena == null:
			e.s = float(t.project(e.pos, t.index_at(float(e.s))).distance)
		return
	e.s = fposmod(float(e.s) + float(spec.speed) * delta, t.length)
	var want := 0.0
	if e.kind == "leader_hunter":
		want = RacingLine.for_track(t).offset_at(e.s)
	elif target and is_instance_valid(target):
		want = target.lateral
	e.lat = move_toward(float(e.lat), want, LATERAL_RATE * delta)
	var x := t.transform_at(e.s, e.lat)
	var next: Vector3 = x.origin + x.basis.y * float(spec.height)
	e.vel = (next - pos) / maxf(delta, 1e-4)
	e.pos = next


func _slick(e: Dictionary, delta: float) -> void:
	if not e.has("fly"):
		return
	e.fly = float(e.fly) - delta
	var k := 1.0 - clampf(float(e.fly) / THROW_S, 0.0, 1.0)
	var from: Vector3 = e.from
	var to: Vector3 = e.landing
	e.pos = from.lerp(to, k) + Vector3.UP * 3.0 * sin(PI * k)
	if e.fly <= 0.0:
		e.pos = to
		e.erase("fly")


## A Bolt and a Seeker, another Bolt or a Slick: both go. The Hunter passes everything.
func _collide() -> void:
	var bolts := list.values().filter(func(e: Dictionary) -> bool: return e.kind == "bolt")
	for b: Dictionary in bolts:
		if not list.has(b.id):
			continue
		for o: Dictionary in list.values():
			if o.id == b.id or o.kind == "leader_hunter" or o.has("fly"):
				continue
			if (b.pos as Vector3).distance_to(o.pos) < float(b.radius) + float(o.radius):
				remove(b.id)
				remove(o.id)
				break


## `p` on the ground below it (at `height` over it), or falling if there's none near.
func _ground(p: Vector3, from_y: float, height := 0.03, e := {}, delta := 0.0) -> Vector3:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, maxf(p.y, from_y) + 2.0, p.z), Vector3(p.x, p.y - 6.0, p.z), Vehicle.LAYER_WORLD)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		if not e.is_empty():
			e.fall = float(e.get("fall", 0.0)) + GRAVITY * delta
			return p - Vector3.UP * float(e.fall) * delta
		return p
	if not e.is_empty():
		e.fall = 0.0
	return (hit.position as Vector3) + Vector3.UP * height


# --- looks ---------------------------------------------------------------------------------

func _place(e: Dictionary) -> void:
	var n: Node3D = e.node
	if n == null:
		return
	n.position = e.pos
	var v: Vector3 = e.vel
	v.y = 0.0
	if v.length() > 0.1:
		n.basis = Basis.looking_at(v.normalized(), Vector3.UP)


static var _meshes := {}


## Steady glowing shapes (no flashing): a yellow bolt, a red seeker, a purple hunter, a dark slick.
func _node(kind: String) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not _meshes.has(kind):
		var m := StandardMaterial3D.new()
		var mesh: PrimitiveMesh
		match kind:
			"bolt":
				mesh = SphereMesh.new()
				(mesh as SphereMesh).radius = 0.3
				(mesh as SphereMesh).height = 0.6
				m.albedo_color = Color(1.0, 0.85, 0.2)
				m.emission_enabled = true
				m.emission = Color(1.0, 0.8, 0.2)
			"seeker", "leader_hunter":
				mesh = CylinderMesh.new()
				(mesh as CylinderMesh).top_radius = 0.0
				(mesh as CylinderMesh).bottom_radius = 0.3 if kind == "seeker" else 0.5
				(mesh as CylinderMesh).height = 0.9 if kind == "seeker" else 1.4
				m.albedo_color = Color(0.9, 0.15, 0.12) if kind == "seeker" else Color(0.55, 0.2, 0.85)
				m.emission_enabled = true
				m.emission = m.albedo_color * 0.6
			"oil_slick":
				mesh = CylinderMesh.new()
				(mesh as CylinderMesh).top_radius = 1.0
				(mesh as CylinderMesh).bottom_radius = 1.0
				(mesh as CylinderMesh).height = 0.02
				m.albedo_color = Color(0.04, 0.04, 0.05)
				m.metallic = 0.6
				m.roughness = 0.1
		mesh.material = m
		_meshes[kind] = mesh
	mi.mesh = _meshes[kind]
	if kind in ["seeker", "leader_hunter"]:
		mi.rotation = Vector3(-PI / 2.0, 0, 0) # the cone's tip along -Z, the way looking_at points
	var holder := Node3D.new()
	holder.add_child(mi)
	return holder
