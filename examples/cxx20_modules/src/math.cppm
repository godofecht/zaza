export module math;

export int add(int lhs, int rhs) {
    return lhs + rhs;
}

export int mul_add(int lhs, int rhs, int extra) {
    return (lhs * rhs) + extra;
}
