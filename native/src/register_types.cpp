#include <gdextension_interface.h>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "audio/gd_audio.h"
#include "core/noss_core.h"
#include "endless/gd_road_gen.h"
#include "input/gd_input.h"
#include "mesh/gd_mesh.h"
#include "package/gd_package.h"
#include "traffic/gd_traffic.h"
#include "vehicle/gd_conformance.h"
#include "vehicle/gd_vehicle_sim.h"
#include "world/gd_terrain.h"

using namespace godot;

static void initialize_noss_core(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_ABSTRACT_CLASS(noss::NossCore);
	GDREGISTER_ABSTRACT_CLASS(noss::NossPackage);
	GDREGISTER_CLASS(noss::VehicleSim);
	GDREGISTER_ABSTRACT_CLASS(noss::NossInput);
	GDREGISTER_ABSTRACT_CLASS(noss::NossConformance);
	GDREGISTER_ABSTRACT_CLASS(noss::NossMesh);
	GDREGISTER_ABSTRACT_CLASS(noss::NossAudio);
	GDREGISTER_CLASS(noss::NossSurfaceMap);
	GDREGISTER_CLASS(noss::NossTerrain);
	GDREGISTER_CLASS(noss::NossTraffic);
	GDREGISTER_CLASS(noss::NossRoadGen);
}

static void uninitialize_noss_core(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_SCENE) {
		noss::NossInput::stop(); // joins the FFB thread before the library unloads
	}
}

extern "C" {

GDExtensionBool GDE_EXPORT noss_core_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_noss_core);
	init_obj.register_terminator(uninitialize_noss_core);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}

} // extern "C"
