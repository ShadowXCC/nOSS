#pragma once

// Integer helpers for the lane sim (D108): every game steps traffic from the same seed and
// events, so its state is integers (mm, mm/s) and its arithmetic integer, the same on every
// compiler and CPU. Plain C++, no Godot types.

#include <cstdint>

namespace noss::traffic {

// floor(sqrt(n)).
inline uint64_t isqrt64(uint64_t p_n) {
	if (p_n < 2) {
		return p_n;
	}
	uint64_t x = p_n;
	uint64_t y = (x + 1) / 2;
	while (y < x) {
		x = y;
		y = (x + p_n / x) / 2;
	}
	return x;
}

// PCG32 (O'Neill): a small, seeded generator with a known sequence.
struct Pcg32 {
	uint64_t state = 0x853c49e6748fea9bULL;
	uint64_t inc = 0xda3e39cb94b95bdbULL;

	Pcg32() = default;
	Pcg32(uint64_t p_seed, uint64_t p_stream) { seed(p_seed, p_stream); }

	void seed(uint64_t p_seed, uint64_t p_stream) {
		state = 0;
		inc = (p_stream << 1u) | 1u;
		next();
		state += p_seed;
		next();
	}

	uint32_t next() {
		uint64_t old = state;
		state = old * 6364136223846793005ULL + inc;
		uint32_t shifted = uint32_t(((old >> 18u) ^ old) >> 27u);
		uint32_t rot = uint32_t(old >> 59u);
		return (shifted >> rot) | (shifted << ((-rot) & 31u));
	}

	// [0, n), n > 0.
	uint32_t below(uint32_t p_n) { return p_n == 0 ? 0 : uint32_t((uint64_t(next()) * p_n) >> 32); }
	// [lo, hi].
	int32_t range(int32_t p_lo, int32_t p_hi) { return p_hi <= p_lo ? p_lo : p_lo + int32_t(below(uint32_t(p_hi - p_lo + 1))); }
};

// FNV-1a, 64-bit, over bytes or integers (checksums, graph hashes).
struct Fnv64 {
	uint64_t h = 0xcbf29ce484222325ULL;
	void byte(uint8_t p_b) {
		h ^= p_b;
		h *= 0x100000001b3ULL;
	}
	void i64(int64_t p_v) {
		uint64_t u = uint64_t(p_v);
		for (int i = 0; i < 8; i++) {
			byte(uint8_t(u >> (8 * i)));
		}
	}
};

} // namespace noss::traffic
