class_name ScoreAttack
extends RefCounted
## Score attack's rules (docs/GAMEMODES.md §3, D114), on their own so they can be tested exactly:
## near misses (a hull-to-hull gap under 1 m, passing 30 km/h faster or more) and close misses
## (under 0.5 m: double) earn points, times a step for the car's speed (none below 120 km/h);
## passing between two cars side by side earns a bonus. Each event within COMBO_S of the last
## grows the combo, which multiplies the chain's points; once COMBO_S passes with no event the
## chain banks. Any contact (traffic, police, a wall) loses what isn't banked. Going the wrong way
## pauses scoring.

const NEAR_M := 1.0
const CLOSE_M := 0.5
const MIN_RELATIVE_KMH := 30.0
const NEAR_POINTS := 100
const CLOSE_POINTS := 200
const SPLIT_POINTS := 300
## [from km/h, multiplier], fastest first; slower than the last scores nothing.
const SPEED_STEPS := [[250.0, 3.0], [200.0, 2.0], [160.0, 1.5], [120.0, 1.0]]
const COMBO_S := 5.0
## The combo multiplier: ×1 for the first event, COMBO_STEP more for each after, at most
## COMBO_MAX.
const COMBO_STEP := 0.25
const COMBO_MAX := 5.0
## A knock this hard (N·s) is contact.
const CONTACT_NS := 20.0

var banked := 0
## The chain's points so far (before the combo multiplier) and its events.
var chain := 0
var combo := 0
var last_event := -INF
## Wrong way: nothing counts.
var paused := false
## What happened, for the HUD and narration: [{kind, points, text}], taken by whoever shows it.
var news: Array = []


## The speed step at `speed_kmh` (0: too slow to score).
static func speed_multiplier(speed_kmh: float) -> float:
	for step: Array in SPEED_STEPS:
		if speed_kmh >= step[0]:
			return step[1]
	return 0.0


## The combo multiplier for `events` in a chain.
static func combo_multiplier(events: int) -> float:
	return minf(1.0 + COMBO_STEP * maxi(events - 1, 0), COMBO_MAX)


## A pass with `gap_m` between hulls at `relative_kmh`, this car at `speed_kmh`: its points (0 if
## it doesn't count).
func near_miss(gap_m: float, relative_kmh: float, speed_kmh: float, now: float) -> int:
	if gap_m >= NEAR_M or absf(relative_kmh) < MIN_RELATIVE_KMH:
		return 0
	var close := gap_m < CLOSE_M
	return _event("close" if close else "near", CLOSE_POINTS if close else NEAR_POINTS, speed_kmh, now)


## Passed between two cars side by side.
func lane_split(speed_kmh: float, now: float) -> int:
	return _event("split", SPLIT_POINTS, speed_kmh, now)


## A knock of `impulse` N·s: true if it lost the unbanked points.
func contact(impulse: float, _now: float) -> bool:
	if impulse < CONTACT_NS or (chain == 0 and combo == 0):
		return false
	var lost := unbanked()
	chain = 0
	combo = 0
	news.append({ "kind": "lost", "points": lost, "text": "Lost %d" % lost })
	return true


## Banks the chain once COMBO_S has passed without an event.
func update(now: float) -> void:
	if combo > 0 and now - last_event >= COMBO_S:
		var total := unbanked()
		banked += total
		chain = 0
		combo = 0
		news.append({ "kind": "banked", "points": total, "text": "Banked %d" % total })


## The chain's worth if it banked now.
func unbanked() -> int:
	return roundi(chain * combo_multiplier(combo))


func multiplier() -> float:
	return combo_multiplier(combo)


func _event(kind: String, base: int, speed_kmh: float, now: float) -> int:
	if paused:
		return 0
	var step := speed_multiplier(speed_kmh)
	if step <= 0.0:
		return 0
	update(now) # a chain that ran out banks before this one starts
	var points := roundi(base * step)
	chain += points
	combo += 1
	last_event = now
	var words := { "near": "Near miss", "close": "Close miss", "split": "Lane split" }
	news.append({ "kind": kind, "points": points, "text": "%s +%d" % [words[kind], points] })
	if combo > 1:
		news.append({ "kind": "combo", "points": 0, "text": "Combo ×%d" % combo })
	return points
