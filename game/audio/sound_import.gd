class_name SoundImport
extends RefCounted
## Own engine recordings (AV-06, docs/VEHICLE_PACKAGE.md §6, D88): OGG Vorbis or 16-bit PCM WAV,
## mono, 44.1 or 48 kHz, made into seamless loops outside the game (Audacity and the like). Each
## file's header is checked before Godot decodes it, so a bad file never reaches the decoder.

const RATES := [44100, 48000]
const TYPES := ["ogg", "wav"]
## A loop longer than this is surely not one.
const MAX_SECONDS := 20.0


## {ok, error, kind, rate, channels, seconds} for a file's bytes; `ext` is "ogg" or "wav".
static func inspect(bytes: PackedByteArray, ext: String) -> Dictionary:
	var out := { "ok": false, "error": "", "kind": ext.to_lower(), "rate": 0, "channels": 0, "seconds": 0.0 }
	match out.kind:
		"wav":
			_inspect_wav(bytes, out)
		"ogg":
			_inspect_ogg(bytes, out)
		_:
			out.error = "Use OGG or WAV"
			return out
	if out.error:
		return out
	if out.channels != 1:
		out.error = "Use mono"
	elif out.rate not in RATES:
		out.error = "Use 44.1 or 48 kHz"
	elif out.seconds > MAX_SECONDS:
		out.error = "Too long for a loop"
	out.ok = out.error.is_empty()
	return out


## A looping stream from a checked file, or null.
static func stream(bytes: PackedByteArray, ext: String, loop := true) -> AudioStream:
	var info := inspect(bytes, ext)
	if not info.ok:
		return null
	if info.kind == "wav":
		var wav := AudioStreamWAV.load_from_buffer(bytes, {})
		if wav and loop:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / 2
		return wav
	var ogg := AudioStreamOggVorbis.load_from_buffer(bytes)
	if ogg:
		ogg.loop = loop
	return ogg


static func _inspect_wav(b: PackedByteArray, out: Dictionary) -> void:
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF" or b.slice(8, 12).get_string_from_ascii() != "WAVE":
		out.error = "Not a WAV file"
		return
	var at := 12
	var bits := 0
	var data_size := -1
	while at + 8 <= b.size():
		var id := b.slice(at, at + 4).get_string_from_ascii()
		var size := b.decode_u32(at + 4)
		var body := at + 8
		if id == "fmt " and size >= 16 and body + 16 <= b.size():
			if b.decode_u16(body) != 1:
				out.error = "Use plain 16-bit PCM WAV"
				return
			out.channels = b.decode_u16(body + 2)
			out.rate = b.decode_u32(body + 4)
			bits = b.decode_u16(body + 14)
		elif id == "data":
			data_size = mini(size, b.size() - body)
			break
		at = body + size + (size & 1)
	if bits != 16:
		out.error = "Use 16-bit WAV"
	elif data_size <= 0 or out.rate <= 0 or out.channels <= 0:
		out.error = "WAV without sound"
	else:
		out.seconds = float(data_size) / (out.rate * out.channels * 2)


static func _inspect_ogg(b: PackedByteArray, out: Dictionary) -> void:
	# The first page holds the Vorbis identification header: 0x01 "vorbis", version, channels, rate.
	if b.size() < 58 or b.slice(0, 4).get_string_from_ascii() != "OggS":
		out.error = "Not an OGG file"
		return
	var segments := b[26]
	var body := 27 + segments
	if body + 16 > b.size() or b[body] != 1 or b.slice(body + 1, body + 7).get_string_from_ascii() != "vorbis":
		out.error = "Use OGG Vorbis"
		return
	out.channels = b[body + 11]
	out.rate = b.decode_u32(body + 12)
	# The length: the last page's granule position, in samples.
	var last := b.size() - 4
	while last > 0 and b.slice(last, last + 4).get_string_from_ascii() != "OggS":
		last -= 1
	var granule := b.decode_s64(last + 6) if last + 14 <= b.size() else 0
	out.seconds = float(granule) / out.rate if out.rate > 0 and granule > 0 else 0.0
