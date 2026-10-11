class_name CarState
extends RefCounted
## One car's state on the wire (docs/NETWORKING.md §6, D84): 44 bytes.
##   id u8 · time u32 (server clock, ms) · position i32 ×3 (mm) · rotation (smallest three, 32 bits)
##   · linear and angular velocity (half floats) · front steer i8 · wheel lift i8 ×4 (cm)
##   · throttle u8 · brake u8 · gear i8 · rpm u16 · flags u8
## The pose is the ground reference (what Vehicle.reset_to takes), so a placeholder and the real
## car line up whatever their models.

const SIZE := 44
const STEER_RANGE := 0.8 # rad, both ways
const FLAG_BRAKE := 1
const FLAG_GHOSTED := 2
const FLAG_WAITING := 4 # hidden, rejoining
const FLAG_TELEPORT := 8 # placed (reset, grid): snap, don't smooth
const FLAG_HANDBRAKE := 16

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
	return s


func encode(out: PackedByteArray, at: int) -> void:
	out.encode_u8(at, id)
	out.encode_u32(at + 1, int(time * 1000.0) & 0xFFFFFFFF)
	for k in 3:
		out.encode_s32(at + 5 + k * 4, clampi(roundi(xform.origin[k] * 1000.0), -2147483647, 2147483647))
	out.encode_u32(at + 17, pack_rotation(xform.basis.get_rotation_quaternion()))
	for k in 3:
		out.encode_half(at + 21 + k * 2, velocity[k])
		out.encode_half(at + 27 + k * 2, angular[k])
	out.encode_s8(at + 33, clampi(roundi(steer / STEER_RANGE * 127.0), -127, 127))
	for k in 4:
		out.encode_s8(at + 34 + k, clampi(roundi(lift[k] * 100.0), -127, 127))
	out.encode_u8(at + 38, clampi(roundi(throttle * 255.0), 0, 255))
	out.encode_u8(at + 39, clampi(roundi(brake * 255.0), 0, 255))
	out.encode_s8(at + 40, clampi(gear, -127, 127))
	out.encode_u16(at + 41, clampi(roundi(rpm), 0, 65535))
	out.encode_u8(at + 43, flags)


## A state from `bytes` at `at`; `time_base` is the server clock (s) now, to unwrap the 32-bit
## milliseconds. Null if it holds non-finite numbers.
static func decode(bytes: PackedByteArray, at: int, time_base := 0.0) -> CarState:
	var s := CarState.new()
	s.id = bytes.decode_u8(at)
	var ms := bytes.decode_u32(at + 1)
	# The full time nearest time_base with these low 32 bits.
	var base_ms := int(time_base * 1000.0)
	var full := (base_ms & ~0xFFFFFFFF) | ms
	if full - base_ms > 0x7FFFFFFF:
		full -= 0x100000000
	elif base_ms - full > 0x7FFFFFFF:
		full += 0x100000000
	s.time = full / 1000.0
	var origin := Vector3(bytes.decode_s32(at + 5), bytes.decode_s32(at + 9), bytes.decode_s32(at + 13)) / 1000.0
	var q := unpack_rotation(bytes.decode_u32(at + 17))
	s.xform = Transform3D(Basis(q), origin)
	s.velocity = Vector3(bytes.decode_half(at + 21), bytes.decode_half(at + 23), bytes.decode_half(at + 25))
	s.angular = Vector3(bytes.decode_half(at + 27), bytes.decode_half(at + 29), bytes.decode_half(at + 31))
	if not (s.velocity.is_finite() and s.angular.is_finite()):
		return null
	s.steer = bytes.decode_s8(at + 33) / 127.0 * STEER_RANGE
	for k in 4:
		s.lift[k] = bytes.decode_s8(at + 34 + k) / 100.0
	s.throttle = bytes.decode_u8(at + 38) / 255.0
	s.brake = bytes.decode_u8(at + 39) / 255.0
	s.gear = bytes.decode_s8(at + 40)
	s.rpm = bytes.decode_u16(at + 41)
	s.flags = bytes.decode_u8(at + 43)
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
