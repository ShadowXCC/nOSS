#pragma once

// Synthesized weather and ambience (D153, docs/ART_AUDIO.md §7): rain, wind, surf, crickets and
// birds as seamless loops, thunder as a one-shot. Original sound, the same every time (seeded
// noise). Plain C++, no Godot types.

#include <cstdint>
#include <string>
#include <vector>

namespace noss::audio {

enum class WeatherSound {
	RAIN, // steady rain: noise only, a hiss of far drops, the fizz of near ones, a few pats (loop)
	WIND, // gusting wind (loop)
	THUNDER, // a crack and a long rumble (one-shot)
	SURF, // waves on a shore, a swell every few seconds (loop)
	CRICKETS, // night: chirping insects (loop)
	BIRDS, // day: a few birds calling (loop)
};

// Its kind from its name ("rain", "wind", ...); RAIN if unknown.
WeatherSound weather_sound(const std::string &p_name);
// Loops are exactly their length and join seamlessly. 16-bit mono at p_rate.
std::vector<int16_t> render_weather(WeatherSound p_kind, int p_rate = 44100);
// True for the loops (all but thunder).
bool weather_loops(WeatherSound p_kind);

} // namespace noss::audio
