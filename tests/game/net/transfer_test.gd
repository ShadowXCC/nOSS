extends GdUnitTestSuite
## Content transfer (D80, MP-05): files by hash over a simulated link with loss, reordering and
## delay; resuming after a break; size caps; corrupted data; unknown files; the cache.

const DT := 1.0 / 120.0

var dir := "user://tests/net_transfer/"


const Link := preload("res://tests/game/net/link_sim.gd")


func before() -> void:
	Settings.use_folder("user://tests/net_transfer")
	ContentStore.root = dir.path_join("cache")


func after() -> void:
	ContentStore.root = "user://cache/content/"
	Settings.use_folder("user://")


func before_test() -> void:
	ContentStore.clear()
	NetTransfer.clear_blobs()


func _file(name: String, size: int, random := true) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir)
	var bytes := PackedByteArray()
	bytes.resize(size)
	var rng := RandomNumberGenerator.new()
	rng.seed = size
	for i in size:
		bytes[i] = rng.randi() % 256 if random else (i / 64) % 7
	var path := dir.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return { "path": path, "bytes": bytes, "hash": "sha256:" + PlatformLoader.sha256_hex(bytes) }


func _ends() -> Array:
	var sender := NetTransfer.new()
	sender.index = ContentIndex.new()
	var receiver := NetTransfer.new()
	receiver.index = ContentIndex.new()
	return [sender, receiver]


## Runs the link until `done` or `seconds` of simulated time; lets worker results land.
func _run(link: Link, done: Callable, seconds := 20.0) -> bool:
	var steps := int(seconds / DT)
	for k in steps:
		link.step()
		if k % 4 == 0:
			await get_tree().process_frame
		if done.call():
			return true
	return false


func _collect(t: NetTransfer) -> Dictionary:
	var out := { "got": {}, "failed": {} }
	t.received.connect(func(h: String, bytes: PackedByteArray) -> void: out.got[h] = bytes)
	t.failed.connect(func(h: String, reason: String) -> void: out.failed[h] = reason)
	return out


func _part_over(h: String, size: int) -> bool:
	var part := ContentStore.part_path(h)
	return FileAccess.file_exists(part) and FileAccess.open(part, FileAccess.READ).get_length() > size


## Notes where each WANT asks to start, then sends it on.
func _spy(type: int, d: Dictionary, send: Callable, asked: Array) -> void:
	if type == NetProtocol.Msg.WANT:
		asked.append(d.from)
	send.call(type, d)


func _flip_chunk_3(bytes: PackedByteArray) -> PackedByteArray:
	if bytes[0] == NetTransfer.MSG_CHUNK and bytes.decode_u32(3) == 3:
		var copy := bytes.duplicate()
		copy[20] ^= 0xFF
		return copy
	return bytes


func test_files_arrive_whole() -> void:
	var ends := _ends()
	var f1 := _file("random.bin", 300_000)
	var f2 := _file("plain.bin", 500_000, false)
	ends[0].index.add_file(f1.path)
	ends[0].index.add_file(f2.path)
	var link := Link.new(ends[0], ends[1])
	var res := _collect(ends[1])
	ends[1].want(f1.hash)
	ends[1].want(f2.hash, 1)
	assert_bool(await _run(link, func() -> bool: return res.got.size() == 2)).is_true()
	assert_bool(res.got[f1.hash] == f1.bytes).is_true()
	assert_bool(res.got[f2.hash] == f2.bytes).is_true()
	assert_bool(await _run(link, func() -> bool: return not ends[0].busy() and not ends[1].busy(), 1.0)).is_true()


func test_loss_reordering_and_delay() -> void:
	var ends := _ends()
	var f := _file("lossy.bin", 400_000)
	ends[0].index.add_file(f.path)
	var link := Link.new(ends[0], ends[1])
	link.loss = 0.1
	link.delay = 0.075
	link.jitter = 0.03
	var res := _collect(ends[1])
	ends[1].want(f.hash)
	assert_bool(await _run(link, func() -> bool: return res.got.has(f.hash), 30.0)).is_true()
	assert_bool(res.got[f.hash] == f.bytes).is_true()


func test_rate_follows_the_link() -> void:
	# 2 MB over a 1 MB/s link at 50 ms: about 2 s, and the queue never overflows for long.
	var ends := _ends()
	var f := _file("big.bin", 2_000_000)
	ends[0].index.add_file(f.path)
	ends[0].max_rate = 8 << 20
	ends[0].file_rate = 8 << 20
	var link := Link.new(ends[0], ends[1])
	link.delay = 0.025
	link.bandwidth = 1 << 20
	var res := _collect(ends[1])
	ends[1].want(f.hash)
	var start := link.now
	assert_bool(await _run(link, func() -> bool: return res.got.has(f.hash), 20.0)).is_true()
	var took := link.now - start
	assert_float(took).is_less(4.5)
	assert_bool(res.got[f.hash] == f.bytes).is_true()


func test_resume_after_a_break() -> void:
	var ends := _ends()
	var f := _file("resume.bin", 600_000)
	ends[0].index.add_file(f.path)
	var link := Link.new(ends[0], ends[1])
	var res := _collect(ends[1])
	ends[1].want(f.hash)
	await _run(link, _part_over.bind(f.hash, 200_000))
	# The connection drops; a new one asks again and starts where it was.
	ends[1].close()
	var again := _ends()
	again[0].index.add_file(f.path)
	var link2 := Link.new(again[0], again[1])
	var res2 := _collect(again[1])
	var asked := []
	again[1].send_control = _spy.bind(again[1].send_control, asked)
	again[1].want(f.hash)
	assert_bool(await _run(link2, func() -> bool: return res2.got.has(f.hash))).is_true()
	assert_int(asked[0]).is_greater(100)
	assert_bool(res2.got[f.hash] == f.bytes).is_true()
	assert_bool(FileAccess.file_exists(ContentStore.part_path(f.hash))).is_false()
	assert_dict(res.got).is_empty()


func test_size_cap_unknown_and_corrupt() -> void:
	var ends := _ends()
	var f := _file("capped.bin", 200_000)
	ends[0].index.add_file(f.path)
	var link := Link.new(ends[0], ends[1])
	var res := _collect(ends[1])
	ends[1].want(f.hash, 0, 100_000)
	var unknown := "sha256:" + "0".repeat(64)
	ends[1].want(unknown)
	assert_bool(await _run(link, func() -> bool: return res.failed.size() == 2)).is_true()
	assert_str(res.failed[f.hash]).is_equal("Too large")
	assert_str(res.failed[unknown]).is_equal("Not found")
	# A flipped byte on the way: the finished file doesn't hash right.
	link.tamper = _flip_chunk_3
	ends[1].want(f.hash)
	assert_bool(await _run(link, func() -> bool: return res.failed.get(f.hash, "") == "Bad data")).is_true()
	assert_bool(res.got.has(f.hash)).is_false()


func test_held_until_the_file_turns_up() -> void:
	var ends := _ends()
	ends[0].hold_unknown_s = 30.0
	var f := _file("later.bin", 50_000)
	var link := Link.new(ends[0], ends[1])
	var res := _collect(ends[1])
	ends[1].want(f.hash)
	await _run(link, func() -> bool: return false, 1.0)
	assert_dict(res.failed).is_empty()
	ends[0].index.add_file(f.path)
	ends[0].index_changed()
	assert_bool(await _run(link, func() -> bool: return res.got.has(f.hash))).is_true()


func test_cache_takes_only_listed_files() -> void:
	var car := "res://content/cars/noss_box"
	var source := PackageSource.open(car, PackageLoader.DEFAULT_LIMITS)
	var manifest_bytes := source.read("manifest.json")
	var car_hash := "sha256:" + PlatformLoader.sha256_hex(manifest_bytes)
	# Nothing before the manifest; then only files with the manifest's hashes.
	assert_str(ContentStore.put_car_file(car_hash, "fit.json", source.read("fit.json"))).is_equal("Not in the manifest")
	assert_str(ContentStore.put_car_file(car_hash, "manifest.json", source.read("fit.json"))).is_equal("Hash mismatch")
	assert_str(ContentStore.put_car_file(car_hash, "manifest.json", manifest_bytes)).is_empty()
	assert_str(ContentStore.put_car_file(car_hash, "fit.json", source.read("paint.json"))).is_equal("Hash mismatch")
	assert_str(ContentStore.put_car_file(car_hash, "../evil.json", source.read("fit.json"))).is_equal("Bad name")
	var tiers := ContentStore.tiers(ContentStore.car_manifest(car_hash))
	assert_array(Array(tiers.data)).contains_exactly(["manifest.json", "fit.json", "paint.json", "sound/profile.json"])
	assert_array(Array(tiers.preview)).contains_exactly(["model/body.glb"])
	for rel in tiers.data:
		assert_str(ContentStore.put_car_file(car_hash, rel, source.read(rel))).is_empty()
	assert_array(Array(ContentStore.car_missing(car_hash, tiers.data))).is_empty()
	assert_array(Array(ContentStore.car_missing(car_hash, tiers.preview))).contains_exactly(["model/body.glb"])
	source.close()
	# Platforms and tracks.
	var track := FileAccess.get_file_as_bytes("res://content/tracks/proving_ground/track.json")
	var th := "sha256:" + PlatformLoader.sha256_hex(track)
	assert_str(ContentStore.put_file("tracks", th, track)).is_empty()
	assert_bool(ContentStore.has_file("tracks", th)).is_true()
	assert_str(ContentStore.put_file("tracks", "sha256:" + "1".repeat(64), track)).is_equal("Hash mismatch")
	assert_int(ContentStore.size_bytes()).is_greater(track.size())
