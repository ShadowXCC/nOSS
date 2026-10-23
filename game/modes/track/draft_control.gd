class_name DraftControl
extends Node
## Drafting in Track sessions (D208), when the event has it on: 30 times a second each car this
## game drives, on a platform with a slipstream, has its drag cut by how far it's tucked in behind
## another car (Slipstream.tow), and a little more while one is tucked in behind it (the lead
## cut). The tuning is the Track mode's `draft`. Each game drafts its own cars online: nothing
## goes on the wire.

const HZ := 30.0
const DEFAULTS := { "range_m": 40.0, "half_width_m": 1.2, "drag_cut": 0.3, "lead_range_m": 10.0, "lead_cut": 0.04, "min_speed": 20.0 }
## The most a car's drag can be cut.
const MAX_CUT := 0.9

var session: TrackSession
var tuning: Dictionary = DEFAULTS.duplicate()
## Racer -> the drag scale it runs at now (1: no draft).
var scale := {}
var _time := 0.0


## The Track mode's drafting tuning, every key filled in.
static func tuning_for(mode: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	out.merge(mode.get("draft", {}), true)
	return out


## The lowest drag scale a car can draft to with `tuning`.
static func lowest_scale(tuning_: Dictionary) -> float:
	return 1.0 - minf(float(tuning_.drag_cut) + float(tuning_.lead_cut), MAX_CUT)


## True if `platform` makes and feels a slipstream.
static func drafts(platform: Dictionary) -> bool:
	return bool(platform.get("aero", {}).get("slipstream", false))


func _ready() -> void:
	name = "DraftControl"
	process_physics_priority = -57 # after the race field, before the drivers (-50)


func _physics_process(delta: float) -> void:
	_time += delta
	if _time < 1.0 / HZ:
		return
	_time = 0.0
	var reach := float(tuning.range_m)
	var half := float(tuning.half_width_m)
	var min_speed := float(tuning.min_speed)
	for r in session.racers:
		var v := r.vehicle
		if v == null or v.remote or r.waiting or not drafts(v.platform):
			continue
		var cut := float(tuning.drag_cut) * Slipstream.tow(r, session.racers, reach, half, min_speed)
		cut += float(tuning.lead_cut) * Slipstream.pushed(r, session.racers, float(tuning.lead_range_m), half, min_speed)
		var s := 1.0 - minf(cut, MAX_CUT)
		scale[r] = s
		v.sim.set_drag_scale(s)


## Racer `r`'s drag scale now (1 without a draft).
func scale_of(r: Racer) -> float:
	return float(scale.get(r, 1.0))
