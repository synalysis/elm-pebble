#include "elmc_runtime.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
#define ELMC_PEBBLE_PLATFORM 1
#endif
#ifdef ELMC_PEBBLE_PLATFORM
#include <pebble.h>
#endif
#if defined(__GNUC__)
#define ELMC_UNUSED __attribute__((unused))
#else
#define ELMC_UNUSED
#endif

static uint64_t ELMC_ALLOCATED = 0;
static uint64_t ELMC_RELEASED = 0;
static int64_t ELMC_NEXT_PROCESS_ID = 1;
#define ELMC_PROCESS_MAX_SLOTS 16
#define ELMC_RC_IMMORTAL UINT16_MAX
static ElmcValue ELMC_BOOL_FALSE = { ELMC_RC_IMMORTAL, ELMC_TAG_BOOL, NULL, 0 };
static ElmcValue ELMC_BOOL_TRUE = { ELMC_RC_IMMORTAL, ELMC_TAG_BOOL, NULL, 1 };
#define ELMC_SMALL_INT_MIN (-1)
#define ELMC_SMALL_INT_MAX 64
static const ElmcValue ELMC_SMALL_INTS[ELMC_SMALL_INT_MAX - ELMC_SMALL_INT_MIN + 1] = {
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, -1 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 0 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 1 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 2 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 3 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 4 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 5 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 6 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 7 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 8 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 9 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 10 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 11 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 12 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 13 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 14 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 15 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 16 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 17 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 18 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 19 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 20 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 21 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 22 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 23 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 24 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 25 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 26 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 27 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 28 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 29 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 30 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 31 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 32 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 33 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 34 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 35 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 36 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 37 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 38 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 39 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 40 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 41 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 42 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 43 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 44 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 45 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 46 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 47 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 48 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 49 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 50 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 51 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 52 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 53 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 54 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 55 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 56 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 57 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 58 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 59 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 60 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 61 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 62 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 63 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 64 }
};
static ElmcMaybe ELMC_MAYBE_NOTHING_PAYLOAD = { 0, NULL };
static ElmcValue ELMC_MAYBE_NOTHING ELMC_UNUSED = { ELMC_RC_IMMORTAL, ELMC_TAG_MAYBE, &ELMC_MAYBE_NOTHING_PAYLOAD, 0 };
static char ELMC_EMPTY_STRING_PAYLOAD[] = "";
static ElmcValue ELMC_EMPTY_STRING = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, ELMC_EMPTY_STRING_PAYLOAD, 0 };
static ElmcValue ELMC_LIST_NIL = { ELMC_RC_IMMORTAL, ELMC_TAG_LIST, NULL, 0 };

typedef struct {
  ElmcValue value;
  ElmcCons cons;
} ElmcListCell;

#define ELMC_LIST_CELL_SCALAR ((elmc_int_t)0x1EC011)

typedef struct {
  ElmcValue value;
  ElmcMaybe maybe;
} ElmcMaybeCell;

typedef struct {
  ElmcValue value;
  ElmcResult result;
} ElmcResultCell;

typedef struct {
  ElmcValue value;
  ElmcTuple2 tuple;
} ElmcTuple2Cell;

typedef struct {
  ElmcValue value;
  ElmcCmdPayload cmd;
} ElmcCmdCell;

typedef struct {
  ElmcValue value;
  ElmcSubPayload sub;
} ElmcSubCell;

typedef struct {
  ElmcValue value;
  ElmcRecord record;
} ElmcRecordCell;

typedef struct {
  ElmcValue value;
  ElmcRecord record;
  const char **field_names;
} ElmcNamedRecordCell;

typedef struct {
  ElmcValue value;
  ElmcClosure closure;
} ElmcClosureCell;

#define ELMC_MAYBE_CELL_SCALAR ((elmc_int_t)0x1EC012)
#define ELMC_RESULT_CELL_SCALAR ((elmc_int_t)0x1EC013)
#define ELMC_TUPLE2_CELL_SCALAR ((elmc_int_t)0x1EC014)
#define ELMC_CMD_CELL_SCALAR ((elmc_int_t)0x1EC017)
#define ELMC_SUB_CELL_SCALAR ((elmc_int_t)0x1EC018)
#define ELMC_RECORD_CELL_SCALAR ((elmc_int_t)0x1EC015)
#define ELMC_NAMED_RECORD_CELL_SCALAR ((elmc_int_t)0x1EC019)
#define ELMC_CLOSURE_CELL_SCALAR ((elmc_int_t)0x1EC016)

typedef struct {
  int active;
  int64_t pid;
  ElmcValue *task;
#ifdef ELMC_PEBBLE_PLATFORM
  AppTimer *timer;
#else
  void *timer;
#endif
} ElmcProcessSlot;

static ElmcProcessSlot ELMC_PROCESS_SLOTS[ELMC_PROCESS_MAX_SLOTS];

#ifndef ELMC_ALLOC_TRACE
#define ELMC_ALLOC_TRACE 0
#endif

static void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line);
static ElmcValue *elmc_alloc_impl(ElmcTag tag, void *payload, const char *file, int line);
static ElmcValue *elmc_small_int(elmc_int_t value);
static ElmcValue *elmc_list_cell_alloc(ElmcValue *head, ElmcValue *tail, int take);
static int elmc_list_cell_release(ElmcValue *value);
static int elmc_maybe_cell_release(ElmcValue *value);
static int elmc_result_cell_release(ElmcValue *value);
static int elmc_tuple2_cell_release(ElmcValue *value);
static int elmc_record_cell_release(ElmcValue *value);
static int elmc_closure_cell_release(ElmcValue *value);
static ElmcValue *elmc_record_cell_alloc(int field_count, const char **field_names, ElmcValue **field_values, int take);
static ElmcValue *elmc_record_cell_alloc_static(int field_count, const char * const *field_names, ElmcValue **field_values, int take);
static ElmcValue *elmc_record_cell_alloc_values(int field_count, ElmcValue **field_values, int take);
static const char **elmc_record_field_names(ElmcValue *record);

#if ELMC_ALLOC_TRACE
#define elmc_malloc(size, context) elmc_malloc_impl((size), (context), __FILE__, __LINE__)
#define elmc_alloc(tag, payload) elmc_alloc_impl((tag), (payload), __FILE__, __LINE__)
#else
#define elmc_malloc(size, context) elmc_malloc_impl((size), (context), NULL, 0)
#define elmc_alloc(tag, payload) elmc_alloc_impl((tag), (payload), NULL, 0)
#endif
#define elmc_realloc(ptr, size, context) elmc_realloc_impl((ptr), (size), (context))

#if ELMC_RC_TRACK
#define ELMC_RC_TRACK_REGISTER(value, context) \
  elmc_rc_track_register((value), (context), __FILE__, __LINE__)
static void elmc_rc_track_register(ElmcValue *value, const char *context, const char *file, int line);
static void elmc_rc_track_unregister(ElmcValue *value);
static ElmcValue *elmc_retain_impl(ElmcValue *value);
static void elmc_release_impl(ElmcValue *value);
static void elmc_rc_track_on_retain(ElmcValue *value, const char *file, int line);
static void elmc_rc_track_on_release(ElmcValue *value, const char *file, int line);
#else
#define ELMC_RC_TRACK_REGISTER(value, context) ((void)0)
#endif


static ElmcProcessSlot *elmc_process_alloc_slot(void) {
  for (int i = 0; i < ELMC_PROCESS_MAX_SLOTS; i++) {
    if (!ELMC_PROCESS_SLOTS[i].active) {
      ELMC_PROCESS_SLOTS[i].active = 1;
      ELMC_PROCESS_SLOTS[i].pid = ELMC_NEXT_PROCESS_ID++;
      ELMC_PROCESS_SLOTS[i].task = NULL;
      ELMC_PROCESS_SLOTS[i].timer = NULL;
      return &ELMC_PROCESS_SLOTS[i];
    }
  }
  return NULL;
}

static ElmcProcessSlot *elmc_process_find_slot(int64_t pid) {
  for (int i = 0; i < ELMC_PROCESS_MAX_SLOTS; i++) {
    if (ELMC_PROCESS_SLOTS[i].active && ELMC_PROCESS_SLOTS[i].pid == pid) {
      return &ELMC_PROCESS_SLOTS[i];
    }
  }
  return NULL;
}

static void elmc_process_release_slot(ElmcProcessSlot *slot) {
  if (!slot || !slot->active) return;
  if (slot->task) {
    elmc_release(slot->task);
    slot->task = NULL;
  }
#ifdef ELMC_PEBBLE_PLATFORM
  if (slot->timer) {
    app_timer_cancel(slot->timer);
    slot->timer = NULL;
  }
#endif
  slot->active = 0;
  slot->pid = 0;
}

#ifdef ELMC_PEBBLE_PLATFORM
static void elmc_process_spawn_timer_cb(void *data) {
  ElmcProcessSlot *slot = (ElmcProcessSlot *)data;
  if (!slot || !slot->active) return;
  slot->timer = NULL;
  elmc_process_release_slot(slot);
}

static void elmc_process_sleep_timer_cb(void *data) {
  ElmcProcessSlot *slot = (ElmcProcessSlot *)data;
  if (!slot || !slot->active) return;
  slot->timer = NULL;
  elmc_process_release_slot(slot);
}
#endif

static void elmc_log_alloc_failed(const char *context, size_t size, const char *file, int line) {
#ifdef ELMC_PEBBLE_PLATFORM
  if (file && line > 0) {
    APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC malloc failed %s %s:%d %lu",
            context ? context : "?", file, line, (unsigned long)size);
  } else {
    APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC malloc failed %s %lu",
            context ? context : "?", (unsigned long)size);
  }
#else
  if (file && line > 0) {
    fprintf(stderr, "ELMC malloc failed %s %s:%d %lu\n",
            context ? context : "?", file, line, (unsigned long)size);
  } else {
    fprintf(stderr, "ELMC malloc failed %s %lu\n",
            context ? context : "?", (unsigned long)size);
  }
#endif
}

static void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line) {
  void *ptr = malloc(size);
  if (!ptr) elmc_log_alloc_failed(context, size, file, line);
  return ptr;
}

static void *elmc_realloc_impl(void *ptr, size_t size, const char *context) {
  void *next = realloc(ptr, size);
  if (!next && size > 0) elmc_log_alloc_failed(context, size, NULL, 0);
  return next;
}

static ElmcValue *elmc_alloc_impl(ElmcTag tag, void *payload, const char *file, int line) {
  ElmcValue *value = (ElmcValue *)elmc_malloc_impl(sizeof(ElmcValue), __func__, file, line);
  if (!value) return NULL;
  value->rc = 1;
  value->tag = tag;
  value->payload = payload;
  value->scalar = 0;
  ELMC_ALLOCATED += 1;
  ELMC_RC_TRACK_REGISTER(value, __func__);
  return value;
}

static ElmcValue *elmc_alloc_scalar(ElmcTag tag, elmc_int_t scalar) {
  ElmcValue *value = elmc_alloc(tag, NULL);
  if (value) value->scalar = scalar;
  return value;
}

static ElmcValue *elmc_small_int(elmc_int_t value) {
  if (value < ELMC_SMALL_INT_MIN || value > ELMC_SMALL_INT_MAX) return NULL;
  return (ElmcValue *)&ELMC_SMALL_INTS[value - ELMC_SMALL_INT_MIN];
}

ElmcValue *elmc_int_zero(void) {
  return elmc_small_int(0);
}

static ElmcValue *elmc_list_cell_alloc(ElmcValue *head, ElmcValue *tail, int take) {
  ElmcListCell *cell = (ElmcListCell *)elmc_malloc(sizeof(ElmcListCell), __func__);
  if (!cell) {
    if (take) {
      elmc_release(head);
      elmc_release(tail);
    }
    return NULL;
  }
  cell->cons.head = take ? head : elmc_retain(head);
  cell->cons.tail = take ? tail : elmc_retain(tail);
  cell->value.rc = 1;
  cell->value.tag = ELMC_TAG_LIST;
  cell->value.payload = &cell->cons;
  cell->value.scalar = ELMC_LIST_CELL_SCALAR;
  ELMC_ALLOCATED += 1;
  ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
  return &cell->value;
}

static int elmc_list_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_LIST || value->scalar != ELMC_LIST_CELL_SCALAR) return 0;
  ElmcListCell *cell = (ElmcListCell *)value;
  if (value->payload != &cell->cons) return 0;
  free(cell);
  return 1;
}

static int elmc_maybe_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_MAYBE || value->scalar != ELMC_MAYBE_CELL_SCALAR) return 0;
  ElmcMaybeCell *cell = (ElmcMaybeCell *)value;
  if (value->payload != &cell->maybe) return 0;
  free(cell);
  return 1;
}

static int elmc_result_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_RESULT || value->scalar != ELMC_RESULT_CELL_SCALAR) return 0;
  ElmcResultCell *cell = (ElmcResultCell *)value;
  if (value->payload != &cell->result) return 0;
  free(cell);
  return 1;
}

static int elmc_tuple2_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_TUPLE2 || value->scalar != ELMC_TUPLE2_CELL_SCALAR) return 0;
  ElmcTuple2Cell *cell = (ElmcTuple2Cell *)value;
  if (value->payload != &cell->tuple) return 0;
  free(cell);
  return 1;
}

static int elmc_cmd_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_CMD || value->scalar != ELMC_CMD_CELL_SCALAR) return 0;
  ElmcCmdCell *cell = (ElmcCmdCell *)value;
  if (value->payload != &cell->cmd) return 0;
  elmc_release(cell->cmd.text);
  free(cell);
  return 1;
}

static int elmc_sub_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_SUB || value->scalar != ELMC_SUB_CELL_SCALAR) return 0;
  ElmcSubCell *cell = (ElmcSubCell *)value;
  if (value->payload != &cell->sub) return 0;
  free(cell);
  return 1;
}

static int elmc_record_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_RECORD) return 0;
  if (value->scalar == ELMC_RECORD_CELL_SCALAR) {
    ElmcRecordCell *cell = (ElmcRecordCell *)value;
    if (value->payload != &cell->record) return 0;
    free(cell);
    return 1;
  }
  if (value->scalar == ELMC_NAMED_RECORD_CELL_SCALAR) {
    ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)value;
    if (value->payload != &cell->record) return 0;
    free(cell);
    return 1;
  }
  return 0;
}

static int elmc_closure_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_CLOSURE || value->scalar != ELMC_CLOSURE_CELL_SCALAR) return 0;
  ElmcClosureCell *cell = (ElmcClosureCell *)value;
  if (value->payload != &cell->closure) return 0;
  free(cell);
  return 1;
}

static ElmcValue *elmc_record_cell_alloc(int field_count, const char **field_names, ElmcValue **field_values, int take) {
  if (field_count < 0) return NULL;
  size_t names_size = sizeof(const char *) * (size_t)field_count;
  size_t values_size = sizeof(ElmcValue *) * (size_t)field_count;
  ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)elmc_malloc(sizeof(ElmcNamedRecordCell) + names_size + values_size, __func__);
  if (!cell) {
    if (take) {
      for (int i = 0; i < field_count; i++) {
        elmc_release(field_values[i]);
      }
    }
    return NULL;
  }

  char *cursor = (char *)(cell + 1);
  cell->record.field_count = field_count;
  cell->field_names = (const char **)cursor;
  cursor += names_size;
  cell->record.field_values = (ElmcValue **)cursor;

  for (int i = 0; i < field_count; i++) {
    cell->field_names[i] = field_names[i];
    cell->record.field_values[i] = take ? field_values[i] : elmc_retain(field_values[i]);
  }

  cell->value.rc = 1;
  cell->value.tag = ELMC_TAG_RECORD;
  cell->value.payload = &cell->record;
  cell->value.scalar = ELMC_NAMED_RECORD_CELL_SCALAR;
  ELMC_ALLOCATED += 1;
  ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
  return &cell->value;
}

static ElmcValue *elmc_record_cell_alloc_static(int field_count, const char * const *field_names, ElmcValue **field_values, int take) {
  return elmc_record_cell_alloc(field_count, (const char **)field_names, field_values, take);
}

static ElmcValue *elmc_record_cell_alloc_values(int field_count, ElmcValue **field_values, int take) {
  if (field_count < 0) return NULL;
  size_t values_size = sizeof(ElmcValue *) * (size_t)field_count;
  ElmcRecordCell *cell = (ElmcRecordCell *)elmc_malloc(sizeof(ElmcRecordCell) + values_size, __func__);
  if (!cell) {
    if (take) {
      for (int i = 0; i < field_count; i++) {
        elmc_release(field_values[i]);
      }
    }
    return NULL;
  }

  cell->record.field_count = field_count;
  cell->record.field_values = (ElmcValue **)(cell + 1);

  for (int i = 0; i < field_count; i++) {
    cell->record.field_values[i] = take ? field_values[i] : elmc_retain(field_values[i]);
  }

  cell->value.rc = 1;
  cell->value.tag = ELMC_TAG_RECORD;
  cell->value.payload = &cell->record;
  cell->value.scalar = ELMC_RECORD_CELL_SCALAR;
  ELMC_ALLOCATED += 1;
  ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
  return &cell->value;
}

static const char **elmc_record_field_names(ElmcValue *record) {
  if (!record || record->tag != ELMC_TAG_RECORD || record->scalar != ELMC_NAMED_RECORD_CELL_SCALAR) return NULL;
  ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)record;
  if (record->payload != &cell->record) return NULL;
  return cell->field_names;
}

static RC elmc_list_reverse_into(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      next = NULL;
      rc = elmc_list_cons(&next, node->head, rev);
      CHECK_RC(rc);
      elmc_release(rev);
      rev = next;
      next = NULL;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_rc_assign_value(out, rev);
      CHECK_RC(rc);
      rev = NULL;
    }
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

static RC elmc_list_reverse_transfer(ElmcValue **out, ElmcValue **src) {
  ElmcValue *list = src ? *src : NULL;
  RC rc = elmc_list_reverse_into(out, list);
  if (rc == RC_SUCCESS && src && *src) {
    elmc_release(*src);
    *src = NULL;
  }
  return rc;
}

static ElmcValue *elmc_list_reverse_copy(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_reverse_into(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

RC elmc_new_int(ElmcValue **out, elmc_int_t value) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    ElmcValue *small = elmc_small_int(value);
    if (small) {
      rc = elmc_rc_assign_value(out, small);
      CHECK_RC(rc);
    } else {
      rc = elmc_rc_assign_value(out, elmc_alloc_scalar(ELMC_TAG_INT, value));
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

RC elmc_new_bool(ElmcValue **out, int value) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_rc_assign_value(out, value ? &ELMC_BOOL_TRUE : &ELMC_BOOL_FALSE);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

ElmcValue *elmc_new_char(elmc_int_t value) {
  ElmcValue *result = NULL;
  if (elmc_new_int(&result, value) != RC_SUCCESS) return NULL;
  return result;
}

RC elmc_new_string(ElmcValue **out, const char *value) {
  RC rc = RC_SUCCESS;
  char *ptr = NULL;
  CATCH_BEGIN
    if (!value || value[0] == '\0') {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      size_t len = strlen(value);
      ptr = (char *)elmc_malloc(len + 1, __func__);
      if (!ptr) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      memcpy(ptr, value, len + 1);
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, ptr);
      ptr = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (ptr) free(ptr);
  return rc;
}

ElmcValue *elmc_list_nil(void) {
  return &ELMC_LIST_NIL;
}

RC elmc_list_cons(ElmcValue **out, ElmcValue *head, ElmcValue *tail) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_rc_assign_value(out, elmc_list_cell_alloc(head, tail, 0));
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

ElmcValue *elmc_list_cons_take(ElmcValue *head, ElmcValue *tail) {
  ElmcValue *out = NULL;
  if (elmc_rc_assign_value(&out, elmc_list_cell_alloc(head, tail, 1)) != RC_SUCCESS) {
    return elmc_int_zero();
  }
  return out;
}

RC elmc_list_from_values(ElmcValue **out, ElmcValue **items, int count) {
  RC rc = RC_SUCCESS;
  ElmcValue *list = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!items || count <= 0) {
      rc = elmc_rc_assign_value(out, list);
      CHECK_RC(rc);
      list = NULL;
    } else {
      for (int i = count - 1; i >= 0; i--) {
        next = NULL;
        rc = elmc_list_cons(&next, items[i], list);
        CHECK_RC(rc);
        elmc_release(list);
        list = next;
        next = NULL;
      }
      rc = elmc_rc_assign_value(out, list);
      CHECK_RC(rc);
      list = NULL;
    }
  CATCH_END;
  elmc_release(next);
  elmc_release(list);
  return rc;
}

RC elmc_list_from_values_take(ElmcValue **out, ElmcValue **items, int count) {
  RC rc = RC_SUCCESS;
  ElmcValue *list = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!items || count <= 0) {
      rc = elmc_rc_assign_value(out, list);
      CHECK_RC(rc);
      list = NULL;
    } else {
      for (int i = count - 1; i >= 0; i--) {
        next = NULL;
        rc = elmc_rc_assign_value(&next, elmc_list_cell_alloc(items[i], list, 1));
        CHECK_RC(rc);
        list = next;
        next = NULL;
      }
      rc = elmc_rc_assign_value(out, list);
      CHECK_RC(rc);
      list = NULL;
    }
  CATCH_END;
  elmc_release(next);
  elmc_release(list);
  return rc;
}

RC elmc_list_from_int_array(ElmcValue **out, const elmc_int_t *items, int count) {
  RC rc = RC_SUCCESS;
  ElmcValue *list = elmc_list_nil();
  ElmcValue *item = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!items || count <= 0) {
      rc = elmc_rc_assign_value(out, list);
      CHECK_RC(rc);
      list = NULL;
    } else {
      for (int i = count - 1; i >= 0; i--) {
        item = NULL;
        rc = elmc_new_int(&item, items[i]);
        CHECK_RC(rc);
        next = NULL;
        rc = elmc_list_cons(&next, item, list);
        CHECK_RC(rc);
        elmc_release(item);
        item = NULL;
        elmc_release(list);
        list = next;
        next = NULL;
      }
      rc = elmc_rc_assign_value(out, list);
      CHECK_RC(rc);
      list = NULL;
    }
  CATCH_END;
  elmc_release(item);
  elmc_release(next);
  elmc_release(list);
  return rc;
}

RC elmc_list_from_tuple2_int_array(ElmcValue **out, const elmc_int_t items[][2], int count) {
  RC rc = RC_SUCCESS;
  ElmcValue *list = elmc_list_nil();
  ElmcValue *item = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!items || count <= 0) {
      rc = elmc_rc_assign_value(out, list);
      CHECK_RC(rc);
      list = NULL;
    } else {
      for (int i = count - 1; i >= 0; i--) {
        item = NULL;
        rc = elmc_tuple2_ints(&item, items[i][0], items[i][1]);
        CHECK_RC(rc);
        next = NULL;
        rc = elmc_list_cons(&next, item, list);
        CHECK_RC(rc);
        elmc_release(item);
        item = NULL;
        elmc_release(list);
        list = next;
        next = NULL;
      }
      rc = elmc_rc_assign_value(out, list);
      CHECK_RC(rc);
      list = NULL;
    }
  CATCH_END;
  elmc_release(item);
  elmc_release(next);
  elmc_release(list);
  return rc;
}

ElmcValue *elmc_list_replace_nth_int(ElmcValue *list, elmc_int_t index, elmc_int_t value) {
  ElmcValue *cursor = list;
  ElmcValue *out = NULL;
  ElmcValue **tail_slot = NULL;
  elmc_int_t i = 0;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *head = NULL;
    if (i == index) {
      if (elmc_new_int(&head, value) != RC_SUCCESS) head = NULL;
      if (!head) {
        elmc_release(out);
        return elmc_retain(list);
      }
    } else {
      head = node->head;
    }
    ElmcValue *empty = elmc_list_nil();
    ElmcValue *cell = NULL;
    if (elmc_list_cons(&cell, head, empty) != RC_SUCCESS) cell = NULL;
    elmc_release(empty);
    if (i == index) {
      elmc_release(head);
    }
    if (!cell) {
      elmc_release(out);
      return elmc_retain(list);
    }
    if (tail_slot) {
      elmc_release(*tail_slot);
      *tail_slot = cell;
    } else {
      out = cell;
    }
    tail_slot = &((ElmcCons *)cell->payload)->tail;
    cursor = node->tail;
    i++;
  }
  return out ? out : elmc_list_nil();
}

ElmcValue *elmc_maybe_nothing(void) {
  return &ELMC_MAYBE_NOTHING;
}

RC elmc_maybe_just(ElmcValue **out, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  ElmcMaybeCell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcMaybeCell *)elmc_malloc(sizeof(ElmcMaybeCell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    cell->maybe.is_just = 1;
    cell->maybe.value = elmc_retain(value);
    cell->value.rc = 1;
    cell->value.tag = ELMC_TAG_MAYBE;
    cell->value.payload = &cell->maybe;
    cell->value.scalar = ELMC_MAYBE_CELL_SCALAR;
    ELMC_ALLOCATED += 1;
    ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
    rc = elmc_rc_assign_value(out, &cell->value);
    CHECK_RC(rc);
    cell = NULL;
  CATCH_END;
  if (cell) elmc_release(&cell->value);
  return rc;
}

ElmcValue *elmc_maybe_or_tuple_just_payload_borrow(ElmcValue *maybe) {
  if (!maybe || !maybe->payload) return elmc_int_zero();
  if (maybe->tag == ELMC_TAG_MAYBE) {
    ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
    return m->is_just && m->value ? m->value : elmc_int_zero();
  }
  if (maybe->tag == ELMC_TAG_TUPLE2) {
    ElmcTuple2 *t = (ElmcTuple2 *)maybe->payload;
    if (elmc_as_int(t->first) != 1) return elmc_int_zero();
    return t->second ? t->second : elmc_int_zero();
  }
  return elmc_int_zero();
}

ElmcValue *elmc_maybe_or_tuple_just_payload(ElmcValue *maybe) {
  ElmcValue *borrowed = elmc_maybe_or_tuple_just_payload_borrow(maybe);
  if (!borrowed || borrowed->tag == ELMC_TAG_INT) return borrowed;
  return elmc_retain(borrowed);
}

RC elmc_result_ok(ElmcValue **out, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  ElmcResultCell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcResultCell *)elmc_malloc(sizeof(ElmcResultCell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    cell->result.is_ok = 1;
    cell->result.value = elmc_retain(value);
    cell->value.rc = 1;
    cell->value.tag = ELMC_TAG_RESULT;
    cell->value.payload = &cell->result;
    cell->value.scalar = ELMC_RESULT_CELL_SCALAR;
    ELMC_ALLOCATED += 1;
    ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
    rc = elmc_rc_assign_value(out, &cell->value);
    CHECK_RC(rc);
    cell = NULL;
  CATCH_END;
  if (cell) elmc_release(&cell->value);
  return rc;
}

RC elmc_result_err(ElmcValue **out, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  ElmcResultCell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcResultCell *)elmc_malloc(sizeof(ElmcResultCell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    cell->result.is_ok = 0;
    cell->result.value = elmc_retain(value);
    cell->value.rc = 1;
    cell->value.tag = ELMC_TAG_RESULT;
    cell->value.payload = &cell->result;
    cell->value.scalar = ELMC_RESULT_CELL_SCALAR;
    ELMC_ALLOCATED += 1;
    ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
    rc = elmc_rc_assign_value(out, &cell->value);
    CHECK_RC(rc);
    cell = NULL;
  CATCH_END;
  if (cell) elmc_release(&cell->value);
  return rc;
}

RC elmc_tuple2(ElmcValue **out, ElmcValue *first, ElmcValue *second) {
  RC rc = RC_SUCCESS;
  ElmcTuple2Cell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcTuple2Cell *)elmc_malloc(sizeof(ElmcTuple2Cell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    cell->tuple.first = elmc_retain(first);
    cell->tuple.second = elmc_retain(second);
    cell->value.rc = 1;
    cell->value.tag = ELMC_TAG_TUPLE2;
    cell->value.payload = &cell->tuple;
    cell->value.scalar = ELMC_TUPLE2_CELL_SCALAR;
    ELMC_ALLOCATED += 1;
    ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
    rc = elmc_rc_assign_value(out, &cell->value);
    CHECK_RC(rc);
    cell = NULL;
  CATCH_END;
  if (cell) elmc_release(&cell->value);
  return rc;
}

RC elmc_tuple2_take(ElmcValue **out, ElmcValue *first, ElmcValue *second) {
  RC rc = RC_SUCCESS;
  ElmcTuple2Cell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcTuple2Cell *)elmc_malloc(sizeof(ElmcTuple2Cell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    cell->tuple.first = first;
    cell->tuple.second = second;
    cell->value.rc = 1;
    cell->value.tag = ELMC_TAG_TUPLE2;
    cell->value.payload = &cell->tuple;
    cell->value.scalar = ELMC_TUPLE2_CELL_SCALAR;
    ELMC_ALLOCATED += 1;
    ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
    rc = elmc_rc_assign_value(out, &cell->value);
    CHECK_RC(rc);
    cell = NULL;
  CATCH_END;
  if (cell) {
    elmc_release(&cell->value);
  } else if (rc != RC_SUCCESS) {
    elmc_release(first);
    elmc_release(second);
  }
  return rc;
}

RC elmc_tuple2_ints(ElmcValue **out, elmc_int_t first, elmc_int_t second) {
  ElmcValue *f = NULL;
  ElmcValue *s = NULL;
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_new_int(&f, first);
    CHECK_RC(rc);
    rc = elmc_new_int(&s, second);
    CHECK_RC(rc);
    rc = elmc_tuple2_take(out, f, s);
    CHECK_RC(rc);
    f = NULL;
    s = NULL;
  CATCH_END;
  elmc_release(f);
  elmc_release(s);
  return rc;
}

static ElmcValue *elmc_cmd_alloc(uint8_t arity, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
  ElmcCmdCell *cell = (ElmcCmdCell *)elmc_malloc(sizeof(ElmcCmdCell), __func__);
  if (!cell) return NULL;
  cell->cmd.arity = arity;
  cell->cmd.kind = kind;
  cell->cmd.p0 = p0;
  cell->cmd.p1 = p1;
  cell->cmd.p2 = p2;
  cell->cmd.p3 = p3;
  cell->cmd.p4 = p4;
  cell->cmd.p5 = p5;
  cell->cmd.text = NULL;
  cell->value.rc = 1;
  cell->value.tag = ELMC_TAG_CMD;
  cell->value.payload = &cell->cmd;
  cell->value.scalar = ELMC_CMD_CELL_SCALAR;
  ELMC_ALLOCATED += 1;
  ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
  return &cell->value;
}

ElmcValue *elmc_cmd0(elmc_int_t kind) {
  return elmc_cmd_alloc(0, kind, 0, 0, 0, 0, 0, 0);
}

ElmcValue *elmc_cmd1(elmc_int_t kind, elmc_int_t p0) {
  return elmc_cmd_alloc(1, kind, p0, 0, 0, 0, 0, 0);
}

ElmcValue *elmc_cmd1_string(elmc_int_t kind, elmc_int_t p0, const char *text) {
  ElmcValue *cmd_value = elmc_cmd_alloc(1, kind, p0, 0, 0, 0, 0, 0);
  if (!cmd_value || cmd_value->tag != ELMC_TAG_CMD || !cmd_value->payload) return cmd_value;
  ElmcCmdPayload *cmd = (ElmcCmdPayload *)cmd_value->payload;
  if (elmc_new_string(&cmd->text, text ? text : "") != RC_SUCCESS) {
    elmc_release(cmd_value);
    return NULL;
  }
  return cmd_value;
}

ElmcValue *elmc_cmd2(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1) {
  return elmc_cmd_alloc(2, kind, p0, p1, 0, 0, 0, 0);
}

ElmcValue *elmc_cmd3(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
  return elmc_cmd_alloc(3, kind, p0, p1, p2, 0, 0, 0);
}

ElmcValue *elmc_cmd4(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
  return elmc_cmd_alloc(4, kind, p0, p1, p2, p3, 0, 0);
}

ElmcValue *elmc_cmd5(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
  return elmc_cmd_alloc(5, kind, p0, p1, p2, p3, p4, 0);
}

static ElmcValue *elmc_sub_alloc(uint8_t arity, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
  ElmcSubCell *cell = (ElmcSubCell *)elmc_malloc(sizeof(ElmcSubCell), __func__);
  if (!cell) return NULL;
  cell->sub.arity = arity;
  cell->sub.mask = mask;
  cell->sub.p0 = p0;
  cell->sub.p1 = p1;
  cell->sub.p2 = p2;
  cell->sub.p3 = p3;
  cell->sub.p4 = p4;
  cell->sub.p5 = p5;
  cell->value.rc = 1;
  cell->value.tag = ELMC_TAG_SUB;
  cell->value.payload = &cell->sub;
  cell->value.scalar = ELMC_SUB_CELL_SCALAR;
  ELMC_ALLOCATED += 1;
  ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
  return &cell->value;
}

ElmcValue *elmc_sub0(elmc_int_t mask) {
  return elmc_sub_alloc(0, mask, 0, 0, 0, 0, 0, 0);
}

ElmcValue *elmc_sub1(elmc_int_t mask, elmc_int_t p0) {
  return elmc_sub_alloc(1, mask, p0, 0, 0, 0, 0, 0);
}

ElmcValue *elmc_sub2(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1) {
  return elmc_sub_alloc(2, mask, p0, p1, 0, 0, 0, 0);
}

ElmcValue *elmc_sub3(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
  return elmc_sub_alloc(3, mask, p0, p1, p2, 0, 0, 0);
}

ElmcValue *elmc_sub4(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
  return elmc_sub_alloc(4, mask, p0, p1, p2, p3, 0, 0);
}

ElmcValue *elmc_sub5(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
  return elmc_sub_alloc(5, mask, p0, p1, p2, p3, p4, 0);
}

elmc_int_t elmc_as_int(ElmcValue *value) {
  if (!value || (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL)) return 0;
  return value->scalar;
}

elmc_int_t elmc_as_bool(ElmcValue *value) {
  return elmc_as_int(value) != 0;
}

int elmc_list_equal_int(ElmcValue *left, ElmcValue *right) {
  if (left == right) return 1;
  ElmcValue *a = left;
  ElmcValue *b = right;
  while (a && b && a->tag == ELMC_TAG_LIST && b->tag == ELMC_TAG_LIST) {
    if (!a->payload || !b->payload) return a->payload == b->payload;
    ElmcCons *ca = (ElmcCons *)a->payload;
    ElmcCons *cb = (ElmcCons *)b->payload;
    if (elmc_as_int(ca->head) != elmc_as_int(cb->head)) return 0;
    a = ca->tail;
    b = cb->tail;
  }
  return 0;
}

int elmc_value_equal(ElmcValue *left, ElmcValue *right) {
  if (left == right) return 1;
  if (!left || !right) return 0;
  if (left->tag != right->tag) {
    if ((left->tag == ELMC_TAG_INT || left->tag == ELMC_TAG_BOOL) &&
        (right->tag == ELMC_TAG_INT || right->tag == ELMC_TAG_BOOL)) {
      return elmc_as_int(left) == elmc_as_int(right);
    }
    if (left->tag == ELMC_TAG_MAYBE && left->payload && right->tag == ELMC_TAG_INT) {
      ElmcMaybe *maybe = (ElmcMaybe *)left->payload;
      return !maybe->is_just && elmc_as_int(right) == 0;
    }
    if (right->tag == ELMC_TAG_MAYBE && right->payload && left->tag == ELMC_TAG_INT) {
      ElmcMaybe *maybe = (ElmcMaybe *)right->payload;
      return !maybe->is_just && elmc_as_int(left) == 0;
    }
    if (left->tag == ELMC_TAG_MAYBE && left->payload && right->tag == ELMC_TAG_TUPLE2 && right->payload) {
      ElmcMaybe *maybe = (ElmcMaybe *)left->payload;
      ElmcTuple2 *tuple = (ElmcTuple2 *)right->payload;
      int tag = (int)elmc_as_int(tuple->first);
      return maybe->is_just ? (tag == 1 && elmc_value_equal(maybe->value, tuple->second)) : tag == 0;
    }
    if (right->tag == ELMC_TAG_MAYBE && right->payload && left->tag == ELMC_TAG_TUPLE2 && left->payload) {
      return elmc_value_equal(right, left);
    }
    return 0;
  }

  switch (left->tag) {
    case ELMC_TAG_INT:
    case ELMC_TAG_BOOL:
      return elmc_as_int(left) == elmc_as_int(right);

    case ELMC_TAG_FLOAT:
      return elmc_as_float(left) == elmc_as_float(right);

    case ELMC_TAG_STRING:
      if (!left->payload || !right->payload) return left->payload == right->payload;
      return strcmp((const char *)left->payload, (const char *)right->payload) == 0;

    case ELMC_TAG_LIST: {
      ElmcValue *a = left;
      ElmcValue *b = right;
      while (a && b && a->tag == ELMC_TAG_LIST && b->tag == ELMC_TAG_LIST) {
        if (!a->payload || !b->payload) return a->payload == b->payload;
        ElmcCons *ca = (ElmcCons *)a->payload;
        ElmcCons *cb = (ElmcCons *)b->payload;
        if (!elmc_value_equal(ca->head, cb->head)) return 0;
        a = ca->tail;
        b = cb->tail;
      }
      return 0;
    }

    case ELMC_TAG_TUPLE2: {
      if (!left->payload || !right->payload) return left->payload == right->payload;
      ElmcTuple2 *a = (ElmcTuple2 *)left->payload;
      ElmcTuple2 *b = (ElmcTuple2 *)right->payload;
      return elmc_value_equal(a->first, b->first) && elmc_value_equal(a->second, b->second);
    }

    case ELMC_TAG_CMD: {
      if (!left->payload || !right->payload) return left->payload == right->payload;
      ElmcCmdPayload *a = (ElmcCmdPayload *)left->payload;
      ElmcCmdPayload *b = (ElmcCmdPayload *)right->payload;
      if (a->arity != b->arity || a->kind != b->kind) return 0;
      if (a->arity > 0 && a->p0 != b->p0) return 0;
      if (a->arity > 1 && a->p1 != b->p1) return 0;
      if (a->arity > 2 && a->p2 != b->p2) return 0;
      if (a->arity > 3 && a->p3 != b->p3) return 0;
      if (a->arity > 4 && a->p4 != b->p4) return 0;
      if (a->arity > 5 && a->p5 != b->p5) return 0;
      if (!elmc_value_equal(a->text, b->text)) return 0;
      return 1;
    }

    case ELMC_TAG_SUB: {
      if (!left->payload || !right->payload) return left->payload == right->payload;
      ElmcSubPayload *a = (ElmcSubPayload *)left->payload;
      ElmcSubPayload *b = (ElmcSubPayload *)right->payload;
      if (a->arity != b->arity || a->mask != b->mask) return 0;
      if (a->arity > 0 && a->p0 != b->p0) return 0;
      if (a->arity > 1 && a->p1 != b->p1) return 0;
      if (a->arity > 2 && a->p2 != b->p2) return 0;
      if (a->arity > 3 && a->p3 != b->p3) return 0;
      if (a->arity > 4 && a->p4 != b->p4) return 0;
      if (a->arity > 5 && a->p5 != b->p5) return 0;
      return 1;
    }

    case ELMC_TAG_MAYBE: {
      if (!left->payload || !right->payload) return left->payload == right->payload;
      ElmcMaybe *a = (ElmcMaybe *)left->payload;
      ElmcMaybe *b = (ElmcMaybe *)right->payload;
      if (a->is_just != b->is_just) return 0;
      return !a->is_just || elmc_value_equal(a->value, b->value);
    }

    case ELMC_TAG_RESULT: {
      if (!left->payload || !right->payload) return left->payload == right->payload;
      ElmcResult *a = (ElmcResult *)left->payload;
      ElmcResult *b = (ElmcResult *)right->payload;
      return a->is_ok == b->is_ok && elmc_value_equal(a->value, b->value);
    }

    case ELMC_TAG_RECORD: {
      if (!left->payload || !right->payload) return left->payload == right->payload;
      ElmcRecord *a = (ElmcRecord *)left->payload;
      ElmcRecord *b = (ElmcRecord *)right->payload;
      if (a->field_count != b->field_count) return 0;
      const char **a_names = elmc_record_field_names(left);
      const char **b_names = elmc_record_field_names(right);
      if ((a_names != NULL) != (b_names != NULL)) {
        for (int i = 0; i < a->field_count; i++) {
          if (!elmc_value_equal(a->field_values[i], b->field_values[i])) return 0;
        }
        return 1;
      }
      if (!a_names) {
        for (int i = 0; i < a->field_count; i++) {
          if (!elmc_value_equal(a->field_values[i], b->field_values[i])) return 0;
        }
        return 1;
      }
      for (int i = 0; i < a->field_count; i++) {
        int found = 0;
        for (int j = 0; j < b->field_count; j++) {
          if (strcmp(a_names[i], b_names[j]) == 0) {
            if (!elmc_value_equal(a->field_values[i], b->field_values[j])) return 0;
            found = 1;
            break;
          }
        }
        if (!found) return 0;
      }
      return 1;
    }

    default:
      return left->payload == right->payload;
  }
}

int elmc_string_length(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_STRING) return 0;
  return (int)strlen((const char *)value->payload);
}

ElmcValue *elmc_list_head(ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_maybe_nothing();
  ElmcCons *node = (ElmcCons *)list->payload;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_maybe_just(&_elmc_rc_out, node->head) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_list_nth_maybe(ElmcValue *list, ElmcValue *index) {
  elmc_int_t idx = elmc_as_int(index);
  if (idx < 0 || !list || list->tag != ELMC_TAG_LIST) return elmc_maybe_nothing();
  ElmcValue *cursor = list;
  while (idx > 0) {
    if (!cursor || cursor->tag != ELMC_TAG_LIST || cursor->payload == NULL) return elmc_maybe_nothing();
    cursor = ((ElmcCons *)cursor->payload)->tail;
    idx--;
  }
  if (!cursor || cursor->tag != ELMC_TAG_LIST || cursor->payload == NULL) return elmc_maybe_nothing();
  ElmcCons *node = (ElmcCons *)cursor->payload;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_maybe_just(&_elmc_rc_out, node->head) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

elmc_int_t elmc_list_nth_int_default(ElmcValue *list, elmc_int_t index, elmc_int_t default_value) {
  if (index < 0 || !list || list->tag != ELMC_TAG_LIST) return default_value;
  ElmcValue *cursor = list;
  while (index > 0) {
    if (!cursor || cursor->tag != ELMC_TAG_LIST || cursor->payload == NULL) return default_value;
    cursor = ((ElmcCons *)cursor->payload)->tail;
    index--;
  }
  if (!cursor || cursor->tag != ELMC_TAG_LIST || cursor->payload == NULL) return default_value;
  ElmcCons *node = (ElmcCons *)cursor->payload;
  return node->head ? elmc_as_int(node->head) : default_value;
}

ElmcValue *elmc_list_nth_int_default_boxed(ElmcValue *list, ElmcValue *index, ElmcValue *default_value) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, elmc_list_nth_int_default(list, elmc_as_int(index), elmc_as_int(default_value))) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

elmc_int_t elmc_list_head_with_default_int(elmc_int_t default_val, ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return default_val;
  ElmcCons *node = (ElmcCons *)list->payload;
  return elmc_as_int(node->head);
}

ElmcValue *elmc_tuple_second(ElmcValue *tuple) {
  if (!tuple || tuple->tag != ELMC_TAG_TUPLE2 || tuple->payload == NULL) return elmc_int_zero();
  ElmcTuple2 *data = (ElmcTuple2 *)tuple->payload;
  return elmc_retain(data->second);
}

ElmcValue *elmc_tuple_first(ElmcValue *tuple) {
  if (!tuple || tuple->tag != ELMC_TAG_TUPLE2 || tuple->payload == NULL) return elmc_int_zero();
  ElmcTuple2 *data = (ElmcTuple2 *)tuple->payload;
  return elmc_retain(data->first);
}

ElmcValue *elmc_result_inc_or_zero(ElmcValue *result) {
  if (!result || result->tag != ELMC_TAG_RESULT || result->payload == NULL) return elmc_int_zero();
  ElmcResult *data = (ElmcResult *)result->payload;
  if (!data->is_ok || !data->value) return elmc_int_zero();
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, elmc_as_int(data->value) + 1) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_max(ElmcValue *left, ElmcValue *right) {
  ElmcValue *cmp = elmc_basics_compare(left, right);
  int take_left = elmc_as_int(cmp) >= 0;
  elmc_release(cmp);
  return take_left ? elmc_retain(left) : elmc_retain(right);
}

ElmcValue *elmc_basics_min(ElmcValue *left, ElmcValue *right) {
  ElmcValue *cmp = elmc_basics_compare(left, right);
  int take_left = elmc_as_int(cmp) <= 0;
  elmc_release(cmp);
  return take_left ? elmc_retain(left) : elmc_retain(right);
}

ElmcValue *elmc_basics_clamp(ElmcValue *low, ElmcValue *high, ElmcValue *value) {
  ElmcValue *below = elmc_basics_compare(value, low);
  if (elmc_as_int(below) < 0) {
    elmc_release(below);
    return elmc_retain(low);
  }
  elmc_release(below);

  ElmcValue *above = elmc_basics_compare(value, high);
  if (elmc_as_int(above) > 0) {
    elmc_release(above);
    return elmc_retain(high);
  }
  elmc_release(above);
  return elmc_retain(value);
}

ElmcValue *elmc_basics_mod_by(ElmcValue *base, ElmcValue *value) {
  elmc_int_t b = elmc_as_int(base);
  elmc_int_t v = elmc_as_int(value);
  if (b == 0) return elmc_int_zero();
  elmc_int_t result = v % b;
  if (result < 0) result += (b < 0 ? -b : b);
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, result) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_bitwise_and(ElmcValue *left, ElmcValue *right) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, elmc_as_int(left) & elmc_as_int(right)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_bitwise_or(ElmcValue *left, ElmcValue *right) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, elmc_as_int(left) | elmc_as_int(right)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_bitwise_xor(ElmcValue *left, ElmcValue *right) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, elmc_as_int(left) ^ elmc_as_int(right)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_bitwise_complement(ElmcValue *value) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, ~elmc_as_int(value)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_bitwise_shift_left_by(ElmcValue *bits, ElmcValue *value) {
  int64_t b = elmc_as_int(bits);
  if (b < 0) b = 0;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, elmc_as_int(value) << b) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_bitwise_shift_right_by(ElmcValue *bits, ElmcValue *value) {
  int64_t b = elmc_as_int(bits);
  if (b < 0) b = 0;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, elmc_as_int(value) >> b) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_bitwise_shift_right_zf_by(ElmcValue *bits, ElmcValue *value) {
  int64_t b = elmc_as_int(bits);
  if (b < 0) b = 0;
  uint64_t raw = (uint64_t)elmc_as_int(value);
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, (int64_t)(raw >> b)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_to_code(ElmcValue *value) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, elmc_as_int(value)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_debug_log(ElmcValue *label, ElmcValue *value) {
  ElmcValue *label_text = elmc_debug_to_string(label);
  ElmcValue *value_text = elmc_debug_to_string(value);
  const char *label_cstr = (label_text && label_text->tag == ELMC_TAG_STRING && label_text->payload)
      ? (const char *)label_text->payload
      : "<label>";
  const char *value_cstr = (value_text && value_text->tag == ELMC_TAG_STRING && value_text->payload)
      ? (const char *)value_text->payload
      : "<value>";
#ifdef ELMC_PEBBLE_PLATFORM
  APP_LOG(APP_LOG_LEVEL_INFO, "%s: %s", label_cstr, value_cstr);
#else
  (void)label_cstr;
  (void)value_cstr;
#endif
  if (label_text) elmc_release(label_text);
  if (value_text) elmc_release(value_text);
  return elmc_retain(value);
}

ElmcValue *elmc_debug_todo(ElmcValue *label) {
  (void)label;
  return elmc_int_zero();
}

ElmcValue *elmc_debug_to_string(ElmcValue *value) {
  if (!value) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_string(&_elmc_rc_out, "<null>") != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  if (value->tag == ELMC_TAG_STRING) return elmc_retain(value);

  char buffer[64];
  if (value->tag == ELMC_TAG_BOOL) {
    {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_string(&_elmc_rc_out, elmc_as_int(value) ? "True" : "False") != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
  }

  if (value->tag == ELMC_TAG_FLOAT) {
    snprintf(buffer, sizeof(buffer), "%g", elmc_as_float(value));
    {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_string(&_elmc_rc_out, buffer) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
  }

  snprintf(buffer, sizeof(buffer), "%lld", (long long)elmc_as_int(value));
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_string(&_elmc_rc_out, buffer) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

RC elmc_string_append_native(ElmcValue **out, const char *left, const char *right) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    const char *a = left ? left : "";
    const char *b = right ? right : "";
    size_t len_a = strlen(a);
    size_t len_b = strlen(b);
    buf = (char *)elmc_malloc(len_a + len_b + 1, __func__);
    if (!buf) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    memcpy(buf, a, len_a);
    memcpy(buf + len_a, b, len_b);
    buf[len_a + len_b] = '\0';
    ElmcValue *result = elmc_alloc(ELMC_TAG_STRING, buf);
    buf = NULL;
    if (!result) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    rc = elmc_rc_assign_value(out, result);
    CHECK_RC(rc);
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_append(ElmcValue **out, ElmcValue *left, ElmcValue *right) {
  const char *a = (left && left->tag == ELMC_TAG_STRING && left->payload) ? (const char *)left->payload : "";
  const char *b = (right && right->tag == ELMC_TAG_STRING && right->payload) ? (const char *)right->payload : "";
  return elmc_string_append_native(out, a, b);
}

ElmcValue *elmc_append(ElmcValue *left, ElmcValue *right) {
  if ((left && left->tag == ELMC_TAG_STRING) || (right && right->tag == ELMC_TAG_STRING)) {
    return elmc_string_append_take(left, right);
  }
  return elmc_list_append_take(left, right);
}

ElmcValue *elmc_string_is_empty(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_STRING || value->payload == NULL) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 1);
    return _elmc_rc_out;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, strlen((const char *)value->payload) == 0);
      return _elmc_rc_out;
  }
}

RC elmc_dict_from_list(ElmcValue **out, ElmcValue *items) {
  RC rc = RC_SUCCESS;
  ElmcValue *acc = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = items;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *entry = node->head;
      if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)entry->payload;
        next = NULL;
        rc = elmc_dict_insert(&next, pair->first, pair->second, acc);
        CHECK_RC(rc);
        elmc_release(acc);
        acc = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, acc);
    CHECK_RC(rc);
    acc = NULL;
  CATCH_END;
  elmc_release(next);
  elmc_release(acc);
  return rc;
}

static int elmc_dict_keys_equal(ElmcValue *left, ElmcValue *right) {
  return left && right && elmc_value_equal(left, right);
}

RC elmc_dict_insert(ElmcValue **out, ElmcValue *key, ElmcValue *value, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *new_head = NULL;
  ElmcValue *pair = NULL;
  ElmcValue *next_rev = NULL;
  int inserted = 0;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *cell_head = node->head;
      int skip = 0;
      if (cell_head && cell_head->tag == ELMC_TAG_TUPLE2 && cell_head->payload != NULL) {
        ElmcTuple2 *tp = (ElmcTuple2 *)cell_head->payload;
        if (tp->first && elmc_dict_keys_equal(tp->first, key)) {
          if (!inserted) {
            new_head = NULL;
            rc = elmc_tuple2(&new_head, key, value);
            CHECK_RC(rc);
            cell_head = new_head;
            inserted = 1;
          } else {
            skip = 1;
          }
        }
      }
      if (!skip) {
        next_rev = NULL;
        rc = elmc_list_cons(&next_rev, cell_head, rev);
        CHECK_RC(rc);
        elmc_release(new_head);
        new_head = NULL;
        elmc_release(rev);
        rev = next_rev;
        next_rev = NULL;
      }
      cursor = node->tail;
    }
    if (!inserted) {
      pair = NULL;
      rc = elmc_tuple2(&pair, key, value);
      CHECK_RC(rc);
      next_rev = NULL;
      rc = elmc_list_cons(&next_rev, pair, rev);
      CHECK_RC(rc);
      elmc_release(pair);
      pair = NULL;
      elmc_release(rev);
      rev = next_rev;
      next_rev = NULL;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(new_head);
  elmc_release(pair);
  elmc_release(next_rev);
  elmc_release(rev);
  return rc;
}

RC elmc_dict_get(ElmcValue **out, ElmcValue *key, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  int found = 0;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (!found && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        if (pair->first && elmc_dict_keys_equal(pair->first, key)) {
          rc = elmc_maybe_just(out, pair->second);
          CHECK_RC(rc);
          found = 1;
        }
      }
      if (!found) cursor = node->tail;
    }
    if (!found) {
      rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

elmc_int_t elmc_dict_get_with_default_int(elmc_int_t default_val, elmc_int_t key, ElmcValue *dict) {
  ElmcValue *cursor = dict;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
      ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
      if (pair->first && elmc_as_int(pair->first) == key) {
        return pair->second ? elmc_as_int(pair->second) : default_val;
      }
    }
    cursor = node->tail;
  }
  return default_val;
}

elmc_int_t elmc_dict_get_with_default_int_value(elmc_int_t default_val, ElmcValue *key, ElmcValue *dict) {
  if (!key) return default_val;
  ElmcValue *found = elmc_dict_get_take(key, dict);
  elmc_int_t out = default_val;
  if (found && found->tag == ELMC_TAG_MAYBE && found->payload != NULL) {
    ElmcMaybe *maybe = (ElmcMaybe *)found->payload;
    if (maybe->is_just && maybe->value) out = elmc_as_int(maybe->value);
  }
  elmc_release(found);
  return out;
}

ElmcValue *elmc_dict_member(ElmcValue *key, ElmcValue *dict) {
  ElmcValue *found = elmc_dict_get_take(key, dict);
  int present = 0;
  if (found && found->tag == ELMC_TAG_MAYBE && found->payload != NULL) {
    present = ((ElmcMaybe *)found->payload)->is_just;
  }
  elmc_release(found);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, present);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_dict_size(ElmcValue *dict) {
  int64_t size = 0;
  ElmcValue *cursor = dict;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    size += 1;
    cursor = ((ElmcCons *)cursor->payload)->tail;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, size) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

RC elmc_set_from_list(ElmcValue **out, ElmcValue *items) {
  RC rc = RC_SUCCESS;
  ElmcValue *acc = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = items;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      next = NULL;
      rc = elmc_set_insert(&next, node->head, acc);
      CHECK_RC(rc);
      elmc_release(acc);
      acc = next;
      next = NULL;
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, acc);
    CHECK_RC(rc);
    acc = NULL;
  CATCH_END;
  elmc_release(next);
  elmc_release(acc);
  return rc;
}

ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set) {
  int64_t wanted = elmc_as_int(value);
  ElmcValue *cursor = set;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (elmc_as_int(node->head) == wanted) {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, 1);
      return _elmc_rc_out;
    }
    cursor = node->tail;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, 0);
      return _elmc_rc_out;
  }
}

RC elmc_set_insert(ElmcValue **out, ElmcValue *value, ElmcValue *set) {
  RC rc = RC_SUCCESS;
  ElmcValue *exists = NULL;
  CATCH_BEGIN
    exists = elmc_set_member(value, set);
    int present = exists && elmc_as_int(exists) != 0;
    if (present) {
      rc = elmc_rc_assign_value(out, elmc_retain(set));
      CHECK_RC(rc);
    } else {
      ElmcValue *tail = set ? set : elmc_list_nil();
      int created_tail = !set;
      rc = elmc_list_cons(out, value, tail);
      CHECK_RC(rc);
      if (created_tail) elmc_release(tail);
    }
  CATCH_END;
  elmc_release(exists);
  return rc;
}

ElmcValue *elmc_set_size(ElmcValue *set) {
  int64_t size = 0;
  ElmcValue *cursor = set;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    size += 1;
    cursor = ((ElmcCons *)cursor->payload)->tail;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, size) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_array_empty(void) {
  return elmc_list_nil();
}

ElmcValue *elmc_array_from_list(ElmcValue *items) {
  return elmc_retain(items);
}

ElmcValue *elmc_array_length(ElmcValue *array) {
  return elmc_set_size(array);
}

ElmcValue *elmc_array_get(ElmcValue *index, ElmcValue *array) {
  int64_t wanted = elmc_as_int(index);
  if (wanted < 0) return elmc_maybe_nothing();

  int64_t i = 0;
  ElmcValue *cursor = array;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (i == wanted) {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_maybe_just(&_elmc_rc_out, node->head) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
    i += 1;
    cursor = node->tail;
  }
  return elmc_maybe_nothing();
}

elmc_int_t elmc_array_get_with_default_int(elmc_int_t default_val, elmc_int_t index, ElmcValue *array) {
  if (index < 0) return default_val;

  elmc_int_t i = 0;
  ElmcValue *cursor = array;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (i == index) return elmc_as_int(node->head);
    i += 1;
    cursor = node->tail;
  }
  return default_val;
}

ElmcValue *elmc_array_set(ElmcValue *index, ElmcValue *value, ElmcValue *array) {
  int64_t wanted = elmc_as_int(index);
  if (wanted < 0) return elmc_retain(array);

  int64_t i = 0;
  int replaced = 0;
  ElmcValue *cursor = array;
  ElmcValue *rev = elmc_list_nil();

  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *item = (i == wanted) ? value : node->head;
    if (i == wanted) replaced = 1;
    ElmcValue *next_rev = NULL;
    if (elmc_list_cons(&next_rev, item, rev) != RC_SUCCESS) next_rev = NULL;
    elmc_release(rev);
    rev = next_rev;
    i += 1;
    cursor = node->tail;
  }

  if (!replaced) {
    elmc_release(rev);
    return elmc_retain(array);
  }

  ElmcValue *out = elmc_list_reverse_copy(rev);
  elmc_release(rev);
  return out;
}

ElmcValue *elmc_array_push(ElmcValue *value, ElmcValue *array) {
  ElmcValue *rev = elmc_list_reverse_copy(array);
  ElmcValue *with_tail = NULL;
  if (elmc_list_cons(&with_tail, value, rev) != RC_SUCCESS) with_tail = NULL;
  elmc_release(rev);
  ElmcValue *out = elmc_list_reverse_copy(with_tail);
  elmc_release(with_tail);
  return out;
}

ElmcValue *elmc_task_succeed(ElmcValue *value) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_result_ok(&_elmc_rc_out, value) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_task_fail(ElmcValue *value) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_result_err(&_elmc_rc_out, value) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_task_map(ElmcValue *f, ElmcValue *task) {
  return elmc_result_map_take(f, task);
}

ElmcValue *elmc_task_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
  if (!a || a->tag != ELMC_TAG_RESULT || !a->payload) {
    ElmcValue *_elmc_rc_msg = NULL;
    if (elmc_new_string(&_elmc_rc_msg, "invalid") != RC_SUCCESS) return NULL;
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_result_err(&_elmc_rc_out, _elmc_rc_msg) != RC_SUCCESS) {
      elmc_release(_elmc_rc_msg);
      return NULL;
    }
    elmc_release(_elmc_rc_msg);
    return _elmc_rc_out;
  }
  if (!b || b->tag != ELMC_TAG_RESULT || !b->payload) {
    ElmcValue *_elmc_rc_msg = NULL;
    if (elmc_new_string(&_elmc_rc_msg, "invalid") != RC_SUCCESS) return NULL;
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_result_err(&_elmc_rc_out, _elmc_rc_msg) != RC_SUCCESS) {
      elmc_release(_elmc_rc_msg);
      return NULL;
    }
    elmc_release(_elmc_rc_msg);
    return _elmc_rc_out;
  }
  ElmcResult *ra = (ElmcResult *)a->payload;
  ElmcResult *rb = (ElmcResult *)b->payload;
  if (!ra->is_ok) return elmc_retain(a);
  if (!rb->is_ok) return elmc_retain(b);
  ElmcValue *args[2] = { ra->value, rb->value };
  ElmcValue *mapped = NULL;
  if (elmc_closure_call_rc(&mapped, f, args, 2) != RC_SUCCESS) {
    elmc_release(mapped);
    return elmc_int_zero();
  }
  ElmcValue *out = NULL;
  if (elmc_result_ok(&out, mapped) != RC_SUCCESS) out = NULL;
  elmc_release(mapped);
  return out;
}

ElmcValue *elmc_task_and_then(ElmcValue *f, ElmcValue *task) {
  return elmc_result_and_then_take(f, task);
}

ElmcValue *elmc_process_spawn(ElmcValue *task) {
  ElmcProcessSlot *slot = elmc_process_alloc_slot();
  int64_t pid_raw = slot ? slot->pid : 0;
  if (slot) {
    slot->task = elmc_retain(task);
  #ifdef ELMC_PEBBLE_PLATFORM
    slot->timer = app_timer_register(1, elmc_process_spawn_timer_cb, slot);
  #else
    elmc_process_release_slot(slot);
  #endif
  }
  ElmcValue *pid = NULL;
  if (elmc_new_int(&pid, pid_raw) != RC_SUCCESS) pid = NULL;
  ElmcValue *out = NULL;
  if (elmc_result_ok(&out, pid) != RC_SUCCESS) out = NULL;
  elmc_release(pid);
  return out;
}

ElmcValue *elmc_process_sleep(ElmcValue *milliseconds) {
  int64_t timeout = elmc_as_int(milliseconds);
  if (timeout < 0) timeout = 0;
  ElmcProcessSlot *slot = elmc_process_alloc_slot();
  if (slot) {
  #ifdef ELMC_PEBBLE_PLATFORM
    uint32_t ms = (uint32_t)(timeout > 2147483647 ? 2147483647 : timeout);
    slot->timer = app_timer_register(ms, elmc_process_sleep_timer_cb, slot);
  #else
    elmc_process_release_slot(slot);
  #endif
  }
  ElmcValue *unit = elmc_int_zero();
  ElmcValue *out = NULL;
  if (elmc_result_ok(&out, unit) != RC_SUCCESS) out = NULL;
  elmc_release(unit);
  return out;
}

ElmcValue *elmc_process_kill(ElmcValue *pid) {
  int64_t pid_raw = elmc_as_int(pid);
  ElmcProcessSlot *slot = elmc_process_find_slot(pid_raw);
  if (slot) {
    elmc_process_release_slot(slot);
  }
  ElmcValue *unit = elmc_int_zero();
  ElmcValue *out = NULL;
  if (elmc_result_ok(&out, unit) != RC_SUCCESS) out = NULL;
  elmc_release(unit);
  return out;
}

ElmcValue *elmc_time_now_millis(void) {
  int64_t millis = (int64_t)time(NULL) * 1000;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, millis) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_time_zone_offset_minutes(void) {
  time_t now = time(NULL);
  struct tm local_tm = {0};
  struct tm utc_tm = {0};

#ifdef _WIN32
  localtime_s(&local_tm, &now);
  gmtime_s(&utc_tm, &now);
#else
  struct tm *local_ptr = localtime(&now);
  struct tm *utc_ptr = gmtime(&now);
  if (local_ptr) local_tm = *local_ptr;
  if (utc_ptr) utc_tm = *utc_ptr;
#endif

  int local_minutes = local_tm.tm_hour * 60 + local_tm.tm_min;
  int utc_minutes = utc_tm.tm_hour * 60 + utc_tm.tm_min;
  int day_delta = local_tm.tm_yday - utc_tm.tm_yday;

  if (day_delta > 1) day_delta = -1;
  if (day_delta < -1) day_delta = 1;

  int offset = (day_delta * 24 * 60) + (local_minutes - utc_minutes);
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, (int64_t)offset) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_cmd_backlight_from_maybe(ElmcValue *maybe_mode) {
  int64_t mode = 0; /* 0 = interaction, 1 = disable, 2 = enable */

  if (maybe_mode && maybe_mode->tag == ELMC_TAG_MAYBE && maybe_mode->payload != NULL) {
    ElmcMaybe *maybe = (ElmcMaybe *)maybe_mode->payload;
    if (maybe->is_just && maybe->value) {
      mode = elmc_as_int(maybe->value) != 0 ? 2 : 1;
    }
  }

  ElmcValue *kind = NULL;
  if (elmc_new_int(&kind, 6) != RC_SUCCESS) kind = NULL;
  ElmcValue *p0 = NULL;
  if (elmc_new_int(&p0, mode) != RC_SUCCESS) p0 = NULL;
  ElmcValue *p1 = elmc_int_zero();
  ElmcValue *p2 = elmc_int_zero();
  ElmcValue *p3 = elmc_int_zero();
  ElmcValue *p4 = elmc_int_zero();
  ElmcValue *p5 = elmc_int_zero();
  ElmcValue *tail0 = NULL;
  if (elmc_tuple2(&tail0, p4, p5) != RC_SUCCESS) tail0 = NULL;
  ElmcValue *tail1 = NULL;
  if (elmc_tuple2(&tail1, p3, tail0) != RC_SUCCESS) tail1 = NULL;
  ElmcValue *tail2 = NULL;
  if (elmc_tuple2(&tail2, p2, tail1) != RC_SUCCESS) tail2 = NULL;
  ElmcValue *tail3 = NULL;
  if (elmc_tuple2(&tail3, p1, tail2) != RC_SUCCESS) tail3 = NULL;
  ElmcValue *tail4 = NULL;
  if (elmc_tuple2(&tail4, p0, tail3) != RC_SUCCESS) tail4 = NULL;
  ElmcValue *command = NULL;
  if (elmc_tuple2(&command, kind, tail4) != RC_SUCCESS) command = NULL;

  elmc_release(kind);
  elmc_release(p0);
  elmc_release(p1);
  elmc_release(p2);
  elmc_release(p3);
  elmc_release(p4);
  elmc_release(p5);
  elmc_release(tail0);
  elmc_release(tail1);
  elmc_release(tail2);
  elmc_release(tail3);
  elmc_release(tail4);
  return command;
}

RC elmc_new_float(ElmcValue **out, double value) {
  RC rc = RC_SUCCESS;
  double *ptr = NULL;
  CATCH_BEGIN
    ptr = (double *)elmc_malloc(sizeof(double), __func__);
    if (!ptr) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    *ptr = value;
    ElmcValue *allocated = elmc_alloc(ELMC_TAG_FLOAT, ptr);
    ptr = NULL;
    if (!allocated) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    rc = elmc_rc_assign_value(out, allocated);
    CHECK_RC(rc);
  CATCH_END;
  if (ptr) free(ptr);
  return rc;
}

double elmc_as_float(ElmcValue *value) {
  if (!value) return 0.0;
  if (value->tag == ELMC_TAG_FLOAT) return *((double *)value->payload);
  if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) return (double)elmc_as_int(value);
  return 0.0;
}

RC elmc_record_new(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_rc_assign_value(out, elmc_record_cell_alloc(field_count, field_names, field_values, 0));
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_take(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_rc_assign_value(out, elmc_record_cell_alloc(field_count, field_names, field_values, 1));
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_ints(ElmcValue **out, int field_count, const char **field_names, const elmc_int_t *field_values) {
  ElmcValue *values[field_count];
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    for (int i = 0; i < field_count; i++) {
      rc = elmc_new_int(&values[i], field_values[i]);
      CHECK_RC(rc);
    }
    rc = elmc_record_new_take(out, field_count, field_names, values);
    CHECK_RC(rc);
  CATCH_END;
  if (rc != RC_SUCCESS) {
    for (int i = 0; i < field_count; i++) {
      elmc_release(values[i]);
    }
  }
  return rc;
}

RC elmc_record_new_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_rc_assign_value(out, elmc_record_cell_alloc_static(field_count, field_names, field_values, 0));
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_static_take(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_rc_assign_value(out, elmc_record_cell_alloc_static(field_count, field_names, field_values, 1));
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_static_ints(ElmcValue **out, int field_count, const char * const *field_names, const elmc_int_t *field_values) {
  ElmcValue *values[field_count];
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    for (int i = 0; i < field_count; i++) {
      rc = elmc_new_int(&values[i], field_values[i]);
      CHECK_RC(rc);
    }
    rc = elmc_record_new_static_take(out, field_count, field_names, values);
    CHECK_RC(rc);
  CATCH_END;
  if (rc != RC_SUCCESS) {
    for (int i = 0; i < field_count; i++) {
      elmc_release(values[i]);
    }
  }
  return rc;
}

RC elmc_record_new_values(ElmcValue **out, int field_count, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_rc_assign_value(out, elmc_record_cell_alloc_values(field_count, field_values, 0));
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_values_take(ElmcValue **out, int field_count, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_rc_assign_value(out, elmc_record_cell_alloc_values(field_count, field_values, 1));
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_values_ints(ElmcValue **out, int field_count, const elmc_int_t *field_values) {
  ElmcValue *values[field_count];
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    for (int i = 0; i < field_count; i++) {
      rc = elmc_new_int(&values[i], field_values[i]);
      CHECK_RC(rc);
    }
    rc = elmc_record_new_values_take(out, field_count, values);
    CHECK_RC(rc);
  CATCH_END;
  if (rc != RC_SUCCESS) {
    for (int i = 0; i < field_count; i++) {
      elmc_release(values[i]);
    }
  }
  return rc;
}

ElmcValue *elmc_record_get(ElmcValue *record, const char *field_name) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  const char **field_names = elmc_record_field_names(record);
  if (!field_names) return elmc_int_zero();
  for (int i = 0; i < rec->field_count; i++) {
    if (field_names[i] && strcmp(field_names[i], field_name) == 0) {
      return elmc_retain(rec->field_values[i]);
    }
  }
  return elmc_int_zero();
}

ElmcValue *elmc_record_get_at(ElmcValue *record, int index, const char *field_name) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  const char **field_names = elmc_record_field_names(record);
  if (!field_names) return elmc_int_zero();
  if (index >= 0 && index < rec->field_count && field_names[index] &&
      strcmp(field_names[index], field_name) == 0) {
    return elmc_retain(rec->field_values[index]);
  }
  return elmc_record_get(record, field_name);
}

ElmcValue *elmc_record_get_index(ElmcValue *record, int index) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_int_zero();
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  if (index >= 0 && index < rec->field_count) return elmc_retain(rec->field_values[index]);
  return elmc_int_zero();
}

elmc_int_t elmc_record_get_int(ElmcValue *record, const char *field_name) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  const char **field_names = elmc_record_field_names(record);
  if (!field_names) return 0;
  for (int i = 0; i < rec->field_count; i++) {
    if (field_names[i] && strcmp(field_names[i], field_name) == 0) {
      return elmc_as_int(rec->field_values[i]);
    }
  }
  return 0;
}

elmc_int_t elmc_record_get_at_int(ElmcValue *record, int index, const char *field_name) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  const char **field_names = elmc_record_field_names(record);
  if (!field_names) return 0;
  if (index >= 0 && index < rec->field_count && field_names[index] &&
      strcmp(field_names[index], field_name) == 0) {
    return elmc_as_int(rec->field_values[index]);
  }
  return elmc_record_get_int(record, field_name);
}

elmc_int_t elmc_record_get_index_int(ElmcValue *record, int index) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  if (index >= 0 && index < rec->field_count) return elmc_as_int(rec->field_values[index]);
  return 0;
}

elmc_int_t elmc_record_get_maybe_int(ElmcValue *record, const char *field_name, elmc_int_t default_val) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return default_val;
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  const char **field_names = elmc_record_field_names(record);
  if (!field_names) return default_val;
  for (int i = 0; i < rec->field_count; i++) {
    if (field_names[i] && strcmp(field_names[i], field_name) == 0) {
      return elmc_maybe_with_default_int(default_val, rec->field_values[i]);
    }
  }
  return default_val;
}

elmc_int_t elmc_record_get_at_maybe_int(ElmcValue *record, int index, const char *field_name, elmc_int_t default_val) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return default_val;
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  const char **field_names = elmc_record_field_names(record);
  if (!field_names) return default_val;
  if (index >= 0 && index < rec->field_count && field_names[index] &&
      strcmp(field_names[index], field_name) == 0) {
    return elmc_maybe_with_default_int(default_val, rec->field_values[index]);
  }
  return elmc_record_get_maybe_int(record, field_name, default_val);
}

elmc_int_t elmc_record_get_index_maybe_int(ElmcValue *record, int index, elmc_int_t default_val) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return default_val;
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  if (index >= 0 && index < rec->field_count) return elmc_maybe_with_default_int(default_val, rec->field_values[index]);
  return default_val;
}

elmc_int_t elmc_record_get_bool(ElmcValue *record, const char *field_name) {
  return elmc_record_get_int(record, field_name) != 0;
}

elmc_int_t elmc_record_get_at_bool(ElmcValue *record, int index, const char *field_name) {
  return elmc_record_get_at_int(record, index, field_name) != 0;
}

elmc_int_t elmc_record_get_index_bool(ElmcValue *record, int index) {
  return elmc_record_get_index_int(record, index) != 0;
}

ElmcValue *elmc_record_update(ElmcValue *record, const char *field_name, ElmcValue *new_value) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_retain(record);
  ElmcRecord *old = (ElmcRecord *)record->payload;
  const char **field_names = elmc_record_field_names(record);
  if (!field_names) return elmc_retain(record);
  for (int i = 0; i < old->field_count; i++) {
    if (field_names[i] && strcmp(field_names[i], field_name) == 0) {
      return elmc_record_update_index(record, i, new_value);
    }
  }
  return elmc_retain(record);
}

ElmcValue *elmc_record_update_index(ElmcValue *record, int index, ElmcValue *new_value) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_retain(record);
  ElmcRecord *old = (ElmcRecord *)record->payload;
  if (index < 0 || index >= old->field_count) return elmc_retain(record);
  ElmcValue **values = (ElmcValue **)elmc_malloc(sizeof(ElmcValue *) * old->field_count, __func__);
  if (!values) return elmc_retain(record);
  for (int i = 0; i < old->field_count; i++) {
    values[i] = i == index ? new_value : old->field_values[i];
  }
  ElmcValue *result = NULL;
  if (elmc_record_new_values(&result, old->field_count, values) != RC_SUCCESS) result = NULL;
  free(values);
  return result;
}

ElmcValue *elmc_record_update_index_cow(ElmcValue *record, int index, ElmcValue *new_value) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return elmc_retain(record);
  ElmcRecord *rec = (ElmcRecord *)record->payload;
  if (index < 0 || index >= rec->field_count) return elmc_retain(record);
  if (record->rc == 1) {
    ElmcValue *old_value = rec->field_values[index];
    rec->field_values[index] = elmc_retain(new_value);
    elmc_release(old_value);
    return record;
  }
  return elmc_record_update_index(record, index, new_value);
}

ElmcValue *elmc_record_update_index_cow_drop(ElmcValue *record, int index, ElmcValue *new_value) {
  ElmcValue *next = elmc_record_update_index_cow(record, index, new_value);
  if (next != record) elmc_release(record);
  return next;
}

static RC elmc_closure_cell_init(
    ElmcClosureCell *cell,
    int arity,
    int capture_count,
    ElmcValue **captures) {
  ElmcClosure *clo = &cell->closure;
  clo->fn = NULL;
  clo->rc_fn = NULL;
  clo->arity = arity;
  clo->capture_count = capture_count;
  clo->is_rc = 0;
  clo->captures = NULL;
  if (capture_count > 0) {
    clo->captures = (ElmcValue **)(cell + 1);
    for (int i = 0; i < capture_count; i++) {
      clo->captures[i] = elmc_retain(captures[i]);
    }
  }
  cell->value.rc = 1;
  cell->value.tag = ELMC_TAG_CLOSURE;
  cell->value.payload = clo;
  cell->value.scalar = ELMC_CLOSURE_CELL_SCALAR;
  ELMC_ALLOCATED += 1;
  ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
  return RC_SUCCESS;
}

RC elmc_closure_new(ElmcValue **out, ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures) {
  RC rc = RC_SUCCESS;
  ElmcClosureCell *cell = NULL;
  CATCH_BEGIN
    if (capture_count < 0) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    size_t captures_size = sizeof(ElmcValue *) * (size_t)capture_count;
    cell = (ElmcClosureCell *)elmc_malloc(sizeof(ElmcClosureCell) + captures_size, __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    rc = elmc_closure_cell_init(cell, arity, capture_count, captures);
    CHECK_RC(rc);
    ((ElmcClosure *)cell->value.payload)->fn = fn;
    rc = elmc_rc_assign_value(out, &cell->value);
    CHECK_RC(rc);
    cell = NULL;
  CATCH_END;
  if (cell) elmc_release(&cell->value);
  return rc;
}

RC elmc_closure_new_rc(ElmcValue **out, RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures) {
  RC rc = RC_SUCCESS;
  ElmcClosureCell *cell = NULL;
  CATCH_BEGIN
    if (capture_count < 0) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    size_t captures_size = sizeof(ElmcValue *) * (size_t)capture_count;
    cell = (ElmcClosureCell *)elmc_malloc(sizeof(ElmcClosureCell) + captures_size, __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    rc = elmc_closure_cell_init(cell, arity, capture_count, captures);
    CHECK_RC(rc);
    ElmcClosure *clo = (ElmcClosure *)cell->value.payload;
    clo->is_rc = 1;
    clo->rc_fn = rc_fn;
    rc = elmc_rc_assign_value(out, &cell->value);
    CHECK_RC(rc);
    cell = NULL;
  CATCH_END;
  if (cell) elmc_release(&cell->value);
  return rc;
}

ElmcValue *elmc_closure_call(ElmcValue *closure, ElmcValue **args, int argc) {
  if (!closure || closure->tag != ELMC_TAG_CLOSURE || !closure->payload) return elmc_int_zero();
  ElmcClosure *clo = (ElmcClosure *)closure->payload;
  int consumed = argc;
  if (clo->arity > 0 && argc > clo->arity) {
    consumed = clo->arity;
  }
  ElmcValue *result = NULL;
  if (clo->is_rc) {
    if (!clo->rc_fn || clo->rc_fn(&result, args, consumed, clo->captures, clo->capture_count) != RC_SUCCESS) {
      return elmc_int_zero();
    }
  } else {
    if (!clo->fn) return elmc_int_zero();
    result = clo->fn(args, consumed, clo->captures, clo->capture_count);
  }
  if (consumed < argc) {
    ElmcValue *next = elmc_closure_call(result, args + consumed, argc - consumed);
    elmc_release(result);
    return next;
  }
  return result;
}

RC elmc_closure_call_rc(ElmcValue **out, ElmcValue *closure, ElmcValue **args, int argc) {
  RC rc = RC_SUCCESS;
  ElmcValue *value = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!closure || closure->tag != ELMC_TAG_CLOSURE || !closure->payload) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    ElmcClosure *clo = (ElmcClosure *)closure->payload;
    if (!clo->is_rc || !clo->rc_fn) {
      value = elmc_closure_call(closure, args, argc);
      rc = elmc_rc_assign_value(out, value);
      CHECK_RC(rc);
      value = NULL;
    } else {
      int consumed = argc;
      if (clo->arity > 0 && argc > clo->arity) {
        consumed = clo->arity;
      }
      rc = clo->rc_fn(out, args, consumed, clo->captures, clo->capture_count);
      CHECK_RC(rc);
      if (consumed < argc) {
        next = NULL;
        rc = elmc_closure_call_rc(&next, *out, args + consumed, argc - consumed);
        CHECK_RC(rc);
        elmc_release(*out);
        *out = next;
        next = NULL;
      }
    }
  CATCH_END;
  elmc_release(value);
  elmc_release(next);
  return rc;
}

ElmcValue *elmc_apply_extra(ElmcValue *value, ElmcValue **args, int argc) {
  if (!value) return elmc_int_zero();
  if (value->tag == ELMC_TAG_CLOSURE) {
    return elmc_closure_call(value, args, argc);
  }
  if (argc == 1 && args && args[0] && args[0]->tag == ELMC_TAG_CLOSURE) {
    ElmcValue *access_args[1] = { value };
    return elmc_closure_call(args[0], access_args, 1);
  }
  return elmc_retain(value);
}

ElmcForwardRef *elmc_forward_ref_new(void) {
  ElmcForwardRef *ref = (ElmcForwardRef *)elmc_malloc(sizeof(ElmcForwardRef), __func__);
  if (ref) ref->value = NULL;
  return ref;
}

void elmc_forward_ref_set(ElmcForwardRef *ref, ElmcValue *value) {
  if (!ref) return;
  if (ref->value) elmc_release(ref->value);
  ref->value = value ? elmc_retain(value) : NULL;
}

ElmcValue *elmc_forward_ref_get(ElmcForwardRef *ref) {
  if (!ref || !ref->value) return elmc_int_zero();
  return elmc_retain(ref->value);
}

void elmc_forward_ref_free(ElmcForwardRef *ref) {
  if (!ref) return;
  if (ref->value) elmc_release(ref->value);
  free(ref);
}

ElmcValue *elmc_forward_ref_capture(ElmcForwardRef *ref) {
  if (!ref) return elmc_int_zero();
  ElmcForwardRef **payload = (ElmcForwardRef **)elmc_malloc(sizeof(ElmcForwardRef *), __func__);
  if (!payload) return elmc_int_zero();
  *payload = ref;
  return elmc_alloc(ELMC_TAG_FORWARD_REF, payload);
}

/* ================================================================
   Standard Library – List operations
   ================================================================ */

ElmcValue *elmc_list_tail(ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) return elmc_maybe_nothing();
  ElmcCons *node = (ElmcCons *)list->payload;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_maybe_just(&_elmc_rc_out, node->tail) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_list_is_empty(ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_LIST) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 1);
    return _elmc_rc_out;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, list->payload == NULL);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_list_length(ElmcValue *list) {
  int64_t count = 0;
  ElmcValue *cursor = list;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    count += 1;
    cursor = ((ElmcCons *)cursor->payload)->tail;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, count) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

RC elmc_list_reverse(ElmcValue **out, ElmcValue *list) {
  return elmc_list_reverse_into(out, list);
}

RC elmc_list_copy(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *reversed = NULL;
  CATCH_BEGIN
    if (!list) {
      rc = elmc_rc_assign_value(out, elmc_int_zero());
      CHECK_RC(rc);
    } else {
      rc = elmc_list_reverse_into(&reversed, list);
      CHECK_RC(rc);
      rc = elmc_list_reverse_transfer(out, &reversed);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(reversed);
  return rc;
}

ElmcValue *elmc_list_member(ElmcValue *value, ElmcValue *list) {
  int64_t wanted = elmc_as_int(value);
  ElmcValue *cursor = list;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (elmc_as_int(node->head) == wanted) {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, 1);
      return _elmc_rc_out;
    }
    cursor = node->tail;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, 0);
      return _elmc_rc_out;
  }
}

RC elmc_list_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *mapped = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      mapped = NULL;
      rc = elmc_closure_call_rc(&mapped, f, args, 1);
      CHECK_RC(rc);
      next = NULL;
      rc = elmc_list_cons(&next, mapped, rev);
      CHECK_RC(rc);
      elmc_release(mapped);
      mapped = NULL;
      elmc_release(rev);
      rev = next;
      next = NULL;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(mapped);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_list_filter(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *keep = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      keep = NULL;
      rc = elmc_closure_call_rc(&keep, f, args, 1);
      CHECK_RC(rc);
      if (elmc_as_int(keep)) {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      elmc_release(keep);
      keep = NULL;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(keep);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_list_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[2] = { node->head, result };
      next = NULL;
      rc = elmc_closure_call_rc(&next, f, args, 2);
      CHECK_RC(rc);
      elmc_release(result);
      result = next;
      next = NULL;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_rc_assign_value(out, result);
      CHECK_RC(rc);
      result = NULL;
    }
  CATCH_END;
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_list_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *reversed = NULL;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *next = NULL;
  CATCH_BEGIN
    rc = elmc_list_reverse_into(&reversed, list);
    CHECK_RC(rc);
    ElmcValue *cursor = reversed;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[2] = { node->head, result };
      next = NULL;
      rc = elmc_closure_call_rc(&next, f, args, 2);
      CHECK_RC(rc);
      elmc_release(result);
      result = next;
      next = NULL;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_rc_assign_value(out, result);
      CHECK_RC(rc);
      result = NULL;
    }
  CATCH_END;
  elmc_release(reversed);
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_list_append(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = NULL;
  ElmcValue **tail_slot = NULL;
  ElmcValue *cell = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = a;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      cell = NULL;
      rc = elmc_list_cons(&cell, node->head, elmc_list_nil());
      CHECK_RC(rc);
      if (tail_slot) {
        elmc_release(*tail_slot);
        *tail_slot = cell;
      } else {
        result = cell;
      }
      tail_slot = &((ElmcCons *)cell->payload)->tail;
      cell = NULL;
      cursor = node->tail;
    }
    if (!result) {
      rc = elmc_rc_assign_value(out, elmc_retain(b));
      CHECK_RC(rc);
    } else {
      elmc_release(*tail_slot);
      *tail_slot = elmc_retain(b);
      rc = elmc_rc_assign_value(out, result);
      CHECK_RC(rc);
      result = NULL;
    }
  CATCH_END;
  elmc_release(cell);
  elmc_release(result);
  return rc;
}

RC elmc_list_concat(ElmcValue **out, ElmcValue *lists) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = NULL;
  ElmcValue **tail_slot = NULL;
  ElmcValue *cell = NULL;
  CATCH_BEGIN
    ElmcValue *outer = lists;
    while (outer && outer->tag == ELMC_TAG_LIST && outer->payload != NULL) {
      ElmcCons *outer_node = (ElmcCons *)outer->payload;
      ElmcValue *inner = outer_node->head;
      while (inner && inner->tag == ELMC_TAG_LIST && inner->payload != NULL) {
        ElmcCons *inner_node = (ElmcCons *)inner->payload;
        cell = NULL;
        rc = elmc_list_cons(&cell, inner_node->head, elmc_list_nil());
        CHECK_RC(rc);
        if (tail_slot) {
          elmc_release(*tail_slot);
          *tail_slot = cell;
        } else {
          result = cell;
        }
        tail_slot = &((ElmcCons *)cell->payload)->tail;
        cell = NULL;
        inner = inner_node->tail;
      }
      outer = outer_node->tail;
    }
    if (!result) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
    } else {
      rc = elmc_rc_assign_value(out, result);
      if (rc == RC_SUCCESS) result = NULL;
    }
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(cell);
  elmc_release(result);
  return rc;
}

RC elmc_list_concat_array(ElmcValue **out, ElmcValue * const *lists, int count) {
  RC rc = RC_SUCCESS;
  ElmcValue *acc = elmc_list_nil();
  ElmcValue *merged = NULL;
  CATCH_BEGIN
    if (!lists || count <= 0) {
      rc = elmc_rc_assign_value(out, acc);
      CHECK_RC(rc);
      acc = NULL;
    } else {
      for (int i = count - 1; i >= 0; i--) {
        merged = NULL;
        rc = elmc_list_append(&merged, lists[i], acc);
        CHECK_RC(rc);
        elmc_release(acc);
        acc = merged;
        merged = NULL;
      }
      rc = elmc_rc_assign_value(out, acc);
      CHECK_RC(rc);
      acc = NULL;
    }
  CATCH_END;
  elmc_release(merged);
  elmc_release(acc);
  return rc;
}

ElmcValue *elmc_list_concat_map(ElmcValue *f, ElmcValue *list) {
  ElmcValue *mapped = elmc_list_map_take(f, list);
  ElmcValue *out = elmc_list_concat_take(mapped);
  elmc_release(mapped);
  return out;
}

RC elmc_list_indexed_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *index_val = NULL;
  ElmcValue *mapped = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    int64_t idx = 0;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      index_val = NULL;
      rc = elmc_new_int(&index_val, idx);
      CHECK_RC(rc);
      ElmcValue *args[2] = { index_val, node->head };
      mapped = NULL;
      rc = elmc_closure_call_rc(&mapped, f, args, 2);
      elmc_release(index_val);
      index_val = NULL;
      CHECK_RC(rc);
      next = NULL;
      rc = elmc_list_cons(&next, mapped, rev);
      CHECK_RC(rc);
      elmc_release(mapped);
      mapped = NULL;
      elmc_release(rev);
      rev = next;
      next = NULL;
      idx += 1;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(index_val);
  elmc_release(mapped);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_list_filter_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *maybe_val = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      maybe_val = NULL;
      rc = elmc_closure_call_rc(&maybe_val, f, args, 1);
      CHECK_RC(rc);
      ElmcValue *payload = NULL;
      if (maybe_val && maybe_val->tag == ELMC_TAG_MAYBE && maybe_val->payload != NULL) {
        ElmcMaybe *m = (ElmcMaybe *)maybe_val->payload;
        if (m->is_just && m->value) payload = m->value;
      } else if (maybe_val && maybe_val->tag == ELMC_TAG_TUPLE2 && maybe_val->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)maybe_val->payload;
        if (pair->first && elmc_as_int(pair->first) == 1 && pair->second) payload = pair->second;
      }
      if (payload) {
        next = NULL;
        rc = elmc_list_cons(&next, payload, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      elmc_release(maybe_val);
      maybe_val = NULL;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(maybe_val);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_list_sum(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    int64_t sum = 0;
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      sum += elmc_as_int(node->head);
      cursor = node->tail;
    }
    rc = elmc_new_int(out, sum);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_list_product(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    int64_t prod = 1;
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      prod *= elmc_as_int(node->head);
      cursor = node->tail;
    }
    rc = elmc_new_int(out, prod);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_list_maximum(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *val = NULL;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) {
      rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
      CHECK_RC(rc);
    } else {
      ElmcCons *first = (ElmcCons *)list->payload;
      int64_t best = elmc_as_int(first->head);
      ElmcValue *cursor = first->tail;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        int64_t v = elmc_as_int(node->head);
        if (v > best) best = v;
        cursor = node->tail;
      }
      rc = elmc_new_int(&val, best);
      CHECK_RC(rc);
      rc = elmc_maybe_just(out, val);
      CHECK_RC(rc);
      val = NULL;
    }
  CATCH_END;
  elmc_release(val);
  return rc;
}

RC elmc_list_minimum(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *val = NULL;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) {
      rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
      CHECK_RC(rc);
    } else {
      ElmcCons *first = (ElmcCons *)list->payload;
      int64_t best = elmc_as_int(first->head);
      ElmcValue *cursor = first->tail;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        int64_t v = elmc_as_int(node->head);
        if (v < best) best = v;
        cursor = node->tail;
      }
      rc = elmc_new_int(&val, best);
      CHECK_RC(rc);
      rc = elmc_maybe_just(out, val);
      CHECK_RC(rc);
      val = NULL;
    }
  CATCH_END;
  elmc_release(val);
  return rc;
}

RC elmc_list_any(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  int answer = 0;
  int done = 0;
  ElmcValue *result = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (!done && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      result = NULL;
      rc = elmc_closure_call_rc(&result, f, args, 1);
      CHECK_RC(rc);
      int truthy = elmc_as_int(result) != 0;
      elmc_release(result);
      result = NULL;
      if (truthy) {
        answer = 1;
        done = 1;
      } else {
        cursor = node->tail;
      }
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_new_bool(out, answer);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(result);
  return rc;
}

RC elmc_list_all(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  int answer = 1;
  int done = 0;
  ElmcValue *result = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (!done && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      result = NULL;
      rc = elmc_closure_call_rc(&result, f, args, 1);
      CHECK_RC(rc);
      int truthy = elmc_as_int(result) != 0;
      elmc_release(result);
      result = NULL;
      if (!truthy) {
        answer = 0;
        done = 1;
      } else {
        cursor = node->tail;
      }
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_new_bool(out, answer);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(result);
  return rc;
}

static int elmc_order_cmp(ElmcValue *order);
static RC elmc_list_sort_compare(int *cmp_out, ElmcValue *left, ElmcValue *right, ElmcValue *f, int sort_by);
static RC elmc_list_insert_sorted(ElmcValue **out, ElmcValue *item, ElmcValue *sorted, ElmcValue *f, int sort_by);
static RC elmc_list_sort_with_fn(ElmcValue **out, ElmcValue *list, ElmcValue *f, int sort_by);

RC elmc_list_sort(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_LIST) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
      CHECK_RC(rc);
    } else {
      rc = elmc_list_sort_with_fn(out, list, NULL, 2);
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

static int elmc_order_cmp(ElmcValue *order) {
  if (!order) return 0;
  return (int)elmc_as_int(order);
}

static RC elmc_list_sort_compare(int *cmp_out, ElmcValue *left, ElmcValue *right, ElmcValue *f, int sort_by) {
  RC rc = RC_SUCCESS;
  ElmcValue *key_left = NULL;
  ElmcValue *key_right = NULL;
  ElmcValue *order = NULL;
  CATCH_BEGIN
    if (sort_by == 2) {
      int64_t a = elmc_as_int(left);
      int64_t b = elmc_as_int(right);
      *cmp_out = (a < b) ? -1 : (a > b) ? 1 : 0;
    } else if (sort_by) {
      ElmcValue *args_left[1] = { left };
      ElmcValue *args_right[1] = { right };
      rc = elmc_closure_call_rc(&key_left, f, args_left, 1);
      CHECK_RC(rc);
      rc = elmc_closure_call_rc(&key_right, f, args_right, 1);
      CHECK_RC(rc);
      order = elmc_basics_compare(key_left, key_right);
      *cmp_out = elmc_order_cmp(order);
      elmc_release(order);
      order = NULL;
    } else {
      ElmcValue *args[2] = { left, right };
      rc = elmc_closure_call_rc(&order, f, args, 2);
      CHECK_RC(rc);
      *cmp_out = elmc_order_cmp(order);
    }
  CATCH_END;
  elmc_release(key_left);
  elmc_release(key_right);
  elmc_release(order);
  return rc;
}

static RC elmc_list_insert_sorted(ElmcValue **out, ElmcValue *item, ElmcValue *sorted, ElmcValue *f, int sort_by) {
  RC rc = RC_SUCCESS;
  ElmcValue *item_copy = elmc_retain(item);
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  int inserted = 0;
  CATCH_BEGIN
    ElmcValue *cursor = sorted;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (!inserted) {
        int cmp = 0;
        rc = elmc_list_sort_compare(&cmp, item_copy, node->head, f, sort_by);
        CHECK_RC(rc);
        if (cmp <= 0) {
          next = NULL;
          rc = elmc_list_cons(&next, item_copy, rev);
          CHECK_RC(rc);
          elmc_release(rev);
          rev = next;
          next = NULL;
          inserted = 1;
        }
      }
      next = NULL;
      rc = elmc_list_cons(&next, elmc_retain(node->head), rev);
      CHECK_RC(rc);
      elmc_release(rev);
      rev = next;
      next = NULL;
      cursor = node->tail;
    }
    if (!inserted) {
      next = NULL;
      rc = elmc_list_cons(&next, item_copy, rev);
      CHECK_RC(rc);
      elmc_release(rev);
      rev = next;
      next = NULL;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(item_copy);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

static RC elmc_list_sort_with_fn(ElmcValue **out, ElmcValue *list, ElmcValue *f, int sort_by) {
  RC rc = RC_SUCCESS;
  ElmcValue *sorted = elmc_list_nil();
  ElmcValue *next_sorted = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      next_sorted = NULL;
      rc = elmc_list_insert_sorted(&next_sorted, node->head, sorted, f, sort_by);
      CHECK_RC(rc);
      elmc_release(sorted);
      sorted = next_sorted;
      next_sorted = NULL;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_rc_assign_value(out, sorted);
      CHECK_RC(rc);
      sorted = NULL;
    }
  CATCH_END;
  elmc_release(next_sorted);
  elmc_release(sorted);
  return rc;
}

RC elmc_list_sort_by(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_LIST) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
      CHECK_RC(rc);
    } else {
      rc = elmc_list_sort_with_fn(out, list, f, 1);
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

RC elmc_list_sort_with(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_LIST) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
      CHECK_RC(rc);
    } else {
      rc = elmc_list_sort_with_fn(out, list, f, 0);
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

RC elmc_list_singleton(ElmcValue **out, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  ElmcValue *nil = elmc_list_nil();
  CATCH_BEGIN
    rc = elmc_list_cons(out, value, nil);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(nil);
  return rc;
}

RC elmc_list_range(ElmcValue **out, ElmcValue *lo, ElmcValue *hi) {
  RC rc = RC_SUCCESS;
  int64_t low = elmc_as_int(lo);
  int64_t high = elmc_as_int(hi);
  ElmcValue *acc = elmc_list_nil();
  ElmcValue *val = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    for (int64_t i = high; i >= low; i--) {
      val = NULL;
      rc = elmc_new_int(&val, i);
      CHECK_RC(rc);
      next = NULL;
      rc = elmc_list_cons(&next, val, acc);
      CHECK_RC(rc);
      elmc_release(val);
      val = NULL;
      elmc_release(acc);
      acc = next;
      next = NULL;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_rc_assign_value(out, acc);
      CHECK_RC(rc);
      acc = NULL;
    }
  CATCH_END;
  elmc_release(val);
  elmc_release(next);
  elmc_release(acc);
  return rc;
}

static RC elmc_list_repeat_count(ElmcValue **out, elmc_int_t count, ElmcValue *value);

RC elmc_list_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *value) {
  return elmc_list_repeat_count(out, (elmc_int_t)elmc_as_int(n), value);
}

static RC elmc_list_repeat_count(ElmcValue **out, elmc_int_t count, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  ElmcValue *acc = elmc_list_nil();
  ElmcValue *item = value ? elmc_retain(value) : elmc_int_zero();
  ElmcValue *cons = NULL;
  CATCH_BEGIN
    for (elmc_int_t i = 0; i < count; i++) {
      cons = NULL;
      rc = elmc_list_cons(&cons, item, acc);
      CHECK_RC(rc);
      elmc_release(acc);
      acc = cons;
      cons = NULL;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_rc_assign_value(out, acc);
      CHECK_RC(rc);
      acc = NULL;
    }
  CATCH_END;
  elmc_release(item);
  elmc_release(cons);
  elmc_release(acc);
  return rc;
}

RC elmc_list_take(ElmcValue **out, ElmcValue *n, ElmcValue *list) {
  return elmc_list_take_int(out, elmc_as_int(n), list);
}

RC elmc_list_take_int(ElmcValue **out, elmc_int_t count, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = NULL;
  ElmcValue **tail_slot = NULL;
  ElmcValue *cell = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    elmc_int_t i = 0;
    while (i < count && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      cell = NULL;
      rc = elmc_list_cons(&cell, node->head, elmc_list_nil());
      CHECK_RC(rc);
      if (tail_slot) {
        elmc_release(*tail_slot);
        *tail_slot = cell;
      } else {
        result = cell;
      }
      tail_slot = &((ElmcCons *)cell->payload)->tail;
      cell = NULL;
      cursor = node->tail;
      i++;
    }
    if (!result) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
    } else {
      rc = elmc_rc_assign_value(out, result);
      if (rc == RC_SUCCESS) result = NULL;
    }
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(cell);
  elmc_release(result);
  return rc;
}

RC elmc_list_drop(ElmcValue **out, ElmcValue *n, ElmcValue *list) {
  return elmc_list_drop_int(out, elmc_as_int(n), list);
}

RC elmc_list_drop_int(ElmcValue **out, elmc_int_t count, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = NULL;
  ElmcValue **tail_slot = NULL;
  ElmcValue *cell = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    elmc_int_t i = 0;
    while (i < count && cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      cursor = ((ElmcCons *)cursor->payload)->tail;
      i++;
    }
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      cell = NULL;
      rc = elmc_list_cons(&cell, node->head, elmc_list_nil());
      CHECK_RC(rc);
      if (tail_slot) {
        elmc_release(*tail_slot);
        *tail_slot = cell;
      } else {
        result = cell;
      }
      tail_slot = &((ElmcCons *)cell->payload)->tail;
      cell = NULL;
      cursor = node->tail;
    }
    if (!result) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
    } else {
      rc = elmc_rc_assign_value(out, result);
      if (rc == RC_SUCCESS) result = NULL;
    }
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(cell);
  elmc_release(result);
  return rc;
}

RC elmc_list_partition(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev_yes = elmc_list_nil();
  ElmcValue *rev_no = elmc_list_nil();
  ElmcValue *keep = NULL;
  ElmcValue *next = NULL;
  ElmcValue *yes = NULL;
  ElmcValue *no = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      keep = NULL;
      rc = elmc_closure_call_rc(&keep, f, args, 1);
      CHECK_RC(rc);
      if (elmc_as_int(keep)) {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev_yes);
        CHECK_RC(rc);
        elmc_release(rev_yes);
        rev_yes = next;
        next = NULL;
      } else {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev_no);
        CHECK_RC(rc);
        elmc_release(rev_no);
        rev_no = next;
        next = NULL;
      }
      elmc_release(keep);
      keep = NULL;
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(&yes, &rev_yes);
      CHECK_RC(rc);
      rc = elmc_list_reverse_transfer(&no, &rev_no);
      CHECK_RC(rc);
      rc = elmc_tuple2(out, yes, no);
      CHECK_RC(rc);
      elmc_release(yes);
      elmc_release(no);
      yes = NULL;
      no = NULL;
    }
  CATCH_END;
  elmc_release(keep);
  elmc_release(next);
  elmc_release(rev_yes);
  elmc_release(rev_no);
  elmc_release(yes);
  elmc_release(no);
  return rc;
}

RC elmc_list_unzip(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev_a = elmc_list_nil();
  ElmcValue *rev_b = elmc_list_nil();
  ElmcValue *na = NULL;
  ElmcValue *nb = NULL;
  ElmcValue *a = NULL;
  ElmcValue *b = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        na = NULL;
        rc = elmc_list_cons(&na, pair->first, rev_a);
        CHECK_RC(rc);
        elmc_release(rev_a);
        rev_a = na;
        na = NULL;
        nb = NULL;
        rc = elmc_list_cons(&nb, pair->second, rev_b);
        CHECK_RC(rc);
        elmc_release(rev_b);
        rev_b = nb;
        nb = NULL;
      }
      cursor = node->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(&a, &rev_a);
      CHECK_RC(rc);
      rc = elmc_list_reverse_transfer(&b, &rev_b);
      CHECK_RC(rc);
      rc = elmc_tuple2(out, a, b);
      CHECK_RC(rc);
      elmc_release(a);
      elmc_release(b);
      a = NULL;
      b = NULL;
    }
  CATCH_END;
  elmc_release(na);
  elmc_release(nb);
  elmc_release(rev_a);
  elmc_release(rev_b);
  elmc_release(a);
  elmc_release(b);
  return rc;
}

RC elmc_list_intersperse(ElmcValue **out, ElmcValue *sep, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *ns = NULL;
  ElmcValue *nh = NULL;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
      CHECK_RC(rc);
    } else {
      ElmcValue *cursor = list;
      int first = 1;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!first) {
          ns = NULL;
          rc = elmc_list_cons(&ns, sep, rev);
          CHECK_RC(rc);
          elmc_release(rev);
          rev = ns;
          ns = NULL;
        }
        nh = NULL;
        rc = elmc_list_cons(&nh, node->head, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = nh;
        nh = NULL;
        first = 0;
        cursor = node->tail;
      }
      if (rc == RC_SUCCESS) {
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  elmc_release(ns);
  elmc_release(nh);
  elmc_release(rev);
  return rc;
}

RC elmc_list_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *mapped = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *ca = a;
    ElmcValue *cb = b;
    while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
           cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL) {
      ElmcCons *na = (ElmcCons *)ca->payload;
      ElmcCons *nb = (ElmcCons *)cb->payload;
      ElmcValue *args[2] = { na->head, nb->head };
      mapped = NULL;
      rc = elmc_closure_call_rc(&mapped, f, args, 2);
      CHECK_RC(rc);
      next = NULL;
      rc = elmc_list_cons(&next, mapped, rev);
      CHECK_RC(rc);
      elmc_release(mapped);
      mapped = NULL;
      elmc_release(rev);
      rev = next;
      next = NULL;
      ca = na->tail;
      cb = nb->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(mapped);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_list_map3(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *mapped = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *ca = a;
    ElmcValue *cb = b;
    ElmcValue *cc = c;
    while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
           cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL &&
           cc && cc->tag == ELMC_TAG_LIST && cc->payload != NULL) {
      ElmcCons *na = (ElmcCons *)ca->payload;
      ElmcCons *nb = (ElmcCons *)cb->payload;
      ElmcCons *nc = (ElmcCons *)cc->payload;
      ElmcValue *args[3] = { na->head, nb->head, nc->head };
      mapped = NULL;
      rc = elmc_closure_call_rc(&mapped, f, args, 3);
      CHECK_RC(rc);
      next = NULL;
      rc = elmc_list_cons(&next, mapped, rev);
      CHECK_RC(rc);
      elmc_release(mapped);
      mapped = NULL;
      elmc_release(rev);
      rev = next;
      next = NULL;
      ca = na->tail;
      cb = nb->tail;
      cc = nc->tail;
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(mapped);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

/* ================================================================
   Standard Library – Maybe operations
   ================================================================ */

ElmcValue *elmc_maybe_with_default(ElmcValue *default_val, ElmcValue *maybe) {
  if (!maybe) return elmc_retain(default_val);
  if (maybe->tag == ELMC_TAG_MAYBE) {
    ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
    if (m && m->is_just && m->value) return elmc_retain(m->value);
    return elmc_retain(default_val);
  }
  if (maybe->tag == ELMC_TAG_TUPLE2 && maybe->payload) {
    ElmcTuple2 *pair = (ElmcTuple2 *)maybe->payload;
    if (pair->first && elmc_as_int(pair->first) == 1 && pair->second) {
      return elmc_retain(pair->second);
    }
  }
  return elmc_retain(default_val);
}

elmc_int_t elmc_maybe_with_default_int(elmc_int_t default_val, ElmcValue *maybe) {
  if (!maybe) return default_val;
  if (maybe->tag == ELMC_TAG_MAYBE) {
    ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
    if (m && m->is_just && m->value) return elmc_as_int(m->value);
    return default_val;
  }
  if (maybe->tag == ELMC_TAG_TUPLE2 && maybe->payload) {
    ElmcTuple2 *pair = (ElmcTuple2 *)maybe->payload;
    if (pair->first && elmc_as_int(pair->first) == 1 && pair->second) {
      return elmc_as_int(pair->second);
    }
  }
  return default_val;
}

RC elmc_maybe_map(ElmcValue **out, ElmcValue *f, ElmcValue *maybe) {
  RC rc = RC_SUCCESS;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    if (!maybe || maybe->tag != ELMC_TAG_MAYBE) {
      rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
      CHECK_RC(rc);
    } else {
      ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
      if (!m->is_just || !m->value) {
        rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
        CHECK_RC(rc);
      } else {
        ElmcValue *args[1] = { m->value };
        rc = elmc_closure_call_rc(&mapped, f, args, 1);
        CHECK_RC(rc);
        rc = elmc_maybe_just(out, mapped);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  elmc_release(mapped);
  return rc;
}

RC elmc_maybe_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    if (!a || a->tag != ELMC_TAG_MAYBE || !b || b->tag != ELMC_TAG_MAYBE) {
      rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
      CHECK_RC(rc);
    } else {
      ElmcMaybe *ma = (ElmcMaybe *)a->payload;
      ElmcMaybe *mb = (ElmcMaybe *)b->payload;
      if (!ma->is_just || !ma->value || !mb->is_just || !mb->value) {
        rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
        CHECK_RC(rc);
      } else {
        ElmcValue *args[2] = { ma->value, mb->value };
        rc = elmc_closure_call_rc(&mapped, f, args, 2);
        CHECK_RC(rc);
        rc = elmc_maybe_just(out, mapped);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  elmc_release(mapped);
  return rc;
}

RC elmc_maybe_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *maybe) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (!maybe || maybe->tag != ELMC_TAG_MAYBE) {
      rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
      CHECK_RC(rc);
    } else {
      ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
      if (!m->is_just || !m->value) {
        rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
        CHECK_RC(rc);
      } else {
        ElmcValue *args[1] = { m->value };
        rc = elmc_closure_call_rc(out, f, args, 1);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  return rc;
}

/* ================================================================
   Standard Library – Result operations
   ================================================================ */

RC elmc_result_map(ElmcValue **out, ElmcValue *f, ElmcValue *result) {
  RC rc = RC_SUCCESS;
  ElmcValue *msg = NULL;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) {
      rc = elmc_new_string(&msg, "invalid");
      CHECK_RC(rc);
      rc = elmc_result_err(out, msg);
      CHECK_RC(rc);
    } else {
      ElmcResult *r = (ElmcResult *)result->payload;
      if (!r->is_ok) {
        rc = elmc_rc_assign_value(out, elmc_retain(result));
        CHECK_RC(rc);
      } else {
        ElmcValue *args[1] = { r->value };
        rc = elmc_closure_call_rc(&mapped, f, args, 1);
        CHECK_RC(rc);
        rc = elmc_result_ok(out, mapped);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  elmc_release(msg);
  elmc_release(mapped);
  return rc;
}

RC elmc_result_map_error(ElmcValue **out, ElmcValue *f, ElmcValue *result) {
  RC rc = RC_SUCCESS;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) {
      rc = elmc_rc_assign_value(out, elmc_retain(result));
      CHECK_RC(rc);
    } else {
      ElmcResult *r = (ElmcResult *)result->payload;
      if (r->is_ok) {
        rc = elmc_rc_assign_value(out, elmc_retain(result));
        CHECK_RC(rc);
      } else {
        ElmcValue *args[1] = { r->value };
        rc = elmc_closure_call_rc(&mapped, f, args, 1);
        CHECK_RC(rc);
        rc = elmc_result_err(out, mapped);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  elmc_release(mapped);
  return rc;
}

RC elmc_result_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *result) {
  RC rc = RC_SUCCESS;
  ElmcValue *msg = NULL;
  CATCH_BEGIN
    if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) {
      rc = elmc_new_string(&msg, "invalid");
      CHECK_RC(rc);
      rc = elmc_result_err(out, msg);
      CHECK_RC(rc);
    } else {
      ElmcResult *r = (ElmcResult *)result->payload;
      if (!r->is_ok) {
        rc = elmc_rc_assign_value(out, elmc_retain(result));
        CHECK_RC(rc);
      } else {
        ElmcValue *args[1] = { r->value };
        rc = elmc_closure_call_rc(out, f, args, 1);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  elmc_release(msg);
  return rc;
}

ElmcValue *elmc_result_with_default(ElmcValue *default_val, ElmcValue *result) {
  if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return elmc_retain(default_val);
  ElmcResult *r = (ElmcResult *)result->payload;
  if (r->is_ok && r->value) return elmc_retain(r->value);
  return elmc_retain(default_val);
}

ElmcValue *elmc_result_to_maybe(ElmcValue *result) {
  if (!result || result->tag != ELMC_TAG_RESULT || !result->payload) return elmc_maybe_nothing();
  ElmcResult *r = (ElmcResult *)result->payload;
  if (r->is_ok && r->value) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_maybe_just(&_elmc_rc_out, r->value) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  return elmc_maybe_nothing();
}

ElmcValue *elmc_result_from_maybe(ElmcValue *err, ElmcValue *maybe) {
  if (!maybe || maybe->tag != ELMC_TAG_MAYBE || !maybe->payload) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_result_err(&_elmc_rc_out, err) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
  if (m->is_just && m->value) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_result_ok(&_elmc_rc_out, m->value) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_result_err(&_elmc_rc_out, err) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

/* ================================================================
   Standard Library – String operations (extended)
   ================================================================ */

ElmcValue *elmc_string_length_val(ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_int_zero();
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, (int64_t)strlen((const char *)s->payload)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

RC elmc_string_reverse(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (size_t i = 0; i < len; i++) {
        buf[i] = src[len - 1 - i];
      }
      buf[len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    int64_t count = elmc_as_int(n);
    if (count <= 0 || !s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t slen = strlen(src);
      size_t total = slen * (size_t)count;
      buf = (char *)elmc_malloc(total + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (int64_t i = 0; i < count; i++) {
        memcpy(buf + i * slen, src, slen);
      }
      buf[total] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_replace(ElmcValue **out, ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else if (!old_s || old_s->tag != ELMC_TAG_STRING || !old_s->payload) {
      rc = elmc_rc_assign_value(out, elmc_retain(s));
      CHECK_RC(rc);
    } else {
      if (!new_s || new_s->tag != ELMC_TAG_STRING || !new_s->payload) new_s = &ELMC_EMPTY_STRING;
      const char *haystack = (const char *)s->payload;
      const char *needle = (const char *)old_s->payload;
      const char *replacement = (const char *)new_s->payload;
      size_t needle_len = strlen(needle);
      if (needle_len == 0) {
        rc = elmc_rc_assign_value(out, elmc_retain(s));
        CHECK_RC(rc);
      } else {
        size_t repl_len = strlen(replacement);
        size_t cap = strlen(haystack) + 1;
        buf = (char *)elmc_malloc(cap, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        size_t out_len = 0;
        const char *p = haystack;
        while (*p) {
          if (strncmp(p, needle, needle_len) == 0) {
            size_t needed = out_len + repl_len + strlen(p) + 1;
            if (needed > cap) {
              cap = needed * 2;
              char *grown = (char *)elmc_malloc(cap, __func__);
              if (!grown) {
                rc = RC_ERR_OUT_OF_MEMORY;
                CHECK_RC(rc);
              }
              memcpy(grown, buf, out_len);
              free(buf);
              buf = grown;
            }
            memcpy(buf + out_len, replacement, repl_len);
            out_len += repl_len;
            p += needle_len;
          } else {
            size_t needed = out_len + strlen(p) + 2;
            if (needed > cap) {
              cap = needed * 2;
              char *grown = (char *)elmc_malloc(cap, __func__);
              if (!grown) {
                rc = RC_ERR_OUT_OF_MEMORY;
                CHECK_RC(rc);
              }
              memcpy(grown, buf, out_len);
              free(buf);
              buf = grown;
            }
            buf[out_len++] = *p++;
          }
        }
        buf[out_len] = '\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!allocated) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        rc = elmc_rc_assign_value(out, allocated);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

ElmcValue *elmc_string_from_int(ElmcValue *n) {
  return elmc_string_from_native_int_take(elmc_as_int(n));
}

RC elmc_string_from_native_int(ElmcValue **out, elmc_int_t n) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    char buf[32];
    snprintf(buf, sizeof(buf), "%lld", (long long)n);
    rc = elmc_new_string(out, buf);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

ElmcValue *elmc_string_to_int(ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_maybe_nothing();
  const char *str = (const char *)s->payload;
  if (!str || *str == '\0') return elmc_maybe_nothing();
  int sign = 1;
  size_t idx = 0;
  if (str[idx] == '+' || str[idx] == '-') {
    if (str[idx] == '-') sign = -1;
    idx++;
  }
  if (str[idx] == '\0') return elmc_maybe_nothing();

  uint64_t acc = 0;
  int saw_digit = 0;
  for (; str[idx] != '\0'; idx++) {
    char ch = str[idx];
    if (ch < '0' || ch > '9') return elmc_maybe_nothing();
    saw_digit = 1;
    uint64_t digit = (uint64_t)(ch - '0');
    if (acc > 922337203685477580ULL || (acc == 922337203685477580ULL && digit > 7ULL + (sign < 0 ? 1ULL : 0ULL))) {
      return elmc_maybe_nothing();
    }
    acc = (acc * 10ULL) + digit;
  }
  if (!saw_digit) return elmc_maybe_nothing();

  int64_t parsed = 0;
  if (sign < 0) {
    if (acc == 9223372036854775808ULL) {
      parsed = INT64_MIN;
    } else {
      parsed = -(int64_t)acc;
    }
  } else {
    parsed = (int64_t)acc;
  }

  ElmcValue *v = NULL;
  if (elmc_new_int(&v, parsed) != RC_SUCCESS) v = NULL;
  ElmcValue *out = NULL;
  if (elmc_maybe_just(&out, v) != RC_SUCCESS) out = NULL;
  elmc_release(v);
  return out;
}

RC elmc_string_from_float(ElmcValue **out, ElmcValue *f) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    char buf[64];
    double val = elmc_as_float(f);
    int64_t whole = (int64_t)val;
    if (val == (double)whole) {
      snprintf(buf, sizeof(buf), "%lld", (long long)whole);
    } else {
      double abs_val = (val < 0.0) ? -val : val;
      int64_t abs_whole = (int64_t)abs_val;
      int64_t frac3 = (int64_t)((abs_val - (double)abs_whole) * 1000.0 + 0.5);
      if (frac3 >= 1000) {
        abs_whole += 1;
        frac3 = 0;
      }
      if (val < 0.0) {
        snprintf(buf, sizeof(buf), "-%lld.%03lld", (long long)abs_whole, (long long)frac3);
      } else {
        snprintf(buf, sizeof(buf), "%lld.%03lld", (long long)abs_whole, (long long)frac3);
      }
    }
    rc = elmc_new_string(out, buf);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

ElmcValue *elmc_string_to_float(ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return elmc_maybe_nothing();

  const char *p = (const char *)s->payload;
  int sign = 1;
  if (*p == '+' || *p == '-') {
    if (*p == '-') sign = -1;
    p++;
  }

  int saw_digit = 0;
  double whole = 0.0;
  while (*p >= '0' && *p <= '9') {
    saw_digit = 1;
    whole = whole * 10.0 + (double)(*p - '0');
    p++;
  }

  double frac = 0.0;
  double place = 0.1;
  if (*p == '.') {
    p++;
    while (*p >= '0' && *p <= '9') {
      saw_digit = 1;
      frac += (double)(*p - '0') * place;
      place *= 0.1;
      p++;
    }
  }

  if (!saw_digit || *p != '\0') return elmc_maybe_nothing();

  double val = (double)sign * (whole + frac);
  ElmcValue *v = elmc_new_float_take(val);
  ElmcValue *out = NULL;
  if (elmc_maybe_just(&out, v) != RC_SUCCESS) out = NULL;
  elmc_release(v);
  return out;
}

RC elmc_string_to_upper(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (size_t i = 0; i < len; i++) {
        char c = src[i];
        buf[i] = (c >= 'a' && c <= 'z') ? (c - 32) : c;
      }
      buf[len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_to_lower(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (size_t i = 0; i < len; i++) {
        char c = src[i];
        buf[i] = (c >= 'A' && c <= 'Z') ? (c + 32) : c;
      }
      buf[len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_trim(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      size_t start = 0;
      while (start < len && (src[start] == ' ' || src[start] == '\t' || src[start] == '\n' || src[start] == '\r')) start++;
      size_t end = len;
      while (end > start && (src[end-1] == ' ' || src[end-1] == '\t' || src[end-1] == '\n' || src[end-1] == '\r')) end--;
      size_t new_len = end - start;
      buf = (char *)elmc_malloc(new_len + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      memcpy(buf, src + start, new_len);
      buf[new_len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_trim_left(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      size_t start = 0;
      while (start < len && (src[start] == ' ' || src[start] == '\t' || src[start] == '\n' || src[start] == '\r')) start++;
      rc = elmc_new_string(out, src + start);
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

RC elmc_string_trim_right(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      while (len > 0 && (src[len-1] == ' ' || src[len-1] == '\t' || src[len-1] == '\n' || src[len-1] == '\r')) len--;
      buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      memcpy(buf, src, len);
      buf[len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

ElmcValue *elmc_string_contains(ElmcValue *sub, ElmcValue *s) {
  if (!sub || sub->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 0);
    return _elmc_rc_out;
  }
  const char *haystack = (const char *)s->payload;
  const char *needle = (const char *)sub->payload;
  if (!haystack || !needle) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 0);
    return _elmc_rc_out;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, strstr(haystack, needle) != NULL);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_string_starts_with(ElmcValue *prefix, ElmcValue *s) {
  if (!prefix || prefix->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 0);
    return _elmc_rc_out;
  }
  const char *str = (const char *)s->payload;
  const char *pre = (const char *)prefix->payload;
  if (!str || !pre) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 0);
    return _elmc_rc_out;
  }
  size_t plen = strlen(pre);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, strncmp(str, pre, plen) == 0);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_string_ends_with(ElmcValue *suffix, ElmcValue *s) {
  if (!suffix || suffix->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 0);
    return _elmc_rc_out;
  }
  const char *str = (const char *)s->payload;
  const char *suf = (const char *)suffix->payload;
  if (!str || !suf) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 0);
    return _elmc_rc_out;
  }
  size_t slen = strlen(str);
  size_t suflen = strlen(suf);
  if (suflen > slen) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 0);
    return _elmc_rc_out;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, strcmp(str + slen - suflen, suf) == 0);
      return _elmc_rc_out;
  }
}

RC elmc_string_split(ElmcValue **out, ElmcValue *sep, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *ch = NULL;
  ElmcValue *part = NULL;
  ElmcValue *next = NULL;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
      CHECK_RC(rc);
    } else if (!sep || sep->tag != ELMC_TAG_STRING || !sep->payload) {
      ElmcValue *nil = elmc_list_nil();
      rc = elmc_list_cons(out, s, nil);
      elmc_release(nil);
      CHECK_RC(rc);
    } else {
      const char *str = (const char *)s->payload;
      const char *sp = (const char *)sep->payload;
      size_t splen = strlen(sp);
      if (splen == 0) {
        size_t slen = strlen(str);
        for (size_t i = 0; i < slen; i++) {
          char tmp[2] = { str[i], '\0' };
          ch = NULL;
          rc = elmc_new_string(&ch, tmp);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, ch, rev);
          CHECK_RC(rc);
          elmc_release(ch);
          ch = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
        }
      } else {
        const char *p = str;
        while (1) {
          const char *found = strstr(p, sp);
          if (!found) {
            part = NULL;
            rc = elmc_new_string(&part, p);
            CHECK_RC(rc);
            next = NULL;
            rc = elmc_list_cons(&next, part, rev);
            CHECK_RC(rc);
            elmc_release(part);
            part = NULL;
            elmc_release(rev);
            rev = next;
            next = NULL;
            break;
          }
          size_t chunk = (size_t)(found - p);
          buf = (char *)elmc_malloc(chunk + 1, __func__);
          if (!buf) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          memcpy(buf, p, chunk);
          buf[chunk] = '\0';
          part = elmc_alloc(ELMC_TAG_STRING, buf);
          buf = NULL;
          if (!part) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          next = NULL;
          rc = elmc_list_cons(&next, part, rev);
          CHECK_RC(rc);
          elmc_release(part);
          part = NULL;
          elmc_release(rev);
          rev = next;
          next = NULL;
          p = found + splen;
        }
      }
      if (rc == RC_SUCCESS) {
        rc = elmc_list_reverse_transfer(out, &rev);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  if (buf) free(buf);
  elmc_release(ch);
  elmc_release(part);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_string_join(ElmcValue **out, ElmcValue *sep, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_LIST || list->payload == NULL) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *sp = (sep && sep->tag == ELMC_TAG_STRING && sep->payload) ? (const char *)sep->payload : "";
      size_t splen = strlen(sp);
      size_t total = 0;
      int count = 0;
      ElmcValue *cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (node->head && node->head->tag == ELMC_TAG_STRING && node->head->payload) {
          total += strlen((const char *)node->head->payload);
        }
        count++;
        cursor = node->tail;
      }
      if (count > 1) total += splen * (size_t)(count - 1);
      buf = (char *)elmc_malloc(total + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      size_t pos = 0;
      int idx = 0;
      cursor = list;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (idx > 0 && splen > 0) {
          memcpy(buf + pos, sp, splen);
          pos += splen;
        }
        if (node->head && node->head->tag == ELMC_TAG_STRING && node->head->payload) {
          size_t slen = strlen((const char *)node->head->payload);
          memcpy(buf + pos, (const char *)node->head->payload, slen);
          pos += slen;
        }
        idx++;
        cursor = node->tail;
      }
      buf[pos] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

ElmcValue *elmc_string_words(ElmcValue *s) {
  ElmcValue *space = NULL;
  if (elmc_new_string(&space, " ") != RC_SUCCESS) space = NULL;
  ElmcValue *out = elmc_string_split_take(space, s);
  elmc_release(space);
  return out;
}

ElmcValue *elmc_string_lines(ElmcValue *s) {
  ElmcValue *nl = NULL;
  if (elmc_new_string(&nl, "\n") != RC_SUCCESS) nl = NULL;
  ElmcValue *out = elmc_string_split_take(nl, s);
  elmc_release(nl);
  return out;
}

RC elmc_string_slice(ElmcValue **out, ElmcValue *start, ElmcValue *end_idx, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      int64_t len = (int64_t)strlen(src);
      int64_t st = elmc_as_int(start);
      int64_t en = elmc_as_int(end_idx);
      if (st < 0) st = len + st;
      if (en < 0) en = len + en;
      if (st < 0) st = 0;
      if (en < 0) en = 0;
      if (st > len) st = len;
      if (en > len) en = len;
      if (en <= st) {
        rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
        CHECK_RC(rc);
      } else {
        size_t new_len = (size_t)(en - st);
        buf = (char *)elmc_malloc(new_len + 1, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        memcpy(buf, src + st, new_len);
        buf[new_len] = '\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!allocated) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        rc = elmc_rc_assign_value(out, allocated);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

ElmcValue *elmc_string_left(ElmcValue *n, ElmcValue *s) {
  ElmcValue *zero = elmc_int_zero();
  ElmcValue *out = elmc_string_slice_take(zero, n, s);
  elmc_release(zero);
  return out;
}

ElmcValue *elmc_string_right(ElmcValue *n, ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
  int64_t len = (int64_t)strlen((const char *)s->payload);
  int64_t count = elmc_as_int(n);
  int64_t st = len - count;
  if (st < 0) st = 0;
  ElmcValue *start_v = NULL;
  if (elmc_new_int(&start_v, st) != RC_SUCCESS) start_v = NULL;
  ElmcValue *end_v = NULL;
  if (elmc_new_int(&end_v, len) != RC_SUCCESS) end_v = NULL;
  ElmcValue *out = elmc_string_slice_take(start_v, end_v, s);
  elmc_release(start_v);
  elmc_release(end_v);
  return out;
}

ElmcValue *elmc_string_drop_left(ElmcValue *n, ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
  int64_t len = (int64_t)strlen((const char *)s->payload);
  ElmcValue *end_v = NULL;
  if (elmc_new_int(&end_v, len) != RC_SUCCESS) end_v = NULL;
  ElmcValue *out = elmc_string_slice_take(n, end_v, s);
  elmc_release(end_v);
  return out;
}

ElmcValue *elmc_string_drop_right(ElmcValue *n, ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
  int64_t len = (int64_t)strlen((const char *)s->payload);
  int64_t count = elmc_as_int(n);
  int64_t en = len - count;
  if (en < 0) en = 0;
  ElmcValue *zero = elmc_int_zero();
  ElmcValue *end_v = NULL;
  if (elmc_new_int(&end_v, en) != RC_SUCCESS) end_v = NULL;
  ElmcValue *out = elmc_string_slice_take(zero, end_v, s);
  elmc_release(zero);
  elmc_release(end_v);
  return out;
}

ElmcValue *elmc_string_cons(ElmcValue *ch, ElmcValue *s) {
  char prefix[2] = { (char)elmc_as_int(ch), '\0' };
  ElmcValue *prefix_v = NULL;
  if (elmc_new_string(&prefix_v, prefix) != RC_SUCCESS) prefix_v = NULL;
  ElmcValue *out = elmc_string_append_take(prefix_v, s);
  elmc_release(prefix_v);
  return out;
}

RC elmc_string_uncons(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  ElmcValue *ch = NULL;
  ElmcValue *rest = NULL;
  ElmcValue *pair = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
      CHECK_RC(rc);
    } else {
      const char *str = (const char *)s->payload;
      if (strlen(str) == 0) {
        rc = elmc_rc_assign_value(out, elmc_maybe_nothing());
        CHECK_RC(rc);
      } else {
        rc = elmc_new_int(&ch, (int64_t)(unsigned char)str[0]);
        CHECK_RC(rc);
        rc = elmc_new_string(&rest, str + 1);
        CHECK_RC(rc);
        rc = elmc_tuple2(&pair, ch, rest);
        CHECK_RC(rc);
        rc = elmc_maybe_just(out, pair);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(rest);
  elmc_release(pair);
  return rc;
}

RC elmc_string_to_list(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *ch = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
      CHECK_RC(rc);
    } else {
      const char *str = (const char *)s->payload;
      size_t len = strlen(str);
      for (size_t i = len; i > 0; i--) {
        ch = NULL;
        rc = elmc_new_int(&ch, (int64_t)(unsigned char)str[i - 1]);
        CHECK_RC(rc);
        next = NULL;
        rc = elmc_list_cons(&next, ch, rev);
        CHECK_RC(rc);
        elmc_release(ch);
        ch = NULL;
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_string_from_list(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    int64_t count = 0;
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      count++;
      cursor = ((ElmcCons *)cursor->payload)->tail;
    }
    buf = (char *)elmc_malloc((size_t)count + 1, __func__);
    if (!buf) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    int64_t idx = 0;
    cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      buf[idx++] = (char)elmc_as_int(node->head);
      cursor = node->tail;
    }
    buf[count] = '\0';
    ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
    buf = NULL;
    if (!allocated) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    rc = elmc_rc_assign_value(out, allocated);
    CHECK_RC(rc);
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_from_char(ElmcValue **out, ElmcValue *ch) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    char buf[2] = { (char)elmc_as_int(ch), '\0' };
    rc = elmc_new_string(out, buf);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

ElmcValue *elmc_string_pad(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
  return elmc_string_pad_left_take(n, ch, s);
}

RC elmc_string_pad_left(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      int64_t target = elmc_as_int(n);
      int64_t cur_len = (int64_t)strlen(src);
      if (cur_len >= target) {
        rc = elmc_rc_assign_value(out, elmc_retain(s));
        CHECK_RC(rc);
      } else {
        int64_t pad_count = target - cur_len;
        char pad_char = (char)elmc_as_int(ch);
        buf = (char *)elmc_malloc((size_t)target + 1, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        for (int64_t i = 0; i < pad_count; i++) buf[i] = pad_char;
        memcpy(buf + pad_count, src, (size_t)cur_len);
        buf[target] = '\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!allocated) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        rc = elmc_rc_assign_value(out, allocated);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_pad_right(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      int64_t target = elmc_as_int(n);
      int64_t cur_len = (int64_t)strlen(src);
      if (cur_len >= target) {
        rc = elmc_rc_assign_value(out, elmc_retain(s));
        CHECK_RC(rc);
      } else {
        int64_t pad_count = target - cur_len;
        char pad_char = (char)elmc_as_int(ch);
        buf = (char *)elmc_malloc((size_t)target + 1, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        memcpy(buf, src, (size_t)cur_len);
        for (int64_t i = 0; i < pad_count; i++) buf[cur_len + i] = pad_char;
        buf[target] = '\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!allocated) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        rc = elmc_rc_assign_value(out, allocated);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  if (buf) free(buf);
  return rc;
}

RC elmc_string_map(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  ElmcValue *ch = NULL;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (size_t i = 0; i < len; i++) {
        ch = NULL;
        rc = elmc_new_int(&ch, (int64_t)(unsigned char)src[i]);
        CHECK_RC(rc);
        ElmcValue *args[1] = { ch };
        mapped = NULL;
        rc = elmc_closure_call_rc(&mapped, f, args, 1);
        CHECK_RC(rc);
        buf[i] = (char)elmc_as_int(mapped);
        elmc_release(ch);
        ch = NULL;
        elmc_release(mapped);
        mapped = NULL;
      }
      buf[len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(mapped);
  if (buf) free(buf);
  return rc;
}

RC elmc_string_filter(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  ElmcValue *ch = NULL;
  ElmcValue *keep = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, &ELMC_EMPTY_STRING);
      CHECK_RC(rc);
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      buf = (char *)elmc_malloc(len + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      size_t out_len = 0;
      for (size_t i = 0; i < len; i++) {
        ch = NULL;
        rc = elmc_new_int(&ch, (int64_t)(unsigned char)src[i]);
        CHECK_RC(rc);
        ElmcValue *args[1] = { ch };
        keep = NULL;
        rc = elmc_closure_call_rc(&keep, f, args, 1);
        CHECK_RC(rc);
        if (elmc_as_int(keep)) buf[out_len++] = src[i];
        elmc_release(ch);
        ch = NULL;
        elmc_release(keep);
        keep = NULL;
      }
      buf[out_len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      rc = elmc_rc_assign_value(out, allocated);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(keep);
  if (buf) free(buf);
  return rc;
}

RC elmc_string_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *ch = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, result);
      CHECK_RC(rc);
      result = NULL;
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      for (size_t i = 0; i < len; i++) {
        ch = NULL;
        rc = elmc_new_int(&ch, (int64_t)(unsigned char)src[i]);
        CHECK_RC(rc);
        ElmcValue *args[2] = { ch, result };
        next = NULL;
        rc = elmc_closure_call_rc(&next, f, args, 2);
        CHECK_RC(rc);
        elmc_release(ch);
        ch = NULL;
        elmc_release(result);
        result = next;
        next = NULL;
      }
      rc = elmc_rc_assign_value(out, result);
      CHECK_RC(rc);
      result = NULL;
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_string_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *ch = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      rc = elmc_rc_assign_value(out, result);
      CHECK_RC(rc);
      result = NULL;
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      for (size_t i = len; i > 0; i--) {
        ch = NULL;
        rc = elmc_new_int(&ch, (int64_t)(unsigned char)src[i - 1]);
        CHECK_RC(rc);
        ElmcValue *args[2] = { ch, result };
        next = NULL;
        rc = elmc_closure_call_rc(&next, f, args, 2);
        CHECK_RC(rc);
        elmc_release(ch);
        ch = NULL;
        elmc_release(result);
        result = next;
        next = NULL;
      }
      rc = elmc_rc_assign_value(out, result);
      CHECK_RC(rc);
      result = NULL;
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_string_any(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  int answer = 0;
  int done = 0;
  ElmcValue *ch = NULL;
  ElmcValue *result = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      answer = 0;
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      for (size_t i = 0; !done && i < len; i++) {
        ch = NULL;
        rc = elmc_new_int(&ch, (int64_t)(unsigned char)src[i]);
        CHECK_RC(rc);
        ElmcValue *args[1] = { ch };
        result = NULL;
        rc = elmc_closure_call_rc(&result, f, args, 1);
        CHECK_RC(rc);
        int truthy = elmc_as_int(result) != 0;
        elmc_release(ch);
        ch = NULL;
        elmc_release(result);
        result = NULL;
        if (truthy) {
          answer = 1;
          done = 1;
        }
      }
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_new_bool(out, answer);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(result);
  return rc;
}

RC elmc_string_all(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  int answer = 1;
  int done = 0;
  ElmcValue *ch = NULL;
  ElmcValue *result = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      answer = 1;
    } else {
      const char *src = (const char *)s->payload;
      size_t len = strlen(src);
      for (size_t i = 0; !done && i < len; i++) {
        ch = NULL;
        rc = elmc_new_int(&ch, (int64_t)(unsigned char)src[i]);
        CHECK_RC(rc);
        ElmcValue *args[1] = { ch };
        result = NULL;
        rc = elmc_closure_call_rc(&result, f, args, 1);
        CHECK_RC(rc);
        int truthy = elmc_as_int(result) != 0;
        elmc_release(ch);
        ch = NULL;
        elmc_release(result);
        result = NULL;
        if (!truthy) {
          answer = 0;
          done = 1;
        }
      }
    }
    if (rc == RC_SUCCESS) {
      rc = elmc_new_bool(out, answer);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(result);
  return rc;
}

RC elmc_string_indexes(ElmcValue **out, ElmcValue *sub, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *idx = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!sub || sub->tag != ELMC_TAG_STRING || !s || s->tag != ELMC_TAG_STRING) {
      rc = elmc_rc_assign_value(out, elmc_list_nil());
      CHECK_RC(rc);
    } else {
      const char *haystack = (const char *)s->payload;
      const char *needle = (const char *)sub->payload;
      if (!haystack || !needle) {
        rc = elmc_rc_assign_value(out, elmc_list_nil());
        CHECK_RC(rc);
      } else {
        size_t nlen = strlen(needle);
        if (nlen == 0) {
          rc = elmc_rc_assign_value(out, elmc_list_nil());
          CHECK_RC(rc);
        } else {
          const char *p = haystack;
          while ((p = strstr(p, needle)) != NULL) {
            idx = NULL;
            rc = elmc_new_int(&idx, (int64_t)(p - haystack));
            CHECK_RC(rc);
            next = NULL;
            rc = elmc_list_cons(&next, idx, rev);
            CHECK_RC(rc);
            elmc_release(idx);
            idx = NULL;
            elmc_release(rev);
            rev = next;
            next = NULL;
            p += 1;
          }
          rc = elmc_list_reverse_transfer(out, &rev);
          CHECK_RC(rc);
        }
      }
    }
  CATCH_END;
  elmc_release(idx);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

/* ================================================================
   Standard Library – Tuple operations (extended)
   ================================================================ */

RC elmc_tuple_map_first(ElmcValue **out, ElmcValue *f, ElmcValue *t) {
  RC rc = RC_SUCCESS;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) {
      rc = elmc_rc_assign_value(out, elmc_retain(t));
      CHECK_RC(rc);
    } else {
      ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
      ElmcValue *args[1] = { tuple->first };
      rc = elmc_closure_call_rc(&mapped, f, args, 1);
      CHECK_RC(rc);
      rc = elmc_tuple2(out, mapped, tuple->second);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(mapped);
  return rc;
}

RC elmc_tuple_map_second(ElmcValue **out, ElmcValue *f, ElmcValue *t) {
  RC rc = RC_SUCCESS;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) {
      rc = elmc_rc_assign_value(out, elmc_retain(t));
      CHECK_RC(rc);
    } else {
      ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
      ElmcValue *args[1] = { tuple->second };
      rc = elmc_closure_call_rc(&mapped, f, args, 1);
      CHECK_RC(rc);
      rc = elmc_tuple2(out, tuple->first, mapped);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(mapped);
  return rc;
}

RC elmc_tuple_map_both(ElmcValue **out, ElmcValue *f, ElmcValue *g, ElmcValue *t) {
  RC rc = RC_SUCCESS;
  ElmcValue *mf = NULL;
  ElmcValue *mg = NULL;
  CATCH_BEGIN
    if (!t || t->tag != ELMC_TAG_TUPLE2 || !t->payload) {
      rc = elmc_rc_assign_value(out, elmc_retain(t));
      CHECK_RC(rc);
    } else {
      ElmcTuple2 *tuple = (ElmcTuple2 *)t->payload;
      ElmcValue *args_f[1] = { tuple->first };
      ElmcValue *args_g[1] = { tuple->second };
      rc = elmc_closure_call_rc(&mf, f, args_f, 1);
      CHECK_RC(rc);
      rc = elmc_closure_call_rc(&mg, g, args_g, 1);
      CHECK_RC(rc);
      rc = elmc_tuple2(out, mf, mg);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(mf);
  elmc_release(mg);
  return rc;
}

/* ================================================================
   Standard Library – Basics (extended)
   ================================================================ */

ElmcValue *elmc_basics_not(ElmcValue *x) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, elmc_as_int(x) == 0 ? 1 : 0);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_negate(ElmcValue *x) {
  if (x && x->tag == ELMC_TAG_FLOAT) {
    return elmc_new_float_take(-elmc_as_float(x));
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, -elmc_as_int(x)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_abs(ElmcValue *x) {
  if (x && x->tag == ELMC_TAG_FLOAT) {
    double v = elmc_as_float(x);
    return elmc_new_float_take(v < 0 ? -v : v);
  }
  int64_t v = elmc_as_int(x);
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, v < 0 ? -v : v) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_to_float(ElmcValue *x) {
  return elmc_new_float_take((double)elmc_as_int(x));
}

static double elmc_basics_nan(void) {
  volatile double zero = 0.0;
  return zero / zero;
}

static double elmc_basics_inf(void) {
  volatile double zero = 0.0;
  return 1.0 / zero;
}

ElmcValue *elmc_basics_sqrt(ElmcValue *x) {
  double v = elmc_as_float(x);
  if (v < 0.0) return elmc_new_float_take(elmc_basics_nan());
  if (v == 0.0) return elmc_new_float_take(0.0);

  double guess = v >= 1.0 ? v : 1.0;
  for (int i = 0; i < 24; i++) {
    guess = 0.5 * (guess + v / guess);
  }
  return elmc_new_float_take(guess);
}

double elmc_basics_sqrt_double(double x) {
  ElmcValue stack = { .rc = 1, .tag = ELMC_TAG_FLOAT, .payload = &x };
  ElmcValue *out = elmc_basics_sqrt(&stack);
  double result = elmc_as_float(out);
  elmc_release(out);
  return result;
}

static double elmc_basics_log_double(double x) {
  const double e = 2.71828182845904523536;
  if (x < 0.0) return elmc_basics_nan();
  if (x == 0.0) return -elmc_basics_inf();

  int k = 0;
  while (x > e) {
    x /= e;
    k++;
  }
  while (x < 1.0 / e) {
    x *= e;
    k--;
  }

  double z = (x - 1.0) / (x + 1.0);
  double z2 = z * z;
  double term = z;
  double sum = 0.0;
  for (int n = 1; n <= 35; n += 2) {
    sum += term / (double)n;
    term *= z2;
  }
  return 2.0 * sum + (double)k;
}

ElmcValue *elmc_basics_log_base(ElmcValue *base, ElmcValue *x) {
  double denominator = elmc_basics_log_double(elmc_as_float(base));
  return elmc_new_float_take(elmc_basics_log_double(elmc_as_float(x)) / denominator);
}

static double elmc_basics_normalize_radians(double x) {
  const double pi = 3.14159265358979323846;
  const double two_pi = 6.28318530717958647692;
  while (x > pi) x -= two_pi;
  while (x < -pi) x += two_pi;
  return x;
}

double elmc_basics_sin_double(double x) {
  const double pi = 3.14159265358979323846;
  const double half_pi = 1.57079632679489661923;
  x = elmc_basics_normalize_radians(x);
  if (x > half_pi) x = pi - x;
  if (x < -half_pi) x = -pi - x;
  double x2 = x * x;
  return x * (1.0
      - x2 / 6.0
      + (x2 * x2) / 120.0
      - (x2 * x2 * x2) / 5040.0
      + (x2 * x2 * x2 * x2) / 362880.0);
}

ElmcValue *elmc_basics_sin(ElmcValue *x) {
  return elmc_new_float_take(elmc_basics_sin_double(elmc_as_float(x)));
}

double elmc_basics_cos_double(double x) {
  const double half_pi = 1.57079632679489661923;
  return elmc_basics_sin_double(x + half_pi);
}

ElmcValue *elmc_basics_cos(ElmcValue *x) {
  return elmc_new_float_take(elmc_basics_cos_double(elmc_as_float(x)));
}

double elmc_basics_tan_double(double x) {
  return elmc_basics_sin_double(x) / elmc_basics_cos_double(x);
}

ElmcValue *elmc_basics_tan(ElmcValue *x) {
  return elmc_new_float_take(elmc_basics_tan_double(elmc_as_float(x)));
}

static double elmc_basics_atan_double(double x) {
  const double half_pi = 1.57079632679489661923;
  int negative = x < 0.0;
  if (negative) x = -x;

  int invert = x > 1.0;
  if (invert) x = 1.0 / x;

  double x2 = x * x;
  double term = x;
  double sum = 0.0;
  double sign = 1.0;
  for (int n = 1; n <= 31; n += 2) {
    sum += sign * term / (double)n;
    term *= x2;
    sign = -sign;
  }

  if (invert) sum = half_pi - sum;
  return negative ? -sum : sum;
}

ElmcValue *elmc_basics_atan(ElmcValue *x) {
  return elmc_new_float_take(elmc_basics_atan_double(elmc_as_float(x)));
}

ElmcValue *elmc_basics_atan2(ElmcValue *y, ElmcValue *x) {
  const double pi = 3.14159265358979323846;
  const double half_pi = 1.57079632679489661923;
  double yy = elmc_as_float(y);
  double xx = elmc_as_float(x);

  if (xx > 0.0) return elmc_new_float_take(elmc_basics_atan_double(yy / xx));
  if (xx < 0.0 && yy >= 0.0) return elmc_new_float_take(elmc_basics_atan_double(yy / xx) + pi);
  if (xx < 0.0 && yy < 0.0) return elmc_new_float_take(elmc_basics_atan_double(yy / xx) - pi);
  if (xx == 0.0 && yy > 0.0) return elmc_new_float_take(half_pi);
  if (xx == 0.0 && yy < 0.0) return elmc_new_float_take(-half_pi);
  return elmc_new_float_take(0.0);
}

ElmcValue *elmc_basics_asin(ElmcValue *x) {
  double v = elmc_as_float(x);
  if (v < -1.0 || v > 1.0) return elmc_new_float_take(elmc_basics_nan());
  double denom = elmc_basics_sqrt_double(1.0 - v * v);
  return elmc_new_float_take(elmc_basics_atan_double(v / denom));
}

ElmcValue *elmc_basics_acos(ElmcValue *x) {
  const double half_pi = 1.57079632679489661923;
  ElmcValue *asin_value = elmc_basics_asin(x);
  double out = half_pi - elmc_as_float(asin_value);
  elmc_release(asin_value);
  return elmc_new_float_take(out);
}

ElmcValue *elmc_basics_degrees(ElmcValue *x) {
  return elmc_new_float_take(elmc_as_float(x) * 0.01745329251994329577);
}

ElmcValue *elmc_basics_radians(ElmcValue *x) {
  return elmc_new_float_take(elmc_as_float(x));
}

ElmcValue *elmc_basics_turns(ElmcValue *x) {
  return elmc_new_float_take(elmc_as_float(x) * 6.28318530717958647692);
}

ElmcValue *elmc_basics_from_polar(ElmcValue *polar) {
  if (!polar || polar->tag != ELMC_TAG_TUPLE2 || !polar->payload) {
    ElmcValue *x0 = elmc_new_float_take(0.0);
    ElmcValue *y0 = elmc_new_float_take(0.0);
    ElmcValue *out0 = NULL;
    if (elmc_tuple2(&out0, x0, y0) != RC_SUCCESS) out0 = NULL;
    elmc_release(x0);
    elmc_release(y0);
    return out0;
  }
  ElmcTuple2 *pair = (ElmcTuple2 *)polar->payload;
  double radius = elmc_as_float(pair->first);
  double theta = elmc_as_float(pair->second);
  ElmcValue *x = elmc_new_float_take(radius * elmc_basics_sin_double(theta + 1.57079632679489661923));
  ElmcValue *y = elmc_new_float_take(radius * elmc_basics_sin_double(theta));
  ElmcValue *out = NULL;
  if (elmc_tuple2(&out, x, y) != RC_SUCCESS) out = NULL;
  elmc_release(x);
  elmc_release(y);
  return out;
}

ElmcValue *elmc_basics_to_polar(ElmcValue *point) {
  if (!point || point->tag != ELMC_TAG_TUPLE2 || !point->payload) {
    ElmcValue *r0 = elmc_new_float_take(0.0);
    ElmcValue *t0 = elmc_new_float_take(0.0);
    ElmcValue *out0 = NULL;
    if (elmc_tuple2(&out0, r0, t0) != RC_SUCCESS) out0 = NULL;
    elmc_release(r0);
    elmc_release(t0);
    return out0;
  }
  ElmcTuple2 *pair = (ElmcTuple2 *)point->payload;
  double x = elmc_as_float(pair->first);
  double y = elmc_as_float(pair->second);
  ElmcValue *radius = elmc_new_float_take(elmc_basics_sqrt_double(x * x + y * y));
  ElmcValue *theta = elmc_new_float_take(elmc_basics_atan_double(y / x));
  if (x < 0.0) {
    double adjusted = elmc_as_float(theta) + (y >= 0.0 ? 3.14159265358979323846 : -3.14159265358979323846);
    elmc_release(theta);
    theta = elmc_new_float_take(adjusted);
  } else if (x == 0.0) {
    elmc_release(theta);
    theta = elmc_new_float_take(y > 0.0 ? 1.57079632679489661923 : (y < 0.0 ? -1.57079632679489661923 : 0.0));
  }
  ElmcValue *out = NULL;
  if (elmc_tuple2(&out, radius, theta) != RC_SUCCESS) out = NULL;
  elmc_release(radius);
  elmc_release(theta);
  return out;
}

ElmcValue *elmc_basics_is_nan(ElmcValue *x) {
  double v = elmc_as_float(x);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, v != v);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_is_infinite(ElmcValue *x) {
  double v = elmc_as_float(x);
  double delta = v - v;
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, (v == v && delta != delta) ? 1 : 0);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_round(ElmcValue *x) {
  double v = elmc_as_float(x);
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, (int64_t)(v + (v >= 0 ? 0.5 : -0.5))) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_floor(ElmcValue *x) {
  double v = elmc_as_float(x);
  int64_t i = (int64_t)v;
  if ((double)i > v) i--;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, i) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_ceiling(ElmcValue *x) {
  double v = elmc_as_float(x);
  int64_t i = (int64_t)v;
  if ((double)i < v) i++;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, i) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_truncate(ElmcValue *x) {
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, (int64_t)elmc_as_float(x)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_remainder_by(ElmcValue *base, ElmcValue *value) {
  elmc_int_t b = elmc_as_int(base);
  elmc_int_t v = elmc_as_int(value);
  if (b == 0) return elmc_int_zero();
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, v % b) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_pow(ElmcValue *base, ElmcValue *exponent) {
  int64_t exp = elmc_as_int(exponent);
  int negative = exp < 0;
  uint64_t count = (uint64_t)(negative ? -exp : exp);
  double result = 1.0;

  if (base && base->tag == ELMC_TAG_FLOAT) {
    double b = elmc_as_float(base);
    for (uint64_t i = 0; i < count; i++) result *= b;
    if (negative) result = (result == 0.0) ? 0.0 : (1.0 / result);
    return elmc_new_float_take(result);
  }

  int64_t b = elmc_as_int(base);
  for (uint64_t i = 0; i < count; i++) result *= (double)b;
  if (negative) {
    result = (result == 0.0) ? 0.0 : (1.0 / result);
    return elmc_new_float_take(result);
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, (int64_t)result) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_xor(ElmcValue *a, ElmcValue *b) {
  int ba = elmc_as_int(a) != 0;
  int bb = elmc_as_int(b) != 0;
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, ba != bb ? 1 : 0);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_basics_compare(ElmcValue *a, ElmcValue *b) {
  /* Returns -1, 0, or 1 as an int for LT, EQ, GT */
  if (a && b && (a->tag == ELMC_TAG_FLOAT || b->tag == ELMC_TAG_FLOAT)) {
    double fa = elmc_as_float(a);
    double fb = elmc_as_float(b);
    if (fa < fb) {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, -1) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
    if (fa > fb) {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, 1) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
    return elmc_int_zero();
  }
  if (a && b && a->tag == ELMC_TAG_STRING && b->tag == ELMC_TAG_STRING) {
    const char *sa = (const char *)a->payload;
    const char *sb = (const char *)b->payload;
    int cmp = strcmp(sa ? sa : "", sb ? sb : "");
    if (cmp < 0) {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, -1) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
    if (cmp > 0) {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, 1) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
    return elmc_int_zero();
  }
  elmc_int_t ia = elmc_as_int(a);
  elmc_int_t ib = elmc_as_int(b);
  if (ia < ib) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, -1) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  if (ia > ib) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, 1) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  return elmc_int_zero();
}

/* ================================================================
   Standard Library – Char (extended)
   ================================================================ */

ElmcValue *elmc_char_is_upper(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, c >= 'A' && c <= 'Z');
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_is_lower(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, c >= 'a' && c <= 'z');
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_is_alpha(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'));
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_is_alpha_num(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9'));
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_is_digit(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, c >= '0' && c <= '9');
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_is_oct_digit(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, c >= '0' && c <= '7');
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_is_hex_digit(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'));
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_to_upper(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  if (c >= 'a' && c <= 'z') c -= 32;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, c) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_char_to_lower(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  if (c >= 'A' && c <= 'Z') c += 32;
  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, c) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

/* ================================================================
   Standard Library – Dict (extended)
   ================================================================ */

RC elmc_dict_remove(ElmcValue **out, ElmcValue *key, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      int skip = 0;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        if (pair->first && elmc_dict_keys_equal(pair->first, key)) skip = 1;
      }
      if (!skip) {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

ElmcValue *elmc_dict_is_empty(ElmcValue *dict) {
  if (!dict || dict->tag != ELMC_TAG_LIST) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 1);
    return _elmc_rc_out;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, dict->payload == NULL);
      return _elmc_rc_out;
  }
}

RC elmc_dict_keys(ElmcValue **out, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        next = NULL;
        rc = elmc_list_cons(&next, pair->first, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_dict_values(ElmcValue **out, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        next = NULL;
        rc = elmc_list_cons(&next, pair->second, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

ElmcValue *elmc_dict_to_list(ElmcValue *dict) {
  /* Dict is already stored as a list of tuples */
  if (!dict) return elmc_list_nil();
  return elmc_retain(dict);
}

RC elmc_dict_map(ElmcValue **out, ElmcValue *f, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *mapped = NULL;
  ElmcValue *new_pair = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        ElmcValue *args[2] = { pair->first, pair->second };
        mapped = NULL;
        rc = elmc_closure_call_rc(&mapped, f, args, 2);
        CHECK_RC(rc);
        new_pair = NULL;
        rc = elmc_tuple2(&new_pair, pair->first, mapped);
        CHECK_RC(rc);
        elmc_release(mapped);
        mapped = NULL;
        next = NULL;
        rc = elmc_list_cons(&next, new_pair, rev);
        CHECK_RC(rc);
        elmc_release(new_pair);
        new_pair = NULL;
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(mapped);
  elmc_release(new_pair);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_dict_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        ElmcValue *args[3] = { pair->first, pair->second, result };
        next = NULL;
        rc = elmc_closure_call_rc(&next, f, args, 3);
        CHECK_RC(rc);
        elmc_release(result);
        result = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, result);
    CHECK_RC(rc);
    result = NULL;
  CATCH_END;
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_dict_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *reversed = NULL;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *next = NULL;
  CATCH_BEGIN
    rc = elmc_list_reverse_into(&reversed, dict);
    CHECK_RC(rc);
    ElmcValue *cursor = reversed;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        ElmcValue *args[3] = { pair->first, pair->second, result };
        next = NULL;
        rc = elmc_closure_call_rc(&next, f, args, 3);
        CHECK_RC(rc);
        elmc_release(result);
        result = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, result);
    CHECK_RC(rc);
    result = NULL;
  CATCH_END;
  elmc_release(reversed);
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_dict_filter(ElmcValue **out, ElmcValue *f, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *keep = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        ElmcValue *args[2] = { pair->first, pair->second };
        keep = NULL;
        rc = elmc_closure_call_rc(&keep, f, args, 2);
        CHECK_RC(rc);
        if (elmc_as_int(keep)) {
          next = NULL;
          rc = elmc_list_cons(&next, node->head, rev);
          CHECK_RC(rc);
          elmc_release(rev);
          rev = next;
          next = NULL;
        }
        elmc_release(keep);
        keep = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(keep);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_dict_partition(ElmcValue **out, ElmcValue *f, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev_yes = elmc_list_nil();
  ElmcValue *rev_no = elmc_list_nil();
  ElmcValue *keep = NULL;
  ElmcValue *next = NULL;
  ElmcValue *yes = NULL;
  ElmcValue *no = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        ElmcValue *args[2] = { pair->first, pair->second };
        keep = NULL;
        rc = elmc_closure_call_rc(&keep, f, args, 2);
        CHECK_RC(rc);
        if (elmc_as_int(keep)) {
          next = NULL;
          rc = elmc_list_cons(&next, node->head, rev_yes);
          CHECK_RC(rc);
          elmc_release(rev_yes);
          rev_yes = next;
          next = NULL;
        } else {
          next = NULL;
          rc = elmc_list_cons(&next, node->head, rev_no);
          CHECK_RC(rc);
          elmc_release(rev_no);
          rev_no = next;
          next = NULL;
        }
        elmc_release(keep);
        keep = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(&yes, &rev_yes);
    CHECK_RC(rc);
    rc = elmc_list_reverse_transfer(&no, &rev_no);
    CHECK_RC(rc);
    rc = elmc_tuple2(out, yes, no);
    CHECK_RC(rc);
    elmc_release(yes);
    elmc_release(no);
    yes = NULL;
    no = NULL;
  CATCH_END;
  elmc_release(keep);
  elmc_release(next);
  elmc_release(rev_yes);
  elmc_release(rev_no);
  elmc_release(yes);
  elmc_release(no);
  return rc;
}

RC elmc_dict_union(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(b);
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = a;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        next = NULL;
        rc = elmc_dict_insert(&next, pair->first, pair->second, result);
        CHECK_RC(rc);
        elmc_release(result);
        result = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, result);
    CHECK_RC(rc);
    result = NULL;
  CATCH_END;
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_dict_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = a;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        ElmcValue *found = elmc_dict_member(pair->first, b);
        if (elmc_as_int(found)) {
          next = NULL;
          rc = elmc_list_cons(&next, node->head, rev);
          CHECK_RC(rc);
          elmc_release(rev);
          rev = next;
          next = NULL;
        }
        elmc_release(found);
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_dict_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = a;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (node->head && node->head->tag == ELMC_TAG_TUPLE2 && node->head->payload != NULL) {
        ElmcTuple2 *pair = (ElmcTuple2 *)node->head->payload;
        ElmcValue *found = elmc_dict_member(pair->first, b);
        if (!elmc_as_int(found)) {
          next = NULL;
          rc = elmc_list_cons(&next, node->head, rev);
          CHECK_RC(rc);
          elmc_release(rev);
          rev = next;
          next = NULL;
        }
        elmc_release(found);
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

static ElmcValue *elmc_dict_pair_key(ElmcValue *pair) {
  if (!pair || pair->tag != ELMC_TAG_TUPLE2 || !pair->payload) return NULL;
  return ((ElmcTuple2 *)pair->payload)->first;
}

static ElmcValue *elmc_dict_pair_value(ElmcValue *pair) {
  if (!pair || pair->tag != ELMC_TAG_TUPLE2 || !pair->payload) return NULL;
  return ((ElmcTuple2 *)pair->payload)->second;
}

static int elmc_dict_key_cmp(ElmcValue *left_key, ElmcValue *right_key) {
  ElmcValue *order = elmc_basics_compare(left_key, right_key);
  int cmp = (int)elmc_as_int(order);
  elmc_release(order);
  return cmp;
}

static RC elmc_dict_sort_by_key(ElmcValue **out, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *sorted = elmc_list_nil();
  ElmcValue *rev_before = elmc_list_nil();
  ElmcValue *rebuilt = NULL;
  ElmcValue *tmp = NULL;
  ElmcValue *next_rb = NULL;
  ElmcValue *new_tail = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = dict;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *key = elmc_dict_pair_key(node->head);
      rev_before = elmc_list_nil();
      ElmcValue *rest = sorted;
      int inserted = 0;
      while (rest && rest->tag == ELMC_TAG_LIST && rest->payload != NULL) {
        ElmcCons *sn = (ElmcCons *)rest->payload;
        ElmcValue *rest_key = elmc_dict_pair_key(sn->head);
        if (!inserted && key && rest_key && elmc_dict_key_cmp(key, rest_key) <= 0) {
          rebuilt = NULL;
          rc = elmc_list_cons(&rebuilt, node->head, rest);
          CHECK_RC(rc);
          ElmcValue *rb_cursor = rev_before;
          while (rb_cursor && rb_cursor->tag == ELMC_TAG_LIST && rb_cursor->payload != NULL) {
            ElmcCons *rbn = (ElmcCons *)rb_cursor->payload;
            tmp = NULL;
            rc = elmc_list_cons(&tmp, rbn->head, rebuilt);
            CHECK_RC(rc);
            elmc_release(rebuilt);
            rebuilt = tmp;
            tmp = NULL;
            rb_cursor = rbn->tail;
          }
          elmc_release(rev_before);
          rev_before = elmc_list_nil();
          elmc_release(sorted);
          sorted = rebuilt;
          rebuilt = NULL;
          inserted = 1;
          break;
        }
        next_rb = NULL;
        rc = elmc_list_cons(&next_rb, sn->head, rev_before);
        CHECK_RC(rc);
        elmc_release(rev_before);
        rev_before = next_rb;
        next_rb = NULL;
        rest = sn->tail;
      }
      if (!inserted) {
        new_tail = NULL;
        rc = elmc_list_cons(&new_tail, node->head, elmc_list_nil());
        CHECK_RC(rc);
        rebuilt = new_tail;
        new_tail = NULL;
        ElmcValue *rb_cursor = rev_before;
        while (rb_cursor && rb_cursor->tag == ELMC_TAG_LIST && rb_cursor->payload != NULL) {
          ElmcCons *rbn = (ElmcCons *)rb_cursor->payload;
          tmp = NULL;
          rc = elmc_list_cons(&tmp, rbn->head, rebuilt);
          CHECK_RC(rc);
          elmc_release(rebuilt);
          rebuilt = tmp;
          tmp = NULL;
          rb_cursor = rbn->tail;
        }
        elmc_release(rev_before);
        rev_before = elmc_list_nil();
        elmc_release(sorted);
        sorted = rebuilt;
        rebuilt = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, sorted);
    CHECK_RC(rc);
    sorted = NULL;
  CATCH_END;
  elmc_release(rev_before);
  elmc_release(rebuilt);
  elmc_release(tmp);
  elmc_release(next_rb);
  elmc_release(new_tail);
  elmc_release(sorted);
  return rc;
}

RC elmc_dict_merge(ElmcValue **out, ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b, ElmcValue *result) {
  RC rc = RC_SUCCESS;
  ElmcValue *left = NULL;
  ElmcValue *right = NULL;
  ElmcValue *acc = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!a) a = elmc_list_nil();
    if (!b) b = elmc_list_nil();
    if (!result) result = elmc_list_nil();
    rc = elmc_dict_sort_by_key(&left, a);
    CHECK_RC(rc);
    rc = elmc_dict_sort_by_key(&right, b);
    CHECK_RC(rc);
    acc = elmc_retain(result);
    ElmcValue *l_cursor = left;
    ElmcValue *r_cursor = right;
    while (l_cursor && l_cursor->tag == ELMC_TAG_LIST && l_cursor->payload != NULL &&
           r_cursor && r_cursor->tag == ELMC_TAG_LIST && r_cursor->payload != NULL) {
      ElmcCons *l_node = (ElmcCons *)l_cursor->payload;
      ElmcCons *r_node = (ElmcCons *)r_cursor->payload;
      ElmcValue *l_key = elmc_dict_pair_key(l_node->head);
      ElmcValue *r_key = elmc_dict_pair_key(r_node->head);
      int cmp = (l_key && r_key) ? elmc_dict_key_cmp(l_key, r_key) : 0;
      if (cmp < 0) {
        ElmcValue *l_val = elmc_dict_pair_value(l_node->head);
        ElmcValue *args[3] = { l_key, l_val, acc };
        next = NULL;
        rc = elmc_closure_call_rc(&next, lf, args, 3);
        CHECK_RC(rc);
        elmc_release(acc);
        acc = next;
        next = NULL;
        l_cursor = l_node->tail;
      } else if (cmp > 0) {
        ElmcValue *r_val = elmc_dict_pair_value(r_node->head);
        ElmcValue *args[3] = { r_key, r_val, acc };
        next = NULL;
        rc = elmc_closure_call_rc(&next, rf, args, 3);
        CHECK_RC(rc);
        elmc_release(acc);
        acc = next;
        next = NULL;
        r_cursor = r_node->tail;
      } else {
        ElmcValue *l_val = elmc_dict_pair_value(l_node->head);
        ElmcValue *r_val = elmc_dict_pair_value(r_node->head);
        ElmcValue *args[4] = { l_key, l_val, r_val, acc };
        next = NULL;
        rc = elmc_closure_call_rc(&next, bf, args, 4);
        CHECK_RC(rc);
        elmc_release(acc);
        acc = next;
        next = NULL;
        l_cursor = l_node->tail;
        r_cursor = r_node->tail;
      }
    }
    while (l_cursor && l_cursor->tag == ELMC_TAG_LIST && l_cursor->payload != NULL) {
      ElmcCons *l_node = (ElmcCons *)l_cursor->payload;
      ElmcValue *l_key = elmc_dict_pair_key(l_node->head);
      ElmcValue *l_val = elmc_dict_pair_value(l_node->head);
      ElmcValue *args[3] = { l_key, l_val, acc };
      next = NULL;
      rc = elmc_closure_call_rc(&next, lf, args, 3);
      CHECK_RC(rc);
      elmc_release(acc);
      acc = next;
      next = NULL;
      l_cursor = l_node->tail;
    }
    while (r_cursor && r_cursor->tag == ELMC_TAG_LIST && r_cursor->payload != NULL) {
      ElmcCons *r_node = (ElmcCons *)r_cursor->payload;
      ElmcValue *r_key = elmc_dict_pair_key(r_node->head);
      ElmcValue *r_val = elmc_dict_pair_value(r_node->head);
      ElmcValue *args[3] = { r_key, r_val, acc };
      next = NULL;
      rc = elmc_closure_call_rc(&next, rf, args, 3);
      CHECK_RC(rc);
      elmc_release(acc);
      acc = next;
      next = NULL;
      r_cursor = r_node->tail;
    }
    rc = elmc_rc_assign_value(out, acc);
    CHECK_RC(rc);
    acc = NULL;
  CATCH_END;
  elmc_release(left);
  elmc_release(right);
  elmc_release(next);
  elmc_release(acc);
  return rc;
}

RC elmc_dict_update(ElmcValue **out, ElmcValue *key, ElmcValue *f, ElmcValue *dict) {
  RC rc = RC_SUCCESS;
  ElmcValue *old_val = NULL;
  ElmcValue *new_maybe = NULL;
  CATCH_BEGIN
    old_val = elmc_dict_get_take(key, dict);
    ElmcValue *args[1] = { old_val };
    rc = elmc_closure_call_rc(&new_maybe, f, args, 1);
    CHECK_RC(rc);
    if (new_maybe && new_maybe->tag == ELMC_TAG_MAYBE && new_maybe->payload != NULL) {
      ElmcMaybe *m = (ElmcMaybe *)new_maybe->payload;
      if (m->is_just && m->value) {
        rc = elmc_dict_insert(out, key, m->value, dict);
        CHECK_RC(rc);
      } else {
        rc = elmc_dict_remove(out, key, dict);
        CHECK_RC(rc);
      }
    } else {
      rc = elmc_dict_remove(out, key, dict);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(old_val);
  elmc_release(new_maybe);
  return rc;
}

ElmcValue *elmc_dict_singleton(ElmcValue *key, ElmcValue *value) {
  ElmcValue *empty = elmc_list_nil();
  ElmcValue *out = elmc_dict_insert_take(key, value, empty);
  elmc_release(empty);
  return out;
}

/* ================================================================
   Standard Library – Set (extended)
   ================================================================ */

ElmcValue *elmc_set_singleton(ElmcValue *value) {
  ElmcValue *empty = elmc_list_nil();
  ElmcValue *out = elmc_set_insert_take(value, empty);
  elmc_release(empty);
  return out;
}

RC elmc_set_remove(ElmcValue **out, ElmcValue *value, ElmcValue *set) {
  RC rc = RC_SUCCESS;
  int64_t wanted = elmc_as_int(value);
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = set;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (elmc_as_int(node->head) != wanted) {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

ElmcValue *elmc_set_is_empty(ElmcValue *set) {
  if (!set || set->tag != ELMC_TAG_LIST) {
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, 1);
    return _elmc_rc_out;
  }
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, set->payload == NULL);
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_set_to_list(ElmcValue *set) {
  if (!set) return elmc_list_nil();
  return elmc_retain(set);
}

RC elmc_set_union(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(b);
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = a;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      next = NULL;
      rc = elmc_set_insert(&next, node->head, result);
      CHECK_RC(rc);
      elmc_release(result);
      result = next;
      next = NULL;
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, result);
    CHECK_RC(rc);
    result = NULL;
  CATCH_END;
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_set_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = a;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *found = elmc_set_member(node->head, b);
      if (elmc_as_int(found)) {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      elmc_release(found);
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_set_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = a;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *found = elmc_set_member(node->head, b);
      if (!elmc_as_int(found)) {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      elmc_release(found);
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_set_map(ElmcValue **out, ElmcValue *f, ElmcValue *set) {
  RC rc = RC_SUCCESS;
  ElmcValue *acc = elmc_list_nil();
  ElmcValue *mapped = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = set;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      mapped = NULL;
      rc = elmc_closure_call_rc(&mapped, f, args, 1);
      CHECK_RC(rc);
      next = NULL;
      rc = elmc_set_insert(&next, mapped, acc);
      CHECK_RC(rc);
      elmc_release(mapped);
      mapped = NULL;
      elmc_release(acc);
      acc = next;
      next = NULL;
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, acc);
    CHECK_RC(rc);
    acc = NULL;
  CATCH_END;
  elmc_release(mapped);
  elmc_release(next);
  elmc_release(acc);
  return rc;
}

RC elmc_set_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = set;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[2] = { node->head, result };
      next = NULL;
      rc = elmc_closure_call_rc(&next, f, args, 2);
      CHECK_RC(rc);
      elmc_release(result);
      result = next;
      next = NULL;
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, result);
    CHECK_RC(rc);
    result = NULL;
  CATCH_END;
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_set_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
  RC rc = RC_SUCCESS;
  ElmcValue *reversed = NULL;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *next = NULL;
  CATCH_BEGIN
    rc = elmc_list_reverse_into(&reversed, set);
    CHECK_RC(rc);
    ElmcValue *cursor = reversed;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[2] = { node->head, result };
      next = NULL;
      rc = elmc_closure_call_rc(&next, f, args, 2);
      CHECK_RC(rc);
      elmc_release(result);
      result = next;
      next = NULL;
      cursor = node->tail;
    }
    rc = elmc_rc_assign_value(out, result);
    CHECK_RC(rc);
    result = NULL;
  CATCH_END;
  elmc_release(reversed);
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_set_filter(ElmcValue **out, ElmcValue *f, ElmcValue *set) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *keep = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = set;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      keep = NULL;
      rc = elmc_closure_call_rc(&keep, f, args, 1);
      CHECK_RC(rc);
      if (elmc_as_int(keep)) {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      elmc_release(keep);
      keep = NULL;
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(out, &rev);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(keep);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_set_partition(ElmcValue **out, ElmcValue *f, ElmcValue *set) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev_yes = elmc_list_nil();
  ElmcValue *rev_no = elmc_list_nil();
  ElmcValue *keep = NULL;
  ElmcValue *next = NULL;
  ElmcValue *yes = NULL;
  ElmcValue *no = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = set;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      ElmcValue *args[1] = { node->head };
      keep = NULL;
      rc = elmc_closure_call_rc(&keep, f, args, 1);
      CHECK_RC(rc);
      if (elmc_as_int(keep)) {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev_yes);
        CHECK_RC(rc);
        elmc_release(rev_yes);
        rev_yes = next;
        next = NULL;
      } else {
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev_no);
        CHECK_RC(rc);
        elmc_release(rev_no);
        rev_no = next;
        next = NULL;
      }
      elmc_release(keep);
      keep = NULL;
      cursor = node->tail;
    }
    rc = elmc_list_reverse_transfer(&yes, &rev_yes);
    CHECK_RC(rc);
    rc = elmc_list_reverse_transfer(&no, &rev_no);
    CHECK_RC(rc);
    rc = elmc_tuple2(out, yes, no);
    CHECK_RC(rc);
    elmc_release(yes);
    elmc_release(no);
    yes = NULL;
    no = NULL;
  CATCH_END;
  elmc_release(keep);
  elmc_release(next);
  elmc_release(rev_yes);
  elmc_release(rev_no);
  elmc_release(yes);
  elmc_release(no);
  return rc;
}

/* ================================================================
   Standard Library – Array (extended)
   ================================================================ */

ElmcValue *elmc_array_initialize(ElmcValue *n, ElmcValue *f) {
  int64_t count = elmc_as_int(n);
  ElmcValue *out = elmc_list_nil();
  for (int64_t i = count - 1; i >= 0; i--) {
    ElmcValue *idx = NULL;
    if (elmc_new_int(&idx, i) != RC_SUCCESS) idx = NULL;
    ElmcValue *args[1] = { idx };
    ElmcValue *val = NULL;
    if (elmc_closure_call_rc(&val, f, args, 1) != RC_SUCCESS) {
      elmc_release(val);
      elmc_release(idx);
      elmc_release(out);
      return elmc_int_zero();
    }
    ElmcValue *next = NULL;
    if (elmc_list_cons(&next, val, out) != RC_SUCCESS) next = NULL;
    elmc_release(idx);
    elmc_release(val);
    elmc_release(out);
    out = next;
  }
  return out;
}

ElmcValue *elmc_array_repeat(ElmcValue *n, ElmcValue *value) {
  return elmc_list_repeat_take(n, value);
}

ElmcValue *elmc_array_is_empty(ElmcValue *array) {
  return elmc_list_is_empty(array);
}

ElmcValue *elmc_array_to_list(ElmcValue *array) {
  if (!array) return elmc_list_nil();
  return elmc_retain(array);
}

ElmcValue *elmc_array_to_indexed_list(ElmcValue *array) {
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *cursor = array;
  int64_t idx = 0;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *index_val = NULL;
    if (elmc_new_int(&index_val, idx) != RC_SUCCESS) index_val = NULL;
    ElmcValue *pair = NULL;
    if (elmc_tuple2(&pair, index_val, node->head) != RC_SUCCESS) pair = NULL;
    ElmcValue *next = NULL;
    if (elmc_list_cons(&next, pair, rev) != RC_SUCCESS) next = NULL;
    elmc_release(index_val);
    elmc_release(pair);
    elmc_release(rev);
    rev = next;
    idx++;
    cursor = node->tail;
  }
  ElmcValue *out = elmc_list_reverse_copy(rev);
  elmc_release(rev);
  return out;
}

ElmcValue *elmc_array_map(ElmcValue *f, ElmcValue *array) {
  return elmc_list_map_take(f, array);
}

ElmcValue *elmc_array_indexed_map(ElmcValue *f, ElmcValue *array) {
  return elmc_list_indexed_map_take(f, array);
}

ElmcValue *elmc_array_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *array) {
  return elmc_list_foldl_take(f, acc, array);
}

ElmcValue *elmc_array_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *array) {
  return elmc_list_foldr_take(f, acc, array);
}

ElmcValue *elmc_array_filter(ElmcValue *f, ElmcValue *array) {
  return elmc_list_filter_take(f, array);
}

ElmcValue *elmc_array_append(ElmcValue *a, ElmcValue *b) {
  return elmc_list_append_take(a, b);
}

ElmcValue *elmc_array_slice(ElmcValue *start, ElmcValue *end_idx, ElmcValue *array) {
  int64_t len_val = 0;
  ElmcValue *cursor = array;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    len_val++;
    cursor = ((ElmcCons *)cursor->payload)->tail;
  }
  int64_t st = elmc_as_int(start);
  int64_t en = elmc_as_int(end_idx);
  if (st < 0) st = len_val + st;
  if (en < 0) en = len_val + en;
  if (st < 0) st = 0;
  if (en < 0) en = 0;
  if (st > len_val) st = len_val;
  if (en > len_val) en = len_val;
  if (en <= st) return elmc_list_nil();
  ElmcValue *rev = elmc_list_nil();
  cursor = array;
  int64_t idx = 0;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (idx >= st && idx < en) {
      ElmcValue *next = NULL;
      if (elmc_list_cons(&next, node->head, rev) != RC_SUCCESS) next = NULL;
      elmc_release(rev);
      rev = next;
    }
    idx++;
    if (idx >= en) break;
    cursor = node->tail;
  }
  ElmcValue *out = elmc_list_reverse_copy(rev);
  elmc_release(rev);
  return out;
}

/* ================================================================
   Standard Library – Json.Decode
   ================================================================ */

#define ELMC_JSON_DECODER_STRING 1
#define ELMC_JSON_DECODER_INT 2
#define ELMC_JSON_DECODER_FLOAT 3
#define ELMC_JSON_DECODER_BOOL 4
#define ELMC_JSON_DECODER_VALUE 5
#define ELMC_JSON_DECODER_FIELD 102
#define ELMC_JSON_DECODER_INDEX 103
#define ELMC_JSON_DECODER_LIST 104
#define ELMC_JSON_DECODER_ARRAY 105
#define ELMC_JSON_DECODER_NULL 106
#define ELMC_JSON_DECODER_MAYBE 107
#define ELMC_JSON_DECODER_ONE_OF 108
#define ELMC_JSON_DECODER_SUCCEED 109
#define ELMC_JSON_DECODER_FAIL 110
#define ELMC_JSON_DECODER_MAP 111
#define ELMC_JSON_DECODER_MAP2 112
#define ELMC_JSON_DECODER_AND_THEN 113
#define ELMC_JSON_DECODER_MAP7 114
#define ELMC_JSON_DECODER_KEY_VALUE_PAIRS 115

#if defined(__GNUC__) || defined(__clang__)
#define ELMC_MAYBE_UNUSED __attribute__((unused))
#else
#define ELMC_MAYBE_UNUSED
#endif

static ELMC_MAYBE_UNUSED int64_t elmc_json_decoder_tag(ElmcValue *decoder) {
  if (!decoder) return 0;
  if (decoder->tag == ELMC_TAG_INT || decoder->tag == ELMC_TAG_BOOL) {
    return elmc_as_int(decoder);
  }
  if (decoder->tag == ELMC_TAG_TUPLE2 && decoder->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)decoder->payload;
    if (tuple->first && (tuple->first->tag == ELMC_TAG_INT || tuple->first->tag == ELMC_TAG_BOOL)) {
      return elmc_as_int(tuple->first);
    }
  }
  return 0;
}

static ELMC_MAYBE_UNUSED ElmcValue *elmc_json_decoder_payload(ElmcValue *decoder) {
  if (!decoder || decoder->tag != ELMC_TAG_TUPLE2 || decoder->payload == NULL) return NULL;
  ElmcTuple2 *tuple = (ElmcTuple2 *)decoder->payload;
  return tuple->second;
}

static ElmcValue *elmc_json_decoder_wrap(int64_t tag, ElmcValue *payload) {
  ElmcValue *tag_value = NULL;
  if (elmc_new_int(&tag_value, tag) != RC_SUCCESS) tag_value = NULL;
  if (!tag_value) return NULL;
  ElmcValue *wrapped = NULL;
  if (elmc_tuple2(&wrapped, tag_value, payload ? payload : elmc_list_nil()) != RC_SUCCESS) wrapped = NULL;
  elmc_release(tag_value);
  return wrapped;
}

typedef enum {
  ELMC_JSON_NULL = 0,
  ELMC_JSON_BOOL = 1,
  ELMC_JSON_INT = 2,
  ELMC_JSON_FLOAT = 3,
  ELMC_JSON_STRING = 4,
  ELMC_JSON_ARRAY = 5,
  ELMC_JSON_OBJECT = 6
} ElmcJsonKind;

typedef struct ElmcJsonValue {
  ElmcJsonKind kind;
  int bool_value;
  int64_t int_value;
  double float_value;
  char *string_value;
  char *key;
  struct ElmcJsonValue *child;
  struct ElmcJsonValue *next;
} ElmcJsonValue;

typedef struct {
  char *data;
  size_t len;
  size_t cap;
} ElmcJsonBuffer;

typedef struct {
  const char *input;
  const char *at;
  const char *error;
} ElmcJsonParser;

static int elmc_json_is_ws(char c) {
  return c == ' ' || c == '\n' || c == '\r' || c == '\t';
}

static void elmc_json_skip_ws(ElmcJsonParser *parser) {
  while (parser && parser->at && elmc_json_is_ws(*parser->at)) parser->at++;
}

static void elmc_json_buf_init(ElmcJsonBuffer *buf) {
  buf->data = NULL;
  buf->len = 0;
  buf->cap = 0;
}

static void elmc_json_buf_free(ElmcJsonBuffer *buf) {
  if (buf && buf->data) free(buf->data);
  if (buf) {
    buf->data = NULL;
    buf->len = 0;
    buf->cap = 0;
  }
}

static int elmc_json_buf_reserve(ElmcJsonBuffer *buf, size_t needed) {
  if (needed <= buf->cap) return 1;
  size_t next = buf->cap ? buf->cap * 2 : 32;
  while (next < needed) next *= 2;
  char *data = (char *)elmc_realloc(buf->data, next, "json_buf");
  if (!data) return 0;
  buf->data = data;
  buf->cap = next;
  return 1;
}

static int elmc_json_buf_append_char(ElmcJsonBuffer *buf, char c) {
  if (!elmc_json_buf_reserve(buf, buf->len + 2)) return 0;
  buf->data[buf->len++] = c;
  buf->data[buf->len] = '\0';
  return 1;
}

static int elmc_json_buf_append_bytes(ElmcJsonBuffer *buf, const char *data, size_t len) {
  if (!elmc_json_buf_reserve(buf, buf->len + len + 1)) return 0;
  if (len > 0) memcpy(buf->data + buf->len, data, len);
  buf->len += len;
  buf->data[buf->len] = '\0';
  return 1;
}

static int elmc_json_buf_append_cstr(ElmcJsonBuffer *buf, const char *data) {
  return elmc_json_buf_append_bytes(buf, data ? data : "", data ? strlen(data) : 0);
}

static ElmcValue *elmc_json_buf_to_string(ElmcJsonBuffer *buf) {
  ElmcValue *out = NULL;
  if (elmc_new_string(&out, buf->data ? buf->data : "") != RC_SUCCESS) out = NULL;
  elmc_json_buf_free(buf);
  return out;
}

static ElmcJsonValue *elmc_json_new_value(ElmcJsonKind kind) {
  ElmcJsonValue *value = (ElmcJsonValue *)elmc_malloc(sizeof(ElmcJsonValue), "json_value");
  if (!value) return NULL;
  value->kind = kind;
  value->bool_value = 0;
  value->int_value = 0;
  value->float_value = 0.0;
  value->string_value = NULL;
  value->key = NULL;
  value->child = NULL;
  value->next = NULL;
  return value;
}

static void elmc_json_free_value(ElmcJsonValue *value) {
  while (value) {
    ElmcJsonValue *next = value->next;
    if (value->child) elmc_json_free_value(value->child);
    if (value->string_value) free(value->string_value);
    if (value->key) free(value->key);
    free(value);
    value = next;
  }
}

static int elmc_json_hex(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

static int elmc_json_append_utf8(ElmcJsonBuffer *buf, unsigned code) {
  if (code <= 0x7f) {
    return elmc_json_buf_append_char(buf, (char)code);
  } else if (code <= 0x7ff) {
    return elmc_json_buf_append_char(buf, (char)(0xc0 | (code >> 6))) &&
           elmc_json_buf_append_char(buf, (char)(0x80 | (code & 0x3f)));
  } else {
    return elmc_json_buf_append_char(buf, (char)(0xe0 | (code >> 12))) &&
           elmc_json_buf_append_char(buf, (char)(0x80 | ((code >> 6) & 0x3f))) &&
           elmc_json_buf_append_char(buf, (char)(0x80 | (code & 0x3f)));
  }
}

static char *elmc_json_parse_string_raw(ElmcJsonParser *parser) {
  if (!parser || *parser->at != '"') return NULL;
  parser->at++;
  ElmcJsonBuffer buf;
  elmc_json_buf_init(&buf);
  while (*parser->at && *parser->at != '"') {
    unsigned char c = (unsigned char)*parser->at++;
    if (c < 0x20) {
      parser->error = "Invalid string";
      elmc_json_buf_free(&buf);
      return NULL;
    }
    if (c != '\\') {
      if (!elmc_json_buf_append_char(&buf, (char)c)) {
        parser->error = "Out of memory";
        return NULL;
      }
      continue;
    }
    char esc = *parser->at++;
    switch (esc) {
      case '"': if (!elmc_json_buf_append_char(&buf, '"')) return NULL; break;
      case '\\': if (!elmc_json_buf_append_char(&buf, '\\')) return NULL; break;
      case '/': if (!elmc_json_buf_append_char(&buf, '/')) return NULL; break;
      case 'b': if (!elmc_json_buf_append_char(&buf, '\b')) return NULL; break;
      case 'f': if (!elmc_json_buf_append_char(&buf, '\f')) return NULL; break;
      case 'n': if (!elmc_json_buf_append_char(&buf, '\n')) return NULL; break;
      case 'r': if (!elmc_json_buf_append_char(&buf, '\r')) return NULL; break;
      case 't': if (!elmc_json_buf_append_char(&buf, '\t')) return NULL; break;
      case 'u': {
        unsigned code = 0;
        for (int i = 0; i < 4; i++) {
          int digit = elmc_json_hex(*parser->at++);
          if (digit < 0) {
            parser->error = "Invalid unicode escape";
            elmc_json_buf_free(&buf);
            return NULL;
          }
          code = (code << 4) | (unsigned)digit;
        }
        if (code >= 0xd800 && code <= 0xdfff) {
          parser->error = "Unsupported unicode surrogate";
          elmc_json_buf_free(&buf);
          return NULL;
        }
        if (!elmc_json_append_utf8(&buf, code)) return NULL;
        break;
      }
      default:
        parser->error = "Invalid string escape";
        elmc_json_buf_free(&buf);
        return NULL;
    }
  }
  if (*parser->at != '"') {
    parser->error = "Unterminated string";
    elmc_json_buf_free(&buf);
    return NULL;
  }
  parser->at++;
  if (!elmc_json_buf_append_char(&buf, '\0')) return NULL;
  buf.len -= 1;
  return buf.data;
}

static ElmcJsonValue *elmc_json_parse_value(ElmcJsonParser *parser, int depth);

static ElmcJsonValue *elmc_json_parse_number(ElmcJsonParser *parser) {
  const char *p = parser->at;
  int sign = 1;
  if (*p == '-') { sign = -1; p++; }
  if (*p < '0' || *p > '9') {
    parser->error = "Invalid number";
    return NULL;
  }
  int64_t int_part = 0;
  double number = 0.0;
  if (*p == '0') {
    p++;
    if (*p >= '0' && *p <= '9') {
      parser->error = "Invalid leading zero";
      return NULL;
    }
  } else {
    while (*p >= '0' && *p <= '9') {
      int digit = *p++ - '0';
      int_part = int_part * 10 + digit;
      number = number * 10.0 + (double)digit;
    }
  }
  int is_int = 1;
  if (*p == '.') {
    is_int = 0;
    p++;
    if (*p < '0' || *p > '9') {
      parser->error = "Invalid fraction";
      return NULL;
    }
    double place = 0.1;
    while (*p >= '0' && *p <= '9') {
      number += (double)(*p++ - '0') * place;
      place *= 0.1;
    }
  }
  if (*p == 'e' || *p == 'E') {
    is_int = 0;
    p++;
    int exp_sign = 1;
    if (*p == '-') { exp_sign = -1; p++; }
    else if (*p == '+') { p++; }
    if (*p < '0' || *p > '9') {
      parser->error = "Invalid exponent";
      return NULL;
    }
    int exp = 0;
    while (*p >= '0' && *p <= '9') {
      exp = exp * 10 + (*p++ - '0');
      if (exp > 308) exp = 308;
    }
    while (exp-- > 0) {
      if (exp_sign > 0) number *= 10.0;
      else number /= 10.0;
    }
  }
  parser->at = p;
  ElmcJsonValue *value = elmc_json_new_value(is_int ? ELMC_JSON_INT : ELMC_JSON_FLOAT);
  if (!value) {
    parser->error = "Out of memory";
    return NULL;
  }
  value->int_value = sign < 0 ? -int_part : int_part;
  value->float_value = (sign < 0 ? -number : number);
  return value;
}

static int elmc_json_match_literal(ElmcJsonParser *parser, const char *literal) {
  size_t len = strlen(literal);
  if (strncmp(parser->at, literal, len) != 0) return 0;
  parser->at += len;
  return 1;
}

static ElmcJsonValue *elmc_json_parse_array(ElmcJsonParser *parser, int depth) {
  parser->at++;
  ElmcJsonValue *array = elmc_json_new_value(ELMC_JSON_ARRAY);
  if (!array) return NULL;
  ElmcJsonValue **tail = &array->child;
  elmc_json_skip_ws(parser);
  if (*parser->at == ']') {
    parser->at++;
    return array;
  }
  while (*parser->at) {
    ElmcJsonValue *child = elmc_json_parse_value(parser, depth + 1);
    if (!child) {
      elmc_json_free_value(array);
      return NULL;
    }
    *tail = child;
    tail = &child->next;
    elmc_json_skip_ws(parser);
    if (*parser->at == ']') {
      parser->at++;
      return array;
    }
    if (*parser->at != ',') {
      parser->error = "Expected array separator";
      elmc_json_free_value(array);
      return NULL;
    }
    parser->at++;
    elmc_json_skip_ws(parser);
  }
  parser->error = "Unterminated array";
  elmc_json_free_value(array);
  return NULL;
}

static ElmcJsonValue *elmc_json_parse_object(ElmcJsonParser *parser, int depth) {
  parser->at++;
  ElmcJsonValue *object = elmc_json_new_value(ELMC_JSON_OBJECT);
  if (!object) return NULL;
  ElmcJsonValue **tail = &object->child;
  elmc_json_skip_ws(parser);
  if (*parser->at == '}') {
    parser->at++;
    return object;
  }
  while (*parser->at) {
    char *key = elmc_json_parse_string_raw(parser);
    if (!key) {
      elmc_json_free_value(object);
      return NULL;
    }
    elmc_json_skip_ws(parser);
    if (*parser->at != ':') {
      free(key);
      parser->error = "Expected object colon";
      elmc_json_free_value(object);
      return NULL;
    }
    parser->at++;
    ElmcJsonValue *child = elmc_json_parse_value(parser, depth + 1);
    if (!child) {
      free(key);
      elmc_json_free_value(object);
      return NULL;
    }
    child->key = key;
    *tail = child;
    tail = &child->next;
    elmc_json_skip_ws(parser);
    if (*parser->at == '}') {
      parser->at++;
      return object;
    }
    if (*parser->at != ',') {
      parser->error = "Expected object separator";
      elmc_json_free_value(object);
      return NULL;
    }
    parser->at++;
    elmc_json_skip_ws(parser);
  }
  parser->error = "Unterminated object";
  elmc_json_free_value(object);
  return NULL;
}

static ElmcJsonValue *elmc_json_parse_value(ElmcJsonParser *parser, int depth) {
  if (depth > 64) {
    parser->error = "JSON nesting too deep";
    return NULL;
  }
  elmc_json_skip_ws(parser);
  if (*parser->at == '"') {
    ElmcJsonValue *value = elmc_json_new_value(ELMC_JSON_STRING);
    if (!value) return NULL;
    value->string_value = elmc_json_parse_string_raw(parser);
    if (!value->string_value) {
      free(value);
      return NULL;
    }
    return value;
  }
  if (*parser->at == '{') return elmc_json_parse_object(parser, depth);
  if (*parser->at == '[') return elmc_json_parse_array(parser, depth);
  if (*parser->at == '-' || (*parser->at >= '0' && *parser->at <= '9')) return elmc_json_parse_number(parser);
  if (elmc_json_match_literal(parser, "true")) {
    ElmcJsonValue *value = elmc_json_new_value(ELMC_JSON_BOOL);
    if (value) value->bool_value = 1;
    return value;
  }
  if (elmc_json_match_literal(parser, "false")) return elmc_json_new_value(ELMC_JSON_BOOL);
  if (elmc_json_match_literal(parser, "null")) return elmc_json_new_value(ELMC_JSON_NULL);
  parser->error = "Invalid JSON";
  return NULL;
}

static ElmcJsonValue *elmc_json_parse_document(const char *raw, const char **error_out) {
  if (!raw) {
    if (error_out) *error_out = "Invalid JSON";
    return NULL;
  }
  ElmcJsonParser parser = { raw, raw, NULL };
  ElmcJsonValue *value = elmc_json_parse_value(&parser, 0);
  if (!value) {
    if (error_out) *error_out = parser.error ? parser.error : "Invalid JSON";
    return NULL;
  }
  elmc_json_skip_ws(&parser);
  if (*parser.at != '\0') {
    elmc_json_free_value(value);
    if (error_out) *error_out = "Trailing JSON input";
    return NULL;
  }
  return value;
}

static ElmcJsonValue *elmc_json_object_get(const ElmcJsonValue *object, const char *key) {
  if (!object || object->kind != ELMC_JSON_OBJECT || !key) return NULL;
  ElmcJsonValue *child = object->child;
  while (child) {
    if (child->key && strcmp(child->key, key) == 0) return child;
    child = child->next;
  }
  return NULL;
}

static ElmcJsonValue *elmc_json_array_get(const ElmcJsonValue *array, int index) {
  if (!array || array->kind != ELMC_JSON_ARRAY || index < 0) return NULL;
  ElmcJsonValue *child = array->child;
  int i = 0;
  while (child) {
    if (i == index) return child;
    i++;
    child = child->next;
  }
  return NULL;
}

static int elmc_json_encode_value_to_buffer(const ElmcJsonValue *value, ElmcJsonBuffer *buf);

static int elmc_json_encode_string_to_buffer(const char *raw, ElmcJsonBuffer *buf) {
  if (!elmc_json_buf_append_char(buf, '"')) return 0;
  const unsigned char *p = (const unsigned char *)(raw ? raw : "");
  while (*p) {
    unsigned char c = *p++;
    switch (c) {
      case '"': if (!elmc_json_buf_append_cstr(buf, "\\\"")) return 0; break;
      case '\\': if (!elmc_json_buf_append_cstr(buf, "\\\\")) return 0; break;
      case '\b': if (!elmc_json_buf_append_cstr(buf, "\\b")) return 0; break;
      case '\f': if (!elmc_json_buf_append_cstr(buf, "\\f")) return 0; break;
      case '\n': if (!elmc_json_buf_append_cstr(buf, "\\n")) return 0; break;
      case '\r': if (!elmc_json_buf_append_cstr(buf, "\\r")) return 0; break;
      case '\t': if (!elmc_json_buf_append_cstr(buf, "\\t")) return 0; break;
      default:
        if (c < 0x20) {
          char escape[7];
          snprintf(escape, sizeof(escape), "\\u%04x", c);
          if (!elmc_json_buf_append_cstr(buf, escape)) return 0;
        } else if (!elmc_json_buf_append_char(buf, (char)c)) {
          return 0;
        }
        break;
    }
  }
  return elmc_json_buf_append_char(buf, '"');
}

static int elmc_json_encode_value_to_buffer(const ElmcJsonValue *value, ElmcJsonBuffer *buf) {
  if (!value) return elmc_json_buf_append_cstr(buf, "null");
  char number[48];
  switch (value->kind) {
    case ELMC_JSON_NULL:
      return elmc_json_buf_append_cstr(buf, "null");
    case ELMC_JSON_BOOL:
      return elmc_json_buf_append_cstr(buf, value->bool_value ? "true" : "false");
    case ELMC_JSON_INT:
      snprintf(number, sizeof(number), "%lld", (long long)value->int_value);
      return elmc_json_buf_append_cstr(buf, number);
    case ELMC_JSON_FLOAT:
      snprintf(number, sizeof(number), "%.17g", value->float_value);
      return elmc_json_buf_append_cstr(buf, number);
    case ELMC_JSON_STRING:
      return elmc_json_encode_string_to_buffer(value->string_value, buf);
    case ELMC_JSON_ARRAY: {
      if (!elmc_json_buf_append_char(buf, '[')) return 0;
      ElmcJsonValue *child = value->child;
      int first = 1;
      while (child) {
        if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
        if (!elmc_json_encode_value_to_buffer(child, buf)) return 0;
        first = 0;
        child = child->next;
      }
      return elmc_json_buf_append_char(buf, ']');
    }
    case ELMC_JSON_OBJECT: {
      if (!elmc_json_buf_append_char(buf, '{')) return 0;
      ElmcJsonValue *child = value->child;
      int first = 1;
      while (child) {
        if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
        if (!elmc_json_encode_string_to_buffer(child->key, buf)) return 0;
        if (!elmc_json_buf_append_char(buf, ':')) return 0;
        if (!elmc_json_encode_value_to_buffer(child, buf)) return 0;
        first = 0;
        child = child->next;
      }
      return elmc_json_buf_append_char(buf, '}');
    }
    default:
      return elmc_json_buf_append_cstr(buf, "null");
  }
}

static ElmcValue *elmc_json_value_to_string(const ElmcJsonValue *value) {
  ElmcJsonBuffer buf;
  elmc_json_buf_init(&buf);
  if (!elmc_json_encode_value_to_buffer(value, &buf)) {
    elmc_json_buf_free(&buf);
    {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_string(&_elmc_rc_out, "null") != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
  }
  return elmc_json_buf_to_string(&buf);
}

static ElmcValue *elmc_json_decode_with_value(ElmcValue *decoder, const ElmcJsonValue *node, const char **error_out);

static ElmcValue *elmc_json_decode_map_with_value(ElmcValue *payload, const ElmcJsonValue *node, const char **error_out) {
  if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
    if (error_out) *error_out = "Invalid map decoder";
    return NULL;
  }
  ElmcTuple2 *tuple = (ElmcTuple2 *)payload->payload;
  ElmcValue *decoded = elmc_json_decode_with_value(tuple->second, node, error_out);
  if (!decoded) return NULL;
  ElmcValue *args[] = { decoded };
  ElmcValue *mapped = elmc_closure_call(tuple->first, args, 1);
  elmc_release(decoded);
  if (!mapped && error_out) *error_out = "Failed to map decoded value";
  return mapped;
}

static int elmc_json_is_decoder_value(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_TUPLE2 || value->payload == NULL) return 0;
  ElmcTuple2 *pair = (ElmcTuple2 *)value->payload;
  return pair->first != NULL &&
         (pair->first->tag == ELMC_TAG_INT || pair->first->tag == ELMC_TAG_BOOL);
}

static int elmc_json_decode_collect_decoders(ElmcValue *cursor, ElmcValue **decoders, int max_count) {
  int count = 0;

  while (cursor && count < max_count) {
    if (cursor->tag != ELMC_TAG_TUPLE2 || cursor->payload == NULL) break;

    ElmcTuple2 *pair = (ElmcTuple2 *)cursor->payload;

    if (!elmc_json_is_decoder_value(pair->first)) break;

    decoders[count++] = pair->first;
    cursor = pair->second;

    if (elmc_json_is_decoder_value(cursor)) {
      decoders[count++] = cursor;
      break;
    }
  }

  return count;
}

static ElmcValue *elmc_json_decode_mapn_with_value(
  ElmcValue *payload,
  const ElmcJsonValue *node,
  int expected_count,
  const char **error_out
) {
  if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
    if (error_out) *error_out = "Invalid map decoder";
    return NULL;
  }

  ElmcTuple2 *outer = (ElmcTuple2 *)payload->payload;
  ElmcValue *decoder_slots[7];
  int count = elmc_json_decode_collect_decoders(outer->second, decoder_slots, 7);

  if (count != expected_count) {
    if (error_out) *error_out = "Invalid map decoder";
    return NULL;
  }

  ElmcValue *args[7];
  int i;

  for (i = 0; i < count; i++) {
    args[i] = elmc_json_decode_with_value(decoder_slots[i], node, error_out);
    if (!args[i]) {
      for (int j = 0; j < i; j++) elmc_release(args[j]);
      return NULL;
    }
  }

  ElmcValue *mapped = elmc_closure_call(outer->first, args, count);
  for (i = 0; i < count; i++) elmc_release(args[i]);
  if (!mapped && error_out) *error_out = "Failed to map decoded value";
  return mapped;
}

static ElmcValue *elmc_json_decode_map7_with_value(ElmcValue *payload, const ElmcJsonValue *node, const char **error_out) {
  if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
    if (error_out) *error_out = "Invalid map decoder";
    return NULL;
  }

  ElmcTuple2 *outer = (ElmcTuple2 *)payload->payload;
  ElmcValue *decoder_slots[7];
  int count = elmc_json_decode_collect_decoders(outer->second, decoder_slots, 7);

  if (count < 2 || count > 7) {
    if (error_out) *error_out = "Invalid map decoder";
    return NULL;
  }

  return elmc_json_decode_mapn_with_value(payload, node, count, error_out);
}

static ElmcValue *elmc_json_decode_map2_with_value(ElmcValue *payload, const ElmcJsonValue *node, const char **error_out) {
  return elmc_json_decode_mapn_with_value(payload, node, 2, error_out);
}

static ElmcValue *elmc_json_decode_key_value_pairs_with_value(
  ElmcValue *decoder,
  const ElmcJsonValue *node,
  const char **error_out
) {
  if (!node || node->kind != ELMC_JSON_OBJECT) {
    if (error_out) *error_out = "Expected OBJECT for key-value pairs";
    return NULL;
  }

  ElmcValue *rev = elmc_list_nil();
  ElmcJsonValue *child = node->child;

  while (child) {
    ElmcValue *key = NULL;
    if (elmc_new_string(&key, child->key ? child->key : "") != RC_SUCCESS) key = NULL;
    ElmcValue *decoded = elmc_json_decode_with_value(decoder, child, error_out);

    if (!key || !decoded) {
      elmc_release(rev);
      if (key) elmc_release(key);
      if (decoded) elmc_release(decoded);
      return NULL;
    }

    ElmcValue *pair = NULL;
    if (elmc_tuple2(&pair, key, decoded) != RC_SUCCESS) pair = NULL;
    elmc_release(key);
    elmc_release(decoded);

    if (!pair) {
      elmc_release(rev);
      return NULL;
    }

    ElmcValue *next = NULL;
    if (elmc_list_cons(&next, pair, rev) != RC_SUCCESS) next = NULL;
    elmc_release(pair);
    elmc_release(rev);
    rev = next;
    child = child->next;
  }

  ElmcValue *out = elmc_list_reverse_copy(rev);
  elmc_release(rev);
  return out;
}

static ElmcValue *elmc_json_decode_with_value(ElmcValue *decoder, const ElmcJsonValue *node, const char **error_out) {
  int64_t tag = elmc_json_decoder_tag(decoder);
  ElmcValue *payload = elmc_json_decoder_payload(decoder);

  switch (tag) {
    case ELMC_JSON_DECODER_STRING:
      if (!node || node->kind != ELMC_JSON_STRING) {
        if (error_out) *error_out = "Expected STRING";
        return NULL;
      }
      {
        ElmcValue *_elmc_rc_out = NULL;
        if (elmc_new_string(&_elmc_rc_out, node->string_value ? node->string_value : "") != RC_SUCCESS) return NULL;
        return _elmc_rc_out;
      }
    case ELMC_JSON_DECODER_INT:
      if (!node || node->kind != ELMC_JSON_INT) {
        if (error_out) *error_out = "Expected INT";
        return NULL;
      }
      {
        ElmcValue *_elmc_rc_out = NULL;
        if (elmc_new_int(&_elmc_rc_out, node->int_value) != RC_SUCCESS) return NULL;
        return _elmc_rc_out;
      }
    case ELMC_JSON_DECODER_FLOAT:
      if (!node || (node->kind != ELMC_JSON_INT && node->kind != ELMC_JSON_FLOAT)) {
        if (error_out) *error_out = "Expected FLOAT";
        return NULL;
      }
      return elmc_new_float_take(node->kind == ELMC_JSON_INT ? (double)node->int_value : node->float_value);
    case ELMC_JSON_DECODER_BOOL:
      if (!node || node->kind != ELMC_JSON_BOOL) {
        if (error_out) *error_out = "Expected BOOL";
        return NULL;
      }
      {
        ElmcValue *_elmc_rc_out = NULL;
        (void)elmc_new_bool(&_elmc_rc_out, node->bool_value);
        return _elmc_rc_out;
      }
    case ELMC_JSON_DECODER_VALUE:
      return elmc_json_value_to_string(node);
    case ELMC_JSON_DECODER_FIELD:
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL || !node || node->kind != ELMC_JSON_OBJECT) {
        if (error_out) *error_out = "Expected OBJECT field";
        return NULL;
      } else {
        ElmcTuple2 *field_tuple = (ElmcTuple2 *)payload->payload;
        const char *field_name =
          (field_tuple->first && field_tuple->first->tag == ELMC_TAG_STRING && field_tuple->first->payload)
            ? (const char *)field_tuple->first->payload
            : NULL;
        if (!field_name) {
          if (error_out) *error_out = "Invalid field decoder";
          return NULL;
        }
        ElmcJsonValue *child = elmc_json_object_get(node, field_name);
        if (!child) {
          if (error_out) *error_out = "Missing field";
          return NULL;
        }
        return elmc_json_decode_with_value(field_tuple->second, child, error_out);
      }
    case ELMC_JSON_DECODER_INDEX:
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL || !node || node->kind != ELMC_JSON_ARRAY) {
        if (error_out) *error_out = "Expected ARRAY index";
        return NULL;
      } else {
        ElmcTuple2 *index_tuple = (ElmcTuple2 *)payload->payload;
        int idx = (int)elmc_as_int(index_tuple->first);
        ElmcJsonValue *child = elmc_json_array_get(node, idx);
        if (!child) {
          if (error_out) *error_out = "Index out of range";
          return NULL;
        }
        return elmc_json_decode_with_value(index_tuple->second, child, error_out);
      }
    case ELMC_JSON_DECODER_LIST:
    case ELMC_JSON_DECODER_ARRAY:
      if (!payload || !node || node->kind != ELMC_JSON_ARRAY) {
        if (error_out) *error_out = "Expected ARRAY";
        return NULL;
      } else {
        ElmcValue *rev = elmc_list_nil();
        if (!rev) {
          if (error_out) *error_out = "Out of memory";
          return NULL;
        }
        ElmcJsonValue *child = node->child;
        while (child) {
          ElmcValue *decoded = elmc_json_decode_with_value(payload, child, error_out);
          if (!decoded) {
            elmc_release(rev);
            return NULL;
          }
          ElmcValue *next = NULL;
          if (elmc_list_cons(&next, decoded, rev) != RC_SUCCESS) next = NULL;
          elmc_release(decoded);
          elmc_release(rev);
          rev = next;
          child = child->next;
        }
        ElmcValue *out = elmc_list_reverse_copy(rev);
        elmc_release(rev);
        return out;
      }
    case ELMC_JSON_DECODER_NULL:
      if (node && node->kind == ELMC_JSON_NULL) return payload ? elmc_retain(payload) : elmc_list_nil();
      if (error_out) *error_out = "Expected NULL";
      return NULL;
    case ELMC_JSON_DECODER_MAYBE: {
      ElmcValue *decoded = elmc_json_decode_with_value(payload, node, NULL);
      if (!decoded) return elmc_maybe_nothing();
      ElmcValue *out = NULL;
      if (elmc_maybe_just(&out, decoded) != RC_SUCCESS) out = NULL;
      elmc_release(decoded);
      return out;
    }
    case ELMC_JSON_DECODER_ONE_OF:
      if (!payload || payload->tag != ELMC_TAG_LIST) {
        if (error_out) *error_out = "Invalid oneOf decoder";
        return NULL;
      } else {
        ElmcValue *cursor = payload;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *cons = (ElmcCons *)cursor->payload;
          ElmcValue *decoded = elmc_json_decode_with_value(cons->head, node, NULL);
          if (decoded) return decoded;
          cursor = cons->tail;
        }
        if (error_out) *error_out = "oneOf failed";
        return NULL;
      }
    case ELMC_JSON_DECODER_SUCCEED:
      return payload ? elmc_retain(payload) : elmc_list_nil();
    case ELMC_JSON_DECODER_FAIL:
      if (error_out) *error_out = "Decoder forced failure";
      return NULL;
    case ELMC_JSON_DECODER_MAP:
      return elmc_json_decode_map_with_value(payload, node, error_out);
    case ELMC_JSON_DECODER_MAP2:
      return elmc_json_decode_map2_with_value(payload, node, error_out);
    case ELMC_JSON_DECODER_MAP7:
      return elmc_json_decode_map7_with_value(payload, node, error_out);
    case ELMC_JSON_DECODER_KEY_VALUE_PAIRS:
      if (!payload) {
        if (error_out) *error_out = "Invalid keyValuePairs decoder";
        return NULL;
      }
      return elmc_json_decode_key_value_pairs_with_value(payload, node, error_out);
    case ELMC_JSON_DECODER_AND_THEN:
      if (!payload || payload->tag != ELMC_TAG_TUPLE2 || payload->payload == NULL) {
        if (error_out) *error_out = "Invalid andThen decoder";
        return NULL;
      } else {
        ElmcTuple2 *and_then_tuple = (ElmcTuple2 *)payload->payload;
        ElmcValue *step = elmc_json_decode_with_value(and_then_tuple->second, node, error_out);
        if (!step) return NULL;
        ElmcValue *args[] = { step };
        ElmcValue *next_decoder = elmc_closure_call(and_then_tuple->first, args, 1);
        elmc_release(step);
        if (!next_decoder) {
          if (error_out) *error_out = "Failed to resolve andThen decoder";
          return NULL;
        }
        ElmcValue *decoded = elmc_json_decode_with_value(next_decoder, node, error_out);
        elmc_release(next_decoder);
        return decoded;
      }
    default:
      if (error_out) *error_out = "Unsupported decoder";
      return NULL;
  }
}

ElmcValue *elmc_json_decode_value(ElmcValue *decoder, ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_STRING || value->payload == NULL) {
    {
      ElmcValue *_elmc_rc_msg = NULL;
      if (elmc_new_string(&_elmc_rc_msg, "Expected JSON string value") != RC_SUCCESS) return NULL;
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_result_err(&_elmc_rc_out, _elmc_rc_msg) != RC_SUCCESS) {
        elmc_release(_elmc_rc_msg);
        return NULL;
      }
      elmc_release(_elmc_rc_msg);
      return _elmc_rc_out;
    }
  }
  const char *raw = (const char *)value->payload;
  const char *parse_error = "Invalid JSON";
  ElmcJsonValue *parsed = elmc_json_parse_document(raw, &parse_error);
  if (!parsed) {
    {
      ElmcValue *_elmc_rc_msg = NULL;
      if (elmc_new_string(&_elmc_rc_msg, parse_error ? parse_error : "Invalid JSON") != RC_SUCCESS) return NULL;
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_result_err(&_elmc_rc_out, _elmc_rc_msg) != RC_SUCCESS) {
        elmc_release(_elmc_rc_msg);
        return NULL;
      }
      elmc_release(_elmc_rc_msg);
      return _elmc_rc_out;
    }
  }
  const char *decode_error = "Decode failed";
  ElmcValue *decoded = elmc_json_decode_with_value(decoder, parsed, &decode_error);
  elmc_json_free_value(parsed);
  if (!decoded) {
    ElmcValue *_elmc_rc_msg = NULL;
    if (elmc_new_string(&_elmc_rc_msg, decode_error ? decode_error : "Decode failed") != RC_SUCCESS) return NULL;
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_result_err(&_elmc_rc_out, _elmc_rc_msg) != RC_SUCCESS) {
      elmc_release(_elmc_rc_msg);
      return NULL;
    }
    elmc_release(_elmc_rc_msg);
    return _elmc_rc_out;
  }
  ElmcValue *ok = NULL;
  if (elmc_result_ok(&ok, decoded) != RC_SUCCESS) ok = NULL;
  elmc_release(decoded);
  return ok;
}

ElmcValue *elmc_json_decode_string(ElmcValue *decoder, ElmcValue *s) {
  return elmc_json_decode_value(decoder, s);
}

ElmcValue *elmc_json_decode_string_decoder(void) {
  {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, ELMC_JSON_DECODER_STRING) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_decode_int_decoder(void) {
  {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, ELMC_JSON_DECODER_INT) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_decode_float_decoder(void) {
  {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, ELMC_JSON_DECODER_FLOAT) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_decode_bool_decoder(void) {
  {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, ELMC_JSON_DECODER_BOOL) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_decode_null(ElmcValue *default_val) {
  return elmc_json_decoder_wrap(ELMC_JSON_DECODER_NULL, default_val);
}

ElmcValue *elmc_json_decode_nullable(ElmcValue *decoder) {
  return elmc_json_decode_maybe(decoder);
}

ElmcValue *elmc_json_decode_list(ElmcValue *decoder) {
  return elmc_json_decoder_wrap(ELMC_JSON_DECODER_LIST, decoder);
}

ElmcValue *elmc_json_decode_array(ElmcValue *decoder) {
  return elmc_json_decoder_wrap(ELMC_JSON_DECODER_ARRAY, decoder);
}

ElmcValue *elmc_json_decode_field(ElmcValue *name, ElmcValue *decoder) {
  ElmcValue *payload = NULL;
  if (elmc_tuple2(&payload, name, decoder) != RC_SUCCESS) payload = NULL;
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_FIELD, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_at(ElmcValue *path, ElmcValue *decoder) {
  if (!path) return elmc_retain(decoder);
  ElmcValue *reversed = elmc_list_reverse_copy(path);
  ElmcValue *current = elmc_retain(decoder);
  ElmcValue *cursor = reversed;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *next = elmc_json_decode_field(node->head, current);
    elmc_release(current);
    current = next;
    cursor = node->tail;
  }
  elmc_release(reversed);
  return current;
}

ElmcValue *elmc_json_decode_index(ElmcValue *idx, ElmcValue *decoder) {
  ElmcValue *payload = NULL;
  if (elmc_tuple2(&payload, idx, decoder) != RC_SUCCESS) payload = NULL;
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_INDEX, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_map(ElmcValue *f, ElmcValue *decoder) {
  ElmcValue *payload = NULL;
  if (elmc_tuple2(&payload, f, decoder) != RC_SUCCESS) payload = NULL;
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_map2(ElmcValue *f, ElmcValue *d1, ElmcValue *d2) {
  ElmcValue *pair = NULL;
  if (elmc_tuple2(&pair, d1, d2) != RC_SUCCESS) pair = NULL;
  if (!pair) return NULL;
  ElmcValue *payload = NULL;
  if (elmc_tuple2(&payload, f, pair) != RC_SUCCESS) payload = NULL;
  elmc_release(pair);
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP2, payload);
  elmc_release(payload);
  return wrapped;
}

static ElmcValue *elmc_json_decode_map_build_payload(ElmcValue *f, ElmcValue **decoders, int count) {
  ElmcValue *tail = NULL;
  int i;

  if (!f || count < 2 || count > 7) return NULL;

  if (elmc_tuple2(&tail, decoders[count - 2], decoders[count - 1]) != RC_SUCCESS) tail = NULL;
  if (!tail) return NULL;

  for (i = count - 3; i >= 0; i--) {
    ElmcValue *next = NULL;
    if (elmc_tuple2(&next, decoders[i], tail) != RC_SUCCESS) next = NULL;
    elmc_release(tail);
    if (!next) return NULL;
    tail = next;
  }

  ElmcValue *payload = NULL;
  if (elmc_tuple2(&payload, f, tail) != RC_SUCCESS) payload = NULL;
  elmc_release(tail);
  return payload;
}

ElmcValue *elmc_json_decode_map3(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3) {
  ElmcValue *decoders[] = {d1, d2, d3};
  ElmcValue *payload = elmc_json_decode_map_build_payload(f, decoders, 3);
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP7, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_map4(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4) {
  ElmcValue *decoders[] = {d1, d2, d3, d4};
  ElmcValue *payload = elmc_json_decode_map_build_payload(f, decoders, 4);
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP7, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_map5(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5) {
  ElmcValue *decoders[] = {d1, d2, d3, d4, d5};
  ElmcValue *payload = elmc_json_decode_map_build_payload(f, decoders, 5);
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP7, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_map6(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6) {
  ElmcValue *decoders[] = {d1, d2, d3, d4, d5, d6};
  ElmcValue *payload = elmc_json_decode_map_build_payload(f, decoders, 6);
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP7, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_map7(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6, ElmcValue *d7) {
  ElmcValue *decoders[] = {d1, d2, d3, d4, d5, d6, d7};
  ElmcValue *payload = elmc_json_decode_map_build_payload(f, decoders, 7);
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAP7, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_succeed(ElmcValue *value) {
  return elmc_json_decoder_wrap(ELMC_JSON_DECODER_SUCCEED, value);
}

ElmcValue *elmc_json_decode_fail(ElmcValue *msg) {
  return elmc_json_decoder_wrap(ELMC_JSON_DECODER_FAIL, msg);
}

ElmcValue *elmc_json_decode_and_then(ElmcValue *f, ElmcValue *decoder) {
  ElmcValue *payload = NULL;
  if (elmc_tuple2(&payload, f, decoder) != RC_SUCCESS) payload = NULL;
  if (!payload) return NULL;
  ElmcValue *wrapped = elmc_json_decoder_wrap(ELMC_JSON_DECODER_AND_THEN, payload);
  elmc_release(payload);
  return wrapped;
}

ElmcValue *elmc_json_decode_one_of(ElmcValue *decoders) {
  return elmc_json_decoder_wrap(ELMC_JSON_DECODER_ONE_OF, decoders);
}

ElmcValue *elmc_json_decode_maybe(ElmcValue *decoder) {
  return elmc_json_decoder_wrap(ELMC_JSON_DECODER_MAYBE, decoder);
}

ElmcValue *elmc_json_decode_lazy(ElmcValue *thunk) {
  if (!thunk || thunk->tag != ELMC_TAG_CLOSURE) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, 0) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  ElmcValue *forced = elmc_closure_call(thunk, NULL, 0);
  {
    if (forced) return forced;
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, 0) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_decode_value_decoder(void) {
  {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_int(&_elmc_rc_out, ELMC_JSON_DECODER_VALUE) != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_decode_error_to_string(ElmcValue *err) {
  if (err && err->tag == ELMC_TAG_STRING && err->payload) return elmc_retain(err);
  {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_string(&_elmc_rc_out, "Json.Decode.Error") != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_decode_key_value_pairs(ElmcValue *decoder) {
  return elmc_json_decoder_wrap(ELMC_JSON_DECODER_KEY_VALUE_PAIRS, decoder);
}

ElmcValue *elmc_json_decode_dict(ElmcValue *decoder) {
  return elmc_json_decode_key_value_pairs(decoder);
}

/* ================================================================
   Standard Library – Json.Encode
   ================================================================ */

static int elmc_json_encoded_to_buffer(ElmcValue *value, ElmcJsonBuffer *buf) {
  if (!value) return elmc_json_buf_append_cstr(buf, "null");
  if (value->tag == ELMC_TAG_STRING && value->payload != NULL) {
    const char *raw = (const char *)value->payload;
    const char *parse_error = NULL;
    ElmcJsonValue *parsed = elmc_json_parse_document(raw, &parse_error);
    if (parsed) {
      int ok = elmc_json_encode_value_to_buffer(parsed, buf);
      elmc_json_free_value(parsed);
      return ok;
    }
    return elmc_json_encode_string_to_buffer(raw, buf);
  }
  if (value->tag == ELMC_TAG_INT) {
    char number[32];
    snprintf(number, sizeof(number), "%lld", (long long)elmc_as_int(value));
    return elmc_json_buf_append_cstr(buf, number);
  }
  if (value->tag == ELMC_TAG_FLOAT) {
    char number[48];
    snprintf(number, sizeof(number), "%.17g", elmc_as_float(value));
    return elmc_json_buf_append_cstr(buf, number);
  }
  if (value->tag == ELMC_TAG_BOOL) return elmc_json_buf_append_cstr(buf, elmc_as_int(value) ? "true" : "false");
  if (value->tag == ELMC_TAG_LIST) {
    if (!elmc_json_buf_append_char(buf, '[')) return 0;
    ElmcValue *cursor = value;
    int first = 1;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
      if (!elmc_json_encoded_to_buffer(node->head, buf)) return 0;
      first = 0;
      cursor = node->tail;
    }
    return elmc_json_buf_append_char(buf, ']');
  }
  return elmc_json_buf_append_cstr(buf, "null");
}

ElmcValue *elmc_json_encode_string(ElmcValue *s) {
  const char *raw = (s && s->tag == ELMC_TAG_STRING && s->payload) ? (const char *)s->payload : "";
  ElmcJsonBuffer buf;
  elmc_json_buf_init(&buf);
  if (!elmc_json_encode_string_to_buffer(raw, &buf)) {
    elmc_json_buf_free(&buf);
    {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_string(&_elmc_rc_out, "\"\"") != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
  }
  return elmc_json_buf_to_string(&buf);
}

ElmcValue *elmc_json_encode_int(ElmcValue *n) {
  return elmc_string_from_int(n);
}

ElmcValue *elmc_json_encode_float(ElmcValue *f) {
  return elmc_string_from_float_take(f);
}

ElmcValue *elmc_json_encode_bool(ElmcValue *b) {
  {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_string(&_elmc_rc_out, elmc_as_int(b) ? "true" : "false") != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_encode_null(void) {
  {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_string(&_elmc_rc_out, "null") != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
}

ElmcValue *elmc_json_encode_list(ElmcValue *f, ElmcValue *items) {
  ElmcJsonBuffer buf;
  elmc_json_buf_init(&buf);
  if (!elmc_json_buf_append_char(&buf, '[')) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_string(&_elmc_rc_out, "[]") != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  ElmcValue *cursor = items;
  int first = 1;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *args[] = { node->head };
    ElmcValue *mapped = elmc_closure_call(f, args, 1);
    if (!first) elmc_json_buf_append_char(&buf, ',');
    elmc_json_encoded_to_buffer(mapped, &buf);
    first = 0;
    if (mapped) elmc_release(mapped);
    cursor = node->tail;
  }
  elmc_json_buf_append_char(&buf, ']');
  return elmc_json_buf_to_string(&buf);
}

ElmcValue *elmc_json_encode_array(ElmcValue *f, ElmcValue *items) {
  return elmc_json_encode_list(f, items);
}

ElmcValue *elmc_json_encode_set(ElmcValue *f, ElmcValue *items) {
  return elmc_json_encode_list(f, items);
}

ElmcValue *elmc_json_encode_object(ElmcValue *pairs) {
  ElmcJsonBuffer buf;
  elmc_json_buf_init(&buf);
  if (!elmc_json_buf_append_char(&buf, '{')) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_string(&_elmc_rc_out, "{}") != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  ElmcValue *cursor = pairs;
  int first = 1;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *entry = node->head;
    if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
      ElmcTuple2 *tuple = (ElmcTuple2 *)entry->payload;
      const char *key = (tuple->first && tuple->first->tag == ELMC_TAG_STRING && tuple->first->payload)
                          ? (const char *)tuple->first->payload
                          : NULL;
      if (key) {
        if (!first) elmc_json_buf_append_char(&buf, ',');
        elmc_json_encode_string_to_buffer(key, &buf);
        elmc_json_buf_append_char(&buf, ':');
        elmc_json_encoded_to_buffer(tuple->second, &buf);
        first = 0;
      }
    }
    cursor = node->tail;
  }
  elmc_json_buf_append_char(&buf, '}');
  return elmc_json_buf_to_string(&buf);
}

ElmcValue *elmc_json_encode_dict(ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict) {
  ElmcJsonBuffer buf;
  elmc_json_buf_init(&buf);
  if (!elmc_json_buf_append_char(&buf, '{')) {
    ElmcValue *_elmc_rc_out = NULL;
    if (elmc_new_string(&_elmc_rc_out, "{}") != RC_SUCCESS) return NULL;
    return _elmc_rc_out;
  }
  ElmcValue *cursor = dict;
  int first = 1;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *entry = node->head;
    if (entry && entry->tag == ELMC_TAG_TUPLE2 && entry->payload != NULL) {
      ElmcTuple2 *tuple = (ElmcTuple2 *)entry->payload;
      ElmcValue *key_args[] = { tuple->first };
      ElmcValue *val_args[] = { tuple->second };
      ElmcValue *key_text = elmc_closure_call(key_fn, key_args, 1);
      ElmcValue *val_enc = elmc_closure_call(val_fn, val_args, 1);
      const char *key = (key_text && key_text->tag == ELMC_TAG_STRING && key_text->payload)
                          ? (const char *)key_text->payload
                          : NULL;
      if (key) {
        if (!first) elmc_json_buf_append_char(&buf, ',');
        elmc_json_encode_string_to_buffer(key, &buf);
        elmc_json_buf_append_char(&buf, ':');
        elmc_json_encoded_to_buffer(val_enc, &buf);
        first = 0;
      }
      if (key_text) elmc_release(key_text);
      if (val_enc) elmc_release(val_enc);
    }
    cursor = node->tail;
  }
  elmc_json_buf_append_char(&buf, '}');
  return elmc_json_buf_to_string(&buf);
}

ElmcValue *elmc_json_encode_encode(ElmcValue *indent, ElmcValue *value) {
  (void)indent;
  ElmcJsonBuffer buf;
  elmc_json_buf_init(&buf);
  if (!elmc_json_encoded_to_buffer(value, &buf)) {
    elmc_json_buf_free(&buf);
    {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_string(&_elmc_rc_out, "null") != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
  }
  return elmc_json_buf_to_string(&buf);
}


uint64_t elmc_rc_allocated_count(void) {
  return ELMC_ALLOCATED;
}

uint64_t elmc_rc_released_count(void) {
  return ELMC_RELEASED;
}

volatile RC elmc_last_fail_rc = RC_SUCCESS;
volatile uint16_t elmc_last_fail_line = 0;

#ifndef ELMC_PEBBLE_PLATFORM
const char *elmc_rc_name(RC rc) {
  static const char * const elmc_rc_names[] = {
  "RC_SUCCESS",
  "RC_ERR_OUT_OF_MEMORY",
  "RC_ERR_INVALID_ARG",
  "RC_ERR_UNSUPPORTED",
  "RC_ERR_MISSING_CALLBACK",
  "RC_ERR_MALFORMED_TUPLE",
  "RC_ERR_MALFORMED_CMD",
  "RC_ERR_MALFORMED_VIEW",
  "RC_ERR_MALFORMED_SUB",
  "RC_ERR_SCENE_BUFFER_OVERFLOW",
  "RC_ERR_SCENE_DECODE",
  "RC_ERR_SCENE_DEPTH_LIMIT",
  "RC_ERR_RENDER_ABORT",
  "RC_ERR_PERSIST_WRITE_INT",
  "RC_ERR_PERSIST_READ_INT",
  "RC_ERR_PERSIST_WRITE_STRING",
  "RC_ERR_PERSIST_READ_STRING",
  "RC_ERR_PERSIST_DELETE",
  "RC_ERR_APP_MESSAGE_OPEN",
  "RC_ERR_APP_MESSAGE_OUTBOX_BEGIN",
  "RC_ERR_APP_MESSAGE_OUTBOX_SEND",
  "RC_ERR_APP_TIMER_REGISTER",
  "RC_ERR_APP_TIMER_RESCHEDULE",
  "RC_ERR_WAKEUP_SCHEDULE",
  "RC_ERR_WAKEUP_CANCEL",
  "RC_ERR_DATA_LOGGING_CREATE",
  "RC_ERR_DATA_LOGGING_LOG",
  "RC_ERR_DICTATION_SESSION_CREATE",
  "RC_ERR_GDRAW_SEQUENCE_CREATE",
  "RC_ERR_GDRAW_IMAGE_CREATE"
  };

  if ((unsigned)rc >= (unsigned)(sizeof(elmc_rc_names) / sizeof(elmc_rc_names[0])))
    return "RC_UNKNOWN";
  return elmc_rc_names[(unsigned)rc];
}

static inline int elmc_rc_is_success(RC rc) {
  return rc == RC_SUCCESS;
}

#endif

#if ELMC_RC_TRACK

#ifndef ELMC_RC_TRACK_MAX
#define ELMC_RC_TRACK_MAX 16384
#endif

typedef struct ElmcRcTrackEntry {
  ElmcValue *value;
  uint32_t id;
  uint8_t tag;
  uint16_t rc;
  uint32_t retains;
  uint32_t releases;
  const char *alloc_context;
  const char *alloc_file;
  int alloc_line;
  const char *last_retain_file;
  int last_retain_line;
  const char *last_release_file;
  int last_release_line;
} ElmcRcTrackEntry;

static ElmcRcTrackEntry ELMC_RC_TRACK_ENTRIES[ELMC_RC_TRACK_MAX];
static uint32_t ELMC_RC_TRACK_COUNT = 0;
static uint32_t ELMC_RC_TRACK_NEXT_ID = 1;

static const char *elmc_rc_track_tag_name(ElmcTag tag) {
  switch (tag) {
    case ELMC_TAG_INT: return "Int";
    case ELMC_TAG_BOOL: return "Bool";
    case ELMC_TAG_STRING: return "String";
    case ELMC_TAG_LIST: return "List";
    case ELMC_TAG_RESULT: return "Result";
    case ELMC_TAG_MAYBE: return "Maybe";
    case ELMC_TAG_TUPLE2: return "Tuple2";
    case ELMC_TAG_RECORD: return "Record";
    case ELMC_TAG_CLOSURE: return "Closure";
    case ELMC_TAG_CMD: return "Cmd";
    case ELMC_TAG_SUB: return "Sub";
    default: return "Value";
  }
}

static ElmcRcTrackEntry *elmc_rc_track_find(ElmcValue *value) {
  if (!value) return NULL;
  for (uint32_t i = 0; i < ELMC_RC_TRACK_COUNT; i++) {
    if (ELMC_RC_TRACK_ENTRIES[i].value == value) return &ELMC_RC_TRACK_ENTRIES[i];
  }
  return NULL;
}

void elmc_rc_track_register(ElmcValue *value, const char *context, const char *file, int line) {
  if (!value || value->rc == ELMC_RC_IMMORTAL) return;
  if (ELMC_RC_TRACK_COUNT >= ELMC_RC_TRACK_MAX) return;
  ElmcRcTrackEntry *entry = &ELMC_RC_TRACK_ENTRIES[ELMC_RC_TRACK_COUNT++];
  entry->value = value;
  entry->id = ELMC_RC_TRACK_NEXT_ID++;
  entry->tag = value->tag;
  entry->rc = value->rc;
  entry->retains = 0;
  entry->releases = 0;
  entry->alloc_context = context ? context : "alloc";
  entry->alloc_file = file;
  entry->alloc_line = line;
  entry->last_retain_file = file;
  entry->last_retain_line = line;
  entry->last_release_file = NULL;
  entry->last_release_line = 0;
}

static void elmc_rc_track_unregister(ElmcValue *value) {
  if (!value) return;
  for (uint32_t i = 0; i < ELMC_RC_TRACK_COUNT; i++) {
    if (ELMC_RC_TRACK_ENTRIES[i].value != value) continue;
    ELMC_RC_TRACK_COUNT -= 1;
    if (i < ELMC_RC_TRACK_COUNT) {
      ELMC_RC_TRACK_ENTRIES[i] = ELMC_RC_TRACK_ENTRIES[ELMC_RC_TRACK_COUNT];
    }
    return;
  }
}

static void elmc_rc_track_sync(ElmcRcTrackEntry *entry) {
  if (!entry || !entry->value) return;
  entry->rc = entry->value->rc;
  entry->tag = entry->value->tag;
}

void elmc_rc_track_reset(void) {
  ELMC_RC_TRACK_COUNT = 0;
  ELMC_RC_TRACK_NEXT_ID = 1;
}

uint32_t elmc_rc_track_live_count(void) {
  return ELMC_RC_TRACK_COUNT;
}

void elmc_rc_track_dump_live(FILE *out) {
  if (!out) out = stderr;
  fprintf(out, "elmc rc track: %u live object(s)\n", ELMC_RC_TRACK_COUNT);
  for (uint32_t i = 0; i < ELMC_RC_TRACK_COUNT; i++) {
    ElmcRcTrackEntry *entry = &ELMC_RC_TRACK_ENTRIES[i];
    const char *alloc_file = entry->alloc_file ? entry->alloc_file : "?";
    const char *retain_file = entry->last_retain_file ? entry->last_retain_file : "?";
    const char *release_file = entry->last_release_file ? entry->last_release_file : "?";
    fprintf(out,
            "  #%u %s rc=%u retains=%u releases=%u alloc=%s:%d (%s) last_retain=%s:%d last_release=%s:%d\n",
            entry->id,
            elmc_rc_track_tag_name((ElmcTag)entry->tag),
            entry->rc,
            entry->retains,
            entry->releases,
            alloc_file,
            entry->alloc_line,
            entry->alloc_context ? entry->alloc_context : "alloc",
            retain_file,
            entry->last_retain_line,
            release_file,
            entry->last_release_line);
  }
}

int elmc_rc_track_check_balanced(void) {
  int ok = 1;
  if (elmc_rc_allocated_count() != elmc_rc_released_count()) {
    fprintf(stderr,
            "elmc rc counters unbalanced: allocated=%llu released=%llu\n",
            (unsigned long long)elmc_rc_allocated_count(),
            (unsigned long long)elmc_rc_released_count());
    ok = 0;
  }
  if (ELMC_RC_TRACK_COUNT > 0) {
    elmc_rc_track_dump_live(stderr);
    ok = 0;
  }
  return ok;
}

static void elmc_rc_track_on_retain(ElmcValue *value, const char *file, int line) {
  if (!value || value->rc == ELMC_RC_IMMORTAL) return;
  ElmcRcTrackEntry *entry = elmc_rc_track_find(value);
  if (!entry) return;
  entry->retains += 1;
  entry->last_retain_file = file;
  entry->last_retain_line = line;
}

static void elmc_rc_track_on_release(ElmcValue *value, const char *file, int line) {
  if (!value || value->rc == ELMC_RC_IMMORTAL) return;
  ElmcRcTrackEntry *entry = elmc_rc_track_find(value);
  if (!entry) return;
  entry->releases += 1;
  entry->last_release_file = file;
  entry->last_release_line = line;
}

#endif


#if ELMC_RC_TRACK
ElmcValue *elmc_rc_track_retain(ElmcValue *value, const char *file, int line) {
  elmc_rc_track_on_retain(value, file, line);
  ElmcValue *out = elmc_retain_impl(value);
  ElmcRcTrackEntry *entry = elmc_rc_track_find(value);
  if (entry) elmc_rc_track_sync(entry);
  return out;
}

void elmc_rc_track_release(ElmcValue *value, const char *file, int line) {
  if (!value) return;
  elmc_rc_track_on_release(value, file, line);
  ElmcRcTrackEntry *entry = elmc_rc_track_find(value);
  uint16_t rc_before = value->rc;
  if (entry && rc_before == 1) {
    elmc_rc_track_unregister(value);
  }
  elmc_release_impl(value);
  if (entry && rc_before > 1) {
    elmc_rc_track_sync(entry);
  }
}
#endif

static ElmcValue *elmc_retain_impl(ElmcValue *value) {
  if (!value) return NULL;
  if (value->rc == ELMC_RC_IMMORTAL) return value;
  if (value->rc < ELMC_RC_IMMORTAL - 1) value->rc += 1;
  return value;
}

#if !ELMC_RC_TRACK
ElmcValue *elmc_retain(ElmcValue *value) {
  return elmc_retain_impl(value);
}
#endif

/* Iterative list teardown: recursive tail release overflows Pebble's ~4-6 KB
   app stack when dropping flat boards (for example elmtris lockPiece board). */
#if ELMC_RC_TRACK
static void elmc_rc_track_drop_owned(ElmcValue *value) {
  if (!value || value->rc == ELMC_RC_IMMORTAL) return;
  elmc_rc_track_unregister(value);
}
#endif

static void elmc_release_list_cell_payload(ElmcValue *cell) {
  if (!cell || cell->tag != ELMC_TAG_LIST || !cell->payload) return;
#if ELMC_RC_TRACK
  elmc_rc_track_drop_owned(cell);
#endif
  if (elmc_list_cell_release(cell)) {
    ELMC_RELEASED += 1;
    return;
  }
  free(cell->payload);
  free(cell);
  ELMC_RELEASED += 1;
}

static void elmc_release_list_spine(ElmcValue *list) {
  ElmcValue *cursor = list;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    if (cursor->rc == ELMC_RC_IMMORTAL) break;
    ElmcCons *node = (ElmcCons *)cursor->payload;
    ElmcValue *head = node->head;
    ElmcValue *next = node->tail;
    node->head = NULL;
    node->tail = NULL;
    elmc_release(head);
    ElmcValue *cell = cursor;
    cursor = next;
    elmc_release_list_cell_payload(cell);
  }
}

static void elmc_release_impl(ElmcValue *value) {
  if (!value) return;
  if (value->rc == ELMC_RC_IMMORTAL) return;
  if (value->rc == 0) return;
  value->rc -= 1;
  if (value->rc > 0) return;
  if (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) {
    /* Scalar values live inline in ElmcValue, not in heap payloads. */
  } else if (value->tag == ELMC_TAG_LIST && value->payload != NULL) {
    elmc_release_list_spine(value);
    return;
  } else if (value->tag == ELMC_TAG_MAYBE && value->payload != NULL) {
    ElmcMaybe *maybe = (ElmcMaybe *)value->payload;
    if (maybe->value) elmc_release(maybe->value);
  } else if (value->tag == ELMC_TAG_RESULT && value->payload != NULL) {
    ElmcResult *result = (ElmcResult *)value->payload;
    if (result->value) elmc_release(result->value);
  } else if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (tuple->first) elmc_release(tuple->first);
    if (tuple->second) elmc_release(tuple->second);
  } else if (value->tag == ELMC_TAG_RECORD && value->payload != NULL) {
    ElmcRecord *rec = (ElmcRecord *)value->payload;
    for (int i = 0; i < rec->field_count; i++) {
      if (rec->field_values[i]) elmc_release(rec->field_values[i]);
    }
    if (elmc_record_cell_release(value)) {
    #if ELMC_RC_TRACK
      elmc_rc_track_drop_owned(value);
    #endif
      ELMC_RELEASED += 1;
      return;
    }
    free(rec->field_values);
  } else if (value->tag == ELMC_TAG_CLOSURE && value->payload != NULL) {
    ElmcClosure *clo = (ElmcClosure *)value->payload;
    for (int i = 0; i < clo->capture_count; i++) {
      if (clo->captures[i]) elmc_release(clo->captures[i]);
    }
    if (elmc_closure_cell_release(value)) {
    #if ELMC_RC_TRACK
      elmc_rc_track_drop_owned(value);
    #endif
      ELMC_RELEASED += 1;
      return;
    }
    free(clo->captures);
  } else if (value->tag == ELMC_TAG_FORWARD_REF && value->payload != NULL) {
    free(value->payload);
  }
  if (value->tag == ELMC_TAG_LIST && elmc_list_cell_release(value)) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_MAYBE && elmc_maybe_cell_release(value)) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_RESULT && elmc_result_cell_release(value)) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_TUPLE2 && elmc_tuple2_cell_release(value)) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_CMD && elmc_cmd_cell_release(value)) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_SUB && elmc_sub_cell_release(value)) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL) {
    free(value->payload);
  }
  free(value);
  ELMC_RELEASED += 1;
}

#if !ELMC_RC_TRACK
void elmc_release(ElmcValue *value) {
  elmc_release_impl(value);
}
#endif


void elmc_release_deep(ElmcValue *value) {
  /* Current runtime representation has no nested ownership for supported subset. */
  elmc_release(value);
}
