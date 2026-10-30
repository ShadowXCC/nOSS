extends GdUnitTestSuite
## Liveries online (docs/NETWORKING.md §7, D242), over real ENet: a player's livery travels on
## its own when they pick a car and goes in the roster once the server has it and it checks out;
## a hostile one (it changes when cleaned, or is too big) never does; the host's Custom liveries
## switch keeps them off; a remote car wears the roster's livery, or a built-in's stock one.

const BOX := "res://content/cars/noss_box"

var port := 0
var server: NetServer
var host: NetHost
var server_content: NetContent
var client: NetClient
var client_content: NetContent
var dir := "user://tests/net_livery/"


func before() -> void:
	Settings.use_folder("user://tests/net_livery")
	ContentStore.root = dir.path_join("cache")
	DirAccess.make_dir_recursive_absolute(dir)


func after() -> void:
	ContentStore.root = "user://cache/content/"
	Settings.use_folder("user://")


func before_test() -> void:
	ContentStore.clear()
	NetTransfer.clear_blobs()
	port = 47900 + randi() % 90


func after_test() -> void:
	for n: Variant in [client_content, server_content, host, client]:
		if is_instance_valid(n):
			(n as Node).free()
	if is_instance_valid(server):
		server.stop()
		server.free()


func _start(cfg := ServerConfig.defaults()) -> void:
	cfg.port = port
	cfg.lan = false
	server = NetServer.new()
	server.manual_poll = true
	add_child(server)
	assert_int(server.start(cfg, NetIdentity.throwaway(), [{ "name": "Host", "color": "00ff00" }])).is_equal(OK)
	server_content = NetContent.new()
	server_content.setup(true, func(peer: int, type: int, d: Dictionary) -> void: server.send(peer, type, d),
		func(peer: int, bytes: PackedByteArray) -> void: server.send_raw(peer, bytes, NetProtocol.CH_CONTENT))
	server_content._local = {}
	server_content._local_scanned = true
	server_content.set_physics_process(false)
	add_child(server_content)
	server.raw.connect(func(peer: int, bytes: PackedByteArray) -> void: server_content.handle_raw(peer, bytes))
	host = NetHost.new(server)
	host.content = server_content
	host.set_physics_process(false)
	add_child(host)
	client = NetClient.new()
	client.manual_poll = true
	add_child(client)
	client_content = NetContent.new()
	client_content.setup(false, func(_peer: int, type: int, d: Dictionary) -> void: client.send(type, d),
		func(_peer: int, bytes: PackedByteArray) -> void: client.send_raw(bytes, NetProtocol.CH_CONTENT))
	client_content._local = {}
	client_content._local_scanned = true
	client_content.set_physics_process(false)
	add_child(client_content)
	client.raw.connect(func(bytes: PackedByteArray) -> void: client_content.handle_raw(1, bytes))
	client.message.connect(func(type: int, d: Dictionary) -> void: client_content.handle_control(1, type, d))
	client.join("127.0.0.1", port, [{ "name": "Ann", "color": "ff0000" }], "", NetIdentity.throwaway())


func _pump(done: Callable, seconds := 8.0) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		server.poll()
		host._physics_process(0.0)
		client.poll()
		server_content._physics_process(1.0 / 120.0)
		client_content._physics_process(1.0 / 120.0)
		await get_tree().process_frame
		if done.call():
			return true
	return false


## The client offers `bytes` from a file of its own (not the cache both sides share here) and
## picks the box with it; returns its hash.
func _pick_with(bytes: PackedByteArray) -> String:
	var path := dir.path_join("mine_%d.json" % randi())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var h := client_content.share_file(path)
	client.send(NetProtocol.Msg.PICK, { "player": client.player_ids()[0], "car": Net.package_hash(BOX), "bytes": 1000,
		"car_name": "nOSS Box", "family": "car", "livery": h })
	return h


func _livery(layers := 3) -> Dictionary:
	var l := LiveryData.new_livery("Online")
	for i in layers:
		l.layers.append(LiveryData.new_layer("shape", Vector3(0.9, 0.5, i * 0.3), Vector3.RIGHT, Vector3.FORWARD, Vector2(0.5, 0.5), "star"))
	return LiveryData.clean(l)


func test_a_picked_livery_reaches_the_roster() -> void:
	_start()
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	var h := _pick_with(LiveryStore.net_blob(_livery()))
	var id: int = client.player_ids()[0]
	assert_bool(await _pump(func() -> bool: return server.players[id].livery == h)).is_true()
	assert_str(String(host.roster().filter(func(d: Dictionary) -> bool: return d.id == id)[0].livery)).is_equal(h)
	assert_int(NetContent.cached_livery(h).layers.size()).is_equal(3)
	# Passed on: anyone can fetch it from the server now.
	assert_bool(server_content.index.has(h)).is_true()


## A livery that isn't what it says (cleaning changes it) shows as plain paint; one over 64 KB
## never arrives.
func test_a_hostile_livery_is_dropped() -> void:
	_start()
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	var id: int = client.player_ids()[0]
	var dirty := _livery()
	dirty["script"] = "evil()"
	(dirty.layers[0] as Dictionary).at = [1e30, 0, 0]
	var h := _pick_with(JSON.stringify(dirty, "", true).to_utf8_buffer())
	assert_bool(await _pump(func() -> bool: return ContentStore.has_file("liveries", h))).is_true()
	await _pump(func() -> bool: return false, 0.5)
	assert_str(server.players[id].livery).is_empty()
	assert_dict(NetContent.cached_livery(h)).is_empty()
	var huge := _livery()
	huge.name = "x".repeat(10)
	var bytes := LiveryData.to_bytes(huge)
	bytes.append_array(" ".repeat(LiveryData.MAX_NET_BYTES).to_utf8_buffer())
	var big := _pick_with(bytes)
	await _pump(func() -> bool: return false, 2.0)
	assert_bool(ContentStore.has_file("liveries", big)).is_false()
	assert_str(server.players[id].livery).is_empty()


## The host's Custom liveries off: none go in the roster, and none are fetched.
func test_custom_liveries_off() -> void:
	var cfg := ServerConfig.defaults()
	cfg.caps.custom_liveries = false
	_start(cfg)
	assert_bool(await _pump(func() -> bool: return client.state == NetClient.State.JOINED)).is_true()
	var id: int = client.player_ids()[0]
	var h := _pick_with(LiveryStore.net_blob(_livery()))
	await _pump(func() -> bool: return false, 1.5)
	assert_str(server.players[id].livery).is_empty()
	assert_bool(ContentStore.has_file("liveries", h)).is_false()
	assert_bool(host.lobby_dict().rules.custom_liveries).is_false()
	assert_bool(host.rules_dict().custom_liveries).is_false()


## A remote car wears the roster's livery once it's here (plain until then); a built-in always
## wears its stock one.
func test_remote_cars_wear_the_roster_livery() -> void:
	var l := _livery()
	var blob := LiveryStore.net_blob(l)
	var h := "sha256:" + PlatformLoader.sha256_hex(blob)
	var platform := PlatformLoader.load_official("official.track.gt")
	var copy := GarageFiles.copy_car(BOX)
	var r := NetRacer.new()
	r.vehicle = Vehicle.create(platform, PackageLoader.load_package(copy.path))
	add_child(r.vehicle)
	r.livery_hash = h
	r.redress()
	assert_dict(r.vehicle.visual.livery).is_empty() # not here yet
	ContentStore.put_file("liveries", h, blob)
	r.redress()
	assert_str(String(r.vehicle.visual.livery.id)).is_equal(String(l.id))
	r.vehicle.mount(PackageLoader.load_package(BOX))
	r.redress()
	assert_str(String(r.vehicle.visual.livery.id)).is_equal(String(LiveryStore.builtin("6e0c6a51-5d0f-4a2b-9a52-3b1f0d7c2e11").id))
	r.vehicle.free()
	r.free()
	GarageFiles.delete(copy.path)
