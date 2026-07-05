#include "elmc_runtime.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <math.h>

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

#ifdef ELMC_PEBBLE_PLATFORM
static uint32_t ELMC_ALLOCATED = 0;
static uint32_t ELMC_RELEASED = 0;
#else
static uint64_t ELMC_ALLOCATED = 0;
static uint64_t ELMC_RELEASED = 0;
#endif
static int64_t ELMC_NEXT_PROCESS_ID = 1;
#define ELMC_PROCESS_MAX_SLOTS 16
#define ELMC_RC_IMMORTAL UINT16_MAX
static ElmcValue ELMC_BOOL_FALSE = { ELMC_RC_IMMORTAL, ELMC_TAG_BOOL, NULL, 0 };
static ElmcValue ELMC_BOOL_TRUE = { ELMC_RC_IMMORTAL, ELMC_TAG_BOOL, NULL, 1 };
#define ELMC_UNIT_SCALAR ((elmc_int_t)0x1EC01A)
#define ELMC_TASK_SUCCEED_SCALAR ((elmc_int_t)0x1EC01B)
#define ELMC_TASK_FAIL_SCALAR ((elmc_int_t)0x1EC01C)
#define ELMC_TASK_AND_THEN_SCALAR ((elmc_int_t)0x1EC01D)
#define ELMC_TASK_MAP_SCALAR ((elmc_int_t)0x1EC01E)
#define ELMC_TASK_SPAWN_SCALAR ((elmc_int_t)0x1EC01F)
#define ELMC_SMALL_INT_MIN (-1)
#define ELMC_SMALL_INT_MAX 64
const ElmcValue ELMC_SMALL_INTS[ELMC_SMALL_INT_MAX - ELMC_SMALL_INT_MIN + 1] = {
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
static ElmcIntListPayload ELMC_EMPTY_INT_LIST_PAYLOAD = { NULL, 0, 0 };
static ElmcValue ELMC_EMPTY_INT_LIST = {
  ELMC_RC_IMMORTAL,
  ELMC_TAG_INT_LIST,
  (void *)&ELMC_EMPTY_INT_LIST_PAYLOAD,
  ELMC_INT_LIST_CELL_SCALAR
};
ElmcValue ELMC_LIST_NIL = { ELMC_RC_IMMORTAL, ELMC_TAG_LIST, NULL, 0 };
static ElmcValue ELMC_UNIT = { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, ELMC_UNIT_SCALAR };

typedef struct {
  ElmcValue value;
  ElmcCons cons;
} ElmcListCell;

#define ELMC_LIST_CELL_SCALAR ((elmc_int_t)0x1EC011)
#define ELMC_DICT_SCALAR ((elmc_int_t)0x1EC012)

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

void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line);
static ElmcValue *elmc_alloc_impl(ElmcTag tag, void *payload, const char *file, int line);
static ElmcValue *elmc_small_int(elmc_int_t value);
static RC elmc_list_cell_alloc(ElmcValue **out, ElmcValue *head, ElmcValue *tail, int take);
static RC elmc_alloc_scalar(ElmcValue **out, ElmcTag tag, elmc_int_t scalar);
static int elmc_list_cell_release(ElmcValue *value);
static int elmc_int_list_cell_release(ElmcValue *value);
static int elmc_maybe_cell_release(ElmcValue *value);
static int elmc_result_cell_release(ElmcValue *value);
static int elmc_tuple2_cell_release(ElmcValue *value);
static int elmc_record_cell_release(ElmcValue *value);
static int elmc_closure_cell_release(ElmcValue *value);
static RC elmc_record_cell_alloc(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values, int take);
static RC elmc_record_cell_alloc_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values, int take);
static RC elmc_record_cell_alloc_values(ElmcValue **out, int field_count, ElmcValue **field_values, int take);
static const char **elmc_record_field_names(ElmcValue *record);

#if ELMC_ALLOC_TRACK
static void elmc_alloc_track_register(void *ptr, size_t size, const char *context, const char *file, int line);
static void elmc_free_impl(void *ptr, const char *context, const char *file, int line);
#endif


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

void elmc_process_release_all_slots(void) {
#ifndef ELMC_PEBBLE_PLATFORM
  for (int i = 0; i < ELMC_PROCESS_MAX_SLOTS; i++) {
    elmc_process_release_slot(&ELMC_PROCESS_SLOTS[i]);
  }
#endif
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

void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line) {
  void *ptr = malloc(size);
  if (!ptr) {
    elmc_log_alloc_failed(context, size, file, line);
  }
#if ELMC_ALLOC_TRACK
  else {
    elmc_alloc_track_register(ptr, size, context, file, line);
  }
#endif
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

static RC elmc_alloc_scalar(ElmcValue **out, ElmcTag tag, elmc_int_t scalar) {
  ElmcValue *value = elmc_alloc(tag, NULL);
  if (!value) return RC_ERR_OUT_OF_MEMORY;
  value->scalar = scalar;
  *out = value;
  return RC_SUCCESS;
}

static ElmcValue *elmc_small_int(elmc_int_t value) {
  if (value < ELMC_SMALL_INT_MIN || value > ELMC_SMALL_INT_MAX) return NULL;
  return (ElmcValue *)&ELMC_SMALL_INTS[value - ELMC_SMALL_INT_MIN];
}

ElmcValue *elmc_int_zero(void) {
  return elmc_small_int(0);
}

ElmcValue *elmc_unit(void) {
  return &ELMC_UNIT;
}

static RC elmc_list_cell_alloc(ElmcValue **out, ElmcValue *head, ElmcValue *tail, int take) {
  ElmcListCell *cell = (ElmcListCell *)elmc_malloc(sizeof(ElmcListCell), __func__);
  if (!cell) {
    if (take) {
      elmc_release(head);
      elmc_release(tail);
    }
    return RC_ERR_OUT_OF_MEMORY;
  }
  cell->cons.head = take ? head : elmc_retain(head);
  cell->cons.tail = take ? tail : elmc_retain(tail);
  cell->value.rc = 1;
  cell->value.tag = ELMC_TAG_LIST;
  cell->value.payload = &cell->cons;
  cell->value.scalar = ELMC_LIST_CELL_SCALAR;
  ELMC_ALLOCATED += 1;
  ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
  *out = &cell->value;
  return RC_SUCCESS;
}

static int elmc_list_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_LIST) return 0;
  if (value->scalar != ELMC_LIST_CELL_SCALAR && value->scalar != ELMC_DICT_SCALAR) return 0;
  ElmcListCell *cell = (ElmcListCell *)value;
  if (value->payload != &cell->cons) return 0;
  elmc_free(cell);
  return 1;
}

static void elmc_dict_mark_spine(ElmcValue *dict) {
  ElmcValue *cursor = dict;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    cursor->scalar = ELMC_DICT_SCALAR;
    cursor = ((ElmcCons *)cursor->payload)->tail;
  }
}

static int elmc_maybe_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_MAYBE || value->scalar != ELMC_MAYBE_CELL_SCALAR) return 0;
  ElmcMaybeCell *cell = (ElmcMaybeCell *)value;
  if (value->payload != &cell->maybe) return 0;
  elmc_free(cell);
  return 1;
}

static int elmc_result_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_RESULT) return 0;
  elmc_int_t scalar = value->scalar;
  if (scalar != ELMC_RESULT_CELL_SCALAR &&
      (scalar < ELMC_TASK_SUCCEED_SCALAR || scalar > ELMC_TASK_SPAWN_SCALAR)) {
    return 0;
  }
  ElmcResultCell *cell = (ElmcResultCell *)value;
  if (value->payload != &cell->result) return 0;
  elmc_free(cell);
  return 1;
}

static int elmc_tuple2_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_TUPLE2 || value->scalar != ELMC_TUPLE2_CELL_SCALAR) return 0;
  ElmcTuple2Cell *cell = (ElmcTuple2Cell *)value;
  if (value->payload != &cell->tuple) return 0;
  elmc_free(cell);
  return 1;
}

static int elmc_cmd_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_CMD || value->scalar != ELMC_CMD_CELL_SCALAR) return 0;
  ElmcCmdCell *cell = (ElmcCmdCell *)value;
  if (value->payload != &cell->cmd) return 0;
  elmc_release(cell->cmd.text);
  elmc_free(cell);
  return 1;
}

static int elmc_sub_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_SUB || value->scalar != ELMC_SUB_CELL_SCALAR) return 0;
  ElmcSubCell *cell = (ElmcSubCell *)value;
  if (value->payload != &cell->sub) return 0;
  elmc_free(cell);
  return 1;
}

static int elmc_record_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_RECORD) return 0;
  if (value->scalar == ELMC_RECORD_CELL_SCALAR) {
    ElmcRecordCell *cell = (ElmcRecordCell *)value;
    if (value->payload != &cell->record) return 0;
    elmc_free(cell);
    return 1;
  }
  if (value->scalar == ELMC_NAMED_RECORD_CELL_SCALAR) {
    ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)value;
    if (value->payload != &cell->record) return 0;
    elmc_free(cell);
    return 1;
  }
  return 0;
}

static int elmc_closure_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_CLOSURE || value->scalar != ELMC_CLOSURE_CELL_SCALAR) return 0;
  ElmcClosureCell *cell = (ElmcClosureCell *)value;
  if (value->payload != &cell->closure) return 0;
  elmc_free(cell);
  return 1;
}

static RC elmc_record_cell_alloc(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values, int take) {
  if (field_count < 0) return RC_ERR_INVALID_ARG;
  size_t names_size = sizeof(const char *) * (size_t)field_count;
  size_t values_size = sizeof(ElmcValue *) * (size_t)field_count;
  ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)elmc_malloc(sizeof(ElmcNamedRecordCell) + names_size + values_size, __func__);
  if (!cell) {
    if (take) {
      for (int i = 0; i < field_count; i++) {
        elmc_release(field_values[i]);
      }
    }
    return RC_ERR_OUT_OF_MEMORY;
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
  *out = &cell->value;
  return RC_SUCCESS;
}

static RC elmc_record_cell_alloc_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values, int take) {
  return elmc_record_cell_alloc(out, field_count, (const char **)field_names, field_values, take);
}

static RC elmc_record_cell_alloc_values(ElmcValue **out, int field_count, ElmcValue **field_values, int take) {
  if (field_count < 0) return RC_ERR_INVALID_ARG;
  size_t values_size = sizeof(ElmcValue *) * (size_t)field_count;
  ElmcRecordCell *cell = (ElmcRecordCell *)elmc_malloc(sizeof(ElmcRecordCell) + values_size, __func__);
  if (!cell) {
    if (take) {
      for (int i = 0; i < field_count; i++) {
        elmc_release(field_values[i]);
      }
    }
    return RC_ERR_OUT_OF_MEMORY;
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
  *out = &cell->value;
  return RC_SUCCESS;
}

static const char **elmc_record_field_names(ElmcValue *record) {
  if (!record || record->tag != ELMC_TAG_RECORD || record->scalar != ELMC_NAMED_RECORD_CELL_SCALAR) return NULL;
  ElmcNamedRecordCell *cell = (ElmcNamedRecordCell *)record;
  if (record->payload != &cell->record) return NULL;
  return cell->field_names;
}

RC elmc_list_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_indexed_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);

static ElmcIntListPayload *elmc_int_list_payload(ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_INT_LIST || !list->payload) return NULL;
  return (ElmcIntListPayload *)list->payload;
}

static int elmc_int_list_length_native(ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  return payload ? payload->length : 0;
}

static int elmc_int_list_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_INT_LIST || value->scalar != ELMC_INT_LIST_CELL_SCALAR) return 0;
  if (value == &ELMC_EMPTY_INT_LIST) return 0;
  ElmcIntListCell *cell = (ElmcIntListCell *)value;
  if (value->payload != &cell->data) return 0;
  if (cell->data.owns_buffer && cell->data.values) elmc_free(cell->data.values);
  elmc_free(cell);
  return 1;
}

static RC elmc_int_list_alloc_copy(ElmcValue **out, const elmc_int_t *items, int count) {
  RC rc = RC_SUCCESS;
  ElmcIntListCell *cell = NULL;
  CATCH_BEGIN
    if (count <= 0) {
      *out = elmc_retain(&ELMC_EMPTY_INT_LIST);
    } else {
      cell = (ElmcIntListCell *)elmc_malloc(sizeof(ElmcIntListCell), __func__);
      if (!cell) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      cell->data.values = (elmc_int_t *)elmc_malloc((size_t)count * sizeof(elmc_int_t), __func__);
      if (!cell->data.values) {
        elmc_free(cell);
        cell = NULL;
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      memcpy(cell->data.values, items, (size_t)count * sizeof(elmc_int_t));
      cell->data.length = count;
      cell->data.owns_buffer = 1;
      cell->value.rc = 1;
      cell->value.tag = ELMC_TAG_INT_LIST;
      cell->value.payload = &cell->data;
      cell->value.scalar = ELMC_INT_LIST_CELL_SCALAR;
      ELMC_ALLOCATED += 1;
      ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
      *out = &cell->value;
      cell = NULL;
    }
  CATCH_END;
  if (cell) {
    if (cell->data.values) elmc_free(cell->data.values);
    elmc_free(cell);
  }
  return rc;
}

static RC elmc_int_list_reuse_or_copy(ElmcValue **out, ElmcValue *existing, const elmc_int_t *items, int count) {
  if (existing && existing->tag == ELMC_TAG_INT_LIST && existing->rc == 1) {
    ElmcIntListPayload *payload = elmc_int_list_payload(existing);
    if (payload && payload->owns_buffer && payload->length == count && payload->values && items) {
      memcpy(payload->values, items, (size_t)count * sizeof(elmc_int_t));
      *out = elmc_retain(existing);
      return RC_SUCCESS;
    }
  }
  return elmc_int_list_alloc_copy(out, items, count);
}

static RC elmc_int_list_take_int(ElmcValue **out, elmc_int_t count, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  if (!payload) return RC_ERR_INVALID_ARG;
  if (count <= 0) return elmc_int_list_alloc_copy(out, NULL, 0);
  if (count > payload->length) count = payload->length;
  return elmc_int_list_alloc_copy(out, payload->values, count);
}

static RC elmc_int_list_drop_int(ElmcValue **out, elmc_int_t count, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  if (!payload) return RC_ERR_INVALID_ARG;
  if (count <= 0) {
    *out = elmc_retain(list);
    return RC_SUCCESS;
  }
  if (count >= payload->length) return elmc_int_list_alloc_copy(out, NULL, 0);
  return elmc_int_list_alloc_copy(out, payload->values + count, payload->length - count);
}

static RC __attribute__((unused)) elmc_int_list_append_to_cons_tail(ElmcValue **tail_slot, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  RC rc = RC_SUCCESS;
  ElmcValue *cell = NULL;
  CATCH_BEGIN
    if (!tail_slot) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    if (!payload || payload->length <= 0) {
      *tail_slot = elmc_list_nil();
    } else {
      for (int i = 0; i < payload->length; i++) {
        ElmcValue *head = NULL;
        rc = elmc_new_int(&head, payload->values[i]);
        CHECK_RC(rc);
        cell = NULL;
        rc = elmc_list_cons(&cell, head, elmc_list_nil());
        elmc_release(head);
        CHECK_RC(rc);
        *tail_slot = cell;
        tail_slot = &((ElmcCons *)cell->payload)->tail;
        cell = NULL;
      }
    }
  CATCH_END;
  elmc_release(cell);
  return rc;
}

static RC elmc_int_list_reverse_into(ElmcValue **out, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  RC rc = RC_SUCCESS;
  elmc_int_t *reversed = NULL;
  CATCH_BEGIN
    if (!payload || payload->length <= 0) {
      rc = elmc_int_list_alloc_copy(out, NULL, 0);
      CHECK_RC(rc);
    } else {
      reversed = (elmc_int_t *)elmc_malloc((size_t)payload->length * sizeof(elmc_int_t), __func__);
      if (!reversed) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (int i = 0; i < payload->length; i++) {
        reversed[i] = payload->values[payload->length - 1 - i];
      }
      rc = elmc_int_list_alloc_copy(out, reversed, payload->length);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (reversed) elmc_free(reversed);
  return rc;
}

static RC elmc_int_list_append(ElmcValue **out, ElmcValue *left, ElmcValue *right) {
  ElmcIntListPayload *a = elmc_int_list_payload(left);
  ElmcIntListPayload *b = elmc_int_list_payload(right);
  RC rc = RC_SUCCESS;
  elmc_int_t *merged = NULL;
  CATCH_BEGIN
    if (!a && !b) {
      rc = elmc_int_list_alloc_copy(out, NULL, 0);
      CHECK_RC(rc);
    } else if (!a) {
      *out = elmc_retain(right);
    } else if (!b) {
      *out = elmc_retain(left);
    } else {
      int total = a->length + b->length;
      if (total <= 0) {
        rc = elmc_int_list_alloc_copy(out, NULL, 0);
        CHECK_RC(rc);
      } else {
        merged = (elmc_int_t *)elmc_malloc((size_t)total * sizeof(elmc_int_t), __func__);
        if (!merged) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        memcpy(merged, a->values, (size_t)a->length * sizeof(elmc_int_t));
        memcpy(merged + a->length, b->values, (size_t)b->length * sizeof(elmc_int_t));
        rc = elmc_int_list_alloc_copy(out, merged, total);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  if (merged) elmc_free(merged);
  return rc;
}

static ElmcValue *elmc_int_list_replace_nth_int(ElmcValue *list, elmc_int_t index, elmc_int_t value) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  if (!payload || index < 0 || index >= payload->length) return elmc_retain(list);
  ElmcValue *out = NULL;
  if (elmc_int_list_alloc_copy(&out, payload->values, payload->length) != RC_SUCCESS || !out) {
    return elmc_retain(list);
  }
  ElmcIntListPayload *copy = elmc_int_list_payload(out);
  if (!copy || !copy->values) {
    elmc_release(out);
    return elmc_retain(list);
  }
  copy->values[index] = value;
  return out;
}

static RC elmc_int_list_filter(ElmcValue **out, ElmcValue *predicate, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  RC rc = RC_SUCCESS;
  elmc_int_t *kept = NULL;
  int kept_count = 0;
  CATCH_BEGIN
    if (!payload) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    if (payload->length <= 0) {
      rc = elmc_int_list_alloc_copy(out, NULL, 0);
      CHECK_RC(rc);
    } else {
      kept = (elmc_int_t *)elmc_malloc((size_t)payload->length * sizeof(elmc_int_t), __func__);
      if (!kept) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (int i = 0; i < payload->length; i++) {
        ElmcValue *boxed = NULL;
        rc = elmc_new_int(&boxed, payload->values[i]);
        CHECK_RC(rc);
        ElmcValue *args[1] = { boxed };
        ElmcValue *keep = NULL;
        rc = elmc_closure_call_rc(&keep, predicate, args, 1);
        elmc_release(boxed);
        CHECK_RC(rc);
        if (elmc_as_int(keep)) kept[kept_count++] = payload->values[i];
        elmc_release(keep);
      }
      rc = elmc_int_list_alloc_copy(out, kept, kept_count);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (kept) elmc_free(kept);
  return rc;
}

static int elmc_value_is_boxed_int(ElmcValue *value) {
  return value && (value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL || value->tag == ELMC_TAG_CHAR);
}

RC elmc_int_list_to_cons(ElmcValue **out, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_list_nil();
  ElmcValue *cell = NULL;
  CATCH_BEGIN
    if (!payload) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    for (int i = payload->length - 1; i >= 0; i--) {
      ElmcValue *head = NULL;
      rc = elmc_new_int(&head, payload->values[i]);
      CHECK_RC(rc);
      cell = NULL;
      rc = elmc_list_cons(&cell, head, result);
      elmc_release(head);
      CHECK_RC(rc);
      elmc_release(result);
      result = cell;
      cell = NULL;
    }
    *out = result;
    result = NULL;
  CATCH_END;
  elmc_release(cell);
  elmc_release(result);
  return rc;
}

static RC elmc_int_list_map(ElmcValue **out, ElmcValue *function, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  RC rc = RC_SUCCESS;
  elmc_int_t *mapped = NULL;
  CATCH_BEGIN
    if (!payload) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    if (payload->length <= 0) {
      rc = elmc_int_list_alloc_copy(out, NULL, 0);
      CHECK_RC(rc);
    } else {
      mapped = (elmc_int_t *)elmc_malloc((size_t)payload->length * sizeof(elmc_int_t), __func__);
      if (!mapped) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (int i = 0; i < payload->length; i++) {
        ElmcValue *boxed = NULL;
        rc = elmc_new_int(&boxed, payload->values[i]);
        CHECK_RC(rc);
        ElmcValue *args[1] = { boxed };
        ElmcValue *item = NULL;
        rc = elmc_closure_call_rc(&item, function, args, 1);
        elmc_release(boxed);
        CHECK_RC(rc);
        if (!elmc_value_is_boxed_int(item)) {
          ElmcValue *cons = NULL;
          elmc_release(item);
          rc = elmc_int_list_to_cons(&cons, list);
          CHECK_RC(rc);
          rc = elmc_list_map(out, function, cons);
          elmc_release(cons);
          elmc_free(mapped);
          mapped = NULL;
          return rc;
        }
        mapped[i] = elmc_as_int(item);
        elmc_release(item);
      }
      rc = elmc_int_list_alloc_copy(out, mapped, payload->length);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (mapped) elmc_free(mapped);
  return rc;
}

static RC elmc_int_list_foldl(ElmcValue **out, ElmcValue *function, ElmcValue *acc, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(acc);
  CATCH_BEGIN
    if (!payload) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    for (int i = 0; i < payload->length; i++) {
      ElmcValue *boxed = NULL;
      ElmcValue *next = NULL;
      rc = elmc_new_int(&boxed, payload->values[i]);
      CHECK_RC(rc);
      ElmcValue *args[2] = { boxed, result };
      rc = elmc_closure_call_rc(&next, function, args, 2);
      elmc_release(boxed);
      elmc_release(result);
      CHECK_RC(rc);
      if (!elmc_value_is_boxed_int(next)) {
        ElmcValue *cons = NULL;
        elmc_release(next);
        rc = elmc_int_list_to_cons(&cons, list);
        CHECK_RC(rc);
        rc = elmc_list_foldl(out, function, acc, cons);
        elmc_release(cons);
        return rc;
      }
      result = next;
    }
    *out = result;
    result = NULL;
  CATCH_END;
  elmc_release(result);
  return rc;
}

static RC elmc_int_list_indexed_map(ElmcValue **out, ElmcValue *function, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  RC rc = RC_SUCCESS;
  elmc_int_t *mapped = NULL;
  CATCH_BEGIN
    if (!payload) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    if (payload->length <= 0) {
      rc = elmc_int_list_alloc_copy(out, NULL, 0);
      CHECK_RC(rc);
    } else {
      mapped = (elmc_int_t *)elmc_malloc((size_t)payload->length * sizeof(elmc_int_t), __func__);
      if (!mapped) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (int i = 0; i < payload->length; i++) {
        ElmcValue *boxed_value = NULL;
        ElmcValue *boxed_index = NULL;
        rc = elmc_new_int(&boxed_value, payload->values[i]);
        CHECK_RC(rc);
        rc = elmc_new_int(&boxed_index, i);
        CHECK_RC(rc);
        ElmcValue *args[2] = { boxed_index, boxed_value };
        ElmcValue *item = NULL;
        rc = elmc_closure_call_rc(&item, function, args, 2);
        elmc_release(boxed_value);
        elmc_release(boxed_index);
        CHECK_RC(rc);
        if (!elmc_value_is_boxed_int(item)) {
          ElmcValue *cons = NULL;
          elmc_release(item);
          rc = elmc_int_list_to_cons(&cons, list);
          CHECK_RC(rc);
          rc = elmc_list_indexed_map(out, function, cons);
          elmc_release(cons);
          elmc_free(mapped);
          mapped = NULL;
          return rc;
        }
        mapped[i] = elmc_as_int(item);
        elmc_release(item);
      }
      rc = elmc_int_list_alloc_copy(out, mapped, payload->length);
      CHECK_RC(rc);
    }
  CATCH_END;
  if (mapped) elmc_free(mapped);
  return rc;
}

int elmc_int_list_is_empty(ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  return !payload || payload->length <= 0;
}

RC elmc_int_list_head_boxed(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (list && list->tag == ELMC_TAG_LIST && list->payload != NULL) {
      ElmcCons *node = (ElmcCons *)list->payload;
      *out = node->head ? elmc_retain(node->head) : elmc_int_zero();
    } else {
      ElmcIntListPayload *payload = elmc_int_list_payload(list);
      if (!payload || payload->length <= 0) {
        *out = elmc_int_zero();
      } else {
        rc = elmc_new_int(out, payload->values[0]);
        CHECK_RC(rc);
      }
    }
  CATCH_END;
  return rc;
}

RC elmc_int_list_tail(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (list && list->tag == ELMC_TAG_LIST) {
      if (list->payload == NULL) {
        *out = elmc_list_nil();
      } else {
        ElmcCons *node = (ElmcCons *)list->payload;
        *out = node->tail ? elmc_retain(node->tail) : elmc_list_nil();
      }
    } else {
      rc = elmc_int_list_drop_int(out, 1, list);
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}
RC elmc_int_list_to_spine(ElmcValue **out, ElmcValue *list) {
  ElmcIntListPayload *payload = elmc_int_list_payload(list);
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_list_nil();
  ElmcIntSpineCell *cell = NULL;
  CATCH_BEGIN
    if (!payload) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    if (payload->length <= 0) {
      *out = result;
      result = NULL;
    } else {
      for (int i = payload->length - 1; i >= 0; i--) {
        cell = (ElmcIntSpineCell *)elmc_malloc(sizeof(ElmcIntSpineCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->spine.head = payload->values[i];
        cell->spine.tail = result;
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_INT_SPINE;
        cell->value.payload = &cell->spine;
        cell->value.scalar = ELMC_INT_SPINE_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        elmc_release(result);
        result = &cell->value;
        cell = NULL;
      }
      *out = result;
      result = NULL;
    }
  CATCH_END;
  if (cell) elmc_free(cell);
  elmc_release(result);
  return rc;
}

static int elmc_int_spine_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_INT_SPINE || value->scalar != ELMC_INT_SPINE_CELL_SCALAR) return 0;
  ElmcIntSpineCell *cell = (ElmcIntSpineCell *)value;
  if (value->payload != &cell->spine) return 0;
  elmc_release(cell->spine.tail);
  elmc_free(cell);
  return 1;
}

int elmc_int_spine_is_empty(ElmcValue *list) {
  return !list || list->tag != ELMC_TAG_INT_SPINE || list->payload == NULL;
}

RC elmc_int_spine_head_boxed(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_INT_SPINE || !list->payload) {
      *out = elmc_int_zero();
    } else {
      rc = elmc_new_int(out, ((ElmcIntSpine *)list->payload)->head);
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

RC elmc_int_spine_tail(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (!list || list->tag != ELMC_TAG_INT_SPINE || !list->payload) {
      *out = elmc_int_zero();
    } else {
      *out = elmc_retain(((ElmcIntSpine *)list->payload)->tail);
    }
  CATCH_END;
  return rc;
}

static ElmcFloatListPayload *elmc_float_list_payload(ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_FLOAT_LIST || !list->payload) return NULL;
  return (ElmcFloatListPayload *)list->payload;
}

static int elmc_float_list_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_FLOAT_LIST || value->scalar != ELMC_FLOAT_LIST_CELL_SCALAR) return 0;
  ElmcFloatListCell *cell = (ElmcFloatListCell *)value;
  if (value->payload != &cell->data) return 0;
  if (cell->data.owns_buffer && cell->data.values) elmc_free(cell->data.values);
  elmc_free(cell);
  return 1;
}

int elmc_float_list_is_empty(ElmcValue *list) {
  ElmcFloatListPayload *payload = elmc_float_list_payload(list);
  return !payload || payload->length <= 0;
}

static RC elmc_float_list_alloc_copy(ElmcValue **out, const double *items, int count) {
  RC rc = RC_SUCCESS;
  ElmcFloatListCell *cell = NULL;
  CATCH_BEGIN
    if (!items || count <= 0) {
      *out = elmc_list_nil();
    } else {
      cell = (ElmcFloatListCell *)elmc_malloc(sizeof(ElmcFloatListCell), __func__);
      if (!cell) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      cell->data.values = (double *)elmc_malloc((size_t)count * sizeof(double), __func__);
      if (!cell->data.values) {
        elmc_free(cell);
        cell = NULL;
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      memcpy(cell->data.values, items, (size_t)count * sizeof(double));
      cell->data.length = count;
      cell->data.owns_buffer = 1;
      cell->value.rc = 1;
      cell->value.tag = ELMC_TAG_FLOAT_LIST;
      cell->value.payload = &cell->data;
      cell->value.scalar = ELMC_FLOAT_LIST_CELL_SCALAR;
      ELMC_ALLOCATED += 1;
      ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
      *out = &cell->value;
      cell = NULL;
    }
  CATCH_END;
  if (cell) {
    if (cell->data.values) elmc_free(cell->data.values);
    elmc_free(cell);
  }
  return rc;
}

RC elmc_list_from_float_array(ElmcValue **out, const double *items, int count) {
  return elmc_float_list_alloc_copy(out, items, count);
}

static RC elmc_float_list_drop(ElmcValue **out, int count, ElmcValue *list) {
  ElmcFloatListPayload *payload = elmc_float_list_payload(list);
  if (!payload || count <= 0) {
    *out = elmc_retain(list);
    return RC_SUCCESS;
  }
  if (count >= payload->length) {
    *out = elmc_list_nil();
    return RC_SUCCESS;
  }
  return elmc_float_list_alloc_copy(out, payload->values + count, payload->length - count);
}

RC elmc_float_list_head_boxed(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    ElmcFloatListPayload *payload = elmc_float_list_payload(list);
    if (!payload || payload->length <= 0) {
      *out = elmc_int_zero();
    } else {
      rc = elmc_new_float(out, payload->values[0]);
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

RC elmc_float_list_tail(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_float_list_drop(out, 1, list);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

static ElmcRecordSeqPayload *elmc_record_seq_payload(ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_RECORD_SEQ || !list->payload) return NULL;
  return (ElmcRecordSeqPayload *)list->payload;
}

static int elmc_record_seq_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_RECORD_SEQ || value->scalar != ELMC_RECORD_SEQ_CELL_SCALAR) return 0;
  ElmcRecordSeqCell *cell = (ElmcRecordSeqCell *)value;
  if (value->payload != &cell->data) return 0;
  if (cell->data.owns_buffer && cell->data.items) {
    for (int i = 0; i < cell->data.length; i++) {
      if (cell->data.items[i]) elmc_release(cell->data.items[i]);
    }
    elmc_free(cell->data.items);
  }
  elmc_free(cell);
  return 1;
}

int elmc_record_seq_is_empty(ElmcValue *list) {
  ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
  return !payload || payload->length <= 0;
}

int elmc_record_seq_length(ElmcValue *list) {
  ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
  return payload ? payload->length : 0;
}

ElmcValue *elmc_record_seq_get(ElmcValue *list, elmc_int_t index) {
  ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
  if (!payload || index < 0 || index >= payload->length) return elmc_int_zero();
  return elmc_retain(payload->items[index]);
}

static RC elmc_record_seq_alloc_copy(ElmcValue **out, ElmcValue **items, int count) {
  RC rc = RC_SUCCESS;
  ElmcRecordSeqCell *cell = NULL;
  CATCH_BEGIN
    if (!items || count <= 0) {
      *out = elmc_list_nil();
    } else {
      cell = (ElmcRecordSeqCell *)elmc_malloc(sizeof(ElmcRecordSeqCell), __func__);
      if (!cell) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      cell->data.items = (ElmcValue **)elmc_malloc((size_t)count * sizeof(ElmcValue *), __func__);
      if (!cell->data.items) {
        elmc_free(cell);
        cell = NULL;
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      for (int i = 0; i < count; i++) {
        cell->data.items[i] = items[i] ? elmc_retain(items[i]) : elmc_int_zero();
      }
      cell->data.length = count;
      cell->data.owns_buffer = 1;
      cell->value.rc = 1;
      cell->value.tag = ELMC_TAG_RECORD_SEQ;
      cell->value.payload = &cell->data;
      cell->value.scalar = ELMC_RECORD_SEQ_CELL_SCALAR;
      ELMC_ALLOCATED += 1;
      ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
      *out = &cell->value;
      cell = NULL;
    }
  CATCH_END;
  if (cell) {
    if (cell->data.items) elmc_free(cell->data.items);
    elmc_free(cell);
  }
  return rc;
}

RC elmc_list_from_record_array(ElmcValue **out, ElmcValue **items, int count) {
  return elmc_record_seq_alloc_copy(out, items, count);
}

RC elmc_record_seq_to_cons(ElmcValue **out, ElmcValue *list) {
  ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!payload || payload->length <= 0) {
      *out = result;
      result = NULL;
    } else {
      for (int i = payload->length - 1; i >= 0; i--) {
        next = NULL;
        rc = elmc_list_cons(&next, payload->items[i], result);
        CHECK_RC(rc);
        elmc_release(result);
        result = next;
        next = NULL;
      }
      *out = result;
      result = NULL;
    }
  CATCH_END;
  elmc_release(next);
  elmc_release(result);
  return rc;
}

static RC elmc_record_seq_drop(ElmcValue **out, int count, ElmcValue *list) {
  ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
  if (!payload || count <= 0) {
    *out = elmc_retain(list);
    return RC_SUCCESS;
  }
  if (count >= payload->length) {
    *out = elmc_list_nil();
    return RC_SUCCESS;
  }
  return elmc_record_seq_alloc_copy(out, payload->items + count, payload->length - count);
}

RC elmc_record_seq_head_boxed(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
    if (!payload || payload->length <= 0) {
      *out = elmc_int_zero();
    } else {
      *out = elmc_retain(payload->items[0]);
    }
  CATCH_END;
  return rc;
}

RC elmc_record_seq_tail(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_record_seq_drop(out, 1, list);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}


static RC elmc_list_materialize_cons(ElmcValue **out, ElmcValue *list) {
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_to_cons(out, list);
  }
  if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
    return elmc_record_seq_to_cons(out, list);
  }
  *out = elmc_retain(list);
  return RC_SUCCESS;
}

static RC elmc_list_reverse_into(ElmcValue **out, ElmcValue *list) {
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_reverse_into(out, list);
  }
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
      *out = rev;
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
      *out = small;
    } else {
      rc = elmc_alloc_scalar(out, ELMC_TAG_INT, value);
      CHECK_RC(rc);
    }
  CATCH_END;
  return rc;
}

RC elmc_new_bool(ElmcValue **out, int value) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    *out = value ? &ELMC_BOOL_TRUE : &ELMC_BOOL_FALSE;
  CATCH_END;
  return rc;
}

ElmcValue *elmc_new_char(elmc_int_t value) {
  ElmcValue *out = NULL;
  if (elmc_alloc_scalar(&out, ELMC_TAG_CHAR, value) != RC_SUCCESS) return elmc_int_zero();
  return out;
}

static elmc_int_t elmc_char_normalize_code(elmc_int_t code) {
  if (code < 0 || code > 0x10FFFF) return 0xFFFD;
  if (code >= 0xD800 && code <= 0xDFFF) return 0xFFFD;
  return code;
}

ElmcValue *elmc_char_from_code_int(elmc_int_t code) {
  return elmc_new_char(elmc_char_normalize_code(code));
}

ElmcValue *elmc_char_from_code(ElmcValue *code) {
  return elmc_char_from_code_int(code ? elmc_as_int(code) : 0);
}

RC elmc_new_order(ElmcValue **out, elmc_int_t value) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_alloc_scalar(out, ELMC_TAG_ORDER, value);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_new_string(ElmcValue **out, const char *value) {
  RC rc = RC_SUCCESS;
  char *ptr = NULL;
  CATCH_BEGIN
    if (!value) {
      *out = &ELMC_EMPTY_STRING;
    } else {
      size_t len = strlen(value);
      ptr = (char *)elmc_malloc(len + 1, __func__);
      if (!ptr) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      if (len > 0) memcpy(ptr, value, len);
      ptr[len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, ptr);
      ptr = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      allocated->scalar = (elmc_int_t)len;
      *out = allocated;
    }
  CATCH_END;
  if (ptr) elmc_free(ptr);
  return rc;
}

static size_t elmc_string_byte_len(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_STRING || !value->payload) return 0;
  if (value->scalar > 0) return (size_t)value->scalar;
  return strlen((const char *)value->payload);
}

static const void *elmc_memmem(const void *haystack, size_t hay_len, const void *needle, size_t needle_len) {
  const unsigned char *h = (const unsigned char *)haystack;
  const unsigned char *n = (const unsigned char *)needle;
  if (!h || !n) return NULL;
  if (needle_len == 0) return h;
  if (needle_len > hay_len) return NULL;
  for (size_t i = 0; i + needle_len <= hay_len; i++) {
    if (memcmp(h + i, n, needle_len) == 0) return h + i;
  }
  return NULL;
}

RC elmc_new_string_len(ElmcValue **out, const char *value, size_t len) {
  RC rc = RC_SUCCESS;
  char *ptr = NULL;
  CATCH_BEGIN
    if (!value || len == 0) {
      *out = &ELMC_EMPTY_STRING;
    } else {
      ptr = (char *)elmc_malloc(len + 1, __func__);
      if (!ptr) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      memcpy(ptr, value, len);
      ptr[len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, ptr);
      ptr = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      allocated->scalar = (elmc_int_t)len;
      *out = allocated;
    }
  CATCH_END;
  if (ptr) elmc_free(ptr);
  return rc;
}

ElmcValue *elmc_list_nil(void) {
  return &ELMC_LIST_NIL;
}

RC elmc_list_cons(ElmcValue **out, ElmcValue *head, ElmcValue *tail) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_list_cell_alloc(out, head, tail, 0);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

ElmcValue *elmc_list_cons_take(ElmcValue *head, ElmcValue *tail) {
  ElmcValue *out = NULL;
  if (elmc_list_cell_alloc(&out, head, tail, 1) != RC_SUCCESS) {
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
      *out = list;
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
      *out = list;
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
      *out = list;
      list = NULL;
    } else {
      for (int i = count - 1; i >= 0; i--) {
        next = NULL;
        rc = elmc_list_cell_alloc(&next, items[i], list, 1);
        CHECK_RC(rc);
        list = next;
        next = NULL;
      }
      *out = list;
      list = NULL;
    }
  CATCH_END;
  elmc_release(next);
  elmc_release(list);
  return rc;
}

RC elmc_list_from_int_array(ElmcValue **out, const elmc_int_t *items, int count) {
  return elmc_int_list_alloc_copy(out, items, count);
}

RC elmc_list_from_int_array_reuse(ElmcValue **out, ElmcValue *existing, const elmc_int_t *items, int count) {
  return elmc_int_list_reuse_or_copy(out, existing, items, count);
}

RC elmc_list_from_tuple2_int_array(ElmcValue **out, const elmc_int_t items[][2], int count) {
  RC rc = RC_SUCCESS;
  ElmcValue *list = elmc_list_nil();
  ElmcValue *item = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!items || count <= 0) {
      *out = list;
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
      *out = list;
      list = NULL;
    }
  CATCH_END;
  elmc_release(item);
  elmc_release(next);
  elmc_release(list);
  return rc;
}

ElmcValue *elmc_list_replace_nth_int(ElmcValue *list, elmc_int_t index, elmc_int_t value) {
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_replace_nth_int(list, index, value);
  }
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
    *out = &cell->value;
    cell = NULL;
  CATCH_END;
  if (cell) elmc_release(&cell->value);
  return rc;
}

RC elmc_maybe_just_own(ElmcValue **out, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  ElmcMaybeCell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcMaybeCell *)elmc_malloc(sizeof(ElmcMaybeCell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    cell->maybe.is_just = 1;
    cell->maybe.value = value;
    cell->value.rc = 1;
    cell->value.tag = ELMC_TAG_MAYBE;
    cell->value.payload = &cell->maybe;
    cell->value.scalar = ELMC_MAYBE_CELL_SCALAR;
    ELMC_ALLOCATED += 1;
    ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
    *out = &cell->value;
    cell = NULL;
  CATCH_END;
  if (cell) {
    elmc_release(value);
    elmc_release(&cell->value);
  }
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
    *out = &cell->value;
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
    *out = &cell->value;
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
    *out = &cell->value;
    cell = NULL;
  CATCH_END;
  if (cell) elmc_release(&cell->value);
  return rc;
}

RC elmc_tuple2_take(ElmcValue **out, ElmcValue *first, ElmcValue *second) {
  RC rc = RC_SUCCESS;
  ElmcTuple2Cell *cell = NULL;
  CATCH_BEGIN
    if (out && *out && *out != first && *out != second) {
      elmc_release(*out);
    }
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
    *out = &cell->value;
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

ElmcValue *elmc_build_constructor_payload(ElmcValue **values, int count) {
  if (!values || count <= 0) return elmc_int_zero();
  if (count == 1) return values[0] ? elmc_retain(values[0]) : elmc_int_zero();
  ElmcValue *tail = elmc_build_constructor_payload(values + 1, count - 1);
  if (!tail) return elmc_int_zero();
  ElmcValue *left = values[0] ? elmc_retain(values[0]) : elmc_int_zero();
  ElmcValue *out = elmc_tuple2_take_value(left, tail);
  return out ? out : elmc_int_zero();
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

static RC elmc_cmd_alloc(ElmcValue **out, uint8_t arity, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
  RC rc = RC_SUCCESS;
  ElmcCmdCell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcCmdCell *)elmc_malloc(sizeof(ElmcCmdCell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
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
    *out = &cell->value;
    cell = NULL;
  CATCH_END
  if (cell) elmc_free(cell);
  return rc;
}

RC elmc_cmd0(ElmcValue **out, elmc_int_t kind) {
  return elmc_cmd_alloc(out, 0, kind, 0, 0, 0, 0, 0, 0);
}

static ElmcValue *elmc_platform_manager_tag(elmc_int_t tag_num) {
  ElmcValue *tag = elmc_small_int(tag_num);
  if (tag) return tag;
  ElmcValue *out = NULL;
  if (elmc_alloc_scalar(&out, ELMC_TAG_INT, tag_num) != RC_SUCCESS) return elmc_int_zero();
  return out;
}

static ElmcValue *elmc_platform_manager_port(ElmcValue *key, ElmcValue *leaf) {
  static const char *names[] = {"$", "k", "l"};
  ElmcValue *empty_key = NULL;
  if (!key && elmc_new_string(&empty_key, "") != RC_SUCCESS) empty_key = NULL;
  ElmcValue *values[3] = {
    elmc_platform_manager_tag(1),
    key ? elmc_retain(key) : (empty_key ? empty_key : elmc_int_zero()),
    leaf ? elmc_retain(leaf) : elmc_int_zero()
  };
  return elmc_record_new_static_take_value(3, names, values);
}

static ElmcValue *elmc_platform_manager_batch(elmc_int_t tag_num, ElmcValue *items) {
  static const char *names[] = {"$", "m"};
  ElmcValue *list = items ? elmc_retain(items) : elmc_list_nil();
  ElmcValue *values[2] = {elmc_platform_manager_tag(tag_num), list};
  return elmc_record_new_static_take_value(2, names, values);
}

static ElmcValue *elmc_platform_manager_map(elmc_int_t tag_num, ElmcValue *fn, ElmcValue *inner) {
  static const char *names[] = {"$", "n", "o"};
  ElmcValue *values[3] = {
    elmc_platform_manager_tag(tag_num),
    fn ? elmc_retain(fn) : elmc_int_zero(),
    inner ? elmc_retain(inner) : elmc_int_zero()
  };
  return elmc_record_new_static_take_value(3, names, values);
}

static int elmc_list_all_tag(ElmcValue *list, elmc_int_t tag) {
  ElmcValue *cursor = list;
  int saw_any = 0;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (!node->head) return saw_any;
    if (node->head->tag != tag) return 0;
    saw_any = 1;
    cursor = node->tail;
  }
  return saw_any;
}

static ElmcValue *elmc_cmd_batch_push_back(ElmcValue *flat, ElmcValue *entry) {
  if (!entry) return flat;
  ElmcValue *cell = NULL;
  if (elmc_list_cons(&cell, entry, elmc_list_nil()) != RC_SUCCESS) return flat;
  if (!flat || (flat->tag == ELMC_TAG_LIST && flat->payload == NULL)) {
    elmc_release(flat);
    return cell;
  }
  if (flat->tag != ELMC_TAG_LIST) {
    elmc_release(cell);
    return flat;
  }
  ElmcValue **tail = &flat;
  ElmcValue *cursor = flat;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    tail = &node->tail;
    cursor = node->tail;
  }
  *tail = cell;
  return flat;
}

static ElmcValue *elmc_cmd_batch_append_entry(ElmcValue *flat, ElmcValue *entry) {
  if (!entry) return flat;
  if (entry->tag == ELMC_TAG_CMD) {
    return elmc_cmd_batch_push_back(flat, entry);
  }
  if (entry->tag == ELMC_TAG_LIST) {
    ElmcValue *cursor = entry;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      flat = elmc_cmd_batch_append_entry(flat, node->head);
      cursor = node->tail;
    }
    return flat;
  }
  return elmc_cmd_batch_push_back(flat, entry);
}

ElmcValue *elmc_cmd_batch(ElmcValue *commands) {
  if (!commands) return elmc_list_nil();
  if (commands->tag == ELMC_TAG_CMD) {
    ElmcValue *next = NULL;
    if (elmc_list_cons(&next, commands, elmc_list_nil()) != RC_SUCCESS) return elmc_list_nil();
    return next;
  }
  if (commands->tag != ELMC_TAG_LIST) {
    return elmc_platform_manager_batch(2, commands);
  }
  if (elmc_list_all_tag(commands, ELMC_TAG_CMD)) {
    return elmc_retain(commands);
  }

  ElmcValue *flat = elmc_cmd_batch_append_entry(NULL, commands);
  if (elmc_list_all_tag(flat, ELMC_TAG_CMD)) {
    return flat ? flat : elmc_list_nil();
  }
  if (flat) elmc_release(flat);
  return elmc_platform_manager_batch(2, commands);
}

ElmcValue *elmc_cmd_map(ElmcValue *f, ElmcValue *cmd) {
  if (cmd && cmd->tag == ELMC_TAG_CMD) {
    return cmd ? elmc_retain(cmd) : elmc_int_zero();
  }
  return elmc_platform_manager_map(3, f, cmd);
}

ElmcValue *elmc_sub_batch(ElmcValue *subs) {
  if (elmc_list_all_tag(subs, ELMC_TAG_SUB)) {
    return subs ? elmc_retain(subs) : elmc_list_nil();
  }
  return elmc_platform_manager_batch(2, subs);
}

ElmcValue *elmc_sub_map(ElmcValue *f, ElmcValue *sub) {
  if (sub && sub->tag == ELMC_TAG_SUB) {
    return sub ? elmc_retain(sub) : elmc_int_zero();
  }
  return elmc_platform_manager_map(3, f, sub);
}

ElmcValue *elmc_port_outgoing(ElmcValue *port_name, ElmcValue *payload) {
  return elmc_platform_manager_port(port_name, payload);
}

ElmcValue *elmc_port_incoming_sub(ElmcValue *port_name, ElmcValue *callback) {
  return elmc_platform_manager_port(port_name, callback);
}

RC elmc_cmd1(ElmcValue **out, elmc_int_t kind, elmc_int_t p0) {
  return elmc_cmd_alloc(out, 1, kind, p0, 0, 0, 0, 0, 0);
}

RC elmc_cmd1_string(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, const char *text) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_cmd_alloc(out, 1, kind, p0, 0, 0, 0, 0, 0);
    CHECK_RC(rc);
    if (!*out || (*out)->tag != ELMC_TAG_CMD || !(*out)->payload) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    ElmcCmdPayload *cmd = (ElmcCmdPayload *)(*out)->payload;
    rc = elmc_new_string(&cmd->text, text ? text : "");
    CHECK_RC(rc);
  CATCH_END
  if (rc != RC_SUCCESS && out && *out) {
    elmc_release(*out);
    *out = NULL;
  }
  return rc;
}

RC elmc_cmd2(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1) {
  return elmc_cmd_alloc(out, 2, kind, p0, p1, 0, 0, 0, 0);
}

RC elmc_cmd3(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
  return elmc_cmd_alloc(out, 3, kind, p0, p1, p2, 0, 0, 0);
}

RC elmc_cmd4(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
  return elmc_cmd_alloc(out, 4, kind, p0, p1, p2, p3, 0, 0);
}

RC elmc_cmd5(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
  return elmc_cmd_alloc(out, 5, kind, p0, p1, p2, p3, p4, 0);
}

static RC elmc_sub_alloc(ElmcValue **out, uint8_t arity, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
  RC rc = RC_SUCCESS;
  ElmcSubCell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcSubCell *)elmc_malloc(sizeof(ElmcSubCell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
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
    *out = &cell->value;
    cell = NULL;
  CATCH_END
  if (cell) elmc_free(cell);
  return rc;
}

RC elmc_sub0(ElmcValue **out, elmc_int_t mask) {
  return elmc_sub_alloc(out, 0, mask, 0, 0, 0, 0, 0, 0);
}

RC elmc_sub1(ElmcValue **out, elmc_int_t mask, elmc_int_t p0) {
  return elmc_sub_alloc(out, 1, mask, p0, 0, 0, 0, 0, 0);
}

RC elmc_sub2(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1) {
  return elmc_sub_alloc(out, 2, mask, p0, p1, 0, 0, 0, 0);
}

RC elmc_sub3(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
  return elmc_sub_alloc(out, 3, mask, p0, p1, p2, 0, 0, 0);
}

RC elmc_sub4(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
  return elmc_sub_alloc(out, 4, mask, p0, p1, p2, p3, 0, 0);
}

RC elmc_sub5(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
  return elmc_sub_alloc(out, 5, mask, p0, p1, p2, p3, p4, 0);
}

elmc_int_t elmc_as_int(ElmcValue *value) {
  if (!value || (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL && value->tag != ELMC_TAG_CHAR && value->tag != ELMC_TAG_ORDER)) return 0;
  if (value->tag == ELMC_TAG_INT && value->scalar == ELMC_UNIT_SCALAR) return 0;
  return value->scalar;
}

elmc_int_t elmc_as_int_number(ElmcValue *value) {
  if (!value) return 0;
  if (value->tag == ELMC_TAG_FLOAT) return (elmc_int_t)elmc_as_float(value);
  return elmc_as_int(value);
}

int elmc_value_is_unit(ElmcValue *value) {
  return value && value->tag == ELMC_TAG_INT && value->scalar == ELMC_UNIT_SCALAR;
}

elmc_int_t elmc_int_idiv(elmc_int_t numerator, elmc_int_t denominator) {
  if (denominator == 0) return 0;
  elmc_int_t quotient = numerator / denominator;
  elmc_int_t remainder = numerator % denominator;
  if (remainder != 0 && ((numerator < 0) != (denominator < 0))) {
    return quotient - 1;
  }
  return quotient;
}

elmc_int_t elmc_polar_point_x(elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle) {
  double theta = (double)angle * 2.0 * 3.14159265358979323846 / 65536.0;
  (void)cy;
  return cx + (elmc_int_t)lround(sin(theta) * (double)radius);
}

elmc_int_t elmc_polar_point_y(elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle) {
  double theta = (double)angle * 2.0 * 3.14159265358979323846 / 65536.0;
  (void)cx;
  return cy - (elmc_int_t)lround(cos(theta) * (double)radius);
}

elmc_int_t elmc_as_bool(ElmcValue *value) {
  return elmc_as_int(value) != 0;
}

int elmc_list_equal_int(ElmcValue *left, ElmcValue *right) {
  if (left == right) return 1;
  if (left && left->tag == ELMC_TAG_INT_LIST && right && right->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *a = elmc_int_list_payload(left);
    ElmcIntListPayload *b = elmc_int_list_payload(right);
    if (!a || !b) return a == b;
    if (a->length != b->length) return 0;
    for (int i = 0; i < a->length; i++) {
      if (a->values[i] != b->values[i]) return 0;
    }
    return 1;
  }
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
    if ((left->tag == ELMC_TAG_INT || left->tag == ELMC_TAG_BOOL ||
         left->tag == ELMC_TAG_CHAR || left->tag == ELMC_TAG_ORDER) &&
        (right->tag == ELMC_TAG_INT || right->tag == ELMC_TAG_BOOL ||
         right->tag == ELMC_TAG_CHAR || right->tag == ELMC_TAG_ORDER)) {
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
    case ELMC_TAG_CHAR:
    case ELMC_TAG_ORDER:
      return elmc_as_int(left) == elmc_as_int(right);

    case ELMC_TAG_FLOAT:
      return elmc_as_float(left) == elmc_as_float(right);

    case ELMC_TAG_STRING:
      if (!left->payload || !right->payload) return left->payload == right->payload;
      {
        size_t left_len = elmc_string_byte_len(left);
        size_t right_len = elmc_string_byte_len(right);
        if (left_len != right_len) return 0;
        return memcmp(left->payload, right->payload, left_len) == 0;
      }

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

    case ELMC_TAG_INT_LIST: {
      if (left->tag != ELMC_TAG_INT_LIST || right->tag != ELMC_TAG_INT_LIST) return 0;
      ElmcIntListPayload *a = elmc_int_list_payload(left);
      ElmcIntListPayload *b = elmc_int_list_payload(right);
      if (!a || !b) return a == b;
      if (a->length != b->length) return 0;
      for (int i = 0; i < a->length; i++) {
        if (a->values[i] != b->values[i]) return 0;
      }
      return 1;
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
  return (int)elmc_string_byte_len(value);
}

ElmcValue *elmc_list_head(ElmcValue *list) {
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *payload = elmc_int_list_payload(list);
    if (!payload || payload->length <= 0) return elmc_maybe_nothing();
    {
      ElmcValue *boxed = elmc_new_int_take(payload->values[0]);
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_maybe_just(&_elmc_rc_out, boxed) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
  }
  if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
    if (elmc_record_seq_is_empty(list)) return elmc_maybe_nothing();
    {
      ElmcValue *head = elmc_record_seq_get(list, 0);
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_maybe_just(&_elmc_rc_out, head) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
  }
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *payload = elmc_int_list_payload(list);
    if (!payload || idx < 0 || idx >= payload->length) return elmc_maybe_nothing();
    {
      ElmcValue *boxed = elmc_new_int_take(payload->values[idx]);
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_maybe_just(&_elmc_rc_out, boxed) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
    }
  }
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *payload = elmc_int_list_payload(list);
    if (!payload || index < 0 || index >= payload->length) return default_value;
    return payload->values[index];
  }
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *payload = elmc_int_list_payload(list);
    if (!payload || payload->length <= 0) return default_val;
    return payload->values[0];
  }
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
  ElmcValue *cmp = elmc_basics_compare_take(left, right);
  int take_left = elmc_as_int(cmp) >= 0;
  elmc_release(cmp);
  return take_left ? elmc_retain(left) : elmc_retain(right);
}

ElmcValue *elmc_basics_min(ElmcValue *left, ElmcValue *right) {
  ElmcValue *cmp = elmc_basics_compare_take(left, right);
  int take_left = elmc_as_int(cmp) <= 0;
  elmc_release(cmp);
  return take_left ? elmc_retain(left) : elmc_retain(right);
}

ElmcValue *elmc_basics_clamp(ElmcValue *low, ElmcValue *high, ElmcValue *value) {
  ElmcValue *below = elmc_basics_compare_take(value, low);
  if (elmc_as_int(below) < 0) {
    elmc_release(below);
    return elmc_retain(low);
  }
  elmc_release(below);

  ElmcValue *above = elmc_basics_compare_take(value, high);
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
  uint32_t raw = (uint32_t)(int32_t)elmc_as_int(value);
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

static RC elmc_debug_append_cstr(ElmcValue **out, const char *piece);
static char *elmc_debug_escape_string(const char *str);
static int elmc_utf8_encode_codepoint(uint32_t cp, char *out, size_t cap);
static int elmc_utf8_decode_codepoint(const unsigned char **p, const unsigned char *end, uint32_t *cp_out);
static size_t elmc_utf8_codepoint_count(const char *src);
static const char *elmc_utf8_byte_offset_at_codepoint(const char *src, int64_t index);
static RC elmc_rc_assign_new_char(ElmcValue **out, elmc_int_t code);
static RC elmc_debug_append_char(ElmcValue **out, elmc_int_t code);
static RC elmc_debug_format_into(ElmcValue **out, ElmcValue *value);
const char *elmc_debug_union_ctor_name(elmc_int_t tag);
static RC elmc_debug_format_union_payload(ElmcValue **out, const char *ctor_name, ElmcValue *payload);
static int elmc_is_task_result(ElmcValue *value);
static const char *elmc_task_debug_ctor_name(ElmcValue *value);
static ElmcValue *elmc_task_wrap(ElmcValue *value, elmc_int_t task_scalar);
static ElmcValue *elmc_task_wrap_pair(ElmcValue *f, ElmcValue *task, elmc_int_t task_scalar);

static RC elmc_debug_append_cstr(ElmcValue **out, const char *piece) {
  if (!piece) piece = "";
  if (!*out) return elmc_new_string(out, piece);
  const char *existing =
    ((*out)->tag == ELMC_TAG_STRING && (*out)->payload) ? (const char *)(*out)->payload : "";
  ElmcValue *next = NULL;
  RC rc = elmc_string_append_native(&next, existing, piece);
  if (rc == RC_SUCCESS) {
    elmc_release(*out);
    *out = next;
  }
  return rc;
}

static RC elmc_debug_append_float(ElmcValue **out, double value) {
  char buffer[64];
  if (value != value) {
    return elmc_debug_append_cstr(out, "nan");
  }
  if (value > 1e308 || value < -1e308) {
    return elmc_debug_append_cstr(out, value < 0.0 ? "-Infinity" : "Infinity");
  }
  snprintf(buffer, sizeof(buffer), "%.6g", value);
  return elmc_debug_append_cstr(out, buffer);
}

static char *elmc_debug_escape_string(const char *str) {
  if (!str) str = "";
  size_t len = strlen(str);
  char *buf = (char *)elmc_malloc(len * 2 + 4, __func__);
  if (!buf) return NULL;
  char *out = buf;
  *out++ = '"';
  for (const char *p = str; *p; p++) {
    switch (*p) {
      case '\\': *out++ = '\\'; *out++ = '\\'; break;
      case '"': *out++ = '\\'; *out++ = '"'; break;
      case '\n': *out++ = '\\'; *out++ = 'n'; break;
      case '\r': *out++ = '\\'; *out++ = 'r'; break;
      case '\t': *out++ = '\\'; *out++ = 't'; break;
      case '\v': *out++ = '\\'; *out++ = 'v'; break;
      case '\0': *out++ = '\\'; *out++ = '0'; break;
      default: *out++ = *p; break;
    }
  }
  *out++ = '"';
  *out = '\0';
  return buf;
}

static int elmc_utf8_encode_codepoint(uint32_t cp, char *out, size_t cap) {
  if (!out || cap == 0) return 0;
  if (cp <= 0x7F) {
    if (cap < 2) return 0;
    out[0] = (char)cp;
    out[1] = '\0';
    return 1;
  }
  if (cp <= 0x7FF) {
    if (cap < 3) return 0;
    out[0] = (char)(0xC0 | (cp >> 6));
    out[1] = (char)(0x80 | (cp & 0x3F));
    out[2] = '\0';
    return 2;
  }
  if (cp <= 0xFFFF) {
    if (cap < 4) return 0;
    out[0] = (char)(0xE0 | (cp >> 12));
    out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[2] = (char)(0x80 | (cp & 0x3F));
    out[3] = '\0';
    return 3;
  }
  if (cap < 5) return 0;
  out[0] = (char)(0xF0 | (cp >> 18));
  out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
  out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
  out[3] = (char)(0x80 | (cp & 0x3F));
  out[4] = '\0';
  return 4;
}

static int elmc_utf8_decode_codepoint(const unsigned char **p, const unsigned char *end, uint32_t *cp_out) {
  if (!p || !*p || !cp_out || *p >= end) return 0;
  const unsigned char *s = *p;
  unsigned char c0 = s[0];
  if (c0 < 0x80) {
    *cp_out = (uint32_t)c0;
    *p = s + 1;
    return 1;
  }
  if ((c0 & 0xE0) == 0xC0 && s + 1 < end) {
    *cp_out = ((uint32_t)(c0 & 0x1F) << 6) | (uint32_t)(s[1] & 0x3F);
    *p = s + 2;
    return 1;
  }
  if ((c0 & 0xF0) == 0xE0 && s + 2 < end) {
    *cp_out = ((uint32_t)(c0 & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6) | (uint32_t)(s[2] & 0x3F);
    *p = s + 3;
    return 1;
  }
  if ((c0 & 0xF8) == 0xF0 && s + 3 < end) {
    *cp_out = ((uint32_t)(c0 & 0x07) << 18) | ((uint32_t)(s[1] & 0x3F) << 12) |
              ((uint32_t)(s[2] & 0x3F) << 6) | (uint32_t)(s[3] & 0x3F);
    *p = s + 4;
    return 1;
  }
  *cp_out = 0xFFFD;
  *p = s + 1;
  return 1;
}

static size_t elmc_utf8_codepoint_count(const char *src) {
  if (!src) return 0;
  const unsigned char *p = (const unsigned char *)src;
  const unsigned char *end = p + strlen(src);
  size_t count = 0;
  while (p < end) {
    uint32_t cp;
    if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
    count++;
  }
  return count;
}

static const char *elmc_utf8_byte_offset_at_codepoint(const char *src, int64_t index) {
  if (!src || index <= 0) return src ? src : "";
  const unsigned char *p = (const unsigned char *)src;
  const unsigned char *end = p + strlen(src);
  int64_t i = 0;
  while (p < end && i < index) {
    uint32_t cp;
    if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
    i++;
  }
  return (const char *)p;
}

static RC elmc_rc_assign_new_char(ElmcValue **out, elmc_int_t code) {
  ElmcValue *ch = elmc_new_char(code);
  if (!ch) return RC_ERR_OUT_OF_MEMORY;
  *out = ch;
  return RC_SUCCESS;
}

static RC elmc_debug_append_char(ElmcValue **out, elmc_int_t code) {
  char buf[16];
  const char *piece = buf;
  if (code == 0) piece = "'\\0'";
  else if (code == '\\') piece = "'\\'";
  else if (code == '\'') piece = "'\''";
  else if (code == '\n') piece = "'\n'";
  else if (code == '\r') piece = "'\r'";
  else if (code == '\t') piece = "'\t'";
  else {
    char utf8[8];
    int n = elmc_utf8_encode_codepoint((uint32_t)code, utf8, sizeof(utf8));
    if (n <= 0) return RC_ERR_INVALID_ARG;
    buf[0] = '\'';
    memcpy(buf + 1, utf8, (size_t)n);
    buf[1 + n] = '\'';
    buf[2 + n] = '\0';
  }
  return elmc_debug_append_cstr(out, piece);
}

static int elmc_is_task_result(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_RESULT) return 0;
  elmc_int_t scalar = value->scalar;
  return scalar >= ELMC_TASK_SUCCEED_SCALAR && scalar <= ELMC_TASK_SPAWN_SCALAR;
}

static const char *elmc_task_debug_ctor_name(ElmcValue *value) {
  if (!elmc_is_task_result(value)) return NULL;
  switch (value->scalar) {
    case ELMC_TASK_SUCCEED_SCALAR: return "<Task:succeed>";
    case ELMC_TASK_FAIL_SCALAR: return "<Task:fail>";
    case ELMC_TASK_AND_THEN_SCALAR: return "<Task:andThen>";
    case ELMC_TASK_SPAWN_SCALAR: return "<Task:spawn>";
    case ELMC_TASK_MAP_SCALAR: {
      if (!value->payload) return "<Task:map>";
      ElmcResult *result = (ElmcResult *)value->payload;
      ElmcValue *payload = result->value;
      if (payload && payload->tag == ELMC_TAG_TUPLE2 && payload->payload) {
        ElmcTuple2 *pair = (ElmcTuple2 *)payload->payload;
        const char *inner = elmc_task_debug_ctor_name(pair->second);
        if (inner) return inner;
      }
      return "<Task:map>";
    }
    default: return NULL;
  }
}

static ElmcValue *elmc_task_wrap(ElmcValue *value, elmc_int_t task_scalar) {
  ElmcValue *out = NULL;
  if (elmc_result_ok(&out, value) != RC_SUCCESS) return NULL;
  out->scalar = task_scalar;
  return out;
}

static ElmcValue *elmc_task_wrap_pair(ElmcValue *f, ElmcValue *task, elmc_int_t task_scalar) {
  ElmcValue *pair = NULL;
  if (elmc_tuple2(&pair, f, task) != RC_SUCCESS) return NULL;
  ElmcValue *out = elmc_task_wrap(pair, task_scalar);
  elmc_release(pair);
  return out;
}

static RC elmc_debug_format_union_payload(ElmcValue **out, const char *ctor_name, ElmcValue *payload) {
  RC rc = RC_SUCCESS;
  ElmcValue *part = NULL;
  CATCH_BEGIN
    if (!payload) {
    } else if (payload->tag == ELMC_TAG_INT && elmc_as_int(payload) == 0) {
    } else if (ctor_name && strcmp(ctor_name, "Char") == 0 &&
               (payload->tag == ELMC_TAG_INT || payload->tag == ELMC_TAG_CHAR)) {
      rc = elmc_debug_append_cstr(out, " ");
      CHECK_RC(rc);
      rc = elmc_debug_append_char(out, elmc_as_int(payload));
      CHECK_RC(rc);
    } else if (payload->tag == ELMC_TAG_TUPLE2 && payload->payload != NULL) {
      ElmcValue *cursor = payload;
      int first = 1;
      while (cursor && cursor->tag == ELMC_TAG_TUPLE2 && cursor->payload != NULL) {
        ElmcTuple2 *node = (ElmcTuple2 *)cursor->payload;
        if (!first) {
          rc = elmc_debug_append_cstr(out, " ");
          CHECK_RC(rc);
        }
        part = NULL;
        rc = elmc_debug_format_into(&part, node->first);
        CHECK_RC(rc);
        const char *piece =
          (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
        rc = elmc_debug_append_cstr(out, piece);
        CHECK_RC(rc);
        elmc_release(part);
        part = NULL;
        first = 0;
        cursor = node->second;
        if (cursor && cursor->tag != ELMC_TAG_TUPLE2) {
          rc = elmc_debug_append_cstr(out, " ");
          CHECK_RC(rc);
          part = NULL;
          rc = elmc_debug_format_into(&part, cursor);
          CHECK_RC(rc);
          piece =
            (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
          rc = elmc_debug_append_cstr(out, piece);
          CHECK_RC(rc);
          elmc_release(part);
          part = NULL;
          cursor = NULL;
        }
      }
    } else {
      rc = elmc_debug_append_cstr(out, " ");
      CHECK_RC(rc);
      part = NULL;
      rc = elmc_debug_format_into(&part, payload);
      CHECK_RC(rc);
      const char *piece =
        (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
      int parenless =
        piece[0] == '{' || piece[0] == '(' || piece[0] == '[' || piece[0] == '<' || piece[0] == '"' ||
        (piece[0] >= 'A' && piece[0] <= 'Z');
      if (!parenless) {
        rc = elmc_debug_append_cstr(out, "(");
        CHECK_RC(rc);
      }
      rc = elmc_debug_append_cstr(out, piece);
      CHECK_RC(rc);
      if (!parenless) {
        rc = elmc_debug_append_cstr(out, ")");
        CHECK_RC(rc);
      }
      elmc_release(part);
      part = NULL;
    }
  CATCH_END;
  elmc_release(part);
  return rc;
}

static RC elmc_debug_format_into(ElmcValue **out, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  char *escaped = NULL;
  char buffer[64];
  ElmcValue *part = NULL;
  CATCH_BEGIN
    if (!value) {
      rc = elmc_debug_append_cstr(out, "<null>");
      CHECK_RC(rc);
      return rc;
    }

    switch (value->tag) {
      case ELMC_TAG_STRING: {
        const char *text = value->payload ? (const char *)value->payload : "";
        escaped = elmc_debug_escape_string(text);
        if (!escaped) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
        rc = elmc_debug_append_cstr(out, escaped);
        CHECK_RC(rc);
        break;
      }

      case ELMC_TAG_BOOL:
        rc = elmc_debug_append_cstr(out, elmc_as_int(value) ? "True" : "False");
        CHECK_RC(rc);
        break;

      case ELMC_TAG_FLOAT:
        rc = elmc_debug_append_float(out, elmc_as_float(value));
        CHECK_RC(rc);
        break;

      case ELMC_TAG_INT:
        if (value->scalar == ELMC_UNIT_SCALAR) {
          rc = elmc_debug_append_cstr(out, "()");
          CHECK_RC(rc);
        } else {
          snprintf(buffer, sizeof(buffer), "%lld", (long long)elmc_as_int(value));
          rc = elmc_debug_append_cstr(out, buffer);
          CHECK_RC(rc);
        }
        break;

      case ELMC_TAG_CHAR:
        rc = elmc_debug_append_char(out, elmc_as_int(value));
        CHECK_RC(rc);
        break;

      case ELMC_TAG_ORDER: {
        elmc_int_t order = elmc_as_int(value);
        const char *name = order < 0 ? "LT" : (order > 0 ? "GT" : "EQ");
        rc = elmc_debug_append_cstr(out, name);
        CHECK_RC(rc);
        break;
      }

      case ELMC_TAG_INT_LIST: {
        ElmcIntListPayload *payload = elmc_int_list_payload(value);
        rc = elmc_debug_append_cstr(out, "[");
        CHECK_RC(rc);
        if (payload) {
          for (int i = 0; i < payload->length; i++) {
            if (i > 0) {
              rc = elmc_debug_append_cstr(out, ",");
              CHECK_RC(rc);
            }
            snprintf(buffer, sizeof(buffer), "%lld", (long long)payload->values[i]);
            rc = elmc_debug_append_cstr(out, buffer);
            CHECK_RC(rc);
          }
        }
        rc = elmc_debug_append_cstr(out, "]");
        CHECK_RC(rc);
        break;
      }

      case ELMC_TAG_LIST: {
        if (value->scalar == ELMC_DICT_SCALAR) {
          rc = elmc_debug_append_cstr(out, "HashMap.fromList ");
          CHECK_RC(rc);
        }
        rc = elmc_debug_append_cstr(out, "[");
        CHECK_RC(rc);
        ElmcValue *cursor = value;
        int first = 1;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          if (!first) {
            rc = elmc_debug_append_cstr(out, ",");
            CHECK_RC(rc);
          }
          part = NULL;
          rc = elmc_debug_format_into(&part, node->head);
          CHECK_RC(rc);
          const char *piece =
            (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
          rc = elmc_debug_append_cstr(out, piece);
          CHECK_RC(rc);
          elmc_release(part);
          part = NULL;
          first = 0;
          cursor = node->tail;
        }
        rc = elmc_debug_append_cstr(out, "]");
        CHECK_RC(rc);
        break;
      }

      case ELMC_TAG_RECORD: {
        if (!value->payload) {
          rc = elmc_debug_append_cstr(out, "{}");
          CHECK_RC(rc);
          break;
        }
        ElmcRecord *record = (ElmcRecord *)value->payload;
        const char **field_names = elmc_record_field_names(value);
        int field_count = record->field_count;
        int indices[32];
        if (field_count > 32) field_count = 32;
        if (field_count == 0) {
          rc = elmc_debug_append_cstr(out, "{}");
          CHECK_RC(rc);
          break;
        }
        for (int i = 0; i < field_count; i++) indices[i] = i;
        if (field_names) {
          for (int i = 0; i < field_count - 1; i++) {
            for (int j = i + 1; j < field_count; j++) {
              const char *a = field_names[indices[i]] ? field_names[indices[i]] : "";
              const char *b = field_names[indices[j]] ? field_names[indices[j]] : "";
              if (strcmp(a, b) > 0) {
                int tmp = indices[i];
                indices[i] = indices[j];
                indices[j] = tmp;
              }
            }
          }
        }
        rc = elmc_debug_append_cstr(out, "{ ");
        CHECK_RC(rc);
        for (int i = 0; i < field_count; i++) {
          int idx = indices[i];
          if (i > 0) {
            rc = elmc_debug_append_cstr(out, ", ");
            CHECK_RC(rc);
          }
          if (field_names && field_names[idx]) {
            rc = elmc_debug_append_cstr(out, field_names[idx]);
            CHECK_RC(rc);
            rc = elmc_debug_append_cstr(out, " = ");
            CHECK_RC(rc);
          }
          part = NULL;
          rc = elmc_debug_format_into(&part, record->field_values[idx]);
          CHECK_RC(rc);
          const char *piece =
            (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
          rc = elmc_debug_append_cstr(out, piece);
          CHECK_RC(rc);
          elmc_release(part);
          part = NULL;
        }
        rc = elmc_debug_append_cstr(out, " }");
        CHECK_RC(rc);
        break;
      }

      case ELMC_TAG_MAYBE: {
        if (!value->payload) {
          rc = elmc_debug_append_cstr(out, "Nothing");
          CHECK_RC(rc);
          break;
        }
        ElmcMaybe *maybe = (ElmcMaybe *)value->payload;
        if (!maybe->is_just) {
          rc = elmc_debug_append_cstr(out, "Nothing");
          CHECK_RC(rc);
        } else {
          rc = elmc_debug_append_cstr(out, "Just ");
          CHECK_RC(rc);
          part = NULL;
          rc = elmc_debug_format_into(&part, maybe->value);
          CHECK_RC(rc);
          const char *piece =
            (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
          int parenless =
            piece[0] != '\0' &&
            (piece[0] == '{' || piece[0] == '(' || piece[0] == '[' || piece[0] == '<' || piece[0] == '"' ||
            strchr(piece, ' ') == NULL);
          if (!parenless) {
            rc = elmc_debug_append_cstr(out, "(");
            CHECK_RC(rc);
          }
          rc = elmc_debug_append_cstr(out, piece);
          CHECK_RC(rc);
          if (!parenless) {
            rc = elmc_debug_append_cstr(out, ")");
            CHECK_RC(rc);
          }
          elmc_release(part);
          part = NULL;
        }
        break;
      }

      case ELMC_TAG_RESULT: {
        if (!value->payload) {
          rc = elmc_debug_append_cstr(out, "<internals>");
          CHECK_RC(rc);
          break;
        }
        const char *task_ctor = elmc_task_debug_ctor_name(value);
        if (task_ctor) {
          rc = elmc_debug_append_cstr(out, task_ctor);
          CHECK_RC(rc);
          break;
        }
        ElmcResult *result = (ElmcResult *)value->payload;
        rc = elmc_debug_append_cstr(out, result->is_ok ? "Ok " : "Err ");
        CHECK_RC(rc);
        part = NULL;
        rc = elmc_debug_format_into(&part, result->value);
        CHECK_RC(rc);
        const char *piece =
          (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
        int parenless =
          piece[0] == '{' || piece[0] == '(' || piece[0] == '[' || piece[0] == '<' || piece[0] == '"' ||
          strchr(piece, ' ') == NULL;
        if (!parenless) {
          rc = elmc_debug_append_cstr(out, "(");
          CHECK_RC(rc);
        }
        rc = elmc_debug_append_cstr(out, piece);
        CHECK_RC(rc);
        if (!parenless) {
          rc = elmc_debug_append_cstr(out, ")");
          CHECK_RC(rc);
        }
        elmc_release(part);
        part = NULL;
        break;
      }

      case ELMC_TAG_TUPLE2: {
        if (!value->payload) {
          rc = elmc_debug_append_cstr(out, "<internals>");
          CHECK_RC(rc);
          break;
        }
        ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
        if (tuple->first && tuple->first->tag == ELMC_TAG_INT) {
          const char *ctor_name = elmc_debug_union_ctor_name(elmc_as_int(tuple->first));
          if (ctor_name) {
            rc = elmc_debug_append_cstr(out, ctor_name);
            CHECK_RC(rc);
            rc = elmc_debug_format_union_payload(out, ctor_name, tuple->second);
            CHECK_RC(rc);
            break;
          }
        }
        rc = elmc_debug_append_cstr(out, "(");
        CHECK_RC(rc);
        part = NULL;
        rc = elmc_debug_format_into(&part, tuple->first);
        CHECK_RC(rc);
        const char *first_piece =
          (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
        rc = elmc_debug_append_cstr(out, first_piece);
        CHECK_RC(rc);
        elmc_release(part);
        part = NULL;
        ElmcValue *rest = tuple->second;
        while (rest && rest->tag == ELMC_TAG_TUPLE2 && rest->payload != NULL) {
          ElmcTuple2 *rest_tuple = (ElmcTuple2 *)rest->payload;
          if (rest_tuple->first && rest_tuple->first->tag != ELMC_TAG_TUPLE2 &&
              rest_tuple->second && rest_tuple->second->tag == ELMC_TAG_TUPLE2) {
            break;
          }
          rc = elmc_debug_append_cstr(out, ",");
          CHECK_RC(rc);
          part = NULL;
          rc = elmc_debug_format_into(&part, rest_tuple->first);
          CHECK_RC(rc);
          const char *mid_piece =
            (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
          rc = elmc_debug_append_cstr(out, mid_piece);
          CHECK_RC(rc);
          elmc_release(part);
          part = NULL;
          rest = rest_tuple->second;
        }
        rc = elmc_debug_append_cstr(out, ",");
        CHECK_RC(rc);
        part = NULL;
        rc = elmc_debug_format_into(&part, rest);
        CHECK_RC(rc);
        const char *last_piece =
          (part && part->tag == ELMC_TAG_STRING && part->payload) ? (const char *)part->payload : "";
        rc = elmc_debug_append_cstr(out, last_piece);
        CHECK_RC(rc);
        elmc_release(part);
        part = NULL;
        rc = elmc_debug_append_cstr(out, ")");
        CHECK_RC(rc);
        break;
      }

      case ELMC_TAG_CLOSURE:
        rc = elmc_debug_append_cstr(out, "<function>");
        CHECK_RC(rc);
        break;

      default:
        rc = elmc_debug_append_cstr(out, "<internals>");
        CHECK_RC(rc);
        break;
    }
  CATCH_END;
  if (escaped) elmc_free(escaped);
  elmc_release(part);
  return rc;
}

ElmcValue *elmc_debug_to_string(ElmcValue *value) {
  ElmcValue *out = NULL;
  if (elmc_debug_format_into(&out, value) != RC_SUCCESS) {
    elmc_release(out);
    return NULL;
  }
  return out;
}

ElmcValue *elmc_debug_set_to_string(ElmcValue *set) {
  ElmcValue *out = NULL;
  ElmcValue *list_part = NULL;
  if (elmc_debug_append_cstr(&out, "Set.fromList ") != RC_SUCCESS) {
    elmc_release(out);
    return NULL;
  }
  if (elmc_debug_format_into(&list_part, set ? set : elmc_list_nil()) != RC_SUCCESS) {
    elmc_release(out);
    elmc_release(list_part);
    return NULL;
  }
  const char *piece =
    (list_part && list_part->tag == ELMC_TAG_STRING && list_part->payload) ? (const char *)list_part->payload : "[]";
  if (elmc_debug_append_cstr(&out, piece) != RC_SUCCESS) {
    elmc_release(out);
    elmc_release(list_part);
    return NULL;
  }
  elmc_release(list_part);
  return out;
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
    if (len_a > 0) memcpy(buf, a, len_a);
    if (len_b > 0) memcpy(buf + len_a, b, len_b);
    buf[len_a + len_b] = '\0';
    ElmcValue *result = elmc_alloc(ELMC_TAG_STRING, buf);
    buf = NULL;
    if (!result) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    result->scalar = (elmc_int_t)(len_a + len_b);
    *out = result;
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_append(ElmcValue **out, ElmcValue *left, ElmcValue *right) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    size_t len_a = left ? elmc_string_byte_len(left) : 0;
    size_t len_b = right ? elmc_string_byte_len(right) : 0;
    const char *a = (left && left->tag == ELMC_TAG_STRING && left->payload) ? (const char *)left->payload : "";
    const char *b = (right && right->tag == ELMC_TAG_STRING && right->payload) ? (const char *)right->payload : "";
    buf = (char *)elmc_malloc(len_a + len_b + 1, __func__);
    if (!buf) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    if (len_a > 0) memcpy(buf, a, len_a);
    if (len_b > 0) memcpy(buf + len_a, b, len_b);
    buf[len_a + len_b] = '\0';
    ElmcValue *result = elmc_alloc(ELMC_TAG_STRING, buf);
    buf = NULL;
    if (!result) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    result->scalar = (elmc_int_t)(len_a + len_b);
    *out = result;
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
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
      (void)elmc_new_bool(&_elmc_rc_out, elmc_string_byte_len(value) == 0);
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
    *out = acc;
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
  ElmcValue *order = NULL;
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
        } else if (!inserted && tp->first) {
          order = elmc_basics_compare_take(key, tp->first);
          if (!order) {
            rc = RC_ERR_INVALID_ARG;
            CHECK_RC(rc);
          }
          elmc_int_t cmp = elmc_as_int(order);
          elmc_release(order);
          order = NULL;
          if (cmp < 0) {
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
            inserted = 1;
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
    if (*out) elmc_dict_mark_spine(*out);
  CATCH_END;
  elmc_release(new_head);
  elmc_release(pair);
  elmc_release(next_rev);
  elmc_release(order);
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
      *out = elmc_maybe_nothing();
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
  ElmcValue *owned = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = items;
    if (items && (items->tag == ELMC_TAG_INT_LIST || items->tag == ELMC_TAG_RECORD_SEQ)) {
      rc = elmc_list_materialize_cons(&cursor, items);
      CHECK_RC(rc);
      owned = cursor;
    }
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
    *out = acc;
    acc = NULL;
  CATCH_END;
  elmc_release(owned);
  elmc_release(next);
  elmc_release(acc);
  return rc;
}

ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set) {
  ElmcValue *cursor = set;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (elmc_value_equal(node->head, value)) {
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
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  ElmcValue *order = NULL;
  int inserted = 0;
  CATCH_BEGIN
    exists = elmc_set_member(value, set);
    int present = exists && elmc_as_int(exists) != 0;
    if (present) {
      *out = elmc_retain(set);
    } else {
      ElmcValue *cursor = set ? set : elmc_list_nil();
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        if (!inserted) {
          order = elmc_basics_compare_take(value, node->head);
          if (!order) {
            rc = RC_ERR_INVALID_ARG;
            CHECK_RC(rc);
          }
          elmc_int_t cmp = elmc_as_int(order);
          elmc_release(order);
          order = NULL;
          if (cmp < 0) {
            next = NULL;
            rc = elmc_list_cons(&next, value, rev);
            CHECK_RC(rc);
            elmc_release(rev);
            rev = next;
            next = NULL;
            inserted = 1;
          }
        }
        next = NULL;
        rc = elmc_list_cons(&next, node->head, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
        cursor = node->tail;
      }
      if (!inserted) {
        next = NULL;
        rc = elmc_list_cons(&next, value, rev);
        CHECK_RC(rc);
        elmc_release(rev);
        rev = next;
        next = NULL;
      }
      rc = elmc_list_reverse_transfer(out, &rev);
      CHECK_RC(rc);
    }
  CATCH_END;
  elmc_release(exists);
  elmc_release(order);
  elmc_release(next);
  elmc_release(rev);
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
  int64_t size = 0;

  if (array && array->tag == ELMC_TAG_INT_LIST) {
    size = elmc_int_list_length_native(array);
  } else if (array && array->tag == ELMC_TAG_INT_SPINE) {
    ElmcValue *cursor = array;
    while (cursor && cursor->tag == ELMC_TAG_INT_SPINE && cursor->payload != NULL) {
      size += 1;
      cursor = ((ElmcIntSpine *)cursor->payload)->tail;
    }
  } else {
    ElmcValue *cursor = array;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      size += 1;
      cursor = ((ElmcCons *)cursor->payload)->tail;
    }
  }

  {
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_new_int(&_elmc_rc_out, size) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

ElmcValue *elmc_array_get(ElmcValue *index, ElmcValue *array) {
  int64_t wanted = elmc_as_int(index);
  if (wanted < 0) return elmc_maybe_nothing();

  if (array && array->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *payload = elmc_int_list_payload(array);
    if (payload && wanted < payload->length) {
      ElmcValue *boxed = NULL;
      if (elmc_new_int(&boxed, payload->values[wanted]) != RC_SUCCESS) return NULL;
      ElmcValue *_elmc_rc_out = NULL;
      if (elmc_maybe_just(&_elmc_rc_out, boxed) != RC_SUCCESS) {
        elmc_release(boxed);
        return NULL;
      }
      elmc_release(boxed);
      return _elmc_rc_out;
    }
    return elmc_maybe_nothing();
  }

  if (array && array->tag == ELMC_TAG_INT_SPINE) {
    int64_t i = 0;
    ElmcValue *cursor = array;
    while (cursor && cursor->tag == ELMC_TAG_INT_SPINE && cursor->payload != NULL) {
      if (i == wanted) {
        ElmcValue *boxed = NULL;
        if (elmc_new_int(&boxed, ((ElmcIntSpine *)cursor->payload)->head) != RC_SUCCESS) return NULL;
        ElmcValue *_elmc_rc_out = NULL;
        if (elmc_maybe_just(&_elmc_rc_out, boxed) != RC_SUCCESS) {
          elmc_release(boxed);
          return NULL;
        }
        elmc_release(boxed);
        return _elmc_rc_out;
      }
      i += 1;
      cursor = ((ElmcIntSpine *)cursor->payload)->tail;
    }
    return elmc_maybe_nothing();
  }

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

  if (array && array->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *payload = elmc_int_list_payload(array);
    if (payload && index < payload->length) return payload->values[index];
    return default_val;
  }

  if (array && array->tag == ELMC_TAG_INT_SPINE) {
    elmc_int_t i = 0;
    ElmcValue *cursor = array;
    while (cursor && cursor->tag == ELMC_TAG_INT_SPINE && cursor->payload != NULL) {
      if (i == index) return ((ElmcIntSpine *)cursor->payload)->head;
      i += 1;
      cursor = ((ElmcIntSpine *)cursor->payload)->tail;
    }
    return default_val;
  }

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

  if (array && array->tag == ELMC_TAG_INT_LIST) {
    return elmc_list_replace_nth_int(array, wanted, elmc_as_int(value));
  }

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
  return elmc_task_wrap(value, ELMC_TASK_SUCCEED_SCALAR);
}

ElmcValue *elmc_task_fail(ElmcValue *value) {
  ElmcValue *out = NULL;
  if (elmc_result_err(&out, value) != RC_SUCCESS) return NULL;
  out->scalar = ELMC_TASK_FAIL_SCALAR;
  return out;
}

ElmcValue *elmc_task_map(ElmcValue *f, ElmcValue *task) {
  return elmc_task_wrap_pair(f, task, ELMC_TASK_MAP_SCALAR);
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
  return elmc_task_wrap_pair(f, task, ELMC_TASK_AND_THEN_SCALAR);
}

ElmcValue *elmc_task_force(ElmcValue *task);

static ElmcValue *elmc_task_force_pair_step(ElmcValue *pair_value, elmc_int_t kind) {
  if (!pair_value || pair_value->tag != ELMC_TAG_TUPLE2 || !pair_value->payload) return NULL;
  ElmcTuple2 *pair = (ElmcTuple2 *)pair_value->payload;
  ElmcValue *forced = elmc_task_force(pair->second);
  if (!forced) return NULL;
  if (forced->tag != ELMC_TAG_RESULT || !forced->payload) {
    elmc_release(forced);
    return NULL;
  }
  ElmcResult *inner = (ElmcResult *)forced->payload;
  if (!inner->is_ok) {
    ElmcValue *err = elmc_retain(forced);
    elmc_release(forced);
    return err;
  }
  ElmcValue *args[1] = { inner->value };
  ElmcValue *step = NULL;
  RC rc = elmc_closure_call_rc(&step, pair->first, args, 1);
  elmc_release(forced);
  if (rc != RC_SUCCESS) {
    elmc_release(step);
    return NULL;
  }
  if (kind == ELMC_TASK_AND_THEN_SCALAR) {
    ElmcValue *out = elmc_task_force(step);
    elmc_release(step);
    return out;
  }
  ElmcValue *out = NULL;
  if (elmc_result_ok(&out, step) != RC_SUCCESS) {
    elmc_release(step);
    return NULL;
  }
  elmc_release(step);
  return out;
}

ElmcValue *elmc_task_force(ElmcValue *task) {
  if (!task) return NULL;
  if (!elmc_is_task_result(task)) return elmc_retain(task);
  if (!task->payload) return NULL;
  ElmcResult *result = (ElmcResult *)task->payload;

  switch (task->scalar) {
    case ELMC_TASK_SUCCEED_SCALAR: {
      ElmcValue *out = NULL;
      ElmcValue *value = result->value ? elmc_retain(result->value) : elmc_int_zero();
      if (elmc_result_ok(&out, value) != RC_SUCCESS) out = NULL;
      elmc_release(value);
      return out;
    }
    case ELMC_TASK_FAIL_SCALAR: {
      ElmcValue *out = NULL;
      ElmcValue *value = result->value ? elmc_retain(result->value) : elmc_int_zero();
      if (elmc_result_err(&out, value) != RC_SUCCESS) out = NULL;
      elmc_release(value);
      return out;
    }
    case ELMC_TASK_MAP_SCALAR:
      return elmc_task_force_pair_step(result->value, ELMC_TASK_MAP_SCALAR);
    case ELMC_TASK_AND_THEN_SCALAR:
      return elmc_task_force_pair_step(result->value, ELMC_TASK_AND_THEN_SCALAR);
    case ELMC_TASK_SPAWN_SCALAR: {
      ElmcProcessSlot *slot = elmc_process_alloc_slot();
      if (!slot) {
        ElmcValue *out = NULL;
        ElmcValue *zero = elmc_int_zero();
        if (elmc_result_ok(&out, zero) != RC_SUCCESS) out = NULL;
        elmc_release(zero);
        return out;
      }
      if (result->value) slot->task = elmc_retain(result->value);
      ElmcValue *pid = elmc_new_int_take(slot->pid);
      ElmcValue *out = NULL;
      if (elmc_result_ok(&out, pid) != RC_SUCCESS) out = NULL;
      elmc_release(pid);
      return out;
    }
    default:
      return elmc_retain(task);
  }
}

ElmcValue *elmc_task_perform(ElmcValue *to_msg, ElmcValue *task) {
  (void)to_msg;
  (void)task;
  return elmc_int_zero();
}

ElmcValue *elmc_process_spawn(ElmcValue *task) {
#ifndef ELMC_PEBBLE_PLATFORM
  ElmcProcessSlot *slot = elmc_process_alloc_slot();
  if (!slot) {
    ElmcValue *out = NULL;
    ElmcValue *zero = elmc_int_zero();
    if (elmc_result_ok(&out, zero) != RC_SUCCESS) out = NULL;
    elmc_release(zero);
    return out;
  }
  slot->task = task ? elmc_retain(task) : NULL;
  ElmcValue *pid = elmc_new_int_take(slot->pid);
  ElmcValue *out = NULL;
  if (elmc_result_ok(&out, pid) != RC_SUCCESS) out = NULL;
  elmc_release(pid);
  if (out) out->scalar = ELMC_TASK_SPAWN_SCALAR;
  return out;
#else
  return elmc_task_wrap(task, ELMC_TASK_SPAWN_SCALAR);
#endif
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
    *out = allocated;
  CATCH_END;
  if (ptr) elmc_free(ptr);
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
    rc = elmc_record_cell_alloc(out, field_count, field_names, field_values, 0);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_take(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_record_cell_alloc(out, field_count, field_names, field_values, 1);
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
    rc = elmc_record_cell_alloc_static(out, field_count, field_names, field_values, 0);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_static_take(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_record_cell_alloc_static(out, field_count, field_names, field_values, 1);
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
    rc = elmc_record_cell_alloc_values(out, field_count, field_values, 0);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

RC elmc_record_new_values_take(ElmcValue **out, int field_count, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_record_cell_alloc_values(out, field_count, field_values, 1);
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
  const char **field_names = elmc_record_field_names(record);
  ElmcValue *result = NULL;
  if (field_names) {
    if (elmc_record_new(&result, old->field_count, field_names, values) != RC_SUCCESS) result = NULL;
  } else if (elmc_record_new_values(&result, old->field_count, values) != RC_SUCCESS) {
    result = NULL;
  }
  elmc_free(values);
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

ElmcValue *elmc_record_update_index_int_cow(ElmcValue *record, int index, elmc_int_t new_value) {
  ElmcValue *boxed = NULL;
  if (elmc_new_int(&boxed, new_value) != RC_SUCCESS || !boxed) return elmc_retain(record);
  ElmcValue *next = elmc_record_update_index_cow(record, index, boxed);
  elmc_release(boxed);
  return next;
}

ElmcValue *elmc_record_update_index_int_cow_drop(ElmcValue *record, int index, elmc_int_t new_value) {
  ElmcValue *next = elmc_record_update_index_int_cow(record, index, new_value);
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
    *out = &cell->value;
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
    *out = &cell->value;
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
      *out = value;
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
  elmc_free(ref);
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *payload = elmc_int_list_payload(list);
    ElmcValue *_elmc_rc_out = NULL;
    (void)elmc_new_bool(&_elmc_rc_out, !payload || payload->length <= 0);
    return _elmc_rc_out;
  }
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    count = elmc_int_list_length_native(list);
  } else {
    ElmcValue *cursor = list;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      count += 1;
      cursor = ((ElmcCons *)cursor->payload)->tail;
    }
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    ElmcIntListPayload *payload = elmc_int_list_payload(list);
    if (!payload || payload->length <= 0) {
      return elmc_int_list_alloc_copy(out, NULL, 0);
    }
    return elmc_int_list_alloc_copy(out, payload->values, payload->length);
  }
  RC rc = RC_SUCCESS;
  ElmcValue *reversed = NULL;
  CATCH_BEGIN
    if (!list) {
      *out = elmc_int_zero();
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
  ElmcValue *cursor = list;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    ElmcCons *node = (ElmcCons *)cursor->payload;
    if (elmc_value_equal(node->head, value)) {
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_map(out, f, list);
  }
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_filter(out, f, list);
  }
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *keep = NULL;
  ElmcValue *next = NULL;
  ElmcValue *owned = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = list;
    if (list && list->tag == ELMC_TAG_RECORD_SEQ) {
      rc = elmc_list_materialize_cons(&cursor, list);
      CHECK_RC(rc);
      owned = cursor;
    }
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
  elmc_release(owned);
  elmc_release(keep);
  elmc_release(next);
  elmc_release(rev);
  return rc;
}

RC elmc_list_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_foldl(out, f, acc, list);
  }
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
      *out = result;
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
      *out = result;
      result = NULL;
    }
  CATCH_END;
  elmc_release(reversed);
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_list_append(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  if (a && a->tag == ELMC_TAG_INT_LIST) {
    if (b && b->tag == ELMC_TAG_INT_LIST) {
      return elmc_int_list_append(out, a, b);
    }
    if (!b || (b->tag == ELMC_TAG_LIST && b->payload == NULL) ||
        (b->tag == ELMC_TAG_INT_LIST && elmc_int_list_is_empty(b))) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        *out = elmc_retain(a);
      CATCH_END;
      return rc;
    }
    RC rc = RC_SUCCESS;
    ElmcValue *result = NULL;
    ElmcValue **tail_slot = NULL;
    ElmcValue *cell = NULL;
    CATCH_BEGIN
      ElmcIntListPayload *payload = elmc_int_list_payload(a);
      if (payload) {
        for (int i = 0; i < payload->length; i++) {
          ElmcValue *head = NULL;
          rc = elmc_new_int(&head, payload->values[i]);
          CHECK_RC(rc);
          cell = NULL;
          rc = elmc_list_cons(&cell, head, elmc_list_nil());
          elmc_release(head);
          CHECK_RC(rc);
          if (tail_slot) {
            elmc_release(*tail_slot);
            *tail_slot = cell;
          } else {
            result = cell;
          }
          tail_slot = &((ElmcCons *)cell->payload)->tail;
          cell = NULL;
        }
      }
      if (!result) {
        *out = elmc_retain(b);
      } else {
        elmc_release(*tail_slot);
        *tail_slot = elmc_retain(b);
        *out = result;
        result = NULL;
      }
    CATCH_END;
    elmc_release(cell);
    elmc_release(result);
    return rc;
  }
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
      *out = elmc_retain(b);
    } else {
      elmc_release(*tail_slot);
      *tail_slot = elmc_retain(b);
      *out = result;
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
      *out = elmc_list_nil();
    } else {
      *out = result;
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
      *out = acc;
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
      *out = acc;
      acc = NULL;
    }
  CATCH_END;
  elmc_release(merged);
  elmc_release(acc);
  return rc;
}

RC elmc_list_concat_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    rc = elmc_list_map(&mapped, f, list);
    CHECK_RC(rc);
    rc = elmc_list_concat(out, mapped);
    CHECK_RC(rc);
  CATCH_END;
  elmc_release(mapped);
  return rc;
}

RC elmc_list_indexed_map(ElmcValue **out, ElmcValue *f, ElmcValue *list) {
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_indexed_map(out, f, list);
  }
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
      *out = elmc_maybe_nothing();
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
      *out = elmc_maybe_nothing();
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
      *out = elmc_list_nil();
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
      order = elmc_basics_compare_take(key_left, key_right);
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
        if (cmp < 0) {
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
      *out = sorted;
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
      *out = elmc_list_nil();
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
      *out = elmc_list_nil();
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
      *out = acc;
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
      *out = acc;
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_take_int(out, count, list);
  }
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
      *out = elmc_list_nil();
    } else {
      *out = result;
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
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_drop_int(out, count, list);
  }
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
      *out = elmc_list_nil();
    } else {
      *out = result;
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
      *out = elmc_list_nil();
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

RC elmc_list_map4(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *mapped = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *ca = a;
    ElmcValue *cb = b;
    ElmcValue *cc = c;
    ElmcValue *cd = d;
    while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
           cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL &&
           cc && cc->tag == ELMC_TAG_LIST && cc->payload != NULL &&
           cd && cd->tag == ELMC_TAG_LIST && cd->payload != NULL) {
      ElmcCons *na = (ElmcCons *)ca->payload;
      ElmcCons *nb = (ElmcCons *)cb->payload;
      ElmcCons *nc = (ElmcCons *)cc->payload;
      ElmcCons *nd = (ElmcCons *)cd->payload;
      ElmcValue *args[4] = { na->head, nb->head, nc->head, nd->head };
      mapped = NULL;
      rc = elmc_closure_call_rc(&mapped, f, args, 4);
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
      cd = nd->tail;
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

RC elmc_list_map5(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e) {
  RC rc = RC_SUCCESS;
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *mapped = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *ca = a;
    ElmcValue *cb = b;
    ElmcValue *cc = c;
    ElmcValue *cd = d;
    ElmcValue *ce = e;
    while (ca && ca->tag == ELMC_TAG_LIST && ca->payload != NULL &&
           cb && cb->tag == ELMC_TAG_LIST && cb->payload != NULL &&
           cc && cc->tag == ELMC_TAG_LIST && cc->payload != NULL &&
           cd && cd->tag == ELMC_TAG_LIST && cd->payload != NULL &&
           ce && ce->tag == ELMC_TAG_LIST && ce->payload != NULL) {
      ElmcCons *na = (ElmcCons *)ca->payload;
      ElmcCons *nb = (ElmcCons *)cb->payload;
      ElmcCons *nc = (ElmcCons *)cc->payload;
      ElmcCons *nd = (ElmcCons *)cd->payload;
      ElmcCons *ne = (ElmcCons *)ce->payload;
      ElmcValue *args[5] = { na->head, nb->head, nc->head, nd->head, ne->head };
      mapped = NULL;
      rc = elmc_closure_call_rc(&mapped, f, args, 5);
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
      cd = nd->tail;
      ce = ne->tail;
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
      *out = elmc_maybe_nothing();
    } else {
      ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
      if (!m->is_just || !m->value) {
        *out = elmc_maybe_nothing();
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
      *out = elmc_maybe_nothing();
    } else {
      ElmcMaybe *ma = (ElmcMaybe *)a->payload;
      ElmcMaybe *mb = (ElmcMaybe *)b->payload;
      if (!ma->is_just || !ma->value || !mb->is_just || !mb->value) {
        *out = elmc_maybe_nothing();
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
      *out = elmc_maybe_nothing();
    } else {
      ElmcMaybe *m = (ElmcMaybe *)maybe->payload;
      if (!m->is_just || !m->value) {
        *out = elmc_maybe_nothing();
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
        *out = elmc_retain(result);
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
      *out = elmc_retain(result);
    } else {
      ElmcResult *r = (ElmcResult *)result->payload;
      if (r->is_ok) {
        *out = elmc_retain(result);
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
        *out = elmc_retain(result);
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
      if (elmc_new_int(&_elmc_rc_out, (int64_t)elmc_string_byte_len(s)) != RC_SUCCESS) return NULL;
      return _elmc_rc_out;
  }
}

RC elmc_string_reverse(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  uint32_t *cps = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
    } else {
      const char *src = (const char *)s->payload;
      size_t byte_len = strlen(src);
      size_t cp_count = elmc_utf8_codepoint_count(src);
      if (cp_count == 0) {
        *out = &ELMC_EMPTY_STRING;
      } else {
        cps = (uint32_t *)elmc_malloc(cp_count * sizeof(uint32_t), __func__);
        if (!cps) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        const unsigned char *p = (const unsigned char *)src;
        const unsigned char *end = p + byte_len;
        for (size_t i = 0; i < cp_count; i++) {
          if (!elmc_utf8_decode_codepoint(&p, end, &cps[i])) break;
        }
        buf = (char *)elmc_malloc(byte_len + 1, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        size_t out_len = 0;
        for (size_t i = cp_count; i > 0; i--) {
          int n = elmc_utf8_encode_codepoint(cps[i - 1], buf + out_len, byte_len + 1 - out_len);
          if (n <= 0) {
            rc = RC_ERR_INVALID_ARG;
            CHECK_RC(rc);
          }
          out_len += (size_t)n;
        }
        buf[out_len] = '\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!allocated) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        *out = allocated;
      }
    }
  CATCH_END;
  if (cps) elmc_free(cps);
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    int64_t count = elmc_as_int(n);
    if (count <= 0 || !s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
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
      *out = allocated;
    }
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_replace(ElmcValue **out, ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
    } else if (!old_s || old_s->tag != ELMC_TAG_STRING || !old_s->payload) {
      *out = elmc_retain(s);
    } else {
      if (!new_s || new_s->tag != ELMC_TAG_STRING || !new_s->payload) new_s = &ELMC_EMPTY_STRING;
      const char *haystack = (const char *)s->payload;
      const char *needle = (const char *)old_s->payload;
      const char *replacement = (const char *)new_s->payload;
      size_t needle_len = strlen(needle);
      if (needle_len == 0) {
        *out = elmc_retain(s);
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
              elmc_free(buf);
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
              elmc_free(buf);
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
        *out = allocated;
      }
    }
  CATCH_END;
  if (buf) elmc_free(buf);
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
      char *dot = strchr(buf, '.');
      if (dot) {
        char *end = buf + strlen(buf) - 1;
        while (end > dot && *end == '0') {
          *end = '\0';
          end--;
        }
        if (end == dot) *end = '\0';
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
      *out = &ELMC_EMPTY_STRING;
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
      *out = allocated;
    }
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_to_lower(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
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
      *out = allocated;
    }
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_trim(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
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
      *out = allocated;
    }
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_trim_left(ElmcValue **out, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
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
      *out = &ELMC_EMPTY_STRING;
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
      *out = allocated;
    }
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

int elmc_string_equals_cstr(ElmcValue *value, const char *literal) {
  if (!value || value->tag != ELMC_TAG_STRING || !value->payload || !literal) return 0;
  size_t len = elmc_string_byte_len(value);
  size_t lit_len = strlen(literal);
  if (len != lit_len) return 0;
  return memcmp(value->payload, literal, len) == 0;
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
  size_t hay_len = elmc_string_byte_len(s);
  size_t needle_len = elmc_string_byte_len(sub);
  {
      ElmcValue *_elmc_rc_out = NULL;
      (void)elmc_new_bool(&_elmc_rc_out, elmc_memmem(haystack, hay_len, needle, needle_len) != NULL);
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
      *out = elmc_list_nil();
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
  if (buf) elmc_free(buf);
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
      *out = &ELMC_EMPTY_STRING;
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
      *out = allocated;
    }
  CATCH_END;
  if (buf) elmc_free(buf);
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
      *out = &ELMC_EMPTY_STRING;
    } else {
      const char *src = (const char *)s->payload;
      int64_t cp_len = (int64_t)elmc_utf8_codepoint_count(src);
      int64_t st = elmc_as_int(start);
      int64_t en = elmc_as_int(end_idx);
      if (st < 0) st = cp_len + st;
      if (en < 0) en = cp_len + en;
      if (st < 0) st = 0;
      if (en < 0) en = 0;
      if (st > cp_len) st = cp_len;
      if (en > cp_len) en = cp_len;
      if (en <= st) {
        *out = &ELMC_EMPTY_STRING;
      } else {
        const char *byte_start = elmc_utf8_byte_offset_at_codepoint(src, st);
        const char *byte_end = elmc_utf8_byte_offset_at_codepoint(src, en);
        size_t new_len = (size_t)(byte_end - byte_start);
        buf = (char *)elmc_malloc(new_len + 1, __func__);
        if (!buf) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        memcpy(buf, byte_start, new_len);
        buf[new_len] = '\0';
        ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
        buf = NULL;
        if (!allocated) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        *out = allocated;
      }
    }
  CATCH_END;
  if (buf) elmc_free(buf);
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
  int64_t len = (int64_t)elmc_utf8_codepoint_count((const char *)s->payload);
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
  int64_t len = (int64_t)elmc_utf8_codepoint_count((const char *)s->payload);
  ElmcValue *end_v = NULL;
  if (elmc_new_int(&end_v, len) != RC_SUCCESS) end_v = NULL;
  ElmcValue *out = elmc_string_slice_take(n, end_v, s);
  elmc_release(end_v);
  return out;
}

ElmcValue *elmc_string_drop_right(ElmcValue *n, ElmcValue *s) {
  if (!s || s->tag != ELMC_TAG_STRING || !s->payload) return &ELMC_EMPTY_STRING;
  int64_t len = (int64_t)elmc_utf8_codepoint_count((const char *)s->payload);
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
  char utf8[8];
  int n = elmc_utf8_encode_codepoint((uint32_t)elmc_as_int(ch), utf8, sizeof(utf8));
  if (n <= 0) return elmc_retain(s);
  char prefix[8];
  memcpy(prefix, utf8, (size_t)n);
  prefix[n] = '\0';
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
      *out = elmc_maybe_nothing();
    } else {
      const char *str = (const char *)s->payload;
      if (strlen(str) == 0) {
        *out = elmc_maybe_nothing();
      } else {
        const unsigned char *p = (const unsigned char *)str;
        const unsigned char *end = p + strlen(str);
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) {
          *out = elmc_maybe_nothing();
        } else {
          rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
          CHECK_RC(rc);
          rc = elmc_new_string(&rest, (const char *)p);
          CHECK_RC(rc);
          rc = elmc_tuple2(&pair, ch, rest);
          CHECK_RC(rc);
          rc = elmc_maybe_just(out, pair);
          CHECK_RC(rc);
        }
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
      *out = elmc_list_nil();
    } else {
      const char *str = (const char *)s->payload;
      const unsigned char *p = (const unsigned char *)str;
      const unsigned char *end = p + strlen(str);
      while (p < end) {
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
        ch = elmc_new_char((elmc_int_t)cp);
        if (!ch) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
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
      rev = NULL;
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
    int64_t idx = 0;
    size_t cap = 16;
    ElmcValue *cursor = list;
    buf = (char *)elmc_malloc(cap, __func__);
    if (!buf) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      char utf8[8];
      int n = elmc_utf8_encode_codepoint((uint32_t)elmc_as_int(node->head), utf8, sizeof(utf8));
      if (n <= 0) {
        rc = RC_ERR_INVALID_ARG;
        CHECK_RC(rc);
      }
      if ((size_t)idx + (size_t)n + 1 > cap) {
        cap = ((size_t)idx + (size_t)n + 1) * 2;
        char *grown = (char *)elmc_malloc(cap, __func__);
        if (!grown) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        memcpy(grown, buf, (size_t)idx);
        elmc_free(buf);
        buf = grown;
      }
      memcpy(buf + idx, utf8, (size_t)n);
      idx += (int64_t)n;
      cursor = node->tail;
    }
    buf[idx] = '\0';
    ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
    buf = NULL;
    if (!allocated) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    *out = allocated;
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_from_char(ElmcValue **out, ElmcValue *ch) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    char buf[1] = { (char)elmc_as_int(ch) };
    rc = elmc_new_string_len(out, buf, 1);
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
      *out = &ELMC_EMPTY_STRING;
    } else {
      const char *src = (const char *)s->payload;
      int64_t target = elmc_as_int(n);
      int64_t cur_len = (int64_t)strlen(src);
      if (cur_len >= target) {
        *out = elmc_retain(s);
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
        *out = allocated;
      }
    }
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_pad_right(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
    } else {
      const char *src = (const char *)s->payload;
      int64_t target = elmc_as_int(n);
      int64_t cur_len = (int64_t)strlen(src);
      if (cur_len >= target) {
        *out = elmc_retain(s);
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
        *out = allocated;
      }
    }
  CATCH_END;
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_map(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  ElmcValue *ch = NULL;
  ElmcValue *mapped = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
    } else {
      const char *src = (const char *)s->payload;
      size_t byte_len = strlen(src);
      size_t cap = byte_len + 1;
      buf = (char *)elmc_malloc(cap, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      size_t out_len = 0;
      const unsigned char *p = (const unsigned char *)src;
      const unsigned char *end = p + byte_len;
      while (p < end) {
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
        ch = NULL;
        rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
        CHECK_RC(rc);
        ElmcValue *args[1] = { ch };
        mapped = NULL;
        rc = elmc_closure_call_rc(&mapped, f, args, 1);
        CHECK_RC(rc);
        char utf8[8];
        int n = elmc_utf8_encode_codepoint((uint32_t)elmc_as_int(mapped), utf8, sizeof(utf8));
        if (n <= 0) {
          rc = RC_ERR_INVALID_ARG;
          CHECK_RC(rc);
        }
        if (out_len + (size_t)n + 1 > cap) {
          cap = (out_len + (size_t)n + 1) * 2;
          char *grown = (char *)elmc_malloc(cap, __func__);
          if (!grown) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          memcpy(grown, buf, out_len);
          elmc_free(buf);
          buf = grown;
        }
        memcpy(buf + out_len, utf8, (size_t)n);
        out_len += (size_t)n;
        elmc_release(ch);
        ch = NULL;
        elmc_release(mapped);
        mapped = NULL;
      }
      buf[out_len] = '\0';
      ElmcValue *allocated = elmc_alloc(ELMC_TAG_STRING, buf);
      buf = NULL;
      if (!allocated) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      *out = allocated;
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(mapped);
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_filter(ElmcValue **out, ElmcValue *f, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  char *buf = NULL;
  ElmcValue *ch = NULL;
  ElmcValue *keep = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = &ELMC_EMPTY_STRING;
    } else {
      const char *src = (const char *)s->payload;
      size_t byte_len = strlen(src);
      buf = (char *)elmc_malloc(byte_len + 1, __func__);
      if (!buf) {
        rc = RC_ERR_OUT_OF_MEMORY;
        CHECK_RC(rc);
      }
      size_t out_len = 0;
      const unsigned char *p = (const unsigned char *)src;
      const unsigned char *end = p + byte_len;
      while (p < end) {
        const unsigned char *cp_start = p;
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
        ch = NULL;
        rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
        CHECK_RC(rc);
        ElmcValue *args[1] = { ch };
        keep = NULL;
        rc = elmc_closure_call_rc(&keep, f, args, 1);
        CHECK_RC(rc);
        if (elmc_as_int(keep)) {
          size_t cp_bytes = (size_t)(p - cp_start);
          memcpy(buf + out_len, cp_start, cp_bytes);
          out_len += cp_bytes;
        }
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
      *out = allocated;
    }
  CATCH_END;
  elmc_release(ch);
  elmc_release(keep);
  if (buf) elmc_free(buf);
  return rc;
}

RC elmc_string_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_retain(acc);
  ElmcValue *ch = NULL;
  ElmcValue *next = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = result;
      result = NULL;
    } else {
      const char *src = (const char *)s->payload;
      const unsigned char *p = (const unsigned char *)src;
      const unsigned char *end = p + strlen(src);
      while (p < end) {
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
        ch = NULL;
        rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
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
      *out = result;
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
  uint32_t *cps = NULL;
  CATCH_BEGIN
    if (!s || s->tag != ELMC_TAG_STRING || !s->payload) {
      *out = result;
      result = NULL;
    } else {
      const char *src = (const char *)s->payload;
      size_t cp_count = elmc_utf8_codepoint_count(src);
      if (cp_count > 0) {
        cps = (uint32_t *)elmc_malloc(cp_count * sizeof(uint32_t), __func__);
        if (!cps) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        const unsigned char *p = (const unsigned char *)src;
        const unsigned char *end = p + strlen(src);
        for (size_t i = 0; i < cp_count; i++) {
          if (!elmc_utf8_decode_codepoint(&p, end, &cps[i])) break;
        }
        for (size_t i = cp_count; i > 0; i--) {
          ch = NULL;
          rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cps[i - 1]);
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
      }
      *out = result;
      result = NULL;
    }
  CATCH_END;
  if (cps) elmc_free(cps);
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
      const unsigned char *p = (const unsigned char *)src;
      const unsigned char *end = p + strlen(src);
      while (!done && p < end) {
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
        ch = NULL;
        rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
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
      const unsigned char *p = (const unsigned char *)src;
      const unsigned char *end = p + strlen(src);
      while (!done && p < end) {
        uint32_t cp;
        if (!elmc_utf8_decode_codepoint(&p, end, &cp)) break;
        ch = NULL;
        rc = elmc_rc_assign_new_char(&ch, (elmc_int_t)cp);
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
      *out = elmc_list_nil();
    } else {
      const char *haystack = (const char *)s->payload;
      const char *needle = (const char *)sub->payload;
      if (!haystack || !needle) {
        *out = elmc_list_nil();
      } else {
        size_t nlen = strlen(needle);
        if (nlen == 0) {
          *out = elmc_list_nil();
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
      *out = elmc_retain(t);
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
      *out = elmc_retain(t);
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
      *out = elmc_retain(t);
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

#ifdef ELMC_PEBBLE_PLATFORM
static double elmc_basics_normalize_radians(double x) {
  const double pi = 3.14159265358979323846;
  const double two_pi = 6.28318530717958647692;
  while (x > pi) x -= two_pi;
  while (x < -pi) x += two_pi;
  return x;
}
#endif

double elmc_basics_sin_double(double x) {
  #ifndef ELMC_PEBBLE_PLATFORM
  return sin(x);
  #else
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
  #endif
}

ElmcValue *elmc_basics_sin(ElmcValue *x) {
  return elmc_new_float_take(elmc_basics_sin_double(elmc_as_float(x)));
}

double elmc_basics_cos_double(double x) {
  #ifndef ELMC_PEBBLE_PLATFORM
  return cos(x);
  #else
  const double half_pi = 1.57079632679489661923;
  return elmc_basics_sin_double(x + half_pi);
  #endif
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
  #ifndef ELMC_PEBBLE_PLATFORM
  return atan(x);
  #else
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
  #endif
}

ElmcValue *elmc_basics_atan(ElmcValue *x) {
  return elmc_new_float_take(elmc_basics_atan_double(elmc_as_float(x)));
}

ElmcValue *elmc_basics_atan2(ElmcValue *y, ElmcValue *x) {
  #ifndef ELMC_PEBBLE_PLATFORM
  return elmc_new_float_take(atan2(elmc_as_float(y), elmc_as_float(x)));
  #else
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
  #endif
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

RC elmc_basics_compare(ElmcValue **out, ElmcValue *a, ElmcValue *b) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    /* Returns LT (-1), EQ (0), or GT (1) as ORDER-tagged values */
    if (a && b && (a->tag == ELMC_TAG_FLOAT || b->tag == ELMC_TAG_FLOAT)) {
      double fa = elmc_as_float(a);
      double fb = elmc_as_float(b);
      if (fa < fb) {
        rc = elmc_new_order(out, -1);
        CHECK_RC(rc);
      } else if (fa > fb) {
        rc = elmc_new_order(out, 1);
        CHECK_RC(rc);
      } else {
        rc = elmc_new_order(out, 0);
        CHECK_RC(rc);
      }
    } else if (a && b && a->tag == ELMC_TAG_STRING && b->tag == ELMC_TAG_STRING) {
      const char *sa = (const char *)a->payload;
      const char *sb = (const char *)b->payload;
      int cmp = strcmp(sa ? sa : "", sb ? sb : "");
      if (cmp < 0) {
        rc = elmc_new_order(out, -1);
        CHECK_RC(rc);
      } else if (cmp > 0) {
        rc = elmc_new_order(out, 1);
        CHECK_RC(rc);
      } else {
        rc = elmc_new_order(out, 0);
        CHECK_RC(rc);
      }
    } else if (a && b && a->tag == ELMC_TAG_CHAR && b->tag == ELMC_TAG_CHAR) {
      elmc_int_t ia = elmc_as_int(a);
      elmc_int_t ib = elmc_as_int(b);
      if (ia < ib) {
        rc = elmc_new_order(out, -1);
        CHECK_RC(rc);
      } else if (ia > ib) {
        rc = elmc_new_order(out, 1);
        CHECK_RC(rc);
      } else {
        rc = elmc_new_order(out, 0);
        CHECK_RC(rc);
      }
    } else {
      elmc_int_t ia = elmc_as_int(a);
      elmc_int_t ib = elmc_as_int(b);
      if (ia < ib) {
        rc = elmc_new_order(out, -1);
        CHECK_RC(rc);
      } else if (ia > ib) {
        rc = elmc_new_order(out, 1);
        CHECK_RC(rc);
      } else {
        rc = elmc_new_order(out, 0);
        CHECK_RC(rc);
      }
    }
  CATCH_END
  return rc;
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
  return elmc_new_char(c);
}

ElmcValue *elmc_char_to_lower(ElmcValue *ch) {
  int64_t c = elmc_as_int(ch);
  if (c >= 'A' && c <= 'Z') c += 32;
  return elmc_new_char(c);
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
  ElmcValue *out = NULL;
  if (!dict) return elmc_list_nil();
  if (elmc_list_copy(&out, dict) != RC_SUCCESS) return elmc_list_nil();
  return out;
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
    *out = result;
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
    *out = result;
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
    *out = result;
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
  ElmcValue *order = elmc_basics_compare_take(left_key, right_key);
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
    *out = sorted;
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
    *out = acc;
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
  ElmcValue *rev = elmc_list_nil();
  ElmcValue *next = NULL;
  CATCH_BEGIN
    ElmcValue *cursor = set;
    while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
      ElmcCons *node = (ElmcCons *)cursor->payload;
      if (!elmc_value_equal(node->head, value)) {
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
    *out = result;
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
    *out = acc;
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
    *out = result;
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
    *out = result;
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

static int elmc_json_buf_append_indent(ElmcJsonBuffer *buf, int indent, int depth) {
  if (!elmc_json_buf_append_char(buf, '\n')) return 0;
  for (int i = 0; i < indent * depth; i++) {
    if (!elmc_json_buf_append_char(buf, ' ')) return 0;
  }
  return 1;
}

static int elmc_json_pretty_value_to_buffer(const ElmcJsonValue *value, ElmcJsonBuffer *buf, int indent, int depth) {
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
        if (!elmc_json_buf_append_indent(buf, indent, depth + 1)) return 0;
        if (!elmc_json_pretty_value_to_buffer(child, buf, indent, depth + 1)) return 0;
        first = 0;
        child = child->next;
      }
      if (!first && !elmc_json_buf_append_indent(buf, indent, depth)) return 0;
      return elmc_json_buf_append_char(buf, ']');
    }
    case ELMC_JSON_OBJECT: {
      if (!elmc_json_buf_append_char(buf, '{')) return 0;
      ElmcJsonValue *child = value->child;
      int first = 1;
      while (child) {
        if (!first && !elmc_json_buf_append_char(buf, ',')) return 0;
        if (!elmc_json_buf_append_indent(buf, indent, depth + 1)) return 0;
        if (!elmc_json_encode_string_to_buffer(child->key, buf)) return 0;
        if (!elmc_json_buf_append_char(buf, ':')) return 0;
        if (!elmc_json_pretty_value_to_buffer(child, buf, indent, depth + 1)) return 0;
        first = 0;
        child = child->next;
      }
      if (!first && !elmc_json_buf_append_indent(buf, indent, depth)) return 0;
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
  int spaces = (int)elmc_as_int(indent);
  if (spaces <= 0) {
    if (value && value->tag == ELMC_TAG_STRING && value->payload) {
      return elmc_retain(value);
    }
  }
  if (value && value->tag == ELMC_TAG_STRING && value->payload) {
    const char *raw = (const char *)value->payload;
    const char *parse_error = NULL;
    ElmcJsonValue *parsed = elmc_json_parse_document(raw, &parse_error);
    if (parsed) {
      ElmcJsonBuffer buf;
      elmc_json_buf_init(&buf);
      int ok = spaces > 0
        ? elmc_json_pretty_value_to_buffer(parsed, &buf, spaces, 0)
        : elmc_json_encode_value_to_buffer(parsed, &buf);
      elmc_json_free_value(parsed);
      if (!ok) {
        elmc_json_buf_free(&buf);
        {
          ElmcValue *_elmc_rc_out = NULL;
          if (elmc_new_string(&_elmc_rc_out, "null") != RC_SUCCESS) return NULL;
          return _elmc_rc_out;
        }
      }
      return elmc_json_buf_to_string(&buf);
    }
  }
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

#endif

#if ELMC_ALLOC_TRACK

#ifndef ELMC_ALLOC_TRACK_MAX
#define ELMC_ALLOC_TRACK_MAX 32768
#endif

typedef struct ElmcAllocTrackEntry {
  void *ptr;
  size_t size;
  uint32_t id;
  const char *context;
  const char *file;
  int line;
} ElmcAllocTrackEntry;

static ElmcAllocTrackEntry ELMC_ALLOC_TRACK_ENTRIES[ELMC_ALLOC_TRACK_MAX];
static uint32_t ELMC_ALLOC_TRACK_COUNT = 0;
static uint32_t ELMC_ALLOC_TRACK_NEXT_ID = 1;

static ElmcAllocTrackEntry *elmc_alloc_track_find(void *ptr) {
  if (!ptr) return NULL;
  for (uint32_t i = 0; i < ELMC_ALLOC_TRACK_COUNT; i++) {
    if (ELMC_ALLOC_TRACK_ENTRIES[i].ptr == ptr) return &ELMC_ALLOC_TRACK_ENTRIES[i];
  }
  return NULL;
}

static void elmc_alloc_track_register(void *ptr, size_t size, const char *context, const char *file, int line) {
  if (!ptr) return;
  if (ELMC_ALLOC_TRACK_COUNT >= ELMC_ALLOC_TRACK_MAX) return;
  ElmcAllocTrackEntry *entry = &ELMC_ALLOC_TRACK_ENTRIES[ELMC_ALLOC_TRACK_COUNT++];
  entry->ptr = ptr;
  entry->size = size;
  entry->id = ELMC_ALLOC_TRACK_NEXT_ID++;
  entry->context = context ? context : "malloc";
  entry->file = file;
  entry->line = line;
}

static void elmc_alloc_track_unregister(void *ptr) {
  if (!ptr) return;
  ElmcAllocTrackEntry *entry = elmc_alloc_track_find(ptr);
  if (!entry) return;
  uint32_t i = (uint32_t)(entry - ELMC_ALLOC_TRACK_ENTRIES);
  ELMC_ALLOC_TRACK_COUNT -= 1;
  if (i < ELMC_ALLOC_TRACK_COUNT) {
    ELMC_ALLOC_TRACK_ENTRIES[i] = ELMC_ALLOC_TRACK_ENTRIES[ELMC_ALLOC_TRACK_COUNT];
  }
}

void elmc_alloc_track_reset(void) {
  ELMC_ALLOC_TRACK_COUNT = 0;
  ELMC_ALLOC_TRACK_NEXT_ID = 1;
}

uint32_t elmc_alloc_track_live_count(void) {
  return ELMC_ALLOC_TRACK_COUNT;
}

uint32_t elmc_alloc_track_next_alloc_id(void) {
  return ELMC_ALLOC_TRACK_NEXT_ID;
}

void elmc_alloc_track_dump_since(uint32_t min_id, FILE *out) {
  if (!out) out = stderr;
  for (uint32_t i = 0; i < ELMC_ALLOC_TRACK_COUNT; i++) {
    ElmcAllocTrackEntry *entry = &ELMC_ALLOC_TRACK_ENTRIES[i];
    if (entry->id < min_id) continue;
    const char *file = entry->file ? entry->file : "?";
    fprintf(out,
            "    +malloc #%u size=%lu %s:%d (%s)\n",
            entry->id,
            (unsigned long)entry->size,
            file,
            entry->line,
            entry->context ? entry->context : "malloc");
  }
}

void elmc_alloc_track_dump_live(FILE *out) {
  if (!out) out = stderr;
  fprintf(out, "elmc alloc track: %u live malloc(s)\n", ELMC_ALLOC_TRACK_COUNT);
  for (uint32_t i = 0; i < ELMC_ALLOC_TRACK_COUNT; i++) {
    ElmcAllocTrackEntry *entry = &ELMC_ALLOC_TRACK_ENTRIES[i];
    const char *file = entry->file ? entry->file : "?";
    fprintf(out,
            "  #%u %p size=%lu %s:%d (%s)\n",
            entry->id,
            entry->ptr,
            (unsigned long)entry->size,
            file,
            entry->line,
            entry->context ? entry->context : "malloc");
  }
}

int elmc_alloc_track_check_balanced(void) {
  if (ELMC_ALLOC_TRACK_COUNT == 0) return 1;
  elmc_alloc_track_dump_live(stderr);
  return 0;
}

static void elmc_free_impl(void *ptr, const char *context, const char *file, int line) {
  (void)context;
  (void)file;
  (void)line;
  if (!ptr) return;
  elmc_alloc_track_unregister(ptr);
  free(ptr);
}

#endif


#if ELMC_ALLOC_PROBE

void elmc_alloc_probe_snap(ElmcAllocProbeSnap *snap) {
  if (!snap) return;
  snap->rc_live = elmc_rc_track_live_count();
  snap->rc_allocated = elmc_rc_allocated_count();
  snap->rc_released = elmc_rc_released_count();
  snap->rc_next_id = elmc_rc_track_next_alloc_id();
#if ELMC_ALLOC_TRACK
  snap->malloc_live = elmc_alloc_track_live_count();
  snap->malloc_next_id = elmc_alloc_track_next_alloc_id();
#endif
}

void elmc_alloc_probe_diff(const ElmcAllocProbeSnap *before, const char *label, FILE *out) {
  if (!before) return;
  if (!out) out = stderr;
  ElmcAllocProbeSnap after = {0};
  elmc_alloc_probe_snap(&after);

  int64_t rc_net = (int64_t)(after.rc_allocated - before->rc_allocated) -
                   (int64_t)(after.rc_released - before->rc_released);
  int32_t rc_live_delta = (int32_t)after.rc_live - (int32_t)before->rc_live;
#if ELMC_ALLOC_TRACK
  int32_t malloc_live_delta = (int32_t)after.malloc_live - (int32_t)before->malloc_live;
#endif

  fprintf(out,
          "probe %s: rc_live %+d rc_net %+lld",
          label ? label : "?",
          rc_live_delta,
          (long long)rc_net);
#if ELMC_ALLOC_TRACK
  fprintf(out, " malloc_live %+d", malloc_live_delta);
#endif
  fprintf(out, "\n");

  if (rc_net != 0 || rc_live_delta != 0) {
    elmc_rc_track_dump_since(before->rc_next_id, out);
  }
#if ELMC_ALLOC_TRACK
  if (malloc_live_delta != 0) {
    elmc_alloc_track_dump_since(before->malloc_next_id, out);
  }
#endif
}

int elmc_alloc_probe_diff_balanced(const ElmcAllocProbeSnap *before, const char *label, FILE *out) {
  if (!before) return 0;
  ElmcAllocProbeSnap after = {0};
  elmc_alloc_probe_snap(&after);

  int64_t rc_net = (int64_t)(after.rc_allocated - before->rc_allocated) -
                   (int64_t)(after.rc_released - before->rc_released);
#if ELMC_ALLOC_TRACK
  int32_t malloc_live_delta = (int32_t)after.malloc_live - (int32_t)before->malloc_live;
  if (malloc_live_delta != 0) {
    elmc_alloc_probe_diff(before, label, out);
    return 0;
  }
#endif

  if (rc_net != 0) {
    elmc_alloc_probe_diff(before, label, out);
    return 0;
  }

  return 1;
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
    case ELMC_TAG_INT_LIST: return "IntList";
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

uint32_t elmc_rc_track_next_alloc_id(void) {
  return ELMC_RC_TRACK_NEXT_ID;
}

void elmc_rc_track_dump_since(uint32_t min_id, FILE *out) {
  if (!out) out = stderr;
  for (uint32_t i = 0; i < ELMC_RC_TRACK_COUNT; i++) {
    ElmcRcTrackEntry *entry = &ELMC_RC_TRACK_ENTRIES[i];
    if (entry->id < min_id) continue;
    const char *alloc_file = entry->alloc_file ? entry->alloc_file : "?";
    fprintf(out,
            "    +rc #%u %s rc=%u alloc=%s:%d (%s)\n",
            entry->id,
            elmc_rc_track_tag_name((ElmcTag)entry->tag),
            entry->rc,
            alloc_file,
            entry->alloc_line,
            entry->alloc_context ? entry->alloc_context : "alloc");
  }
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
  elmc_free(cell->payload);
  elmc_free(cell);
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
    /* Stop when the tail spine is still borrowed elsewhere (for example
       releasing a temporary `first :: rest` cons must not tear down `rest`). */
    if (next && next->tag == ELMC_TAG_LIST && next->payload != NULL && next->rc > 1) {
      elmc_release(next);
      elmc_release_list_cell_payload(cell);
      return;
    }
    cursor = next;
    elmc_release_list_cell_payload(cell);
  }
  if (cursor && cursor->rc != ELMC_RC_IMMORTAL && cursor->tag != ELMC_TAG_LIST) {
    elmc_release(cursor);
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
  } else if (value->tag == ELMC_TAG_INT_LIST) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_int_list_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_INT_SPINE) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_int_spine_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_FLOAT_LIST) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_float_list_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_RECORD_SEQ) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_record_seq_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_LIST && value->payload != NULL) {
    elmc_release_list_spine(value);
    return;
  } else if (value->tag == ELMC_TAG_MAYBE && value->payload != NULL) {
    ElmcMaybe *maybe = (ElmcMaybe *)value->payload;
    if (maybe->value) elmc_release(maybe->value);
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_maybe_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_RESULT && value->payload != NULL) {
    ElmcResult *result = (ElmcResult *)value->payload;
    if (result->value) elmc_release(result->value);
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_result_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (tuple->first) elmc_release(tuple->first);
    if (tuple->second) elmc_release(tuple->second);
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_tuple2_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_RECORD && value->payload != NULL) {
    ElmcRecord *rec = (ElmcRecord *)value->payload;
    for (int i = 0; i < rec->field_count; i++) {
      if (rec->field_values[i]) elmc_release(rec->field_values[i]);
    }
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_record_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
    elmc_free(rec->field_values);
  } else if (value->tag == ELMC_TAG_CLOSURE && value->payload != NULL) {
    ElmcClosure *clo = (ElmcClosure *)value->payload;
    for (int i = 0; i < clo->capture_count; i++) {
      if (clo->captures[i]) elmc_release(clo->captures[i]);
    }
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_closure_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
    elmc_free(clo->captures);
  } else if (value->tag == ELMC_TAG_FORWARD_REF && value->payload != NULL) {
    elmc_free(value->payload);
  }
  if (value->tag == ELMC_TAG_INT_LIST && elmc_int_list_cell_release(value)) {
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_INT_SPINE && elmc_int_spine_cell_release(value)) {
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_FLOAT_LIST && elmc_float_list_cell_release(value)) {
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_RECORD_SEQ && elmc_record_seq_cell_release(value)) {
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_LIST) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_list_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  }
  if (value->tag == ELMC_TAG_CMD) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_cmd_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  }
  if (value->tag == ELMC_TAG_SUB) {
  #if ELMC_RC_TRACK
    elmc_rc_track_drop_owned(value);
  #endif
    if (elmc_sub_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  }
  if (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL) {
    elmc_free(value->payload);
  }
  elmc_free(value);
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
