#include <doctest/doctest.h>

#include "world/heightfield.h"
#include "world/surface_map.h"

using namespace noss::world;

TEST_CASE("surface map: painted layers become surfaces; off the map is -1") {
	Heightfield f;
	f.create(41, 41, -20.0, -20.0, 1.0, 0.0f, 0);
	f.paint(2, 10.0, 10.0, 5.0, 1.0, 0.0);
	std::vector<uint8_t> surfaces = { 4, 6, 5, 7, 8, 9, 1, 0 }; // grass, dirt, gravel, ...
	SurfaceMap m = SurfaceMap::from_layers(f.dominant_layers(), f.w, f.d, f.ox, f.oz, f.cell, surfaces);
	CHECK(m.at(0.0, 0.0) == 4);
	CHECK(m.at(10.0, 10.0) == 5);
	CHECK(m.at(-30.0, 0.0) == -1);
	CHECK(m.at(0.0, 25.0) == -1);
}
