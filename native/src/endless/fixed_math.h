#pragma once

// Integer maths for the endless road (docs/GAMEMODES.md §4, M9): every game makes the same road
// from a seed, so the generator works in integers only (positions in µm, headings as binary
// angles where 2^32 is a full turn) and never calls the platform's maths library, whose sin and
// cos differ between compilers and CPUs. Plain C++, no Godot types.

#include <cstdint>

#include "traffic/fixed.h"

namespace noss::endless {

using traffic::Fnv64;
using traffic::isqrt64;
using traffic::Pcg32;

constexpr int64_t Q30 = int64_t(1) << 30; // 1.0 in Q30
constexpr int64_t TURN = int64_t(1) << 32; // a full turn as a binary angle
constexpr int64_t QUARTER = TURN / 4;
constexpr int64_t HALF_PI_Q30 = 1686629713; // pi / 2 in Q30
// A binary angle per step of 2 m on a curve of radius R metres is this / R.
constexpr int64_t STEP_CURVE = 1367130551;
constexpr double TURN_TO_RAD = 6.283185307179586 / 4294967296.0;

// a * b / 2^30, rounded toward zero (the same for either sign on every compiler).
inline int64_t mul_q30(int64_t p_a, int64_t p_b) {
	bool negative = (p_a < 0) != (p_b < 0);
	uint64_t a = uint64_t(p_a < 0 ? -p_a : p_a), b = uint64_t(p_b < 0 ? -p_b : p_b);
	int64_t r = int64_t((a * b) >> 30);
	return negative ? -r : r;
}

// Division rounding toward minus infinity (C++ rounds toward zero).
inline int64_t floor_div(int64_t p_a, int64_t p_b) {
	int64_t q = p_a / p_b;
	return (p_a % p_b != 0 && ((p_a < 0) != (p_b < 0))) ? q - 1 : q;
}

// sin of a binary angle, in Q30. A Taylor polynomial to x^9 on a quarter turn (within 4e-6),
// non-negative terms only.
inline int64_t sin_q30(int64_t p_angle) {
	uint32_t a = uint32_t(uint64_t(p_angle) & 0xFFFFFFFFu);
	uint32_t quadrant = a >> 30;
	int64_t f = int64_t(a & uint32_t(Q30 - 1));
	if (quadrant & 1u) {
		f = Q30 - f;
	}
	int64_t x = (f * HALF_PI_Q30) >> 30; // radians, Q30, 0..pi/2
	int64_t x2 = (x * x) >> 30;
	int64_t t = Q30 - x2 / 72;
	t = Q30 - ((x2 * t) >> 30) / 42;
	t = Q30 - ((x2 * t) >> 30) / 20;
	t = Q30 - ((x2 * t) >> 30) / 6;
	int64_t s = (x * t) >> 30;
	if (s > Q30) {
		s = Q30;
	}
	return quadrant >= 2 ? -s : s;
}

inline int64_t cos_q30(int64_t p_angle) {
	return sin_q30(p_angle + QUARTER);
}

// A 64-bit mix (splitmix64's finaliser): hashes lattice points and tiles.
inline uint64_t mix64(uint64_t p_x) {
	p_x ^= p_x >> 30;
	p_x *= 0xbf58476d1ce4e5b9ULL;
	p_x ^= p_x >> 27;
	p_x *= 0x94d049bb133111ebULL;
	p_x ^= p_x >> 31;
	return p_x;
}

// 0..65536 (Q16) smoothstep of a Q16 fraction.
inline int64_t smooth_q16(int64_t p_f) {
	return (p_f * p_f * (3 * 65536 - 2 * p_f)) >> 32;
}

} // namespace noss::endless
