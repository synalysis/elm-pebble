#include <math.h>
#include "pebble_trig_host_stubs.h"

int32_t sin_lookup(int32_t angle) {
  double rad = (double)angle * 2.0 * 3.141592653589793 / 65536.0;
  return (int32_t)(sin(rad) * (double)TRIG_MAX_RATIO);
}

int32_t cos_lookup(int32_t angle) {
  double rad = (double)angle * 2.0 * 3.141592653589793 / 65536.0;
  return (int32_t)(cos(rad) * (double)TRIG_MAX_RATIO);
}
