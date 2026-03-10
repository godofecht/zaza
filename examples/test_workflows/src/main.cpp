#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "missing mode\n";
        return 1;
    }

    const std::string mode = argv[1];
    const char* workflow_env = std::getenv("WORKFLOW_MODE");
    if (workflow_env == nullptr) {
        std::cerr << "missing WORKFLOW_MODE\n";
        return 1;
    }

    std::ifstream fixture("fixtures/message.txt");
    if (!fixture) {
        std::cerr << "missing fixture\n";
        return 1;
    }

    std::string message;
    std::getline(fixture, message);

    std::cout << "workflow mode: " << mode << '\n';
    std::cout << "workflow env: " << workflow_env << '\n';
    std::cout << "workflow fixture: " << message << '\n';
    return 0;
}
