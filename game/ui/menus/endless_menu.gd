class_name EndlessMenu
extends RefCounted
## Endless's choices and its last setup, kept for the Host menu until hosting moves to the event
## pages (UI overhaul P8). Local Drive's Endless is a Settings page (EventForms.endless()).

const TRAFFIC := EventForms.ENDLESS_TRAFFIC
const SPREAD := EventForms.SPREAD
const LANES := EventForms.LANES
const SIDES := EventForms.SIDES


## The last endless drive set up (the old menu's memory), or a new road in the forest.
static func last() -> RaceEvent:
	var d: Variant = Settings.profile.get("last_endless")
	if d is Dictionary and not d.is_empty():
		var e := RaceEvent.from_dict(d)
		e.kind = "endless"
		return e
	return RaceEvent.endless(EndlessCode.random_seed(), EndlessBiomes.index_of("forest"))
