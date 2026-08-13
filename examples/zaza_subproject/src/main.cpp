#include <cstdio>

#include "greet.h"

int main() {
    std::printf("zaza top-level linked a zaza subproject: %s\n", greet::message());
    return 0;
}
