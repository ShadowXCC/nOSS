class_name FloatingOrigin
extends Node
## Keeps an endless world near the scene's origin (docs/ARCHITECTURE.md §8, R7, D155): Godot's
## positions are 32-bit floats, good to about 0.25 mm within 2 km but only 2 cm at 150 km. The
## scene's origin sits at a world point (x, z, 64-bit floats); when what the game is watching (its
## players, or a server's convoy) gets SHIFT_AT_M from it, the origin moves there and everything
## in the scene moves back by the same amount, in one physics tick: every node in the group
## "origin_shift" gets origin_shifted(delta), delta being what to add to its scene positions.
##
## - XZ only: heights stay as they are (cameras smooth absolute height).
## - The origin snaps to SNAP_M, the least common multiple of every world texture's period (2, 3,
##   4, 5, 6 and 250 m), so world-mapped textures (roads, ground) don't jump.
## - It runs first in a tick (before the network and the cars), so everything moves together and
##   cameras and sounds see no jump (Doppler compares camera and source).

signal shifted(delta: Vector3)

const SNAP_M := 1500.0
const SHIFT_AT_M := 2000.0

## The world point (metres) the scene's origin is at.
var x := 0.0
var z := 0.0
## () -> Vector3: the scene point to keep near the origin. Unset: nothing moves.
var focus := Callable()
## Off: never moves (the negative control of the long-drive check).
var enabled := true
var shifts := 0


func _ready() -> void:
	name = "FloatingOrigin"
	process_physics_priority = -98


func _physics_process(_delta: float) -> void:
	if enabled and focus.is_valid():
		check(focus.call())


## Moves the origin if `at` (scene) is SHIFT_AT_M or more from it. True if it moved.
func check(at: Vector3) -> bool:
	if Vector2(at.x, at.z).length() < SHIFT_AT_M:
		return false
	var dx := snappedf(at.x, SNAP_M)
	var dz := snappedf(at.z, SNAP_M)
	if dx == 0.0 and dz == 0.0:
		return false
	shift_by(dx, dz)
	return true


## Moves the origin by (dx, dz) world metres: everything in the scene moves by (-dx, -dz).
func shift_by(dx: float, dz: float) -> void:
	x += dx
	z += dz
	shifts += 1
	var delta := Vector3(-dx, 0.0, -dz)
	get_tree().call_group(&"origin_shift", &"origin_shifted", delta)
	shifted.emit(delta)


## A world point (64-bit floats) in the scene.
func to_scene(wx: float, wy: float, wz: float) -> Vector3:
	return Vector3(wx - x, wy, wz - z)


## A scene point in the world, as [x, y, z] (64-bit floats).
func to_world(p: Vector3) -> PackedFloat64Array:
	return PackedFloat64Array([float(p.x) + x, float(p.y), float(p.z) + z])
