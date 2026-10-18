#pragma once

#include <string>

namespace noss {

struct Version {
	int major = 0;
	int minor = 0;
	int patch = 0;
};

// Must match application/config/version in project.godot (checked by tests).
inline constexpr Version core_version{ 0, 10, 0 };

inline std::string to_string(const Version &p_version) {
	return std::to_string(p_version.major) + "." + std::to_string(p_version.minor) + "." + std::to_string(p_version.patch);
}

} // namespace noss
