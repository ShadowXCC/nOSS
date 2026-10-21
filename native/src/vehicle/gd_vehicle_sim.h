#pragma once

#include <memory>
#include <optional>

#include <godot_cpp/classes/physics_direct_body_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>

#include "vehicle/vehicle_model.h"

namespace noss {

// Script-facing vehicle sim. The vehicle's RigidBody3D calls integrate(state) from
// _integrate_forces; the sim casts the wheel rays and applies its force and torque.
class VehicleSim : public godot::RefCounted {
	GDCLASS(VehicleSim, godot::RefCounted)

	std::unique_ptr<vehicle::VehicleModel> _model;
	godot::Ref<godot::PhysicsRayQueryParameters3D> _ray;
	godot::String _error;
	double _reference_rack = 9.0;
	std::optional<vehicle::KartParams> _arcade;

protected:
	static void _bind_methods();

public:
	VehicleSim();

	// Calling it again keeps engine, gearbox and wheel state (hotswap).
	// platform: a validated platform with defaults merged (PlatformLoader).
	// geometry: Fitting's physics wheels, see parse_geometry().
	bool configure(const godot::Dictionary &p_platform, const godot::Dictionary &p_geometry);
	godot::String get_error() const { return _error; }
	// {mass, center_of_mass, inertia} for the RigidBody3D.
	godot::Dictionary get_body_params() const;

	void integrate(godot::PhysicsDirectBodyState3D *p_state);
	void set_exclude(const godot::TypedArray<godot::RID> &p_exclude);
	void set_collision_mask(int64_t p_mask);

	void set_controls(double p_steer, double p_throttle, double p_brake, double p_handbrake, double p_clutch);
	void shift(int64_t p_direction);
	void select_gear(int64_t p_gear);
	void set_assists(const godot::Dictionary &p_assists);
	// Water and snow on the road (0..1 each, ENV-02); both 0 is the dry sim exactly.
	void set_conditions(double p_wetness, double p_snow);
	godot::Vector2 get_conditions() const;
	// Flat tyres (a spike strip): bit i for wheel i, 0 for none.
	void set_flats(int64_t p_mask);
	int64_t get_flats() const;
	// A surface's grip in these conditions (AI speeds, the HUD).
	static double grip_of(int64_t p_surface, double p_wetness, double p_snow);
	void reset();
	void roll_at(double p_speed);

	double get_speed() const;
	double get_rpm() const;
	int64_t get_gear() const;
	bool is_shifting() const;
	int64_t get_wheel_count() const;
	// (steer rad + = left, spin rad, suspension lift m + = up, contact 0/1)
	godot::Vector4 get_wheel_visual(int64_t p_index) const;
	// Rack torque over the platform's reference, + = pulls the wheel left.
	double get_rack_force() const;
	double get_throttle() const;
	double get_brake() const;
	double get_engine_load() const;
	// Body-frame acceleration, m/s^2 (without gravity).
	godot::Vector3 get_acceleration() const;
	godot::Dictionary get_telemetry() const;

	// The kart_arcade layer (D130): a mode's "arcade" block, or {} for none. It stays through
	// configure() (hotswap).
	void set_layer(const godot::Dictionary &p_arcade);
	bool has_layer() const;
	void set_kart_input(bool p_drift);
	// Slipstream drag share, and a pull toward another kart (m/s^2, world): set at 30 Hz.
	void set_kart_drag(double p_scale);
	void set_kart_pull(const godot::Vector3 &p_accel);
	// KART_BOOST (value s), KART_SPIN (value s, dir +1 left / -1 right), KART_SLOW (value s,
	// dir = power left), KART_CANCEL.
	void kart_effect(int64_t p_kind, double p_value, double p_dir);
	int64_t get_kart_flags() const;
	godot::Dictionary get_kart_state() const;
	double get_geared_top() const;
};

} // namespace noss
