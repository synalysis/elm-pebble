#include "elmc_runtime.h"
#include <stdarg.h>

const char *elmc_debug_union_ctor_name(elmc_int_t tag) {
  (void)tag;
  return NULL;
}

#ifndef APP_LOG_LEVEL_ERROR
#define APP_LOG_LEVEL_ERROR 200
#endif
#ifndef APP_LOG_LEVEL_WARNING
#define APP_LOG_LEVEL_WARNING 150
#endif
#ifndef APP_LOG_LEVEL_INFO
#define APP_LOG_LEVEL_INFO 100
#endif
#ifndef APP_LOG_LEVEL_DEBUG
#define APP_LOG_LEVEL_DEBUG 50
#endif

#ifndef APP_LOG
#define APP_LOG(level, ...) ((void)(level))
#endif
