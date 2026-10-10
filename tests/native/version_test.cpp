#include <doctest/doctest.h>

#include "core/version.h"

TEST_CASE("version formats as major.minor.patch") {
	CHECK(noss::to_string(noss::Version{ 1, 22, 333 }) == "1.22.333");
	CHECK(noss::to_string(noss::Version{}) == "0.0.0");
}

