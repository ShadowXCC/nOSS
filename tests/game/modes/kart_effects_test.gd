extends GdUnitTestSuite
## Kart effects and Reduce flashing (D146, ACC-04): with it on, every effect flashes at most three
## times a second (sampled at 1 kHz for 10 s); without it, sparks and flames flicker. Light bars
## and item effects share the layers each player's camera picks.


func test_reduce_flashing_keeps_every_effect_to_three_a_second() -> void:
	for effect in ["sparks", "flame", "shield", "emp"]:
		var calm := Flash.most_per_second(func(t: float) -> float: return KartEffects.pattern(effect, t, true))
		assert_int(calm).override_failure_message(effect).is_less_equal(int(Flash.CALM_MAX))
	assert_int(Flash.most_per_second(func(t: float) -> float: return KartEffects.pattern("sparks", t, false))).is_greater(3)
	assert_int(Flash.most_per_second(func(t: float) -> float: return LightBar.pattern(t, true).red)).is_less_equal(3)


func test_light_bars_and_effects_share_the_layers() -> void:
	assert_int(LightBar.LAYER_NORMAL).is_equal(Flash.LAYER_NORMAL)
	assert_int(LightBar.cull_mask_for(true, 0xFFFFF)).is_equal(Flash.cull_mask_for(true, 0xFFFFF))
	var n := MeshInstance3D.new()
	n.add_child(MeshInstance3D.new())
	Flash.put_on(n, true)
	assert_int(n.layers).is_equal(1 << (Flash.LAYER_CALM - 1))
	assert_int((n.get_child(0) as MeshInstance3D).layers).is_equal(1 << (Flash.LAYER_CALM - 1))
	n.free()
