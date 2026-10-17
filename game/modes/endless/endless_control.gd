class_name EndlessControl
extends Node
## An endless drive's rules (docs/GAMEMODES.md §4, MODE-06, D157), beside an ordinary free session:
## where players start (one behind another in the right-hand lane), resets (back in the lane where
## they were, ghosted for a moment), keeping local players on one stretch of road (the session's
## rule: bring the one behind up, or hold the leader back), the minimal HUD (hidden until shown),
## each biome's weather and sounds, its name as you enter it, and the pause menu's items.

## Players start this far along the road (the road behind needs room).
const START_M := 1500.0
const SPACING_M := 18.0
## Local players this far apart: a warning; this far: brought together.
const SPREAD_WARN_M := 2500.0
const SPREAD_MAX_M := 3000.0
## Brought up or held back to this far from the others.
const REGROUP_M := 60.0
const GHOST_S := 3.0
const CHECK_S := 1.0
## HUD elements an endless drive never shows (no laps, places or flags).
const NEVER := ["timing", "delta", "position", "standings", "flags"]

var session: TrackSession
var world: EndlessWorld
var event: RaceEvent
## Players who chose to show the HUD (by slot index).
var hud_shown := {}
var _check := 0.0
var _biome := -1
var _warned := {}


func _ready() -> void:
	name = "EndlessControl"
	process_physics_priority = -56


## Player `i`'s start: in single file, in the right-hand lane.
func spawn_for(i: int) -> Transform3D:
	return lane_transform(START_M - SPACING_M * i)


## A car's spot in the right-hand lane at `distance`, facing along the road.
func lane_transform(distance: float) -> Transform3D:
	var road := world.road
	var d := clampf(distance, road.offset_m + 10.0, road.end_m() - 10.0)
	var lane := road.half_width(d, 1.0) - RoadWindow.SHOULDER_M
	return road.transform_at(d, -lane / 2.0)


## Back in the lane where it was (its last good spot), at rest, ghosted for a moment.
func reset(r: Racer) -> void:
	if r.vehicle == null:
		return
	var at := lane_transform(r.last_valid)
	r.vehicle.reset_to(at)
	r.distance = r.last_valid
	r.track_index = -1
	r.ghost_for(GHOST_S)


func _physics_process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = CHECK_S
	_keep_together()
	_biome_here()
	if Game.dev.has("endless-debug") and not session.players.is_empty() and session.players[0].vehicle:
		var p: SessionPlayer = session.players[0]
		print("endless: d %.1f lat %.2f idx %d car %s road %s speed %.1f window %.0f..%.0f %s origin %.0f,%.0f" % [p.distance, p.lateral, p.track_index,
			p.vehicle.global_position, world.road.point_at(p.distance), p.speed, world.road.offset_m, world.road.end_m(), world.counts(), session.origin.x, session.origin.z])
		if session.endless_traffic:
			print("traffic: %d scheduled, %d physics, %d gone" % [session.endless_traffic.scheduled().size(), session.endless_traffic.cars.size(), session.endless_traffic.gone.size()])


## Local players on one stretch of road (floating origin, one world): when they drift too far apart
## the one behind comes up, or the leader goes back (the event's rule).
func _keep_together() -> void:
	var mine: Array[SessionPlayer] = []
	for p in session.players:
		if p.vehicle and not p.waiting:
			mine.append(p)
	if mine.size() < 2:
		return
	mine.sort_custom(func(a: Racer, b: Racer) -> bool: return a.distance < b.distance)
	var last: SessionPlayer = mine[0]
	var lead: SessionPlayer = mine[-1]
	var apart := lead.distance - last.distance
	var mover := lead if event.spread == "hold" else last
	if apart > SPREAD_WARN_M and not _warned.get(mover, false):
		_warned[mover] = true
		mover.notify("Wait for the group" if event.spread == "hold" else "Catching up", 3.0)
	if apart <= SPREAD_WARN_M:
		_warned.clear()
	if apart > SPREAD_MAX_M:
		var to := last.distance + REGROUP_M if mover == lead else lead.distance - REGROUP_M
		mover.vehicle.reset_to(lane_transform(to))
		mover.distance = to
		mover.last_valid = to
		mover.track_index = -1
		mover.ghost_for(GHOST_S)
		_warned.erase(mover)


## The biome under P1 (or the first player): its weather and sounds, and its name when it changes.
func _biome_here() -> void:
	if session.players.is_empty() or session.players[0].vehicle == null:
		return
	var p: SessionPlayer = session.players[0]
	var road := world.road
	var i := road.index_of(p.distance)
	if i < 0:
		return
	var b := int(road.biome2[i]) if road.blend[i] >= 0.5 else int(road.biome[i])
	var data := EndlessBiomes.of(b)
	if b != _biome:
		if _biome >= 0:
			for sp in session.players:
				sp.notify(String(data.get("name", "")), 2.5)
		_biome = b
		session.env.biome_weather = data.get("weather", {})
	if session.env.ambience:
		var amb: Dictionary = data.get("ambience", {})
		var night := session.env.night
		session.env.extra_ambience = {
			"birds": float(amb.get("birds", 0.0)) * (1.0 - night) * (1.0 - float(session.env.snapshot.get("precip", 0.0))),
			"crickets": float(amb.get("crickets", 0.0)) * night,
			"surf": float(amb.get("surf", 0.0)),
		}


## The minimal HUD (D157): hidden until the player shows it; laps and places never.
func apply_hud(p: SessionPlayer) -> void:
	var hidden := PackedStringArray(NEVER)
	if not hud_shown.get(p.slot.index, false):
		hidden.append_array(["speed", "assists", "car"])
	p.hud.session_hidden = hidden
	p.hud.apply_profile(p.slot.profile)


## The pause menu's items for player `p`: [text, callable, description].
func pause_items(p: SessionPlayer) -> Array:
	var items: Array = []
	var auto := bool(p.slot.profile.data.get("assists", {}).get("autodrive", false))
	items.append(["Autodrive: " + ("On" if auto else "Off"), p.toggle_autodrive, "The car drives itself (O)"])
	var shown := bool(hud_shown.get(p.slot.index, false))
	items.append(["Hide HUD" if shown else "Show HUD", func() -> void:
		hud_shown[p.slot.index] = not shown
		apply_hud(p), "Speed and gear on screen"])
	var code := EndlessCode.encode(event.road_seed, event.biome)
	items.append(["Road code: " + code, func() -> void:
		DisplayServer.clipboard_set(code)
		p.notify("Code copied", 2.0), "Copies it, to share this road"])
	if not session.is_online():
		items.append(["New road", func() -> void:
			var e := RaceEvent.from_dict(event.to_dict())
			e.road_seed = EndlessCode.random_seed()
			Game.start_event(e, session.platform_id, ""), "A road from a new seed"])
	return items

