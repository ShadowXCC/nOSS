class_name PoliceTuning
extends RefCounted
## How hard the police come by heat level (D192), shared by every road they work: how many units
## chase a player and what each does up close, how fast they close and how far over the limit
## they'll go, when spike strips and roadblocks come, how they steer, and how far they see.

## Per level 1-5: units after the player; each one's role up close, by its place among them
## (PoliceBrain: "tail" keeps off, "ram" hits the rear quarter, "pit" spins the target, "block"
## gets ahead and slows); closing speed over the target's (m/s) and the most times the limit;
## spike strips (s between, 0: none); roadblocks; steering gain and lead (s); sight (m).
const LEVELS := [
	{ "units": 1, "roles": ["tail"], "closing_mps": 10.0, "max_factor": 1.6, "spikes_s": 0.0, "roadblock": false,
		"steer_gain": 1.8, "lead_s": 0.25, "sight_m": 250.0 },
	{ "units": 2, "roles": ["ram", "block"], "closing_mps": 13.0, "max_factor": 1.9, "spikes_s": 0.0, "roadblock": false,
		"steer_gain": 2.0, "lead_s": 0.3, "sight_m": 275.0 },
	{ "units": 3, "roles": ["ram", "ram", "block"], "closing_mps": 16.0, "max_factor": 2.2, "spikes_s": 45.0, "roadblock": false,
		"steer_gain": 2.2, "lead_s": 0.35, "sight_m": 300.0 },
	{ "units": 4, "roles": ["pit", "pit", "block", "tail"], "closing_mps": 19.0, "max_factor": 2.5, "spikes_s": 35.0, "roadblock": true,
		"steer_gain": 2.4, "lead_s": 0.4, "sight_m": 325.0 },
	{ "units": 5, "roles": ["pit", "pit", "block", "tail", "tail"], "closing_mps": 22.0, "max_factor": 2.8, "spikes_s": 25.0, "roadblock": true,
		"steer_gain": 2.6, "lead_s": 0.45, "sight_m": 350.0 },
]
## Near the target: this much faster than it while behind (m/s), and where a ram aims: this far
## behind its centre, this far to one side (its rear quarter).
const RAM_MPS := 4.0
const AIM_BACK_M := 2.0
const AIM_SIDE_M := 0.8
## Within this of the target a unit works close in (PoliceBrain); further off it drives the road.
const CLOSE_M := 35.0


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
