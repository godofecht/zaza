#include <fmt/core.h>

int main() 
{
    fmt::print("Hello from {}, version {}!\n", "fmt", FMT_VERSION);
    
    // Test some formatting features
    fmt::print("Integers: {0:d};  Hex: {0:x};  Oct: {0:o}; Bin: {0:b}\n", 42);
    fmt::print("Floating point: {:.2f}\n", 3.14159);
    fmt::print("Padding: >{0: <10}<\n", "left");
    
    return 0;
} 