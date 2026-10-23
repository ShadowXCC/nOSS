class_name PoliceBrain
extends RefCounted
## A police unit close to its target (D192): what it does with the target within
## PoliceTuning.CLOSE_M, worked out from where the two cars are and how they're going, so it can be
## tested on its own. Both PoliceAI (highways) and EndlessPoliceAI hand over to it up close.
##
## Its role (PoliceTuning.roles) says how:
## - tail: sits a few car lengths behind at the target's speed, no contact;
## - ram: aims at the target's rear quarter on its `side`, a little faster, and past it slows to
##   box the target in;
## - pit: lines its nose up with the target's rear wheels on its `side` (ALIGN), turns in to knock
##   the tail round (TURN), then drops back (BACK_OFF) and lines up again;
## - block: gets ahead of the target in its path and slows, never below BLOCK_FLOOR of the target's
##   speed.

enum Pit { ALIGN, TURN, BACK_OFF }

const TAIL_GAP_M := 9.0
## PIT: lined up when its nose is within this along the target's rear axle and this far off its
## side, going within this of its speed; it turns in this long, then backs off this long.
const PIT_ALONG_M := 1.2
const PIT_GAP_M := 1.4
const PIT_MATCH_MPS := 3.0
const PIT_TURN_S := 0.7
const PIT_STEER := 0.55
const PIT_BACK_S := 2.0
## Block: this far ahead of the target, passing it this far to one side, this much faster; and
## never slower than this share of its speed.
const BLOCK_AHEAD_M := 14.0
const BLOCK_PASS_SIDE_M := 3.2
const BLOCK_PASS_MPS := 9.0
const BLOCK_SLOW_MPS := 4.0
const BLOCK_FLOOR := 0.4

## Which side it comes at the target from (+1 left, -1 right).
var side := 1.0
## The heat level it drives to, and its role (PoliceTuning.roles).
var level := 1
var role := "ram"
var pit := Pit.ALIGN
## The speed it wanted last tick (m/s; checks).
var last_want := 0.0
var _pit_t := 0.0


## This tick's controls for unit `v` on target `tv`: {steer, throttle, brake, handbrake}.
func controls(v: Vehicle, tv: Vehicle, delta: float) -> Dictionary:
	return decide(state_of(v), state_of(tv), delta)


## What the brain needs of a car: {pos, fwd (flat, unit), vel, speed, half (half length, half width)}.
static func state_of(v: Vehicle) -> Dictionary:
	var e := v.fitted.envelope if v.fitted else AABB(Vector3(-0.9, 0, -2.2), Vector3(1.8, 1.4, 4.4))
	return {
		"pos": v.global_position, "fwd": Vector3(v.global_basis.z.x, 0.0, v.global_basis.z.z).normalized(),
		"vel": v.remote_velocity if v.remote else v.linear_velocity, "speed": absf(v.speed()),
		"half": Vector2(e.size.z / 2.0, e.size.x / 2.0),
	}


## The controls for a unit in state `me` on a target in state `them` (state_of).
func decide(me: Dictionary, them: Dictionary, delta: float) -> Dictionary:
	var t := PoliceTuning.at(level)
	var tf: Vector3 = them.fwd
	var right := Vector3(-tf.z, 0.0, tf.x)
	var rel: Vector3 = me.pos - them.pos
	var along := rel.dot(tf) # + ahead of the target
	var across := rel.dot(-right) # + to its left
	var ts: float = them.speed
	var lead: Vector3 = them.vel * float(t.lead_s)
	var aim: Vector3
	var want := ts
	var steer_bias := 0.0
	match role:
		"tail":
			aim = them.pos - tf * TAIL_GAP_M + lead
			var gap := -along - TAIL_GAP_M
			want = ts + clampf(gap * 0.5, -6.0, 6.0)
		"block":
			var half_len: float = them.half.x + me.half.x
			if along < half_len + 2.0:
				# Not ahead yet: by on its side, quicker.
				aim = them.pos + tf * (along + 12.0) - right * side * BLOCK_PASS_SIDE_M
				want = ts + BLOCK_PASS_MPS
			else:
				aim = them.pos + tf * BLOCK_AHEAD_M + lead
				want = ts - BLOCK_SLOW_MPS if along < BLOCK_AHEAD_M + 6.0 else ts
			want = maxf(want, ts * BLOCK_FLOOR)
		"pit":
			var r := _pit(me, them, along, across, delta)
			aim = r.aim
			want = r.want
			steer_bias = r.steer
		_: # ram
			aim = them.pos - tf * PoliceTuning.AIM_BACK_M - right * side * PoliceTuning.AIM_SIDE_M + lead
			var fwd: Vector3 = me.fwd
			var ahead: float = (them.pos - me.pos).dot(fwd)
			want = ts + (PoliceTuning.RAM_MPS if ahead > 0.0 else -PoliceTuning.RAM_MPS * 2.0)
	last_want = want
	var to: Vector3 = aim - me.pos
	var mf: Vector3 = me.fwd
	var ml := Vector3(mf.z, 0.0, -mf.x) # its left
	var angle := atan2(-to.dot(ml), maxf(to.dot(mf), 0.5)) # + to its right, as the steer input
	var speed: float = me.speed
	return {
		"steer": clampf(angle * float(t.steer_gain) + steer_bias, -1.0, 1.0),
		"throttle": clampf((want - speed) * 0.3, 0.0, 1.0),
		"brake": clampf((speed - want) * 0.25, 0.0, 1.0),
		"handbrake": 0.0,
	}


## How fast a unit drives the road after its target going `ts` m/s, `dist` m off (D201): the
## level's closing speed over the target's, easing in to RAM_MPS over it by CLOSE_M (braking at
## `braking` m/s^2); at a level with a cap, within `limit` to max_factor times it. A unit that
## waited ahead and pulled out keeps to LAUNCH_SHARE of the target's speed until they meet
## (`waiting_for`).
static func chase_speed(level: int, ts: float, dist: float, limit: float, braking: float, waiting_for := false) -> float:
	if waiting_for:
		return maxf(ts * PoliceTuning.LAUNCH_SHARE, PoliceTuning.AHEAD_CRAWL_MPS)
	var t := PoliceTuning.at(level)
	var want := ts + float(t.closing_mps)
	if float(t.max_factor) > 0.0:
		want = clampf(want, limit, limit * float(t.max_factor))
	var ease := ts + PoliceTuning.RAM_MPS + sqrt(2.0 * braking * PoliceTuning.EASE_IN * maxf(dist - PoliceTuning.CLOSE_M, 0.0))
	return minf(want, ease)


## A unit that waited ahead, up close to its target (`me`, `them`: state_of; D201): it blocks
## while it's ahead of them; once they're clearly past it (`passed` already, or now), the level's
## lead role (ram at 2-3, pit at 4-5) for good, from the side it's on. [role, passed, side].
static func ahead_role(me: Dictionary, them: Dictionary, level: int, passed: bool, side: float) -> Array:
	if not passed:
		var tf: Vector3 = them.fwd
		var rel: Vector3 = me.pos - them.pos
		var me_half: Vector2 = me.half
		var them_half: Vector2 = them.half
		if rel.dot(tf) < -(me_half.x + them_half.x + 2.0):
			passed = true
			side = 1.0 if rel.dot(Vector3(tf.z, 0.0, -tf.x)) >= 0.0 else -1.0
	return [PoliceTuning.role(level, 0) if passed else "block", passed, side]


## The PIT: {aim, want, steer (added)}. Its nose by the target's rear wheels on `side`, then a turn
## into the target, then back off.
func _pit(me: Dictionary, them: Dictionary, along: float, across: float, delta: float) -> Dictionary:
	var tf: Vector3 = them.fwd
	var right := Vector3(-tf.z, 0.0, tf.x)
	var ts: float = them.speed
	var me_half: Vector2 = me.half
	var them_half: Vector2 = them.half
	# Lined up: its front axle by the target's rear one, alongside.
	var nose := -them_half.x * 0.6 - me_half.x * 0.6
	var beside := them_half.y + me_half.y + 0.3
	_pit_t += delta
	match pit:
		Pit.ALIGN:
			var lined := absf(along - nose) < PIT_ALONG_M and absf(absf(across) - beside) < PIT_GAP_M and signf(across) == side \
				and absf(float(me.speed) - ts) < PIT_MATCH_MPS
			if lined:
				pit = Pit.TURN
				_pit_t = 0.0
			var spot: Vector3 = them.pos + tf * nose - right * side * beside + them.vel * 0.2
			return { "aim": spot + tf * 6.0, "want": ts + clampf((nose - along) * 0.8, -4.0, 4.0), "steer": 0.0 }
		Pit.TURN:
			if _pit_t > PIT_TURN_S:
				pit = Pit.BACK_OFF
				_pit_t = 0.0
			# Into the target's side: + side means it's on the left, so it steers right (+).
			return { "aim": them.pos - tf * them_half.x, "want": ts + 1.5, "steer": side * PIT_STEER }
		_:
			if _pit_t > PIT_BACK_S:
				pit = Pit.ALIGN
				_pit_t = 0.0
			return { "aim": them.pos - tf * (TAIL_GAP_M + 4.0) - right * side * beside, "want": ts - 3.0, "steer": 0.0 }
