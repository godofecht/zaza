#include <cstdint>
#include <cstdlib>
#include <iostream>

#include <dlfcn.h>

using plugin_name_fn = const char* (*)();
using plugin_compute_fn = int32_t (*)(int32_t);

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "missing plugin path\n";
        return 1;
    }

    void* handle = dlopen(argv[1], RTLD_NOW);
    if (handle == nullptr) {
        std::cerr << "dlopen failed: " << dlerror() << '\n';
        return 1;
    }

    const auto plugin_name = reinterpret_cast<plugin_name_fn>(dlsym(handle, "vex_plugin_name"));
    const auto plugin_compute = reinterpret_cast<plugin_compute_fn>(dlsym(handle, "vex_plugin_compute"));
    if (plugin_name == nullptr || plugin_compute == nullptr) {
        std::cerr << "dlsym failed\n";
        dlclose(handle);
        return 1;
    }

    std::cout << "plugin name: " << plugin_name() << '\n';
    std::cout << "plugin result: " << plugin_compute(6) << '\n';
    dlclose(handle);
    return 0;
}
