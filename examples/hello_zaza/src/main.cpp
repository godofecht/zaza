#include <iostream>
#include "hello_zaza.h"

int main() {
    std::cout << "\n\033[1;32m=== RUN: hello_zaza_cpp ===\033[0m\n";
    std::cout << "lang: cpp\n";
    std::cout << "msg: " << hello_zaza_banner() << "\n";
    return 0;
}
