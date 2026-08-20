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
static ElmcValue ELMC_BOOL_FALSE ELMC_UNUSED = { ELMC_RC_IMMORTAL, ELMC_TAG_BOOL, NULL, 0 };
static ElmcValue ELMC_BOOL_TRUE ELMC_UNUSED = { ELMC_RC_IMMORTAL, ELMC_TAG_BOOL, NULL, 1 };
/* Keep all type/macro/immortal preamble above the first function so
   prune_source (preamble + kept bodies) does not drop cell typedefs. */
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
static ElmcValue ELMC_EMPTY_STRING ELMC_UNUSED = { ELMC_RC_IMMORTAL, ELMC_TAG_STRING, ELMC_EMPTY_STRING_PAYLOAD, 0 };
static ElmcIntListPayload ELMC_EMPTY_INT_LIST_PAYLOAD = { NULL, 0, 0 };
static ElmcValue ELMC_EMPTY_INT_LIST ELMC_UNUSED = {
  ELMC_RC_IMMORTAL,
  ELMC_TAG_INT_LIST,
  (void *)&ELMC_EMPTY_INT_LIST_PAYLOAD,
  ELMC_INT_LIST_CELL_SCALAR
};
ElmcValue ELMC_LIST_NIL = { ELMC_RC_IMMORTAL, ELMC_TAG_LIST, NULL, 0 };

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


static ElmcValue *elmc_bool(int value) {
  return value ? &ELMC_BOOL_TRUE : &ELMC_BOOL_FALSE;
}

static void elmc_log_alloc_failed(const char *context, size_t size, const char *file, int line) {
  /* Host APP_LOG stubs may discard format args; keep params live for -Wextra. */
  (void)context;
  (void)size;
  (void)file;
  (void)line;
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
  CATCH_END
  elmc_release(cell);
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

static int ELMC_UNUSED elmc_float_list_cell_release(ElmcValue *value) {
  (void)value;
  return 0;
}

static int ELMC_UNUSED elmc_record_seq_cell_release(ElmcValue *value) {
  (void)value;
  return 0;
}

static ElmcLazyMapPayload *elmc_lazy_map_payload(ElmcValue *list) {
  if (!list || list->tag != ELMC_TAG_LAZY_MAP || !list->payload) return NULL;
  return (ElmcLazyMapPayload *)list->payload;
}

static int elmc_lazy_map_cell_release(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_LAZY_MAP || value->scalar != ELMC_LAZY_MAP_CELL_SCALAR) return 0;
  ElmcLazyMapCell *cell = (ElmcLazyMapCell *)value;
  if (value->payload != &cell->data) return 0;
  if (cell->data.source) elmc_release(cell->data.source);
  if (cell->data.captures) {
    for (int i = 0; i < cell->data.capture_count; i++) {
      if (cell->data.captures[i]) elmc_release(cell->data.captures[i]);
    }
    elmc_free(cell->data.captures);
  }
  elmc_free(cell);
  return 1;
}

int elmc_lazy_map_length(ElmcValue *list) {
  ElmcLazyMapPayload *payload = elmc_lazy_map_payload(list);
  if (!payload) return 0;
  return (int)elmc_list_length_native(payload->source);
}

RC elmc_lazy_map_nth(ElmcValue **out, ElmcValue *list, int index) {
  ElmcLazyMapPayload *payload = elmc_lazy_map_payload(list);
  RC rc = RC_SUCCESS;
  ElmcValue *arg = NULL;
  CATCH_BEGIN
    if (!payload || !payload->mapper || index < 0) {
      rc = RC_ERR_INVALID_ARG;
      CHECK_RC(rc);
    }
    if (payload->source && payload->source->tag == ELMC_TAG_INT_LIST) {
      ElmcIntListPayload *src = (ElmcIntListPayload *)payload->source->payload;
      if (!src || index >= src->length) {
        rc = RC_ERR_INVALID_ARG;
        CHECK_RC(rc);
      }
      rc = elmc_new_int(&arg, src->values[index]);
      CHECK_RC(rc);
    } else {
      rc = RC_ERR_UNSUPPORTED;
      CHECK_RC(rc);
    }
    ElmcValue *args[1] = { arg };
    ElmcLazyMapFn mapper = (ElmcLazyMapFn)payload->mapper;
    rc = mapper(out, args, 1, payload->captures, payload->capture_count);
    CHECK_RC(rc);
  CATCH_END
  elmc_release(arg);
  return rc;
}

RC elmc_lazy_map_to_cons(ElmcValue **out, ElmcValue *list) {
  RC rc = RC_SUCCESS;
  ElmcValue *result = elmc_list_nil();
  ElmcValue *item = NULL;
  ElmcValue *next = NULL;
  int n = elmc_lazy_map_length(list);
  CATCH_BEGIN
    for (int i = n - 1; i >= 0; i--) {
      item = NULL;
      rc = elmc_lazy_map_nth(&item, list, i);
      CHECK_RC(rc);
      next = NULL;
      rc = elmc_list_cons(&next, item, result);
      CHECK_RC(rc);
      elmc_release(item);
      item = NULL;
      elmc_release(result);
      result = next;
      next = NULL;
    }
    *out = result;
    result = NULL;
  CATCH_END
  elmc_release(item);
  elmc_release(next);
  elmc_release(result);
  return rc;
}

RC elmc_list_materialize_cons(ElmcValue **out, ElmcValue *list) {
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return elmc_int_list_to_cons(out, list);
  }if (list && list->tag == ELMC_TAG_LAZY_MAP) {
    return elmc_lazy_map_to_cons(out, list);
  }
  *out = elmc_retain(list);
  return RC_SUCCESS;
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
  CATCH_END
  return rc;
}

RC elmc_new_bool(ElmcValue **out, int value) {
  *out = elmc_bool(value);
  return RC_SUCCESS;
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
  CATCH_END
  if (ptr) elmc_free(ptr);
  return rc;
}

ElmcValue *elmc_list_nil(void) {
  return &ELMC_LIST_NIL;
}

RC elmc_list_cons(ElmcValue **out, ElmcValue *head, ElmcValue *tail) {
  RC rc = RC_SUCCESS;
  ElmcValue *owned_tail = NULL;
  CATCH_BEGIN
    ElmcValue *use_tail = tail;
    /* Compact INT_LIST / RECORD_SEQ tails must become cons cells; otherwise
       `42 :: [1,2,3]` stores an opaque tail that Debug/toString walks as []. */
    if (tail && tail->tag != ELMC_TAG_LIST) {
      rc = elmc_list_materialize_cons(&owned_tail, tail);
      CHECK_RC(rc);
      use_tail = owned_tail;
    }
    rc = elmc_list_cell_alloc(out, head, use_tail, 0);
    CHECK_RC(rc);
  CATCH_END
  elmc_release(owned_tail);
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

RC elmc_result_ok_own(ElmcValue **out, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  ElmcResultCell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcResultCell *)elmc_malloc(sizeof(ElmcResultCell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    cell->result.is_ok = 1;
    cell->result.value = value;
    cell->value.rc = 1;
    cell->value.tag = ELMC_TAG_RESULT;
    cell->value.payload = &cell->result;
    cell->value.scalar = ELMC_RESULT_CELL_SCALAR;
    ELMC_ALLOCATED += 1;
    ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
    *out = &cell->value;
    cell = NULL;
  CATCH_END
  if (cell) {
    elmc_release(value);
    elmc_release(&cell->value);
  }
  return rc;
}

RC elmc_result_err_own(ElmcValue **out, ElmcValue *value) {
  RC rc = RC_SUCCESS;
  ElmcResultCell *cell = NULL;
  CATCH_BEGIN
    cell = (ElmcResultCell *)elmc_malloc(sizeof(ElmcResultCell), __func__);
    if (!cell) {
      rc = RC_ERR_OUT_OF_MEMORY;
      CHECK_RC(rc);
    }
    cell->result.is_ok = 0;
    cell->result.value = value;
    cell->value.rc = 1;
    cell->value.tag = ELMC_TAG_RESULT;
    cell->value.payload = &cell->result;
    cell->value.scalar = ELMC_RESULT_CELL_SCALAR;
    ELMC_ALLOCATED += 1;
    ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
    *out = &cell->value;
    cell = NULL;
  CATCH_END
  if (cell) {
    elmc_release(value);
    elmc_release(&cell->value);
  }
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
  CATCH_END
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
  CATCH_END
  if (cell) {
    elmc_release(&cell->value);
  } else if (rc != RC_SUCCESS) {
    elmc_release(first);
    elmc_release(second);
  }
  return rc;
}

int elmc_cmd_is_none(ElmcValue *value) {
  if (!value) return 1;
  if ((value->tag == ELMC_TAG_INT || value->tag == ELMC_TAG_BOOL) && elmc_as_int(value) == 0) {
    return 1;
  }
  if (value->tag == ELMC_TAG_CMD && value->payload != NULL) {
    ElmcCmdPayload *cmd = (ElmcCmdPayload *)value->payload;
    return cmd->kind == 0;
  }
  return 0;
}

ElmcValue *elmc_cmd_none(void) {
  return elmc_int_zero();
}

RC elmc_cmd_queue_cons_take(ElmcValue **out, ElmcValue *head, ElmcValue *tail) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_list_cons(out, head, tail);
    CHECK_RC(rc);
    /* elmc_list_cons retains head/tail; take semantics drop caller ownership. */
    elmc_release(head);
    elmc_release(tail);
  CATCH_END
  return rc;
}

RC elmc_cmd_queue_push_back_take(ElmcValue **out, ElmcValue *queue, ElmcValue *cmd) {
  RC rc = RC_SUCCESS;
  ElmcValue *cell = NULL;
  ElmcValue *head_cell = NULL;
  CATCH_BEGIN
    if (!cmd || elmc_cmd_is_none(cmd)) {
      elmc_release(cmd);
      cmd = NULL;
      *out = queue ? queue : elmc_cmd_none();
      queue = NULL;
    } else if (!queue || elmc_cmd_is_none(queue)) {
      elmc_release(queue);
      queue = NULL;
      *out = cmd;
      cmd = NULL;
    } else {
      rc = elmc_cmd_queue_cons_take(&cell, cmd, elmc_list_nil());
      cmd = NULL;
      CHECK_RC(rc);
      if (!cell || elmc_cmd_is_none(cell)) {
        *out = queue ? queue : elmc_cmd_none();
        queue = NULL;
        cell = NULL;
      } else if (queue->tag == ELMC_TAG_CMD) {
        rc = elmc_cmd_queue_cons_take(&head_cell, queue, cell);
        queue = NULL;
        cell = NULL;
        CHECK_RC(rc);
        *out = head_cell ? head_cell : elmc_cmd_none();
        head_cell = NULL;
      } else if (queue->tag != ELMC_TAG_LIST) {
        elmc_release(cell);
        cell = NULL;
        *out = queue;
        queue = NULL;
      } else {
        ElmcValue **tail = &queue;
        ElmcValue *cursor = queue;
        while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
          ElmcCons *node = (ElmcCons *)cursor->payload;
          tail = &node->tail;
          cursor = node->tail;
        }
        *tail = cell;
        cell = NULL;
        *out = queue;
        queue = NULL;
      }
    }
  CATCH_END
  elmc_release(cmd);
  elmc_release(queue);
  elmc_release(cell);
  elmc_release(head_cell);
  return rc;
}

RC elmc_cmd_queue_concat_take(ElmcValue **out, ElmcValue *left, ElmcValue *right) {
  RC rc = RC_SUCCESS;
  ElmcValue *tail_cell = NULL;
  ElmcValue *pair = NULL;
  CATCH_BEGIN
    if (!left || elmc_cmd_is_none(left)) {
      elmc_release(left);
      left = NULL;
      *out = right ? right : elmc_cmd_none();
      right = NULL;
    } else if (!right || elmc_cmd_is_none(right)) {
      elmc_release(right);
      right = NULL;
      *out = left;
      left = NULL;
    } else if (left->tag == ELMC_TAG_CMD) {
      if (right->tag == ELMC_TAG_CMD) {
        rc = elmc_cmd_queue_cons_take(&tail_cell, right, elmc_list_nil());
        right = NULL;
        CHECK_RC(rc);
        rc = elmc_cmd_queue_cons_take(&pair, left, tail_cell ? tail_cell : elmc_list_nil());
        left = NULL;
        tail_cell = NULL;
        CHECK_RC(rc);
        *out = pair;
        pair = NULL;
      } else if (right->tag == ELMC_TAG_LIST) {
        rc = elmc_cmd_queue_cons_take(&pair, left, right);
        left = NULL;
        right = NULL;
        CHECK_RC(rc);
        *out = pair;
        pair = NULL;
      } else {
        elmc_release(right);
        right = NULL;
        *out = left;
        left = NULL;
      }
    } else if (right->tag == ELMC_TAG_CMD) {
      rc = elmc_cmd_queue_push_back_take(out, left, right);
      left = NULL;
      right = NULL;
      CHECK_RC(rc);
    } else if (right->tag != ELMC_TAG_LIST) {
      elmc_release(right);
      right = NULL;
      *out = left;
      left = NULL;
    } else if (left->tag != ELMC_TAG_LIST) {
      elmc_release(left);
      left = NULL;
      *out = right;
      right = NULL;
    } else {
      ElmcValue **tail = &left;
      ElmcValue *cursor = left;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        tail = &node->tail;
        cursor = node->tail;
      }
      *tail = right;
      right = NULL;
      *out = left;
      left = NULL;
    }
  CATCH_END
  elmc_release(left);
  elmc_release(right);
  elmc_release(tail_cell);
  elmc_release(pair);
  return rc;
}

ElmcValue *elmc_cmd_queue_peel_manager(ElmcValue *value) {
  if (!value || value->tag != ELMC_TAG_RECORD) {
    return NULL;
  }

  ElmcValue *tag = elmc_record_get(value, "$");
  if (!tag) {
    return NULL;
  }

  elmc_int_t tag_num = elmc_as_int(tag);
  elmc_release(tag);

  if (tag_num == 2) {
    return elmc_record_get(value, "m");
  }

  if (tag_num == 3) {
    return elmc_record_get(value, "o");
  }

  return NULL;
}

RC elmc_cmd_queue_push_entry(ElmcValue **out, ElmcValue *flat, ElmcValue *entry) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    for (;;) {
      ElmcValue *peeled = elmc_cmd_queue_peel_manager(entry);
      if (!peeled) {
        break;
      }

      elmc_release(entry);
      entry = peeled;
    }

    if (!entry) {
      *out = flat ? flat : elmc_cmd_none();
      flat = NULL;
    } else if (elmc_cmd_is_none(entry)) {
      elmc_release(entry);
      entry = NULL;
      *out = flat ? flat : elmc_cmd_none();
      flat = NULL;
    } else if (entry->tag == ELMC_TAG_LIST) {
      ElmcValue *cursor = entry;
      ElmcValue *current_flat = flat;
      flat = NULL;
      while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
        ElmcCons *node = (ElmcCons *)cursor->payload;
        ElmcValue *head = node->head;
        node->head = NULL;
        rc = elmc_cmd_queue_push_entry(&current_flat, current_flat, head);
        CHECK_RC(rc);
        ElmcValue *next = node->tail;
        node->tail = NULL;
        ElmcValue *cursor_cell = cursor;
        cursor = next;
        elmc_release(cursor_cell);
      }
      /* List spine cells were released in the loop; do not release entry again. */
      entry = NULL;
      *out = current_flat;
    } else {
      rc = elmc_cmd_queue_push_back_take(out, flat, entry);
      flat = NULL;
      entry = NULL;
      CHECK_RC(rc);
    }
  CATCH_END
  elmc_release(flat);
  elmc_release(entry);
  return rc;
}

RC elmc_cmd_queue_normalize(ElmcValue **out, ElmcValue *cmd) {
  RC rc = RC_SUCCESS;
  ElmcValue *flat = NULL;
  ElmcValue *materialized = NULL;
  CATCH_BEGIN
    if (!cmd || elmc_cmd_is_none(cmd)) {
      elmc_release(cmd);
      cmd = NULL;
      *out = elmc_cmd_none();
    } else {
      materialized = cmd;
      cmd = NULL;

      for (;;) {
        ElmcValue *peeled = elmc_cmd_queue_peel_manager(materialized);
        if (!peeled) {
          break;
        }

        elmc_release(materialized);
        materialized = peeled;
      }

      if (!materialized || elmc_cmd_is_none(materialized)) {
        elmc_release(materialized);
        materialized = NULL;
        *out = elmc_cmd_none();
      } else if (materialized->tag != ELMC_TAG_LIST) {
        flat = elmc_cmd_none();
        rc = elmc_cmd_queue_push_back_take(&flat, flat, materialized);
        materialized = NULL;
        CHECK_RC(rc);
        *out = flat;
        flat = NULL;
      } else {
        flat = elmc_cmd_none();
        rc = elmc_cmd_queue_push_entry(&flat, flat, materialized);
        CHECK_RC(rc);
        materialized = NULL;
        *out = flat;
        flat = NULL;
      }
    }
  CATCH_END
  elmc_release(cmd);
  elmc_release(materialized);
  elmc_release(flat);
  return rc;
}

elmc_int_t elmc_as_int(ElmcValue *value) {
  if (!value || (value->tag != ELMC_TAG_INT && value->tag != ELMC_TAG_BOOL && value->tag != ELMC_TAG_CHAR && value->tag != ELMC_TAG_ORDER)) return 0;
  if (value->tag == ELMC_TAG_INT && value->scalar == ELMC_UNIT_SCALAR) return 0;
  return value->scalar;
}

RC elmc_record_new_values(ElmcValue **out, int field_count, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_record_cell_alloc_values(out, field_count, field_values, 0);
    CHECK_RC(rc);
  CATCH_END
  return rc;
}

RC elmc_record_new_values_take(ElmcValue **out, int field_count, ElmcValue **field_values) {
  RC rc = RC_SUCCESS;
  CATCH_BEGIN
    rc = elmc_record_cell_alloc_values(out, field_count, field_values, 1);
    CHECK_RC(rc);
  CATCH_END
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

elmc_int_t elmc_list_length_native(ElmcValue *list) {
  if (list && list->tag == ELMC_TAG_INT_LIST) {
    return (elmc_int_t)elmc_int_list_length_native(list);
  }if (list && list->tag == ELMC_TAG_LAZY_MAP) {
    return (elmc_int_t)elmc_lazy_map_length(list);
  }
  elmc_int_t count = 0;
  ElmcValue *cursor = list;
  while (cursor && cursor->tag == ELMC_TAG_LIST && cursor->payload != NULL) {
    count += 1;
    cursor = ((ElmcCons *)cursor->payload)->tail;
  }
  return count;
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
  } else if (value->tag == ELMC_TAG_LAZY_MAP) {
    if (elmc_lazy_map_cell_release(value)) {
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
    /* Payload is a heap ElmcForwardRef*; free it here and return so the
       generic elmc_free(value->payload) fallthrough below cannot double-free. */
    elmc_free(value->payload);
    elmc_free(value);
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_INT_LIST && elmc_int_list_cell_release(value)) {
    ELMC_RELEASED += 1;
    return;
  }
  if (value->tag == ELMC_TAG_INT_SPINE && elmc_int_spine_cell_release(value)) {
    ELMC_RELEASED += 1;
    return;
  }
  
  
  if (value->tag == ELMC_TAG_LAZY_MAP && elmc_lazy_map_cell_release(value)) {
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
