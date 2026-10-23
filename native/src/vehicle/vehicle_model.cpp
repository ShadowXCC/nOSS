#include "vehicle/vehicle_model.h"

#include <algorithm>
#include <array>
#include <cmath>

namespace noss::vehicle {

namespace {

// grip, drag, wet grip, grip under snow. Sealed surfaces lose a quarter of their grip wet and
// pack down to 0.45 under snow; loose ones keep theirs wet and go to snow's under snow.
constexpr std::array<SurfaceInfo, SURFACE_COUNT> SURFACES = { {
		{ 1.00, 0.0, 0.75, 0.45 }, // asphalt
		{ 0.97, 0.0, 0.7275, 0.45 }, // concrete
		{ 0.90, 0.005, 0.675, 0.45 }, // curb
		{ 0.95, 0.0, 0.7125, 0.45 }, // painted line
		{ 0.60, 0.06, 0.60, 0.35 }, // grass
		{ 0.55, 0.12, 0.55, 0.35 }, // gravel
		{ 0.70, 0.03, 0.70, 0.35 }, // dirt
		{ 0.40, 0.20, 0.40, 0.35 }, // sand
		{ 0.35, 0.02, 0.35, 0.35 }, // snow
		{ 0.12, 0.0, 0.12, 0.12 }, // ice
} };

// Slip ratio uses max(|v|, this) as its denominator, so it stays finite at a standstill.
constexpr double SLIP_SPEED_FLOOR = 3.0;
// Below this speed lateral damping blends in, so cars stop and hold instead of jittering.
constexpr double LOW_SPEED = 3.0;
constexpr double LOW_SPEED_DAMPING = 0.6; // per N of load, N s/m
constexpr double MECHANICAL_TRAIL = 0.02; // m, caster
constexpr double ACKERMANN = 0.5;
// Stability control: active above this speed, m/s; target yaw capped at this share of the
// grip; acts past this yaw-rate error, rad/s, or this body slip, rad.
constexpr double ESC_MIN_SPEED = 5.0;
constexpr double ESC_GRIP = 0.9;
constexpr double ESC_YAW_MARGIN = 0.06;
constexpr double ESC_BETA = 0.07;
constexpr double ESC_BETA_GAIN = 2.0;
// Brake torque per rad/s of error, as a share of the full brake torque, and its cap.
constexpr double ESC_GAIN = 0.8;
constexpr double ESC_MAX = 0.35;
// Understeer only counts against a car that understeers this much: characteristic speed, m/s.
constexpr double ESC_CHARACTERISTIC_SPEED = 25.0;
constexpr double PITCH_INERTIA_RATIO = 0.9;
constexpr double ROLL_RADIUS_OVER_TRACK = 0.39;
constexpr double BUMP_STOP_ZONE = 0.15; // last fraction of travel
constexpr double BUMP_STOP_LOAD = 3.0; // extra static loads at full travel
constexpr double BEYOND_TRAVEL_RATE = 20.0; // spring rates past full travel
constexpr int SOLVER_ITERATIONS = 8;
// Springs are integrated once per 120 Hz tick: past omega * dt of about 1 they go unstable, so
// stiff ones (karts, bump stops) are capped below that.
constexpr double TICK = 1.0 / 120.0;
constexpr double MAX_OMEGA_DT = 0.8;
// Wheel, tire and brake inertia per kg of vehicle and m^2 of rolling radius (1.2 kg m^2 on GT).
constexpr double WHEEL_INERTIA_PER_KG_M2 = 0.0085;

} // namespace

const SurfaceInfo &surface_info(int p_surface) {
	return SURFACES[size_t(std::clamp(p_surface, 0, SURFACE_COUNT - 1))];
}

double surface_grip(int p_surface, const Conditions &p_conditions) {
	const SurfaceInfo &s = surface_info(p_surface);
	double w = std::clamp(p_conditions.wetness, 0.0, 1.0), snow = std::clamp(p_conditions.snow, 0.0, 1.0);
	double g = s.grip + (s.wet - s.grip) * w;
	return g + (s.snow - g) * snow;
}

Config make_config(const PlatformSpec &p_spec, const Geometry &p_geometry) {
	Config c;
	c.spec = p_spec;
	c.mass = p_spec.mass;
	c.r_ref = p_spec.wheel_radius_ref;
	c.wheel_inertia = p_spec.wheel_inertia > 0.0 ? p_spec.wheel_inertia : WHEEL_INERTIA_PER_KG_M2 * p_spec.mass * c.r_ref * c.r_ref;
	c.spec.tire.reference_load = p_spec.mass * GRAVITY / 4.0;

	double z_sum[2] = { 0, 0 }, x_sum = 0;
	int count[2] = { 0, 0 };
	double left_x[2] = { 0, 0 }, right_x[2] = { 0, 0 };
	int left_n[2] = { 0, 0 }, right_n[2] = { 0, 0 };
	double hub_y[2] = { 0, 0 };
	for (const WheelGeometry &w : p_geometry.wheels) {
		int a = std::clamp(w.axle, 0, 1);
		z_sum[a] += w.hub.z;
		hub_y[a] += w.hub.y;
		x_sum += w.hub.x;
		count[a]++;
		if (w.side > 0) {
			left_x[a] += w.hub.x;
			left_n[a]++;
		} else if (w.side < 0) {
			right_x[a] += w.hub.x;
			right_n[a]++;
		}
	}
	for (int a = 0; a < 2; a++) {
		int n = std::max(count[a], 1);
		c.axle_center[a] = V3(0, hub_y[a] / n, z_sum[a] / n);
		c.axle_track[a] = (left_n[a] && right_n[a]) ? left_x[a] / left_n[a] - right_x[a] / right_n[a] : 0.0;
	}
	c.wheelbase = c.axle_center[0].z - c.axle_center[1].z;
	double share[2] = { p_spec.roll_front_share, 1.0 - p_spec.roll_front_share };
	// Effective track: the axles' tracks weighted by their share of roll stiffness, so each
	// axle's lateral load transfer stays the reference's (docs/PLATFORMS.md §4.2).
	double track_sum = 0.0, share_sum = 0.0;
	for (int a = 0; a < 2; a++) {
		if (c.axle_track[a] > 0.0) {
			track_sum += share[a] * c.axle_track[a];
			share_sum += share[a];
		}
	}
	c.track = share_sum > 0.0 ? track_sum / share_sum : p_spec.track_ref;
	// The ground is where the wheels touch down, whatever fit.json says.
	double ground = 0.0;
	for (const WheelGeometry &w : p_geometry.wheels) {
		ground += w.hub.y - w.radius;
	}
	ground /= double(std::max<size_t>(p_geometry.wheels.size(), 1));

	// CoG from the platform's invariants (docs/PLATFORMS.md §4.2).
	double L = std::max(c.wheelbase, 0.5);
	double b = p_spec.front_weight * L; // CoG to rear axle
	double a = L - b;
	c.cog_height = p_spec.cog_height_over_track * c.track;
	c.com = V3(x_sum / std::max<size_t>(p_geometry.wheels.size(), 1), ground + c.cog_height, c.axle_center[1].z + b);
	// Tire forces act at the reference wheelbase and track in the ground plane, so yaw uses
	// the reference's inertia and steering. Pitch keeps the fitted wheelbase: the springs sit
	// at the fitted hubs. Roll inertia grows with the track, not its square, so roll speed
	// doesn't change with it.
	double L_ref = p_spec.wheelbase_ref;
	double yaw = p_spec.yaw_dynamic_index * p_spec.mass * (1.0 - p_spec.front_weight) * p_spec.front_weight * L_ref * L_ref;
	double pitch = PITCH_INERTIA_RATIO * p_spec.yaw_dynamic_index * p_spec.mass * a * b;
	double roll = p_spec.mass * ROLL_RADIUS_OVER_TRACK * ROLL_RADIUS_OVER_TRACK * c.track * p_spec.track_ref;
	c.inertia = V3(pitch, yaw, roll);
	c.max_steer = p_spec.max_steer_deg * PI / 180.0;
	c.pitch_arm_delta = p_spec.cog_height_over_track * (p_spec.track_ref * L / p_spec.wheelbase_ref - c.track);

	// Springs from ride frequency, roll bars from the roll gradient.
	double weight = p_spec.mass * GRAVITY;
	double axle_load[2] = { weight * p_spec.front_weight, weight * (1.0 - p_spec.front_weight) };
	double k_axle[2] = { 0, 0 }, c_axle[2] = { 0, 0 };
	// Drive torque per axle: all of it to a single driven axle; split by the center diff on AWD.
	int driven_n[2] = { 0, 0 };
	for (const WheelGeometry &w : p_geometry.wheels) {
		int ax = std::clamp(w.axle, 0, 1);
		driven_n[ax] += p_spec.axles[ax].driven ? 1 : 0;
	}
	if (driven_n[0] > 0 && driven_n[1] > 0) {
		c.axle_drive_share[0] = std::clamp(p_spec.center.front_share, 0.0, 1.0);
		c.axle_drive_share[1] = 1.0 - c.axle_drive_share[0];
	} else {
		c.axle_drive_share[0] = driven_n[0] > 0 ? 1.0 : 0.0;
		c.axle_drive_share[1] = driven_n[1] > 0 ? 1.0 : 0.0;
	}
	for (const WheelGeometry &w : p_geometry.wheels) {
		int ax = std::clamp(w.axle, 0, 1);
		const AxleSpec &spec = p_spec.axles[ax];
		WheelConfig wc;
		wc.geo = w;
		wc.steer = spec.steer;
		wc.driven = spec.driven;
		wc.travel = spec.travel;
		wc.static_load = axle_load[ax] / std::max(count[ax], 1);
		double m_corner = wc.static_load / GRAVITY;
		double k_cap = m_corner * std::pow(MAX_OMEGA_DT / TICK, 2.0);
		double omega = 2.0 * PI * spec.freq_hz;
		wc.k = std::min(m_corner * omega * omega, 0.5 * k_cap);
		double c_cap = MAX_OMEGA_DT * m_corner / TICK;
		wc.c_bump = std::min(2.0 * spec.damping_bump * std::sqrt(wc.k * m_corner), c_cap);
		wc.c_rebound = std::min(2.0 * spec.damping_rebound * std::sqrt(wc.k * m_corner), c_cap);
		// The bump stop's stiffness at full travel (2 * load * BUMP_STOP_LOAD / zone) and the
		// rate past it stay under the cap.
		wc.bump_zone = std::max(spec.travel * BUMP_STOP_ZONE, 2.0 * BUMP_STOP_LOAD * wc.static_load / std::max(k_cap - wc.k, 1.0));
		wc.bump_zone = std::min(wc.bump_zone, spec.travel);
		wc.k_beyond = std::max(std::min(BEYOND_TRAVEL_RATE * wc.k, k_cap - wc.k), 0.0);
		wc.drive_share = spec.driven ? c.axle_drive_share[ax] / std::max(driven_n[ax], 1) : 0.0;
		double bias = ax == 0 ? p_spec.brake_bias_front : 1.0 - p_spec.brake_bias_front;
		wc.brake_share = bias / std::max(count[ax], 1);
		double dx = w.hub.x - c.com.x, dz = w.hub.z - c.com.z;
		double t = c.axle_track[ax];
		wc.plane_dx = (t > 0.0 ? dx * p_spec.track_ref / t : dx) - dx;
		wc.plane_dz = dz * L_ref / L - dz;
		k_axle[ax] = wc.k;
		c_axle[ax] = 0.5 * (wc.c_bump + wc.c_rebound);
		c.wheels.push_back(wc);
	}
	// Each axle takes its share of the total roll stiffness. Springs give k T^2 / 2 and the
	// bar makes up the rest, which can be negative on a wide track with stiff springs.
	double roll_rad_per_g = std::max(p_spec.roll_gradient_deg_per_g, 0.05) * PI / 180.0;
	double k_roll = weight * c.cog_height / roll_rad_per_g;
	for (int ax = 0; ax < 2; ax++) {
		double t = c.axle_track[ax];
		if (t <= 0.0) {
			continue;
		}
		double k_ax = share[ax] / share_sum * (t / c.track) * k_roll;
		c.k_arb[ax] = (k_ax - k_axle[ax] * t * t / 2.0) / (t * t);
		c.c_roll[ax] = c_axle[ax] * (p_spec.track_ref / t - 1.0) / 2.0;
	}

	double peak = 0.0;
	for (const auto &pt : p_spec.engine.torque_curve) {
		peak = std::max(peak, pt.second);
	}
	c.clutch_max = 1.6 * std::max(peak, 50.0);
	return c;
}

VehicleModel::VehicleModel(const Config &p_config) :
		_config(p_config) {
	wheels.resize(_config.wheels.size());
	gearbox.spec = _config.spec.gearbox;
	engine_omega = _config.spec.engine.idle_rpm * RPM_TO_RAD;
	for (size_t i = 0; i < _config.wheels.size(); i++) {
		if (_config.wheels[i].driven) {
			_driven.push_back(int(i));
		}
	}
	if (_config.spec.arcade) {
		kart.emplace(*_config.spec.arcade);
	}
}

void VehicleModel::reset() {
	for (WheelState &w : wheels) {
		w = WheelState();
	}
	engine_omega = _config.spec.engine.idle_rpm * RPM_TO_RAD;
	if (gearbox.gear < 0 || gearbox.target < 0) {
		gearbox.gear = gearbox.target = 1;
	}
	gearbox.shift_timer = 0.0;
	_tcs_factor = 1.0;
	_has_last_velocity = false;
	if (kart) {
		kart->reset();
	}
}

void VehicleModel::roll_at(double p_speed) {
	reset();
	double omega = std::max(p_speed, 0.0) / std::max(_config.r_ref, 0.05);
	for (WheelState &w : wheels) {
		w.omega = omega;
	}
	// The highest gear that keeps the engine above 1.6 x idle, below 0.85 x redline if it can.
	const EngineSpec &e = _config.spec.engine;
	int best = 1;
	for (int g = 1; g <= gearbox.top_gear(); g++) {
		double rpm = omega * gearbox.ratio(g) / RPM_TO_RAD;
		if (rpm <= e.redline_rpm * 0.85) {
			best = g;
			if (rpm < e.idle_rpm * 1.6) {
				best = std::max(1, g - 1);
			}
			break;
		}
	}
	gearbox.gear = gearbox.target = best;
	engine_omega = std::max(omega * gearbox.ratio(best), e.idle_rpm * RPM_TO_RAD);
}

void VehicleModel::take_state(const VehicleModel &p_other) {
	controls = p_other.controls;
	assists = p_other.assists;
	conditions = p_other.conditions;
	flats = p_other.flats;
	engine_omega = p_other.engine_omega;
	gearbox.gear = p_other.gearbox.gear;
	gearbox.target = p_other.gearbox.target;
	gearbox.shift_timer = p_other.gearbox.shift_timer;
	gearbox.engage = p_other.gearbox.engage;
	gearbox.since_shift = p_other.gearbox.since_shift;
	_auto = p_other._auto;
	_tcs_factor = p_other._tcs_factor;
	_auto_clutch = p_other._auto_clutch;
	_fuel_cut = p_other._fuel_cut;
	for (size_t i = 0; i < wheels.size() && i < p_other.wheels.size(); i++) {
		wheels[i].omega = p_other.wheels[i].omega;
		wheels[i].deflection = p_other.wheels[i].deflection;
		wheels[i].spin_angle = p_other.wheels[i].spin_angle;
		wheels[i].abs_factor = p_other.wheels[i].abs_factor;
	}
	if (kart && p_other.kart) {
		KartParams params = kart->params;
		*kart = *p_other.kart;
		kart->params = params;
	}
}

void VehicleModel::set_kart(const KartParams *p_params) {
	if (!p_params) {
		kart.reset();
	} else if (kart) {
		kart->params = *p_params;
	} else {
		kart.emplace(*p_params);
	}
}

Ray VehicleModel::wheel_ray(int p_index, const Chassis &p_chassis) const {
	const WheelConfig &w = _config.wheels[size_t(p_index)];
	V3 up = p_chassis.basis.c1;
	// Starts a wheel radius above the top of travel, so deep bumps still hit.
	double above = w.travel + w.geo.radius;
	Ray ray;
	ray.origin = p_chassis.origin + p_chassis.basis * w.geo.hub + up * above;
	ray.direction = -up;
	ray.length = 2.0 * w.travel + 2.0 * w.geo.radius + 0.05;
	return ray;
}

double VehicleModel::_driven_omega() const {
	// Speed at the gearbox output: the driven wheels weighted by their share of the torque.
	double sum = 0.0;
	for (int i : _driven) {
		sum += _config.wheels[size_t(i)].drive_share * wheels[size_t(i)].omega;
	}
	return sum;
}

void VehicleModel::_update_gearbox(double p_driver_throttle, double p_driver_brake, double p_dt) {
	const GearboxType type = _config.spec.gearbox.type;
	// An automatic platform always shifts itself; the assist does it on the others.
	const bool automatic = assists.auto_gearbox || type == GearboxType::AUTO;
	if (automatic) {
		AutoShiftInput in;
		in.rpm = rpm();
		in.throttle = p_driver_throttle;
		in.brake = p_driver_brake;
		in.forward_speed = forward_speed;
		in.peak_slip = _config.spec.tire.peak_slip_ratio;
		double slip = 0.0;
		for (int i : _driven) {
			slip += _config.wheels[size_t(i)].drive_share * wheels[size_t(i)].kappa;
		}
		in.drive_slip = slip;
		int want = _auto.choose(gearbox, _config.spec.engine, in, p_dt);
		if (want != gearbox.gear) {
			gearbox.request(want);
		}
	}
	// An H-pattern box needs the clutch in to change gear (the auto clutch does that for you).
	// Out of gear into neutral always works. A refused shift grinds.
	auto clutch_in = [&](int p_to) {
		return type != GearboxType::MANUAL_H || assists.auto_clutch || controls.clutch > 0.5 || p_to == 0;
	};
	if (controls.select_gear != INT_MIN) {
		int want = std::clamp(controls.select_gear, -1, gearbox.top_gear());
		controls.select_gear = INT_MIN;
		if (type != GearboxType::AUTO && want != gearbox.gear && want != gearbox.target) {
			if (clutch_in(want)) {
				gearbox.request(want);
			} else {
				grinds++;
			}
		}
	}
	if (controls.shift != 0 && !gearbox.shifting() && type != GearboxType::AUTO) {
		int next = std::clamp(gearbox.gear + (controls.shift > 0 ? 1 : -1), -1, gearbox.top_gear());
		if (clutch_in(next)) {
			gearbox.request(next);
		} else {
			grinds++;
		}
	}
	controls.shift = 0;
	gearbox.update(p_dt);
}

StepResult VehicleModel::step(const Chassis &p_chassis, const std::vector<Contact> &p_contacts, double p_dt) {
	const PlatformSpec &spec = _config.spec;
	const EngineSpec &engine = spec.engine;
	const M3 &R = p_chassis.basis;
	const V3 up = R.c1;
	const V3 forward = R.c2;
	const size_t n = wheels.size();
	forward_speed = dot(p_chassis.velocity, forward);

	if (_has_last_velocity) {
		acceleration = R.transposed() * ((p_chassis.velocity - _last_velocity) / p_dt);
	}
	_last_velocity = p_chassis.velocity;
	_has_last_velocity = true;
	KartMods mods;
	if (kart) {
		mods = kart->begin(_config, p_chassis, p_contacts, controls, gravity, rpm(), p_dt);
	}

	// --- Driver inputs and gearbox -----------------------------------------------------
	double driver_throttle = clampd(controls.throttle, 0.0, 1.0);
	double driver_brake = clampd(controls.brake, 0.0, 1.0);
	_update_gearbox(driver_throttle, driver_brake, p_dt);
	double throttle = driver_throttle, brake = driver_brake;
	if (assists.auto_gearbox && (gearbox.gear == -1 || gearbox.target == -1)) {
		std::swap(throttle, brake); // the brake pedal drives backwards in auto reverse
	}

	// TCS: cut torque while a driven wheel spins past the peak. In a corner the tire is
	// already busy sideways, so it watches the combined slip too. While the clutch slips it
	// limits the torque itself; cutting then would stop the engine from revving up to engage
	// it, and the car would sit at idle.
	bool spinning = false;
	double drive_sign = gearbox.ratio() >= 0.0 ? 1.0 : -1.0;
	for (int i : (clutch_out > 0.9 ? _driven : std::vector<int>())) {
		const WheelState &w = wheels[size_t(i)];
		if (!w.contact) {
			continue;
		}
		double kappa = w.kappa * drive_sign / spec.tire.peak_slip_ratio;
		double alpha = w.tan_alpha * mods.slip_seen / std::tan(spec.tire.peak_slip_angle);
		double combined = std::sqrt(kappa * kappa + alpha * alpha);
		if (kappa > 1.15 || (kappa > 0.4 && combined > 1.1)) {
			spinning = true;
		}
	}
	tcs_active = false;
	if (assists.tcs && throttle > 0.05 && spinning) {
		_tcs_factor = std::max(0.05, _tcs_factor - p_dt * 15.0);
		tcs_active = true;
	} else {
		_tcs_factor = std::min(1.0, _tcs_factor + p_dt * 2.5);
	}
	double throttle_drive = throttle * (assists.tcs ? _tcs_factor : 1.0) * mods.power;
	tcs_active = tcs_active || (assists.tcs && _tcs_factor < 0.98 && throttle > 0.05);

	// Clutch engagement.
	double g = gearbox.ratio();
	double idle = engine.idle_rpm;
	if (assists.auto_clutch) {
		double target = 0.0;
		if (g != 0.0) {
			double wheel_rpm = std::abs(g * _driven_omega()) / RPM_TO_RAD;
			double launch_rpm = idle + 0.35 * (engine.redline_rpm - idle);
			// Slip the clutch on launch until the wheels catch up with the engine.
			bool caught_up = wheel_rpm >= rpm() * 0.97 || throttle_drive < 0.1;
			if (wheel_rpm >= idle * 1.02 && caught_up) {
				target = 1.0;
			} else if (throttle_drive > 0.02) {
				double t = clampd((rpm() - idle * 1.05) / (launch_rpm - idle * 1.05), 0.0, 1.0);
				target = t * t * (3.0 - 2.0 * t);
			}
		}
		double rate = target > _auto_clutch ? 8.0 : 20.0;
		_auto_clutch += clampd(target - _auto_clutch, -rate * p_dt, rate * p_dt);
		clutch_out = _auto_clutch;
	} else {
		clutch_out = 1.0 - clampd(controls.clutch, 0.0, 1.0);
	}
	double clutch_capacity = mods.free_clutch ? 0.0 : _config.clutch_max * clutch_out * gearbox.engage;

	// Shifts: ignition cut on upshifts, a throttle blip to rev-match downshifts.
	bool blip = false;
	double blip_target = 0.0;
	if (gearbox.shifting()) {
		if (gearbox.target > gearbox.gear && gearbox.gear > 0) {
			throttle_drive = 0.0;
		} else if (gearbox.target > 0 && gearbox.target < gearbox.gear) {
			blip = true;
			blip_target = std::abs(gearbox.ratio(gearbox.target) * _driven_omega());
		}
	}

	// --- Steering ------------------------------------------------------------------------
	double delta = -clampd(controls.steer, -1.0, 1.0) * _config.max_steer * mods.steer;
	double L = std::max(_config.wheelbase, 0.5);
	for (size_t i = 0; i < n; i++) {
		const WheelConfig &wc = _config.wheels[i];
		if (!wc.steer) {
			wheels[i].steer = 0.0;
			continue;
		}
		// Ackermann from the reference proportions, so it doesn't change with the fit.
		double t = std::tan(delta);
		double half_track = 0.5 * spec.track_ref / spec.wheelbase_ref;
		double ackermann = std::atan(t / std::max(1.0 - wc.geo.side * half_track * t, 0.1 / L));
		wheels[i].steer = delta + ACKERMANN * (ackermann - delta);
	}

	// --- Stability control ---------------------------------------------------------------
	// Compares the yaw rate the steering asks for (a neutral car, capped by grip) with the
	// measured one. Turning more than asked, or sliding wide, brakes the outside front wheel
	// and trims the throttle; turning much less brakes the inside rear (docs/PHYSICS.md §8).
	std::vector<double> esc_brake(n, 0.0);
	stability_active = false;
	if (assists.stability && forward_speed > ESC_MIN_SPEED) {
		double v = forward_speed;
		double yaw = dot(p_chassis.angular_velocity, up); // + = turning left
		double limit = ESC_GRIP * spec.tire.mu * surface_grip(SURFACE_ASPHALT, conditions) * 9.81 / v;
		double target = clampd(v * std::tan(delta) / spec.wheelbase_ref, -limit, limit);
		V3 vb = R.transposed() * p_chassis.velocity;
		double beta = std::atan2(vb.x, std::max(std::abs(vb.z), 1.0)); // + = sliding to the left
		double over = 0.0; // + = rotating too far left
		if (yaw * target >= 0.0 && std::abs(yaw) > std::abs(target) + ESC_YAW_MARGIN) {
			over = yaw - target;
		} else if (yaw * target < 0.0 && std::abs(yaw) > ESC_YAW_MARGIN) {
			over = yaw; // rotating against the steering: the driver is catching a slide
		}
		// Sliding: the rear swings out toward the side the car is sliding away from.
		if (std::abs(beta) > ESC_BETA && over * -beta >= 0.0) {
			over += -beta * ESC_BETA_GAIN;
		}
		if (over != 0.0) {
			double torque = std::min(ESC_GAIN * std::abs(over) * spec.brake_torque, ESC_MAX * spec.brake_torque);
			int outside = over > 0.0 ? -1 : 1;
			for (size_t i = 0; i < n; i++) {
				if (_config.wheels[i].geo.axle == 0 && _config.wheels[i].geo.side == outside) {
					esc_brake[i] = torque;
				}
			}
			throttle_drive *= clampd(1.0 - std::abs(over) * 2.0, 0.2, 1.0);
			stability_active = true;
		} else if (double under = std::abs(target) / (1.0 + v * v / (ESC_CHARACTERISTIC_SPEED * ESC_CHARACTERISTIC_SPEED)) - std::abs(yaw);
				yaw * target >= 0.0 && under > 2.0 * ESC_YAW_MARGIN) {
			double torque = std::min(0.5 * ESC_GAIN * under * spec.brake_torque, 0.5 * ESC_MAX * spec.brake_torque);
			int inside = target > 0.0 ? 1 : -1;
			for (size_t i = 0; i < n; i++) {
				if (_config.wheels[i].geo.axle == 1 && _config.wheels[i].geo.side == inside) {
					esc_brake[i] = torque;
				}
			}
			stability_active = true;
		}
	}

	// --- Suspension (once per tick: the chassis doesn't move within a tick) -------------
	std::vector<double> spring(n, 0.0), rate(n, 0.0);
	std::vector<V3> fwd(n), lat(n), point(n), plane(n);
	std::vector<double> v_long(n, 0.0), v_lat(n, 0.0);
	for (size_t i = 0; i < n; i++) {
		const WheelConfig &wc = _config.wheels[i];
		WheelState &w = wheels[i];
		const Contact &c = p_contacts[i];
		w.contact = c.hit;
		w.surface = c.surface;
		if (c.hit) {
			// The ray starts a radius above the top of travel; a flat tyre sits lower on its rim.
			w.disp = wc.travel + wc.geo.radius * (1.0 + (flat(i) ? FLAT_RADIUS : 1.0)) - c.distance;
		} else {
			w.disp = -wc.travel;
		}
		// Compression rate: the hub's speed toward the ground along the contact normal (moving
		// along a flat ground doesn't compress, even when the body is pitched).
		V3 hub_world = p_chassis.origin + R * wc.geo.hub;
		V3 v_hub = p_chassis.velocity + cross(p_chassis.angular_velocity, hub_world - p_chassis.com) - c.ground_velocity;
		V3 n_ground = c.hit ? normalized(c.normal) : up;
		double v_comp = -dot(v_hub, n_ground) / std::max(dot(up, n_ground), 0.3);
		double f = wc.static_load + wc.k * w.disp;
		double zone_start = wc.travel - wc.bump_zone;
		if (w.disp > zone_start) {
			double e = std::min(w.disp, wc.travel) - zone_start;
			f += BUMP_STOP_LOAD * wc.static_load * std::pow(e / wc.bump_zone, 2.0);
			if (w.disp > wc.travel) {
				f += wc.k_beyond * (w.disp - wc.travel);
			}
		}
		f += (v_comp > 0.0 ? wc.c_bump : wc.c_rebound) * v_comp;
		spring[i] = f;
		rate[i] = v_comp;
	}
	for (size_t i = 0; i < n; i++) {
		// Anti-roll bar: pairs each wheel with the other side of its axle.
		const WheelConfig &wc = _config.wheels[i];
		for (size_t j = 0; j < n; j++) {
			const WheelConfig &other = _config.wheels[j];
			if (j != i && other.geo.axle == wc.geo.axle && other.geo.side == -wc.geo.side && wc.geo.side != 0) {
				int ax = std::clamp(wc.geo.axle, 0, 1);
				spring[i] += _config.k_arb[ax] * (wheels[i].disp - wheels[j].disp) + _config.c_roll[ax] * (rate[i] - rate[j]);
				break;
			}
		}
		WheelState &w = wheels[i];
		w.fz = w.contact ? std::max(0.0, spring[i]) : 0.0;
		if (!w.contact) {
			continue;
		}
		const Contact &c = p_contacts[i];
		V3 n_c = normalized(c.normal);
		V3 dir = R * V3(std::sin(w.steer), 0.0, std::cos(w.steer));
		fwd[i] = normalized(dir - n_c * dot(dir, n_c), forward);
		lat[i] = normalized(cross(n_c, fwd[i]));
		point[i] = c.point;
		plane[i] = c.point + R * V3(wc.plane_dx, 0.0, wc.plane_dz);
		V3 v_c = p_chassis.velocity + cross(p_chassis.angular_velocity, plane[i] - p_chassis.com) - c.ground_velocity;
		v_long[i] = dot(v_c, fwd[i]);
		v_lat[i] = dot(v_c, lat[i]);
	}

	// --- Substeps: tires, wheel spin, drivetrain, brakes --------------------------------
	const double h = p_dt / SUBSTEPS;
	const double r = _config.r_ref;
	const double sigma = std::max(spec.relaxation_length, 0.02);
	const double max_tan_alpha = std::tan(std::min(2.5 * spec.tire.peak_slip_angle, 1.3));
	std::vector<double> sum_fx(n, 0.0), sum_fy(n, 0.0), sum_mz(n, 0.0);
	std::vector<double> ieff(n), fx0(n), dfx(n), omega0(n), mu(n), v_den(n);
	std::vector<double> brake_cap(n, 0.0);
	abs_active = false;
	engine_load = 0.0;
	throttle_out = 0.0;

	for (int s = 0; s < SUBSTEPS; s++) {
		// Engine: combustion, friction, idle control, rev limiter.
		double rpm_now = rpm();
		if (rpm_now > engine.limiter_rpm) {
			_fuel_cut = true;
		} else if (rpm_now < engine.limiter_rpm - 150.0) {
			_fuel_cut = false;
		}
		double thr = _fuel_cut ? 0.0 : throttle_drive;
		if (blip) {
			thr = clampd((blip_target - engine_omega) * 0.05, 0.0, 1.0);
		}
		if (rpm_now < idle + 50.0) {
			thr = std::max(thr, clampd(0.1 + (idle - rpm_now) * 0.002, 0.0, 0.6));
		}
		double torque = thr * engine_torque(engine, rpm_now) - (1.0 - thr) * engine_friction(engine, rpm_now);
		engine_omega += h * torque / engine.inertia;
		throttle_out += thr / SUBSTEPS;
		engine_load += (torque / std::max(engine_torque(engine, rpm_now), 1.0)) / SUBSTEPS;

		// Tires, linearized so the wheel spin step is implicit (stable at any speed).
		for (size_t i = 0; i < n; i++) {
			WheelState &w = wheels[i];
			omega0[i] = w.omega;
			ieff[i] = _config.wheel_inertia;
			fx0[i] = 0.0;
			dfx[i] = 0.0;
			if (!w.contact || w.fz <= 0.0) {
				continue;
			}
			double vl = v_long[i];
			if (std::abs(vl) > 0.05) {
				double target = v_lat[i] * sigma / std::abs(vl);
				w.deflection = target + (w.deflection - target) * std::exp(-std::abs(vl) * h / sigma);
			} else {
				w.deflection += v_lat[i] * h;
			}
			w.deflection = clampd(w.deflection, -sigma * max_tan_alpha, sigma * max_tan_alpha);
			w.tan_alpha = w.deflection / sigma;
			v_den[i] = std::max(std::abs(vl), SLIP_SPEED_FLOOR);
			mu[i] = tire_mu(spec.tire, w.fz) * surface_grip(w.surface, conditions) * mods.grip * (flat(i) ? FLAT_GRIP : 1.0);
			double kappa = (w.omega * r - vl) / v_den[i];
			double dk = 0.01 * spec.tire.peak_slip_ratio;
			double tan_alpha = w.tan_alpha * mods.slip_seen;
			TireForce f0 = tire_force(spec.tire, w.fz, mu[i], kappa, tan_alpha);
			TireForce f1 = tire_force(spec.tire, w.fz, mu[i], kappa + dk, tan_alpha);
			fx0[i] = f0.fx;
			dfx[i] = std::max(0.0, (f1.fx - f0.fx) / dk) * r / v_den[i];
			ieff[i] += h * r * dfx[i];
			w.omega += h * (-r * fx0[i]) / ieff[i];
		}

		// Brake torque per wheel, with ABS modulation.
		for (size_t i = 0; i < n; i++) {
			const WheelConfig &wc = _config.wheels[i];
			double t_brake = (brake * spec.brake_torque * wc.brake_share + esc_brake[i]) * (assists.abs ? wheels[i].abs_factor : 1.0);
			if (wc.geo.axle == 1 && controls.handbrake > 0.0) {
				t_brake += controls.handbrake * spec.handbrake_torque / 2.0;
			}
			brake_cap[i] = t_brake * h;
		}

		// Sequential impulses: clutch, limited-slip diff, brakes.
		double clutch_cap = (g != 0.0) ? clutch_capacity * h : 0.0;
		double clutch_mass = 0.0;
		if (clutch_cap > 0.0) {
			double inv = 1.0 / engine.inertia;
			for (int i : _driven) {
				inv += std::pow(g * _config.wheels[size_t(i)].drive_share, 2.0) / ieff[size_t(i)];
			}
			clutch_mass = 1.0 / inv;
		}
		// Center diff (AWD): front and rear axle mean speeds, as a torque-limited constraint.
		const CenterDiffSpec &center = spec.center;
		double center_mass = 0.0, center_limit = 0.0;
		int center_n[2] = { 0, 0 };
		for (int i : _driven) {
			center_n[std::clamp(_config.wheels[size_t(i)].geo.axle, 0, 1)]++;
		}
		bool has_center = center.type != CenterType::OPEN && center_n[0] > 0 && center_n[1] > 0;
		if (has_center) {
			double inv = 0.0, mean[2] = { 0.0, 0.0 };
			for (int i : _driven) {
				int ax = std::clamp(_config.wheels[size_t(i)].geo.axle, 0, 1);
				inv += 1.0 / (center_n[ax] * center_n[ax] * ieff[size_t(i)]);
				mean[ax] += wheels[size_t(i)].omega / center_n[ax];
			}
			center_mass = 1.0 / inv;
			center_limit = center.type == CenterType::LOCKED ? 1e9 : center.preload + center.viscous * std::abs(mean[0] - mean[1]);
		}
		double clutch_acc = 0.0, center_acc = 0.0;
		double lsd_acc[2] = { 0.0, 0.0 };
		std::vector<double> brake_acc(n, 0.0);
		for (int it = 0; it < SOLVER_ITERATIONS; it++) {
			if (clutch_cap > 0.0) {
				double cdot = engine_omega - g * _driven_omega();
				double old = clutch_acc;
				clutch_acc = clampd(clutch_acc - clutch_mass * cdot, -clutch_cap, clutch_cap);
				double lambda = clutch_acc - old;
				engine_omega += lambda / engine.inertia;
				for (int i : _driven) {
					wheels[size_t(i)].omega -= g * _config.wheels[size_t(i)].drive_share * lambda / ieff[size_t(i)];
				}
			}
			if (has_center) {
				double cdot = 0.0;
				for (int i : _driven) {
					int ax = std::clamp(_config.wheels[size_t(i)].geo.axle, 0, 1);
					cdot += (ax == 0 ? 1.0 : -1.0) * wheels[size_t(i)].omega / center_n[ax];
				}
				double old = center_acc;
				center_acc = clampd(center_acc - center_mass * cdot, -center_limit * h, center_limit * h);
				double lambda = center_acc - old;
				for (int i : _driven) {
					int ax = std::clamp(_config.wheels[size_t(i)].geo.axle, 0, 1);
					wheels[size_t(i)].omega += (ax == 0 ? 1.0 : -1.0) * lambda / (center_n[ax] * ieff[size_t(i)]);
				}
			}
			for (int ax = 0; ax < 2; ax++) {
				const DiffSpec &diff = spec.axle_diff[ax];
				if (diff.type == DiffType::OPEN) {
					continue;
				}
				int left = -1, right = -1;
				for (int i : _driven) {
					const WheelConfig &wc = _config.wheels[size_t(i)];
					if (wc.geo.axle == ax) {
						(wc.geo.side > 0 ? left : right) = i;
					}
				}
				if (left < 0 || right < 0) {
					continue;
				}
				// The torque this axle gets from the gearbox locks its diff.
				double input = std::abs(clutch_acc / h * g) * _config.axle_drive_share[ax];
				bool power = clutch_acc <= 0.0;
				double limit = diff.type == DiffType::LOCKED ? 1e9 : diff.preload + (power ? diff.power_lock : diff.coast_lock) * input;
				double mass = 1.0 / (1.0 / ieff[size_t(left)] + 1.0 / ieff[size_t(right)]);
				double cdot = wheels[size_t(left)].omega - wheels[size_t(right)].omega;
				double old = lsd_acc[ax];
				lsd_acc[ax] = clampd(lsd_acc[ax] - mass * cdot, -limit * h, limit * h);
				double lambda = lsd_acc[ax] - old;
				wheels[size_t(left)].omega += lambda / ieff[size_t(left)];
				wheels[size_t(right)].omega -= lambda / ieff[size_t(right)];
			}
			for (size_t i = 0; i < n; i++) {
				if (brake_cap[i] <= 0.0) {
					continue;
				}
				double old = brake_acc[i];
				brake_acc[i] = clampd(brake_acc[i] - ieff[i] * wheels[i].omega, -brake_cap[i], brake_cap[i]);
				wheels[i].omega += (brake_acc[i] - old) / ieff[i];
			}
		}
		engine_omega = std::max(engine_omega, 0.0);

		// Final tire forces at the new wheel speeds.
		for (size_t i = 0; i < n; i++) {
			WheelState &w = wheels[i];
			if (!w.contact || w.fz <= 0.0) {
				w.kappa = 0.0;
				continue;
			}
			double fx = fx0[i] + dfx[i] * (w.omega - omega0[i]);
			w.kappa = (w.omega * r - v_long[i]) / v_den[i];
			TireForce exact = tire_force(spec.tire, w.fz, mu[i], w.kappa, w.tan_alpha * mods.slip_seen);
			double fy = exact.fy * mods.lateral;
			double low = clampd(1.0 - std::abs(v_long[i]) / LOW_SPEED, 0.0, 1.0);
			fy -= LOW_SPEED_DAMPING * w.fz * v_lat[i] * low;
			double limit = mu[i] * w.fz;
			double mag = std::sqrt(fx * fx + fy * fy);
			if (mag > limit && mag > 0.0) {
				fx *= limit / mag;
				fy *= limit / mag;
			}
			sum_fx[i] += fx;
			sum_fy[i] += fy;
			sum_mz[i] += exact.mz;

			// ABS: release a wheel that's locking, then re-apply.
			if (assists.abs && brake_cap[i] > 0.0 && std::abs(v_long[i]) > 2.0 && w.kappa < -1.2 * spec.tire.peak_slip_ratio) {
				w.abs_factor = std::max(0.1, w.abs_factor * 0.7);
				abs_active = true;
			} else {
				w.abs_factor = std::min(1.0, w.abs_factor + h * 6.0);
			}
		}
	}
	brake_out = brake;

	// --- Forces on the chassis ----------------------------------------------------------
	StepResult out;
	rack_torque = 0.0;
	double longitudinal = 0.0; // tire force along the body's forward axis
	for (size_t i = 0; i < n; i++) {
		const WheelConfig &wc = _config.wheels[i];
		WheelState &w = wheels[i];
		w.fx = sum_fx[i] / SUBSTEPS;
		w.fy = sum_fy[i] / SUBSTEPS;
		w.mz = sum_mz[i] / SUBSTEPS;
		double drawn = wc.geo.visual_radius > 0.0 ? wc.geo.visual_radius : wc.geo.radius;
		w.spin_angle = std::fmod(w.spin_angle + w.omega * p_dt * (r / std::max(drawn, 0.05)), 2.0 * PI);
		if (!w.contact) {
			w.slip_speed = 0.0;
			continue;
		}
		double roll_coef = spec.rolling_resistance + surface_info(w.surface).drag + (flat(i) ? FLAT_DRAG : 0.0);
		double rolling = -roll_coef * w.fz * std::tanh(v_long[i] / 0.5);
		// Load at the fitted contact point; grip forces where the reference tire would be.
		V3 load = up * w.fz;
		V3 grip = fwd[i] * (w.fx + rolling) + lat[i] * w.fy;
		out.force += load + grip;
		out.torque += cross(point[i] - p_chassis.com, load) + cross(plane[i] - p_chassis.com, grip);
		longitudinal += dot(grip, forward);
		w.slip_speed = std::sqrt(std::pow(w.omega * r - v_long[i], 2.0) + v_lat[i] * v_lat[i]);
		if (wc.steer) {
			rack_torque += w.mz - MECHANICAL_TRAIL * w.fy;
		}
	}

	// Longitudinal load transfer as if the CoG height had the reference's ratio to the
	// wheelbase: a force along +Z at depth d gives -d F about the body's +X.
	out.torque += R.c0 * (-_config.pitch_arm_delta * longitudinal);

	// Aero: drag at the CoG, downforce at the axles.
	double q_fwd = 0.5 * AIR_DENSITY * forward_speed * forward_speed;
	out.force += p_chassis.velocity * (-0.5 * AIR_DENSITY * spec.cd_a * mods.drag * drag_scale * length(p_chassis.velocity));
	for (int ax = 0; ax < 2; ax++) {
		double cl = ax == 0 ? spec.cl_a_front : spec.cl_a_rear;
		if (cl == 0.0) {
			continue;
		}
		V3 f = up * (q_fwd * cl);
		V3 at = p_chassis.origin + R * _config.axle_center[ax];
		out.force += f;
		out.torque += cross(at - p_chassis.com, f);
	}
	if (kart) {
		out.force += mods.force;
		out.torque += mods.torque;
	}
	return out;
}

} // namespace noss::vehicle
