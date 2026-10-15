class_name Plausibility
extends RefCounted
## The server's checks on a remote car's states (docs/NETWORKING.md §8, D87). nOSS is open source,
## so a determined cheater can change their game; these make cheating hard and visible:
## - speed above the platform's top speed (power against drag) plus a margin
## - acceleration no car could do, away from contacts, knocks and resets (along the ground: landing
##   off a crest or a kerb's knock is up and down, a speed cheat isn't; a car its game says was
##   knocked may lose speed suddenly, not gain it)
## - moving further between two states than its speed allows (a teleport not marked as a reset)
## - a reset that jumps ahead along the track
## - states stamped far from the server's clock
## - a lap faster than the racing line's ideal for the platform
## A car gets strikes; STRIKES within WINDOW_S trigger the server's response (warn, flag, kick).

const STRIKES := 3
const WINDOW_S := 10.0
const SPEED_MARGIN := 1.15
const SPEED_EXTRA := 8.0 # m/s: slipstream, downhill
const MAX_ACCEL := 45.0 # m/s²: well beyond any grip, short of a crash's spike
const ACCEL_GRACE_S := 0.5 # after a contact or reset
const KNOCK_GAIN := 2.0 # m/s: what a knocked car may gain and still count as knocked
const JUMP_SLACK_M := 6.0
const RESET_AHEAD_M := 40.0
const CLOCK_AHEAD_S := 0.5
const CLOCK_BEHIND_S := 5.0
const LAP_FLOOR := 0.97
const AIR_DENSITY := 1.225

## The fastest the platform's car can go on the flat, m/s.
var top_speed := 100.0
## The racing line's ideal lap for the platform here, s (0: unknown).
var ideal_lap := 0.0
var _last: CarState
var _strikes: Array[Dictionary] = [] # {time, reason}
var _grace_until := 0.0


static func for_platform(platform: Dictionary, track: TrackData) -> Plausibility:
	var p := Plausibility.new()
	var power := GameModes.peak_power_kw(platform) * 1000.0
	var cd_a := maxf(float(platform.get("aero", {}).get("cd_a", 0.8)), 0.05)
	p.top_speed = pow(2.0 * power / (AIR_DENSITY * cd_a), 1.0 / 3.0)
	if track and track.arena == null: # an arena has no laps
		var line := RacingLine.for_track(track)
		p.ideal_lap = line.lap_time(line.speed_profile(platform, 1.0))
	return p


## A new state from the car's game, received at server time `now`; `track` places resets.
## Returns the reasons found (empty if fine).
func check(s: CarState, now: float, track: TrackData, contact := false) -> PackedStringArray:
	var out := PackedStringArray()
	if s.time - now > CLOCK_AHEAD_S or now - s.time > CLOCK_BEHIND_S:
		out.append("clock")
	if s.velocity.length() > top_speed * SPEED_MARGIN + SPEED_EXTRA:
		out.append("speed")
	if contact:
		_grace_until = now + ACCEL_GRACE_S
	var placed := s.flags & CarState.FLAG_TELEPORT != 0
	if placed:
		_grace_until = now + ACCEL_GRACE_S
		if _last and track and _ahead(track, _last.xform.origin, s.xform.origin) > RESET_AHEAD_M:
			out.append("reset ahead")
	elif _last and s.time > _last.time:
		var dt := s.time - _last.time
		if s.flags & CarState.FLAG_KNOCK and s.velocity.length() <= _last.velocity.length() + KNOCK_GAIN:
			_grace_until = now + ACCEL_GRACE_S # a knock stops a car hard; it never speeds one up much
		var moved := _last.xform.origin.distance_to(s.xform.origin)
		var could := maxf(_last.velocity.length(), s.velocity.length()) * dt + JUMP_SLACK_M
		if moved > could and s.flags & CarState.FLAG_WAITING == 0:
			out.append("teleport")
		var dv := s.velocity - _last.velocity
		if dt > 0.01 and now >= _grace_until and Vector2(dv.x, dv.z).length() / dt > MAX_ACCEL:
			out.append("acceleration")
	_last = s
	return out


## A lap of `seconds` was timed for the car: too fast to be true?
func check_lap(seconds: float) -> bool:
	return ideal_lap > 0.0 and seconds > 0.0 and seconds < ideal_lap * LAP_FLOOR


## Records `reasons` at `now`; true once the car has STRIKES within WINDOW_S.
func strike(reasons: PackedStringArray, now: float) -> bool:
	for r in reasons:
		_strikes.append({ "time": now, "reason": r })
	_strikes = _strikes.filter(func(x: Dictionary) -> bool: return now - float(x.time) <= WINDOW_S)
	return _strikes.size() >= STRIKES


func reasons() -> String:
	var seen := {}
	for x: Dictionary in _strikes:
		seen[x.reason] = true
	return ", ".join(PackedStringArray(seen.keys()))


func clear() -> void:
	_strikes.clear()


## How far `to` is ahead of `from` along the track (m; negative behind).
static func _ahead(track: TrackData, from: Vector3, to: Vector3) -> float:
	var a: float = track.project(from).distance
	var b: float = track.project(to).distance
	var d := fposmod(b - a, track.length)
	return d if d < track.length / 2.0 else d - track.length
