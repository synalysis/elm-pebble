#ifndef ELMC_HOST_STUBS_H
#define ELMC_HOST_STUBS_H

#include <stddef.h>
#include <stdint.h>

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

#ifndef TRIG_MAX_RATIO
#define TRIG_MAX_RATIO 16384
#endif

/* Declarations only — harness builds link `pebble_trig_host_stubs.c`. Defining
   bodies here as static inline collided with that .c under `-include`. */
int32_t sin_lookup(int32_t angle);
int32_t cos_lookup(int32_t angle);

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
