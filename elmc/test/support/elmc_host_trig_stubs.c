#include <stdint.h>

#ifndef TRIG_MAX_RATIO
#define TRIG_MAX_RATIO 16384
#endif

/* Weak defaults so host typecheck/link works without Pebble SDK trig.
   Strong definitions in pebble_trig_host_stubs.c win when that file is linked. */
__attribute__((weak)) int32_t sin_lookup(int32_t angle) {
  (void)angle;
  return 0;
}

__attribute__((weak)) int32_t cos_lookup(int32_t angle) {
  (void)angle;
  return TRIG_MAX_RATIO;
}
