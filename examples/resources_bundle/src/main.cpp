#include <fstream>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "missing asset path\n";
        return 1;
    }

    std::ifstream input(argv[1]);
    if (!input) {
        std::cerr << "failed to open asset\n";
        return 1;
    }

    std::string message;
    std::getline(input, message);
    std::cout << "resource message: " << message << '\n';
    return 0;
}
