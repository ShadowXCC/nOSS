#pragma once

// Ambient music for the endless road (D157, docs/ART_AUDIO.md §7): a slow chord progression on
// soft detuned pads, a quiet bass and a few bell notes over it, with an echo, as a seamless loop.
// Each seed gives its own key, progression and melody. Original sound. Plain C++, no Godot types.

#include <cstdint>
#include <vector>

namespace noss::audio {

constexpr int MUSIC_CHORDS = 8;
constexpr double MUSIC_CHORD_S = 8.0; // each chord's length; the loop is 64 s

// 16-bit mono at p_rate, MUSIC_CHORDS * MUSIC_CHORD_S long.
std::vector<int16_t> render_music(uint32_t p_seed, int p_rate = 44100);

} // namespace noss::audio
