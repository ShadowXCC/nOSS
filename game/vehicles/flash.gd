class_name Flash
extends RefCounted
## Anything that flashes (ACC-04, D116, D146): police light bars, kart items' effects. Each is
## drawn twice, on LAYER_NORMAL with its full pattern and on LAYER_CALM for players with Reduce
## flashing on, where it changes at most CALM_MAX times a second. Each player's camera shows one
## (cull_mask_for), so splitscreen players can differ.

const LAYER_NORMAL := 15
const LAYER_CALM := 16
## WCAG: no more than three flashes a second.
const CALM_MAX := 3.0


## A camera mask that shows the copies for `reduce_flashing` (and not the others).
static func cull_mask_for(reduce_flashing: bool, mask: int) -> int:
	var normal := 1 << (LAYER_NORMAL - 1)
	var calm := 1 << (LAYER_CALM - 1)
	return (mask | calm) & ~normal if reduce_flashing else (mask | normal) & ~calm


## `node` and its meshes on the normal or the calm layer.
static func put_on(node: Node, calm: bool) -> void:
	var bit := 1 << ((LAYER_CALM if calm else LAYER_NORMAL) - 1)
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = bit
	for vi: VisualInstance3D in node.find_children("*", "VisualInstance3D", true, false):
		vi.layers = bit


## The most flashes in any second of `pattern(t) -> brightness 0..1`, sampled at 1 kHz for
## `seconds`: rises through the middle of its range, when it changes by a tenth or more.
static func most_per_second(pattern: Callable, seconds := 10.0) -> int:
	var samples := PackedFloat32Array()
	for ms in int(seconds * 1000.0):
		samples.append(float(pattern.call(ms / 1000.0)))
	var lo := INF
	var hi := -INF
	for v in samples:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if hi - lo < 0.1:
		return 0
	var mid := (lo + hi) / 2.0
	var rises := PackedInt32Array()
	for i in range(1, samples.size()):
		if samples[i - 1] < mid and samples[i] >= mid:
			rises.append(i)
	var most := 0
	for i in rises.size():
		var n := 0
		for j in range(i, rises.size()):
			if rises[j] - rises[i] < 1000:
				n += 1
		most = maxi(most, n)
	return most
