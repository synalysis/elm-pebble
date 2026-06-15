#ifndef ELMC_WORKER_H
#define ELMC_WORKER_H

#include "elmc_generated.h"

#define ELMC_WORKER_MAX_BUTTON_RAW_SUBS 4
#define ELMC_WORKER_SUB_TAG_SLOTS 1
#define ELMC_WORKER_SLOT_FRAME 0


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
} ElmcWorkerState;

int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags);
int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg);
ElmcValue *elmc_worker_model(ElmcWorkerState *state);
ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state);
int64_t elmc_worker_subscriptions(ElmcWorkerState *state);
elmc_int_t elmc_worker_sub_msg_tag(ElmcWorkerState *state, int64_t flag);
elmc_int_t elmc_worker_button_raw_msg_tag(ElmcWorkerState *state, elmc_int_t button_id, elmc_int_t event);
void elmc_worker_deinit(ElmcWorkerState *state);

#endif
