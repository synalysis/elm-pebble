#include "handheld_host.h"

/* Stand-in used when the directory is built before an Elm program is linked.
 * A real build replaces this file with meow_app_entry.c from elmc.
 */
int meow_app_start(const HandheldHost *host) {
    int32_t bar[5] = {0, 28, 128, 8, 1};
    if (!host || !host->graphics || !host->graphics->draw) return 1;
    host->graphics->draw(host->ud, HANDHELD_DRAW_CLEAR, (int32_t[]){0}, 1, NULL);
    host->graphics->draw(host->ud, HANDHELD_DRAW_FILL_RECT, bar, 5, NULL);
    host->graphics->draw(host->ud, HANDHELD_DRAW_TEXT, (int32_t[]){4, 20}, 2, "Elm");
    if (host->graphics->present) host->graphics->present(host->ud);
    return 0;
}

void meow_app_stop(void) {}

void meow_app_event(int kind, const int32_t *args, int nargs) {
    (void)kind;
    (void)args;
    (void)nargs;
}

void meow_app_frame(int dt_ms) { (void)dt_ms; }
