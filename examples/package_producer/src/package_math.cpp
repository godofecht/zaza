#include "package_math.hpp"

namespace package_math {

int add(int lhs, int rhs) {
    return lhs + rhs;
}

int mul_add(int lhs, int rhs, int extra) {
    return (lhs * rhs) + extra;
}

} // namespace package_math
