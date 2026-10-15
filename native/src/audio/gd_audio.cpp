#include "audio/gd_audio.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <algorithm>

#include "audio/engine_synth.h"
#include "audio/fx_synth.h"
#include "audio/siren_synth.h"
#include "audio/tire_synth.h"

using namespace godot;
using namespace noss::audio;

namespace noss {

namespace {

double num(const Dictionary &p_d, const char *p_key, double p_default) {
	Variant v = p_d.get(p_key, Variant());
	return (v.get_type() == Variant::FLOAT || v.get_type() == Variant::INT) ? double(v) : p_default;
}

EngineProfile read_profile(const Dictionary &p) {
	EngineProfile e;
	Array fire = p.get("fire_deg", Array());
	Array bank = p.get("bank", Array());
	for (int64_t i = 0; i < fire.size(); i++) {
		e.fire_deg.push_back(double(fire[i]));
		e.bank.push_back(i < bank.size() ? int(bank[i]) : 0);
	}
	Array ex = p.get("exhaust_hz", Array());
	for (int i = 0; i < 2; i++) {
		e.exhaust_hz[i] = ex.size() > i ? double(ex[i]) : (ex.size() > 0 ? double(ex[0]) : e.exhaust_hz[i]);
	}
	Array delay = p.get("exhaust_delay_ms", Array());
	for (int i = 0; i < 2 && i < delay.size(); i++) {
		e.exhaust_delay_ms[i] = double(delay[i]);
	}
	e.pulse_ms = num(p, "pulse_ms", e.pulse_ms);
	e.exhaust_q = num(p, "exhaust_q", e.exhaust_q);
	e.muffler_hz = num(p, "muffler_hz", e.muffler_hz);
	e.intake_hz = num(p, "intake_hz", e.intake_hz);
	e.intake_q = num(p, "intake_q", e.intake_q);
	e.intake_noise = num(p, "intake_noise", e.intake_noise);
	e.mechanical = num(p, "mechanical", e.mechanical);
	e.harshness = num(p, "harshness", e.harshness);
	e.jitter = num(p, "jitter", e.jitter);
	e.electric = bool(p.get("electric", false));
	e.motor_order = num(p, "motor_order", e.motor_order);
	e.inverter_order = num(p, "inverter_order", e.inverter_order);
	return e;
}

} // namespace

void NossAudio::_bind_methods() {
	ClassDB::bind_static_method("NossAudio", D_METHOD("render_loop", "profile", "rpm", "load", "emitter", "length_s"), &NossAudio::render_loop, DEFVAL(0.5));
	ClassDB::bind_static_method("NossAudio", D_METHOD("render_tire_loop", "params", "length_s"), &NossAudio::render_tire_loop, DEFVAL(2.5));
	ClassDB::bind_static_method("NossAudio", D_METHOD("render_siren", "kind"), &NossAudio::render_siren);
	ClassDB::bind_static_method("NossAudio", D_METHOD("render_horn", "f1", "f2"), &NossAudio::render_horn);
	ClassDB::bind_static_method("NossAudio", D_METHOD("render_fx", "kind"), &NossAudio::render_fx);
}

namespace {

PackedByteArray pcm_bytes(const std::vector<int16_t> &p_samples) {
	PackedByteArray data;
	data.resize(int64_t(p_samples.size() * 2));
	for (size_t i = 0; i < p_samples.size(); i++) {
		data.encode_s16(int64_t(i * 2), p_samples[i]);
	}
	return data;
}

} // namespace

PackedByteArray NossAudio::render_siren(const String &p_kind) {
	return pcm_bytes(audio::render_siren(p_kind == "yelp" ? audio::SirenKind::YELP : audio::SirenKind::WAIL));
}

PackedByteArray NossAudio::render_fx(const String &p_kind) {
	return pcm_bytes(audio::render_fx(audio::fx_kind(p_kind.utf8().get_data())));
}

PackedByteArray NossAudio::render_horn(double p_f1, double p_f2) {
	return pcm_bytes(audio::render_horn(std::clamp(p_f1, 50.0, 4000.0), std::clamp(p_f2, 50.0, 4000.0)));
}

PackedByteArray NossAudio::render_tire_loop(const Dictionary &p_params, double p_length_s) {
	TireProfile t;
	Array bands = p_params.get("bands", Array());
	for (int64_t i = 0; i < bands.size() && i < 8; i++) {
		Array b = bands[i];
		if (b.size() >= 3) {
			t.bands.push_back({ double(b[0]), double(b[1]), double(b[2]) });
		}
	}
	t.tone = num(p_params, "tone", t.tone);
	t.tone_hz = num(p_params, "tone_hz", t.tone_hz);
	t.drift = num(p_params, "drift", t.drift);
	t.drift_hz = num(p_params, "drift_hz", t.drift_hz);
	t.flutter = num(p_params, "flutter", t.flutter);
	t.flutter_hz = num(p_params, "flutter_hz", t.flutter_hz);
	std::vector<int16_t> samples = audio::render_tire_loop(t, 44100, std::clamp(p_length_s, 0.1, 10.0), uint32_t(num(p_params, "seed", 1)));
	PackedByteArray data;
	data.resize(int64_t(samples.size() * 2));
	for (size_t i = 0; i < samples.size(); i++) {
		data.encode_s16(int64_t(i * 2), samples[i]);
	}
	return data;
}

Dictionary NossAudio::render_loop(const Dictionary &p_profile, double p_rpm, double p_load, const String &p_emitter, double p_length_s) {
	Emitter emitter = p_emitter == "exhaust" ? Emitter::EXHAUST : p_emitter == "intake" ? Emitter::INTAKE : Emitter::ENGINE;
	Loop loop = audio::render_loop(read_profile(p_profile), p_rpm, p_load, emitter, 44100, p_length_s, uint32_t(num(p_profile, "seed", 1)));
	PackedByteArray data;
	data.resize(int64_t(loop.samples.size() * 2));
	for (size_t i = 0; i < loop.samples.size(); i++) {
		data.encode_s16(int64_t(i * 2), loop.samples[i]);
	}
	Dictionary d;
	d["data"] = data;
	d["rpm"] = loop.rpm;
	d["rate"] = 44100;
	return d;
}

} // namespace noss
