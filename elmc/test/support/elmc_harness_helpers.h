#ifndef ELMC_HARNESS_HELPERS_H
#define ELMC_HARNESS_HELPERS_H

#include "elmc_runtime.h"

ElmcValue *elmc_harness_new_int(elmc_int_t value);
ElmcValue *elmc_harness_new_bool(int value);
ElmcValue *elmc_harness_new_string(const char *value);
ElmcValue *elmc_harness_tuple2_take(ElmcValue *first, ElmcValue *second);

#endif
