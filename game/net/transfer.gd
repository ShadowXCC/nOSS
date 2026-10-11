class_name NetTransfer
extends RefCounted
## Content transfer over one link (docs/NETWORKING.md §7, D80). Files are asked for by hash
## (WANT); the sender compresses the file with zstd and offers it (OFFER: size, compressed size,
## chunks), then sends 1150-byte chunks as unreliable packets, so ENet's reliable window (64 KB
## in flight) never limits the rate. ENet drops a chunk that arrives after a newer one; it's
## resent like a lost one. The receiver acks with its next missing chunk plus the
## chunks it just got; the sender resends what isn't acked in time. Its rate starts low, grows
## while the link keeps up, and falls back on loss or when the round trip grows (a queue
## building), so car states always get through. The receiver keeps what it has in tmp/ and asks
## to resume from there after a break. A finished file is checked against its hash before use.

signal received(h: String, bytes: PackedByteArray)
signal failed(h: String, reason: String)

## Chunk size (bytes) this side sends; the offer says which, so the two sides needn't agree.
const CHUNK := 4096
const MAX_CHUNK := 16384
const MSG_CHUNK := 120
const MSG_ACK := 121
const CHUNK_HEADER := 7
## Most WANTs out at once; more wait their turn by priority.
const MAX_WANTS := 6
## Most chunks a receiver holds out of order, and ahead of their offer.
const MAX_AHEAD := 8192
const MAX_EARLY := 512
const START_RATE := 1024 * 1024
const MIN_RATE := 64 * 1024
const RATE_STEP_S := 0.1
## Queueing delay (s) where the rate stops growing, and where it drains back.
const QUEUE_HOLD_S := 0.025
const QUEUE_DRAIN_S := 0.05
const MIN_RTO_S := 0.2
const MAX_RTO_S := 2.0
## A chunk is lost once this many chunks sent after it have been acked (reordering is allowed
## up to that).
const REORDER := 48
## An offer or the next chunk not coming for this long: ask again.
const STALL_S := 15.0
## Compressed files kept for sending to more players (bytes).
const BLOB_CACHE_BYTES := 384 << 20

## (type: int, data: Dictionary) for reliable control messages to the other side.
var send_control: Callable
## (bytes: PackedByteArray) for unreliable packets on the content channel.
var send_raw: Callable
## What this side may send.
var index: ContentIndex
## Bytes per chunk this side sends.
var chunk := CHUNK
## Upload limits (bytes/s): the whole link, and each file.
var max_rate := 8192 * 1024
var file_rate := 2048 * 1024
## Unknown hashes wait this long for the file to turn up here (a server still fetching a car
## from its owner) before the other side hears NOT_FOUND.
var hold_unknown_s := 0.0

## Measured upload rate and round trip.
var rate := float(START_RATE)
var srtt := 0.0
var rttvar := 0.0
var min_rtt := 0.0

static var _blobs := {} # hash -> {data, size, used}
static var _blob_bytes := 0
static var _blob_mutex := Mutex.new()

var _now := 0.0
var _next_xfer := 1
# Receiving
var _queue: Array[Dictionary] = [] # {hash, priority, cap, order}
var _asked := {} # hash -> {priority, cap, at, from}
var _in := {} # xfer -> In
## Chunks that came before their OFFER (it travels on another channel): xfer -> [packets].
var _early := {}
var _early_count := 0
var _order := 0
# Sending
var _out := {} # xfer -> Out
var _preparing := {} # hash -> [requests waiting for compression]
var _held: Array[Dictionary] = [] # {hash, from, at}
var _tokens := 0.0
var _period_sent := 0
var _period_lost := 0
var _period_time := 0.0
var _period_acked := 0
var _period_rtt_min := INF
var _rr := 0
var _seq := 0
## Worker tasks (compressing, unpacking); every one is waited for once done.
var _tasks := PackedInt64Array()


class In:
	var xfer := 0
	var hash := ""
	var size := 0
	var csize := 0
	var chunk := CHUNK
	var chunks := 0
	var cum := 0
	var ahead := {} # chunk -> bytes
	var acks := PackedInt32Array()
	var file: FileAccess
	var last_data := 0.0
	var cap := -1


class Out:
	var xfer := 0
	var hash := ""
	var data := PackedByteArray()
	var chunk := CHUNK
	var chunks := 0
	var acked := PackedByteArray()
	var unacked := 0
	var next := 0
	var retx: Array[int] = []
	var sent_at := PackedFloat64Array()
	var resent := PackedByteArray()
	## Each chunk's latest send number, and the highest send number acked so far.
	var sent_seq := PackedInt64Array()
	var acked_seq := -1
	## Chunks sent, oldest first, with when and their send number (a queue read from `head`).
	var flight_i := PackedInt32Array()
	var flight_t := PackedFloat64Array()
	var flight_s := PackedInt64Array()
	var head := 0
	## Sent and not acked or found lost yet: per chunk, and how many.
	var live := PackedByteArray()
	var outstanding := 0
	## Every chunk below this is acked.
	var base := 0
	var tokens := 0.0

	func in_flight() -> int:
		return outstanding

	func push(i: int, t: float, seq: int) -> void:
		if head > 4096:
			flight_i = flight_i.slice(head)
			flight_t = flight_t.slice(head)
			flight_s = flight_s.slice(head)
			head = 0
		flight_i.append(i)
		flight_t.append(t)
		flight_s.append(seq)
		if live[i] == 0:
			live[i] = 1
			outstanding += 1

	func settle(i: int) -> void:
		if live[i] == 1:
			live[i] = 0
			outstanding -= 1


## Asks for the file `h` (smaller `priority` first). `cap`: most bytes it may be (-1: any).
func want(h: String, priority := 0, cap := -1) -> void:
	if _asked.has(h) or _queue.any(func(q: Dictionary) -> bool: return q.hash == h):
		return
	_order += 1
	_queue.append({ "hash": h, "priority": priority, "cap": cap, "order": _order })


## Drops a wanted file (no longer needed).
func unwant(h: String) -> void:
	_queue = _queue.filter(func(q: Dictionary) -> bool: return q.hash != h)
	if _asked.has(h):
		_asked.erase(h)
		send_control.call(NetProtocol.Msg.CANCEL, { "hash": h })
		for x: int in _in.keys():
			if _in[x].hash == h:
				_close_in(_in[x], false)
				_in.erase(x)


## Files asked for or waiting.
func pending() -> int:
	return _queue.size() + _asked.size()


func busy() -> bool:
	return pending() > 0 or not _out.is_empty() or not _preparing.is_empty()


## Control messages for transfers; returns whether it was one.
func handle_control(type: int, d: Dictionary) -> bool:
	match type:
		NetProtocol.Msg.WANT:
			if NetProtocol.has_fields(d, { "hash": [TYPE_STRING, 71], "from": TYPE_INT }) and ContentStore.valid_hash(d.hash):
				_serve(d.hash, maxi(d.from, 0))
		NetProtocol.Msg.OFFER:
			if NetProtocol.has_fields(d, { "xfer": TYPE_INT, "hash": [TYPE_STRING, 71], "size": TYPE_INT, "csize": TYPE_INT, "from": TYPE_INT, "chunk": TYPE_INT }):
				_on_offer(d)
		NetProtocol.Msg.NOT_FOUND:
			if NetProtocol.has_fields(d, { "hash": [TYPE_STRING, 71] }) and _asked.has(d.hash):
				_asked.erase(d.hash)
				failed.emit(d.hash, "Not found")
		NetProtocol.Msg.CANCEL:
			if NetProtocol.has_fields(d, { "hash": [TYPE_STRING, 71] }):
				for x: int in _out.keys():
					if _out[x].hash == d.hash:
						_out.erase(x)
				_held = _held.filter(func(w: Dictionary) -> bool: return w.hash != d.hash)
		_:
			return false
	return true


## Chunk and ack packets; returns whether it was one.
func handle_raw(bytes: PackedByteArray) -> bool:
	if bytes.is_empty():
		return false
	match bytes[0]:
		MSG_CHUNK:
			if bytes.size() > CHUNK_HEADER:
				_on_chunk(bytes)
		MSG_ACK:
			if bytes.size() >= 8:
				_on_ack(bytes)
		_:
			return false
	return true


## Sends, acks, resends and asks; call every physics tick.
func tick(delta: float) -> void:
	_now += delta
	_reap_tasks()
	if _asked.is_empty() and _early_count > 0:
		_early.clear()
		_early_count = 0
	_ask()
	_check_stalls()
	_send_acks()
	_check_held()
	_pump(delta)
	_adapt(delta)


## Something new can be sent (a server got more of a car): unknown hashes are looked at again.
func index_changed() -> void:
	_check_held()


## The link is gone: downloads keep what they have in tmp/ to resume from.
func close() -> void:
	for x: int in _in.keys():
		_close_in(_in[x], true)
	_in.clear()
	_out.clear()
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


func _reap_tasks() -> void:
	var i := 0
	while i < _tasks.size():
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
		else:
			i += 1


# --- Receiving ------------------------------------------------------------------------------

func _ask() -> void:
	if _queue.is_empty() or _asked.size() >= MAX_WANTS:
		return
	_queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.priority < b.priority or (a.priority == b.priority and a.order < b.order))
	while not _queue.is_empty() and _asked.size() < MAX_WANTS:
		var q: Dictionary = _queue.pop_front()
		var from := _resume_point(q.hash)
		_asked[q.hash] = { "priority": q.priority, "cap": q.cap, "at": _now, "from": from }
		send_control.call(NetProtocol.Msg.WANT, { "hash": q.hash, "from": from })


## Bytes already in tmp/<hex>.part from an earlier try.
func _resume_point(h: String) -> int:
	var path := ContentStore.part_path(h)
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	return int(f.get_length()) if f else 0


func _on_offer(d: Dictionary) -> void:
	var ask: Dictionary = _asked.get(d.hash, {})
	if ask.is_empty():
		send_control.call(NetProtocol.Msg.CANCEL, { "hash": d.hash })
		return
	if d.size < 0 or d.csize <= 0 or d.size > PackageLoader.DEFAULT_LIMITS.max_total_bytes or d.csize > d.size + (1 << 20) + d.size / 8:
		_give_up(d.hash, "Bad offer")
		return
	if ask.cap >= 0 and d.size > ask.cap:
		_give_up(d.hash, "Too large")
		return
	if d.chunk < 256 or d.chunk > MAX_CHUNK:
		_give_up(d.hash, "Bad offer")
		return
	var t := In.new()
	t.xfer = d.xfer
	t.hash = d.hash
	t.size = d.size
	t.csize = d.csize
	t.chunk = d.chunk
	t.chunks = ceili(float(d.csize) / t.chunk)
	t.cap = ask.cap
	t.last_data = _now
	# `from` is in chunks; the part file keeps whole chunks of this size from there.
	var from: int = d.from if d.from * t.chunk <= int(ask.from) else 0
	DirAccess.make_dir_recursive_absolute(ContentStore.tmp_dir())
	var part := ContentStore.part_path(d.hash)
	if from == 0 or not FileAccess.file_exists(part):
		t.file = FileAccess.open(part, FileAccess.WRITE)
		from = 0
	else:
		t.file = FileAccess.open(part, FileAccess.READ_WRITE)
		if t.file:
			t.file.resize(from * t.chunk)
			t.file.seek_end()
	if t.file == null:
		_give_up(d.hash, "Can't write the cache")
		return
	t.cum = from
	_in[t.xfer] = t
	ask.at = _now
	if t.cum >= t.chunks:
		_finish(t)
		return
	var early: Array = _early.get(t.xfer, [])
	_early.erase(t.xfer)
	_early_count -= early.size()
	for packet: PackedByteArray in early:
		_on_chunk(packet)


func _on_chunk(bytes: PackedByteArray) -> void:
	var x := bytes.decode_u16(1)
	var i := int(bytes.decode_u32(3))
	var t: In = _in.get(x)
	if t == null:
		if not _asked.is_empty() and _early_count < MAX_EARLY:
			if not _early.has(x):
				_early[x] = []
			_early[x].append(bytes)
			_early_count += 1
		return
	if i >= t.chunks:
		return
	t.last_data = _now
	t.acks.append(i)
	if i < t.cum or t.ahead.has(i):
		return
	var payload := bytes.slice(CHUNK_HEADER)
	var want_size := mini(t.chunk, t.csize - i * t.chunk)
	if payload.size() != want_size:
		return
	if i == t.cum:
		t.file.store_buffer(payload)
		t.cum += 1
		while t.ahead.has(t.cum):
			t.file.store_buffer(t.ahead[t.cum])
			t.ahead.erase(t.cum)
			t.cum += 1
		if t.cum >= t.chunks:
			_finish(t)
	elif t.ahead.size() < MAX_AHEAD:
		t.ahead[i] = payload


func _send_acks() -> void:
	for t: In in _in.values():
		if t.acks.is_empty():
			continue
		var start := 0
		while start < t.acks.size():
			var n := mini(t.acks.size() - start, 255)
			var p := PackedByteArray()
			p.resize(8 + n * 4)
			p[0] = MSG_ACK
			p.encode_u16(1, t.xfer)
			p.encode_u32(3, t.cum)
			p[7] = n
			for k in n:
				p.encode_u32(8 + k * 4, t.acks[start + k])
			send_raw.call(p)
			start += n
		t.acks.clear()


func _finish(t: In) -> void:
	_in.erase(t.xfer)
	_send_final_ack(t)
	t.file.close()
	t.file = null
	var h := t.hash
	var size := t.size
	var path := ContentStore.part_path(h)
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var packed := FileAccess.get_file_as_bytes(path)
		var bytes := packed.decompress(size, FileAccess.COMPRESSION_ZSTD) if size > 0 else PackedByteArray()
		var ok := bytes.size() == size and "sha256:" + PlatformLoader.sha256_hex(bytes) == h
		DirAccess.remove_absolute(path)
		_done.call_deferred(h, bytes, ok)))


func _send_final_ack(t: In) -> void:
	var p := PackedByteArray([MSG_ACK, 0, 0, 0, 0, 0, 0, 0])
	p.encode_u16(1, t.xfer)
	p.encode_u32(3, t.chunks)
	send_raw.call(p)


func _done(h: String, bytes: PackedByteArray, ok: bool) -> void:
	if not _asked.has(h):
		return # cancelled meanwhile
	_asked.erase(h)
	if ok:
		received.emit(h, bytes)
	else:
		failed.emit(h, "Bad data")


func _check_stalls() -> void:
	for h: String in _asked.keys():
		var ask: Dictionary = _asked[h]
		var t: In = null
		for x: In in _in.values():
			if x.hash == h:
				t = x
		var last: float = t.last_data if t else float(ask.at)
		if _now - last > STALL_S:
			# Ask again from what's saved; the other side starts over.
			if t:
				_close_in(t, true)
				_in.erase(t.xfer)
			send_control.call(NetProtocol.Msg.CANCEL, { "hash": h })
			ask.from = _resume_point(h)
			ask.at = _now
			send_control.call(NetProtocol.Msg.WANT, { "hash": h, "from": ask.from })


func _give_up(h: String, reason: String) -> void:
	_asked.erase(h)
	send_control.call(NetProtocol.Msg.CANCEL, { "hash": h })
	DirAccess.remove_absolute(ContentStore.part_path(h))
	failed.emit(h, reason)


## Closes a download's part file; `keep` leaves what's there to resume from.
func _close_in(t: In, keep: bool) -> void:
	if t.file:
		t.file.close()
		t.file = null
	if not keep:
		DirAccess.remove_absolute(ContentStore.part_path(t.hash))


# --- Sending --------------------------------------------------------------------------------

func _serve(h: String, from: int) -> void:
	for x: int in _out.keys():
		if _out[x].hash == h:
			_out.erase(x) # asked again: start over from `from`
	if not index.has(h):
		if hold_unknown_s > 0.0:
			_held.append({ "hash": h, "from": from, "at": _now })
		else:
			send_control.call(NetProtocol.Msg.NOT_FOUND, { "hash": h })
		return
	var blob := _blob(h)
	if not blob.is_empty():
		_offer(h, blob, from)
		return
	if _preparing.has(h):
		_preparing[h].append(from)
		return
	_preparing[h] = [from]
	var idx := index
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var bytes := idx.read(h)
		var packed := bytes.compress(FileAccess.COMPRESSION_ZSTD) if not bytes.is_empty() else PackedByteArray()
		_prepared.call_deferred(h, packed, bytes.size())))


func _prepared(h: String, packed: PackedByteArray, size: int) -> void:
	var waiting: Array = _preparing.get(h, [])
	_preparing.erase(h)
	if packed.is_empty():
		for _from: int in waiting:
			send_control.call(NetProtocol.Msg.NOT_FOUND, { "hash": h })
		return
	var blob := _store_blob(h, packed, size)
	for from: int in waiting:
		_offer(h, blob, from)


## `from_bytes`: what the other side has already (a resume); whole chunks of it are skipped.
func _offer(h: String, blob: Dictionary, from_bytes: int) -> void:
	var o := Out.new()
	o.xfer = _next_xfer
	_next_xfer = _next_xfer % 65535 + 1
	o.hash = h
	o.data = blob.data
	o.chunk = chunk
	o.chunks = ceili(float(o.data.size()) / o.chunk)
	var from := clampi(from_bytes / o.chunk, 0, o.chunks)
	o.acked.resize(o.chunks)
	o.acked.fill(0)
	for i in from:
		o.acked[i] = 1
	o.unacked = o.chunks - from
	o.next = from
	o.base = from
	o.sent_at.resize(o.chunks)
	o.resent.resize(o.chunks)
	o.resent.fill(0)
	o.sent_seq.resize(o.chunks)
	o.sent_seq.fill(-1)
	o.live.resize(o.chunks)
	o.live.fill(0)
	_out[o.xfer] = o
	send_control.call(NetProtocol.Msg.OFFER, { "xfer": o.xfer, "hash": h, "size": blob.size, "csize": o.data.size(), "from": from, "chunk": o.chunk })
	if o.unacked == 0:
		_out.erase(o.xfer)


func _check_held() -> void:
	if _held.is_empty():
		return
	var keep: Array[Dictionary] = []
	for w: Dictionary in _held:
		if index.has(w.hash):
			_serve(w.hash, w.from)
		elif _now - float(w.at) > hold_unknown_s:
			send_control.call(NetProtocol.Msg.NOT_FOUND, { "hash": w.hash })
		else:
			keep.append(w)
	_held = keep


func _on_ack(bytes: PackedByteArray) -> void:
	var x := bytes.decode_u16(1)
	var o: Out = _out.get(x)
	if o == null:
		return
	var cum := mini(int(bytes.decode_u32(3)), o.chunks)
	var n := bytes[7] if bytes.size() > 7 else 0
	if bytes.size() < 8 + n * 4:
		return
	# The chunks that just arrived first (they time the round trip), then everything below `cum`.
	for j in n:
		var i := int(bytes.decode_u32(8 + j * 4))
		if i < o.chunks and o.acked[i] == 0:
			_mark(o, i)
	while o.base < cum:
		if o.acked[o.base] == 0:
			_mark(o, o.base, false)
		o.base += 1
	if o.unacked == 0:
		_out.erase(x)


## Chunk `i` arrived. `timed`: acked on its own (a cumulative ack can come much later, so it
## says nothing about the round trip).
func _mark(o: Out, i: int, timed := true) -> void:
	o.acked[i] = 1
	o.unacked -= 1
	_period_acked += o.chunk
	if o.sent_seq[i] >= 0:
		o.acked_seq = maxi(o.acked_seq, o.sent_seq[i])
	o.settle(i)
	if timed and o.resent[i] == 0 and o.sent_at[i] > 0.0:
		var sample := maxf(_now - o.sent_at[i], 0.001)
		if srtt == 0.0:
			srtt = sample
			rttvar = sample / 2.0
			min_rtt = sample
		else:
			rttvar = 0.75 * rttvar + 0.25 * absf(srtt - sample)
			srtt = 0.875 * srtt + 0.125 * sample
			min_rtt = minf(min_rtt, sample)
		_period_rtt_min = minf(_period_rtt_min, sample)


func _rto() -> float:
	return clampf(srtt + maxf(4.0 * rttvar, 0.03), MIN_RTO_S, MAX_RTO_S) if srtt > 0.0 else 0.5


func _pump(delta: float) -> void:
	if _out.is_empty():
		_tokens = 0.0
		return
	var burst := rate * 0.03
	_tokens = minf(_tokens + rate * delta, burst + chunk)
	var rto := _rto()
	var outs: Array = _out.values()
	# Per-file share, and losses: chunks REORDER sends behind the newest acked one, or not
	# acked within a timeout.
	for o: Out in outs:
		o.tokens = minf(o.tokens + file_rate * delta, file_rate * 0.03 + o.chunk)
		while o.head < o.flight_i.size():
			var i := o.flight_i[o.head]
			var seq := o.flight_s[o.head]
			var stale := o.sent_seq[i] != seq # sent again since
			if o.acked[i] == 1 or stale:
				o.head += 1
				continue
			if seq + REORDER < o.acked_seq or _now - o.flight_t[o.head] > rto:
				o.head += 1
				o.settle(i)
				o.retx.append(i)
				_period_lost += 1
				continue
			break
	# Round robin over the files in flight.
	var idle := 0
	while _tokens >= chunk and idle < outs.size():
		_rr = (_rr + 1) % outs.size()
		var o: Out = outs[_rr]
		var i := _next_chunk(o)
		if i < 0 or o.tokens < o.chunk:
			idle += 1
			continue
		idle = 0
		_send_chunk(o, i)
		_tokens -= o.chunk
		o.tokens -= o.chunk


func _next_chunk(o: Out) -> int:
	while not o.retx.is_empty():
		var i: int = o.retx.pop_front()
		if o.acked[i] == 0:
			o.resent[i] = 1
			return i
	# About a round trip's worth in flight (at the link's best round trip, plus a little), so
	# an overshoot fills a router's queue less.
	var base_rtt := min_rtt if min_rtt > 0.0 else 0.1
	var in_flight_cap := maxi(int(rate * (1.25 * base_rtt + 0.03) / o.chunk), 16)
	if o.in_flight() >= in_flight_cap:
		return -1
	while o.next < o.chunks and o.acked[o.next] == 1:
		o.next += 1
	if o.next >= o.chunks:
		return -1
	o.next += 1
	return o.next - 1


func _send_chunk(o: Out, i: int) -> void:
	var a := i * o.chunk
	var payload := o.data.slice(a, mini(a + o.chunk, o.data.size()))
	var p := PackedByteArray()
	p.resize(CHUNK_HEADER)
	p[0] = MSG_CHUNK
	p.encode_u16(1, o.xfer)
	p.encode_u32(3, i)
	p.append_array(payload)
	send_raw.call(p)
	o.sent_at[i] = _now
	_seq += 1
	o.sent_seq[i] = _seq
	o.push(i, _now, _seq)
	_period_sent += 1


## Rate control, by queueing delay: the round trip's best is the empty link; when the round trips
## of the last period sit more than QUEUE_HOLD_S above it, a queue is building somewhere, so the
## rate holds, and over QUEUE_DRAIN_S it drops to what actually got through. Below that it grows
## while it uses what it has. Heavy loss also cuts it; light random loss doesn't.
func _adapt(delta: float) -> void:
	_period_time += delta
	if _period_time < clampf(srtt, RATE_STEP_S, 0.5):
		return
	var delivered := _period_acked / _period_time
	if _period_sent > 0:
		var loss := float(_period_lost) / _period_sent
		var queue := (_period_rtt_min if _period_rtt_min < INF else srtt) - min_rtt
		if loss > 0.1:
			rate = minf(rate, delivered) * 0.7
		elif queue > QUEUE_DRAIN_S:
			rate = delivered * 0.9
		elif queue > QUEUE_HOLD_S:
			pass
		elif _tokens < chunk * 2: # used what it had: try more, faster while there's no queue
			rate *= 1.3 if queue < QUEUE_HOLD_S * 0.4 else 1.1
		rate = clampf(rate, MIN_RATE, max_rate)
	_period_time = 0.0
	_period_sent = 0
	_period_lost = 0
	_period_acked = 0
	_period_rtt_min = INF


# --- Compressed files -----------------------------------------------------------------------

static func _blob(h: String) -> Dictionary:
	_blob_mutex.lock()
	var b: Dictionary = _blobs.get(h, {})
	if not b.is_empty():
		b.used = Time.get_ticks_msec()
	_blob_mutex.unlock()
	return b


static func _store_blob(h: String, packed: PackedByteArray, size: int) -> Dictionary:
	_blob_mutex.lock()
	var b := { "data": packed, "size": size, "used": Time.get_ticks_msec() }
	if not _blobs.has(h):
		_blobs[h] = b
		_blob_bytes += packed.size()
		while _blob_bytes > BLOB_CACHE_BYTES and _blobs.size() > 1:
			var oldest := ""
			for k: String in _blobs:
				if k != h and (oldest.is_empty() or _blobs[k].used < _blobs[oldest].used):
					oldest = k
			_blob_bytes -= _blobs[oldest].data.size()
			_blobs.erase(oldest)
	else:
		b = _blobs[h]
	_blob_mutex.unlock()
	return b


static func clear_blobs() -> void:
	_blob_mutex.lock()
	_blobs.clear()
	_blob_bytes = 0
	_blob_mutex.unlock()
