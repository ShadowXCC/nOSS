#pragma once

#include <cstdint>
#include <string>

namespace noss {

// How much memory the graphics card has, in bytes; 0 if it can't tell. Linux and Windows ask
// Vulkan through an instance of their own (so it works whatever Godot draws with, D3D12 too):
// the largest device-local heap of the device named `adapter_name` (Godot's
// RenderingServer.get_video_adapter_name()), else the discrete one with the most. macOS asks
// Metal for the device's recommended working set (D247). Slow (tens of ms): call it once.
uint64_t gpu_memory_bytes(const std::string &adapter_name);

} // namespace noss
