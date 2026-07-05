#ifndef PEBBLE_TRIG_HOST_STUBS_H
#define PEBBLE_TRIG_HOST_STUBS_H
#include <stdint.h>
#ifndef TRIG_MAX_RATIO
#define TRIG_MAX_RATIO 16384
#endif
int32_t sin_lookup(int32_t angle);
int32_t cos_lookup(int32_t angle);
#endif
