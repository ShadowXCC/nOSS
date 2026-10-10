class_name WheelInput
extends RefCounted
## Wheel, pedals and force feedback through noss_core (docs/INPUT.md §5-6). Filled in by
## the native input layer; inactive when no wheel is connected.


func is_active() -> bool:
	return false


func has_clutch() -> bool:
	return false


func steer() -> float:
	return 0.0


func throttle() -> float:
	return 0.0


func brake() -> float:
	return 0.0


func clutch() -> float:
	return 0.0
