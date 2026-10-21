class_name SpikeStrip
extends Node3D
## A spike strip (D192): laid across the road ahead of a chased player, with half a lane left open.
## A wheel that rolls over it goes flat (Vehicle.flatten) for FLAT_S, or until the car's reset. It
## lies in road space, `at_m` along the road from `lat_from` to `lat_to` across, so it's checked
## through the road's own projection wherever the scene's origin is.

const LENGTH_M := 0.8
const FLAT_S := 30.0
## Taken up once its player is this far past it, or this long after it went down.
const PAST_M := 120.0
const LIFE_S := 60.0
## Wheels further than this from its middle aren't looked at.
const NEAR_M := 14.0

var road: PoliceRoad
var at_m := 0.0
var lat_from := 0.0
var lat_to := 0.0
## Whom it was laid for, and whose cars it catches.
var for_racer: Racer
var watch: Array = []
var age := 0.0


func _ready() -> void:
	name = "SpikeStrip"
	add_to_group(&"origin_shift")
	var at := road.session.track.transform_at(at_m, (lat_from + lat_to) / 2.0)
	transform = Transform3D(at.basis, at.origin + at.basis.y * 0.03)
	var width := absf(lat_to - lat_from)
	var strip := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.06, LENGTH_M)
	strip.mesh = box
	strip.material_override = WorldMaterials.get_material("spike_strip", RetroTextures.checker(), 0.5, 0.6, false, Vector2(12.0, 1.0), Color(0.22, 0.22, 0.24))
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	for end: float in [-1.0, 1.0]:
		var cap := MeshInstance3D.new()
		var cb := BoxMesh.new()
		cb.size = Vector3(0.3, 0.1, LENGTH_M)
		cap.mesh = cb
		cap.position = Vector3(end * width / 2.0, 0.02, 0.0)
		cap.material_override = WorldMaterials.get_material("spike_strip_end", null, 0.6, 0.2, false, Vector2.ONE, Color(1.0, 0.8, 0.1))
		add_child(cap)


func _physics_process(delta: float) -> void:
	age += delta
	for r: Variant in watch:
		if r is Racer and is_instance_valid(r):
			_check(r)


## Done with: long enough down, its player well past it (or gone).
func done() -> bool:
	return age > LIFE_S or for_racer == null or not is_instance_valid(for_racer) or road.past(for_racer, at_m) > PAST_M


## Which of `v`'s wheels are on it now (bit i for physics wheel i).
func on_it(v: Vehicle) -> int:
	if v.fitted == null or v.global_position.distance_to(global_position) > NEAR_M:
		return 0
	var mask := 0
	for i in v.fitted.physics_wheels.size():
		var w: Dictionary = v.fitted.physics_wheels[i]
		var p := v.global_transform * (w.center as Vector3)
		var proj := road.project(p)
		if absf(road.delta_m(float(proj.distance), at_m)) < LENGTH_M / 2.0 + 0.15 \
				and float(proj.lateral) >= minf(lat_from, lat_to) and float(proj.lateral) <= maxf(lat_from, lat_to):
			mask |= 1 << i
	return mask


func _check(r: Racer) -> void:
	var v := r.vehicle
	if v == null or not is_instance_valid(v) or v.remote:
		return
	var mask := on_it(v)
	if mask & ~v.flats:
		v.flatten(mask, FLAT_S)
		r.notify("Flat tyre" if mask & (mask - 1) == 0 else "Flat tyres", 2.5)


## The world moved (FloatingOrigin): so does the strip (its road-space spot doesn't).
func origin_shifted(delta: Vector3) -> void:
	position += delta
