class_name EndlessLanes
extends RefCounted
## The endless road's lanes (docs/GAMEMODES.md §4, D190): one or two each way, driven on the right
## or on the left. A lane's id is pos * 2 + dir: dir UP (0, the players' way) or DOWN (1, oncoming),
## pos 0 by the centre line and 1 by the edge. So ids 0 and 1 are a two-lane road's lanes, as they
## always were. Laterals are + to the left of the road (TrackData).
##
## Two each way, cars keep to the edge lane and pass in the one by the centre, and the two lanes
## run at their own speeds (speed_factor): the schedule stays exact, so cars in one lane never meet.

const UP := 0
const DOWN := 1
## Four lanes: the passing lane runs this much faster than the road's traffic speed, the other
## this much slower.
const PASS_FACTOR := 1.12
const KEEP_FACTOR := 0.96
## A car pulled over has its centre this far in from the road's edge.
const PULL_OVER_IN_M := 1.1

## Lanes each way (1 or 2), and driving on the left.
var per_dir := 1
var left_hand := false


static func make(lanes: int, side: String) -> EndlessLanes:
	var l := EndlessLanes.new()
	l.per_dir = 2 if lanes >= 4 else 1
	l.left_hand = side == "left"
	return l


func count() -> int:
	return per_dir * 2


## Every lane's id.
func ids() -> Array[int]:
	var out: Array[int] = []
	for i in count():
		out.append(i)
	return out


static func id(pos: int, dir: int) -> int:
	return pos * 2 + dir


static func dir_of(lane: int) -> int:
	return lane & 1


static func pos_of(lane: int) -> int:
	return lane >> 1


## The position a car keeps to when it isn't passing: by the edge.
func keep_pos() -> int:
	return per_dir - 1


func keep_lane(dir: int) -> int:
	return id(keep_pos(), dir)


## Where a car going `dir` passes: its own lane by the centre, or (one each way) the oncoming one.
func pass_lane(dir: int) -> int:
	return id(0, dir) if per_dir == 2 else id(0, 1 - dir)


## Whether passing means going into the oncoming lane.
func passes_oncoming() -> bool:
	return per_dir == 1


## Which side of the centre line a way drives on: -1 the right, 1 the left (as laterals).
func side_sign(dir: int) -> float:
	var s := -1.0 if dir == UP else 1.0
	return -s if left_hand else s


## Of the road's traffic speed, how fast lane `lane` runs.
func speed_factor(lane: int) -> float:
	if per_dir == 1:
		return 1.0
	return PASS_FACTOR if pos_of(lane) == 0 else KEEP_FACTOR


## One lane's width at absolute distance `s`.
func lane_w(road: RoadWindow, s: float) -> float:
	return (road.half_width(s, 1.0) - RoadWindow.SHOULDER_M) / per_dir


## Lane `lane`'s centre at `s`, as a lateral.
func lateral(road: RoadWindow, lane: int, s: float) -> float:
	return side_sign(dir_of(lane)) * lane_w(road, s) * (pos_of(lane) + 0.5)


## The lane a lateral at `s` is in.
func lane_at(road: RoadWindow, s: float, lat: float) -> int:
	var dir := UP if lat * side_sign(UP) >= 0.0 else DOWN
	return id(clampi(floori(absf(lat) / lane_w(road, s)), 0, per_dir - 1), dir)


## Where a car going `dir` pulls over at `s`: at the edge on its own side.
func shoulder(road: RoadWindow, dir: int, s: float) -> float:
	return side_sign(dir) * (road.half_width(s, 1.0) - PULL_OVER_IN_M)
