#ifndef ELMC_WORKER_H
#define ELMC_WORKER_H

#include "elmc_generated.h"

#define ELMC_WORKER_MAX_BUTTON_RAW_SUBS 3
#define ELMC_WORKER_SUB_TAG_SLOTS 2
#define ELMC_WORKER_SLOT_ACCEL_TAP 0
#define ELMC_WORKER_SLOT_SECOND_CHANGE 1


typedef struct {
  elmc_int_t button_id;
  elmc_int_t event;
  elmc_int_t msg_tag;
} ElmcButtonRawSub;

typedef struct {
  ElmcValue *model;
  ElmcValue *pending_cmd;
  int64_t subscriptions;
  elmc_int_t sub_msg_tags[ELMC_WORKER_SUB_TAG_SLOTS];
  ElmcButtonRawSub button_raw_subs[ELMC_WORKER_MAX_BUTTON_RAW_SUBS];
  int button_raw_sub_count;
  int dispatch_needs_render;
} ElmcWorkerState;

int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags);
int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg);
int elmc_worker_dispatch_needs_render(ElmcWorkerState *state);
ElmcValue *elmc_worker_model(ElmcWorkerState *state);
ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state);
int64_t elmc_worker_subscriptions(ElmcWorkerState *state);
elmc_int_t elmc_worker_sub_msg_tag(ElmcWorkerState *state, int64_t flag);
elmc_int_t elmc_worker_button_raw_msg_tag(ElmcWorkerState *state, elmc_int_t button_id, elmc_int_t event);
elmc_int_t elmc_worker_last_fail_code(void);
elmc_int_t elmc_worker_last_fail_line(void);
void elmc_worker_deinit(ElmcWorkerState *state);

#endif
