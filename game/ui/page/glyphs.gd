class_name Glyphs
extends RefCounted
## Button glyphs for prompts (docs/UI_FLOW.md §10.2): Kenney's Input Prompts (CC0) in
## content/ui/prompts/<family>/<id>.png, for three families: "keyboard", "xbox" and "playstation".
## An input is {id, text}: the glyph's id, and its name for a text chip when there's no glyph
## (a wheel's "Button 3", or a missing file) and for screen readers.

const DIR := "res://content/ui/prompts/"
const FAMILIES := ["keyboard", "xbox", "playstation"]
## What a prompt is for, and the menu actions behind it in a player's view.
const ACTIONS := {
	"confirm": ["menu_confirm"],
	"cancel": ["menu_cancel"],
	"change": ["menu_left", "menu_right"],
	"tabs": ["menu_tab_prev", "menu_tab_next"],
}
## The main window's inputs (Godot's ui_* actions, Bindings.apply()), by family.
const WINDOW := {
	"keyboard": { "confirm": ["enter"], "cancel": ["escape"], "change": ["arrows"], "tabs": ["q", "e"] },
	"xbox": { "confirm": ["a"], "cancel": ["b"], "change": ["dpad"], "tabs": ["lb", "rb"] },
	"playstation": { "confirm": ["cross"], "cancel": ["circle"], "change": ["dpad"], "tabs": ["l1", "r1"] },
}
## Gamepad buttons: [xbox id, playstation id].
const PAD := {
	JOY_BUTTON_A: ["a", "cross"], JOY_BUTTON_B: ["b", "circle"], JOY_BUTTON_X: ["x", "square"],
	JOY_BUTTON_Y: ["y", "triangle"], JOY_BUTTON_LEFT_SHOULDER: ["lb", "l1"],
	JOY_BUTTON_RIGHT_SHOULDER: ["rb", "r1"], JOY_BUTTON_LEFT_STICK: ["l3", "l3"],
	JOY_BUTTON_RIGHT_STICK: ["r3", "r3"], JOY_BUTTON_BACK: ["view", "share"],
	JOY_BUTTON_START: ["menu", "options"], JOY_BUTTON_DPAD_UP: ["dpad", "dpad"],
	JOY_BUTTON_DPAD_DOWN: ["dpad", "dpad"], JOY_BUTTON_DPAD_LEFT: ["dpad", "dpad"],
	JOY_BUTTON_DPAD_RIGHT: ["dpad", "dpad"],
}
const PAD_AXES := {
	JOY_AXIS_LEFT_X: ["left_stick", "left_stick"], JOY_AXIS_LEFT_Y: ["left_stick", "left_stick"],
	JOY_AXIS_RIGHT_X: ["right_stick", "right_stick"], JOY_AXIS_RIGHT_Y: ["right_stick", "right_stick"],
	JOY_AXIS_TRIGGER_LEFT: ["lt", "l2"], JOY_AXIS_TRIGGER_RIGHT: ["rt", "r2"],
}
const KEYS := {
	KEY_ENTER: "enter", KEY_KP_ENTER: "enter", KEY_SPACE: "space", KEY_ESCAPE: "escape",
	KEY_BACKSPACE: "backspace", KEY_TAB: "tab", KEY_COMMA: "comma", KEY_PERIOD: "period",
	KEY_UP: "arrows", KEY_DOWN: "arrows", KEY_LEFT: "arrows", KEY_RIGHT: "arrows",
}
## Names for ids whose own spelling won't do on a chip.
const NAMES := {
	"enter": "Enter", "space": "Space", "escape": "Esc", "backspace": "Backspace", "tab": "Tab",
	"comma": ",", "period": ".", "arrows": "Arrows", "dpad": "D-pad", "left_stick": "Left stick",
	"right_stick": "Right stick", "view": "View", "menu": "Menu", "cross": "Cross",
	"circle": "Circle", "square": "Square", "triangle": "Triangle", "share": "Share",
	"options": "Options",
}

static var _textures := {}


## The inputs to show for a prompt (`what`: a key of ACTIONS). In a player's view (`slot`), from
## their own bindings on the device they last used in a menu; in the main window, by `family`.
## Repeats (left and right both on the d-pad) show once.
static func inputs(what: String, family: String, slot: PlayerSlot = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if slot == null:
		for id: String in WINDOW.get(family, WINDOW.keyboard).get(what, []):
			out.append({ "id": id, "text": name_of(id) })
		return out
	var kind := String(slot.input.menu_device().get("kind", "keyboard"))
	for action: String in ACTIONS.get(what, []):
		var refs := slot.input.menu_refs(action)
		if refs.is_empty():
			continue
		var input := of_ref(refs[0], kind, family)
		if not out.any(func(o: Dictionary) -> bool: return o.id == input.id and (input.id or o.text == input.text)):
			out.append(input)
	return out


## A binding ref (Bindings) on a kind of device as an input: {id, text}. Sim devices have no
## glyphs ({id: ""}, text "Button 3").
static func of_ref(ref: Dictionary, kind: String, family: String) -> Dictionary:
	var ps := 1 if family == "playstation" else 0
	if kind == "keyboard" and ref.has("key"):
		if KEYS.has(int(ref.key)):
			var id := String(KEYS[int(ref.key)])
			return { "id": id, "text": name_of(id) }
		# A letter by what's printed on it (the bindings are physical keys).
		var text := Bindings.ref_label(ref, "keyboard")
		var letter := text.length() == 1 and text.to_upper() >= "A" and text.to_upper() <= "Z"
		return { "id": text.to_lower() if letter else "", "text": text }
	if kind == "gamepad" and ref.has("button") and PAD.has(int(ref.button)):
		var id := String(PAD[int(ref.button)][ps])
		return { "id": id, "text": name_of(id) }
	if kind == "gamepad" and ref.has("axis") and PAD_AXES.has(int(ref.axis)):
		var id := String(PAD_AXES[int(ref.axis)][ps])
		return { "id": id, "text": name_of(id) }
	return { "id": "", "text": Bindings.ref_label(ref, kind) }


## What a glyph id is called on a chip: "LB", "Enter", "D-pad".
static func name_of(id: String) -> String:
	if NAMES.has(id):
		return NAMES[id]
	return id.to_upper() if id.length() <= 2 else id.capitalize()


## The glyph, or null if this family has none by that id.
static func texture(family: String, id: String) -> Texture2D:
	if id.is_empty() or family not in FAMILIES:
		return null
	var path := "%s%s/%s.png" % [DIR, family, id]
	if not _textures.has(path):
		_textures[path] = load(path) if ResourceLoader.exists(path) else null
	return _textures[path]


## An input shown `size` px tall: its glyph, or a text chip (its name in a rounded box) without one.
## Either way named for screen readers.
static func icon(input: Dictionary, family: String, size := 40) -> Control:
	var tex := texture(family, String(input.get("id", "")))
	if tex:
		var r := TextureRect.new()
		r.name = "Glyph"
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(size, size)
		r.accessibility_name = String(input.text)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var chip := PanelContainer.new()
	chip.name = "Chip"
	chip.custom_minimum_size = Vector2(size, size)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = UiKit.BUTTON
	box.border_color = UiKit.MUTED
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.content_margin_left = 10
	box.content_margin_right = 10
	chip.add_theme_stylebox_override(&"panel", box)
	var l := UiKit.label(String(input.text), 26)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(l)
	return chip
