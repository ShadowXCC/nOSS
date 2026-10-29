class_name DraftControl
extends Node
## Drafting in Track sessions (D208), when the event has it on: 30 times a second each car this
## game drives, on a platform with a slipstream, has its drag cut by how far it's tucked in behind
## another car (Slipstream.tow), and a little more while one is tucked in behind it (the lead
## cut). In a pack (D228, the event's pack racing) a line of cars goes faster the longer it is
## (each car `line_cut` more for every car past two, up to `line_max`), and a car alongside at
## the rear quarter takes air off a car's side (`side_cut` more drag). The tuning is the Track
## mode's `draft`. Each game drafts its own cars online: nothing goes on the wire.

const HZ := 30.0
const DEFAULTS := { "range_m": 40.0, "half_width_m": 1.2, "drag_cut": 0.3, "lead_range_m": 10.0, "lead_cut": 0.04, "min_speed": 20.0,
	"line_cut": 0.03, "line_max": 4, "link_tow": 0.25, "side_cut": 0.05, "side_gap_m": 1.0 }
## The most a car's drag can be cut.
const MAX_CUT := 0.9

var session: TrackSession
var tuning: Dictionary = DEFAULTS.duplicate()
## Pack racing (D228): line and side drafting on.
var pack := false
## Racer -> the drag scale it runs at now (1: no draft).
var scale := {}
## Racer -> how many cars its line has (pack racing only).
var lines := {}
var _time := 0.0


## The Track mode's drafting tuning, every key filled in.
static func tuning_for(mode: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	out.merge(mode.get("draft", {}), true)
	return out


## The lowest drag scale a car can draft to with `tuning`; with `pack`, in the longest line a pack
## makes (D228).
static func lowest_scale(tuning_: Dictionary, pack := false) -> float:
	var line := float(tuning_.line_cut) * int(tuning_.line_max) if pack else 0.0
	return 1.0 - minf(float(tuning_.drag_cut) + float(tuning_.lead_cut) + line, MAX_CUT)


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
	# Every car's tow, remote ones too: they make up the lines.
	var tows := {}
	for r in session.racers:
		if r.vehicle and not r.waiting and drafts(r.vehicle.platform):
			tows[r] = Slipstream.tow_from(r, session.racers, reach, half, min_speed)
	if pack:
		lines = Slipstream.line_sizes(tows, float(tuning.link_tow))
	for r: Racer in tows:
		var v := r.vehicle
		if v.remote:
			continue
		var cut := float(tuning.drag_cut) * float(tows[r][0])
		cut += float(tuning.lead_cut) * Slipstream.pushed(r, session.racers, float(tuning.lead_range_m), half, min_speed)
		if pack:
			cut += float(tuning.line_cut) * clampi(int(lines.get(r, 1)) - 2, 0, int(tuning.line_max))
			cut -= float(tuning.side_cut) * Slipstream.side(r, session.racers, float(tuning.side_gap_m), min_speed)
		var s := 1.0 - minf(cut, MAX_CUT)
		scale[r] = s
		v.sim.set_drag_scale(s)


## Racer `r`'s drag scale now (1 without a draft).
func scale_of(r: Racer) -> float:
	return float(scale.get(r, 1.0))
