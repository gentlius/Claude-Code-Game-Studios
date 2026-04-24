// register_types.cpp — GDExtension entry point.
// Entry symbol: "markov_generator_init" (must match [configuration].entry_symbol in .gdextension)

#include "register_types.h"
#include "markov_generator.h"
#include "price_kernel.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

void initialize_markov_generator_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    ClassDB::register_class<MarkovGenerator>();
    ClassDB::register_class<PriceKernel>();
}

void uninitialize_markov_generator_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    // Nothing to clean up — MarkovGenerator and PriceKernel are RefCounted.
}

extern "C" {

GDExtensionBool GDE_EXPORT markov_generator_init(
        GDExtensionInterfaceGetProcAddress p_get_proc_address,
        const GDExtensionClassLibraryPtr p_library,
        GDExtensionInitialization *r_initialization) {

    GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_markov_generator_module);
    init_obj.register_terminator(uninitialize_markov_generator_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}

} // extern "C"
