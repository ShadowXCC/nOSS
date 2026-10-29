class_name SumoTeams
extends RefCounted
## Sumo Team Battle (D234): the teams' names and colours, the random draw and the field it is
## drawn from. Every car, player or bot, goes into the hat; a new draw each match.

## The teams, in order. The name always goes with the colour (docs/ACCESSIBILITY.md), and the
## colours stay apart for every colour vision Palette simulates (sumo_teams_test).
const NAMES := ["Red", "Blue", "Green", "Gold"]
const COLORS := [Color("#E03A2F"), Color("#2A5FD8"), Color("#22B07D"), Color("#F7D23E")]


static func name_of(team: int) -> String:
	return String(NAMES[team]) if team >= 0 and team < NAMES.size() else ""


static func color_of(team: int) -> Color:
	return COLORS[team] if team >= 0 and team < COLORS.size() else Color.WHITE


## `racers` shuffled and dealt round the `teams` in turn, so no team has more than one car more
## than another: racer -> team. From the game's own random numbers, so a seeded soak check
## replays a match exactly; online only the server draws, and says.
static func draw(racers: Array, teams: int) -> Dictionary:
	var hat := racers.duplicate()
	hat.shuffle()
	var out := {}
	for i in hat.size():
		out[hat[i]] = i % maxi(teams, 1)
	return out


## The bots a team match takes (D234): enough added that the field splits evenly, at least one car
## a team, and no more than `cap` cars in all, trimming bots when the round-up would pass it. When
## the players alone cannot be split evenly within the cap, one team is a car short.
static func even_field(humans: int, bots: int, teams: int, cap: int) -> int:
	teams = maxi(teams, 1)
	var want := maxi(ceili(float(humans + bots) / float(teams)) * teams, teams)
	if want > cap:
		want = floori(float(cap) / float(teams)) * teams
	return clampi(want - humans, 0, maxi(cap - humans, 0))
