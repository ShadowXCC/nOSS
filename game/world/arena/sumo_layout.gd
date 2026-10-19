class_name SumoLayout
extends ArenaLayout
## Sumo platforms (D162): 1-5 discs stacked on one centre, each lower one wider, floating in a
## pit over lava or acid. A disc shrinks once a car is on it; when it has gone, whoever was still
## on it falls to the next one, or into the goo. Built from the match settings alone, so every
## game makes the same arena without a track file and nothing but the radii go on the wire.

## Each tier's starting radius, the top one first (m). Lower tiers are wider, so a car knocked
## off one lands on the next (D163). The steps are wide enough to catch a car thrown off by a
## whole ring going at once, which is the longest fall a stepped or crumbling platform makes.
const RADII := [24.0, 36.0, 48.0, 60.0, 72.0]
## From one tier's floor down to the next (m).
const DROP_M := 18.0
## The goo's surface, below the lowest tier (m). Shallow enough, against the pit's width, that
## the pool is in view past the platform's rim rather than hidden behind it — and the band of it
## widens as the platform shrinks, so the goo closes in on the eye as well as underfoot.
const HAZARD_DROP_M := 5.0
## The pit wall stands this far out from the widest tier, and this far above the top one: wide
## enough that the pool is seen past the rim, high enough to still read as a wall.
const PIT_MARGIN_M := 45.0
const PIT_RIM_M := 22.0
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
## The wedges a platform is thought of in: what the warning before a ring goes is marked in, and
## what a crumbling platform comes off in (D182). SEGMENTS divides by it.
const SECTORS := 16
## Every wedge at once: a whole ring is on its way out, not a piece of one.
const ALL_WEDGES := (1 << SECTORS) - 1
## A crumbling platform's bites (D182): each wedge takes one a step, in a shuffled order, so the
## rim goes ragged without ever being more than one bite out of round. The last step is left to
## come off as a whole ring, because a wedge bitten STEPS times is a slice cut to the middle, and
## then there is no floor at the centre and nothing sensible to say about a car parked on it.
const BITES := STEPS - 1
const EVENTS := BITES * SECTORS
const SLOTS := STEPS * SECTORS

## [{ start, radius, floor_y, live, armed, elapsed, warn, hits, done, plan }], the top tier first.
## `warn` is a bitmask of the wedges about to go, which the authority works out and a client is
## told (D183). `radius` is the widest wedge, which is also the bound they are all held under.
## `hits` is how many bites each wedge has taken, `plan` the order they come off in and `done` how
## far through it this tier is (crumbling only, D182).
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
		a.tiers.append({ "start": RADII[i], "radius": RADII[i], "floor_y": -DROP_M * i, "live": true,
			"armed": false, "elapsed": 0.0, "warn": 0, "hits": no_bites(), "done": 0,
			"plan": crumble_plan() if a.style == "crumble" else PackedByteArray() })
	a.floor_y = 0.0
	a.centre = Vector2.ZERO
	a.hazard_y = -DROP_M * (count - 1) - HAZARD_DROP_M
	a.pit_r = RADII[count - 1] + PIT_MARGIN_M
	a.outline = ring(RADII[0])
	a.area = PI * RADII[0] * RADII[0]
	a._sumo_spawns()
	return a


## The order a crumbling platform's wedges come off in: every wedge once a step, shuffled within
## each step. That is what keeps the depths within one bite of each other, so the rim is ragged but
## still roughly round -- no deep slot, no island, and no spike for a car or a bot to trip on. From
## the game's own random numbers, so a seeded soak check replays a match exactly; nothing needs it
## to match between machines, because the depths themselves go on the wire.
static func crumble_plan() -> PackedByteArray:
	var out := PackedByteArray()
	for _step in BITES:
		var wedges: Array[int] = []
		for w in SECTORS:
			wedges.append(w)
		wedges.shuffle()
		for w in wedges:
			out.append(w)
	return out


## A platform nothing has been taken out of yet.
static func no_bites() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SECTORS)
	out.fill(0)
	return out


## The wedge an angle round the middle belongs to.
static func wedge_of(angle: float) -> int:
	return mini(int(fposmod(angle, TAU) / TAU * SECTORS), SECTORS - 1)


## The wedge `pos` is over.
static func wedge_at(pos: Vector3) -> int:
	return wedge_of(atan2(pos.z, pos.x))


## A circle of `n` points round the middle, counter-clockwise (x, z).
static func ring(radius: float, n := SEGMENTS) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var ang := TAU * i / n
		out.append(Vector2(cos(ang), sin(ang)) * radius)
	return out


func count() -> int:
	return tiers.size()


## The widest wedge of tier `i`: the size the platform reads as, and the bound every wedge of a
## crumbling one is held under.
func radius_of(i: int) -> float:
	return float(tiers[i].radius) if i >= 0 and i < tiers.size() else 0.0


func floor_y_of(i: int) -> float:
	return float(tiers[i].floor_y) if i >= 0 and i < tiers.size() else hazard_y


func live(i: int) -> bool:
	return i >= 0 and i < tiers.size() and bool(tiers[i].live)


## Wedge `w`'s radius on tier `i`. On anything but a crumbling platform every wedge is the disc's
## own radius; on one, a wedge is as far in as its bites have taken it, under the bound the whole
## platform is held to and no further in than the sudden-death pillar -- until the pillar itself
## starts to go, when the platform is below the pillar and the wedges go down with it.
func wedge_radius(i: int, w: int) -> float:
	if i < 0 or i >= tiers.size():
		return 0.0
	var t := tiers[i]
	if style != "crumble":
		return float(t.radius)
	var hits: PackedByteArray = t.hits
	var bitten := float(t.start) * (1.0 - float(hits[w]) / float(STEPS))
	return clampf(bitten, least_radius(i), float(t.radius))


## The smallest a wedge of tier `i` may be: the pillar while it stands, and the platform itself
## once the pillar is fading (a match always ends).
func least_radius(i: int) -> float:
	return minf(floor_radius(i), float(tiers[i].radius))


## The radius of the wedge `pos` is over on tier `i`.
func radius_at(i: int, pos: Vector3) -> float:
	return wedge_radius(i, wedge_at(pos))


## The tier `pos` is on, or -1 for none: a live disc whose floor is within a band of `pos` and
## whose edge it is inside. Tiers are tested top down, so a car falling past one belongs to the
## one it is about to land on. The radial test only, so a car straddling two wedges still belongs
## to the platform it is driving on rather than flickering into the air between them.
func tier_at(pos: Vector3) -> int:
	var r := Vector2(pos.x, pos.z).length()
	var w := wedge_at(pos)
	for i in tiers.size():
		var t := tiers[i]
		if not t.live:
			continue
		var y := float(t.floor_y)
		if pos.y <= y + BAND_ABOVE_M and pos.y >= y - BAND_BELOW_M and r <= wedge_radius(i, w):
			return i
	return -1


## The tier `pos` is standing on, or -1: like tier_at, but it has to be down on the floor rather
## than on its way to it. This is what starts a platform shrinking.
func standing_on(pos: Vector3) -> int:
	var i := tier_at(pos)
	if i < 0 or pos.y > floor_y_of(i) + ON_BAND_M:
		return -1
	return i


## On a platform, at least `margin` from any edge of it (ArenaLayout.inside, for a stack of discs).
func inside(pos: Vector3, margin := 0.0) -> bool:
	return edge_distance(pos) >= margin


## How far `pos` is from the nearest edge of the tier it is on (negative: off the edge). On a
## crumbling platform that counts the hole beside it as well as the rim ahead: a car can be well
## inside its own wedge and a hand's breadth from the drop where a bitten neighbour starts.
func edge_distance(pos: Vector3) -> float:
	var i := tier_at(pos)
	if i < 0:
		return -INF
	var flat := Vector2(pos.x, pos.z)
	var r := flat.length()
	var w := wedge_at(pos)
	var mine := wedge_radius(i, w)
	var best := mine - r
	if style != "crumble":
		return best
	var ang := atan2(flat.y, flat.x)
	for side: int in [-1, 1]:
		if wedge_radius(i, (w + side + SECTORS) % SECTORS) >= mine - 0.001:
			continue
		# How far it is from the boundary they share, measured across it.
		var bound := TAU * float(w + maxi(side, 0)) / float(SECTORS)
		best = minf(best, absf(r * sin(ang - bound)))
	return best


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


## The wedges of tier `i` about to go, as a bitmask of SECTORS bits (0: none are). Stored rather
## than worked out on the spot, because a client never shrinks a platform of its own -- it has no
## clock to read -- and so had no warning at all before this (D183).
func warning(i: int) -> int:
	return int(tiers[i].warn) if i >= 0 and i < tiers.size() else 0


## Tier `i` is about to lose a whole ring, so the HUD can say so: stepped, and the last ring of a
## crumbling platform. A crumbling platform taking one wedge marks that wedge alone, which is for
## the arena to show and not worth a word.
func stepping(i: int) -> bool:
	return warning(i) == ALL_WEDGES


## Every wedge's radius on tier `i`: all the same on a disc that shrinks whole.
func wedge_radii(i: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if i < 0 or i >= tiers.size():
		return out
	out.resize(SECTORS)
	if style != "crumble":
		out.fill(float(tiers[i].radius))
		return out
	for w in SECTORS:
		out[w] = wedge_radius(i, w)
	return out


## What wedge `w` of tier `i` is left with once the floor now marked has gone: one step further
## in, or the sudden-death pillar.
func next_radius(i: int, w: int) -> float:
	if i < 0 or i >= tiers.size() or w < 0 or w >= SECTORS:
		return 0.0
	return maxf(wedge_radius(i, w) - float(tiers[i].start) / float(STEPS), least_radius(i))


## How much of tier `i` is left, 0..1 of its radius. On a crumbling platform, the radius a disc of
## the same area would have, so the HUD's percentage means the same in all three styles and comes
## down a bite at a time rather than a sixth at a time.
func shrink_of(i: int) -> float:
	if i < 0 or i >= tiers.size():
		return 0.0
	var start := maxf(float(tiers[i].start), 0.01)
	if style != "crumble":
		return clampf(float(tiers[i].radius) / start, 0.0, 1.0)
	var sum := 0.0
	for w in SECTORS:
		var part := wedge_radius(i, w) / start
		sum += part * part
	return clampf(sqrt(sum / float(SECTORS)), 0.0, 1.0)


## Tier `i`'s wedge depths, for a snapshot over the wire.
func hits_of(i: int) -> PackedByteArray:
	return tiers[i].hits if i >= 0 and i < tiers.size() else PackedByteArray()


## Which wedges of tier `i` are on their way out. Smooth creeps in evenly on every edge, so there
## is nothing to point at; stepped loses a whole ring, marked WARN_S before it goes; a crumbling
## one marks the wedge its next bite will take for the whole of that bite's turn, so there is
## always somewhere to look, and its last ring like a stepped one's.
func _warn_mask(i: int) -> int:
	if style == "smooth" or not armed(i) or not live(i):
		return 0
	# Holding at the pillar, or fading with it: what goes next is the pillar, and it goes smoothly.
	var t := tiers[i]
	if float(t.radius) <= floor_radius(i):
		return 0
	var per := secs / float(STEPS)
	var into := fmod(float(t.elapsed), per)
	if style == "crumble":
		var plan: PackedByteArray = t.plan
		if int(t.done) < plan.size():
			return 1 << int(plan[int(t.done)])
	return ALL_WEDGES if into >= per - WARN_S else 0


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
			# Rings come off a step at a time. A crumbling platform takes its wedges out of the step
			# it is in (D182), so this is the bound they are held under rather than the floor itself.
			left = 1.0 - clampf(floorf(at * STEPS) / float(STEPS), 0.0, 1.0)
		var least := floor_radius(i)
		var want := start * left
		if least > 0.0 and want <= least:
			# Sudden death: it holds at the pillar, then that goes too (a match always ends).
			var held := float(t.elapsed) - secs * (1.0 - least / start) - PILLAR_HOLD_S
			t.radius = least if held <= 0.0 else maxf(least * (1.0 - held / PILLAR_FADE_S), 0.0)
		else:
			t.radius = maxf(want, least)
		if style == "crumble":
			_bite(i, at)
		if float(t.radius) <= 0.0:
			t.live = false
			t.radius = 0.0
			gone.append(i)
	# Over every tier, not only the ones that moved: an unarmed one must not be left marked.
	for i in tiers.size():
		tiers[i].warn = _warn_mask(i)
	return gone


## Takes whatever bites tier `i` is due by now, and leaves its radius at the widest wedge. The
## count is worked out from the clock rather than added up tick by tick, so a big step of the clock
## takes every bite it should and nothing drifts apart over a long match.
func _bite(i: int, at: float) -> void:
	var t := tiers[i]
	var plan: PackedByteArray = t.plan
	var want := mini(floori(at * float(SLOTS)), plan.size())
	if int(t.done) < want:
		# Packed arrays are values, not references: this has to be written back.
		var hits: PackedByteArray = t.hits
		while int(t.done) < want:
			var w := int(plan[int(t.done)])
			hits[w] = mini(int(hits[w]) + 1, BITES)
			t.done = int(t.done) + 1
		t.hits = hits
	var widest := 0.0
	for w in SECTORS:
		widest = maxf(widest, wedge_radius(i, w))
	t.radius = widest


## Every platform back to its full size, none of them going yet (a match restarted).
func restore() -> void:
	for t in tiers:
		t.radius = float(t.start)
		t.elapsed = 0.0
		t.armed = false
		t.live = true
		t.warn = 0
		t.hits = no_bites()
		t.done = 0


## Every tier's radius, for a snapshot over the wire.
func radii() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for t in tiers:
		out.append(float(t.radius))
	return out


## A server's platforms (online clients follow rather than shrink on their own): how far each one
## has shrunk, and the wedges it has marked as about to go.
func apply_state(from: PackedFloat32Array, wedges: int, hits: PackedByteArray, warns: PackedInt32Array) -> void:
	for i in mini(from.size(), tiers.size()):
		var r := float(from[i])
		tiers[i].radius = r
		tiers[i].warn = int(warns[i]) if i < warns.size() else 0
		if wedges == SECTORS and hits.size() >= (i + 1) * SECTORS:
			tiers[i].hits = hits.slice(i * SECTORS, (i + 1) * SECTORS)
		# A marked or a bitten tier is a going tier, which is how a client knows one is armed
		# before its widest wedge has lost anything.
		tiers[i].armed = bool(tiers[i].armed) or r < float(tiers[i].start) - 0.01 \
			or int(tiers[i].warn) != 0 or _bitten(i)
		tiers[i].live = r > 0.0 or floor_radius(i) > 0.0


## Whether any of tier `i`'s wedges has been bitten.
func _bitten(i: int) -> bool:
	for h in (tiers[i].hits as PackedByteArray):
		if h > 0:
			return true
	return false


## A server's radii alone (a layout whose platforms shrink whole).
func apply_radii(from: PackedFloat32Array) -> void:
	apply_state(from, 0, PackedByteArray(), PackedInt32Array())


## A ring of spawns part way out on the top tier, every car facing the middle.
func _sumo_spawns() -> void:
	var r: float = RADII[0] * SPAWN_RING
	for i in AUTO_SPAWNS:
		var ang := TAU * i / AUTO_SPAWNS
		var at := Vector2(cos(ang), sin(ang)) * r
		var to_middle := -at.normalized()
		# +Z toward the middle, as on any arena.
		spawns.append(Transform3D(Basis(Vector3.UP, atan2(to_middle.x, to_middle.y)), Vector3(at.x, 0.0, at.y)))
