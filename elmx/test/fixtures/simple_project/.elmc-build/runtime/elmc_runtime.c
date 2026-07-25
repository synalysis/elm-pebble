#include "elmc_runtime.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>
#include <math.h>
#define ELMC_JSON_FLOAT_NUMBERS 0


#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
#define ELMC_PEBBLE_PLATFORM 1
#endif
#ifdef ELMC_PEBBLE_PLATFORM
#include <pebble.h>
#endif
#if defined(__GNUC__)
#define ELMC_UNUSED __attribute__((unused))
#define ELMC_MAYBE_UNUSED __attribute__((unused))
#else
#define ELMC_UNUSED
#define ELMC_MAYBE_UNUSED
#endif

#ifdef ELMC_PEBBLE_PLATFORM
static uint32_t ELMC_ALLOCATED = 0;
static uint32_t ELMC_RELEASED = 0;
#else
static uint64_t ELMC_ALLOCATED = 0;
static uint64_t ELMC_RELEASED = 0;
#endif

#define ELMC_PROCESS_MAX_SLOTS 2
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
#define ELMC_SMALL_INT_MAX 3
const ElmcValue ELMC_SMALL_INTS[ELMC_SMALL_INT_MAX - ELMC_SMALL_INT_MIN + 1] = {
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, -1 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 0 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 1 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 2 },
      { ELMC_RC_IMMORTAL, ELMC_TAG_INT, NULL, 3 }
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


void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line);
void *elmc_calloc_impl(size_t nmemb, size_t size, const char *context, const char *file, int line);

#if ELMC_ALLOC_TRACK

#endif


#if ELMC_ALLOC_TRACE
#define elmc_malloc(size, context) elmc_malloc_impl((size), (context), __FILE__, __LINE__)
#define elmc_calloc(nmemb, size, context) elmc_calloc_impl((nmemb), (size), (context), __FILE__, __LINE__)
#define elmc_alloc(tag, payload) elmc_alloc_impl((tag), (payload), __FILE__, __LINE__)
#else
#define elmc_malloc(size, context) elmc_malloc_impl((size), (context), NULL, 0)
#define elmc_calloc(nmemb, size, context) elmc_calloc_impl((nmemb), (size), (context), NULL, 0)
#define elmc_alloc(tag, payload) elmc_alloc_impl((tag), (payload), NULL, 0)
#endif
#define elmc_realloc(ptr, size, context) elmc_realloc_impl((ptr), (size), (context))

#if ELMC_RC_TRACK
#define ELMC_RC_TRACK_REGISTER(value, context) \
  elmc_rc_track_register((value), (context), __FILE__, __LINE__)

#else
#define ELMC_RC_TRACK_REGISTER(value, context) ((void)0)
#endif


static void elmc_log_alloc_failed(const char *context, size_t size, const char *file, int line) {
  if (file && line > 0) {
    APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC malloc failed %s %s:%d %lu",
            context ? context : "?", file, line, (unsigned long)size);
  } else {
    APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC malloc failed %s %lu",
            context ? context : "?", (unsigned long)size);
  }
}

void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line) {
  void *ptr = malloc(size);
  if (!ptr) {
    elmc_log_alloc_failed(context, size, file, line);
  }
  return ptr;
}

void *elmc_calloc_impl(size_t nmemb, size_t size, const char *context, const char *file, int line) {
  void *ptr = calloc(nmemb, size);
  if (!ptr) {
    elmc_log_alloc_failed(context, nmemb * size, file, line);
  }
  return ptr;
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
  cell->record.mutation_gen = 0;
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
  cell->record.mutation_gen = 0;
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

static ElmcIntListPayload *elmc_int_list_payload(ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_INT_LIST || !list->payload) return NULL;
  return (ElmcIntListPayload *)list->payload;
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

static int elmc_int_spine_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_INT_SPINE || value->scalar != ELMC_INT_SPINE_CELL_SCALAR) return 0;
  ElmcIntSpineCell *cell = (ElmcIntSpineCell *)value;
  if (value->payload != &cell->spine) return 0;
  elmc_release(cell->spine.tail);
  elmc_free(cell);
  return 1;
}

static int elmc_float_list_cell_release(ElmcValue *value) {
  (void)value;
  return 0;
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

RC elmc_render_cmd6_take(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
  RC rc = RC_SUCCESS;
  const elmc_int_t ps[6] = { p0, p1, p2, p3, p4, p5 };
  CATCH_BEGIN
    ElmcValue *tail = elmc_int_zero();
    for (int i = 5; i >= 0; i--) {
      ElmcValue *pv = elmc_new_int_take(ps[i]);
      if (!pv) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
      ElmcValue *pair = NULL;
      rc = elmc_tuple2_take(&pair, pv, tail);
      CHECK_RC(rc);
      tail = pair;
    }
    ElmcValue *kind_v = elmc_new_int_take(kind);
    if (!kind_v) { rc = RC_ERR_OUT_OF_MEMORY; CHECK_RC(rc); }
    rc = elmc_tuple2_take(out, kind_v, tail);
    CHECK_RC(rc);
  CATCH_END;
  return rc;
}

ElmcValue *elmc_maybe_nothing(void) {
  return &ELMC_MAYBE_NOTHING;
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

static ElmcValue *elmc_platform_manager_batch(elmc_int_t tag_num, ElmcValue *items) {
  static const char *names[] = {"$", "m"};
  ElmcValue *list = items ? elmc_retain(items) : elmc_list_nil();
  ElmcValue *values[2] = {elmc_platform_manager_tag(tag_num), list};
  return elmc_record_new_static_take_value(2, names, values);
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

static int elmc_cmd_cell_is_none(ElmcValue *value) {
  return !value || ((value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) && elmc_as_int(value) == 0);
}

static ElmcValue *elmc_cmd_batch_push_back(ElmcValue *flat, ElmcValue *entry) {
  if (!entry) return flat;
  if (elmc_cmd_cell_is_none(entry)) return flat;
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
  if (elmc_cmd_cell_is_none(entry)) return flat;
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
    ElmcValue *flat = elmc_cmd_batch_append_entry(NULL, commands);
    if (flat) return flat;
    return elmc_platform_manager_batch(2, commands);
  }
  if (elmc_list_all_tag(commands, ELMC_TAG_CMD)) {
    return elmc_platform_manager_batch(2, commands);
  }

  ElmcValue *flat = elmc_cmd_batch_append_entry(NULL, commands);
  if (flat) {
    return elmc_platform_manager_batch(2, flat);
  }
  return elmc_platform_manager_batch(2, commands);
}

RC elmc_cmd1(ElmcValue **out, elmc_int_t kind, elmc_int_t p0) {
  return elmc_cmd_alloc(out, 1, kind, p0, 0, 0, 0, 0, 0);
}

RC elmc_cmd2(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1) {
  return elmc_cmd_alloc(out, 2, kind, p0, p1, 0, 0, 0, 0);
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

RC elmc_sub1(ElmcValue **out, elmc_int_t mask, elmc_int_t p0) {
  return elmc_sub_alloc(out, 1, mask, p0, 0, 0, 0, 0, 0);
}

RC elmc_sub3(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
  return elmc_sub_alloc(out, 3, mask, p0, p1, p2, 0, 0, 0);
}

elmc_int_t elmc_as_int(ElmcValue *value) {
  if (!value || (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL && value->tag != ELMC_TAG_CHAR && value->tag != ELMC_TAG_ORDER)) return 0;
  if (value->tag == ELMC_TAG_INT && value->scalar == ELMC_UNIT_SCALAR) return 0;
  return value->scalar;
}

elmc_int_t elmc_as_int_number(ElmcValue *value) {
  return elmc_as_int(value);
}

ElmcValue *elmc_tuple_second(ElmcValue *tuple) {
  if (!tuple) return elmc_int_zero();
  if (tuple->tag == ELMC_TAG_RESULT && tuple->payload != NULL) {
    ElmcResult *data = (ElmcResult *)tuple->payload;
    return data->value ? elmc_retain(data->value) : elmc_int_zero();
  }
  if (tuple->tag == ELMC_TAG_MAYBE && tuple->payload != NULL) {
    ElmcMaybe *data = (ElmcMaybe *)tuple->payload;
    return data->is_just && data->value ? elmc_retain(data->value) : elmc_int_zero();
  }
  if (tuple->tag != ELMC_TAG_TUPLE2 || tuple->payload == NULL) return elmc_int_zero();
  ElmcTuple2 *data = (ElmcTuple2 *)tuple->payload;
  return elmc_retain(data->second);
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

uint32_t elmc_record_mutation_gen(ElmcValue *record) {
  if (!record || record->tag != ELMC_TAG_RECORD || !record->payload) return 0;
  return ((ElmcRecord *)record->payload)->mutation_gen;
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

static ElmcValue *elmc_retain_impl(ElmcValue *value) {
  if (!value) return NULL;
  if (value->rc == ELMC_RC_IMMORTAL) return value;
  if (value->rc < ELMC_RC_IMMORTAL - 1) value->rc += 1;
  return value;
}

ElmcValue *elmc_retain(ElmcValue *value) {
  return elmc_retain_impl(value);
}

static void elmc_release_list_cell_payload(ElmcValue *cell) {
  if (!cell || cell->tag != ELMC_TAG_LIST || !cell->payload) return;
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
    if (elmc_int_list_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_INT_SPINE) {
    if (elmc_int_spine_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_FLOAT_LIST) {
    if (elmc_float_list_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_RECORD_SEQ) {
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
    if (elmc_maybe_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_RESULT && value->payload != NULL) {
    ElmcResult *result = (ElmcResult *)value->payload;
    if (result->value) elmc_release(result->value);
    if (elmc_result_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_TUPLE2 && value->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)value->payload;
    if (tuple->first) elmc_release(tuple->first);
    if (tuple->second) elmc_release(tuple->second);
    if (elmc_tuple2_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  } else if (value->tag == ELMC_TAG_RECORD && value->payload != NULL) {
    ElmcRecord *rec = (ElmcRecord *)value->payload;
    for (int i = 0; i < rec->field_count; i++) {
      if (rec->field_values[i]) elmc_release(rec->field_values[i]);
    }
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
    if (elmc_list_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  }
  if (value->tag == ELMC_TAG_CMD) {
    if (elmc_cmd_cell_release(value)) {
      ELMC_RELEASED += 1;
      return;
    }
  }
  if (value->tag == ELMC_TAG_SUB) {
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

void elmc_release(ElmcValue *value) {
  elmc_release_impl(value);
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
