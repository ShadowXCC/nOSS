class_name SumoLayout
extends ArenaLayout
## Sumo platforms (D162): 1-3 discs stacked on one centre, each lower one wider, floating in a
## pit over lava or acid. A disc shrinks once a car is on it; when it has gone, whoever was still
## on it falls to the next one, or into the goo. Built from the match settings alone, so every
## game makes the same arena without a track file and nothing but the radii go on the wire.

## Each tier's starting radius, the top one first (m). Lower tiers are wider, so a car knocked
## off one lands on the next (D163). The steps are wide enough to catch a car thrown off by a
## whole ring going at once, which is the longest fall a stepped or crumbling platform makes.
const RADII := [24.0, 36.0, 48.0]
## From one tier's floor down to the next (m).
const DROP_M := 18.0
## The goo's surface, below the lowest tier (m).
const HAZARD_DROP_M := 16.0
## The pit wall stands this far out from the widest tier, and this far above the top one.
const PIT_MARGIN_M := 34.0
const PIT_RIM_M := 26.0
## Sudden death: the bottom tier stops here instead of going altogether (m). It holds that size
## for a while, then goes after all, so two cautious drivers cannot stall the match for ever.
const PILLAR_R := 6.0
const PILLAR_HOLD_S := 25.0
const PILLAR_FADE_S := 20.0
## The rim slopes out this far past the floor, to catch a car that lands on the edge.
const LIP_M := 2.5
## This far above a tier's floor, and this far below it, still counts as belonging to it (a car
## on its way down belongs to the platform it is about to land on).
const BAND_ABOVE_M := 6.0
const BAND_BELOW_M := 2.5
## Within this of the floor it is really standing on it, which is what starts the shrink.
const ON_BAND_M := 2.5
## Steps a stepped or crumbling platform takes on its way out, and the warning before each.
const STEPS := 6
const WARN_S := 1.5
## Points round a disc's edge: enough that it reads as a circle, few enough to rebuild often.
const SEGMENTS := 48

## [{ start, radius, floor_y, live, armed, elapsed }], the top tier first.
var tiers: Array[Dictionary] = []
## "lava" or "acid".
var hazard := "lava"
## "smooth", "crumble" or "stepped".
var style := "smooth"
## How long one platform takes to shrink away.
var secs := 90.0
## Sudden death: the bottom tier stops at a pillar.
var pillar := false
var hazard_y := 0.0
var pit_r := 0.0


## The platforms a match's settings call for. `t` is the stand-in track they hang on.
static func make(t: TrackData, event: RaceEvent) -> SumoLayout:
	var a := SumoLayout.new()
	a.track = t
	a.settings = DEFAULTS.duplicate(true)
	a.hazard = String(event.sumo_hazard)
	a.style = String(event.sumo_shrink)
	a.secs = float(event.sumo_secs)
	a.pillar = bool(event.sumo_pillar)
	var count := clampi(int(event.sumo_tiers), 1, RADII.size())
	for i in count:
		a.tiers.append({ "start": RADII[i], "radius": RADII[i], "floor_y": -DROP_M * i, "live": true, "armed": false, "elapsed": 0.0 })
	a.floor_y = 0.0
	a.centre = Vector2.ZERO
	a.hazard_y = -DROP_M * (count - 1) - HAZARD_DROP_M
	a.pit_r = RADII[count - 1] + PIT_MARGIN_M
	a.outline = ring(RADII[0])
	a.area = PI * RADII[0] * RADII[0]
	a._sumo_spawns()
	return a


## A circle of `n` points round the middle, counter-clockwise (x, z).
static func ring(radius: float, n := SEGMENTS) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var ang := TAU * i / n
		out.append(Vector2(cos(ang), sin(ang)) * radius)
	return out


func count() -> int:
	return tiers.size()


func radius_of(i: int) -> float:
	return float(tiers[i].radius) if i >= 0 and i < tiers.size() else 0.0


func floor_y_of(i: int) -> float:
	return float(tiers[i].floor_y) if i >= 0 and i < tiers.size() else hazard_y


func live(i: int) -> bool:
	return i >= 0 and i < tiers.size() and bool(tiers[i].live)


## The tier `pos` is on, or -1 for none: a live disc whose floor is within a band of `pos` and
## whose edge it is inside. Tiers are tested top down, so a car falling past one belongs to the
## one it is about to land on.
func tier_at(pos: Vector3) -> int:
	var r := Vector2(pos.x, pos.z).length()
	for i in tiers.size():
		var t := tiers[i]
		if not t.live:
			continue
		var y := float(t.floor_y)
		if pos.y <= y + BAND_ABOVE_M and pos.y >= y - BAND_BELOW_M and r <= float(t.radius):
			return i
	return -1


## The tier `pos` is standing on, or -1: like tier_at, but it has to be down on the floor rather
## than on its way to it. This is what starts a platform shrinking.
func standing_on(pos: Vector3) -> int:
	var i := tier_at(pos)
	if i < 0 or pos.y > floor_y_of(i) + ON_BAND_M:
		return -1
	return i


## On a platform, at least `margin` from its edge (ArenaLayout.inside, for a stack of discs).
func inside(pos: Vector3, margin := 0.0) -> bool:
	var i := tier_at(pos)
	return i >= 0 and Vector2(pos.x, pos.z).length() <= float(tiers[i].radius) - margin


## How far `pos` is from the edge of the tier it is on (negative: off the edge).
func edge_distance(pos: Vector3) -> float:
	var i := tier_at(pos)
	if i < 0:
		return -INF
	return float(tiers[i].radius) - Vector2(pos.x, pos.z).length()


## The lowest tier still standing, or -1 when the goo is all that's left.
func lowest_live() -> int:
	for i in range(tiers.size() - 1, -1, -1):
		if tiers[i].live:
			return i
	return -1


## Start tier `i` shrinking (a car has landed on it). Already shrinking: nothing.
func arm(i: int) -> void:
	if i >= 0 and i < tiers.size() and not tiers[i].armed:
		tiers[i].armed = true


func armed(i: int) -> bool:
	return i >= 0 and i < tiers.size() and bool(tiers[i].armed)


## Tier `i` is about to lose a ring (stepped and crumbling only), so the HUD can warn.
func stepping(i: int) -> bool:
	if style == "smooth" or not armed(i) or not live(i):
		return false
	var per := secs / float(STEPS)
	var into := fmod(float(tiers[i].elapsed), per)
	return into >= per - WARN_S


## The smallest a tier may get: nothing, or the sudden-death pillar on the bottom one.
func floor_radius(i: int) -> float:
	return PILLAR_R if pillar and i == tiers.size() - 1 else 0.0


## Shrinks every armed tier. Returns the tiers that went altogether this step.
func advance(delta: float) -> Array[int]:
	var gone: Array[int] = []
	for i in tiers.size():
		var t := tiers[i]
		if not t.live or not t.armed:
			continue
		t.elapsed = float(t.elapsed) + delta
		var start := float(t.start)
		var at := clampf(float(t.elapsed) / maxf(secs, 1.0), 0.0, 1.0)
		var left := 1.0 - at
		if style != "smooth":
			# Rings come off a step at a time; crumbling only differs in how it looks.
			left = 1.0 - clampf(floorf(at * STEPS) / float(STEPS), 0.0, 1.0)
		var least := floor_radius(i)
		var want := start * left
		if least > 0.0 and want <= least:
			# Sudden death: it holds at the pillar, then that goes too (a match always ends).
			var held := float(t.elapsed) - secs * (1.0 - least / start) - PILLAR_HOLD_S
			t.radius = least if held <= 0.0 else maxf(least * (1.0 - held / PILLAR_FADE_S), 0.0)
		else:
			t.radius = maxf(want, least)
		if float(t.radius) <= 0.0:
			t.live = false
			t.radius = 0.0
			gone.append(i)
	return gone


## Every platform back to its full size, none of them going yet (a match restarted).
func restore() -> void:
	for t in tiers:
		t.radius = float(t.start)
		t.elapsed = 0.0
		t.armed = false
		t.live = true


## Every tier's radius, for a snapshot over the wire.
func radii() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for t in tiers:
		out.append(float(t.radius))
	return out


## A server's radii (online clients follow rather than shrink on their own).
func apply_radii(from: PackedFloat32Array) -> void:
	for i in mini(from.size(), tiers.size()):
		var r := float(from[i])
		tiers[i].radius = r
		tiers[i].armed = bool(tiers[i].armed) or r < float(tiers[i].start) - 0.01
		tiers[i].live = r > 0.0 or floor_radius(i) > 0.0


## A ring of spawns part way out on the top tier, every car facing the middle.
func _sumo_spawns() -> void:
	var r: float = RADII[0] * SPAWN_RING
	for i in AUTO_SPAWNS:
		var ang := TAU * i / AUTO_SPAWNS
		var at := Vector2(cos(ang), sin(ang)) * r
		var to_middle := -at.normalized()
		# +Z toward the middle, as on any arena.
		spawns.append(Transform3D(Basis(Vector3.UP, atan2(to_middle.x, to_middle.y)), Vector3(at.x, 0.0, at.y)))
