class_name EndlessMarkings
extends RefCounted
## The endless road's markings (docs/GAMEMODES.md §4, D190): solid white edges; one lane each way,
## a dashed centre line; two each way, a double solid centre line and a dashed one between each
## way's lanes. The centre is yellow on a road driven on the right and white on one driven on the
## left. RoadBuilder draws them in place of a track's own lines.

## Between the two lines of a double centre line.
const DOUBLE_GAP_M := 0.12

var track: TrackData
var lanes: EndlessLanes


func _init(t: TrackData, l: EndlessLanes) -> void:
	track = t
	lanes = l


## Segment i -> j's markings: white ones into `white`, a yellow centre into `yellow`.
func lines(white: MeshBatch, yellow: MeshBatch, i: int, j: int) -> void:
	var from := (track as RoadWindow).offset_m if track is RoadWindow else 0.0
	var dash := fmod(from + track.distances[i], RoadBuilder.DASH_ON + RoadBuilder.DASH_OFF) <= RoadBuilder.DASH_ON
	var edge := RoadBuilder.LINE_INSET + RoadBuilder.LINE_WIDTH / 2.0
	_line(white, i, j, track.half_l[i] - edge, track.half_l[j] - edge)
	_line(white, i, j, -(track.half_r[i] - edge), -(track.half_r[j] - edge))
	var centre := white if lanes.left_hand else yellow
	if lanes.per_dir == 1:
		if dash:
			_line(centre, i, j, 0.0, 0.0)
		return
	var off := (RoadBuilder.LINE_WIDTH + DOUBLE_GAP_M) / 2.0
	_line(centre, i, j, off, off)
	_line(centre, i, j, -off, -off)
	if dash:
		var wi := (track.half_l[i] - RoadWindow.SHOULDER_M) / lanes.per_dir
		var wj := (track.half_l[j] - RoadWindow.SHOULDER_M) / lanes.per_dir
		_line(white, i, j, wi, wj)
		_line(white, i, j, -wi, -wj)


## A line along the segment, its middle at these laterals (+ left).
func _line(b: MeshBatch, i: int, j: int, lat_i: float, lat_j: float) -> void:
	var w := RoadBuilder.LINE_WIDTH / 2.0
	var pi := track.samples[i] + track.ups[i] * RoadBuilder.LINE_UP
	var pj := track.samples[j] + track.ups[j] * RoadBuilder.LINE_UP
	var li := track.lefts[i]
	var lj := track.lefts[j]
	b.quad([pi + li * (lat_i + w), pi + li * (lat_i - w), pj + lj * (lat_j - w), pj + lj * (lat_j + w)],
		[Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
