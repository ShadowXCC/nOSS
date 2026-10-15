#pragma once

// Synthesized kart item sounds (D139, docs/ART_AUDIO.md): short one-shots, original sound, the
// same every time (seeded noise). Plain C++, no Godot types.

#include <cstdint>
#include <string>
#include <vector>

namespace noss::audio {

enum class FxKind {
	PICKUP, // a box: a quick rising arpeggio
	ROULETTE, // one tick of the roulette
	FIRE, // a Bolt, a Seeker or the Hunter away: a whoosh with a thump
	HIT, // a kart hit: a low thud and a crunch
	SHIELD, // a shield up: a shimmering rising chord
	EMP, // a deep falling pulse
	BOOST, // a rising rush
	TIER, // a drift tier reached: a bright chirp
	SLICK, // a Slick dropped: a splat
};

// The sound's kind from its name ("pickup", "roulette", ...); PICKUP if unknown.
FxKind fx_kind(const std::string &p_name);
// 16-bit mono at p_rate.
std::vector<int16_t> render_fx(FxKind p_kind, int p_rate = 44100);

} // namespace noss::audio
