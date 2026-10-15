#include "vehicle/gd_platform.h"

#include <algorithm>

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector3.hpp>

using namespace godot;
using namespace noss::vehicle;

namespace noss {

namespace {

// Value at a dotted path in nested Dictionaries, or p_default.
Variant at(const Dictionary &p_dict, const String &p_path, const Variant &p_default = Variant()) {
	PackedStringArray parts = p_path.split(".");
	Variant node = p_dict;
	for (const String &part : parts) {
		if (node.get_type() != Variant::DICTIONARY) {
			return p_default;
		}
		Dictionary d = node;
		if (!d.has(part)) {
			return p_default;
		}
		node = d[part];
	}
	return node;
}

double num(const Dictionary &p_dict, const String &p_path, double p_default) {
	Variant v = at(p_dict, p_path);
	return (v.get_type() == Variant::FLOAT || v.get_type() == Variant::INT) ? double(v) : p_default;
}

AxleSpec axle(const Dictionary &p_platform, const String &p_name, int p_index) {
	AxleSpec a;
	String base = "suspension." + p_name + ".";
	a.freq_hz = num(p_platform, base + "freq_hz", a.freq_hz);
	a.damping_bump = num(p_platform, base + "damping_bump", a.damping_bump);
	a.damping_rebound = num(p_platform, base + "damping_rebound", a.damping_rebound);
	a.travel = std::max(num(p_platform, base + "travel_m", a.travel), 0.01);
	Array axles = at(p_platform, "layout.axles", Array());
	if (p_index < axles.size()) {
		Dictionary ad = axles[p_index];
		a.steer = bool(ad.get("steer", false));
		a.driven = bool(ad.get("driven", false));
	}
	return a;
}

DiffSpec diff_spec(const Dictionary &p_platform, const String &p_base, const DiffSpec &p_default) {
	Variant block = at(p_platform, p_base);
	if (block.get_type() != Variant::DICTIONARY) {
		return p_default;
	}
	DiffSpec d = p_default;
	String type = at(p_platform, p_base + String(".type"), "");
	if (!type.is_empty()) {
		d.type = type == "lsd_clutch" ? DiffType::LSD_CLUTCH : (type == "locked" || type == "spool") ? DiffType::LOCKED : DiffType::OPEN;
	}
	d.preload = num(p_platform, p_base + String(".preload_nm"), d.preload);
	d.power_lock = num(p_platform, p_base + String(".power_lock"), d.power_lock);
	d.coast_lock = num(p_platform, p_base + String(".coast_lock"), d.coast_lock);
	return d;
}

} // namespace

PlatformSpec parse_platform(const Dictionary &p) {
	PlatformSpec s;
	s.mass = num(p, "mass.kg", s.mass);
	s.front_weight = num(p, "mass.front_weight", s.front_weight);
	s.cog_height_over_track = num(p, "mass.cog_height_over_track", s.cog_height_over_track);
	s.yaw_dynamic_index = num(p, "mass.yaw_dynamic_index", s.yaw_dynamic_index);
	s.wheelbase_ref = num(p, "geometry.wheelbase_m.ref", s.wheelbase_ref);
	s.track_ref = num(p, "geometry.track_m.ref", s.track_ref);
	s.wheel_radius_ref = num(p, "geometry.wheel_radius_m.ref", s.wheel_radius_ref);
	String drive = at(p, "layout.drive", "rwd");
	s.drive = drive == "fwd" ? Drive::FWD : drive == "awd" ? Drive::AWD : Drive::RWD;

	Array curve = at(p, "engine.torque_curve_nm", Array());
	for (int64_t i = 0; i < curve.size(); i++) {
		Array pt = curve[i];
		if (pt.size() == 2) {
			s.engine.torque_curve.emplace_back(double(pt[0]), double(pt[1]));
		}
	}
	s.engine.idle_rpm = num(p, "engine.idle_rpm", s.engine.idle_rpm);
	s.engine.redline_rpm = num(p, "engine.redline_rpm", s.engine.redline_rpm);
	s.engine.limiter_rpm = num(p, "engine.limiter_rpm", s.engine.limiter_rpm);
	s.engine.inertia = num(p, "engine.inertia_kgm2", s.engine.inertia);
	s.engine.engine_brake = num(p, "engine.engine_brake_nm", s.engine.engine_brake);

	String box = at(p, "gearbox.type", "sequential");
	s.gearbox.type = box == "auto" ? GearboxType::AUTO : box == "manual_h" ? GearboxType::MANUAL_H : GearboxType::SEQUENTIAL;
	Array ratios = at(p, "gearbox.ratios", Array());
	for (int64_t i = 0; i < ratios.size(); i++) {
		s.gearbox.ratios.push_back(double(ratios[i]));
	}
	s.gearbox.reverse = num(p, "gearbox.reverse", s.gearbox.reverse);
	s.gearbox.final_drive = num(p, "gearbox.final_drive", s.gearbox.final_drive);
	s.gearbox.shift_time = num(p, "gearbox.shift_time_s", s.gearbox.shift_time);

	// differential.front / .rear override the shared settings per axle.
	DiffSpec shared = diff_spec(p, "differential", DiffSpec());
	s.axle_diff[0] = diff_spec(p, "differential.front", shared);
	s.axle_diff[1] = diff_spec(p, "differential.rear", shared);
	String center = at(p, "differential.center.type", "open");
	s.center.type = center == "viscous" ? CenterType::VISCOUS : center == "locked" ? CenterType::LOCKED : CenterType::OPEN;
	s.center.front_share = num(p, "differential.center.front_share", s.center.front_share);
	s.center.viscous = num(p, "differential.center.viscous_nm_per_rad_s", 0.0);
	s.center.preload = num(p, "differential.center.preload_nm", 0.0);

	s.brake_torque = num(p, "brakes.max_torque_nm", s.brake_torque);
	s.brake_bias_front = num(p, "brakes.bias_front", s.brake_bias_front);
	s.axles[0] = axle(p, "front", 0);
	s.axles[1] = axle(p, "rear", 1);
	s.rigid = String(at(p, "suspension.type", "independent")) == "rigid";
	s.roll_gradient_deg_per_g = num(p, "suspension.roll_gradient_deg_per_g", s.roll_gradient_deg_per_g);
	s.roll_front_share = num(p, "suspension.roll_stiffness_front_share", s.roll_front_share);
	s.max_steer_deg = num(p, "steering.max_road_angle_deg", s.max_steer_deg);
	s.cd_a = num(p, "aero.cd_a", s.cd_a);
	s.cl_a_front = num(p, "aero.cl_a_front", 0.0);
	s.cl_a_rear = num(p, "aero.cl_a_rear", 0.0);
	s.tire.mu = num(p, "tires.mu_peak", s.tire.mu);
	s.tire.load_sensitivity = num(p, "tires.load_sensitivity", s.tire.load_sensitivity);
	s.tire.peak_slip_ratio = num(p, "tires.peak_slip_ratio", s.tire.peak_slip_ratio);
	s.tire.peak_slip_angle = num(p, "tires.peak_slip_angle_deg", 7.5) * PI / 180.0;
	s.relaxation_length = num(p, "tires.relaxation_length_m", s.relaxation_length);
	s.rolling_resistance = num(p, "tires.rolling_resistance", s.rolling_resistance);
	s.wheel_inertia = num(p, "tires.wheel_inertia_kgm2", 0.0);
	s.ffb_reference_nm = num(p, "ffb.reference_rack_nm", s.ffb_reference_nm);
	return s;
}

KartParams parse_kart(const Dictionary &p) {
	KartParams k;
	auto pair = [&](const String &p_path, double (&r_pair)[2]) {
		Array a = at(p, p_path, Array());
		for (int64_t i = 0; i < 2 && i < a.size(); i++) {
			r_pair[i] = double(a[i]);
		}
	};
	auto triple = [&](const String &p_path, double (&r_triple)[3]) {
		Array a = at(p, p_path, Array());
		for (int64_t i = 0; i < 3 && i < a.size(); i++) {
			r_triple[i] = double(a[i]);
		}
	};
	k.grip = num(p, "grip", k.grip);
	k.drift_min_speed = num(p, "drift.min_speed", k.drift_min_speed);
	k.drift_min_steer = num(p, "drift.min_steer", k.drift_min_steer);
	pair("drift.turn_g", k.drift_turn_g);
	pair("drift.slip", k.drift_slip);
	k.drift_side_grip = num(p, "drift.side_grip", k.drift_side_grip);
	k.drift_tire_slip = num(p, "drift.tire_slip", k.drift_tire_slip);
	k.drift_wheel_steer = num(p, "drift.wheel_steer", k.drift_wheel_steer);
	k.drift_yaw_accel = num(p, "drift.yaw_accel", k.drift_yaw_accel);
	k.drift_hop = num(p, "drift.hop", k.drift_hop);
	triple("drift.tiers_s", k.drift_tiers);
	triple("drift.boost_s", k.drift_boost);
	k.boost_accel = num(p, "boost.accel", k.boost_accel);
	k.boost_cap = num(p, "boost.cap", k.boost_cap);
	k.pad_s = num(p, "boost.pad_s", k.pad_s);
	k.air_pitch = num(p, "air.pitch", k.air_pitch);
	k.air_roll = num(p, "air.roll", k.air_roll);
	k.air_yaw = num(p, "air.yaw", k.air_yaw);
	k.trick_window = num(p, "air.trick_window_s", k.trick_window);
	k.trick_boost = num(p, "air.trick_boost_s", k.trick_boost);
	k.stick_min_speed = num(p, "stick.min_speed", k.stick_min_speed);
	k.stick_hold = num(p, "stick.hold_s", k.stick_hold);
	k.right_after = num(p, "right_after_s", k.right_after);
	k.spin_s = num(p, "spin.s", k.spin_s);
	k.spin_grip = num(p, "spin.grip", k.spin_grip);
	k.spin_yaw_rate = num(p, "spin.yaw_rate", k.spin_yaw_rate);
	k.slow_power = num(p, "slow.power", k.slow_power);
	return k;
}

bool parse_geometry(const Dictionary &p_geometry, Geometry &r_geometry, String &r_error) {
	r_geometry = Geometry();
	r_geometry.ground_y = double(p_geometry.get("ground_y", 0.0));
	Array wheels = p_geometry.get("wheels", Array());
	for (int64_t i = 0; i < wheels.size(); i++) {
		Dictionary w = wheels[i];
		Vector3 c = w.get("center", Vector3());
		WheelGeometry wg;
		wg.hub = V3(c.x, c.y, c.z);
		wg.radius = double(w.get("radius", 0.3));
		wg.visual_radius = double(w.get("visual_radius", 0.0));
		int axle = int(w.get("axle", 1));
		if (axle < 1 || axle > 2) {
			r_error = "Physics wheels must be on axle 1 or 2";
			return false;
		}
		wg.axle = axle - 1;
		String side = w.get("side", "L");
		wg.side = side == "L" ? 1 : side == "R" ? -1 : 0;
		r_geometry.wheels.push_back(wg);
	}
	if (r_geometry.wheels.size() < 2) {
		r_error = "Needs at least 2 wheels";
		return false;
	}
	return true;
}

} // namespace noss
