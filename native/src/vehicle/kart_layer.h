#pragma once

// The kart_arcade layer (docs/PHYSICS.md §9, D130-D133): modifiers on the core sim for kart
// mode, not a separate sim. VehicleModel asks it once per tick for KartMods (grip, drift, power,
// drag, extra force and torque) and applies them at fixed points. Without a layer the model runs
// exactly as before.
//
// Every force is a mass times an acceleration, and every torque an inertia (the model's, which
// is the reference's for yaw) times an angular acceleration, so fitting never changes how a kart
// drifts, boosts or flies (docs/PLATFORMS.md §4.2).

#include <vector>

#include "vehicle/vmath.h"

namespace noss::vehicle {

struct Config;
struct Chassis;
struct Contact;
struct Controls;

// Collider tags, the "noss_tag" meta next to "noss_surface" (D133). A wheel on a tagged collider
// reports the tag in its Contact.
enum ContactTag {
	TAG_BOOST = 1, // boost pad
	TAG_JUMP = 2, // jump ramp: opens the trick window on take-off
	TAG_STICK = 4, // wall-ride and loop: gravity follows the surface
};

// What happens to a kart (items, KartLayer::effect).
enum KartEffect {
	KART_BOOST, // value = seconds
	KART_SPIN, // value = seconds; p_dir = +1 spins left, -1 right
	KART_SLOW, // value = seconds; p_dir = power share left (0 = none)
	KART_CANCEL, // ends boosts, spins and slows (a tow)
};

// KartLayer::flags(): the native part of CarState's kart word (D142).
enum KartFlag {
	KART_FLAG_DRIFT_LEFT = 1,
	KART_FLAG_DRIFT_RIGHT = 2,
	KART_FLAG_TIER_SHIFT = 2, // bits 2-3: the drift's charge tier, 0-3
	KART_FLAG_BOOST = 16,
	KART_FLAG_SPUN = 64,
	KART_FLAG_SLOWED = 128,
	KART_FLAG_TRICK = 512,
	KART_FLAG_AIRBORNE = 4096,
	KART_FLAG_STICK = 8192, // held to a wall-ride or loop by stick gravity
};

// The mode's "arcade" block (data/modes/kart.mode.json).
struct KartParams {
	double grip = 1.25; // every tire's friction
	// Drift: hold the button at speed while steering one way; the direction locks. Steering then
	// sets how tight it turns (a lateral acceleration in g, wide to tight) and how far the nose
	// points into the turn (body slip, rad). The tires slide (their side force is scaled down)
	// and the layer turns the kart along its arc, so a drift keeps its speed.
	double drift_min_speed = 8.0; // m/s
	double drift_min_steer = 0.3;
	double drift_turn_g[2] = { 0.15, 1.0 }; // the tires add about 0.4 g
	double drift_slip[2] = { 0.25, 0.45 };
	double drift_side_grip = 0.35; // the tires' side force while drifting
	double drift_tire_slip = 0.3; // share of their slip angle the tires feel (so they still drive)
	double drift_wheel_steer = 0.3; // share of the steering that turns the front wheels
	double drift_yaw_accel = 12.0; // rad/s^2, the most the drift turns the kart's yaw rate by
	double drift_hop = 0.8; // m/s up when the button goes down on the ground
	double drift_exit = 0.4; // s over which the tires get their grip back after a drift
	double drift_tiers[3] = { 0.6, 1.2, 2.0 }; // s of charge for each tier
	double drift_boost[3] = { 0.5, 0.9, 1.4 }; // s of boost each tier gives on release
	// Boost: extra drive, up to a share of the kart's geared top speed.
	double boost_accel = 6.0; // m/s^2
	double boost_cap = 1.25;
	double pad_s = 0.8;
	// In the air: target angular accelerations, rad/s^2.
	double air_pitch = 3.0;
	double air_roll = 3.0;
	double air_yaw = 2.0;
	double trick_window = 0.35; // s after leaving a jump in which the button does a trick
	double trick_boost = 0.6; // s, landing a trick upright
	// Stick gravity on wall-rides and loops.
	double stick_min_speed = 7.0; // m/s
	double stick_hold = 0.25; // s after the wheels leave the surface
	double right_after = 1.5; // s upside down before the kart rights itself
	double spin_s = 1.2;
	double spin_grip = 0.35;
	double spin_yaw_rate = 7.0; // rad/s
	double spin_brake = 10.0; // m/s^2: a spun kart slows, so it spins where it was hit
	double slow_power = 0.0;
};

// What the layer asks of the model this tick. The defaults change nothing.
struct KartMods {
	double grip = 1.0; // every tire's friction
	double lateral = 1.0; // the tires' side force
	double slip_seen = 1.0; // share of the slip angle the tire model sees
	double steer = 1.0; // share of the steering input that turns the wheels
	double power = 1.0; // engine drive
	double drag = 1.0; // aero drag
	bool free_clutch = false; // the engine doesn't hold the wheels back (boosting past its top)
	V3 force; // world, at the centre of mass
	V3 torque; // world
};

class KartLayer {
public:
	KartParams params;

	// Inputs, set by the game each tick.
	bool drift = false; // the drift button, held (its press does the hop or a trick)
	double drag_scale = 1.0; // slipstream (Magnet makes it stronger)
	V3 pull; // extra acceleration toward another kart (Magnet), world m/s^2

	// State. Read-only outside the layer.
	int drift_dir = 0; // +1 drifting right, -1 left, 0 not
	double charge = 0.0; // s of drift charge
	double drift_exit = 0.0; // s left of the grip coming back after a drift
	double boost = 0.0; // s of boost left
	double boost_length = 0.0; // s the latest boost was given
	double spin = 0.0; // s of spin-out left
	int spin_dir = 1;
	double slow = 0.0; // s of power cut left
	double slow_power = 0.0;
	double air_time = 0.0; // s with no wheel down
	double since_jump = 1e9; // s since a wheel was on a jump
	bool trick = false; // a trick is under way; landing it upright boosts
	double upside = 0.0; // s upside down or stuck on the side
	double righting = 0.0; // s of righting left
	double stick = 0.0; // s of stick gravity left
	V3 stick_normal{ 0, 1, 0 };
	int grounded = 0; // wheels down this tick
	int boosts = 0; // boosts given so far (drift releases, pads, tricks, items)
	int tricks = 0; // tricks landed

	explicit KartLayer(const KartParams &p_params = KartParams()) :
			params(p_params) {}

	// The modifiers for this tick, and the state machine stepped. p_gravity is the world's
	// gravity at the kart; p_rpm and p_limiter_rpm free the clutch at the top of a boost.
	KartMods begin(const Config &p_config, const Chassis &p_chassis, const std::vector<Contact> &p_contacts, const Controls &p_controls,
			const V3 &p_gravity, double p_rpm, double p_dt);
	void effect(int p_kind, double p_value, double p_dir = 1.0);
	// Back to driving normally (after a reset or a tow).
	void reset();
	// Charge tier, 0 (none) to 3.
	int tier() const;
	int flags() const;
	// The kart's top speed in its top gear at the limiter, m/s.
	static double geared_top(const Config &p_config);

private:
	bool _prev_drift = false;
	V3 _last_velocity;
	bool _has_last_velocity = false;
	void _give_boost(double p_seconds);
};

} // namespace noss::vehicle
