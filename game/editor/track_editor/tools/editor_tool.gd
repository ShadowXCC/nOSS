class_name EditorTool
extends RefCounted
## One of the track editor's tools (Road, Terrain, Paint, Props, Race, Check, File): its panel,
## what it does with the view's pointer and shortcuts, and what it draws.

var editor: TrackEditor
var draft: TrackDraft
var view: EditorView


## The tab's name.
func title() -> String:
	return ""


## Whether the tool works on this draft (Terrain and Paint need terrain; Surfaces, a scene).
func available() -> bool:
	return true


## The panel's controls, top to bottom (rebuilt by editor.refresh_panel()).
func panel() -> Array:
	return []


func activate() -> void:
	pass


func deactivate() -> void:
	view.gizmos.show_brush(Vector3.ZERO, 0.0, Callable())


## A view pointer event (EditorView.pointer).
func pointer(_e: Dictionary) -> void:
	pass


## Every frame while the tool is in use (brushes).
func tick(_delta: float) -> void:
	pass


## A shortcut from the view; true if this tool used it.
func action(_name: String) -> bool:
	return false


## The draft changed (also after undo and redo).
func draft_changed(_what: StringName) -> void:
	pass


## A text field is being typed in: panels wait for it to finish before they're built again.
func typing() -> bool:
	var owner := editor.get_viewport().gui_get_focus_owner() if editor.is_inside_tree() else null
	return owner is LineEdit and (owner as LineEdit).is_editing()


## The AI line and the checks are new (editor.analysis).
func analysed() -> void:
	pass


## Redraws the editor's gizmos for this tool.
func refresh_gizmos() -> void:
	view.gizmos.show_track(draft.track(), draft.points())


## A short line for the key-hint bar.
func hint() -> String:
	return ""
