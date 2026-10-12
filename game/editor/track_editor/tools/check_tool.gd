extends EditorTool
## The Check tool (EDT-07): what TrackValidator found, errors first. Each problem is a button that
## shows where it is. Errors stop the track being saved to your tracks or raced online; the
## draft is still autosaved.

const MARKS := { "error": "✖ Error", "warning": "▲ Warning", "info": "● Note" }


func title() -> String:
	return "Check"


func hint() -> String:
	return "Pick a problem to see where it is"


func analysed() -> void:
	if editor.tool == self:
		editor.refresh_panel()


func draft_changed(_what: StringName) -> void:
	pass # the list comes again when the checks have run (analysed)


func panel() -> Array:
	var a: Dictionary = editor.analysis
	var fresh: bool = a.get("stamp", -1) == editor._changes and a.has("problems")
	if not a.has("problems"):
		return [UiKit.label("Checking…", 24)]
	var found: Array = a.problems
	var counts := {}
	for p: Dictionary in found:
		counts[p.level] = int(counts.get(p.level, 0)) + 1
	var summary := "No problems"
	if not found.is_empty():
		var parts := []
		for level: String in ["error", "warning", "info"]:
			if counts.has(level):
				parts.append("%d %s%s" % [counts[level], {"error": "error", "warning": "warning", "info": "note"}[level], "" if counts[level] == 1 else "s"])
		summary = ", ".join(parts)
	var out := [UiKit.label(summary + ("" if fresh else " (checking…)"), 26)]
	for p: Dictionary in found:
		var text := "%s: %s" % [MARKS.get(p.level, p.level), p.text]
		var b := UiKit.button(text, _show.bind(p), "Show where" if p.point != null else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.add_theme_color_override("font_color", view.gizmos.colors.get({"error": "bad", "warning": "warn"}.get(p.level, ""), Color.WHITE))
		out.append(b)
	if counts.has("error"):
		var note := UiKit.label("Errors stop saving to your tracks and racing online. Autosave still works.", 20)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		out.append(note)
	out.append(UiKit.button("Check now", func() -> void: editor._analyse_in = 0.0, "Run the checks again"))
	return out


func _show(p: Dictionary) -> void:
	editor.say(String(p.text))
	if p.point is Vector3:
		view.camera.focus(p.point, 120.0)
