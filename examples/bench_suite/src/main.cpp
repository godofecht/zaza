// A trivial benchmark that exists to prove the addBench API, not to measure
// anything real. It runs a fixed compute workload a few times and prints the
// per-repetition wall time. The repetition count is read from `--reps N`, which
// the build forwards from `zig build bench-suite-run -- --reps 9`.

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <iostream>

namespace {

std::uint64_t workload() {
    // Enough arithmetic to take a measurable but small amount of time.
    std::uint64_t acc = 0;
    for (std::uint64_t i = 1; i < 2'000'000ULL; ++i) {
        acc += i * 2654435761ULL;
        acc ^= acc >> 15;
    }
    return acc;
}

int parse_reps(int argc, char** argv) {
    for (int i = 1; i + 1 < argc; ++i) {
        if (std::strcmp(argv[i], "--reps") == 0) {
            int n = std::atoi(argv[i + 1]);
            if (n > 0) return n;
        }
    }
    return 5;
}

} // namespace

int main(int argc, char** argv) {
    const int reps = parse_reps(argc, argv);

    std::uint64_t sink = 0;
    double total_us = 0.0;

    std::cout << "bench-suite: compute workload, " << reps << " reps\n";
    for (int r = 0; r < reps; ++r) {
        const auto start = std::chrono::steady_clock::now();
        sink ^= workload();
        const auto end = std::chrono::steady_clock::now();
        const double us =
            std::chrono::duration<double, std::micro>(end - start).count();
        total_us += us;
        std::cout << "  rep " << r << ": " << us << " us\n";
    }

    std::cout << "  mean: " << (total_us / reps) << " us\n";
    // Keep the compiler from folding the workload away.
    if (sink == 0x1234) std::cerr << "";
    return 0;
}
