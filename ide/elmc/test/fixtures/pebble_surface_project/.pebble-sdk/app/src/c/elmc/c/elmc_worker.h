#ifndef ELMC_WORKER_H
#define ELMC_WORKER_H

#include "elmc_generated.h"

typedef struct {
  ElmcValue *model;
  ElmcValue *pending_cmd;
  int64_t subscriptions;
} ElmcWorkerState;

int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags);
int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg);
ElmcValue *elmc_worker_model(ElmcWorkerState *state);
ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state);
int64_t elmc_worker_subscriptions(ElmcWorkerState *state);
void elmc_worker_deinit(ElmcWorkerState *state);

#endif
