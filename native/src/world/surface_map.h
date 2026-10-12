#pragma once

// What the ground is made of, per terrain sample (D91): the sim reads it for each wheel on the
// terrain, so painted gravel grips like gravel. Plain C++, no Godot types.

#include <cstdint>
#include <vector>

namespace noss::world {

struct SurfaceMap {
	double ox = 0.0;
	double oz = 0.0;
	double cell = 1.0;
	int w = 0;
	int d = 0;
	std::vector<uint8_t> ids; // surface id per sample, row by row

	// The nearest sample's surface; -1 off the map.
	int at(double p_x, double p_z) const;
	// From each sample's heaviest paint layer and what each layer is (p_layer_surfaces[layer]).
	static SurfaceMap from_layers(const std::vector<uint8_t> &p_layers, int p_w, int p_d, double p_ox, double p_oz, double p_cell,
			const std::vector<uint8_t> &p_layer_surfaces);
};

} // namespace noss::world
