// Links against an installed zlib that Zaza resolved with `findPackage`. The
// point of the example is the linkage: no include path or library name is
// written here or in build.zig. `findPackage` asked pkg-config (or CMake) where
// zlib is and folded the answer into the target.
#include <stdio.h>
#include <string.h>
#include <zlib.h>

int main(void) {
    const char *input = "zaza findPackage links a real installed zlib";
    unsigned char packed[128];
    uLongf packed_len = sizeof(packed);

    if (compress(packed, &packed_len, (const unsigned char *)input,
                 (uLong)strlen(input) + 1) != Z_OK) {
        fprintf(stderr, "compress failed\n");
        return 1;
    }

    unsigned char restored[128];
    uLongf restored_len = sizeof(restored);
    if (uncompress(restored, &restored_len, packed, packed_len) != Z_OK) {
        fprintf(stderr, "uncompress failed\n");
        return 1;
    }

    if (strcmp((const char *)restored, input) != 0) {
        fprintf(stderr, "round trip mismatch\n");
        return 1;
    }

    printf("zaza+zlib: linked zlib %s, compressed %lu bytes to %lu and back\n",
           zlibVersion(), (unsigned long)strlen(input) + 1,
           (unsigned long)packed_len);
    return 0;
}
