#include <iostream>

#include "package_math.hpp"

int main() {
    const int result = package_math::mul_add(5, 8, 2);
    std::cout << "package consumer result: " << result << '\n';
    return 0;
}
