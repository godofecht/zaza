#include <fmt/format.h>
#include <spdlog/spdlog.h>

int main() {
    spdlog::info("{}", fmt::format("hello from cmake_combo"));
    return 0;
}
