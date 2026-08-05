// Downstream consumer of the Zaza-built fmt slice. Exercises a handful of the
// fmt entry points that live in the compiled translation units (format.cc /
// os.cc) so the run is a genuine link-and-execute proof, not a header-only one.
#include <fmt/core.h>
#include <fmt/format.h>

int main() {
    fmt::print("zaza+fmt slice: {} {}!\n", "hello", "corpus");

    // fmt::format pulls in the compiled formatting code from format.cc.
    std::string table = fmt::format("|{:>8}|{:^8}|{:<8}|", "right", "center", "left");
    fmt::print("{}\n", table);

    // A numeric format to touch the grisu/dragonbox paths in the object file.
    fmt::print("pi ~= {:.5f}, big = {:>12L}\n", 3.14159265, 1234567);
    return 0;
}
