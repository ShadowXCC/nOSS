#include "vehicle/kart_layer.h"

#include <cmath>

#include "vehicle/vehicle_model.h"

namespace noss::vehicle {

namespace {

// Drift: how fast the yaw rate is pulled to its target (1/s), and how fast the body slip is
// brought to its own (rad/s per rad).
constexpr double DRIFT_YAW_GAIN = 10.0;
constexpr double DRIFT_SLIP_GAIN = 4.0;
// A drift ends below this share of its minimum speed.
constexpr double DRIFT_DROP = 0.6;
// Boost fades out over the last share of its time, and as the speed nears its cap.
constexpr double BOOST_TAIL = 0.1;
constexpr double BOOST_CAP_FADE = 0.08;
constexpr double BOOST_FREE_RPM = 300.0; // below the limiter, where the clutch lets go
constexpr double AIR_AFTER = 0.1; // s off the ground before air control
constexpr double AIR_LEVEL = 8.0; // rad/s^2 per rad toward upright, pitch and roll
constexpr double AIR_DAMP = 3.0; // 1/s
constexpr double TRICK_AIR = 0.5; // s of air that allows a trick without a jump
constexpr double TRICK_LAND_COS = 0.819; // cos 35 deg
constexpr double SPIN_GAIN = 12.0;
constexpr double SPIN_ACCEL = 40.0;
constexpr double STUCK_SPEED = 3.0; // m/s: on the side or roof, slower than this
constexpr double RIGHT_TIME = 0.6;
constexpr double RIGHT_GAIN = 60.0;
constexpr double RIGHT_DAMP = 12.0;
constexpr double RIGHT_HOP = 2.5; // m/s
constexpr double STICK_FADE = 2.0; // m/s below the minimum over which stick gravity fades

// A timer counted down by a tick, to exactly 0 at the end.
double tick_down(double p_timer, double p_dt) {
	return p_timer > p_dt + 1e-9 ? p_timer - p_dt : 0.0;
}

// Torque that gives the body-frame angular acceleration p_alpha_body, about the model's
// principal axes (x pitch, y yaw, z roll).
V3 body_torque(const Config &p_config, const M3 &p_basis, const V3 &p_alpha_body) {
	const V3 &I = p_config.inertia;
	return p_basis * V3(I.x * p_alpha_body.x, I.y * p_alpha_body.y, I.z * p_alpha_body.z);
}

} // namespace

double KartLayer::geared_top(const Config &p_config) {
	Gearbox box;
	box.spec = p_config.spec.gearbox;
	double ratio = std::abs(box.ratio(std::max(box.top_gear(), 1)));
	return ratio > 0.0 ? p_config.spec.engine.limiter_rpm * RPM_TO_RAD / ratio * p_config.r_ref : 0.0;
}

void KartLayer::reset() {
	drift_dir = 0;
	charge = 0.0;
	drift_exit = 0.0;
	boost = boost_length = 0.0;
	spin = slow = 0.0;
	air_time = 0.0;
	since_jump = 1e9;
	trick = false;
	upside = righting = 0.0;
	stick = 0.0;
	pull = V3();
	drag_scale = 1.0;
	_prev_drift = drift;
	_has_last_velocity = false;
}

int KartLayer::tier() const {
	int t = 0;
	for (double s : params.drift_tiers) {
		t += charge >= s ? 1 : 0;
	}
	return t;
}

int KartLayer::flags() const {
	int f = 0;
	f |= drift_dir < 0 ? KART_FLAG_DRIFT_LEFT : drift_dir > 0 ? KART_FLAG_DRIFT_RIGHT : 0;
	f |= (drift_dir != 0 ? tier() : 0) << KART_FLAG_TIER_SHIFT;
	f |= boost > 0.0 ? KART_FLAG_BOOST : 0;
	f |= spin > 0.0 ? KART_FLAG_SPUN : 0;
	f |= slow > 0.0 ? KART_FLAG_SLOWED : 0;
	f |= trick ? KART_FLAG_TRICK : 0;
	f |= grounded == 0 ? KART_FLAG_AIRBORNE : 0;
	f |= stick > 0.0 ? KART_FLAG_STICK : 0;
	return f;
}

void KartLayer::_give_boost(double p_seconds) {
	if (p_seconds <= 0.0 || spin > 0.0 || slow > 0.0) {
		return;
	}
	if (p_seconds >= boost) {
		boost = boost_length = p_seconds;
	}
	boosts++;
}

void KartLayer::effect(int p_kind, double p_value, double p_dir) {
	switch (p_kind) {
		case KART_BOOST:
			_give_boost(p_value);
			break;
		case KART_SPIN:
			spin = std::max(spin, p_value);
			spin_dir = p_dir < 0.0 ? -1 : 1;
			drift_dir = 0;
			charge = 0.0;
			boost = 0.0;
			break;
		case KART_SLOW:
			slow = std::max(slow, p_value);
			slow_power = clampd(p_dir, 0.0, 1.0);
			boost = 0.0;
			break;
		case KART_CANCEL:
			boost = spin = slow = 0.0;
			drift_dir = 0;
			charge = 0.0;
			break;
		default:
			break;
	}
}

KartMods KartLayer::begin(const Config &p_config, const Chassis &p_chassis, const std::vector<Contact> &p_contacts, const Controls &p_controls,
		const V3 &p_gravity, double p_rpm, double p_dt) {
	KartMods m;
	const KartParams &p = params;
	const M3 &R = p_chassis.basis;
	const V3 up = R.c1;
	const V3 forward = R.c2;
	const double mass = p_config.mass;
	const double g = length(p_gravity);
	const V3 world_up = g > 1e-6 ? p_gravity * (-1.0 / g) : V3(0, 1, 0);
	const double v = dot(p_chassis.velocity, forward);
	const double speed = length(p_chassis.velocity);
	const V3 w_body = R.transposed() * p_chassis.angular_velocity;
	m.grip = p.grip;
	m.drag = drag_scale;
	// How fast the path turns (+ = left): the velocity's own rotation since last tick.
	double path_rate = 0.0;
	if (_has_last_velocity && speed > 1.0) {
		path_rate = dot(cross(_last_velocity, p_chassis.velocity), up) / (speed * speed * p_dt);
	}
	_last_velocity = p_chassis.velocity;
	_has_last_velocity = true;

	// What the wheels touch.
	grounded = 0;
	int tags = 0, stick_n = 0;
	V3 normal_sum, stick_sum;
	for (const Contact &c : p_contacts) {
		if (!c.hit) {
			continue;
		}
		grounded++;
		tags |= c.tags;
		normal_sum += c.normal;
		if (c.tags & TAG_STICK) {
			stick_sum += c.normal;
			stick_n++;
		}
	}
	const bool air = grounded == 0;
	air_time = air ? air_time + p_dt : 0.0;
	since_jump = (tags & TAG_JUMP) ? 0.0 : since_jump + p_dt;
	boost = tick_down(boost, p_dt);
	spin = tick_down(spin, p_dt);
	slow = tick_down(slow, p_dt);
	if (tags & TAG_BOOST) {
		_give_boost(std::max(p.pad_s, boost));
	}
	const bool press = drift && !_prev_drift;
	_prev_drift = drift;

	// --- Drift ---------------------------------------------------------------------------
	if (press && !air && drift_dir == 0 && spin <= 0.0) {
		m.force += world_up * (mass * p.drift_hop / p_dt); // a hop
	}
	if (drift && drift_dir == 0 && grounded >= 2 && v >= p.drift_min_speed && std::abs(p_controls.steer) >= p.drift_min_steer && spin <= 0.0) {
		drift_dir = p_controls.steer > 0.0 ? 1 : -1;
		charge = 0.0;
	}
	if (drift_dir != 0) {
		if (!drift) {
			int t = tier();
			if (t > 0) {
				_give_boost(p.drift_boost[t - 1]);
			}
			drift_dir = 0;
			charge = 0.0;
			drift_exit = p.drift_exit;
		} else if (v < DRIFT_DROP * p.drift_min_speed || spin > 0.0) {
			drift_dir = 0;
			charge = 0.0;
			drift_exit = p.drift_exit;
		} else {
			if (grounded >= 2 && v >= p.drift_min_speed) {
				charge += p_dt;
			}
			if (grounded >= 2) {
				m.lateral = p.drift_side_grip;
				m.slip_seen = p.drift_tire_slip;
				m.steer = p.drift_wheel_steer;
				// Steering into the drift tightens it, against it widens it.
				double tight = clampd(0.5 + 0.5 * p_controls.steer * drift_dir, 0.0, 1.0);
				double a_lat = lerpd(p.drift_turn_g[0], p.drift_turn_g[1], tight) * GRAVITY;
				// The arc: a sideways pull across the kart's path, in the ground plane.
				V3 n = normalized(normal_sum, up);
				V3 vel = p_chassis.velocity - n * dot(p_chassis.velocity, n);
				V3 across = normalized(cross(n, vel), R.c0); // to the left of the path
				m.force += across * (-drift_dir * mass * a_lat);
				// The nose points into the turn by the slip angle; it yaws with the path.
				V3 vb = R.transposed() * p_chassis.velocity;
				double beta = std::atan2(vb.x, std::max(std::abs(vb.z), 1.0)); // + = sliding left
				double slip = drift_dir * lerpd(p.drift_slip[0], p.drift_slip[1], tight);
				double target = -drift_dir * a_lat / std::max(length(vel), 1.0) - DRIFT_SLIP_GAIN * (slip - beta); // + = left
				double alpha = clampd(DRIFT_YAW_GAIN * (target - w_body.y), -p.drift_yaw_accel, p.drift_yaw_accel);
				m.torque += body_torque(p_config, R, V3(0, alpha, 0));
			}
		}
	}

	// Just out of a drift: the tires get their grip back over a moment, not at once (no snap),
	// and the nose swings back in line with the path instead of spinning on.
	if (drift_dir == 0 && drift_exit > 0.0) {
		drift_exit = tick_down(drift_exit, p_dt);
		double k = p.drift_exit > 0.0 ? 1.0 - drift_exit / p.drift_exit : 1.0;
		m.lateral = lerpd(p.drift_side_grip, 1.0, k);
		m.slip_seen = lerpd(p.drift_tire_slip, 1.0, k);
		m.steer = lerpd(p.drift_wheel_steer, 1.0, k);
		if (grounded >= 2) {
			V3 vb = R.transposed() * p_chassis.velocity;
			double beta = std::atan2(vb.x, std::max(std::abs(vb.z), 1.0)); // + = sliding left
			double target = path_rate + DRIFT_SLIP_GAIN * beta;
			double alpha = clampd(DRIFT_YAW_GAIN * (target - w_body.y), -p.drift_yaw_accel, p.drift_yaw_accel);
			m.torque += body_torque(p_config, R, V3(0, alpha, 0));
		}
	}

	// --- Spin-out and power cut ----------------------------------------------------------
	if (spin > 0.0) {
		m.grip *= p.spin_grip;
		double alpha = clampd(SPIN_GAIN * (spin_dir * p.spin_yaw_rate - w_body.y), -SPIN_ACCEL, SPIN_ACCEL);
		m.torque += body_torque(p_config, R, V3(0, alpha, 0));
		if (!air && speed > 0.5) {
			V3 n = normalized(normal_sum, up);
			V3 along = p_chassis.velocity - n * dot(p_chassis.velocity, n);
			m.force += normalized(along, forward) * (-mass * std::min(p.spin_brake, speed / p_dt));
		}
	}
	if (slow > 0.0) {
		m.power = slow_power;
	}

	// --- Boost ---------------------------------------------------------------------------
	if (boost > 0.0) {
		double cap = p.boost_cap * geared_top(p_config);
		double fade = clampd((cap - v) / std::max(BOOST_CAP_FADE * cap, 0.1), 0.0, 1.0);
		double tail = boost_length > 0.0 ? clampd(boost / (BOOST_TAIL * boost_length), 0.0, 1.0) : 1.0;
		V3 dir = forward;
		if (!air) {
			V3 n = normalized(normal_sum, up);
			dir = normalized(forward - n * dot(forward, n), forward);
		}
		m.force += dir * (mass * p.boost_accel * fade * tail);
		if (p_rpm > p_config.spec.engine.limiter_rpm - BOOST_FREE_RPM) {
			m.free_clutch = true;
		}
	}

	// --- Tricks --------------------------------------------------------------------------
	if (press && air && !trick && (since_jump <= p.trick_window || air_time >= TRICK_AIR)) {
		trick = true;
	}
	if (trick && grounded >= 2) {
		if (dot(up, world_up) >= TRICK_LAND_COS) {
			_give_boost(p.trick_boost);
			tricks++;
		}
		trick = false;
	}

	// --- Righting ------------------------------------------------------------------------
	double upness = dot(up, world_up);
	if ((grounded < 2 && upness < 0.5 && speed < STUCK_SPEED) || (air && upness < 0.3)) {
		upside += p_dt;
	} else {
		upside = 0.0;
	}
	if (righting <= 0.0 && upside >= p.right_after) {
		righting = RIGHT_TIME;
		upside = 0.0;
		m.force += world_up * (mass * RIGHT_HOP / p_dt);
	}
	if (righting > 0.0) {
		righting = tick_down(righting, p_dt);
		V3 axis = cross(up, world_up);
		double angle = std::acos(clampd(upness, -1.0, 1.0));
		if (length(axis) < 1e-6) {
			axis = forward; // flat on its roof: roll over
		}
		V3 alpha = normalized(axis, forward) * (RIGHT_GAIN * angle) - p_chassis.angular_velocity * RIGHT_DAMP;
		V3 alpha_body = R.transposed() * alpha;
		m.torque += body_torque(p_config, R, alpha_body);
	} else if (air_time > AIR_AFTER) {
		// --- Air control: pitch with the pedals, yaw with the steering; roll (and pitch,
		// with the pedals off) settles toward upright.
		V3 tilt = R.transposed() * cross(up, world_up); // body axis * sin(angle) to upright
		double pedals = clampd(p_controls.throttle, 0.0, 1.0) - clampd(p_controls.brake, 0.0, 1.0);
		double steer = clampd(p_controls.steer, -1.0, 1.0);
		V3 a;
		a.x = std::abs(pedals) > 0.05 ? pedals * p.air_pitch : clampd(AIR_LEVEL * tilt.x, -p.air_pitch, p.air_pitch);
		a.y = -steer * p.air_yaw;
		a.z = clampd(AIR_LEVEL * tilt.z, -p.air_roll, p.air_roll);
		a -= V3(w_body.x, std::abs(steer) > 0.05 ? 0.0 : w_body.y, w_body.z) * AIR_DAMP;
		m.torque += body_torque(p_config, R, a);
	}

	// --- Stick gravity -------------------------------------------------------------------
	if (stick_n > 0) {
		stick_normal = normalized(stick_sum, up);
		stick = p.stick_hold;
	} else {
		stick = tick_down(stick, p_dt);
	}
	if (stick > 0.0) {
		double fade = clampd((speed - (p.stick_min_speed - STICK_FADE)) / STICK_FADE, 0.0, 1.0);
		m.force += (stick_normal * -g - p_gravity) * (mass * fade);
	}

	// --- Slipstream and pulls --------------------------------------------------------------
	m.force += pull * mass;
	return m;
}

} // namespace noss::vehicle
