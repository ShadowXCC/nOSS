#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace noss {

// Script access to the engine synth (engine_synth.h), e.g. NossAudio.render_loop().
class NossAudio : public godot::Object {
	GDCLASS(NossAudio, godot::Object)

protected:
	static void _bind_methods();

public:
	// p_profile: a data/sound_profiles/<id>.json synth block. p_emitter: engine, exhaust or
	// intake. Returns {data: 16-bit mono PCM (PackedByteArray), rpm (exact), rate}.
	static godot::Dictionary render_loop(const godot::Dictionary &p_profile, double p_rpm, double p_load, const godot::String &p_emitter, double p_length_s);
};

} // namespace noss
