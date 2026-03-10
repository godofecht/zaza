#include <iostream>

#include "package_math.hpp"

int main() {
    std::cout << "package producer demo: "
              << package_math::mul_add(6, 7, 3)
              << '\n';
    return 0;
}
