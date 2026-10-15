class_name CarState
extends RefCounted
## One car's state on the wire (docs/NETWORKING.md §6, D84, D112): 46 bytes.
##   id u16 · time u32 (server clock, ms) · position i32 ×3 (mm) · rotation (smallest three, 32
##   bits) · linear and angular velocity (half floats) · front steer i8 · wheel lift i8 ×4 (cm)
##   · throttle u8 · brake u8 · gear i8 · rpm u16 · flags u8 · flags2 u8
## The pose is the ground reference (what Vehicle.reset_to takes), so a placeholder and the real
## car line up whatever their models. Ids: players 1-199, the server's AI 200-299, police
## 300-399, highway traffic 1000 + its lane-sim index (NetProtocol).

const SIZE := 46
const STEER_RANGE := 0.8 # rad, both ways
const FLAG_BRAKE := 1
const FLAG_GHOSTED := 2
const FLAG_WAITING := 4 # hidden, rejoining
const FLAG_TELEPORT := 8 # placed (reset, grid): snap, don't smooth
const FLAG_HANDBRAKE := 16
const FLAG_KNOCK := 32 # just took a knock (a wall, a car): a sudden stop isn't a cheat
## flags2: lights, horn and siren (D119), and a traffic car's driver (D110).
const FLAG2_HORN := 1
const FLAG2_HEAD_FLASH := 2
const FLAG2_INDICATOR_L := 4
const FLAG2_INDICATOR_R := 8
const FLAG2_SIREN := 16
const FLAG2_LIGHT_BAR := 32
const FLAG2_WRECKED := 64 # traffic: a wreck where it stands
const FLAG2_LANE_OK := 128 # traffic: on its lane's line, the right way, upright

var id := 0
## Server clock, seconds.
var time := 0.0
## Ground reference: origin on the ground under the car, +Z forward.
var xform := Transform3D.IDENTITY
var velocity := Vector3.ZERO
var angular := Vector3.ZERO
var steer := 0.0
var lift := PackedFloat32Array([0, 0, 0, 0])
var throttle := 0.0
var brake := 0.0
var gear := 0
var rpm := 0.0
var flags := 0
var flags2 := 0


## The state of `vehicle` now (`time` in server seconds).
static func of(vehicle: Vehicle, car_id: int, server_time: float) -> CarState:
	var s := CarState.new()
	s.id = car_id
	s.time = server_time
	s.xform = vehicle.ground_reference()
	s.velocity = vehicle.linear_velocity
	s.angular = vehicle.angular_velocity
	var sim := vehicle.sim
	var n := sim.get_wheel_count()
	if n > 0:
		s.steer = sim.get_wheel_visual(0).x
	for i in mini(n, 4):
		s.lift[i] = sim.get_wheel_visual(i).z
	s.throttle = sim.get_throttle()
	s.brake = sim.get_brake()
	s.gear = sim.get_gear()
	s.rpm = sim.get_rpm()
	s.flags = (FLAG_BRAKE if s.brake > 0.05 else 0) | (FLAG_HANDBRAKE if vehicle.handbrake > 0.5 else 0)
	s.flags2 = (FLAG2_HORN if vehicle.horn else 0) | (FLAG2_HEAD_FLASH if vehicle.head_flash else 0) \
		| (FLAG2_INDICATOR_L if vehicle.indicators & 1 else 0) | (FLAG2_INDICATOR_R if vehicle.indicators & 2 else 0) \
		| (FLAG2_SIREN if vehicle.siren else 0) | (FLAG2_LIGHT_BAR if vehicle.light_bar else 0)
	return s


## The lights, horn and siren a remote car shows (flags2).
static func show_on(vehicle: Vehicle, flags2: int) -> void:
	vehicle.horn = flags2 & FLAG2_HORN != 0
	vehicle.head_flash = flags2 & FLAG2_HEAD_FLASH != 0
	vehicle.indicators = (1 if flags2 & FLAG2_INDICATOR_L else 0) | (2 if flags2 & FLAG2_INDICATOR_R else 0)
	vehicle.siren = flags2 & FLAG2_SIREN != 0
	vehicle.light_bar = flags2 & FLAG2_LIGHT_BAR != 0


func encode(out: PackedByteArray, at: int) -> void:
	out.encode_u16(at, id)
	out.encode_u32(at + 2, int(time * 1000.0) & 0xFFFFFFFF)
	for k in 3:
		out.encode_s32(at + 6 + k * 4, clampi(roundi(xform.origin[k] * 1000.0), -2147483647, 2147483647))
	out.encode_u32(at + 18, pack_rotation(xform.basis.get_rotation_quaternion()))
	for k in 3:
		out.encode_half(at + 22 + k * 2, velocity[k])
		out.encode_half(at + 28 + k * 2, angular[k])
	out.encode_s8(at + 34, clampi(roundi(steer / STEER_RANGE * 127.0), -127, 127))
	for k in 4:
		out.encode_s8(at + 35 + k, clampi(roundi(lift[k] * 100.0), -127, 127))
	out.encode_u8(at + 39, clampi(roundi(throttle * 255.0), 0, 255))
	out.encode_u8(at + 40, clampi(roundi(brake * 255.0), 0, 255))
	out.encode_s8(at + 41, clampi(gear, -127, 127))
	out.encode_u16(at + 42, clampi(roundi(rpm), 0, 65535))
	out.encode_u8(at + 44, flags)
	out.encode_u8(at + 45, flags2)


## A state from `bytes` at `at`; `time_base` is the server clock (s) now, to unwrap the 32-bit
## milliseconds. Null if it holds non-finite numbers.
static func decode(bytes: PackedByteArray, at: int, time_base := 0.0) -> CarState:
	var s := CarState.new()
	s.id = bytes.decode_u16(at)
	var ms := bytes.decode_u32(at + 2)
	# The full time nearest time_base with these low 32 bits.
	var base_ms := int(time_base * 1000.0)
	var full := (base_ms & ~0xFFFFFFFF) | ms
	if full - base_ms > 0x7FFFFFFF:
		full -= 0x100000000
	elif base_ms - full > 0x7FFFFFFF:
		full += 0x100000000
	s.time = full / 1000.0
	var origin := Vector3(bytes.decode_s32(at + 6), bytes.decode_s32(at + 10), bytes.decode_s32(at + 14)) / 1000.0
	var q := unpack_rotation(bytes.decode_u32(at + 18))
	s.xform = Transform3D(Basis(q), origin)
	s.velocity = Vector3(bytes.decode_half(at + 22), bytes.decode_half(at + 24), bytes.decode_half(at + 26))
	s.angular = Vector3(bytes.decode_half(at + 28), bytes.decode_half(at + 30), bytes.decode_half(at + 32))
	if not (s.velocity.is_finite() and s.angular.is_finite()):
		return null
	s.steer = bytes.decode_s8(at + 34) / 127.0 * STEER_RANGE
	for k in 4:
		s.lift[k] = bytes.decode_s8(at + 35 + k) / 100.0
	s.throttle = bytes.decode_u8(at + 39) / 255.0
	s.brake = bytes.decode_u8(at + 40) / 255.0
	s.gear = bytes.decode_s8(at + 41)
	s.rpm = bytes.decode_u16(at + 42)
	s.flags = bytes.decode_u8(at + 44)
	s.flags2 = bytes.decode_u8(at + 45)
	return s


## Smallest three: the largest component's index (2 bits) and the other three in 10 bits each,
## scaled from ±1/√2.
static func pack_rotation(q: Quaternion) -> int:
	q = q.normalized()
	var c := [q.x, q.y, q.z, q.w]
	var big := 0
	for i in 4:
		if absf(c[i]) > absf(c[big]):
			big = i
	var sign := 1.0 if c[big] >= 0.0 else -1.0
	var out := big
	var shift := 2
	for i in 4:
		if i == big:
			continue
		var v := clampf(c[i] * sign / 0.70710678, -1.0, 1.0)
		out |= (roundi((v + 1.0) * 511.5) & 0x3FF) << shift
		shift += 10
	return out


static func unpack_rotation(packed: int) -> Quaternion:
	var big := packed & 3
	var c := [0.0, 0.0, 0.0, 0.0]
	var shift := 2
	var sum := 0.0
	for i in 4:
		if i == big:
			continue
		var v := (((packed >> shift) & 0x3FF) / 511.5 - 1.0) * 0.70710678
		c[i] = v
		sum += v * v
		shift += 10
	c[big] = sqrt(maxf(1.0 - sum, 0.0))
	return Quaternion(c[0], c[1], c[2], c[3]).normalized()
