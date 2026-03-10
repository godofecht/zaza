#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iostream>

static std::uint64_t benchmark_sum(int iterations) {
    std::uint64_t acc = 0;
    for (int i = 0; i < iterations; ++i) {
        acc += static_cast<std::uint64_t>((i * 17) ^ (i + 31));
    }
    return acc;
}

int main(int argc, char** argv) {
    const int iterations = argc >= 2 ? std::atoi(argv[1]) : 500000;
    const auto start = std::chrono::steady_clock::now();
    const auto sum = benchmark_sum(iterations);
    const auto end = std::chrono::steady_clock::now();
    const auto micros = std::chrono::duration_cast<std::chrono::microseconds>(end - start).count();

    std::cout << "benchmark iterations: " << iterations << '\n';
    std::cout << "benchmark checksum: " << sum << '\n';
    std::cout << "benchmark elapsed_us: " << micros << '\n';
    return 0;
}
