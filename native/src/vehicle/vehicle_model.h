#pragma once

// The sim-cade vehicle model (docs/PHYSICS.md). Plain C++, no Godot types, so it can be
// unit tested with its own rigid-body harness. VehicleSim (gd_vehicle_sim) feeds it Jolt's
// chassis state and wheel ray hits, and applies the force and torque it returns.
//
// Body frame (the fitted model frame): +X left, +Y up, +Z forward, metres.

#include <climits>
#include <vector>

#include "vehicle/drivetrain.h"
#include "vehicle/tire.h"
#include "vehicle/vmath.h"

namespace noss::vehicle {

constexpr double GRAVITY = 9.81;
constexpr double AIR_DENSITY = 1.225;
constexpr int SUBSTEPS = 4;

enum class Drive {
	FWD,
	RWD,
	AWD,
};

enum class DiffType {
	OPEN,
	LSD_CLUTCH,
	LOCKED,
};

// An axle's differential (docs/PHYSICS.md §5). Spool is LOCKED.
struct DiffSpec {
	DiffType type = DiffType::OPEN;
	double preload = 0.0; // Nm
	double power_lock = 0.0; // share of the input torque that can lock it on power
	double coast_lock = 0.0;
};

enum class CenterType {
	OPEN,
	VISCOUS,
	LOCKED,
};

// Between the front and rear axles of an AWD layout.
struct CenterDiffSpec {
	CenterType type = CenterType::OPEN;
	double front_share = 0.5; // of the drive torque, when open
	double viscous = 0.0; // Nm per rad/s of front/rear speed difference
	double preload = 0.0; // Nm
};

// Surface ids, set on colliders as the "noss_surface" meta (docs/PHYSICS.md §4).
enum Surface {
	SURFACE_ASPHALT,
	SURFACE_CONCRETE,
	SURFACE_CURB,
	SURFACE_PAINT,
	SURFACE_GRASS,
	SURFACE_GRAVEL,
	SURFACE_DIRT,
	SURFACE_SAND,
	SURFACE_SNOW,
	SURFACE_ICE,
	SURFACE_COUNT,
};

struct SurfaceInfo {
	double grip;
	double drag; // extra rolling resistance coefficient
};

const SurfaceInfo &surface_info(int p_surface);

struct AxleSpec {
	double freq_hz = 2.0;
	double damping_bump = 0.45;
	double damping_rebound = 0.65;
	double travel = 0.1; // m from static to the bump stop (and to full droop)
	bool steer = false;
	bool driven = false;
};

// The platform's numbers (docs/PLATFORMS.md §2), in SI units.
struct PlatformSpec {
	double mass = 1300.0;
	double front_weight = 0.5;
	double cog_height_over_track = 0.3;
	double yaw_dynamic_index = 1.0;
	double wheelbase_ref = 2.6;
	double track_ref = 1.6;
	double wheel_radius_ref = 0.33;
	Drive drive = Drive::RWD;
	EngineSpec engine;
	GearboxSpec gearbox;
	DiffSpec axle_diff[2]; // front, rear
	CenterDiffSpec center;
	double brake_torque = 5000.0; // Nm total at full pedal
	double brake_bias_front = 0.6;
	double handbrake_torque = 2500.0; // Nm on the rear axle
	AxleSpec axles[2];
	bool rigid = false; // kart-style: a stiff contact spring instead of a suspension
	double roll_gradient_deg_per_g = 1.5;
	double roll_front_share = 0.55;
	double max_steer_deg = 30.0;
	double cd_a = 0.7;
	double cl_a_front = 0.0;
	double cl_a_rear = 0.0;
	TireParams tire;
	double relaxation_length = 0.25;
	double rolling_resistance = 0.012;
	double wheel_inertia = 0.0; // kg m^2 per wheel; 0 = from mass and wheel radius
	double ffb_reference_nm = 9.0;
};

struct WheelGeometry {
	V3 hub; // static hub center, body frame
	double radius = 0.3; // contact offset: the hub's height above the ground
	double visual_radius = 0.0; // the drawn wheel's, for its spin; 0 = radius
	int axle = 0; // 0 front, 1 rear
	int side = 1; // +1 left, -1 right
};

// Fitted geometry (docs/PLATFORMS.md §4.1), body frame.
struct Geometry {
	std::vector<WheelGeometry> wheels;
	double ground_y = 0.0;
};

struct WheelConfig {
	WheelGeometry geo;
	// Horizontal offset (body x, z) from the fitted hub to where its tire forces act in the
	// ground plane: the hub's position at the reference wheelbase and track.
	double plane_dx = 0.0;
	double plane_dz = 0.0;
	bool steer = false;
	bool driven = false;
	double static_load = 0.0; // N
	double k = 0.0; // spring, N/m
	double c_bump = 0.0; // damper, N s/m
	double c_rebound = 0.0;
	double travel = 0.1;
	double brake_share = 0.25; // of the total brake torque
	double drive_share = 0.0; // of the drive torque (all driven wheels add up to 1)
	double bump_zone = 0.015; // m before full travel where the bump stop builds up
	double k_beyond = 0.0; // N/m past full travel
};

// Everything derived from platform + geometry, keeping handling equal across fits (§4.2).
struct Config {
	PlatformSpec spec;
	std::vector<WheelConfig> wheels;
	double mass = 0.0;
	V3 com; // body frame
	V3 inertia; // principal moments about body x (pitch), y (yaw), z (roll)
	double wheelbase = 0.0;
	double track = 0.0;
	double axle_track[2] = { 0.0, 0.0 };
	V3 axle_center[2]; // body frame, at hub height
	double k_arb[2] = { 0.0, 0.0 };
	// Roll damping bar per axle, N s/m between the two sides: brings each wheel's roll damping
	// to what it is at the reference track. Negative on wide tracks.
	double c_roll[2] = { 0.0, 0.0 };
	// Extra CoG depth for the pitch moment of the longitudinal tire forces, so longitudinal
	// load transfer matches the reference geometry (docs/PLATFORMS.md §4.2).
	double pitch_arm_delta = 0.0;
	double max_steer = 0.5; // rad at full input
	double r_ref = 0.33;
	double wheel_inertia = 1.2;
	double axle_drive_share[2] = { 0.0, 0.0 };
	double clutch_max = 900.0; // Nm
	double cog_height = 0.0;
};

Config make_config(const PlatformSpec &p_spec, const Geometry &p_geometry);

struct Controls {
	double steer = 0.0; // -1..1, + = right
	double throttle = 0.0;
	double brake = 0.0;
	double clutch = 0.0; // 1 = pedal down (disengaged)
	double handbrake = 0.0;
	int shift = 0; // +1 up, -1 down, consumed by step()
	int select_gear = INT_MIN; // direct gear request (H-shifter), consumed by step()
};

struct Assists {
	bool abs = true;
	bool tcs = true;
	bool auto_gearbox = true;
	bool auto_clutch = true;
	bool stability = false;
};

struct Chassis {
	M3 basis; // body to world rotation
	V3 origin; // body origin, world
	V3 com; // centre of mass, world
	V3 velocity; // of the centre of mass
	V3 angular_velocity; // world
};

struct Ray {
	V3 origin;
	V3 direction;
	double length = 0.0;
};

struct Contact {
	bool hit = false;
	V3 point;
	V3 normal{ 0, 1, 0 };
	double distance = 0.0;
	int surface = SURFACE_ASPHALT;
	V3 ground_velocity;
};

struct StepResult {
	V3 force; // world, at the centre of mass
	V3 torque; // world, about the centre of mass
};

struct WheelState {
	double omega = 0.0; // rad/s, + = rolling forward
	double spin_angle = 0.0; // visual, rad
	double deflection = 0.0; // lateral carcass deflection, m (relaxation length state)
	double disp = 0.0; // suspension, m from static, + = compressed
	double fz = 0.0;
	double fx = 0.0;
	double fy = 0.0;
	double mz = 0.0;
	double kappa = 0.0;
	double tan_alpha = 0.0;
	double slip_speed = 0.0; // contact patch sliding speed, m/s
	double steer = 0.0; // rad, + = left
	double abs_factor = 1.0;
	bool contact = false;
	int surface = SURFACE_ASPHALT;
};

class VehicleModel {
public:
	explicit VehicleModel(const Config &p_config);

	const Config &config() const { return _config; }

	Controls controls;
	Assists assists;

	// Ray each wheel casts this tick; the caller fills a Contact per wheel.
	Ray wheel_ray(int p_index, const Chassis &p_chassis) const;
	StepResult step(const Chassis &p_chassis, const std::vector<Contact> &p_contacts, double p_dt);
	// Stops wheels and engine, e.g. after a reset. Keeps the gear unless it's reverse.
	void reset();
	// Takes over engine, gearbox, wheel spin and assist state from p_other (hotswap).
	void take_state(const VehicleModel &p_other);

	std::vector<WheelState> wheels;
	Gearbox gearbox;
	double engine_omega = 0.0;

	// Outputs, refreshed by step().
	double forward_speed = 0.0; // m/s
	double throttle_out = 0.0; // after assists and fuel cut
	double brake_out = 0.0;
	double clutch_out = 1.0; // engagement 0..1
	double engine_load = 0.0; // fraction of available torque
	bool abs_active = false;
	bool tcs_active = false;
	bool stability_active = false;
	int grinds = 0; // refused gear changes so far (H-pattern without the clutch)
	double rack_torque = 0.0; // Nm about the steering axis, + = turns the wheels left
	V3 acceleration; // body frame, m/s^2 (for g-forces)
	double rpm() const { return engine_omega / RPM_TO_RAD; }

private:
	Config _config;
	AutoShifter _auto;
	double _tcs_factor = 1.0;
	double _auto_clutch = 0.0;
	bool _fuel_cut = false;
	bool _has_last_velocity = false;
	V3 _last_velocity;
	std::vector<int> _driven;

	void _update_gearbox(double p_driver_throttle, double p_driver_brake, double p_dt);
	double _driven_omega() const;
};

} // namespace noss::vehicle
