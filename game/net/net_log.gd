class_name NetLog
extends RefCounted
## Server log (docs/NETWORKING.md §9): each line goes to stdout and, once opened, to a file in
## user://logs/.

static var _file: FileAccess


static func open(path := "user://logs/server.log") -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_file = FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if _file:
		_file.seek_end()


static func close() -> void:
	_file = null


static func line(text: String) -> void:
	var stamped := "%s %s" % [Time.get_datetime_string_from_system(false, true), text]
	print(stamped)
	if _file:
		_file.store_line(stamped)
		_file.flush()
