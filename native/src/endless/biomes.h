#pragma once

// The endless road's biomes (docs/GAMEMODES.md §4): how each one's road bends and climbs and how
// its ground rises, as integers so every game builds the same road (D152). What they look like
// (colours, props, sky, sounds) is data in data/endless/biomes/. Plain C++, no Godot types.

#include <cstdint>

namespace noss::endless {

enum Biome : uint8_t {
	BIOME_COAST,
	BIOME_FOREST,
	BIOME_FARMLAND,
	BIOME_CANYON,
	BIOME_ALPINE,
	BIOME_SNOW,
	BIOME_AUTUMN,
	BIOME_COUNT,
};

struct BiomeStyle {
	const char *id;
	// Bends: shares per mille of straights, gentle, medium and tight bends (summing to 1000), and
	// their radii in metres.
	int32_t straight, gentle, medium, tight;
	int32_t r_gentle[2], r_medium[2], r_tight[2];
	int32_t straight_m[2]; // length of a straight
	int32_t arc_deg[2]; // how far a bend turns
	int32_t max_grade_pm; // per mille
	int32_t crest_m; // smallest radius of a crest or dip
	int32_t lane_mm;
	int32_t design_kmh; // traffic's cruising speed
	// Ground: relief (mm) on cells this size (m), ridged or rolling; the region's rise and fall
	// counts per mille; a base height (mm) on top of the region's 100 m.
	int32_t relief_mm, relief_cell_m;
	bool ridged;
	int32_t regional_pm;
	int32_t base_mm;
	int8_t next[3]; // what may come after it (-1: none)
};

const BiomeStyle &biome_style(int p_biome);

} // namespace noss::endless
