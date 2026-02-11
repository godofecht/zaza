#include <iostream>
#include "hello_vex.h"

int main() {
    std::cout << "\n\033[1;32m=== RUN: hello_vex_cpp ===\033[0m\n";
    std::cout << "lang: cpp\n";
    std::cout << "msg: " << hello_vex_banner() << "\n";
    return 0;
}
