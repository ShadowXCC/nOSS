class_name RacingLine
extends RefCounted
## The AI's line around a track and its target speeds (AI-01; docs/PHYSICS.md §8). The line is a
## lateral offset per centreline sample that bends as little as possible inside the road
## (minimum curvature: wide entry, apex, wide exit), found by relaxing the offsets coarse to
## fine. Target speeds come from the platform: grip-limited corners (with downforce), a
## power-limited forward pass and a grip-limited braking pass. The same line drives the AI,
## the racing-line display and the access assists.

## Road edge to the car's centre, m: half a car plus a little room.
const EDGE_MARGIN := 1.3
## How far onto a curb the line may go, m.
const CURB_USE := 0.5
## A wall standing within WALL_NEAR_M of the edge (an oval's) keeps the line WALL_MARGIN further
## in: brushing it at speed spins a car.
const WALL_NEAR_M := 2.0
const WALL_MARGIN := 0.6
## Relaxation passes per level (sample step): coarse levels shape the line, fine ones polish it.
const LEVELS := [[16, 2500], [4, 700], [1, 150]]
const GRAVITY := 9.81
const AIR_DENSITY := 1.225
const MAX_SPEED := 120.0
## Share of the tires' peak grip the profile counts on at grip 1.0 (load sensitivity, slip
## that isn't at the peak, bumps).
const GRIP_SHARE := 0.92
## Share of peak power that reaches the road on average (gear steps, shifts).
const POWER_SHARE := 0.82
## Braking uses this share of the grip (ABS works around the peak).
const BRAKE_SHARE := 0.9
const ROLLING := 0.012
## Over a crest the line keeps this much of the car's weight on its tires (lifting for it, as a
## driver does), instead of taking off.
const CREST_LOAD := 0.75
## Tires lose grip as they're loaded (their load sensitivity), the outside ones most: across an
## axle cornering at its limit that's about LOAD_SPREAD times the sensitivity per g of load. Only
## the change from 1 g counts (GRIP_SHARE has the rest): banking and dips lose grip, crests gain.
const LOAD_SPREAD := 1.36

## Lines solved lately (track layout -> RacingLine), oldest first.
static var _cache := {}
const CACHE_SIZE := 4

var track: TrackData
## Metres left (+) of the centreline, per sample.
var offsets := PackedFloat32Array()
var points := PackedVector3Array()
## Signed curvature of the line, 1/m (+ = left).
var curvature := PackedFloat32Array()
## Length of the line from sample i to i + 1.
var steps := PackedFloat32Array()
## Per sample: banking into the turn (rad, + helps), grade (rise over run), crest curvature
## (1/m, + over a crest). A flat track has none, and keeps the flat profile (D93).
var bank_in := PackedFloat32Array()
var grade := PackedFloat32Array()
var crest := PackedFloat32Array()
var flat := true
var _profiles := {} # key -> PackedFloat32Array of speeds per sample


## The line for `track`, solved once per layout and kept (the last few).
static func for_track(t: TrackData) -> RacingLine:
	var key := "%s|%s|%d|%.3f" % [t.id, t.layout_hash, t.samples.size(), t.length]
	if not _cache.has(key):
		if _cache.size() >= CACHE_SIZE:
			_cache.erase(_cache.keys()[0])
		_cache[key] = solve(t)
	return _cache[key]


## A line for `t`, solved now and not kept (the editor, while the track changes).
static func solve(t: TrackData) -> RacingLine:
	var line := RacingLine.new()
	line.track = t
	line._solve()
	return line


static func clear_cache() -> void:
	_cache.clear()


## Lateral offset of the line at an along-track distance.
func offset_at(distance: float) -> float:
	var at := _at(distance)
	return lerpf(offsets[int(at.x)], offsets[int(at.y)], at.z)


func curvature_at(distance: float) -> float:
	var at := _at(distance)
	return lerpf(curvature[int(at.x)], curvature[int(at.y)], at.z)


## Target speed at `distance` from a speed_profile().
func speed_at(profile: PackedFloat32Array, distance: float) -> float:
	var at := _at(distance)
	return lerpf(profile[int(at.x)], profile[int(at.y)], at.z)


## How far the road reaches from the line's centre each side at `distance`, for a car centre:
## [left limit, right limit] as offsets from the centreline.
func corridor(distance: float) -> Vector2:
	return corridor_at(track, distance)


static func corridor_at(t: TrackData, distance: float) -> Vector2:
	return limits(t, t.index_at(distance))


## The corridor at sample `i`.
static func limits(t: TrackData, i: int) -> Vector2:
	return Vector2(_limit(t, i, 1.0), -_limit(t, i, -1.0))


## How far a car's centre may go toward the edge on `side` at sample `i`.
static func _limit(t: TrackData, i: int, side: float) -> float:
	var left := side > 0.0
	var wall := int((t.barrier_l if left else t.barrier_r)[i]) > TrackFormat.BARRIER_AUTO and (t.runoff_l_m if left else t.runoff_r_m)[i] < WALL_NEAR_M
	return (t.half_l if left else t.half_r)[i] - EDGE_MARGIN - (WALL_MARGIN if wall else 0.0) + (CURB_USE if (t.curb_l if left else t.curb_r)[i] else 0.0)


## Speeds along the line for `platform` using `grip` (0-1] of what the profile counts on, its
## drag times `drag_scale` (in a slipstream, D208). Without `power_limited` it's the ceiling: how
## fast the corners and the braking for them allow, however much power there is. Cached.
func speed_profile(platform: Dictionary, grip := 1.0, drag_scale := 1.0, power_limited := true) -> PackedFloat32Array:
	var key := "%s|%s|%.3f" % [platform.get("id", ""), platform.get("version", ""), grip]
	if drag_scale != 1.0 or not power_limited:
		key += "|%.3f|%s" % [drag_scale, power_limited]
	if _profiles.has(key):
		return _profiles[key]
	var n := points.size()
	var mass := float(platform.mass.kg)
	var mu := float(platform.tires.mu_peak) * GRIP_SHARE * grip
	var aero: Dictionary = platform.get("aero", {})
	var downforce := 0.5 * AIR_DENSITY * maxf(-(float(aero.get("cl_a_front", 0.0)) + float(aero.get("cl_a_rear", 0.0))), 0.0) / mass
	var drag := 0.5 * AIR_DENSITY * float(aero.get("cd_a", 0.8)) / mass * drag_scale
	var power := GameModes.peak_power_kw(platform) * 1000.0 * POWER_SHARE / mass
	var front := float(platform.mass.front_weight)
	var drive := String(platform.layout.drive)
	var driven := front if drive == "fwd" else (1.0 - front if drive == "rwd" else 1.0)
	var brake_cap := max_braking(platform, mu) / mu # share of the grip the brake balance allows
	if not flat:
		var sensitivity := float(platform.tires.get("load_sensitivity", 0.08)) * LOAD_SPREAD
		_profiles[key] = _profile_3d(mu, downforce, drag, power, driven, brake_cap, sensitivity, power_limited)
		return _profiles[key]

	# Corner limits: v² |κ| <= mu (g + downforce v²).
	var v := PackedFloat32Array()
	v.resize(n)
	for i in n:
		var k := absf(curvature[i])
		var denom := k - mu * downforce
		v[i] = MAX_SPEED if denom <= 1e-6 else minf(sqrt(mu * GRAVITY / denom), MAX_SPEED)
	# Start both passes from the slowest corner so the loop closes.
	var slowest := 0
	for i in n:
		if v[i] < v[slowest]:
			slowest = i
	# Forward: power and traction.
	for pass_i in (2 if power_limited else 0):
		for s in n:
			var i := (slowest + s) % n
			var j := (i + 1) % n
			var u := v[i]
			var grip_total := mu * (GRAVITY + downforce * u * u)
			var used := clampf(u * u * absf(curvature[i]) / maxf(grip_total, 1e-3), 0.0, 1.0)
			var spare := sqrt(1.0 - used * used)
			var a := minf(power / maxf(u, 1.0), grip_total * driven) * spare - drag * u * u - ROLLING * GRAVITY
			v[j] = minf(v[j], sqrt(maxf(u * u + 2.0 * a * steps[i], 0.0)))
	# Backward: braking.
	for pass_i in 2:
		for s in n:
			var j := (slowest - s + n) % n
			var i := (j - 1 + n) % n
			var u := v[j]
			var grip_total := mu * (GRAVITY + downforce * u * u)
			var used := clampf(u * u * absf(curvature[j]) / maxf(grip_total, 1e-3), 0.0, 1.0)
			var spare := sqrt(1.0 - used * used)
			var b := grip_total * minf(BRAKE_SHARE, brake_cap) * spare + drag * u * u + ROLLING * GRAVITY
			v[i] = minf(v[i], sqrt(u * u + 2.0 * b * steps[i]))
	_profiles[key] = v
	return v


## The profile on a track with banking, slopes or crests: banking into a turn lets it be taken
## faster, a crest unloads the tires, a climb slows the car and helps it brake.
func _profile_3d(mu: float, downforce: float, drag: float, power: float, driven: float, brake_cap: float, sensitivity := 0.0, power_limited := true) -> PackedFloat32Array:
	var n := points.size()
	var v := PackedFloat32Array()
	v.resize(n)
	# The grip at a load of `normal` (m/s² pressing the car into the road).
	var mu_at := func(normal: float) -> float: return mu * maxf(1.0 - sensitivity * (normal / GRAVITY - 1.0), 0.5)
	for i in n:
		var k := absf(curvature[i])
		var c := cos(bank_in[i])
		var s := sin(bank_in[i])
		v[i] = MAX_SPEED
		var m := mu
		for pass_i in 3: # the corner's load sets the grip, which sets the speed
			var denom := k * (c - m * s) - m * downforce
			var num := GRAVITY * (m * c + s)
			v[i] = MAX_SPEED if denom <= 1e-6 or num <= 0.0 else minf(sqrt(num / denom), MAX_SPEED)
			m = mu_at.call(GRAVITY * c + v[i] * v[i] * k * s)
		if crest[i] > 1e-5: # over a crest, slow enough that the tires keep some load
			v[i] = minf(v[i], sqrt(GRAVITY * cos(atan(grade[i])) * CREST_LOAD / crest[i]))
	var slowest := 0
	for i in n:
		if v[i] < v[slowest]:
			slowest = i
	var grip := func(i: int, u: float) -> Vector2: # (total grip, share of it the corner uses)
		# Banking into the turn presses the car into the road (and takes some of the weight off it).
		var normal := maxf(GRAVITY * cos(atan(grade[i])) * cos(bank_in[i]) + u * u * absf(curvature[i]) * sin(bank_in[i]) - u * u * crest[i], GRAVITY * 0.2)
		var total: float = mu_at.call(normal) * (normal + downforce * u * u)
		var lateral := maxf(u * u * absf(curvature[i]) * cos(bank_in[i]) - GRAVITY * sin(bank_in[i]), 0.0)
		return Vector2(total, clampf(lateral / maxf(total, 1e-3), 0.0, 1.0))
	for pass_i in (2 if power_limited else 0):
		for step in n:
			var i := (slowest + step) % n
			var j := (i + 1) % n
			var u := v[i]
			var g: Vector2 = grip.call(i, u)
			var spare := sqrt(1.0 - g.y * g.y)
			var a := minf(power / maxf(u, 1.0), g.x * driven) * spare - drag * u * u - ROLLING * GRAVITY - GRAVITY * sin(atan(grade[i]))
			v[j] = minf(v[j], sqrt(maxf(u * u + 2.0 * a * steps[i], 0.0)))
	for pass_i in 2:
		for step in n:
			var j := (slowest - step + n) % n
			var i := (j - 1 + n) % n
			var u := v[j]
			var g: Vector2 = grip.call(j, u)
			var spare := sqrt(1.0 - g.y * g.y)
			var b := g.x * minf(BRAKE_SHARE, brake_cap) * spare + drag * u * u + ROLLING * GRAVITY + GRAVITY * sin(atan(grade[i]))
			v[i] = minf(v[i], sqrt(maxf(u * u + 2.0 * b * steps[i], 0.0)))
	return v


## The ceiling: how fast the corners and the braking for them allow (speed_profile without the
## power), for a car a tow can carry past its own pace.
func ceiling(platform: Dictionary, grip := 1.0) -> PackedFloat32Array:
	return speed_profile(platform, grip, 1.0, false)


## Deceleration (in g × mu units, i.e. m/s² per unit of grip) the brakes reach before one axle
## is at its grip limit: braking moves load forward, so a rear-biased balance runs out of rear
## grip first and the car turns round. Returns m/s² for `mu`.
static func max_braking(platform: Dictionary, mu: float) -> float:
	var bias := float(platform.brakes.bias_front)
	var front := float(platform.mass.front_weight)
	var h_over_l := float(platform.mass.cog_height_over_track) * float(platform.geometry.track_m.ref) / float(platform.geometry.wheelbase_m.ref)
	# Front: bias·a <= mu (front + a·h/L); rear: (1 - bias)·a <= mu (1 - front - a·h/L), in g.
	var a_rear := mu * (1.0 - front) / ((1.0 - bias) + mu * h_over_l)
	var denom := bias - mu * h_over_l
	var a_front := mu * front / denom if denom > 1e-6 else INF
	return minf(minf(a_front, a_rear), mu) * GRAVITY


## Time the profile takes from one along-track distance to the next (forward), s.
func time_between(profile: PackedFloat32Array, from: float, to: float) -> float:
	var span := fposmod(to - from, track.length)
	var t := 0.0
	var d := 0.0
	while d < span:
		var step := minf(TrackData.SAMPLE_M, span - d)
		t += step / maxf(speed_at(profile, from + d + step / 2.0), 1.0)
		d += step
	return t


## Lap time the profile predicts, s (tuning aid).
func lap_time(profile: PackedFloat32Array) -> float:
	var t := 0.0
	for i in profile.size():
		t += steps[i] / maxf((profile[i] + profile[(i + 1) % profile.size()]) / 2.0, 0.1)
	return t


# --- solving ------------------------------------------------------------------------------


func _solve() -> void:
	var n := track.samples.size()
	var base := PackedVector2Array()
	var lefts := PackedVector2Array()
	var to_left := PackedFloat32Array()
	var limit_l := PackedFloat32Array()
	var limit_r := PackedFloat32Array()
	base.resize(n)
	lefts.resize(n)
	to_left.resize(n)
	limit_l.resize(n)
	limit_r.resize(n)
	for i in n:
		base[i] = Vector2(track.samples[i].x, track.samples[i].z)
		# A banked sample's left, seen from above, is shorter (cos(bank)): an offset along the
		# road moves the line less across the map. Flat samples keep the unit left exactly.
		var left := Vector2(track.lefts[i].x, track.lefts[i].z)
		var banked := i < track.bank.size() and track.bank[i] != 0.0
		lefts[i] = left if banked else left.normalized()
		to_left[i] = 1.0 / maxf(left.length_squared(), 1e-6) if banked else 1.0
		limit_l[i] = _limit(track, i, 1.0)
		limit_r[i] = _limit(track, i, -1.0)
	offsets.resize(n)
	offsets.fill(0.0)
	# The editor's pins: fixed offsets the line bends through, inside the road. A kart track's
	# loops add theirs: into the entry lane, out of the exit lane (D143).
	var pins := {}
	for pin: Dictionary in track.ai_pins + (track.kart.ai_pins() if track.kart else []):
		var k := track.index_at(float(pin.at_m))
		pins[k] = clampf(float(pin.offset_m), -limit_r[k], limit_l[k])
		offsets[k] = pins[k]
	for level: Array in LEVELS:
		var step: int = level[0]
		var ring := PackedInt32Array()
		for i in range(0, n, step):
			ring.append(i)
		if not pins.is_empty():
			for k: int in pins:
				if k not in ring:
					ring.append(k)
			ring.sort()
		_relax(ring, level[1], base, lefts, to_left, limit_l, limit_r, pins)
		_fill_between(ring)

	points.resize(n)
	steps.resize(n)
	curvature.resize(n)
	for i in n:
		points[i] = track.samples[i] + track.lefts[i] * offsets[i]
	for i in n:
		steps[i] = points[i].distance_to(points[(i + 1) % n])
	# Curvature from points two samples apart either side, then smoothed a little.
	var raw := PackedFloat32Array()
	raw.resize(n)
	for i in n:
		var a := _flat(points[(i - 2 + n) % n])
		var b := _flat(points[i])
		var c := _flat(points[(i + 2) % n])
		var ab := b - a
		var bc := c - b
		var ca := a - c
		raw[i] = 2.0 * ab.cross(bc) / maxf(ab.length() * bc.length() * ca.length(), 1e-6)
	for i in n:
		var sum := 0.0
		for k in range(-2, 3):
			sum += raw[(i + k + n) % n]
		curvature[i] = sum / 5.0
	# Match the centreline's sign convention (+ = left) whatever the axes' handedness.
	var dot := 0.0
	for i in n:
		dot += curvature[i] * track.curvature[i]
	if dot < 0.0:
		for i in n:
			curvature[i] = -curvature[i]
	_slopes(track)


## Banking into each turn, and the grade and crests along the line (all zero on a flat track).
## The line's own heights: on banking it runs higher or lower than the centreline, whose height
## rises and falls with the banking.
func _slopes(track: TrackData) -> void:
	var n := points.size()
	bank_in.resize(n)
	grade.resize(n)
	crest.resize(n)
	flat = true
	for i in n:
		var a := points[(i - 2 + n) % n]
		var b := points[i]
		var c := points[(i + 2) % n]
		var run_ab := maxf(_flat(b - a).length(), 0.1)
		var run_bc := maxf(_flat(c - b).length(), 0.1)
		var g_ab := (b.y - a.y) / run_ab
		var g_bc := (c.y - b.y) / run_bc
		grade[i] = (g_ab + g_bc) * 0.5
		crest[i] = -(g_bc - g_ab) / ((run_ab + run_bc) * 0.5)
		bank_in[i] = -track.bank[i] * signf(curvature[i]) if i < track.bank.size() else 0.0
		if absf(grade[i]) > 1e-4 or absf(crest[i]) > 1e-6 or absf(bank_in[i]) > 1e-4:
			flat = false


## Gauss-Seidel on the line's squared second differences, each point kept inside its limits.
## `to_left` turns a move across the map into an offset along the road (1 where it's flat).
func _relax(ring: PackedInt32Array, passes: int, base: PackedVector2Array, lefts: PackedVector2Array, to_left: PackedFloat32Array, limit_l: PackedFloat32Array, limit_r: PackedFloat32Array, pins := {}) -> void:
	var m := ring.size()
	var p := PackedVector2Array()
	p.resize(m)
	for a in m:
		var k := ring[a]
		p[a] = base[k] + lefts[k] * offsets[k]
	for pass_i in passes:
		for a in m:
			var k := ring[a]
			if pins.has(k):
				continue
			var target := (4.0 * (p[(a - 1 + m) % m] + p[(a + 1) % m]) - p[(a - 2 + m) % m] - p[(a + 2) % m]) / 6.0
			var o := clampf((target - base[k]).dot(lefts[k]) * to_left[k], -limit_r[k], limit_l[k])
			p[a] = base[k] + lefts[k] * o
			offsets[k] = o


## Offsets between the ring's points, linearly.
func _fill_between(ring: PackedInt32Array) -> void:
	var n := offsets.size()
	var m := ring.size()
	for a in m:
		var k0 := ring[a]
		var k1 := ring[(a + 1) % m]
		var span := posmod(k1 - k0, n)
		if span == 0:
			span = n
		for s in range(1, span):
			offsets[(k0 + s) % n] = lerpf(offsets[k0], offsets[k1], float(s) / span)


## (i, j, t): the samples around `distance` and how far between them.
func _at(distance: float) -> Vector3:
	var i := track.index_at(distance)
	var j := (i + 1) % points.size()
	var span := (track.distances[j] if j > 0 else track.length) - track.distances[i]
	var t := clampf((fposmod(distance, track.length) - track.distances[i]) / maxf(span, 0.001), 0.0, 1.0)
	return Vector3(i, j, t)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)
