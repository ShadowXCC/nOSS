class_name ClockSync
extends RefCounted
## The server's clock on a client (D84). The client pings now and then; each answer carries the
## server's time, which is half a round trip old when it lands. Of the recent answers, the one
## with the shortest round trip (least queueing) gives the offset; the clock moves toward it
## gently, or jumps if it's far off. The server's clock is just its own.

const PING := 101
const PONG := 102
const KEEP := 16
const STEP_S := 0.5

## server time = local time + offset
var offset := 0.0
var rtt := 0.0
var synced := false
var _samples: Array = [] # [rtt, offset]
var _next_ping := 0.0
var _pings := 0


static func local_now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func now() -> float:
	return local_now() + offset


## A ping to send now, or empty: quickly at first, then every second.
func ping_due() -> PackedByteArray:
	var t := local_now()
	if t < _next_ping:
		return PackedByteArray()
	_pings += 1
	_next_ping = t + (0.1 if _pings < 8 else 1.0)
	var p := PackedByteArray([PING, 0, 0, 0, 0, 0, 0, 0, 0])
	p.encode_double(1, t)
	return p


## The server's answer to `ping`, stamped with its clock.
static func pong(ping: PackedByteArray, server_now: float) -> PackedByteArray:
	if ping.size() != 9:
		return PackedByteArray()
	var p := PackedByteArray([PONG])
	p.append_array(ping.slice(1, 9))
	p.resize(17)
	p.encode_double(9, server_now)
	return p


## The server's answer to a ping; `at`: when it arrived (local time; now if negative).
func on_pong(bytes: PackedByteArray, at := -1.0) -> void:
	if bytes.size() != 17:
		return
	var sent := bytes.decode_double(1)
	var server := bytes.decode_double(9)
	var t := at if at >= 0.0 else local_now()
	var trip := t - sent
	if not is_finite(server) or trip < 0.0 or trip > 5.0:
		return
	_samples.append([trip, server + trip / 2.0 - t])
	if _samples.size() > KEEP:
		_samples.pop_front()
	var best: Array = _samples[0]
	for s: Array in _samples:
		if s[0] < best[0]:
			best = s
	rtt = best[0]
	if not synced or absf(best[1] - offset) > STEP_S:
		offset = best[1]
		synced = true
	else:
		offset = lerpf(offset, best[1], 0.2)
