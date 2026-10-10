extends SceneTree
## Compiles every GDScript under res://game and res://tests and reports failures.
##   tools/godot.sh --headless -s res://tools/check_scripts.gd


var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true # autoload names exist from the first frame on
	var failed := 0
	var count := 0
	for root in ["res://game", "res://tests/game"]:
		for path in _scripts(root):
			count += 1
			var script := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
			if script == null or not script.can_instantiate():
				failed += 1
				print("FAIL ", path)
	print("%d scripts, %d failed" % [count, failed])
	quit(1 if failed else 0)
	return false


func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
