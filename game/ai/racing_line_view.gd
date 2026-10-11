class_name RacingLineView
extends MeshInstance3D
## The racing line assist (docs/PHYSICS.md §8, INP-07): the AI line drawn on the road, coloured
## by its target speed (fast, lift, brake) in the player's palette, with chevrons in braking
## zones so it never relies on colour alone. Each player's line sits on its own visual layer
## that only their camera draws.

## Visual layers 11-14 hold players 1-4's lines.
const FIRST_LAYER := 11
const WIDTH := 0.7
const LIFT := 0.04
const CHEVRON_EVERY := 6 # samples (12 m)


## A line for `platform` on `track`, for player `index` (0-3), in `palette`.
static func create(track: TrackData, platform: Dictionary, index: int, palette: Dictionary) -> RacingLineView:
	var view := RacingLineView.new()
	view.name = "RacingLine%d" % (index + 1)
	view.layers = 1 << (FIRST_LAYER - 1 + index)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var line := RacingLine.for_track(track)
	var speeds := line.speed_profile(platform, 0.92)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := line.points.size()
	var states := PackedInt32Array()
	states.resize(n)
	for i in n:
		var drop := speeds[i] - speeds[(i + 5) % n]
		states[i] = 2 if drop > 1.5 else (1 if drop > 0.3 else 0)
	var colors := [palette.line_fast, palette.line_lift, palette.line_brake]
	for i in n:
		var j := (i + 1) % n
		var c: Color = colors[states[i]]
		c.a = 0.7
		var up := Vector3.UP * LIFT
		var li := line.points[i] + track.lefts[i] * WIDTH / 2.0 + up
		var ri := line.points[i] - track.lefts[i] * WIDTH / 2.0 + up
		var lj := line.points[j] + track.lefts[j] * WIDTH / 2.0 + up
		var rj := line.points[j] - track.lefts[j] * WIDTH / 2.0 + up
		for v in [li, ri, rj, li, rj, lj]:
			st.set_color(c)
			st.add_vertex(v)
		# Braking zones: a chevron pointing along the track.
		if states[i] == 2 and i % CHEVRON_EVERY == 0:
			var fwd := track.tangents[i]
			var left := track.lefts[i]
			var tip := line.points[i] + fwd * 1.2 + up * 1.2
			var cc: Color = colors[2]
			cc.a = 0.9
			for side: float in [1.0, -1.0]:
				var wing := line.points[i] + left * side * 1.0 + up * 1.2
				var thick := fwd * 0.35
				for v in [wing, tip, tip + thick, wing, tip + thick, wing + thick]:
					st.set_color(cc)
					st.add_vertex(v)
	view.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	view.material_override = m
	return view


## Camera mask for player `index`: everything but the other players' lines.
static func cull_mask_for(index: int, mask: int) -> int:
	for i in 4:
		var bit := 1 << (FIRST_LAYER - 1 + i)
		mask = (mask | bit) if i == index else (mask & ~bit)
	return mask
