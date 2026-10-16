class_name ItemPolicy
extends RefCounted
## When to use a kart item (D143): the kart AI's choice, and the item assist's for players
## (ACC-07). After getting an item it waits a moment (longer at lower skill), then uses it when
## it pays: Nitro on a straight, a Bolt with a kart lined up ahead (or close behind, thrown back),
## Seekers and the Hunter at once, a Shield when something's coming, a Slick or an EMP with karts
## close, a Magnet with a kart a little way ahead. Nothing is held for ever.

const STRAIGHT_M := 60.0
const STRAIGHT_CURVATURE := 1.0 / 120.0
const BOLT_RANGE_M := 45.0
const BOLT_BACK_M := 15.0
const SLICK_BEHIND_M := 25.0
const EMP_NEAR_M := 14.0
const MAGNET_RANGE := Vector2(15.0, 55.0)
const THREAT_M := 50.0
## The most an item is held, by kind, before it's used anyway.
const HOLD_MAX := { "shield": 5.0, "oil_slick": 6.0, "emp": 6.0, "bolt": 8.0, "magnet": 6.0, "nitro": 4.0, "nitro_x3": 4.0 }

var racer: Racer
var skill := 80.0
var rng := RandomNumberGenerator.new()
var _item := ""
var _wait := 0.0
var _held := 0.0


## What to do now: null (keep it), or whether to throw it back.
func think(delta: float) -> Variant:
	var kart := racer.session.kart
	if kart == null or racer.vehicle == null:
		return null
	var items := kart.items
	var item := items.item_of(racer)
	if item == "":
		_item = ""
		return null
	if item != _item:
		_item = item
		_held = 0.0
		_wait = lerpf(1.5, 0.15, clampf(skill / 100.0, 0.0, 1.0)) * rng.randf_range(0.6, 1.4)
	_held += delta
	if _wait > 0.0:
		_wait -= delta
		return null
	if _held >= float(HOLD_MAX.get(item, 4.0)):
		return false
	match item:
		"nitro", "nitro_x3":
			if items.slot(racer).nitro_gap <= 0.0 and _straight_ahead() and racer.vehicle.speed() < racer.vehicle.sim.get_geared_top() * 0.97:
				return false
		"bolt":
			if _lined_up(BOLT_RANGE_M, 1.0):
				return false
			if _behind_within(BOLT_BACK_M, 1.2):
				return true
		"seeker":
			if items._ahead_of(racer, racer.session.track.length / 2.0) != null:
				return false
		"leader_hunter":
			return false
		"shield":
			if _threatened():
				return false
		"oil_slick":
			if _behind_within(SLICK_BEHIND_M, 3.0):
				return false
		"emp":
			if _near_count(EMP_NEAR_M) > 0:
				return false
		"magnet":
			var ahead := items._ahead_of(racer, MAGNET_RANGE.y)
			if ahead and ahead.com().distance_to(racer.com()) > MAGNET_RANGE.x:
				return false
	return null


func _straight_ahead() -> bool:
	var t := racer.session.track
	if t.arena:
		return true
	for d in range(0, int(STRAIGHT_M), 10):
		if absf(t.curvature[t.index_at(racer.distance + d)]) > STRAIGHT_CURVATURE:
			return false
	return true


## A kart ahead within `reach` m, inside `width` m (more for a worse aim) of the way it points.
func _lined_up(reach: float, width: float) -> bool:
	var me := racer.vehicle.global_transform
	var slack := width + (1.0 - skill / 100.0) * 1.5
	for o: Racer in racer.session.racers:
		if o == racer or o.vehicle == null or o.towed or o.out:
			continue
		var local := me.affine_inverse() * o.com()
		if local.z > 2.0 and local.z < reach and absf(local.x) < slack + local.z * 0.02:
			return true
	return false


func _behind_within(reach: float, width: float) -> bool:
	var me := racer.vehicle.global_transform
	for o: Racer in racer.session.racers:
		if o == racer or o.vehicle == null or o.towed or o.out:
			continue
		var local := me.affine_inverse() * o.com()
		if local.z < -1.0 and local.z > -reach and absf(local.x) < width:
			return true
	return false


func _near_count(reach: float) -> int:
	var n := 0
	for o: Racer in racer.session.racers:
		if o != racer and o.vehicle and not o.towed and not o.out and o.com().distance_to(racer.com()) < reach:
			n += 1
	return n


## A Seeker or the Hunter coming for it, or a Bolt heading its way close by.
func _threatened() -> bool:
	var me := racer.com()
	for e: Dictionary in racer.session.kart.entities.list.values():
		var to_me := me - (e.pos as Vector3)
		var d := to_me.length()
		if e.target == racer and d < THREAT_M:
			return true
		if e.kind == "bolt" and d < 15.0 and (e.vel as Vector3).dot(to_me) > 0.0:
			return true
	return false
