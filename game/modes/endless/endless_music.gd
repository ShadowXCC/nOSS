class_name EndlessMusic
extends Node
## Music for the endless road (D157, docs/ART_AUDIO.md §7) on the Music bus: your own OGG and MP3
## files from the music folder (user://music/), shuffled, if there are any; otherwise original
## ambient pieces made from the road's seed (NossAudio.render_music), each played twice, then the
## next fades in.

const DIR := "user://music/"
const FADE_S := 6.0
const REPEATS := 2

var seed_base := 1
var _files := PackedStringArray()
var _players: Array[AudioStreamPlayer] = []
var _current := 0
var _index := 0
var _elapsed := 0.0
var _task := -1
var _next: AudioStreamWAV
var _next_stream: Array = [] # [stream] made on a worker
var _fading := 0.0


func _ready() -> void:
	name = "EndlessMusic"
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		p.volume_db = -80.0
		p.finished.connect(_on_finished.bind(i))
		add_child(p)
		_players.append(p)
	_files = own_files()
	if _files.is_empty():
		_make(seed_base)
	else:
		var list := Array(_files)
		list.shuffle()
		_files = PackedStringArray(list)
		_play(_load_file(_files[0]))


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


## Music files in the music folder.
static func own_files() -> PackedStringArray:
	var out := PackedStringArray()
	if not DirAccess.dir_exists_absolute(DIR):
		return out
	for f in DirAccess.get_files_at(DIR):
		if f.get_extension().to_lower() in ["ogg", "mp3"]:
			out.append(DIR.path_join(f))
	return out


func _load_file(path: String) -> AudioStream:
	if path.get_extension().to_lower() == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	var mp3 := AudioStreamMP3.new()
	mp3.data = FileAccess.get_file_as_bytes(path)
	return mp3


## A piece from `seed_value`, made on a worker.
func _make(seed_value: int) -> void:
	_next_stream.clear()
	_task = WorkerThreadPool.add_task(func() -> void:
		var wav := EngineSound._wav(NossAudio.render_music(seed_value), true)
		_next_stream.append(wav), false, "Endless music")


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_next = _next_stream[0] if not _next_stream.is_empty() else null
		if _next and not _players[_current].playing: # the first piece
			_play(_next)
			_next = null
			_index += 1
			_make(seed_base + _index)
	if not _files.is_empty():
		return
	# Generated pieces loop; after REPEATS plays the next one fades in.
	var p := _players[_current]
	if p.playing and p.stream:
		_elapsed += delta
		if _elapsed > REPEATS * p.stream.get_length() - FADE_S and _next and _fading <= 0.0:
			_current = 1 - _current
			_play(_next, false)
			_next = null
			_index += 1
			_make(seed_base + _index)
	if _fading > 0.0:
		_fading = maxf(_fading - delta, 0.0)
		var t := 1.0 - _fading / FADE_S
		_players[_current].volume_db = linear_to_db(maxf(t, 0.001))
		_players[1 - _current].volume_db = linear_to_db(maxf(1.0 - t, 0.001))
		if _fading <= 0.0:
			_players[1 - _current].stop()


func _play(stream: AudioStream, loud := true) -> void:
	var p := _players[_current]
	p.stream = stream
	p.volume_db = 0.0 if loud else -80.0
	p.play()
	_elapsed = 0.0
	if not loud:
		_fading = FADE_S


## A file ended: the next one. A generated piece loops, so it never ends; its plays are counted.
func _on_finished(i: int) -> void:
	if i != _current or _files.is_empty():
		return
	_index = (_index + 1) % _files.size()
	_play(_load_file(_files[_index]))
