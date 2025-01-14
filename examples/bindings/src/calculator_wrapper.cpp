#include "calculator.hpp"

extern "C" {
    void* cpp_create() {
        return new Calculator();
    }

    void cpp_destroy(void* ptr) {
        delete static_cast<Calculator*>(ptr);
    }

    int cpp_add(void* ptr, int a, int b) {
        return static_cast<Calculator*>(ptr)->add(a, b);
    }

    int cpp_subtract(void* ptr, int a, int b) {
        return static_cast<Calculator*>(ptr)->subtract(a, b);
    }

    int cpp_multiply(void* ptr, int a, int b) {
        return static_cast<Calculator*>(ptr)->multiply(a, b);
    }

    double cpp_divide(void* ptr, int a, int b) {
        return static_cast<Calculator*>(ptr)->divide(a, b);
    }
} 