#pragma once

#define HELLO_VEX_PUBLIC 1
#define HELLO_VEX_PRIVATE 1

inline const char* hello_vex_banner() {
    return "hello from zig build system";
}
