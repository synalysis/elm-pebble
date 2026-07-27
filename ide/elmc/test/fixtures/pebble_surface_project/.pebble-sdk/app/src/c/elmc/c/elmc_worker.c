#include "elmc_worker.h"

static ElmcValue *extract_model(ElmcValue *value) {
  if (!value) return elmc_new_int(0);
  if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_retain(value);
  ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
  if (!pair->first) return elmc_new_int(0);
  return elmc_retain(pair->first);
}

static ElmcValue *extract_cmd(ElmcValue *value) {
  if (!value) return elmc_new_int(0);
  if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_new_int(0);
  ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
  if (!pair->second) return elmc_new_int(0);
  return elmc_retain(pair->second);
}

static int64_t compute_subscriptions(ElmcWorkerState *state) {
  if (!state || !state->model) return 0;
ElmcValue *args[] = { state->model };
  ElmcValue *result = elmc_fn_Main_subscriptions(args, 1);

  int64_t value = result ? elmc_as_int(result) : 0;
  elmc_release(result);
  return value;
}

int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags) {
  if (!state) return -1;
  state->subscriptions = 0;
ElmcValue *args[] = { flags };
  ElmcValue *result = elmc_fn_Main_init(args, 1);

  ElmcValue *next_model = extract_model(result);
  if (!next_model) {
    elmc_release(result);
    return -2;
  }
  state->model = next_model;
  state->pending_cmd = extract_cmd(result);
  elmc_release(result);
  state->subscriptions = compute_subscriptions(state);
  return 0;
}

int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg) {
  if (!state || !state->model) return -1;
ElmcValue *args[] = { msg, state->model };
  ElmcValue *result = elmc_fn_Main_update(args, 2);

  ElmcValue *next_model = extract_model(result);
  if (!next_model) {
    elmc_release(result);
    return -2;
  }
  elmc_release(state->model);
  state->model = next_model;
  if (state->pending_cmd) {
    elmc_release(state->pending_cmd);
  }
  state->pending_cmd = extract_cmd(result);
  elmc_release(result);
  state->subscriptions = compute_subscriptions(state);
  return 0;
}

ElmcValue *elmc_worker_model(ElmcWorkerState *state) {
  if (!state || !state->model) return NULL;
  return elmc_retain(state->model);
}

ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state) {
  if (!state) return NULL;
  ElmcValue *cmd = state->pending_cmd ? state->pending_cmd : elmc_new_int(0);
  state->pending_cmd = elmc_new_int(0);
  return cmd;
}

int64_t elmc_worker_subscriptions(ElmcWorkerState *state) {
  if (!state) return 0;
  return state->subscriptions;
}

void elmc_worker_deinit(ElmcWorkerState *state) {
  if (!state) return;
  if (state->model) {
    elmc_release(state->model);
    state->model = NULL;
  }
  if (state->pending_cmd) {
    elmc_release(state->pending_cmd);
    state->pending_cmd = NULL;
  }
  state->subscriptions = 0;
}
