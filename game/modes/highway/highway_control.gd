class_name HighwayControl
extends Node
## A highway session's rules (docs/GAMEMODES.md §3, D113): where players start and reset (on the
## outer shoulder of their carriageway, at rest; traffic never uses the shoulder), changing
## direction, and the sub-mode (cruise; score attack, loop laps and runs build on this).

## Players start this far behind the lap line, this far apart.
const START_BACK_M := 40.0
const START_GAP_M := 30.0

var session: TrackSession
var layout: HighwayLayout
var event: RaceEvent


func _ready() -> void:
	process_physics_priority = -56


## Player `i`'s start: on the shoulder of direction `dir`'s carriageway behind the lap line.
func spawn_for(i: int, dir: int) -> Transform3D:
	var d := layout.main.start_m - dir * (START_BACK_M + i * START_GAP_M)
	return shoulder_spot(dir, fposmod(d, layout.main.length))


## On direction `dir`'s outer shoulder at main-road distance `d`, facing the way it drives.
func shoulder_spot(dir: int, d: float) -> Transform3D:
	var shoulder := float(layout.settings.shoulder_out_m)
	var lat := -dir * (layout.inner + layout.lanes * layout.lane_m + shoulder / 2.0)
	var k := layout.main.index_at(d)
	# Not in a ramp's mouth (the shoulder is part of the taper there): a little further on.
	for step in 40:
		if not layout.gap(k, -float(dir)):
			break
		d = fposmod(d + dir * 10.0, layout.main.length)
		k = layout.main.index_at(d)
	var t := layout.main.transform_at(d, lat)
	if dir < 0:
		t.basis = Basis(-t.basis.x, t.basis.y, -t.basis.z)
	return t


## A reset (the player's, or after falling off): at rest on the shoulder of the carriageway it
## was on, beside where it was.
func reset(r: Racer) -> void:
	_place(r, r.direction)
	r.notify("Reset", 1.5)


## Back on the other carriageway, going the other way.
func change_direction(r: Racer) -> void:
	_place(r, -r.direction)
	r.notify("Turned round", 1.5)


func _place(r: Racer, dir: int) -> void:
	if r.vehicle == null:
		return
	r.timer.invalidate("Reset")
	r.direction = dir
	var at := shoulder_spot(dir, r.distance)
	r.vehicle.reset_to(at)
	var proj := layout.main.project(at.origin)
	r.distance = proj.distance
	r.lateral = proj.lateral
	r.track_index = -1
	r.timer.teleported(r.lap_pos(r.distance))


## Pause menu items for player `p`: [[text, callable, description]].
func pause_items(p: SessionPlayer) -> Array:
	return [["Change direction", func() -> void: change_direction(p), "Turn round onto the other carriageway"]]
