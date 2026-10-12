class_name EditHistory
extends RefCounted
## Undo and redo for the track editor (EDT-06, D96): Godot's UndoRedo, kept by the draft so it
## lasts through test drives. Each action is a pair of callables; a brush stroke is applied as it
## goes and recorded once it ends (execute = false).

const MAX_STEPS := 1000

var _undo := UndoRedo.new()


func _init() -> void:
	_undo.max_steps = MAX_STEPS


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_undo):
		_undo.free()


## Records (and, unless `execute` is off, does) an action named `name`.
func act(name: String, do_fn: Callable, undo_fn: Callable, execute := true) -> void:
	_undo.create_action(name)
	_undo.add_do_method(do_fn)
	_undo.add_undo_method(undo_fn)
	_undo.commit_action(execute)


func can_undo() -> bool:
	return _undo.has_undo()


func can_redo() -> bool:
	return _undo.has_redo()


## Undoes the last action; its name ("" if there was none).
func undo_last() -> String:
	if not _undo.has_undo():
		return ""
	var name := _undo.get_current_action_name()
	_undo.undo()
	return name


## Redoes the next action; its name ("" if there was none).
func redo_next() -> String:
	if not _undo.has_redo():
		return ""
	_undo.redo()
	return _undo.get_current_action_name()


## Changes with every action, undo and redo (to know if there's anything to save).
func version() -> int:
	return _undo.get_version()


func clear() -> void:
	_undo.clear_history()
