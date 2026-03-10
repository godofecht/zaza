#include "mixed_bridge.h"

#include "mixed_core.h"

extern "C" int mixed_bridge_compute(int value) {
    return mixed_core_scale_add(value, 5, 7);
}
