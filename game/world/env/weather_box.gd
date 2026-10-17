class_name WeatherBox
extends MultiMeshInstance3D
## One player's rain or snow (D153): streaks drawn round their camera by weather.gdshader, on
## their own render layer, so splitscreen players each see the weather round themselves. As many
## streaks as the graphics preset allows, times how hard it's falling; none under shelter.

const FIRST_LAYER := 17
const COUNTS := { "low": 500, "medium": 1100, "high": 2000 }
const SHADER := preload("res://game/world/env/weather.gdshader")

## The player's car (under shelter, nothing falls).
var vehicle: Vehicle
var index := 0
var amount := 0.0
var snowing := false
var _material: ShaderMaterial


## A box for player `player_index` (0-3).
static func create(player_index: int) -> WeatherBox:
	var b := WeatherBox.new()
	b.name = "Weather%d" % (player_index + 1)
	b.index = player_index
	b.layers = 1 << (FIRST_LAYER - 1 + player_index)
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5)) # it's always round the camera
	var quad := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var count: int = COUNTS.get(Settings.graphics, 1100)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234 + player_index
	for i in count:
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), rng.randf(), 0.0))
	mm.visible_instance_count = 0
	b.multimesh = mm
	b._material = ShaderMaterial.new()
	b._material.shader = SHADER
	b.material_override = b._material
	b.add_to_group(&"weather_boxes")
	return b


## How hard it's falling (0..1), rain or snow, the sky's light, and whether it reaches here.
func set_weather(falling: float, snow: bool, light: float, sheltered: bool) -> void:
	amount = 0.0 if sheltered else clampf(falling, 0.0, 1.0)
	multimesh.visible_instance_count = roundi(multimesh.instance_count * amount)
	visible = amount > 0.0
	if snow != snowing or _material.get_shader_parameter("fall") == null:
		snowing = snow
		_material.set_shader_parameter("fall", 1.3 if snow else 9.0)
		_material.set_shader_parameter("length_m", 0.06 if snow else 0.6)
		_material.set_shader_parameter("width_m", 0.06 if snow else 0.02)
		_material.set_shader_parameter("sway", 0.6 if snow else 0.0)
		_material.set_shader_parameter("box", 28.0 if snow else 36.0)
		_material.set_shader_parameter("tint", Color(1.0, 1.0, 1.0, 0.85) if snow else Color(0.72, 0.77, 0.85, 0.42))
	_material.set_shader_parameter("light", clampf(light, 0.15, 1.0))


## A camera mask that shows player `player_index`'s box and no one else's.
static func cull_mask_for(player_index: int, mask: int) -> int:
	for i in 4:
		var bit := 1 << (FIRST_LAYER - 1 + i)
		mask = (mask | bit) if i == player_index else (mask & ~bit)
	return mask
