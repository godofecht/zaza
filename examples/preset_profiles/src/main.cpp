#include <iostream>

int main() {
    const char* runtime_status = "preset runtime ready";

#if defined(ZAZA_ASAN)
    std::cout << "preset: asan\n";
#elif defined(ZAZA_LTO)
    std::cout << "preset: lto\n";
#elif defined(NDEBUG)
    std::cout << "preset: release\n";
#else
    std::cout << "preset: debug\n";
#endif

#if defined(ZAZA_ASAN)
    std::cout << "sanitizer instrumentation requested\n";
#endif

    std::cout << runtime_status << '\n';

    return 0;
}
