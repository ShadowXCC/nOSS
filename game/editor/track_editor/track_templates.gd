class_name TrackTemplates
extends RefCounted
## Tracks to start from (docs/TRACK_EDITOR.md §2): an empty field, or a ready road to change.

## [[id, name]] for menus.
static func list() -> Array:
	return [["empty", "Empty"]]


static func make(id: String) -> TrackDraft:
	match id:
		_:
			return TrackDraft.blank()
