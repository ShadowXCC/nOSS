#pragma once

#include <memory>

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
	void set_assists(bool p_abs, bool p_tcs, bool p_auto_gearbox, bool p_auto_clutch);
	void reset();

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
};

} // namespace noss
