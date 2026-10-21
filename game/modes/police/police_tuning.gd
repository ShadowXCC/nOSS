class_name PoliceTuning
extends RefCounted
## How hard the police come by heat level (D192), shared by every road they work: how many units
## chase a player, how fast they close and how far over the limit they'll go, what contact they
## make, when they block, lay spikes and set up roadblocks, how they steer, and how far they see.

## Per level 1-5: units after the player; closing speed over the target's (m/s) and the most
## times the limit; contact ("tail": none, "ram": the rear quarter, "pit": a ram that turns in to
## spin them); whether a unit drives ahead to block; spike strips (s between, 0: none); roadblocks;
## steering gain and lead (s); sight (m).
const LEVELS := [
	{ "units": 1, "closing_mps": 15.0, "max_factor": 2.2, "contact": "ram", "block": false, "spikes_s": 0.0, "roadblock": false,
		"steer_gain": 2.0, "lead_s": 0.3, "sight_m": 250.0 },
	{ "units": 2, "closing_mps": 15.0, "max_factor": 2.2, "contact": "ram", "block": false, "spikes_s": 0.0, "roadblock": false,
		"steer_gain": 2.0, "lead_s": 0.3, "sight_m": 250.0 },
	{ "units": 3, "closing_mps": 15.0, "max_factor": 2.2, "contact": "ram", "block": false, "spikes_s": 0.0, "roadblock": false,
		"steer_gain": 2.0, "lead_s": 0.3, "sight_m": 250.0 },
	{ "units": 4, "closing_mps": 15.0, "max_factor": 2.2, "contact": "ram", "block": false, "spikes_s": 0.0, "roadblock": true,
		"steer_gain": 2.0, "lead_s": 0.3, "sight_m": 250.0 },
	{ "units": 5, "closing_mps": 15.0, "max_factor": 2.2, "contact": "ram", "block": false, "spikes_s": 0.0, "roadblock": true,
		"steer_gain": 2.0, "lead_s": 0.3, "sight_m": 250.0 },
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
