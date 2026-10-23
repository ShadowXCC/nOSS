class_name PoliceTuning
extends RefCounted
## How hard the police come by heat level (D192, D201), shared by every road they work: how many
## units chase a player and what each does up close, how many wait ahead, how fast they close,
## how hard they take bends, when spike strips and roadblocks come, how they steer, and how far
## they see.

## Per level 1-5: units after the player; each one's role up close, by its place among them
## (PoliceBrain: "tail" keeps off, "ram" hits the rear quarter, "pit" spins the target, "block"
## gets ahead and slows); units waiting ahead, on top (PoliceControl); closing speed over the
## target's (m/s) and the most times the limit (0: no cap, as fast as bends and the car allow);
## the share of the tyres' grip used in bends and braking; spike strips (s between, 0: none);
## roadblocks; steering gain and lead (s); sight (m).
const LEVELS := [
	{ "units": 1, "roles": ["tail"], "ahead": 0, "closing_mps": 10.0, "max_factor": 1.6, "grip": 0.5, "spikes_s": 0.0,
		"roadblock": false, "steer_gain": 1.8, "lead_s": 0.25, "sight_m": 250.0 },
	{ "units": 2, "roles": ["ram", "block"], "ahead": 1, "closing_mps": 13.0, "max_factor": 0.0, "grip": 0.65, "spikes_s": 0.0,
		"roadblock": false, "steer_gain": 2.0, "lead_s": 0.3, "sight_m": 275.0 },
	{ "units": 3, "roles": ["ram", "ram", "block"], "ahead": 1, "closing_mps": 16.0, "max_factor": 0.0, "grip": 0.72, "spikes_s": 45.0,
		"roadblock": false, "steer_gain": 2.2, "lead_s": 0.35, "sight_m": 300.0 },
	{ "units": 4, "roles": ["pit", "pit", "block", "tail"], "ahead": 2, "closing_mps": 19.0, "max_factor": 0.0, "grip": 0.8, "spikes_s": 35.0,
		"roadblock": true, "steer_gain": 2.4, "lead_s": 0.4, "sight_m": 325.0 },
	{ "units": 5, "roles": ["pit", "pit", "block", "tail", "tail"], "ahead": 2, "closing_mps": 22.0, "max_factor": 0.0, "grip": 0.88,
		"spikes_s": 25.0, "roadblock": true, "steer_gain": 2.6, "lead_s": 0.45, "sight_m": 350.0 },
]
## Near the target: this much faster than it while behind (m/s), and where a ram aims: this far
## behind its centre, this far to one side (its rear quarter).
const RAM_MPS := 4.0
const AIM_BACK_M := 2.0
const AIM_SIDE_M := 0.8
## Within this of the target a unit works close in (PoliceBrain); further off it drives the road.
const CLOSE_M := 35.0
## A unit waiting ahead that's pulled out keeps to this share of its target's speed until they
## meet, at least this (m/s).
const LAUNCH_SHARE := 0.75
const AHEAD_CRAWL_MPS := 10.0
## Closing in, a unit plans to be down to RAM_MPS over the target's speed by CLOSE_M, braking at
## this share of what it brakes with.
const EASE_IN := 0.5
## Grip the tyres have when a platform doesn't say.
const MU_DEFAULT := 1.2


## Level `level`'s numbers (0 counts as 1, over 5 as 5).
static func at(level: int) -> Dictionary:
	return LEVELS[clampi(level, 1, LEVELS.size()) - 1]


## The role of the `i`th unit (0: the first sent) at `level`.
static func role(level: int, i: int) -> String:
	var roles: Array = at(level).roles
	return String(roles[i]) if i < roles.size() else "tail"


## Whether a role touches the target.
static func contact(r: String) -> bool:
	return r in ["ram", "pit"]


## The sideways and braking acceleration a unit plans with at `level` in car `v` on a dry road
## (m/s^2): the level's share of its tyres' grip.
static func grip_mps2(level: int, v: Vehicle) -> float:
	var mu := float(v.platform.get("tires", {}).get("mu_peak", MU_DEFAULT)) if v and v.platform else MU_DEFAULT
	return float(at(level).grip) * mu * 9.81
