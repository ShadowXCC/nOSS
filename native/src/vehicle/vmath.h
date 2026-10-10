#pragma once

// Minimal double-precision vector math for the vehicle sim. Plain C++, no Godot types.

#include <algorithm>
#include <cmath>

namespace noss::vehicle {

struct V3 {
	double x = 0.0, y = 0.0, z = 0.0;

	constexpr V3() = default;
	constexpr V3(double p_x, double p_y, double p_z) :
			x(p_x), y(p_y), z(p_z) {}

	constexpr V3 operator+(const V3 &o) const { return { x + o.x, y + o.y, z + o.z }; }
	constexpr V3 operator-(const V3 &o) const { return { x - o.x, y - o.y, z - o.z }; }
	constexpr V3 operator-() const { return { -x, -y, -z }; }
	constexpr V3 operator*(double s) const { return { x * s, y * s, z * s }; }
	constexpr V3 operator/(double s) const { return { x / s, y / s, z / s }; }
	V3 &operator+=(const V3 &o) {
		x += o.x;
		y += o.y;
		z += o.z;
		return *this;
	}
	V3 &operator-=(const V3 &o) {
		x -= o.x;
		y -= o.y;
		z -= o.z;
		return *this;
	}
	V3 &operator*=(double s) {
		x *= s;
		y *= s;
		z *= s;
		return *this;
	}
};

inline constexpr V3 operator*(double s, const V3 &v) {
	return v * s;
}

inline constexpr double dot(const V3 &a, const V3 &b) {
	return a.x * b.x + a.y * b.y + a.z * b.z;
}

inline constexpr V3 cross(const V3 &a, const V3 &b) {
	return { a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x };
}

inline double length(const V3 &v) {
	return std::sqrt(dot(v, v));
}

inline V3 normalized(const V3 &v, const V3 &p_fallback = { 0, 1, 0 }) {
	double l = length(v);
	return l > 1e-12 ? v / l : p_fallback;
}

// Rotation (or any 3x3) stored as columns: c0 = image of x, c1 = of y, c2 = of z.
struct M3 {
	V3 c0{ 1, 0, 0 }, c1{ 0, 1, 0 }, c2{ 0, 0, 1 };

	constexpr V3 operator*(const V3 &v) const { return c0 * v.x + c1 * v.y + c2 * v.z; }
	constexpr M3 operator*(const M3 &o) const { return { *this * o.c0, *this * o.c1, *this * o.c2 }; }
	// Inverse for a rotation.
	constexpr M3 transposed() const {
		return { { c0.x, c1.x, c2.x }, { c0.y, c1.y, c2.y }, { c0.z, c1.z, c2.z } };
	}
	static M3 axis_angle(const V3 &p_axis, double p_angle) {
		V3 a = normalized(p_axis);
		double c = std::cos(p_angle), s = std::sin(p_angle), t = 1.0 - c;
		return {
			{ t * a.x * a.x + c, t * a.x * a.y + s * a.z, t * a.x * a.z - s * a.y },
			{ t * a.x * a.y - s * a.z, t * a.y * a.y + c, t * a.y * a.z + s * a.x },
			{ t * a.x * a.z + s * a.y, t * a.y * a.z - s * a.x, t * a.z * a.z + c },
		};
	}
};

inline double clampd(double v, double lo, double hi) {
	return std::min(std::max(v, lo), hi);
}

inline double lerpd(double a, double b, double t) {
	return a + (b - a) * t;
}

inline double signd(double v) {
	return v > 0.0 ? 1.0 : (v < 0.0 ? -1.0 : 0.0);
}

constexpr double PI = 3.14159265358979323846;
constexpr double RPM_TO_RAD = 2.0 * PI / 60.0;

} // namespace noss::vehicle
