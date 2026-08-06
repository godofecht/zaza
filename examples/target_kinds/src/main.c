#include <stdio.h>
#include "math_kinds.h"
int main(void) {
    int r = math_add(2, 3);
    printf("target_kinds: math_add(2, 3) = %d\n", r);
    return r == 5 ? 0 : 1;
}
