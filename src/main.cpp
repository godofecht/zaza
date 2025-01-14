#include <iostream>
#include <nlohmann/json.hpp>

int main()
{
    nlohmann::json j = {
        {"name", "C++ with Zig"},
        {"awesome", true}
    };
    std::cout << j.dump(4) << std::endl;
    return 0;
} 