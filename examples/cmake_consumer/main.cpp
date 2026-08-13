// Consumes package_math, a library Zaza built and exported as a CMake package.
// The include comes from the imported target's INTERFACE_INCLUDE_DIRECTORIES;
// the symbols come from its IMPORTED_LOCATION. This file writes neither path.
#include <package_math.hpp>
#include <cstdio>

int main() {
    const int sum = package_math::add(2, 3);
    const int mul_add = package_math::mul_add(2, 3, 4);
    std::printf(
        "cmake consumer linked zaza-built package_math: add(2,3)=%d, mul_add(2,3,4)=%d\n",
        sum, mul_add);
    return (sum == 5 && mul_add == 10) ? 0 : 1;
}
