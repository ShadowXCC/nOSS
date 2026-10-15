class_name Siren
extends Node
## A police car's siren (D115, D116), synthesized (NossAudio.render_siren): a wail, switching to
## a yelp once it's within YELP_M of whoever hears it here, pitched by the Doppler effect as it
## passes. It sounds while its car's `siren` is on (its own game's, or from its states online).

const YELP_M := 80.0

static var _streams := {} # "wail" / "yelp" -> AudioStreamWAV

var vehicle: Vehicle
var _player: AudioStreamPlayer3D
var _tone := ""


func _ready() -> void:
	_player = AudioStreamPlayer3D.new()
	_player.name = "SirenSound"
	_player.bus = &"Effects"
	_player.unit_size = 25.0
	_player.max_distance = 900.0
	_player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	vehicle.add_child(_player)


func _process(_delta: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.siren:
		if _player and _player.playing:
			_player.stop()
		_tone = ""
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var near := cam != null and cam.global_position.distance_to(vehicle.global_position) < YELP_M
	var tone := "yelp" if near else "wail"
	if tone != _tone:
		_tone = tone
		_player.stream = stream(tone)
		_player.play()
	elif not _player.playing:
		_player.play()


## The siren's loop for `tone` ("wail" or "yelp"), made once.
static func stream(tone: String) -> AudioStreamWAV:
	if not _streams.has(tone):
		_streams[tone] = EngineSound._wav(NossAudio.render_siren(tone))
	return _streams[tone]


## A light bar and a siren for `v` if its model is a police car's (tagged "police"); a new
## model (mount) gets a new bar.
static func fit(v: Vehicle) -> void:
	var old := v.get_node_or_null(^"LightBar")
	if old:
		v.remove_child(old)
		old.queue_free()
	if v.package == null or "police" not in v.package.manifest.get("tags", []):
		return
	var bar := LightBar.new()
	bar.name = "LightBar"
	if bar.setup(v):
		v.add_child(bar)
	else:
		bar.free()
	if v.has_node(^"Siren"):
		return
	var siren := Siren.new()
	siren.name = "Siren"
	siren.vehicle = v
	v.add_child(siren)
