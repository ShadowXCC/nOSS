extends RefCounted
## Two transfer ends joined by a simulated link. Control messages are reliable and in order
## (ENet does that); content packets can be lost, reordered and delayed.

const DT := 1.0 / 120.0

var a: NetTransfer
var b: NetTransfer
var loss := 0.0
var delay := 0.02
var jitter := 0.0
## Bytes per second each way (0: no limit), with a queue that drops when full.
var bandwidth := 0.0
var tamper := Callable()
var cut := false
var now := 0.0
var queue: Array = [] # [time, to (0 = a, 1 = b), kind ("c" control or "r" raw), type, data]
var busy_until := [0.0, 0.0]
var rng := RandomNumberGenerator.new()

func _init(p_a: NetTransfer, p_b: NetTransfer) -> void:
	rng.seed = 7
	a = p_a
	b = p_b
	a.send_control = func(type: int, d: Dictionary) -> void: _push(1, "c", type, d)
	b.send_control = func(type: int, d: Dictionary) -> void: _push(0, "c", type, d)
	a.send_raw = func(bytes: PackedByteArray) -> void: _push(1, "r", 0, bytes)
	b.send_raw = func(bytes: PackedByteArray) -> void: _push(0, "r", 0, bytes)

func _push(to: int, kind: String, type: int, data: Variant) -> void:
	if cut:
		return
	var at := now + delay
	if kind == "r":
		if rng.randf() < loss:
			return
		at += rng.randf() * jitter
		if bandwidth > 0.0:
			var start := maxf(busy_until[to], now)
			if start - now > 0.25: # a 250 ms queue is full
				return
			busy_until[to] = start + (data as PackedByteArray).size() / bandwidth
			at = busy_until[to] + delay
		if tamper.is_valid():
			data = tamper.call(data)
	queue.append([at, to, kind, type, data])

func step() -> void:
	now += DT
	a.tick(DT)
	b.tick(DT)
	var due := queue.filter(func(q: Array) -> bool: return q[0] <= now)
	queue = queue.filter(func(q: Array) -> bool: return q[0] > now)
	due.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for q: Array in due:
		var end: NetTransfer = a if q[1] == 0 else b
		if q[2] == "c":
			end.handle_control(q[3], q[4])
		else:
			end.handle_raw(q[4])
