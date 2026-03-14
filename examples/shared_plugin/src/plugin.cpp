#include <cstdint>

extern "C" const char* zaza_plugin_name() {
    return "shared_plugin";
}

extern "C" int32_t zaza_plugin_compute(int32_t value) {
    return (value * 6) + 6;
}
