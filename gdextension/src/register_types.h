// register_types.h — GDExtension module init/deinit declarations.
#pragma once
#include <godot_cpp/core/class_db.hpp>

void initialize_markov_generator_module(godot::ModuleInitializationLevel p_level);
void uninitialize_markov_generator_module(godot::ModuleInitializationLevel p_level);
