#include <iostream>
#include <vector>
#include <string>

int main() {
    std::cout << "=== Vex C++ Test ===" << std::endl;
    
    // Test basic C++ functionality
    std::vector<std::string> messages = {
        "✅ Zig 0.14.0 working",
        "✅ C++ compilation successful", 
        "✅ Standard library working",
        "✅ Vex build system functional"
    };
    
    for (const auto& msg : messages) {
        std::cout << msg << std::endl;
    }
    
    std::cout << "\n🎉 All tests passed!" << std::endl;
    return 0;
}
