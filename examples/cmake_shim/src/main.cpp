#include <iostream>
#include <nlohmann/json.hpp>

int main() {
    nlohmann::json payload = {
        {"name", "cmake_shim"},
        {"ok", true},
        {"answer", 42}
    };

    std::cout << payload.dump(2) << std::endl;
    return 0;
}
