#include "vehicle/gd_conformance.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <thread>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

#include "vehicle/gd_platform.h"
#include "vehicle/maneuvers.h"

using namespace godot;
using namespace noss::vehicle;

namespace noss {

namespace {

struct Job {
	Config config;
	ManeuverSpec spec;
	std::string error;
	ManeuverResult result;
};

void read_number(const Dictionary &p_options, const char *p_key, double &r_value) {
	Variant v = p_options.get(p_key, Variant());
	if (v.get_type() == Variant::FLOAT || v.get_type() == Variant::INT) {
		r_value = double(v);
	}
}

ManeuverSpec read_spec(const String &p_maneuver, const Dictionary &p_options) {
	ManeuverSpec s;
	s.name = p_maneuver.utf8().get_data();
	PackedVector2Array track = p_options.get("track", PackedVector2Array());
	for (int64_t i = 0; i < track.size(); i++) {
		s.track.emplace_back(track[i].x, track[i].y);
	}
	double gates = s.slalom_gates;
	read_number(p_options, "track_width", s.track_width);
	read_number(p_options, "track_start_s", s.track_start_s);
	read_number(p_options, "lap_runup", s.lap_runup);
	read_number(p_options, "skidpad_radius", s.skidpad_radius);
	read_number(p_options, "slalom_spacing", s.slalom_spacing);
	read_number(p_options, "slalom_gates", gates);
	read_number(p_options, "slalom_max_error", s.slalom_max_error);
	read_number(p_options, "step_speed", s.step_speed);
	read_number(p_options, "step_lateral_g", s.step_lateral_g);
	read_number(p_options, "top_speed_time", s.top_speed_time);
	read_number(p_options, "pace", s.pace);
	s.slalom_gates = std::max(int(gates), 2);
	return s;
}

} // namespace

void NossConformance::_bind_methods() {
	ClassDB::bind_static_method("NossConformance", D_METHOD("run_batch", "jobs", "threads"), &NossConformance::run_batch, DEFVAL(0));
	ClassDB::bind_static_method("NossConformance", D_METHOD("maneuvers"), &NossConformance::maneuvers);
}

Array NossConformance::run_batch(const Array &p_jobs, int64_t p_threads) {
	// Godot types are only touched here, on the calling thread.
	std::vector<Job> jobs(size_t(p_jobs.size()));
	for (int64_t i = 0; i < p_jobs.size(); i++) {
		Job &job = jobs[size_t(i)];
		Dictionary d = p_jobs[i];
		PlatformSpec platform = parse_platform(d.get("platform", Dictionary()));
		Geometry geometry;
		String error;
		if (platform.engine.torque_curve.size() < 2 || platform.gearbox.ratios.empty()) {
			job.error = "Platform has no engine or gearbox";
		} else if (!parse_geometry(d.get("geometry", Dictionary()), geometry, error)) {
			job.error = error.utf8().get_data();
		} else {
			job.config = make_config(platform, geometry);
		}
		job.spec = read_spec(d.get("maneuver", ""), d.get("options", Dictionary()));
	}

	std::atomic<size_t> next{ 0 };
	auto worker = [&]() {
		for (size_t i = next++; i < jobs.size(); i = next++) {
			if (jobs[i].error.empty()) {
				jobs[i].result = run_maneuver(jobs[i].config, jobs[i].spec);
			}
		}
	};
	size_t threads = p_threads > 0 ? size_t(p_threads) : std::max(1u, std::thread::hardware_concurrency());
	threads = std::min(threads, std::max<size_t>(jobs.size(), 1));
	std::vector<std::thread> pool;
	for (size_t t = 1; t < threads; t++) {
		pool.emplace_back(worker);
	}
	worker();
	for (std::thread &t : pool) {
		t.join();
	}

	Array out;
	for (const Job &job : jobs) {
		Dictionary r;
		std::string error = job.error.empty() ? job.result.error : job.error;
		r["ok"] = error.empty();
		r["error"] = String::utf8(error.c_str());
		Dictionary metrics;
		for (const Metric &m : job.result.metrics) {
			metrics[String::utf8(m.name.c_str())] = std::isfinite(m.value) ? Variant(m.value) : Variant();
		}
		r["metrics"] = metrics;
		out.push_back(r);
	}
	return out;
}

PackedStringArray NossConformance::maneuvers() {
	PackedStringArray out;
	for (const std::string &name : maneuver_names()) {
		out.push_back(String::utf8(name.c_str()));
	}
	return out;
}

} // namespace noss
