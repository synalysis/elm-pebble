#ifndef ELMC_WORKER_H
#define ELMC_WORKER_H

#include "elmc_generated.h"

#define ELMC_WORKER_MAX_BUTTON_RAW_SUBS 1
#define ELMC_WORKER_SUB_TAG_SLOTS 1


typedef struct {
  elmc_int_t button_id;
  elmc_int_t event;
  elmc_int_t msg_tag;
} ElmcButtonRawSub;

#define ELMC_WORKER_LAST_DISPATCH_CMD_CAP 8

typedef struct {
  int64_t kind;
  int64_t p0;
  int64_t p1;
  int64_t p2;
  int64_t p3;
  int64_t p4;
  int64_t p5;
  char text[128];
} ElmcWorkerDispatchCmd;

typedef struct {
  ElmcValue *model;
  ElmcValue *pending_cmd;
  ElmcWorkerDispatchCmd last_dispatch_cmds[ELMC_WORKER_LAST_DISPATCH_CMD_CAP];
  int last_dispatch_cmd_count;
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
ElmcValue *elmc_worker_pending_cmds_borrow(ElmcWorkerState *state);
int elmc_worker_last_dispatch_cmd_count(ElmcWorkerState *state);
int elmc_worker_last_dispatch_cmd_at(ElmcWorkerState *state, int index, ElmcWorkerDispatchCmd *out_cmd);
ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state);
int64_t elmc_worker_subscriptions(ElmcWorkerState *state);
elmc_int_t elmc_worker_sub_msg_tag(ElmcWorkerState *state, int64_t flag);
elmc_int_t elmc_worker_button_raw_msg_tag(ElmcWorkerState *state, elmc_int_t button_id, elmc_int_t event);
elmc_int_t elmc_worker_last_fail_code(void);
elmc_int_t elmc_worker_last_fail_line(void);
void elmc_worker_deinit(ElmcWorkerState *state);

#endif
