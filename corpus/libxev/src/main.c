/* Downstream C consumer of libxev's C API. It drives a real event loop through
 * the libxev static library: a timer fires, a callback runs, and the loop
 * returns when there is no more work. No Zig is involved in this translation
 * unit; the compiler compiles it and links it against libxev's C library.
 *
 * Modelled on libxev's own examples/_basic.c. Must be built as C99 (see
 * FINDING.md): libxev's include/xev.h does not compile in C++ mode or in the
 * default gnu C mode on a target where max_align_t is 32 bytes. */
#include <stdio.h>
#include <xev.h>

static xev_cb_action on_timer(xev_loop *loop, xev_completion *c, int result, void *userdata) {
    (void)loop; (void)c; (void)result;
    int *fired = (int *)userdata;
    *fired += 1;
    return XEV_DISARM;
}

int main(void) {
    xev_loop loop;
    if (xev_loop_init(&loop) != 0) { printf("xev_loop_init failed\n"); return 1; }

    xev_completion c;
    xev_watcher w;
    if (xev_timer_init(&w) != 0) { printf("xev_timer_init failed\n"); return 1; }

    int fired = 0;
    xev_timer_run(&w, &loop, &c, 1 /* ms */, &fired, &on_timer);
    xev_loop_run(&loop, XEV_RUN_UNTIL_DONE);

    xev_timer_deinit(&w);
    xev_loop_deinit(&loop);

    printf("zaza+libxev slice: event loop ran, timer fired %d time(s)\n", fired);
    return fired == 1 ? 0 : 1;
}
