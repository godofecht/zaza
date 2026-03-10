#include <iostream>

#include "graph_iface.hpp"

int main() {
    std::cout << "graph result: " << graph_iface::graph_compute(9) << '\n';
    std::cout << "graph api level: " << graph_iface::graph_api_level() << '\n';
    return 0;
}
