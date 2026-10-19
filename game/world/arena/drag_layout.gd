class_name DragLayout
extends ArenaLayout
## A drag strip (D168): two lanes down a flat deck, built from the match settings alone, so there
## is no track file and nothing of the strip goes on the wire. The strip runs along +Z: the water
## box and the staging lanes sit behind the start line at z = 0, the finish is at the picked
## length, and past it a shutdown area long enough to stop a Top Fuel car in, ending in sand.
##
## The outline is a long rectangle, so ArenaLayout's floor and wall and ArenaBuilder's deck serve
## as they stand; DragBuilder only adds the markings and the sand.

## Lane width and the gap each side of the centreline. A lane's middle is half a lane out.
const LANE_W := 4.0
## Deck past the outer lane edges: room to correct, and where the wall stands.
const SHOULDER_M := 3.0
## Behind the start line: the staging lanes and, further back, the water box.
const STAGE_BACK_M := 50.0
## Where a car stages, just short of the line, and where a burnout is done.
const STAGE_Z := -3.0
const BURNOUT_Z := -30.0
## Shutdown past the finish: as long again as the strip, within these bounds. A Top Fuel car
## through the lights at 95 m/s needs about 470 m to stop at 1 g.
const SHUTDOWN_MIN_M := 250.0
const SHUTDOWN_MAX_M := 700.0
## The last of the shutdown is sand, to stop anyone who never got on the brakes.
const TRAP_M := 60.0
## The strip lengths the menu offers (m): 1/8, 1/4 and 1/2 mile.
const LENGTHS := [201, 402, 805]


## The strip this match's settings call for. `t` is the stand-in track it hangs on.
static func make(t: TrackData, event: RaceEvent) -> DragLayout:
	var a := DragLayout.new()
	a.track = t
	a.settings = DEFAULTS.duplicate(true)
	a.settings.floor = "asphalt"
	a.settings.wall = "concrete"
	a.length_m = float(clampi(int(event.drag_length_m), LENGTHS[0], LENGTHS[LENGTHS.size() - 1]))
	a.shutdown_m = clampf(a.length_m, SHUTDOWN_MIN_M, SHUTDOWN_MAX_M)
	a.floor_y = 0.0
	a.half_width = LANE_W + SHOULDER_M
	a.outline = rect_of(a.half_width, a.back_z(), a.end_z())
	a.centre = Vector2(0.0, (a.back_z() + a.end_z()) / 2.0)
	a.area = 2.0 * a.half_width * (a.end_z() - a.back_z())
	a._lane_spawns()
	return a


## The picked distance from the start line to the finish (m).
var length_m := 402.0
## Shutdown past the finish, sand included.
var shutdown_m := 402.0
## Deck from the centreline to its edge.
var half_width := LANE_W + SHOULDER_M


## Behind the start line, and the far end of the deck.
func back_z() -> float:
	return -STAGE_BACK_M


func end_z() -> float:
	return length_m + shutdown_m


## Where the sand starts.
func trap_z() -> float:
	return end_z() - TRAP_M


## The middle of lane `lane` (0: left, 1: right).
func lane_x(lane: int) -> float:
	return (LANE_W * 0.5) * (1.0 if lane == 1 else -1.0)


## Where car `lane` stages, facing down the strip (+Z is forward).
func spawn_of(lane: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(lane_x(lane), floor_y, STAGE_Z))


## Where a burnout is done, in the same lane.
func burnout_of(lane: int) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(lane_x(lane), floor_y, BURNOUT_Z))


## How far past the start line `pos` is (negative behind it).
func distance_from_start(pos: Vector3) -> float:
	return pos.z


## Through the lights.
func past_finish(pos: Vector3) -> bool:
	return pos.z >= length_m


## In the sand.
func in_trap(pos: Vector3) -> bool:
	return pos.z >= trap_z()


## The lane `pos` is in (0 or 1), or -1 over the centreline or off the outer edge. `margin`
## keeps that much clear of each lane edge.
func lane_of(pos: Vector3, margin := 0.0) -> int:
	for lane in 2:
		var x := lane_x(lane)
		if absf(pos.x - x) <= LANE_W * 0.5 - margin:
			return lane
	return -1


## `pos` is over the centreline, into the other lane (the foul, where it is on).
func crossed_centreline(pos: Vector3, lane: int) -> bool:
	return signf(pos.x) != signf(lane_x(lane)) and absf(pos.x) > 0.0


## How far `pos` is from the centreline, on its own side (negative: over it).
func centreline_distance(pos: Vector3, lane: int) -> float:
	return pos.x * signf(lane_x(lane))


## Off the outer edge of the deck.
func off_deck(pos: Vector3) -> bool:
	return absf(pos.x) > half_width or pos.z < back_z() or pos.z > end_z()


## The deck's outline for a match's settings, before there is a layout to ask: TrackSession
## synthesises the stand-in track from it, as it does from the sumo arena's ring.
static func outline_for(event: RaceEvent) -> PackedVector2Array:
	var length := float(clampi(int(event.drag_length_m), LENGTHS[0], LENGTHS[LENGTHS.size() - 1]))
	var shutdown := clampf(length, SHUTDOWN_MIN_M, SHUTDOWN_MAX_M)
	return rect_of(LANE_W + SHOULDER_M, -STAGE_BACK_M, length + shutdown)


## A rectangle, counter-clockwise (x, z).
static func rect_of(half_w: float, z0: float, z1: float) -> PackedVector2Array:
	var out := PackedVector2Array([
		Vector2(-half_w, z0), Vector2(half_w, z0), Vector2(half_w, z1), Vector2(-half_w, z1),
	])
	if Geometry2D.is_polygon_clockwise(out):
		out.reverse()
	return out


## Two spawns, one a lane, staged and facing down the strip. The field is paired two at a time
## (D170), so a pass only ever needs these two.
func _lane_spawns() -> void:
	for lane in 2:
		spawns.append(spawn_of(lane))
