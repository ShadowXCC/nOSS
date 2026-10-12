#include "world/surface_map.h"

#include <cmath>

namespace noss::world {

int SurfaceMap::at(double p_x, double p_z) const {
	if (w <= 0 || d <= 0) {
		return -1;
	}
	long x = std::lround((p_x - ox) / cell), z = std::lround((p_z - oz) / cell);
	if (x < 0 || z < 0 || x >= w || z >= d) {
		return -1;
	}
	return ids[size_t(z) * size_t(w) + size_t(x)];
}

SurfaceMap SurfaceMap::from_layers(const std::vector<uint8_t> &p_layers, int p_w, int p_d, double p_ox, double p_oz, double p_cell,
		const std::vector<uint8_t> &p_layer_surfaces) {
	SurfaceMap m;
	m.ox = p_ox;
	m.oz = p_oz;
	m.cell = p_cell;
	m.w = p_w;
	m.d = p_d;
	m.ids.resize(p_layers.size());
	for (size_t i = 0; i < p_layers.size(); i++) {
		uint8_t layer = p_layers[i];
		m.ids[i] = layer < p_layer_surfaces.size() ? p_layer_surfaces[layer] : 0;
	}
	return m;
}

} // namespace noss::world
