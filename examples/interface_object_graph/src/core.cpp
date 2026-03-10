#include "graph_iface.hpp"

int graph_object_value(int value);

namespace graph_iface {

int graph_compute(int value) {
    return graph_object_value(value) + 6;
}

int graph_api_level() {
    return GRAPH_API_LEVEL;
}

} // namespace graph_iface
