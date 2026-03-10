#include <cstdint>

extern "C" const char* vex_plugin_name() {
    return "shared_plugin";
}

extern "C" int32_t vex_plugin_compute(int32_t value) {
    return (value * 6) + 6;
}
