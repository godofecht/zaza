#include <iostream>

#include "generated_greeter.hpp"

int main() {
    std::cout << generated_headers::greeting() << '\n';
    return 0;
}
