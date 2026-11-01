// macOS: the graphics card's memory from Metal (gpu_memory.cpp has Linux and Windows). Built
// only on macOS (SConstruct); untested so far, as there's no Mac build yet (D247).

#include "core/gpu_memory.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

namespace noss {

uint64_t gpu_memory_bytes(const std::string &adapter_name) {
	(void)adapter_name; // the system's default device is the one Godot draws with
	uint64_t size = 0;
	@autoreleasepool {
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (device != nil) {
			// What Metal says the device can use before performance suffers: the card's memory on
			// a discrete GPU, a share of RAM on Apple silicon.
			size = [device recommendedMaxWorkingSetSize];
#if !__has_feature(objc_arc)
			[device release];
#endif
		}
	}
	return size;
}

} // namespace noss
