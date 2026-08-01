#include "elmc_harness_helpers.h"

ElmcValue *elmc_harness_new_int(elmc_int_t value) {
  ElmcValue *out = NULL;
  if (elmc_new_int(&out, value) != RC_SUCCESS) return NULL;
  return out;
}

ElmcValue *elmc_harness_new_bool(int value) {
  ElmcValue *out = NULL;
  if (elmc_new_bool(&out, value) != RC_SUCCESS) return NULL;
  return out;
}

ElmcValue *elmc_harness_new_string(const char *value) {
  ElmcValue *out = NULL;
  if (elmc_new_string(&out, value) != RC_SUCCESS) return NULL;
  return out;
}

ElmcValue *elmc_harness_tuple2_take(ElmcValue *first, ElmcValue *second) {
  ElmcValue *out = NULL;
  if (elmc_tuple2_take(&out, first, second) != RC_SUCCESS) return NULL;
  return out;
}
