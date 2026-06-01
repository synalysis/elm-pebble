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

static int elmc_cmd_is_none(ElmcValue *value) {
  return !value || ((value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) && elmc_as_int(value) == 0);
}

static ElmcValue *elmc_cmd_singleton(ElmcValue *cmd) {
  ElmcValue *empty = elmc_list_nil();
  ElmcValue *list = elmc_list_cons(cmd, empty);
  elmc_release(empty);
  return list;
}

static ElmcValue *elmc_cmd_queue_append(ElmcValue *existing, ElmcValue *next) {
  if (elmc_cmd_is_none(existing) && elmc_cmd_is_none(next)) return elmc_new_int(0);
  if (elmc_cmd_is_none(existing)) return elmc_retain(next);
  if (elmc_cmd_is_none(next)) return elmc_retain(existing);

  if (existing->tag == ELMC_TAG_LIST && next->tag == ELMC_TAG_LIST) {
    return elmc_list_append(existing, next);
  }

  if (existing->tag == ELMC_TAG_LIST) {
    ElmcValue *next_list = elmc_cmd_singleton(next);
    ElmcValue *merged = elmc_list_append(existing, next_list);
    elmc_release(next_list);
    return merged;
  }

  ElmcValue *existing_list = elmc_cmd_singleton(existing);

  if (next->tag == ELMC_TAG_LIST) {
    ElmcValue *merged = elmc_list_append(existing_list, next);
    elmc_release(existing_list);
    return merged;
  }

  ElmcValue *next_list = elmc_cmd_singleton(next);
  ElmcValue *merged = elmc_list_append(existing_list, next_list);
  elmc_release(existing_list);
  elmc_release(next_list);
  return merged;
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
  ElmcValue *next_cmd = extract_cmd(result);
  ElmcValue *merged_cmd = elmc_cmd_queue_append(state->pending_cmd, next_cmd);
  if (state->pending_cmd) {
    elmc_release(state->pending_cmd);
  }
  elmc_release(next_cmd);
  state->pending_cmd = merged_cmd;
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
  if (!state->pending_cmd) {
    return elmc_new_int(0);
  }

  while (state->pending_cmd && state->pending_cmd->tag == ELMC_TAG_LIST) {
    if (state->pending_cmd->payload == NULL) {
      elmc_release(state->pending_cmd);
      state->pending_cmd = elmc_new_int(0);
      return elmc_new_int(0);
    }

    ElmcCons *node = (ElmcCons *)state->pending_cmd->payload;
    ElmcValue *head = node->head ? elmc_retain(node->head) : elmc_new_int(0);
    ElmcValue *next_pending = node->tail ? elmc_retain(node->tail) : elmc_new_int(0);
    elmc_release(state->pending_cmd);
    state->pending_cmd = next_pending;

    if (head->tag == ELMC_TAG_LIST) {
      ElmcValue *merged_pending = elmc_cmd_queue_append(head, state->pending_cmd);
      elmc_release(state->pending_cmd);
      state->pending_cmd = merged_pending;
      elmc_release(head);
      continue;
    }

    if (elmc_cmd_is_none(head)) {
      elmc_release(head);
      continue;
    }

    return head;
  }

  if (elmc_cmd_is_none(state->pending_cmd)) {
    elmc_release(state->pending_cmd);
    state->pending_cmd = elmc_new_int(0);
    return elmc_new_int(0);
  }

  ElmcValue *cmd = state->pending_cmd;
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
