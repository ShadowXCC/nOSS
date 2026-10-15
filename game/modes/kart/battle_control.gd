class_name BattleControl
extends Node
## Battles (D144): lives, hits and the end of a match. Built out in K7.

var session: TrackSession
var _lost := {}


## Lives `r` has lost so far (the item odds lean on it).
func lives_lost(r: Racer) -> int:
	return int(_lost.get(r, 0))
