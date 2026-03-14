#pragma once

#define HELLO_ZAZA_PUBLIC 1
#define HELLO_ZAZA_PRIVATE 1

inline const char* hello_zaza_banner() {
    return "hello from zig build system";
}
