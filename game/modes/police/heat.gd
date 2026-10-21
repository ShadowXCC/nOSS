class_name Heat
extends RefCounted
## A player's heat with the police (docs/GAMEMODES.md §3, D115), on its own so it can be tested
## exactly. Only what a unit sees counts (within SEEN_M, in line of sight): speeding by
## SPEEDING_KMH or more (+1 every SPEEDING_EVERY_S), a near miss (+1), a close miss (+2), a crash
## (+3), ramming the police (+5); a speed camera's snap speeding (+2, the endless road, D194). Levels start at LEVELS points (1 to 5); a level brings that many
## units, and roadblocks from ROADBLOCK_LEVEL. Unseen, with every unit over EVADE_M away, for
## EVADE_S + EVADE_PER_LEVEL_S × level: evaded, and the heat is gone. Slower than BUST_KMH with a
## unit touching or within BUST_M for BUST_S: busted (the heat goes too; the session takes the
## unbanked score and puts the car back).

const SEEN_M := 250.0
const SPEEDING_KMH := 20.0
const SPEEDING_EVERY_S := 2.0
const POINTS := { "speeding": 1, "near": 1, "close": 2, "crash": 3, "ram": 5, "camera": 2 }
const LEVELS := [1, 6, 15, 30, 50]
const ROADBLOCK_LEVEL := 4
const EVADE_M := 300.0
const EVADE_S := 8.0
const EVADE_PER_LEVEL_S := 4.0
const BUST_KMH := 10.0
const BUST_M := 0.6
const BUST_S := 3.0

var points := 0
## What happened, for the HUD and narration: [{kind, text}], taken by whoever shows it.
var news: Array = []
var _speeding := 0.0
var _hidden := 0.0
var _bust := 0.0


## 0 (none) to 5.
func level() -> int:
	var out := 0
	for i in LEVELS.size():
		if points >= LEVELS[i]:
			out = i + 1
	return out


## Something a unit saw (`kind`: near, close, crash, ram).
func seen(kind: String) -> void:
	_add(int(POINTS.get(kind, 0)))


## Seen going `over_kmh` over the limit for `dt`.
func seen_speeding(over_kmh: float, dt: float) -> void:
	if over_kmh < SPEEDING_KMH:
		_speeding = 0.0
		return
	_speeding += dt
	if _speeding >= SPEEDING_EVERY_S:
		_speeding -= SPEEDING_EVERY_S
		_add(POINTS.speeding)


## A tick of the chase: whether a unit sees the player, the nearest unit's distance (m), the
## player's speed and whether a unit is touching (or within BUST_M). Returns "busted", "evaded"
## or "".
func update(dt: float, is_seen: bool, nearest_m: float, speed_kmh: float, unit_close: bool) -> String:
	if level() == 0:
		_hidden = 0.0
		_bust = 0.0
		return ""
	_bust = _bust + dt if speed_kmh < BUST_KMH and unit_close else 0.0
	if _bust >= BUST_S:
		_clear()
		news.append({ "kind": "busted", "text": "Busted" })
		return "busted"
	_hidden = _hidden + dt if not is_seen and nearest_m > EVADE_M else 0.0
	if _hidden >= evade_s():
		_clear()
		news.append({ "kind": "evaded", "text": "Evaded" })
		return "evaded"
	return ""


## How long the police must be shaken off at this level.
func evade_s() -> float:
	return EVADE_S + EVADE_PER_LEVEL_S * level()


## How far into shaking them off (0..1), for the HUD.
func evading() -> float:
	return clampf(_hidden / evade_s(), 0.0, 1.0) if level() > 0 else 0.0


func _add(n: int) -> void:
	var before := level()
	points += n
	if level() > before:
		news.append({ "kind": "heat", "text": "Heat %d" % level() })


func _clear() -> void:
	points = 0
	_speeding = 0.0
	_hidden = 0.0
	_bust = 0.0
