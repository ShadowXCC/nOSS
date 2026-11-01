#include "core/gpu_memory.h"

#ifndef __APPLE__ // gpu_memory_apple.mm

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan_core.h>

#include <vector>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace noss {

namespace {

void *open_library(const char *p_name) {
#ifdef _WIN32
	return reinterpret_cast<void *>(LoadLibraryA(p_name));
#else
	return dlopen(p_name, RTLD_NOW | RTLD_LOCAL);
#endif
}

void close_library(void *p_handle) {
#ifdef _WIN32
	FreeLibrary(reinterpret_cast<HMODULE>(p_handle));
#else
	dlclose(p_handle);
#endif
}

void *symbol(void *p_handle, const char *p_name) {
#ifdef _WIN32
	return reinterpret_cast<void *>(GetProcAddress(reinterpret_cast<HMODULE>(p_handle), p_name));
#else
	return dlsym(p_handle, p_name);
#endif
}

void *open_vulkan() {
#ifdef _WIN32
	return open_library("vulkan-1.dll");
#else
	void *handle = open_library("libvulkan.so.1");
	return handle ? handle : open_library("libvulkan.so");
#endif
}

// The largest device-local heap of a device.
uint64_t device_local(const VkPhysicalDeviceMemoryProperties &p_mem) {
	uint64_t most = 0;
	for (uint32_t i = 0; i < p_mem.memoryHeapCount; i++) {
		if (p_mem.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT && p_mem.memoryHeaps[i].size > most) {
			most = p_mem.memoryHeaps[i].size;
		}
	}
	return most;
}

uint64_t ask(PFN_vkGetInstanceProcAddr p_proc, const std::string &p_adapter_name) {
	auto create = reinterpret_cast<PFN_vkCreateInstance>(p_proc(nullptr, "vkCreateInstance"));
	if (!create) {
		return 0;
	}
	VkApplicationInfo app{};
	app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
	app.pApplicationName = "nOSS";
	app.apiVersion = VK_API_VERSION_1_0;
	VkInstanceCreateInfo info{};
	info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
	info.pApplicationInfo = &app;
	VkInstance instance = VK_NULL_HANDLE;
	if (create(&info, nullptr, &instance) != VK_SUCCESS) {
		return 0;
	}
	auto destroy = reinterpret_cast<PFN_vkDestroyInstance>(p_proc(instance, "vkDestroyInstance"));
	auto enumerate = reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(p_proc(instance, "vkEnumeratePhysicalDevices"));
	auto properties = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(p_proc(instance, "vkGetPhysicalDeviceProperties"));
	auto memory = reinterpret_cast<PFN_vkGetPhysicalDeviceMemoryProperties>(p_proc(instance, "vkGetPhysicalDeviceMemoryProperties"));
	uint64_t named = 0;
	uint64_t discrete = 0;
	uint64_t any = 0;
	uint32_t count = 0;
	if (enumerate && properties && memory && enumerate(instance, &count, nullptr) == VK_SUCCESS && count > 0) {
		std::vector<VkPhysicalDevice> devices(count);
		if (enumerate(instance, &count, devices.data()) >= VK_SUCCESS) { // VK_INCOMPLETE: those it gave
			for (uint32_t i = 0; i < count; i++) {
				VkPhysicalDeviceProperties props{};
				VkPhysicalDeviceMemoryProperties mem{};
				properties(devices[i], &props);
				memory(devices[i], &mem);
				uint64_t size = device_local(mem);
				if (!p_adapter_name.empty() && p_adapter_name == props.deviceName && size > named) {
					named = size;
				}
				if (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU && size > discrete) {
					discrete = size;
				}
				if (size > any) {
					any = size;
				}
			}
		}
	}
	if (destroy) {
		destroy(instance, nullptr);
	}
	return named ? named : discrete ? discrete : any;
}

} // namespace

uint64_t gpu_memory_bytes(const std::string &adapter_name) {
	void *lib = open_vulkan();
	if (!lib) {
		return 0;
	}
	uint64_t size = 0;
	if (auto proc = reinterpret_cast<PFN_vkGetInstanceProcAddr>(symbol(lib, "vkGetInstanceProcAddr"))) {
		size = ask(proc, adapter_name);
	}
	close_library(lib);
	return size;
}

} // namespace noss

#endif
