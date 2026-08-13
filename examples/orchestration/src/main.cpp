#include <cstdio>

// BUILD_MODE is set through a generator-expressioned define in build.zig:
//   BUILD_MODE=$<IF:$<CONFIG:Debug>,debug,release>
// so its value proves the generator expression evaluated against the config.
#ifndef BUILD_MODE
#define BUILD_MODE unset
#endif

#define STRINGIZE2(x) #x
#define STRINGIZE(x) STRINGIZE2(x)

int main() {
    std::printf("orchestration demo: generator-expressioned BUILD_MODE = %s\n", STRINGIZE(BUILD_MODE));
    return 0;
}
