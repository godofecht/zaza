// The Zaza-built top-level. It calls into mathlib, which Zaza built from the
// in-tree CMake subdirectory. No library path is written here: linkInto added
// the built archive and its headers.
#include <mathlib.h>
#include <stdio.h>

int main(void) {
    const int r = mathlib_square(7);
    printf("zaza top-level linked a CMake-built subdirectory: mathlib_square(7)=%d\n", r);
    return (r == 49) ? 0 : 1;
}
