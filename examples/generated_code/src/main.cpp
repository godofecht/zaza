#include <iostream>

extern const char* generated_message();

int main() {
    std::cout << generated_message() << "\n";
    return 0;
}
