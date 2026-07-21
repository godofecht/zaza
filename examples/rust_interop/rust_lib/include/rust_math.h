// C header for the rust_math static library.
// This file is consumed by Zig's C-import mechanism.

#ifndef RUST_MATH_H
#define RUST_MATH_H

#include <stdint.h>
#include <stddef.h>

int32_t rust_add(int32_t a, int32_t b);
uint64_t rust_factorial(uint32_t n);
size_t rust_strlen(const char *s);

#endif
