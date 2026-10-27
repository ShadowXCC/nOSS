#include "endless/biomes.h"

#include <algorithm>
#include <array>

namespace noss::endless {

namespace {

// clang-format off
constexpr std::array<BiomeStyle, BIOME_COUNT> STYLES = { {
	// id         straight gentle medium tight  r_gentle      r_medium     r_tight     straight_m   arc_deg    grade crest lane  kmh  relief  cell ridged regional base     next
	{ "coast",    250, 350, 300, 100, { 300, 800 },  { 120, 300 }, { 70, 120 }, { 60, 250 },  { 15, 80 },  70, 1200, 3500, 80,  24000, 500, false, 0,    -88000,  { BIOME_FOREST, BIOME_FARMLAND, BIOME_AUTUMN, -1 } },
	{ "forest",   250, 350, 300, 100, { 300, 900 },  { 120, 300 }, { 60, 120 }, { 60, 300 },  { 15, 90 },  70, 1500, 3500, 85,  18000, 350, false, 1000, 0,     { BIOME_AUTUMN, BIOME_ALPINE, BIOME_FARMLAND, BIOME_HAUNTED } },
	{ "farmland", 500, 350, 130, 20,  { 500, 1500 }, { 200, 500 }, { 100, 200 }, { 150, 600 }, { 10, 60 },  50, 2500, 3500, 95,  6000,  500, false, 600,  20000, { BIOME_FOREST, BIOME_CANYON, BIOME_COAST, -1 } },
	{ "canyon",   300, 400, 250, 50,  { 400, 1200 }, { 150, 400 }, { 90, 150 }, { 100, 500 }, { 15, 90 },  70, 1800, 3600, 95,  40000, 420, true,  1000, 60000, { BIOME_FARMLAND, BIOME_ALPINE, BIOME_COAST, -1 } },
	{ "alpine",   150, 250, 350, 250, { 250, 700 },  { 90, 250 },  { 45, 90 },  { 40, 200 },  { 20, 120 }, 90, 900,  3250, 70,  55000, 450, true,  1000, 120000, { BIOME_SNOW, BIOME_FOREST, BIOME_AUTUMN, -1 } },
	{ "snow",     200, 300, 350, 150, { 300, 800 },  { 100, 300 }, { 55, 100 }, { 50, 250 },  { 15, 100 }, 80, 1000, 3250, 65,  38000, 400, true,  1000, 100000, { BIOME_ALPINE, BIOME_FOREST, -1, -1 } },
	{ "autumn",   250, 350, 300, 100, { 300, 900 },  { 120, 300 }, { 60, 120 }, { 60, 300 },  { 15, 90 },  70, 1500, 3500, 80,  20000, 320, false, 1000, 10000, { BIOME_FOREST, BIOME_FARMLAND, BIOME_ALPINE, BIOME_HAUNTED } },
	{ "haunted",  200, 300, 350, 150, { 250, 700 },  { 100, 250 }, { 55, 100 }, { 40, 200 },  { 20, 100 }, 80, 1100, 3250, 60,  22000, 300, false, 1000, 5000,  { BIOME_FOREST, BIOME_AUTUMN, BIOME_FARMLAND, -1 } },
} };
// clang-format on

// Every row there (a missing one has no id), its bend shares summing to 1000, and what may follow
// it: other biomes, none twice, any -1 only after them. An unwritten slot would be 0, the coast.
constexpr bool styles_ok() {
	for (int b = 0; b < BIOME_COUNT; b++) {
		const BiomeStyle &s = STYLES[size_t(b)];
		if (s.id == nullptr || s.straight + s.gentle + s.medium + s.tight != 1000 || s.next[0] < 0) {
			return false;
		}
		bool ended = false;
		for (int i = 0; i < NEXT_MAX; i++) {
			int n = s.next[i];
			if (n == -1) {
				ended = true;
				continue;
			}
			if (ended || n < 0 || n >= BIOME_COUNT || n == b) {
				return false;
			}
			for (int j = 0; j < i; j++) {
				if (s.next[j] == n) {
					return false;
				}
			}
		}
	}
	return true;
}
static_assert(styles_ok(), "a biome row is missing or wrong");

} // namespace

const BiomeStyle &biome_style(int p_biome) {
	return STYLES[size_t(std::clamp(p_biome, 0, int(BIOME_COUNT) - 1))];
}

} // namespace noss::endless
