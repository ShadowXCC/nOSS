class_name AudioMix
extends RefCounted
## Volume groups and mono audio (ACC-05, docs/ACCESSIBILITY.md §3). Each group is a bus made at
## run time; car sounds sit under "Cars", which splitscreen turns down by 1/√views, so the
## player's volumes multiply with it. Speech (spotter, narration) doesn't go through buses:
## its volume is given to the text-to-speech call. One output, so these are machine settings.

## Settings key -> bus. Engines, tires and wind are car sounds.
const GROUPS := {
	"vol_own_engine": &"OwnEngines",
	"vol_other_engines": &"OtherEngines",
	"vol_tires": &"Tires",
	"vol_effects": &"Effects",
	"vol_ambience": &"Ambience",
	"vol_music": &"Music",
	"vol_ui": &"UI",
}
const CAR_GROUPS := [&"OwnEngines", &"OtherEngines", &"Tires"]
const CARS := &"Cars"


## Index of `bus`, made if needed (car groups under Cars, the rest under Master).
static func bus(name: StringName) -> int:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		return i
	var parent := &"Master"
	if name in CAR_GROUPS:
		parent = CARS
		bus(CARS)
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, parent)
	return i


## Applies the volumes and mono from Settings.
static func apply() -> void:
	for key: String in GROUPS:
		AudioServer.set_bus_volume_db(bus(GROUPS[key]), linear_to_db(maxf(float(Settings.get(key)), 0.0001)))
	_set_mono(Settings.mono)


## Splitscreen: with n views listening, car sound is scaled by 1/√n (docs/ARCHITECTURE.md §6).
static func set_listeners(n: int) -> void:
	AudioServer.set_bus_volume_db(bus(CARS), linear_to_db(1.0 / sqrt(maxf(float(n), 1.0))))


## Mono: a stereo enhancer with no side signal on Master folds everything to the middle.
static func _set_mono(on: bool) -> void:
	var master := AudioServer.get_bus_index(&"Master")
	var at := -1
	for k in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, k) is AudioEffectStereoEnhance:
			at = k
	if at < 0:
		var fx := AudioEffectStereoEnhance.new()
		fx.pan_pullout = 0.0
		AudioServer.add_bus_effect(master, fx)
		at = AudioServer.get_bus_effect_count(master) - 1
	AudioServer.set_bus_effect_enabled(master, at, on)


## Speech volume for tts_speak, 0-100.
static func speech_volume(key: String) -> int:
	return roundi(clampf(float(Settings.get(key)), 0.0, 1.0) * float(Settings.master_volume) * 100.0)
