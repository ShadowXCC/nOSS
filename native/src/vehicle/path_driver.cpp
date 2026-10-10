#include "vehicle/path_driver.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace noss::vehicle {

namespace {

double wrap_angle(double p_angle) {
	return std::remainder(p_angle, 2.0 * PI);
}

} // namespace

Path::Path(const std::vector<std::pair<double, double>> &p_points, bool p_closed, double p_smooth_m) :
		_closed(p_closed) {
	for (const auto &p : p_points) {
		if (!_x.empty() && std::hypot(p.first - _x.back(), p.second - _z.back()) < 1e-6) {
			continue; // duplicate point
		}
		_x.push_back(p.first);
		_z.push_back(p.second);
	}
	if (_closed && _x.size() > 2 && std::hypot(_x.front() - _x.back(), _z.front() - _z.back()) < 1e-6) {
		_x.pop_back();
		_z.pop_back();
	}
	size_t n = _x.size();
	if (n < 2) {
		_x.assign({ 0.0, 0.0 });
		_z.assign({ 0.0, 1.0 });
		_closed = false;
		n = 2;
	}
	size_t segs = _segments();
	std::vector<double> seg_len(segs), seg_heading(segs);
	_s.assign(n, 0.0);
	for (size_t i = 0; i < segs; i++) {
		size_t j = (i + 1) % n;
		double dx = _x[j] - _x[i], dz = _z[j] - _z[i];
		seg_len[i] = std::hypot(dx, dz);
		seg_heading[i] = std::atan2(dx, dz);
		if (i + 1 < n) {
			_s[i + 1] = _s[i] + seg_len[i];
		}
	}
	_length = _s.back() + (_closed ? seg_len.back() : 0.0);

	// Curvature at each point from the heading change between its two segments.
	std::vector<double> raw(n, 0.0);
	for (size_t i = 0; i < n; i++) {
		if (!_closed && (i == 0 || i == n - 1)) {
			continue;
		}
		size_t prev = (i + segs - 1) % segs, next = i % segs;
		double ds = 0.5 * (seg_len[prev] + seg_len[next]);
		raw[i] = ds > 1e-9 ? wrap_angle(seg_heading[next] - seg_heading[prev]) / ds : 0.0;
	}
	// Smoothed over about p_smooth_m of path.
	double spacing = _length / double(std::max<size_t>(segs, 1));
	int half = int(std::lround(0.5 * p_smooth_m / std::max(spacing, 1e-3)));
	_k.assign(n, 0.0);
	for (size_t i = 0; i < n; i++) {
		double sum = 0.0;
		int count = 0;
		for (int d = -half; d <= half; d++) {
			long j = long(i) + d;
			if (_closed) {
				j = ((j % long(n)) + long(n)) % long(n);
			} else if (j < 0 || j >= long(n)) {
				continue;
			}
			sum += raw[size_t(j)];
			count++;
		}
		_k[i] = count ? sum / count : 0.0;
	}
}

double Path::wrap(double p_s) const {
	if (_closed) {
		double s = std::fmod(p_s, _length);
		return s < 0.0 ? s + _length : s;
	}
	return std::clamp(p_s, 0.0, _length);
}

size_t Path::index_at(double p_s) const {
	auto it = std::upper_bound(_s.begin(), _s.end(), wrap(p_s));
	return it == _s.begin() ? 0 : size_t(it - _s.begin()) - 1;
}

Path::Projection Path::project(double p_x, double p_z, size_t p_hint, size_t p_window) const {
	size_t segs = _segments();
	size_t n = _x.size();
	Projection best;
	double best_d2 = std::numeric_limits<double>::max();
	// Segments to search: all of them, or a window around the hint (wrapping on a closed path).
	size_t first = 0, count = segs;
	if (p_window > 0 && 2 * p_window + 1 < segs) {
		if (_closed) {
			first = (p_hint % segs + segs - p_window) % segs;
			count = 2 * p_window + 1;
		} else {
			first = p_hint > p_window ? p_hint - p_window : 0;
			count = std::min(segs, p_hint + p_window + 1) - first;
		}
	}
	for (size_t k = 0; k < count; k++) {
		size_t i = (first + k) % segs;
		size_t j = (i + 1) % n;
		double dx = _x[j] - _x[i], dz = _z[j] - _z[i];
		double len2 = dx * dx + dz * dz;
		double t = len2 > 0.0 ? std::clamp(((p_x - _x[i]) * dx + (p_z - _z[i]) * dz) / len2, 0.0, 1.0) : 0.0;
		double qx = _x[i] + dx * t, qz = _z[i] + dz * t;
		double d2 = (p_x - qx) * (p_x - qx) + (p_z - qz) * (p_z - qz);
		if (d2 < best_d2) {
			best_d2 = d2;
			double len = std::sqrt(len2);
			best.segment = i;
			best.s = _s[i] + t * len;
			best.heading = std::atan2(dx, dz);
			best.lateral = len > 0.0 ? ((p_x - qx) * dz - (p_z - qz) * dx) / len : 0.0;
		}
	}
	return best;
}

double Path::curvature_at(double p_s) const {
	double s = wrap(p_s);
	size_t i = index_at(s);
	size_t j = (i + 1) % _x.size();
	if (!_closed && i + 1 >= _x.size()) {
		return _k.back();
	}
	double s1 = (j == 0) ? _length : _s[j];
	double t = s1 > _s[i] ? (s - _s[i]) / (s1 - _s[i]) : 0.0;
	return _k[i] + (_k[j] - _k[i]) * t;
}

void Path::point_at(double p_s, double &r_x, double &r_z, double &r_heading) const {
	double s = wrap(p_s);
	size_t i = std::min(index_at(s), _segments() - 1);
	size_t j = (i + 1) % _x.size();
	double dx = _x[j] - _x[i], dz = _z[j] - _z[i];
	double len = std::hypot(dx, dz);
	double t = len > 0.0 ? std::clamp((s - _s[i]) / len, 0.0, 1.0) : 0.0;
	r_x = _x[i] + dx * t;
	r_z = _z[i] + dz * t;
	r_heading = std::atan2(dx, dz);
}

std::vector<double> speed_profile(const Path &p_path, double p_lateral_accel, double p_brake_accel, double p_max_speed) {
	size_t n = p_path.size();
	std::vector<double> v(n);
	for (size_t i = 0; i < n; i++) {
		double k = std::abs(p_path.curvature_at_index(i));
		v[i] = k > 1e-6 ? std::min(p_max_speed, std::sqrt(p_lateral_accel / k)) : p_max_speed;
	}
	// Braking into each point, with only the grip the corner leaves over (friction ellipse).
	int passes = p_path.closed() ? 2 : 1;
	for (int pass = 0; pass < passes; pass++) {
		for (size_t k = n; k-- > 0;) {
			size_t next = k + 1;
			double ds;
			if (next >= n) {
				if (!p_path.closed()) {
					continue;
				}
				next = 0;
				ds = p_path.length() - p_path.s_at(k);
			} else {
				ds = p_path.s_at(next) - p_path.s_at(k);
			}
			double lateral = v[next] * v[next] * std::abs(p_path.curvature_at_index(k)) / p_lateral_accel;
			double brake = p_brake_accel * std::sqrt(std::max(0.0, 1.0 - lateral * lateral));
			v[k] = std::min(v[k], std::sqrt(v[next] * v[next] + 2.0 * brake * ds));
		}
	}
	return v;
}

PathDriver::PathDriver(const Path &p_path, const PlatformSpec &p_spec, const DriverParams &p_params) :
		_path(p_path), _params(p_params) {
	_path_wheelbase = p_spec.wheelbase_ref;
	_max_road = std::max(p_spec.max_steer_deg * PI / 180.0, 1e-3);
}

double PathDriver::steer(const FlatHarness &p_harness) {
	const V3 &c = p_harness.chassis.com;
	Path::Projection p = _path.project(c.x, c.z, _proj.segment, _started ? 40 : 0);
	if (_started) {
		double ds = p.s - _proj.s;
		if (_path.closed()) {
			double half = 0.5 * _path.length();
			ds = ds > half ? ds - _path.length() : ds < -half ? ds + _path.length() : ds;
		}
		_progress += ds;
	}
	_proj = p;
	_started = true;

	double v = std::max(p_harness.forward_speed(), 1.0);
	double ld = _params.lookahead_base + _params.lookahead_per_speed * v;
	double heading_error = wrap_angle(p_harness.heading() - p.heading);
	double integral = 0.0;
	if (_params.lateral_time > 0.0) {
		if (std::abs(p.lateral) < 2.0) {
			_lateral_integral = std::clamp(_lateral_integral + p.lateral * FlatHarness::DT, -2.0, 2.0);
		}
		integral = _lateral_integral / _params.lateral_time;
	}
	double k = _path.curvature_at(p.s + v * _params.preview) - 2.0 * (p.lateral + ld * std::sin(heading_error) + integral) / (ld * ld);
	// Road angle along the path's curvature, corrected by the yaw rate the car actually has,
	// plus the body slip angle so the front wheels point where the car is going when the rear
	// steps out.
	double yaw_error = v * k - p_harness.yaw_rate();
	_yaw_integral = std::clamp(_yaw_integral + _params.yaw_ki * yaw_error * FlatHarness::DT, -0.5 * _max_road, 0.5 * _max_road);
	double road = k * _path_wheelbase + _params.yaw_kp * yaw_error + _yaw_integral + _params.countersteer * p_harness.slip_angle();
	return std::clamp(-road / _max_road, -1.0, 1.0);
}

void PathDriver::speed(const FlatHarness &p_harness, double p_target, double &r_throttle, double &r_brake) {
	double error = p_target - p_harness.forward_speed();
	double u = _params.kp * error + _integral;
	// Integrate only while the output isn't saturated in the same direction (anti-windup).
	if (!((u >= 1.0 && error > 0.0) || (u <= -1.0 && error < 0.0))) {
		_integral = std::clamp(_integral + _params.ki * error * FlatHarness::DT, -0.5, 1.0);
	}
	u = _params.kp * error + _integral;
	r_throttle = std::clamp(u, 0.0, 1.0);
	r_brake = std::clamp(-u * _params.brake_gain, 0.0, 1.0);
}

} // namespace noss::vehicle
