#include "vehicle/gd_vehicle_sim.h"

#include "vehicle/gd_platform.h"
#include "world/gd_terrain.h"

#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;
using namespace noss::vehicle;

namespace noss {

namespace {

Vector3 gv(const V3 &p) {
	return Vector3(real_t(p.x), real_t(p.y), real_t(p.z));
}

V3 v3(const Vector3 &p) {
	return { p.x, p.y, p.z };
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
	ClassDB::bind_method(D_METHOD("set_assists", "assists"), &VehicleSim::set_assists);
	ClassDB::bind_method(D_METHOD("reset"), &VehicleSim::reset);
	ClassDB::bind_method(D_METHOD("roll_at", "speed"), &VehicleSim::roll_at);
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
	ClassDB::bind_method(D_METHOD("set_layer", "arcade"), &VehicleSim::set_layer);
	ClassDB::bind_method(D_METHOD("has_layer"), &VehicleSim::has_layer);
	ClassDB::bind_method(D_METHOD("set_kart_input", "drift"), &VehicleSim::set_kart_input);
	ClassDB::bind_method(D_METHOD("set_kart_drag", "scale"), &VehicleSim::set_kart_drag);
	ClassDB::bind_method(D_METHOD("set_kart_pull", "accel"), &VehicleSim::set_kart_pull);
	ClassDB::bind_method(D_METHOD("kart_effect", "kind", "value", "dir"), &VehicleSim::kart_effect, DEFVAL(1.0));
	ClassDB::bind_method(D_METHOD("get_kart_flags"), &VehicleSim::get_kart_flags);
	ClassDB::bind_method(D_METHOD("get_kart_state"), &VehicleSim::get_kart_state);
	ClassDB::bind_method(D_METHOD("get_geared_top"), &VehicleSim::get_geared_top);

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
	BIND_CONSTANT(TAG_BOOST);
	BIND_CONSTANT(TAG_JUMP);
	BIND_CONSTANT(TAG_STICK);
	BIND_CONSTANT(KART_BOOST);
	BIND_CONSTANT(KART_SPIN);
	BIND_CONSTANT(KART_SLOW);
	BIND_CONSTANT(KART_CANCEL);
	BIND_CONSTANT(KART_FLAG_DRIFT_LEFT);
	BIND_CONSTANT(KART_FLAG_DRIFT_RIGHT);
	BIND_CONSTANT(KART_FLAG_TIER_SHIFT);
	BIND_CONSTANT(KART_FLAG_BOOST);
	BIND_CONSTANT(KART_FLAG_SPUN);
	BIND_CONSTANT(KART_FLAG_SLOWED);
	BIND_CONSTANT(KART_FLAG_TRICK);
	BIND_CONSTANT(KART_FLAG_AIRBORNE);
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
	if (!parse_geometry(p_geometry, geo, _error)) {
		return false;
	}
	_reference_rack = spec.ffb_reference_nm;
	spec.arcade = _arcade;
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
			c.tags = int(collider->get_meta("noss_tag", 0));
			// Terrain: what's painted under this wheel (D91). (get_meta with no default errors.)
			NossSurfaceMap *map = collider->has_meta("noss_surface_map") ? Object::cast_to<NossSurfaceMap>(collider->get_meta("noss_surface_map")) : nullptr;
			if (map) {
				int64_t s = map->surface_at(c.point.x, c.point.z);
				if (s >= 0) {
					c.surface = int(s);
				}
			}
		}
	}
	_model->gravity = v3(p_state->get_total_gravity());
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

// Keys: abs, tcs, stability, auto_gearbox, auto_clutch. Missing keys keep their value.
void VehicleSim::set_assists(const Dictionary &p_assists) {
	if (!_model) {
		return;
	}
	Assists &a = _model->assists;
	a.abs = p_assists.get("abs", a.abs);
	a.tcs = p_assists.get("tcs", a.tcs);
	a.stability = p_assists.get("stability", a.stability);
	a.auto_gearbox = p_assists.get("auto_gearbox", a.auto_gearbox);
	a.auto_clutch = p_assists.get("auto_clutch", a.auto_clutch);
}

void VehicleSim::reset() {
	if (_model) {
		_model->reset();
	}
}

void VehicleSim::roll_at(double p_speed) {
	if (_model) {
		_model->roll_at(p_speed);
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
	// A rigid chassis (kart) has no visible suspension travel.
	double lift = _model->config().spec.rigid ? 0.0 : std::clamp(w.disp, -travel, travel);
	return Vector4(real_t(w.steer), real_t(w.spin_angle), real_t(lift), w.contact ? 1.0f : 0.0f);
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
	d["esc"] = m.stability_active;
	d["grinds"] = m.grinds;
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

void VehicleSim::set_layer(const Dictionary &p_arcade) {
	if (p_arcade.is_empty()) {
		_arcade.reset();
	} else {
		_arcade = parse_kart(p_arcade);
	}
	if (_model) {
		_model->set_kart(_arcade ? &*_arcade : nullptr);
	}
}

bool VehicleSim::has_layer() const {
	return _model && _model->kart.has_value();
}

void VehicleSim::set_kart_input(bool p_drift) {
	if (has_layer()) {
		_model->kart->drift = p_drift;
	}
}

void VehicleSim::set_kart_drag(double p_scale) {
	if (has_layer()) {
		_model->kart->drag_scale = std::clamp(p_scale, 0.0, 2.0);
	}
}

void VehicleSim::set_kart_pull(const Vector3 &p_accel) {
	if (has_layer()) {
		_model->kart->pull = v3(p_accel);
	}
}

void VehicleSim::kart_effect(int64_t p_kind, double p_value, double p_dir) {
	if (has_layer()) {
		_model->kart->effect(int(p_kind), p_value, p_dir);
	}
}

int64_t VehicleSim::get_kart_flags() const {
	return has_layer() ? _model->kart->flags() : 0;
}

Dictionary VehicleSim::get_kart_state() const {
	Dictionary d;
	if (!has_layer()) {
		return d;
	}
	const KartLayer &k = *_model->kart;
	d["drift"] = k.drift_dir;
	d["charge"] = k.charge;
	d["tier"] = k.drift_dir != 0 ? k.tier() : 0;
	d["boost"] = k.boost;
	d["spin"] = k.spin;
	d["slow"] = k.slow;
	d["air_time"] = k.air_time;
	d["trick"] = k.trick;
	d["righting"] = k.righting;
	d["upside"] = k.upside;
	d["stick"] = k.stick;
	d["grounded"] = k.grounded;
	d["boosts"] = k.boosts;
	d["tricks"] = k.tricks;
	return d;
}

double VehicleSim::get_geared_top() const {
	return _model ? KartLayer::geared_top(_model->config()) : 0.0;
}

} // namespace noss
