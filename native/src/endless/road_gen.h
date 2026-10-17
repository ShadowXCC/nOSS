#pragma once

// The endless road (docs/GAMEMODES.md §4, MODE-06, D152): a two-lane road made 2 m at a time from
// a seed and a start biome, in integers only, so every machine makes the same road (M9
// acceptance: "a seed reproduces the same road on two machines").
//
// - Path: bends are clothoids (curvature ramps in, holds, ramps out) picked per biome, never
//   tighter than the biome's tightest radius, mostly toward the side where the ground stays level
//   (along valleys, round hills), and the heading never turns more than 75 degrees
//   off the landscape's axis, so the road always moves on along it and can't cross itself.
// - Height: follows the natural ground 20 to 220 m ahead, within the biome's grade and crest
//   limits, and never below 4 m above the sea. Where it runs well above the ground it's a bridge;
//   where the ground drops away beside it, a guard rail.
// - Traffic: each lane's speed along the road (bends, braking before them, pulling away after)
//   and the time a car takes to get anywhere at that speed, for the traffic schedule.
//
// Samples come in chunks of 120 (240 m). The generator works ahead of the samples it finishes and
// keeps a checkpoint at every chunk, so any chunk can be made again exactly (driving back, a
// player joining far away). Plain C++, no Godot types.

#include <cstdint>
#include <deque>
#include <vector>

#include "endless/fixed_math.h"
#include "endless/landscape.h"

namespace noss::endless {

constexpr int64_t STEP_UM = 2000000; // 2 m between samples
constexpr int64_t STEP_MM = 2000;
constexpr int CHUNK = 120; // samples per chunk (240 m)
constexpr int64_t SIDE_MM = 9000; // where the ground beside the road is looked at

enum SampleFlag : uint8_t {
	FLAG_LIFTED = 1, // a bridge
	FLAG_BARRIER_L = 2,
	FLAG_BARRIER_R = 4,
};

struct Sample {
	int64_t index = 0;
	int64_t x = 0, y = 0, z = 0; // µm, world
	int64_t heading = 0; // binary angle: 0 = +Z, + = turned left (toward +X)
	int64_t curve = 0; // heading change to the next sample, binary angle, + = left
	int64_t grade = 0; // rise to the next sample, µm
	int64_t ground = 0, ground_l = 0, ground_r = 0; // natural ground at the centre and 9 m each side, µm
	int64_t axis = 0; // how far along the landscape's axis, mm
	int32_t lane_mm = 3500;
	int32_t bank_mdeg = 0; // + = the left edge lower (into a left bend)
	int64_t cap2 = 0; // traffic's top speed here (bends, the biome's cruise), (mm/s)^2
	int32_t v_up = 0, v_down = 0; // traffic speed in each lane, mm/s (up: toward higher indices)
	int64_t t_up = 0, t_down = 0; // µs from sample 0 to here at those speeds
	uint8_t biome = 0, biome2 = 0;
	uint16_t blend = 0; // Q16 weight of biome2
	uint8_t flags = 0;
};

class RoadGen {
public:
	static constexpr int LOOK = 300; // samples looked ahead for braking and pulling away (600 m)
	static constexpr int RAMP_MAX = 60; // longest curvature ramp (steps)

	void setup(uint64_t p_seed, int p_start_biome);
	const Landscape &landscape() const { return _land; }
	uint64_t seed() const { return _seed; }
	int start_biome() const { return _start; }

	// Samples k * CHUNK .. k * CHUNK + CHUNK (CHUNK + 1 of them: the next chunk's first too, so a
	// chunk can be built on its own). None for k < 0.
	std::vector<Sample> chunk(int64_t p_k);
	// FNV-1a over everything a sample holds.
	static uint64_t checksum(const std::vector<Sample> &p_samples, uint64_t p_chain = 0xcbf29ce484222325ULL);
	// Chunks checkpointed so far (they can be made again exactly).
	int64_t checkpoints() const { return int64_t(_checkpoints.size()); }

private:
	struct PathState {
		int64_t index = 0;
		int64_t x = 0, z = 0, heading = 0, curve = 0;
		int64_t k0 = 0, kt = 0;
		int32_t n_ramp = 0, i_ramp = 0, n_hold = 0, i_hold = 0;
		uint64_t rng_state = 0, rng_inc = 0;
	};
	struct HeightState {
		int64_t index = 0;
		int64_t y = 0, grade = 0;
		bool started = false;
	};
	struct FinishState {
		int64_t index = 0;
		int64_t v2_up = 0, v2_down = 0; // carried limits: pulling away (up), braking (down)
		int64_t t_up = 0, t_down = 0;
		int32_t prev_up = 0, prev_down = 0;
		int64_t drop_l = -1000, drop_r = -1000; // last sample with a drop beside it
		bool bridge = false;
	};
	struct Checkpoint {
		PathState path;
		HeightState height;
		FinishState finish;
	};

	Landscape _land;
	uint64_t _seed = 1;
	int _start = 0;
	PathState _path;
	HeightState _height;
	FinishState _finish;
	std::deque<Sample> _buf; // samples _finish.index .. _path.index - 1
	int64_t _window_sum = 0; // ground over the height lookahead window
	bool _window_ready = false;
	std::vector<Checkpoint> _checkpoints; // per chunk
	std::deque<PathState> _path_marks; // the path's state at chunk starts not yet checkpointed
	std::deque<HeightState> _height_marks;
	Sample _last; // the last finished sample

	void _restore(int64_t p_k);
	void _plan();
	void _step_path();
	void _step_height();
	Sample _finish_one();
	Sample &_at(int64_t p_index) { return _buf[size_t(p_index - _finish.index)]; }
	static int64_t _cap2(const Sample &p_s);
};

} // namespace noss::endless
