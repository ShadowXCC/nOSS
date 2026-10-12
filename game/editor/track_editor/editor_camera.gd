class_name EditorCamera
extends Node3D
## The track editor's camera (D95): it orbits a pivot on the ground (yaw, pitch, distance),
## pans across the ground and zooms; Map view looks straight down. Moves ease toward their
## target, so keys and sticks feel smooth.

const PITCH_MIN := deg_to_rad(-89.0)
const PITCH_MAX := deg_to_rad(-12.0)
const DISTANCE_MIN := 4.0
const DISTANCE_MAX := 2500.0
const EASE := 12.0

var camera := Camera3D.new()
var pivot := Vector3.ZERO
var yaw := deg_to_rad(30.0)
var pitch := deg_to_rad(-45.0)
var distance := 220.0
var map_view := false
## Where the camera is heading (eased toward each frame).
var _target := {}


func _init() -> void:
	name = "EditorCamera"
	camera.far = 6000.0
	camera.near = 0.2
	add_child(camera)
	_target = _state()


func _ready() -> void:
	_apply(1.0)


func _process(delta: float) -> void:
	_apply(1.0 - exp(-EASE * delta))


## Turns about the pivot by `d_yaw` and tilts by `d_pitch` (radians).
func orbit(d_yaw: float, d_pitch: float) -> void:
	_target.yaw = float(_target.yaw) + d_yaw
	_target.pitch = clampf(float(_target.pitch) + d_pitch, PITCH_MIN, PITCH_MAX)


## Moves the pivot across the ground: `right` and `forward` in metres, as the camera faces.
func pan(right: float, forward: float) -> void:
	var y := float(_target.yaw)
	var fwd := Vector3(-sin(y), 0.0, -cos(y))
	var side := Vector3(cos(y), 0.0, -sin(y))
	_target.pivot = (_target.pivot as Vector3) + side * right + fwd * forward


## Zooms by `factor` (< 1 closer).
func zoom(factor: float) -> void:
	_target.distance = clampf(float(_target.distance) * factor, DISTANCE_MIN, DISTANCE_MAX)


func set_pivot(p: Vector3, now := false) -> void:
	_target.pivot = p
	if now:
		pivot = p
		_apply(1.0)


## Looks at `p` from `dist` metres.
func focus(p: Vector3, dist := -1.0) -> void:
	_target.pivot = p
	if dist > 0.0:
		_target.distance = clampf(dist, DISTANCE_MIN, DISTANCE_MAX)


func toggle_map() -> void:
	map_view = not map_view
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if map_view else Camera3D.PROJECTION_PERSPECTIVE
	_apply(1.0)


## For coming back from a test drive.
func state() -> Dictionary:
	var s := _state()
	s.map = map_view
	return s


func restore(s: Dictionary) -> void:
	if s.is_empty():
		return
	_target = { "pivot": s.get("pivot", pivot), "yaw": float(s.get("yaw", yaw)), "pitch": float(s.get("pitch", pitch)), "distance": float(s.get("distance", distance)) }
	if bool(s.get("map", false)) != map_view:
		toggle_map()
	pivot = _target.pivot
	yaw = _target.yaw
	pitch = _target.pitch
	distance = _target.distance
	_apply(1.0)


func _state() -> Dictionary:
	return { "pivot": pivot, "yaw": yaw, "pitch": pitch, "distance": distance }


func _apply(k: float) -> void:
	pivot = pivot.lerp(_target.pivot, k)
	yaw = lerp_angle(yaw, float(_target.yaw), k)
	pitch = lerpf(pitch, float(_target.pitch), k)
	distance = lerpf(distance, float(_target.distance), k)
	if map_view:
		camera.size = distance * 1.6
		camera.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90.0), yaw, 0.0)), pivot + Vector3.UP * 1500.0)
		return
	var b := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	camera.transform = Transform3D(b, pivot + b.z * distance)
