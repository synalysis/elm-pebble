#include "elmc_worker.h"
#if defined(__has_include)
#if __has_include("../../elmc_emulator_build_flags.h")
#include "../../elmc_emulator_build_flags.h"
#elif __has_include("elmc_emulator_build_flags.h")
#include "elmc_emulator_build_flags.h"
#endif
#endif

#if defined(ELMC_PEBBLE_PLATFORM)
#include <pebble.h>
#define ELMC_WORKER_LOG_RC_FAIL(site, rc) \
do { \
  ELMC_RC_LOG_FAIL((rc), (site), "failed"); \
  APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC %s RC %u line %u", (site), (unsigned)(rc), (unsigned)elmc_last_fail_line); \
} while (0)
#else
#define ELMC_WORKER_LOG_RC_FAIL(site, rc) ELMC_RC_LOG_FAIL((rc), (site), "failed")
#endif

#if defined(ELMC_PEBBLE_PLATFORM) && ELMC_PEBBLE_HEAP_LOG
static void elmc_worker_heap_log(const char *label) {
  APP_LOG(
  APP_LOG_LEVEL_INFO,
  "ELMC heap %s used=%lu free=%lu",
  label ? label : "?",
  (unsigned long)heap_bytes_used(),
  (unsigned long)heap_bytes_free());
}
#else
#define elmc_worker_heap_log(label) do { (void)(label); } while (0)
#endif

static ElmcValue *extract_model(ElmcValue *value) {
  if (!value) return elmc_new_int_take(0);
  if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_retain(value);
  ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
  if (!pair->first) return elmc_new_int_take(0);
  return elmc_retain(pair->first);
}

static ElmcValue *extract_cmd(ElmcValue *value) {
  if (!value) return elmc_new_int_take(0);
  if (value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return elmc_new_int_take(0);
  ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
  if (!pair->second) return elmc_new_int_take(0);
  return elmc_retain(pair->second);
}

static int elmc_cmd_is_none(ElmcValue *value) {
  return !value || ((value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) && elmc_as_int(value) == 0);
}

static ElmcValue *elmc_cmd_none(void) {
  return elmc_int_zero();
}

static ElmcValue *elmc_cmd_singleton(ElmcValue *cmd) {
  ElmcValue *empty = elmc_list_nil();
  ElmcValue *list = elmc_list_cons_take(cmd, empty);
  elmc_release(empty);
  return list ? list : elmc_cmd_none();
}

static ElmcValue *elmc_cmd_queue_append(ElmcValue *existing, ElmcValue *next) {
  if (elmc_cmd_is_none(existing) && elmc_cmd_is_none(next)) {
    elmc_release(existing);
    elmc_release(next);
    return elmc_cmd_none();
  }
  if (elmc_cmd_is_none(existing)) {
    elmc_release(existing);
    return next;
  }
  if (elmc_cmd_is_none(next)) {
    elmc_release(next);
    return existing;
  }

  if (existing->tag == ELMC_TAG_LIST && next->tag == ELMC_TAG_LIST) {
    ElmcValue *merged = elmc_list_append_take(existing, next);
    elmc_release(existing);
    elmc_release(next);
    return merged;
  }

  if (existing->tag == ELMC_TAG_LIST) {
    ElmcValue *next_list = elmc_cmd_singleton(next);
    ElmcValue *merged = elmc_list_append_take(existing, next_list);
    elmc_release(next_list);
    elmc_release(existing);
    elmc_release(next);
    return merged;
  }

  ElmcValue *existing_list = elmc_cmd_singleton(existing);

  if (next->tag == ELMC_TAG_LIST) {
    ElmcValue *merged = elmc_list_append_take(existing_list, next);
    elmc_release(existing_list);
    elmc_release(existing);
    elmc_release(next);
    return merged;
  }

  ElmcValue *next_list = elmc_cmd_singleton(next);
  ElmcValue *merged = elmc_list_append_take(existing_list, next_list);
  elmc_release(existing_list);
  elmc_release(next_list);
  elmc_release(existing);
  elmc_release(next);
  return merged;
}

static ElmcValue *elmc_cmd_queue_push_entry(ElmcValue *flat, ElmcValue *entry) {
  if (!entry) return flat ? flat : elmc_new_int_take(0);
  if (elmc_cmd_is_none(entry)) {
    elmc_release(entry);
    return flat ? flat : elmc_new_int_take(0);
  }

  if (entry->tag == ELMC_TAG_LIST) {
    ElmcValue *cursor = entry;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *head = node->head;
      node->head = NULL;
      flat = elmc_cmd_queue_push_entry(flat, head);
      ElmcValue *next = node->tail;
      node->tail = NULL;
      elmc_release(cursor);
      cursor = next;
    }
    return flat;
  }

  ElmcValue *single = elmc_cmd_singleton(entry);
  return elmc_cmd_queue_append(flat, single);
}

static ElmcValue *elmc_cmd_queue_normalize(ElmcValue *cmd) {
  if (!cmd || elmc_cmd_is_none(cmd)) {
    if (cmd) elmc_release(cmd);
    return elmc_cmd_none();
  }
  if (cmd->tag != ELMC_TAG_LIST) return cmd;

  ElmcValue *flat = elmc_cmd_none();
  flat = elmc_cmd_queue_push_entry(flat, cmd);
  return flat;
}

static int elmc_sub_tag_slot(int64_t mask) {
  if (mask == 0) return -1;
  (void)mask;
  return -1;
}

static void elmc_worker_clear_sub_tags(ElmcWorkerState *state) {
  if (!state) return;
  for (int i = 0; i < ELMC_WORKER_SUB_TAG_SLOTS; i++) state->sub_msg_tags[i] = 0;
  state->button_raw_sub_count = 0;
}

static int elmc_worker_mask_is_button_raw(int64_t mask) {
  return (mask & (1LL << 14)) != 0;
}

static void elmc_worker_apply_sub(ElmcWorkerState *state, ElmcValue *sub) {
  if (!state || !sub) return;

  if (sub->tag == ELMC_TAG_SUB && sub->payload != NULL) {
    ElmcSubPayload *payload = (ElmcSubPayload *)sub->payload;
    state->subscriptions |= payload->mask;
    if (elmc_worker_mask_is_button_raw(payload->mask) && payload->arity >= 3) {
      if (state->button_raw_sub_count < ELMC_WORKER_MAX_BUTTON_RAW_SUBS) {
        ElmcButtonRawSub *entry = &state->button_raw_subs[state->button_raw_sub_count++];
        entry->button_id = payload->p0;
        entry->event = payload->p1;
        entry->msg_tag = payload->p2;
      }
      return;
    }
    if (payload->arity > 0) {
      int slot = elmc_sub_tag_slot(payload->mask);
      if (slot >= 0 && slot < ELMC_WORKER_SUB_TAG_SLOTS) state->sub_msg_tags[slot] = payload->p0;
    }
    return;
  }

  if (sub->tag == ELMC_TAG_LIST && sub->payload != NULL) {
    ElmcValue *cursor = sub;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *cons = (ElmcCons *)cursor->payload;
      if (cons->head) elmc_worker_apply_sub(state, cons->head);
      cursor = cons->tail;
    }
  }
}

static int64_t compute_subscriptions(ElmcWorkerState *state) {
  if (!state || !state->model) return 0;
  ElmcValue *result = elmc_new_int_take(0);

  elmc_worker_clear_sub_tags(state);
  state->subscriptions = 0;
  if (result) elmc_worker_apply_sub(state, result);
  elmc_release(result);
  return state->subscriptions;
}

elmc_int_t elmc_worker_sub_msg_tag(ElmcWorkerState *state, int64_t flag) {
  if (!state || flag == 0) return 0;
  int slot = elmc_sub_tag_slot(flag);
  if (slot < 0 || slot >= ELMC_WORKER_SUB_TAG_SLOTS) return 0;
  return state->sub_msg_tags[slot];
}

elmc_int_t elmc_worker_button_raw_msg_tag(ElmcWorkerState *state, elmc_int_t button_id, elmc_int_t event) {
  if (!state) return 0;
  for (int i = 0; i < state->button_raw_sub_count; i++) {
    ElmcButtonRawSub *entry = &state->button_raw_subs[i];
    if (entry->button_id == button_id && entry->event == event) return entry->msg_tag;
  }
  return 0;
}

int elmc_worker_init(ElmcWorkerState *state, ElmcValue *flags) {
  if (!state) return -1;
  state->subscriptions = 0;
  elmc_worker_clear_sub_tags(state);
  elmc_worker_heap_log("init:start");
  return -3;
  (void)flags;
  ElmcValue *result = elmc_new_int_take(0);

  ElmcValue *next_model = extract_model(result);
  if (!next_model) {
    elmc_release(result);
    return -2;
  }
  state->model = next_model;
  state->pending_cmd = elmc_cmd_queue_normalize(extract_cmd(result));
  elmc_release(result);
  state->subscriptions = compute_subscriptions(state);
  elmc_worker_heap_log("init:end");
  return 0;
}

int elmc_worker_dispatch(ElmcWorkerState *state, ElmcValue *msg) {
  if (!state || !state->model) return -1;
  elmc_worker_heap_log("update:start");
  return -4;
  (void)msg;
  ElmcValue *result = elmc_new_int_take(0);

  ElmcValue *next_model = extract_model(result);
  if (!next_model) {
    elmc_release(result);
    return -2;
  }
  elmc_release(state->model);
  state->model = next_model;
  ElmcValue *next_cmd = elmc_cmd_queue_normalize(extract_cmd(result));
  state->pending_cmd = elmc_cmd_queue_append(state->pending_cmd, next_cmd);
  elmc_release(result);
  elmc_worker_heap_log("update:end");
  return 0;
}

ElmcValue *elmc_worker_model(ElmcWorkerState *state) {
  if (!state || !state->model) return NULL;
  return elmc_retain(state->model);
}

ElmcValue *elmc_worker_take_cmd(ElmcWorkerState *state) {
  if (!state) return NULL;
  if (!state->pending_cmd) {
    return elmc_cmd_none();
  }

  while (state->pending_cmd && state->pending_cmd->tag == ELMC_TAG_LIST) {
    if (state->pending_cmd->payload == NULL) {
      elmc_release(state->pending_cmd);
      state->pending_cmd = elmc_cmd_none();
      return elmc_cmd_none();
    }

    ElmcCons *node = (ElmcCons *)state->pending_cmd->payload;
    ElmcValue *head = node->head;
    ElmcValue *rest = node->tail;
    /* Transfer ownership: detach before release (list release walks the spine). */
    node->head = NULL;
    node->tail = NULL;
    elmc_release(state->pending_cmd);
    state->pending_cmd = rest ? rest : elmc_cmd_none();

    if (elmc_cmd_is_none(head)) {
      elmc_release(head);
      continue;
    }

    return head;
  }

  if (elmc_cmd_is_none(state->pending_cmd)) {
    ElmcValue *none = elmc_cmd_none();
    elmc_release(state->pending_cmd);
    state->pending_cmd = none;
    return none;
  }

  ElmcValue *cmd = state->pending_cmd;
  state->pending_cmd = elmc_cmd_none();
  return cmd;
}

int64_t elmc_worker_subscriptions(ElmcWorkerState *state) {
  if (!state) return 0;
  return state->subscriptions;
}

elmc_int_t elmc_worker_last_fail_code(void) {
  return (elmc_int_t)elmc_rc_fail_code();
}

elmc_int_t elmc_worker_last_fail_line(void) {
  return (elmc_int_t)elmc_last_fail_line;
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
