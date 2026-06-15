#ifndef ELMC_RUNTIME_H
#define ELMC_RUNTIME_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>


#if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
#ifndef ELMC_PEBBLE_PLATFORM
#define ELMC_PEBBLE_PLATFORM 1
#endif
#include <pebble.h>
#endif

#if defined(ELMC_PEBBLE_INT32) || defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_GABBRO)
typedef int32_t elmc_int_t;
#else
typedef int64_t elmc_int_t;
#endif

typedef enum {
  ELMC_TAG_INT = 1,
  ELMC_TAG_BOOL = 2,
  ELMC_TAG_STRING = 3,
  ELMC_TAG_LIST = 4,
  ELMC_TAG_RESULT = 5,
  ELMC_TAG_MAYBE = 6,
  ELMC_TAG_TUPLE2 = 7,
  ELMC_TAG_PORT_PAYLOAD = 9,
  ELMC_TAG_FLOAT = 10,
  ELMC_TAG_RECORD = 11,
  ELMC_TAG_CLOSURE = 12,
  ELMC_TAG_FORWARD_REF = 13,
  ELMC_TAG_CMD = 14,
  ELMC_TAG_SUB = 15
} ElmcTag;

typedef struct ElmcValue {
  uint16_t rc;
  uint8_t tag;
  void *payload;
  elmc_int_t scalar;
} ElmcValue;

typedef struct ElmcCons {
  ElmcValue *head;
  ElmcValue *tail;
} ElmcCons;

#ifndef ELMC_RC_IMMORTAL
#define ELMC_RC_IMMORTAL UINT16_MAX
#endif
#ifndef ELMC_LIST_CELL_SCALAR
#define ELMC_LIST_CELL_SCALAR ((elmc_int_t)0x1EC011)
#endif

typedef struct ElmcTuple2 {
  ElmcValue *first;
  ElmcValue *second;
} ElmcTuple2;

typedef struct ElmcCmdPayload {
  uint8_t arity;
  elmc_int_t kind;
  elmc_int_t p0;
  elmc_int_t p1;
  elmc_int_t p2;
  elmc_int_t p3;
  elmc_int_t p4;
  elmc_int_t p5;
  ElmcValue *text;
} ElmcCmdPayload;

typedef struct ElmcSubPayload {
  uint8_t arity;
  elmc_int_t mask;
  elmc_int_t p0;
  elmc_int_t p1;
  elmc_int_t p2;
  elmc_int_t p3;
  elmc_int_t p4;
  elmc_int_t p5;
} ElmcSubPayload;

typedef struct ElmcResult {
  int is_ok;
  ElmcValue *value;
} ElmcResult;

typedef struct ElmcMaybe {
  int is_just;
  ElmcValue *value;
} ElmcMaybe;

typedef struct ElmcRecord {
  int field_count;
  ElmcValue **field_values;
} ElmcRecord;

#define ELMC_RECORD_GET_INDEX(record, index) \
  (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \
    (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \
   ((ElmcRecord *)(record)->payload)->field_values[(index)] : elmc_int_zero())

#define ELMC_RECORD_GET_INDEX_INT(record, index) \
  (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \
    (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \
   elmc_as_int(((ElmcRecord *)(record)->payload)->field_values[(index)]) : 0)

#define ELMC_RECORD_GET_INDEX_FLOAT(record, index) \
  (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \
    (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \
   elmc_as_float(((ElmcRecord *)(record)->payload)->field_values[(index)]) : 0.0)

#define ELMC_RECORD_GET_INDEX_BOOL(record, index) \
  (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \
    (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \
   elmc_as_bool(((ElmcRecord *)(record)->payload)->field_values[(index)]) : 0)

typedef void (*ElmcPortCallback)(ElmcValue *value, void *context);

/* Return codes (RC) — distinct from ElmcValue.rc reference counts. */
typedef enum {
  RC_SUCCESS,
  RC_ERR_OUT_OF_MEMORY,
  RC_ERR_INVALID_ARG,
  RC_ERR_UNSUPPORTED,
  RC_ERR_MISSING_CALLBACK,
  RC_ERR_MALFORMED_TUPLE,
  RC_ERR_MALFORMED_CMD,
  RC_ERR_MALFORMED_VIEW,
  RC_ERR_MALFORMED_SUB,
  RC_ERR_SCENE_BUFFER_OVERFLOW,
  RC_ERR_SCENE_DECODE,
  RC_ERR_SCENE_DEPTH_LIMIT,
  RC_ERR_RENDER_ABORT,
  RC_ERR_PERSIST_WRITE_INT,
  RC_ERR_PERSIST_READ_INT,
  RC_ERR_PERSIST_WRITE_STRING,
  RC_ERR_PERSIST_READ_STRING,
  RC_ERR_PERSIST_DELETE,
  RC_ERR_APP_MESSAGE_OPEN,
  RC_ERR_APP_MESSAGE_OUTBOX_BEGIN,
  RC_ERR_APP_MESSAGE_OUTBOX_SEND,
  RC_ERR_APP_TIMER_REGISTER,
  RC_ERR_APP_TIMER_RESCHEDULE,
  RC_ERR_WAKEUP_SCHEDULE,
  RC_ERR_WAKEUP_CANCEL,
  RC_ERR_DATA_LOGGING_CREATE,
  RC_ERR_DATA_LOGGING_LOG,
  RC_ERR_DICTATION_SESSION_CREATE,
  RC_ERR_GDRAW_SEQUENCE_CREATE,
  RC_ERR_GDRAW_IMAGE_CREATE
} RC;


#ifndef ELMC_PEBBLE_PLATFORM
#include <stdio.h>
#endif

#ifndef ELMC_CATCH_MACROS
#define ELMC_CATCH_MACROS
#define CATCH_BEGIN     do {
#define CATCH_END       } while (0)

#ifndef ELMC_CHECK_RC_BREAK
/* break must target CATCH_BEGIN's loop — never wrap it in do/while. */
#define ELMC_CHECK_RC_BREAK(rc, file, line) \
  if (1) { \
    (void)(rc); \
    (void)(file); \
    (void)(line); \
    break; \
  }
#endif

#define CHECK_RC(rc_var) \
  if ((rc_var) != RC_SUCCESS) { \
    ELMC_CHECK_RC_BREAK((rc_var), __FILE__, __LINE__); \
  }

#define CHECK_RC_TO(rc_var, expr) \
  do { \
    (rc_var) = (expr); \
    if ((rc_var) != RC_SUCCESS) { \
      ELMC_CHECK_RC_BREAK((rc_var), __FILE__, __LINE__); \
    } \
  } while (0)
#endif

#ifdef ELMC_PEBBLE_PLATFORM
#if defined(ELMC_DEBUG_RC)
#define ELMC_RC_LOG_FAIL(rc, site, ...) \
  APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC RC %s at %s: " __VA_ARGS__, elmc_rc_name(rc), site)
#else
#define ELMC_RC_LOG_FAIL(rc, site, ...) ((void)0)
#endif
#else
#define ELMC_RC_LOG_FAIL(rc, site, ...) \
  fprintf(stderr, "ELMC RC %s at %s: " __VA_ARGS__ "\n", elmc_rc_name(rc), site)
#endif

const char *elmc_rc_name(RC rc);

static inline RC elmc_rc_assign_value(ElmcValue **out, ElmcValue *value) {
  if (!value) return RC_ERR_OUT_OF_MEMORY;
  if (out) *out = value;
  return RC_SUCCESS;
}


typedef struct ElmcClosure {
  ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count);
  RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count);
  int arity;
  int capture_count;
  int is_rc;
  ElmcValue **captures;
} ElmcClosure;

RC elmc_new_int(ElmcValue **out, elmc_int_t value);
RC elmc_new_bool(ElmcValue **out, int value);
ElmcValue *elmc_new_char(elmc_int_t value);
RC elmc_new_string(ElmcValue **out, const char *value);
ElmcValue *elmc_int_zero(void);
ElmcValue *elmc_list_nil(void);
RC elmc_list_cons(ElmcValue **out, ElmcValue *head, ElmcValue *tail);
ElmcValue *elmc_list_cons_take(ElmcValue *head, ElmcValue *tail);
RC elmc_list_from_values(ElmcValue **out, ElmcValue **items, int count);
RC elmc_list_from_values_take(ElmcValue **out, ElmcValue **items, int count);
RC elmc_list_from_int_array(ElmcValue **out, const elmc_int_t *items, int count);
RC elmc_list_from_tuple2_int_array(ElmcValue **out, const elmc_int_t items[][2], int count);
ElmcValue *elmc_list_replace_nth_int(ElmcValue *list, elmc_int_t index, elmc_int_t value);
ElmcValue *elmc_maybe_nothing(void);
RC elmc_maybe_just(ElmcValue **out, ElmcValue *value);
ElmcValue *elmc_maybe_or_tuple_just_payload(ElmcValue *maybe);
ElmcValue *elmc_maybe_or_tuple_just_payload_borrow(ElmcValue *maybe);
RC elmc_result_ok(ElmcValue **out, ElmcValue *value);
RC elmc_result_err(ElmcValue **out, ElmcValue *value);
RC elmc_tuple2(ElmcValue **out, ElmcValue *first, ElmcValue *second);
RC elmc_tuple2_take(ElmcValue **out, ElmcValue *first, ElmcValue *second);
RC elmc_tuple2_ints(ElmcValue **out, elmc_int_t first, elmc_int_t second);
ElmcValue *elmc_cmd0(elmc_int_t kind);
ElmcValue *elmc_cmd1(elmc_int_t kind, elmc_int_t p0);
ElmcValue *elmc_cmd1_string(elmc_int_t kind, elmc_int_t p0, const char *text);
ElmcValue *elmc_cmd2(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1);
ElmcValue *elmc_cmd3(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2);
ElmcValue *elmc_cmd4(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3);
ElmcValue *elmc_cmd5(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4);
ElmcValue *elmc_sub0(elmc_int_t mask);
ElmcValue *elmc_sub1(elmc_int_t mask, elmc_int_t p0);
ElmcValue *elmc_sub2(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1);
ElmcValue *elmc_sub3(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2);
ElmcValue *elmc_sub4(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3);
ElmcValue *elmc_sub5(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4);

elmc_int_t elmc_as_int(ElmcValue *value);
elmc_int_t elmc_as_bool(ElmcValue *value);
int elmc_value_equal(ElmcValue *left, ElmcValue *right);
int elmc_list_equal_int(ElmcValue *left, ElmcValue *right);
int elmc_string_length(ElmcValue *value);
ElmcValue *elmc_list_head(ElmcValue *list);
ElmcValue *elmc_list_nth_maybe(ElmcValue *list, ElmcValue *index);
elmc_int_t elmc_list_nth_int_default(ElmcValue *list, elmc_int_t index, elmc_int_t default_value);
ElmcValue *elmc_list_nth_int_default_boxed(ElmcValue *list, ElmcValue *index, ElmcValue *default_value);
elmc_int_t elmc_list_head_with_default_int(elmc_int_t default_val, ElmcValue *list);
ElmcValue *elmc_tuple_first(ElmcValue *tuple);
ElmcValue *elmc_tuple_second(ElmcValue *tuple);
ElmcValue *elmc_result_inc_or_zero(ElmcValue *result);
ElmcValue *elmc_basics_max(ElmcValue *left, ElmcValue *right);
ElmcValue *elmc_basics_min(ElmcValue *left, ElmcValue *right);
ElmcValue *elmc_basics_clamp(ElmcValue *low, ElmcValue *high, ElmcValue *value);
ElmcValue *elmc_basics_mod_by(ElmcValue *base, ElmcValue *value);
ElmcValue *elmc_bitwise_and(ElmcValue *left, ElmcValue *right);
ElmcValue *elmc_bitwise_or(ElmcValue *left, ElmcValue *right);
ElmcValue *elmc_bitwise_xor(ElmcValue *left, ElmcValue *right);
ElmcValue *elmc_bitwise_complement(ElmcValue *value);
ElmcValue *elmc_bitwise_shift_left_by(ElmcValue *bits, ElmcValue *value);
ElmcValue *elmc_bitwise_shift_right_by(ElmcValue *bits, ElmcValue *value);
ElmcValue *elmc_bitwise_shift_right_zf_by(ElmcValue *bits, ElmcValue *value);
ElmcValue *elmc_char_to_code(ElmcValue *value);
ElmcValue *elmc_debug_log(ElmcValue *label, ElmcValue *value);
ElmcValue *elmc_debug_todo(ElmcValue *label);
ElmcValue *elmc_debug_to_string(ElmcValue *value);
ElmcValue *elmc_append(ElmcValue *left, ElmcValue *right);
RC elmc_string_append(ElmcValue **out, ElmcValue *left, ElmcValue *right);
RC elmc_string_append_native(ElmcValue **out, const char *left, const char *right);
ElmcValue *elmc_string_is_empty(ElmcValue *value);
RC elmc_dict_from_list(ElmcValue **out, ElmcValue *items);
RC elmc_dict_insert(ElmcValue **out, ElmcValue *key, ElmcValue *value, ElmcValue *dict);
RC elmc_dict_get(ElmcValue **out, ElmcValue *key, ElmcValue *dict);
elmc_int_t elmc_dict_get_with_default_int(elmc_int_t default_val, elmc_int_t key, ElmcValue *dict);
elmc_int_t elmc_dict_get_with_default_int_value(elmc_int_t default_val, ElmcValue *key, ElmcValue *dict);
ElmcValue *elmc_dict_member(ElmcValue *key, ElmcValue *dict);
ElmcValue *elmc_dict_size(ElmcValue *dict);
RC elmc_set_from_list(ElmcValue **out, ElmcValue *items);
RC elmc_set_insert(ElmcValue **out, ElmcValue *value, ElmcValue *set);
ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set);
ElmcValue *elmc_set_size(ElmcValue *set);
ElmcValue *elmc_array_empty(void);
ElmcValue *elmc_array_from_list(ElmcValue *items);
ElmcValue *elmc_array_length(ElmcValue *array);
ElmcValue *elmc_array_get(ElmcValue *index, ElmcValue *array);
elmc_int_t elmc_array_get_with_default_int(elmc_int_t default_val, elmc_int_t index, ElmcValue *array);
ElmcValue *elmc_array_set(ElmcValue *index, ElmcValue *value, ElmcValue *array);
ElmcValue *elmc_array_push(ElmcValue *value, ElmcValue *array);
ElmcValue *elmc_task_succeed(ElmcValue *value);
ElmcValue *elmc_task_fail(ElmcValue *value);
ElmcValue *elmc_task_map(ElmcValue *f, ElmcValue *task);
ElmcValue *elmc_task_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_task_and_then(ElmcValue *f, ElmcValue *task);
ElmcValue *elmc_process_spawn(ElmcValue *task);
ElmcValue *elmc_process_sleep(ElmcValue *milliseconds);
ElmcValue *elmc_process_kill(ElmcValue *pid);
ElmcValue *elmc_time_now_millis(void);
ElmcValue *elmc_time_zone_offset_minutes(void);
ElmcValue *elmc_cmd_backlight_from_maybe(ElmcValue *maybe_mode);

/* --- List operations --- */
ElmcValue *elmc_list_tail(ElmcValue *list);
ElmcValue *elmc_list_is_empty(ElmcValue *list);
ElmcValue *elmc_list_length(ElmcValue *list);
RC elmc_list_reverse(ElmcValue **out, ElmcValue *list);
RC elmc_list_copy(ElmcValue **out, ElmcValue *list);
ElmcValue *elmc_list_member(ElmcValue *value, ElmcValue *list);
RC elmc_list_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_filter(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list);
RC elmc_list_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list);
RC elmc_list_append(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_list_concat(ElmcValue **out, ElmcValue *lists);
RC elmc_list_concat_array(ElmcValue **out, ElmcValue * const *lists, int count);
ElmcValue *elmc_list_concat_map(ElmcValue *f, ElmcValue *list);
RC elmc_list_indexed_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_filter_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_sum(ElmcValue **out, ElmcValue *list);
RC elmc_list_product(ElmcValue **out, ElmcValue *list);
RC elmc_list_maximum(ElmcValue **out, ElmcValue *list);
RC elmc_list_minimum(ElmcValue **out, ElmcValue *list);
RC elmc_list_any(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_all(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_sort(ElmcValue **out, ElmcValue *list);
RC elmc_list_sort_by(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_sort_with(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_singleton(ElmcValue **out, ElmcValue *value);
RC elmc_list_range(ElmcValue **out, ElmcValue *lo, ElmcValue *hi);
RC elmc_list_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *value);
RC elmc_list_take(ElmcValue **out, ElmcValue *n, ElmcValue *list);
RC elmc_list_take_int(ElmcValue **out, elmc_int_t count, ElmcValue *list);
RC elmc_list_drop(ElmcValue **out, ElmcValue *n, ElmcValue *list);
RC elmc_list_drop_int(ElmcValue **out, elmc_int_t count, ElmcValue *list);
RC elmc_list_partition(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_unzip(ElmcValue **out, ElmcValue *list);
RC elmc_list_intersperse(ElmcValue **out, ElmcValue *sep, ElmcValue *list);
RC elmc_list_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b);
RC elmc_list_map3(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c);

/* --- Maybe operations --- */
ElmcValue *elmc_maybe_with_default(ElmcValue *default_val, ElmcValue *maybe);
elmc_int_t elmc_maybe_with_default_int(elmc_int_t default_val, ElmcValue *maybe);
RC elmc_maybe_map(ElmcValue **out, ElmcValue *f, ElmcValue *maybe);
RC elmc_maybe_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b);
RC elmc_maybe_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *maybe);

/* --- Result operations --- */
RC elmc_result_map(ElmcValue **out, ElmcValue *f, ElmcValue *result);
RC elmc_result_map_error(ElmcValue **out, ElmcValue *f, ElmcValue *result);
RC elmc_result_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *result);
ElmcValue *elmc_result_with_default(ElmcValue *default_val, ElmcValue *result);
ElmcValue *elmc_result_to_maybe(ElmcValue *result);
ElmcValue *elmc_result_from_maybe(ElmcValue *err, ElmcValue *maybe);

/* --- String operations (extended) --- */
ElmcValue *elmc_string_length_val(ElmcValue *s);
RC elmc_string_reverse(ElmcValue **out, ElmcValue *s);
RC elmc_string_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *s);
RC elmc_string_replace(ElmcValue **out, ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s);
ElmcValue *elmc_string_from_int(ElmcValue *n);
RC elmc_string_from_native_int(ElmcValue **out, elmc_int_t n);
ElmcValue *elmc_string_to_int(ElmcValue *s);
RC elmc_string_from_float(ElmcValue **out, ElmcValue *f);
ElmcValue *elmc_string_to_float(ElmcValue *s);
RC elmc_string_to_upper(ElmcValue **out, ElmcValue *s);
RC elmc_string_to_lower(ElmcValue **out, ElmcValue *s);
RC elmc_string_trim(ElmcValue **out, ElmcValue *s);
RC elmc_string_trim_left(ElmcValue **out, ElmcValue *s);
RC elmc_string_trim_right(ElmcValue **out, ElmcValue *s);
ElmcValue *elmc_string_contains(ElmcValue *sub, ElmcValue *s);
ElmcValue *elmc_string_starts_with(ElmcValue *prefix, ElmcValue *s);
ElmcValue *elmc_string_ends_with(ElmcValue *suffix, ElmcValue *s);
RC elmc_string_split(ElmcValue **out, ElmcValue *sep, ElmcValue *s);
RC elmc_string_join(ElmcValue **out, ElmcValue *sep, ElmcValue *list);
ElmcValue *elmc_string_words(ElmcValue *s);
ElmcValue *elmc_string_lines(ElmcValue *s);
RC elmc_string_slice(ElmcValue **out, ElmcValue *start, ElmcValue *end_idx, ElmcValue *s);
ElmcValue *elmc_string_left(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_right(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_drop_left(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_drop_right(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_cons(ElmcValue *ch, ElmcValue *s);
RC elmc_string_uncons(ElmcValue **out, ElmcValue *s);
RC elmc_string_to_list(ElmcValue **out, ElmcValue *s);
RC elmc_string_from_list(ElmcValue **out, ElmcValue *list);
RC elmc_string_from_char(ElmcValue **out, ElmcValue *ch);
ElmcValue *elmc_string_pad(ElmcValue *n, ElmcValue *ch, ElmcValue *s);
RC elmc_string_pad_left(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s);
RC elmc_string_pad_right(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s);
RC elmc_string_map(ElmcValue **out, ElmcValue *f, ElmcValue *s);
RC elmc_string_filter(ElmcValue **out, ElmcValue *f, ElmcValue *s);
RC elmc_string_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s);
RC elmc_string_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *s);
RC elmc_string_any(ElmcValue **out, ElmcValue *f, ElmcValue *s);
RC elmc_string_all(ElmcValue **out, ElmcValue *f, ElmcValue *s);
RC elmc_string_indexes(ElmcValue **out, ElmcValue *sub, ElmcValue *s);

/* --- Tuple operations (extended) --- */
RC elmc_tuple_map_first(ElmcValue **out, ElmcValue *f, ElmcValue *t);
RC elmc_tuple_map_second(ElmcValue **out, ElmcValue *f, ElmcValue *t);
RC elmc_tuple_map_both(ElmcValue **out, ElmcValue *f, ElmcValue *g, ElmcValue *t);

/* --- Basics (extended) --- */
ElmcValue *elmc_basics_not(ElmcValue *x);
ElmcValue *elmc_basics_negate(ElmcValue *x);
ElmcValue *elmc_basics_abs(ElmcValue *x);
ElmcValue *elmc_basics_to_float(ElmcValue *x);
ElmcValue *elmc_basics_sqrt(ElmcValue *x);
ElmcValue *elmc_basics_log_base(ElmcValue *base, ElmcValue *x);
ElmcValue *elmc_basics_sin(ElmcValue *x);
ElmcValue *elmc_basics_cos(ElmcValue *x);
ElmcValue *elmc_basics_tan(ElmcValue *x);
ElmcValue *elmc_basics_acos(ElmcValue *x);
ElmcValue *elmc_basics_asin(ElmcValue *x);
ElmcValue *elmc_basics_atan(ElmcValue *x);
ElmcValue *elmc_basics_atan2(ElmcValue *y, ElmcValue *x);
ElmcValue *elmc_basics_degrees(ElmcValue *x);
ElmcValue *elmc_basics_radians(ElmcValue *x);
ElmcValue *elmc_basics_turns(ElmcValue *x);
ElmcValue *elmc_basics_from_polar(ElmcValue *polar);
ElmcValue *elmc_basics_to_polar(ElmcValue *point);
ElmcValue *elmc_basics_is_nan(ElmcValue *x);
ElmcValue *elmc_basics_is_infinite(ElmcValue *x);
ElmcValue *elmc_basics_round(ElmcValue *x);
ElmcValue *elmc_basics_floor(ElmcValue *x);
ElmcValue *elmc_basics_ceiling(ElmcValue *x);
ElmcValue *elmc_basics_truncate(ElmcValue *x);
ElmcValue *elmc_basics_remainder_by(ElmcValue *base, ElmcValue *value);
ElmcValue *elmc_basics_pow(ElmcValue *base, ElmcValue *exponent);
ElmcValue *elmc_basics_xor(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_basics_compare(ElmcValue *a, ElmcValue *b);

/* --- Char (extended) --- */
ElmcValue *elmc_char_is_upper(ElmcValue *ch);
ElmcValue *elmc_char_is_lower(ElmcValue *ch);
ElmcValue *elmc_char_is_alpha(ElmcValue *ch);
ElmcValue *elmc_char_is_alpha_num(ElmcValue *ch);
ElmcValue *elmc_char_is_digit(ElmcValue *ch);
ElmcValue *elmc_char_is_oct_digit(ElmcValue *ch);
ElmcValue *elmc_char_is_hex_digit(ElmcValue *ch);
ElmcValue *elmc_char_to_upper(ElmcValue *ch);
ElmcValue *elmc_char_to_lower(ElmcValue *ch);

/* --- Dict (extended) --- */
RC elmc_dict_remove(ElmcValue **out, ElmcValue *key, ElmcValue *dict);
ElmcValue *elmc_dict_is_empty(ElmcValue *dict);
RC elmc_dict_keys(ElmcValue **out, ElmcValue *dict);
RC elmc_dict_values(ElmcValue **out, ElmcValue *dict);
ElmcValue *elmc_dict_to_list(ElmcValue *dict);
RC elmc_dict_map(ElmcValue **out, ElmcValue *f, ElmcValue *dict);
RC elmc_dict_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *dict);
RC elmc_dict_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *dict);
RC elmc_dict_filter(ElmcValue **out, ElmcValue *f, ElmcValue *dict);
RC elmc_dict_partition(ElmcValue **out, ElmcValue *f, ElmcValue *dict);
RC elmc_dict_union(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_dict_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_dict_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_dict_merge(ElmcValue **out, ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b, ElmcValue *result);
RC elmc_dict_update(ElmcValue **out, ElmcValue *key, ElmcValue *f, ElmcValue *dict);
ElmcValue *elmc_dict_singleton(ElmcValue *key, ElmcValue *value);

/* --- Set (extended) --- */
ElmcValue *elmc_set_singleton(ElmcValue *value);
RC elmc_set_remove(ElmcValue **out, ElmcValue *value, ElmcValue *set);
ElmcValue *elmc_set_is_empty(ElmcValue *set);
ElmcValue *elmc_set_to_list(ElmcValue *set);
RC elmc_set_union(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_set_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_set_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_set_map(ElmcValue **out, ElmcValue *f, ElmcValue *set);
RC elmc_set_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set);
RC elmc_set_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set);
RC elmc_set_filter(ElmcValue **out, ElmcValue *f, ElmcValue *set);
RC elmc_set_partition(ElmcValue **out, ElmcValue *f, ElmcValue *set);

/* --- Array (extended) --- */
ElmcValue *elmc_array_initialize(ElmcValue *n, ElmcValue *f);
ElmcValue *elmc_array_repeat(ElmcValue *n, ElmcValue *value);
ElmcValue *elmc_array_is_empty(ElmcValue *array);
ElmcValue *elmc_array_to_list(ElmcValue *array);
ElmcValue *elmc_array_to_indexed_list(ElmcValue *array);
ElmcValue *elmc_array_map(ElmcValue *f, ElmcValue *array);
ElmcValue *elmc_array_indexed_map(ElmcValue *f, ElmcValue *array);
ElmcValue *elmc_array_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *array);
ElmcValue *elmc_array_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *array);
ElmcValue *elmc_array_filter(ElmcValue *f, ElmcValue *array);
ElmcValue *elmc_array_append(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_array_slice(ElmcValue *start, ElmcValue *end_idx, ElmcValue *array);

/* --- Json.Decode --- */
ElmcValue *elmc_json_decode_value(ElmcValue *decoder, ElmcValue *value);
ElmcValue *elmc_json_decode_string(ElmcValue *decoder, ElmcValue *s);
ElmcValue *elmc_json_decode_string_decoder(void);
ElmcValue *elmc_json_decode_int_decoder(void);
ElmcValue *elmc_json_decode_float_decoder(void);
ElmcValue *elmc_json_decode_bool_decoder(void);
ElmcValue *elmc_json_decode_null(ElmcValue *default_val);
ElmcValue *elmc_json_decode_nullable(ElmcValue *decoder);
ElmcValue *elmc_json_decode_list(ElmcValue *decoder);
ElmcValue *elmc_json_decode_array(ElmcValue *decoder);
ElmcValue *elmc_json_decode_field(ElmcValue *name, ElmcValue *decoder);
ElmcValue *elmc_json_decode_at(ElmcValue *path, ElmcValue *decoder);
ElmcValue *elmc_json_decode_index(ElmcValue *idx, ElmcValue *decoder);
ElmcValue *elmc_json_decode_map(ElmcValue *f, ElmcValue *decoder);
ElmcValue *elmc_json_decode_map2(ElmcValue *f, ElmcValue *d1, ElmcValue *d2);
ElmcValue *elmc_json_decode_map3(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3);
ElmcValue *elmc_json_decode_map4(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4);
ElmcValue *elmc_json_decode_map5(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5);
ElmcValue *elmc_json_decode_map6(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6);
ElmcValue *elmc_json_decode_map7(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6, ElmcValue *d7);
ElmcValue *elmc_json_decode_succeed(ElmcValue *value);
ElmcValue *elmc_json_decode_fail(ElmcValue *msg);
ElmcValue *elmc_json_decode_and_then(ElmcValue *f, ElmcValue *decoder);
ElmcValue *elmc_json_decode_one_of(ElmcValue *decoders);
ElmcValue *elmc_json_decode_maybe(ElmcValue *decoder);
ElmcValue *elmc_json_decode_lazy(ElmcValue *thunk);
ElmcValue *elmc_json_decode_value_decoder(void);
ElmcValue *elmc_json_decode_error_to_string(ElmcValue *err);
ElmcValue *elmc_json_decode_key_value_pairs(ElmcValue *decoder);
ElmcValue *elmc_json_decode_dict(ElmcValue *decoder);

/* --- Json.Encode --- */
ElmcValue *elmc_json_encode_string(ElmcValue *s);
ElmcValue *elmc_json_encode_int(ElmcValue *n);
ElmcValue *elmc_json_encode_float(ElmcValue *f);
ElmcValue *elmc_json_encode_bool(ElmcValue *b);
ElmcValue *elmc_json_encode_null(void);
ElmcValue *elmc_json_encode_list(ElmcValue *f, ElmcValue *items);
ElmcValue *elmc_json_encode_array(ElmcValue *f, ElmcValue *items);
ElmcValue *elmc_json_encode_set(ElmcValue *f, ElmcValue *items);
ElmcValue *elmc_json_encode_object(ElmcValue *pairs);
ElmcValue *elmc_json_encode_dict(ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict);
ElmcValue *elmc_json_encode_encode(ElmcValue *indent, ElmcValue *value);


RC elmc_new_float(ElmcValue **out, double value);
double elmc_as_float(ElmcValue *value);
double elmc_basics_sqrt_double(double x);
double elmc_basics_sin_double(double x);
double elmc_basics_cos_double(double x);
double elmc_basics_tan_double(double x);

RC elmc_record_new(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values);
RC elmc_record_new_take(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values);
RC elmc_record_new_ints(ElmcValue **out, int field_count, const char **field_names, const elmc_int_t *field_values);
RC elmc_record_new_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values);
RC elmc_record_new_static_take(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values);
RC elmc_record_new_static_ints(ElmcValue **out, int field_count, const char * const *field_names, const elmc_int_t *field_values);
RC elmc_record_new_values(ElmcValue **out, int field_count, ElmcValue **field_values);
RC elmc_record_new_values_take(ElmcValue **out, int field_count, ElmcValue **field_values);
RC elmc_record_new_values_ints(ElmcValue **out, int field_count, const elmc_int_t *field_values);

static inline ElmcValue *elmc_new_int_take(elmc_int_t value) {
  ElmcValue *out = NULL;
  return elmc_new_int(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_new_bool_take(int value) {
  ElmcValue *out = NULL;
  return elmc_new_bool(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_new_string_take(const char *value) {
  ElmcValue *out = NULL;
  return elmc_new_string(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_new_float_take(double value) {
  ElmcValue *out = NULL;
  return elmc_new_float(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_from_int_array_take(const elmc_int_t *items, int count) {
  ElmcValue *out = NULL;
  return elmc_list_from_int_array(&out, items, count) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_from_values_take_value(ElmcValue **items, int count) {
  ElmcValue *out = NULL;
  return elmc_list_from_values_take(&out, items, count) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_from_tuple2_int_array_take(const elmc_int_t items[][2], int count) {
  ElmcValue *out = NULL;
  return elmc_list_from_tuple2_int_array(&out, items, count) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_tuple2_take_value(ElmcValue *first, ElmcValue *second) {
  ElmcValue *out = NULL;
  return elmc_tuple2_take(&out, first, second) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_record_new_take_value(
    int field_count, const char **field_names, ElmcValue **field_values) {
  ElmcValue *out = NULL;
  return elmc_record_new_take(&out, field_count, field_names, field_values) == RC_SUCCESS
      ? out
      : elmc_int_zero();
}

static inline ElmcValue *elmc_record_new_static_take_value(
    int field_count, const char * const *field_names, ElmcValue **field_values) {
  ElmcValue *out = NULL;
  return elmc_record_new_static_take(&out, field_count, field_names, field_values) ==
             RC_SUCCESS
      ? out
      : elmc_int_zero();
}

static inline ElmcValue *elmc_record_new_values_take_value(
    int field_count, ElmcValue **field_values) {
  ElmcValue *out = NULL;
  return elmc_record_new_values_take(&out, field_count, field_values) == RC_SUCCESS
      ? out
      : elmc_int_zero();
}

static inline ElmcValue *elmc_record_new_values_ints_take(
    int field_count, const elmc_int_t *field_values) {
  ElmcValue *out = NULL;
  return elmc_record_new_values_ints(&out, field_count, field_values) == RC_SUCCESS
      ? out
      : elmc_int_zero();
}

static inline ElmcValue *elmc_maybe_just_take(ElmcValue *value) {
  ElmcValue *out = NULL;
  return elmc_maybe_just(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_result_ok_take(ElmcValue *value) {
  ElmcValue *out = NULL;
  return elmc_result_ok(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_result_err_take(ElmcValue *value) {
  ElmcValue *out = NULL;
  return elmc_result_err(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_reverse_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_reverse(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_copy_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_copy(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_map_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_map(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_filter_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_filter(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_foldl(&out, f, acc, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_append_take(ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_list_append(&out, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_concat_array_take(ElmcValue * const *lists, int count) {
  ElmcValue *out = NULL;
  return elmc_list_concat_array(&out, lists, count) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_foldr(&out, f, acc, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_concat_take(ElmcValue *lists) {
  ElmcValue *out = NULL;
  return elmc_list_concat(&out, lists) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_indexed_map_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_indexed_map(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_filter_map_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_filter_map(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_singleton_take(ElmcValue *value) {
  ElmcValue *out = NULL;
  return elmc_list_singleton(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_range_take(ElmcValue *lo, ElmcValue *hi) {
  ElmcValue *out = NULL;
  return elmc_list_range(&out, lo, hi) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_repeat_take(ElmcValue *n, ElmcValue *value) {
  ElmcValue *out = NULL;
  return elmc_list_repeat(&out, n, value) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_take_take(ElmcValue *n, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_take(&out, n, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_take_int_take(elmc_int_t count, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_take_int(&out, count, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_drop_take(ElmcValue *n, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_drop(&out, n, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_drop_int_take(elmc_int_t count, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_drop_int(&out, count, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_partition_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_partition(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_unzip_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_unzip(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_intersperse_take(ElmcValue *sep, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_intersperse(&out, sep, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_map2_take(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_list_map2(&out, f, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_map3_take(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c) {
  ElmcValue *out = NULL;
  return elmc_list_map3(&out, f, a, b, c) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_sum_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_sum(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_product_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_product(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_maximum_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_maximum(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_minimum_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_minimum(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_any_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_any(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_all_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_all(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_sort_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_sort(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_sort_by_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_sort_by(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_list_sort_with_take(ElmcValue *f, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_list_sort_with(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_append_take(ElmcValue *left, ElmcValue *right) {
  ElmcValue *out = NULL;
  return elmc_string_append(&out, left, right) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_append_native_take(const char *left, const char *right) {
  ElmcValue *out = NULL;
  return elmc_string_append_native(&out, left, right) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_replace_take(ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_replace(&out, old_s, new_s, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_reverse_take(ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_reverse(&out, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_repeat_take(ElmcValue *n, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_repeat(&out, n, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_from_float_take(ElmcValue *f) {
  ElmcValue *out = NULL;
  return elmc_string_from_float(&out, f) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_to_upper_take(ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_to_upper(&out, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_to_lower_take(ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_to_lower(&out, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_trim_take(ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_trim(&out, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_trim_left_take(ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_trim_left(&out, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_trim_right_take(ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_trim_right(&out, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_split_take(ElmcValue *sep, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_split(&out, sep, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_join_take(ElmcValue *sep, ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_string_join(&out, sep, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_slice_take(ElmcValue *start, ElmcValue *end_idx, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_slice(&out, start, end_idx, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_from_list_take(ElmcValue *list) {
  ElmcValue *out = NULL;
  return elmc_string_from_list(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_from_char_take(ElmcValue *ch) {
  ElmcValue *out = NULL;
  return elmc_string_from_char(&out, ch) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_pad_left_take(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_pad_left(&out, n, ch, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_pad_right_take(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_pad_right(&out, n, ch, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_map_take(ElmcValue *f, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_map(&out, f, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_filter_take(ElmcValue *f, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_filter(&out, f, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_foldl(&out, f, acc, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_foldr(&out, f, acc, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_any_take(ElmcValue *f, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_any(&out, f, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_all_take(ElmcValue *f, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_all(&out, f, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_indexes_take(ElmcValue *sub, ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_indexes(&out, sub, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_uncons_take(ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_uncons(&out, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_to_list_take(ElmcValue *s) {
  ElmcValue *out = NULL;
  return elmc_string_to_list(&out, s) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_from_list_take(ElmcValue *items) {
  ElmcValue *out = NULL;
  return elmc_dict_from_list(&out, items) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_insert_take(ElmcValue *key, ElmcValue *value, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_insert(&out, key, value, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_get_take(ElmcValue *key, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_get(&out, key, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_remove_take(ElmcValue *key, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_remove(&out, key, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_keys_take(ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_keys(&out, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_values_take(ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_values(&out, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_map_take(ElmcValue *f, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_map(&out, f, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_foldl(&out, f, acc, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_foldr(&out, f, acc, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_filter_take(ElmcValue *f, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_filter(&out, f, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_partition_take(ElmcValue *f, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_partition(&out, f, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_intersect_take(ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_dict_intersect(&out, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_diff_take(ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_dict_diff(&out, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_union_take(ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_dict_union(&out, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_merge_take(ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b, ElmcValue *result) {
  ElmcValue *out = NULL;
  return elmc_dict_merge(&out, lf, bf, rf, a, b, result) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_dict_update_take(ElmcValue *key, ElmcValue *f, ElmcValue *dict) {
  ElmcValue *out = NULL;
  return elmc_dict_update(&out, key, f, dict) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_from_list_take(ElmcValue *items) {
  ElmcValue *out = NULL;
  return elmc_set_from_list(&out, items) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_insert_take(ElmcValue *value, ElmcValue *set) {
  ElmcValue *out = NULL;
  return elmc_set_insert(&out, value, set) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_remove_take(ElmcValue *value, ElmcValue *set) {
  ElmcValue *out = NULL;
  return elmc_set_remove(&out, value, set) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
  ElmcValue *out = NULL;
  return elmc_set_foldl(&out, f, acc, set) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
  ElmcValue *out = NULL;
  return elmc_set_foldr(&out, f, acc, set) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_filter_take(ElmcValue *f, ElmcValue *set) {
  ElmcValue *out = NULL;
  return elmc_set_filter(&out, f, set) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_partition_take(ElmcValue *f, ElmcValue *set) {
  ElmcValue *out = NULL;
  return elmc_set_partition(&out, f, set) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_union_take(ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_set_union(&out, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_intersect_take(ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_set_intersect(&out, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_diff_take(ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_set_diff(&out, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_set_map_take(ElmcValue *f, ElmcValue *set) {
  ElmcValue *out = NULL;
  return elmc_set_map(&out, f, set) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_string_from_native_int_take(elmc_int_t n) {
  ElmcValue *out = NULL;
  return elmc_string_from_native_int(&out, n) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_maybe_map_take(ElmcValue *f, ElmcValue *maybe) {
  ElmcValue *out = NULL;
  return elmc_maybe_map(&out, f, maybe) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_maybe_map2_take(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
  ElmcValue *out = NULL;
  return elmc_maybe_map2(&out, f, a, b) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_maybe_and_then_take(ElmcValue *f, ElmcValue *maybe) {
  ElmcValue *out = NULL;
  return elmc_maybe_and_then(&out, f, maybe) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_result_map_take(ElmcValue *f, ElmcValue *result) {
  ElmcValue *out = NULL;
  return elmc_result_map(&out, f, result) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_result_map_error_take(ElmcValue *f, ElmcValue *result) {
  ElmcValue *out = NULL;
  return elmc_result_map_error(&out, f, result) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_result_and_then_take(ElmcValue *f, ElmcValue *result) {
  ElmcValue *out = NULL;
  return elmc_result_and_then(&out, f, result) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_tuple_map_first_take(ElmcValue *f, ElmcValue *t) {
  ElmcValue *out = NULL;
  return elmc_tuple_map_first(&out, f, t) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_tuple_map_second_take(ElmcValue *f, ElmcValue *t) {
  ElmcValue *out = NULL;
  return elmc_tuple_map_second(&out, f, t) == RC_SUCCESS ? out : elmc_int_zero();
}

static inline ElmcValue *elmc_tuple_map_both_take(ElmcValue *f, ElmcValue *g, ElmcValue *t) {
  ElmcValue *out = NULL;
  return elmc_tuple_map_both(&out, f, g, t) == RC_SUCCESS ? out : elmc_int_zero();
}


ElmcValue *elmc_record_get(ElmcValue *record, const char *field_name);
ElmcValue *elmc_record_get_at(ElmcValue *record, int index, const char *field_name);
ElmcValue *elmc_record_get_index(ElmcValue *record, int index);
elmc_int_t elmc_record_get_int(ElmcValue *record, const char *field_name);
elmc_int_t elmc_record_get_at_int(ElmcValue *record, int index, const char *field_name);
elmc_int_t elmc_record_get_index_int(ElmcValue *record, int index);
elmc_int_t elmc_record_get_maybe_int(ElmcValue *record, const char *field_name, elmc_int_t default_val);
elmc_int_t elmc_record_get_at_maybe_int(ElmcValue *record, int index, const char *field_name, elmc_int_t default_val);
elmc_int_t elmc_record_get_index_maybe_int(ElmcValue *record, int index, elmc_int_t default_val);
elmc_int_t elmc_record_get_bool(ElmcValue *record, const char *field_name);
elmc_int_t elmc_record_get_at_bool(ElmcValue *record, int index, const char *field_name);
elmc_int_t elmc_record_get_index_bool(ElmcValue *record, int index);
ElmcValue *elmc_record_update(ElmcValue *record, const char *field_name, ElmcValue *new_value);
ElmcValue *elmc_record_update_index(ElmcValue *record, int index, ElmcValue *new_value);
ElmcValue *elmc_record_update_index_cow(ElmcValue *record, int index, ElmcValue *new_value);

RC elmc_closure_new(ElmcValue **out, ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures);
RC elmc_closure_new_rc(ElmcValue **out, RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures);
static inline ElmcValue *elmc_closure_new_take(
    ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count),
    int arity,
    int capture_count,
    ElmcValue **captures) {
  ElmcValue *out = NULL;
  return elmc_closure_new(&out, fn, arity, capture_count, captures) == RC_SUCCESS
      ? out
      : elmc_int_zero();
}

static inline ElmcValue *elmc_closure_new_rc_take(
    RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count),
    int arity,
    int capture_count,
    ElmcValue **captures) {
  ElmcValue *out = NULL;
  return elmc_closure_new_rc(&out, rc_fn, arity, capture_count, captures) == RC_SUCCESS
      ? out
      : elmc_int_zero();
}

ElmcValue *elmc_closure_call(ElmcValue *closure, ElmcValue **args, int argc);
RC elmc_closure_call_rc(ElmcValue **out, ElmcValue *closure, ElmcValue **args, int argc);
ElmcValue *elmc_apply_extra(ElmcValue *value, ElmcValue **args, int argc);

typedef struct ElmcForwardRef {
  ElmcValue *value;
} ElmcForwardRef;

ElmcForwardRef *elmc_forward_ref_new(void);
void elmc_forward_ref_set(ElmcForwardRef *ref, ElmcValue *value);
ElmcValue *elmc_forward_ref_get(ElmcForwardRef *ref);
void elmc_forward_ref_free(ElmcForwardRef *ref);
ElmcValue *elmc_forward_ref_capture(ElmcForwardRef *ref);

uint64_t elmc_rc_allocated_count(void);
uint64_t elmc_rc_released_count(void);

#ifndef ELMC_RC_TRACK
#define ELMC_RC_TRACK 0
#endif

#if ELMC_RC_TRACK
#include <stdio.h>
void elmc_rc_track_reset(void);
uint32_t elmc_rc_track_live_count(void);
int elmc_rc_track_check_balanced(void);
void elmc_rc_track_dump_live(FILE *out);
ElmcValue *elmc_rc_track_retain(ElmcValue *value, const char *file, int line);
void elmc_rc_track_release(ElmcValue *value, const char *file, int line);
#define elmc_retain(value) elmc_rc_track_retain((value), __FILE__, __LINE__)
#define elmc_release(value) elmc_rc_track_release((value), __FILE__, __LINE__)
#else
ElmcValue *elmc_retain(ElmcValue *value);
void elmc_release(ElmcValue *value);
#endif
void elmc_release_deep(ElmcValue *value);


#endif
