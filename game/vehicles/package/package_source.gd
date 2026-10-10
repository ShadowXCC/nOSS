class_name PackageSource
extends RefCounted
## Read access to one package: a .noss zip, or an unpacked folder (official content in
## res://content/). Zip directories are checked by noss_core before anything is decompressed.

var path := ""
var error := ""
var _zip: ZIPReader
var _files := {} # relative path -> uncompressed size


## Opens a package. Check `error` afterwards; it's empty on success.
static func open(p_path: String, limits: Dictionary) -> PackageSource:
	var source := PackageSource.new()
	source.path = p_path
	if DirAccess.dir_exists_absolute(p_path):
		source._open_dir(p_path, "")
	else:
		source._open_zip(limits)
	return source


func files() -> PackedStringArray:
	return PackedStringArray(_files.keys())


func has(rel: String) -> bool:
	return _files.has(rel)


func size_of(rel: String) -> int:
	return _files.get(rel, 0)


func read(rel: String) -> PackedByteArray:
	if not _files.has(rel):
		return PackedByteArray()
	if _zip:
		return _zip.read_file(rel)
	return FileAccess.get_file_as_bytes(path.path_join(rel))


func close() -> void:
	if _zip:
		_zip.close()
		_zip = null


func _open_zip(limits: Dictionary) -> void:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		error = "Can't read package"
		return
	var index: Dictionary = NossPackage.inspect_zip(bytes, limits)
	if not index.ok:
		error = index.error
		return
	for entry: Dictionary in index.entries:
		_files[entry.name] = entry.size
	_zip = ZIPReader.new()
	if _zip.open(path) != OK:
		error = "Can't open package"
		_zip = null


func _open_dir(root: String, rel: String) -> void:
	var dir := root.path_join(rel)
	for file in DirAccess.get_files_at(dir):
		var child := rel.path_join(file) if rel else file
		if file.ends_with(".import") or file.ends_with(".uid"):
			continue # editor metadata next to official content
		if not NossPackage.is_safe_path(child):
			error = "File not allowed: " + child
			return
		var f := FileAccess.open(root.path_join(child), FileAccess.READ)
		_files[child] = f.get_length() if f else 0
	for sub in DirAccess.get_directories_at(dir):
		_open_dir(root, rel.path_join(sub) if rel else sub)
