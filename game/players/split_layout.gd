class_name SplitLayout
extends RefCounted
## Where each player's view goes in a window (docs/ARCHITECTURE.md §6, LOC-02, LOC-03), in 0..1
## of the window. 1 player: full. 2: stacked or side by side. 3: one wide view on top and two
## below, or 2×2 with the track map in the spare quarter. 4: 2×2. Each monitor's window is
## split on its own, so 1+3 and 2+2 across two monitors fall out.

const HALF_TOP := Rect2(0, 0, 1, 0.5)
const HALF_BOTTOM := Rect2(0, 0.5, 1, 0.5)
const QUARTERS: Array[Rect2] = [Rect2(0, 0, 0.5, 0.5), Rect2(0.5, 0, 0.5, 0.5), Rect2(0, 0.5, 0.5, 0.5), Rect2(0.5, 0.5, 0.5, 0.5)]


## Rects for `count` views. two: "stacked" or "side"; three: "wide" or "map".
static func rects(count: int, two := "stacked", three := "wide") -> Array[Rect2]:
	match count:
		0:
			return []
		1:
			return [Rect2(0, 0, 1, 1)]
		2:
			if two == "side":
				return [Rect2(0, 0, 0.5, 1), Rect2(0.5, 0, 0.5, 1)]
			return [HALF_TOP, HALF_BOTTOM]
		3:
			if three == "map":
				return [QUARTERS[0], QUARTERS[1], QUARTERS[2]]
			return [HALF_TOP, QUARTERS[2], QUARTERS[3]]
	return QUARTERS.slice(0, mini(count, 4))


## The spare quarter for the track map; an empty Rect2 if there's none.
static func spare(count: int, three := "wide") -> Rect2:
	return QUARTERS[3] if count == 3 and three == "map" else Rect2()


## Players grouped by monitor, in player order: {screen: [player index]}. A player's screen
## of -1 (or a monitor that isn't there) means the main window's.
static func by_screen(screens: Array, main_screen: int, screen_count: int) -> Dictionary:
	var out := {}
	for i in screens.size():
		var s := int(screens[i])
		if s < 0 or s >= screen_count:
			s = main_screen
		if not out.has(s):
			out[s] = []
		out[s].append(i)
	return out
