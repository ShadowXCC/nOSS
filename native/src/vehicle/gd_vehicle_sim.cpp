#include "vehicle/gd_vehicle_sim.h"

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

using namespace godot;
using namespace noss::vehicle;

namespace noss {

namespace {

V3 v3(const Vector3 &p) {
	return { p.x, p.y, p.z };
}

Vector3 gv(const V3 &p) {
	return Vector3(real_t(p.x), real_t(p.y), real_t(p.z));
}

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

PlatformSpec parse_platform(const Dictionary &p) {
	PlatformSpec s;
	s.mass = num(p, "mass.kg", s.mass);
	s.front_weight = num(p, "mass.front_weight", s.front_weight);
	s.cog_height_over_track = num(p, "mass.cog_height_over_track", s.cog_height_over_track);
	s.yaw_dynamic_index = num(p, "mass.yaw_dynamic_index", s.yaw_dynamic_index);
	s.wheelbase_ref = num(p, "geometry.wheelbase_m.ref", s.wheelbase_ref);
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

	String diff = at(p, "differential.type", "open");
	s.diff = diff == "lsd_clutch" ? DiffType::LSD_CLUTCH : (diff == "locked" || diff == "spool") ? DiffType::LOCKED : DiffType::OPEN;
	s.diff_preload = num(p, "differential.preload_nm", 0.0);
	s.diff_power_lock = num(p, "differential.power_lock", 0.0);
	s.diff_coast_lock = num(p, "differential.coast_lock", 0.0);

	s.brake_torque = num(p, "brakes.max_torque_nm", s.brake_torque);
	s.brake_bias_front = num(p, "brakes.bias_front", s.brake_bias_front);
	s.axles[0] = axle(p, "front", 0);
	s.axles[1] = axle(p, "rear", 1);
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
	s.ffb_reference_nm = num(p, "ffb.reference_rack_nm", s.ffb_reference_nm);
	return s;
}

} // namespace

void VehicleSim::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "platform", "geometry"), &VehicleSim::configure);
	ClassDB::bind_method(D_METHOD("get_error"), &VehicleSim::get_error);
	ClassDB::bind_method(D_METHOD("get_body_params"), &VehicleSim::get_body_params);
	ClassDB::bind_method(D_METHOD("integrate", "state"), &VehicleSim::integrate);
	ClassDB::bind_method(D_METHOD("set_exclude", "exclude"), &VehicleSim::set_exclude);
	ClassDB::bind_method(D_METHOD("set_collision_mask", "mask"), &VehicleSim::set_collision_mask);
	ClassDB::bind_method(D_METHOD("set_controls", "steer", "throttle", "brake", "handbrake", "clutch"), &VehicleSim::set_controls);
	ClassDB::bind_method(D_METHOD("shift", "direction"), &VehicleSim::shift);
	ClassDB::bind_method(D_METHOD("select_gear", "gear"), &VehicleSim::select_gear);
	ClassDB::bind_method(D_METHOD("set_assists", "abs", "tcs", "auto_gearbox", "auto_clutch"), &VehicleSim::set_assists);
	ClassDB::bind_method(D_METHOD("reset"), &VehicleSim::reset);
	ClassDB::bind_method(D_METHOD("get_speed"), &VehicleSim::get_speed);
	ClassDB::bind_method(D_METHOD("get_rpm"), &VehicleSim::get_rpm);
	ClassDB::bind_method(D_METHOD("get_gear"), &VehicleSim::get_gear);
	ClassDB::bind_method(D_METHOD("is_shifting"), &VehicleSim::is_shifting);
	ClassDB::bind_method(D_METHOD("get_wheel_count"), &VehicleSim::get_wheel_count);
	ClassDB::bind_method(D_METHOD("get_wheel_visual", "index"), &VehicleSim::get_wheel_visual);
	ClassDB::bind_method(D_METHOD("get_rack_force"), &VehicleSim::get_rack_force);
	ClassDB::bind_method(D_METHOD("get_throttle"), &VehicleSim::get_throttle);
	ClassDB::bind_method(D_METHOD("get_brake"), &VehicleSim::get_brake);
	ClassDB::bind_method(D_METHOD("get_engine_load"), &VehicleSim::get_engine_load);
	ClassDB::bind_method(D_METHOD("get_acceleration"), &VehicleSim::get_acceleration);
	ClassDB::bind_method(D_METHOD("get_telemetry"), &VehicleSim::get_telemetry);

	BIND_CONSTANT(SURFACE_ASPHALT);
	BIND_CONSTANT(SURFACE_CONCRETE);
	BIND_CONSTANT(SURFACE_CURB);
	BIND_CONSTANT(SURFACE_PAINT);
	BIND_CONSTANT(SURFACE_GRASS);
	BIND_CONSTANT(SURFACE_GRAVEL);
	BIND_CONSTANT(SURFACE_DIRT);
	BIND_CONSTANT(SURFACE_SAND);
	BIND_CONSTANT(SURFACE_SNOW);
	BIND_CONSTANT(SURFACE_ICE);
}

VehicleSim::VehicleSim() {
	_ray.instantiate();
	_ray->set_collide_with_areas(false);
	_ray->set_hit_back_faces(false);
}

bool VehicleSim::configure(const Dictionary &p_platform, const Dictionary &p_geometry) {
	_error = "";
	PlatformSpec spec = parse_platform(p_platform);
	if (spec.engine.torque_curve.size() < 2 || spec.gearbox.ratios.empty()) {
		_error = "Platform has no engine or gearbox";
		return false;
	}
	Geometry geo;
	geo.ground_y = double(p_geometry.get("ground_y", 0.0));
	Array wheels = p_geometry.get("wheels", Array());
	for (int64_t i = 0; i < wheels.size(); i++) {
		Dictionary w = wheels[i];
		WheelGeometry wg;
		wg.hub = v3(w.get("center", Vector3()));
		wg.radius = double(w.get("radius", 0.3));
		wg.axle = std::clamp(int(w.get("axle", 1)) - 1, 0, 1);
		String side = w.get("side", "L");
		wg.side = side == "L" ? 1 : side == "R" ? -1 : 0;
		geo.wheels.push_back(wg);
	}
	if (geo.wheels.size() < 2) {
		_error = "Needs at least 2 wheels";
		return false;
	}
	_reference_rack = spec.ffb_reference_nm;
	auto model = std::make_unique<VehicleModel>(make_config(spec, geo));
	if (_model) {
		model->take_state(*_model); // reconfiguring mid-drive (hotswap) keeps the physics state
	}
	_model = std::move(model);
	return true;
}

Dictionary VehicleSim::get_body_params() const {
	Dictionary d;
	if (_model) {
		const Config &c = _model->config();
		d["mass"] = c.mass;
		d["center_of_mass"] = gv(c.com);
		d["inertia"] = gv(c.inertia);
		d["wheelbase"] = c.wheelbase;
		d["track"] = c.track;
		d["cog_height"] = c.cog_height;
	}
	return d;
}

void VehicleSim::set_exclude(const TypedArray<RID> &p_exclude) {
	_ray->set_exclude(p_exclude);
}

void VehicleSim::set_collision_mask(int64_t p_mask) {
	_ray->set_collision_mask(uint32_t(p_mask));
}

void VehicleSim::integrate(PhysicsDirectBodyState3D *p_state) {
	if (!_model || p_state == nullptr) {
		return;
	}
	Transform3D xf = p_state->get_transform();
	Chassis ch;
	ch.basis = { v3(xf.basis.get_column(0)), v3(xf.basis.get_column(1)), v3(xf.basis.get_column(2)) };
	ch.origin = v3(xf.origin);
	ch.com = v3(xf.origin + p_state->get_center_of_mass());
	ch.velocity = v3(p_state->get_linear_velocity());
	ch.angular_velocity = v3(p_state->get_angular_velocity());

	PhysicsDirectSpaceState3D *space = p_state->get_space_state();
	std::vector<Contact> contacts(_model->wheels.size());
	for (size_t i = 0; i < contacts.size() && space; i++) {
		Ray ray = _model->wheel_ray(int(i), ch);
		_ray->set_from(gv(ray.origin));
		_ray->set_to(gv(ray.origin + ray.direction * ray.length));
		Dictionary hit = space->intersect_ray(_ray);
		if (hit.is_empty()) {
			continue;
		}
		Contact &c = contacts[i];
		c.hit = true;
		c.point = v3(hit["position"]);
		c.normal = v3(hit["normal"]);
		c.distance = dot(c.point - ray.origin, ray.direction);
		Object *collider = hit["collider"];
		if (collider) {
			c.surface = int(collider->get_meta("noss_surface", 0));
		}
	}
	StepResult r = _model->step(ch, contacts, p_state->get_step());
	p_state->apply_central_force(gv(r.force));
	p_state->apply_torque(gv(r.torque));
}

void VehicleSim::set_controls(double p_steer, double p_throttle, double p_brake, double p_handbrake, double p_clutch) {
	if (_model) {
		Controls &c = _model->controls;
		c.steer = p_steer;
		c.throttle = p_throttle;
		c.brake = p_brake;
		c.handbrake = p_handbrake;
		c.clutch = p_clutch;
	}
}

void VehicleSim::shift(int64_t p_direction) {
	if (_model && p_direction != 0) {
		_model->controls.shift = p_direction > 0 ? 1 : -1;
	}
}

void VehicleSim::select_gear(int64_t p_gear) {
	if (_model) {
		_model->controls.select_gear = int(p_gear);
	}
}

void VehicleSim::set_assists(bool p_abs, bool p_tcs, bool p_auto_gearbox, bool p_auto_clutch) {
	if (_model) {
		_model->assists = { p_abs, p_tcs, p_auto_gearbox, p_auto_clutch };
	}
}

void VehicleSim::reset() {
	if (_model) {
		_model->reset();
	}
}

double VehicleSim::get_speed() const {
	return _model ? _model->forward_speed : 0.0;
}

double VehicleSim::get_rpm() const {
	return _model ? _model->rpm() : 0.0;
}

int64_t VehicleSim::get_gear() const {
	return _model ? _model->gearbox.gear : 0;
}

bool VehicleSim::is_shifting() const {
	return _model && _model->gearbox.shifting();
}

int64_t VehicleSim::get_wheel_count() const {
	return _model ? int64_t(_model->wheels.size()) : 0;
}

Vector4 VehicleSim::get_wheel_visual(int64_t p_index) const {
	if (!_model || p_index < 0 || p_index >= int64_t(_model->wheels.size())) {
		return Vector4();
	}
	const WheelState &w = _model->wheels[size_t(p_index)];
	double travel = _model->config().wheels[size_t(p_index)].travel;
	return Vector4(real_t(w.steer), real_t(w.spin_angle), real_t(std::clamp(w.disp, -travel, travel)), w.contact ? 1.0f : 0.0f);
}

double VehicleSim::get_rack_force() const {
	return _model ? _model->rack_torque / std::max(_reference_rack, 0.1) : 0.0;
}

double VehicleSim::get_throttle() const {
	return _model ? _model->throttle_out : 0.0;
}

double VehicleSim::get_brake() const {
	return _model ? _model->brake_out : 0.0;
}

double VehicleSim::get_engine_load() const {
	return _model ? _model->engine_load : 0.0;
}

Vector3 VehicleSim::get_acceleration() const {
	return _model ? gv(_model->acceleration) : Vector3();
}

Dictionary VehicleSim::get_telemetry() const {
	Dictionary d;
	if (!_model) {
		return d;
	}
	const VehicleModel &m = *_model;
	d["speed"] = m.forward_speed;
	d["rpm"] = m.rpm();
	d["gear"] = m.gearbox.gear;
	d["throttle"] = m.throttle_out;
	d["brake"] = m.brake_out;
	d["clutch"] = m.clutch_out;
	d["steer"] = m.controls.steer;
	d["engine_load"] = m.engine_load;
	d["abs"] = m.abs_active;
	d["tcs"] = m.tcs_active;
	d["accel"] = gv(m.acceleration);
	d["rack"] = get_rack_force();
	Array wheels;
	for (const WheelState &w : m.wheels) {
		Dictionary wd;
		wd["load"] = w.fz;
		wd["slip_ratio"] = w.kappa;
		wd["slip_angle"] = std::atan(w.tan_alpha);
		wd["slip_speed"] = w.slip_speed;
		wd["travel"] = w.disp;
		wd["contact"] = w.contact;
		wd["surface"] = w.surface;
		wheels.push_back(wd);
	}
	d["wheels"] = wheels;
	return d;
}

} // namespace noss
