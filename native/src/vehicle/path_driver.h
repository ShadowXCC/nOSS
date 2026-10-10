#pragma once

// A scripted driver for the conformance runner (docs/PLATFORMS.md §5): follows a 2D path with
// the centre of mass and holds a target speed. It only uses the platform's reference geometry
// (L_ref, max road angle), never the fitted model's, so every fit gets the same driver.

#include <cstddef>
#include <utility>
#include <vector>

#include "vehicle/flat_harness.h"

namespace noss::vehicle {

// A polyline on the ground plane, (x, z) points. Curvature + = turning left.
class Path {
public:
	struct Projection {
		double s = 0.0; // along-path distance of the closest point
		double lateral = 0.0; // + = the point is left of the path
		double heading = 0.0; // path heading there (0 = +Z, + = toward +X)
		size_t segment = 0;
	};

	Path() = default;
	Path(const std::vector<std::pair<double, double>> &p_points, bool p_closed, double p_smooth_m = 10.0);

	bool closed() const { return _closed; }
	double length() const { return _length; }
	size_t size() const { return _x.size(); }
	double s_at(size_t p_index) const { return _s[p_index]; }
	double curvature_at_index(size_t p_index) const { return _k[p_index]; }

	// Closest point. p_window > 0 searches that many segments around p_hint; 0 searches all.
	Projection project(double p_x, double p_z, size_t p_hint = 0, size_t p_window = 0) const;
	double curvature_at(double p_s) const;
	void point_at(double p_s, double &r_x, double &r_z, double &r_heading) const;
	// Wraps s into [0, length) on a closed path, clamps it on an open one.
	double wrap(double p_s) const;
	// Index of the point at or before p_s (wrapped).
	size_t index_at(double p_s) const;

private:
	std::vector<double> _x, _z, _s, _k;
	double _length = 0.0;
	bool _closed = false;

	size_t _segments() const { return _closed ? _x.size() : _x.size() - 1; }
};

// Highest speed per path point for a lateral limit, braking into slower points within the
// grip the corner leaves over (m/s).
std::vector<double> speed_profile(const Path &p_path, double p_lateral_accel, double p_brake_accel, double p_max_speed);

struct DriverParams {
	double lookahead_base = 5.0; // m
	double lookahead_per_speed = 0.35; // s
	double preview = 0.15; // s of curvature feedforward lead
	double countersteer = 1.0; // share of the body slip angle steered into (catches slides)
	// Inner loop on the yaw rate the path asks for: rad of road angle per rad/s of error, and
	// its integral per rad (makes up for understeer).
	double yaw_kp = 0.05;
	double yaw_ki = 0.6;
	// s, integral time of the path error, which removes the steady understeer offset on a
	// constant radius. 0 = off.
	double lateral_time = 0.0;
	double kp = 0.4; // throttle per m/s of speed error
	double ki = 0.4;
	double brake_gain = 0.5; // brake per unit of negative control
};

class PathDriver {
public:
	PathDriver(const Path &p_path, const PlatformSpec &p_spec, const DriverParams &p_params = DriverParams());

	// Steering input for the harness state (-1..1, + = right). Updates projection().
	double steer(const FlatHarness &p_harness);
	// Throttle and brake (0..1) toward p_target m/s.
	void speed(const FlatHarness &p_harness, double p_target, double &r_throttle, double &r_brake);

	const Path::Projection &projection() const { return _proj; }
	// Distance driven along the path since the start, unwrapped on a closed path.
	double progress() const { return _progress; }

private:
	const Path &_path;
	DriverParams _params;
	double _path_wheelbase; // the platform's reference wheelbase
	double _max_road; // the platform's max road angle, rad
	Path::Projection _proj;
	bool _started = false;
	double _progress = 0.0;
	double _integral = 0.0;
	double _lateral_integral = 0.0;
	double _yaw_integral = 0.0; // rad of road angle
};

} // namespace noss::vehicle
