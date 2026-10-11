extends Node
## Built-in narration (autoload "Narrator", ACC-03, docs/ACCESSIBILITY.md §2): reads menus and
## race events aloud through the OS text-to-speech. Menus are read only when no screen reader
## is running (it reads them itself). Spoken race events are also shown as captions by the
## player's HUD, so nothing is voice-only. Without a voice (no speech-dispatcher on Linux),
## captions still work.

## A screen that reads itself out (first boot) forces menu narration while it's up.
var force_menus := false

var _voice := ""
var _available := false
var _last := ""
var _last_time := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" or not ProjectSettings.get_setting("audio/general/text_to_speech", false):
		return
	# The system's language and region first ("en-US"), then its language, then English, then any.
	var all := DisplayServer.tts_get_voices()
	if Game.dev.has("voices"):
		for v: Dictionary in all:
			print(v)
	var locale := OS.get_locale().replace("_", "-").to_lower()
	var lang := locale.get_slice("-", 0)
	var pick: Dictionary = {}
	# Voice languages look like "en-US_none" (variant after the underscore).
	var lang_of := func(v: Dictionary) -> String: return String(v.get("language", "")).get_slice("_", 0).to_lower()
	for test: Callable in [
			func(v: Dictionary) -> bool: return lang_of.call(v) == locale,
			func(v: Dictionary) -> bool: return lang_of.call(v).begins_with(lang),
			func(v: Dictionary) -> bool: return lang_of.call(v).begins_with("en"),
			func(_v: Dictionary) -> bool: return true]:
		var found := all.filter(test)
		if not found.is_empty():
			pick = found[0]
			break
	_available = not pick.is_empty()
	_voice = String(pick.get("id", ""))
	print("Speech: %s" % (String(pick.get("name", _voice)) if _available else "none (captions only)"))
	watch(get_viewport(), null)


func available() -> bool:
	return _available


func screen_reader_running() -> bool:
	return DisplayServer.get_name() != "headless" and DisplayServer.accessibility_screen_reader_active() == 1


## Speaks `text` now, cutting off what was being said. `volume_key` is a Settings volume.
func say(text: String, volume_key := "vol_narration", rate := 1.0) -> void:
	if not _available or text.is_empty():
		return
	# The same line twice in a row within a second (focus bouncing) is said once.
	var now := Time.get_ticks_msec()
	if text == _last and now - _last_time < 1000:
		return
	_last = text
	_last_time = now
	DisplayServer.tts_speak(text, _voice, AudioMix.speech_volume(volume_key), 1.0, clampf(rate, 0.5, 2.0), 0, true)


func stop() -> void:
	if _available:
		DisplayServer.tts_stop()


## Reads `viewport`'s focused control as it changes, when `profile`'s narration is on (null:
## the primary player's, for shared menus).
func watch(viewport: Viewport, profile: PlayerProfile) -> void:
	viewport.gui_focus_changed.connect(func(c: Control) -> void:
		var p := profile if profile else Settings.primary
		if menus_on(p):
			say(describe(c), "vol_narration", float(p.data.get("narration_rate", 1.0)) if p else 1.0))


## Menu narration for this player: on unless it's off or a screen reader is reading.
func menus_on(profile: PlayerProfile) -> bool:
	if screen_reader_running():
		return false
	return force_menus or (profile != null and String(profile.data.get("narration", "off")) != "off")


## Race events for this player ("P3", "Final lap").
func race_on(profile: PlayerProfile) -> bool:
	return profile != null and String(profile.data.get("narration", "off")) == "race"


## What a control says: its name, its state or value, then its description.
static func describe(c: Control) -> String:
	var text := String(c.accessibility_name)
	if text.is_empty() and "text" in c:
		text = String(c.get("text"))
	if c is CheckButton or c is CheckBox:
		text += ", on" if (c as BaseButton).button_pressed else ", off"
	elif c is Range and not text.contains(":"):
		text += ", %s" % str((c as Range).value)
	var desc := String(c.accessibility_description)
	return text + (". " + desc if desc and not desc.begins_with("Left and right") else "")
