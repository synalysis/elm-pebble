#ifndef ELMC_HOST_STUBS_H
#define ELMC_HOST_STUBS_H

#include <stddef.h>

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

typedef void *AppTimer;
typedef void (*AppTimerCallback)(void *data);

static inline AppTimer app_timer_register(unsigned int ms, AppTimerCallback cb, void *data) {
  (void)ms;
  (void)cb;
  (void)data;
  return NULL;
}

static inline void app_timer_cancel(AppTimer timer) {
  (void)timer;
}

#endif
