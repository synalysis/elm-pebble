#ifndef FLIPPER_HOST_H
#define FLIPPER_HOST_H

#include <stdint.h>

/* Flipper Zero is 128x64 mono. Flipper One has not published a panel size. */
#define FLIPPER_PROFILE_ZERO 1
#define FLIPPER_PROFILE_ONE 2

/* FAP entry. Links meow_app_start from the Elm build, or from smoke_app.c. */
int32_t flipper_app_main(void *arg);

#endif
