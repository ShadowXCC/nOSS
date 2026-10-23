class_name PoliceWatch
extends RefCounted
## The police in a long check (highway_check, endless_check; D201): holds a player's heat at a
## level (--heat=N: set again every tick, so neither more heat nor a bust or evade changes it), and
## counts how close the units chasing them get: the share of the time one is within
## PoliceTuning.CLOSE_M, when that first happened, and how often units reset.

var police: PoliceControl
var player: Racer
## The level held (0: as it comes).
var heat := 0
var time := 0.0
var close_s := 0.0
var first_close := -1.0


func _init(pc: PoliceControl, p: Racer, level: int) -> void:
	police = pc
	player = p
	heat = level


func step(dt: float) -> void:
	if police == null or player == null or player.vehicle == null:
		return
	time += dt
	if heat > 0 and police.heat_of(player).level() != heat:
		police.heat_of(player).points = Heat.LEVELS[heat - 1]
	var nearest := INF
	for u in police.units:
		if u.waiting or u.vehicle == null or u.ai == null or u.ai.target != player:
			continue
		nearest = minf(nearest, u.vehicle.global_position.distance_to(player.vehicle.global_position))
	if nearest < PoliceTuning.CLOSE_M:
		close_s += dt
		if first_close < 0.0:
			first_close = time


## Resets of every unit so far.
func resets() -> int:
	var n := 0
	for u in police.units:
		if u.ai:
			n += int(u.ai.get(&"resets"))
	return n


func line() -> String:
	var pc := police
	return "  police: %d pursuits, %d busts, %d evaded, %d roadblocks, %d spike strips, %d patrols joined, %d waited ahead, %d pulled out; a unit within %.0f m %.0f%% of the time (first after %s), unit resets %d" % [
		pc.pursuits, pc.busts, pc.evades, pc.roadblocks, pc.spikes_laid, pc.patrols_converted, pc.aheads, pc.launches,
		PoliceTuning.CLOSE_M, close_s / maxf(time, 0.001) * 100.0, "%.0f s" % first_close if first_close >= 0.0 else "never", resets()]
