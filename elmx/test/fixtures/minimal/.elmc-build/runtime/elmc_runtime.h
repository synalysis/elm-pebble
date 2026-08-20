#ifndef ELMC_RUNTIME_H
#define ELMC_RUNTIME_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdlib.h>
#define ELMC_PEBBLE_INT32 1


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
  ELMC_TAG_CHAR = 8,
  ELMC_TAG_PORT_PAYLOAD = 9,
  ELMC_TAG_FLOAT = 10,
  ELMC_TAG_RECORD = 11,
  ELMC_TAG_CLOSURE = 12,
  ELMC_TAG_FORWARD_REF = 13,
  ELMC_TAG_CMD = 14,
  ELMC_TAG_SUB = 15,
  ELMC_TAG_ORDER = 16,
  ELMC_TAG_INT_LIST = 17,
  ELMC_TAG_INT_SPINE = 18,
  ELMC_TAG_RECORD_SEQ = 19,
  ELMC_TAG_FLOAT_LIST = 20,
  ELMC_TAG_LAZY_MAP = 21
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

#ifndef ELMC_INT_LIST_CELL_SCALAR
#define ELMC_INT_LIST_CELL_SCALAR ((elmc_int_t)0x1EC013)
#endif

#ifndef ELMC_INT_SPINE_CELL_SCALAR
#define ELMC_INT_SPINE_CELL_SCALAR ((elmc_int_t)0x1EC01A)
#endif

#ifndef ELMC_RECORD_SEQ_CELL_SCALAR
#define ELMC_RECORD_SEQ_CELL_SCALAR ((elmc_int_t)0x1EC01B)
#endif

/* Compact `List.range` for modest spans. Huge ranges fall back to cons
   so a `List.range 0 100000` cannot claim a multi-megabyte INT_LIST.
   Keep this in the header: implementation-file `#define`s between
   extracted functions are dropped by runtime generation. */
#ifndef ELMC_INT_LIST_RANGE_MAX
#define ELMC_INT_LIST_RANGE_MAX 512
#endif

typedef struct ElmcIntListPayload {
  elmc_int_t *values;
  int length;
  unsigned char owns_buffer;
} ElmcIntListPayload;

typedef struct ElmcIntListCell {
  ElmcValue value;
  ElmcIntListPayload data;
} ElmcIntListCell;

typedef struct ElmcIntSpine {
  elmc_int_t head;
  struct ElmcValue *tail;
} ElmcIntSpine;

typedef struct ElmcIntSpineCell {
  ElmcValue value;
  ElmcIntSpine spine;
} ElmcIntSpineCell;

typedef struct ElmcRecordSeqPayload {
  struct ElmcValue **items;
  int length;
  unsigned char owns_buffer;
} ElmcRecordSeqPayload;

typedef struct ElmcRecordSeqCell {
  ElmcValue value;
  ElmcRecordSeqPayload data;
} ElmcRecordSeqCell;


#ifndef ELMC_LAZY_MAP_CELL_SCALAR
#define ELMC_LAZY_MAP_CELL_SCALAR ((elmc_int_t)0x1EC01C)
#endif

typedef struct ElmcLazyMapPayload {
  ElmcValue *source;
  void *mapper;
  ElmcValue **captures;
  int capture_count;
} ElmcLazyMapPayload;

typedef struct ElmcLazyMapCell {
  ElmcValue value;
  ElmcLazyMapPayload data;
} ElmcLazyMapCell;


#ifndef ELMC_RC_IMMORTAL
#define ELMC_RC_IMMORTAL UINT16_MAX
#endif
#ifndef ELMC_LIST_CELL_SCALAR
#define ELMC_LIST_CELL_SCALAR ((elmc_int_t)0x1EC011)
#endif
#ifndef ELMC_DICT_SCALAR
#define ELMC_DICT_SCALAR ((elmc_int_t)0x1EC012)
#endif

#define ELMC_SMALL_INT_MIN (-1)
#define ELMC_SMALL_INT_MAX 3
extern const ElmcValue ELMC_SMALL_INTS[ELMC_SMALL_INT_MAX - ELMC_SMALL_INT_MIN + 1];
extern ElmcValue ELMC_LIST_NIL;
#define ELMC_STATIC_INT(n) ((ElmcValue *)&ELMC_SMALL_INTS[(n) - ELMC_SMALL_INT_MIN])
#define ELMC_STATIC_LIST_NIL (&ELMC_LIST_NIL)

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
  uint32_t mutation_gen;
  ElmcValue **field_values;
} ElmcRecord;

#define ELMC_RECORD_GET_INDEX(record, index) \
  (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \
    (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \
   ((ElmcRecord *)(record)->payload)->field_values[(index)] : elmc_int_zero())

#define ELMC_RECORD_GET_INDEX_INT(record, index) \
  (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \
    (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \
   elmc_as_int_number(((ElmcRecord *)(record)->payload)->field_values[(index)]) : 0)

#define ELMC_RECORD_GET_INDEX_BOOL(record, index) \
  (((record) && (record)->tag == ELMC_TAG_RECORD && (record)->payload && \
    (index) >= 0 && (index) < ((ElmcRecord *)(record)->payload)->field_count) ? \
   (elmc_as_int(((ElmcRecord *)(record)->payload)->field_values[(index)]) != 0) : 0)

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
#define CATCH_END       } while (0);

#ifndef DIM
#define DIM(arr) (sizeof(arr) / sizeof((arr)[0]))
#endif

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
    elmc_rc_record_fail((rc_var), __LINE__); \
    ELMC_CHECK_RC_BREAK((rc_var), __FILE__, __LINE__); \
  }

#define CHECK_RC_TO(rc_var, expr) \
  do { \
    (rc_var) = (expr); \
    if ((rc_var) != RC_SUCCESS) { \
      elmc_rc_record_fail((rc_var), __LINE__); \
      ELMC_CHECK_RC_BREAK((rc_var), __FILE__, __LINE__); \
    } \
  } while (0)

#ifndef ELMC_RELEASE
#define ELMC_RELEASE(var) \
  do { \
    elmc_release(var); \
    (var) = NULL; \
  } while (0)
#endif
#endif

extern volatile RC elmc_last_fail_rc;
extern volatile uint16_t elmc_last_fail_line;

static inline void elmc_rc_record_fail(RC rc, int line) {
  if (rc != RC_SUCCESS) {
    elmc_last_fail_rc = rc;
    elmc_last_fail_line = (uint16_t)line;
  }
}

static inline RC elmc_rc_fail_code(void) {
  return elmc_last_fail_rc;
}

#ifdef ELMC_PEBBLE_PLATFORM
#if defined(ELMC_DEBUG_RC)
#define ELMC_RC_LOG_FAIL(rc, site, ...) \
  do { \
    elmc_rc_record_fail((rc), __LINE__); \
    APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC RC %u at %s", (unsigned)(rc), site); \
  } while (0)
#else
#define ELMC_RC_LOG_FAIL(rc, site, ...) \
  do { \
    elmc_rc_record_fail((rc), __LINE__); \
    (void)(site); \
  } while (0)
#endif
#else
#define ELMC_RC_LOG_FAIL(rc, site, ...) \
  do { \
    elmc_rc_record_fail((rc), __LINE__); \
    fprintf(stderr, "ELMC RC %s at %s: " __VA_ARGS__ "\n", elmc_rc_name(rc), site); \
  } while (0)
#endif

#ifdef ELMC_PEBBLE_PLATFORM
static inline const char *elmc_rc_name(RC rc) {
  (void)rc;
  return "RC";
}
#else
const char *elmc_rc_name(RC rc);
#endif

/* Deprecated: use `Rc = expr; CHECK_RC(Rc);` inside CATCH_BEGIN bodies instead. */
#define ELMC_TAKE_OR_RETURN(site, take_expr, on_fail) \
  do { \
    RC __take_rc = (take_expr); \
    if (__take_rc != RC_SUCCESS) { \
      (void)(site); \
      on_fail; \
    } \
  } while (0)


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
RC elmc_new_char(ElmcValue **out, elmc_int_t value);
RC elmc_char_from_code(ElmcValue **out, ElmcValue *code);
RC elmc_char_from_code_int(ElmcValue **out, elmc_int_t code);
RC elmc_new_order(ElmcValue **out, elmc_int_t value);
RC elmc_new_string(ElmcValue **out, const char *value);
RC elmc_new_string_len(ElmcValue **out, const char *value, size_t len);
ElmcValue *elmc_int_zero(void);
ElmcValue *elmc_unit(void);
ElmcValue *elmc_list_nil(void);
RC elmc_list_cons(ElmcValue **out, ElmcValue *head, ElmcValue *tail);
RC elmc_list_from_values(ElmcValue **out, ElmcValue **items, int count);
RC elmc_list_from_values_take(ElmcValue **out, ElmcValue **items, int count);
int elmc_int_list_is_empty(ElmcValue *list);
RC elmc_int_list_head_boxed(ElmcValue **out, ElmcValue *list);
RC elmc_int_list_tail(ElmcValue **out, ElmcValue *list);
int elmc_record_seq_is_empty(ElmcValue *list);
int elmc_record_seq_length(ElmcValue *list);
ElmcValue *elmc_record_seq_get(ElmcValue *list, elmc_int_t index);
RC elmc_record_seq_head_boxed(ElmcValue **out, ElmcValue *list);
RC elmc_record_seq_tail(ElmcValue **out, ElmcValue *list);
int elmc_int_spine_is_empty(ElmcValue *list);
RC elmc_int_spine_head_boxed(ElmcValue **out, ElmcValue *list);
RC elmc_int_spine_tail(ElmcValue **out, ElmcValue *list);
RC elmc_list_from_int_array(ElmcValue **out, const elmc_int_t *items, int count);
RC elmc_list_from_int_array_reuse(ElmcValue **out, ElmcValue *existing, const elmc_int_t *items, int count);
RC elmc_int_list_to_cons(ElmcValue **out, ElmcValue *list);
RC elmc_int_list_to_spine(ElmcValue **out, ElmcValue *list);
RC elmc_list_from_record_array(ElmcValue **out, ElmcValue **items, int count);
RC elmc_record_seq_to_cons(ElmcValue **out, ElmcValue *list);
RC elmc_list_materialize_cons(ElmcValue **out, ElmcValue *list);
typedef RC (*ElmcLazyMapFn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count);
RC elmc_lazy_map(ElmcValue **out, ElmcValue *source, ElmcLazyMapFn mapper, ElmcValue **captures, int capture_count);
int elmc_lazy_map_length(ElmcValue *list);
RC elmc_lazy_map_nth(ElmcValue **out, ElmcValue *list, int index);
RC elmc_lazy_map_to_cons(ElmcValue **out, ElmcValue *list);

RC elmc_list_from_tuple2_int_array(ElmcValue **out, const elmc_int_t items[][2], int count);
RC elmc_render_cmd6_take(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5);
RC elmc_render_text_cmd_take(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4, elmc_int_t p5, ElmcValue *text);
RC elmc_list_replace_nth_int(ElmcValue **out, ElmcValue *list, elmc_int_t index, elmc_int_t value);
ElmcValue *elmc_maybe_nothing(void);
RC elmc_maybe_just(ElmcValue **out, ElmcValue *value);
RC elmc_maybe_just_own(ElmcValue **out, ElmcValue *value);
ElmcValue *elmc_maybe_or_tuple_just_payload(ElmcValue *maybe);
ElmcValue *elmc_maybe_or_tuple_just_payload_borrow(ElmcValue *maybe);
RC elmc_result_ok(ElmcValue **out, ElmcValue *value);
RC elmc_result_err(ElmcValue **out, ElmcValue *value);
RC elmc_result_ok_own(ElmcValue **out, ElmcValue *value);
RC elmc_result_err_own(ElmcValue **out, ElmcValue *value);
RC elmc_tuple2(ElmcValue **out, ElmcValue *first, ElmcValue *second);
RC elmc_tuple2_take(ElmcValue **out, ElmcValue *first, ElmcValue *second);
RC elmc_build_constructor_payload(ElmcValue **out, ElmcValue **values, int count);
RC elmc_tuple2_ints(ElmcValue **out, elmc_int_t first, elmc_int_t second);
RC elmc_cmd0(ElmcValue **out, elmc_int_t kind);
RC elmc_cmd_batch(ElmcValue **out, ElmcValue *commands);
int elmc_cmd_is_none(ElmcValue *value);
ElmcValue *elmc_cmd_none(void);
RC elmc_cmd_queue_cons_take(ElmcValue **out, ElmcValue *head, ElmcValue *tail);
RC elmc_cmd_queue_push_back_take(ElmcValue **out, ElmcValue *queue, ElmcValue *cmd);
RC elmc_cmd_queue_concat_take(ElmcValue **out, ElmcValue *left, ElmcValue *right);
ElmcValue *elmc_cmd_queue_peel_manager(ElmcValue *value);
RC elmc_cmd_queue_push_entry(ElmcValue **out, ElmcValue *flat, ElmcValue *entry);
RC elmc_cmd_queue_normalize(ElmcValue **out, ElmcValue *cmd);

RC elmc_cmd_map(ElmcValue **out, ElmcValue *f, ElmcValue *cmd);
RC elmc_sub_batch(ElmcValue **out, ElmcValue *subs);
RC elmc_sub_map(ElmcValue **out, ElmcValue *f, ElmcValue *sub);
RC elmc_port_outgoing(ElmcValue **out, ElmcValue *port_name, ElmcValue *payload);
RC elmc_port_incoming_sub(ElmcValue **out, ElmcValue *port_name, ElmcValue *callback);
RC elmc_cmd1(ElmcValue **out, elmc_int_t kind, elmc_int_t p0);
RC elmc_cmd1_string(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, const char *text);
RC elmc_cmd_companion_send_value(ElmcValue **out, ElmcValue *message);
RC elmc_cmd2(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1);
RC elmc_cmd3(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2);
RC elmc_cmd4(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3);
RC elmc_cmd5(ElmcValue **out, elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4);
RC elmc_sub0(ElmcValue **out, elmc_int_t mask);
RC elmc_sub1(ElmcValue **out, elmc_int_t mask, elmc_int_t p0);
RC elmc_sub2(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1);
RC elmc_sub3(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2);
RC elmc_sub4(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3);
RC elmc_sub5(ElmcValue **out, elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4);

elmc_int_t elmc_as_int(ElmcValue *value);
elmc_int_t elmc_text_options_packed(ElmcValue *value);
elmc_int_t elmc_as_int_number(ElmcValue *value);
int elmc_value_is_unit(ElmcValue *value);
elmc_int_t elmc_int_idiv(elmc_int_t numerator, elmc_int_t denominator);
static inline elmc_int_t elmc_int_mod_by(elmc_int_t base, elmc_int_t value) {
  if (base == 0) return 0;
  elmc_int_t r = value % base;
  return r < 0 ? r + (base < 0 ? -base : base) : r;
}
static inline elmc_int_t elmc_angle_from_minute(elmc_int_t minute) {
  elmc_int_t angle = elmc_int_idiv(((minute - (elmc_int_t)720) * (elmc_int_t)65536), (elmc_int_t)1440) % (elmc_int_t)65536;
  return angle < 0 ? angle + (elmc_int_t)65536 : angle;
}
elmc_int_t elmc_polar_point_x(elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle);
elmc_int_t elmc_polar_point_y(elmc_int_t cx, elmc_int_t cy, elmc_int_t radius, elmc_int_t angle);
elmc_int_t elmc_as_bool(ElmcValue *value);
int elmc_value_equal(ElmcValue *left, ElmcValue *right);
int elmc_list_equal_int(ElmcValue *left, ElmcValue *right);
int elmc_string_length(ElmcValue *value);
RC elmc_list_head(ElmcValue **out, ElmcValue *list);
RC elmc_list_nth_maybe(ElmcValue **out, ElmcValue *list, ElmcValue *index);
RC elmc_list_nth_maybe_int(ElmcValue **out, ElmcValue *list, elmc_int_t index);
elmc_int_t elmc_list_nth_int_default(ElmcValue *list, elmc_int_t index, elmc_int_t default_value);
RC elmc_list_nth_int_default_boxed(ElmcValue **out, ElmcValue *list, ElmcValue *index, ElmcValue *default_value);
elmc_int_t elmc_list_head_with_default_int(elmc_int_t default_val, ElmcValue *list);
ElmcValue *elmc_tuple_first(ElmcValue *tuple);
ElmcValue *elmc_tuple_second(ElmcValue *tuple);
ElmcValue *elmc_tuple_first_borrow(ElmcValue *tuple);
ElmcValue *elmc_tuple_second_borrow(ElmcValue *tuple);
RC elmc_result_inc_or_zero(ElmcValue **out, ElmcValue *result);
RC elmc_basics_max(ElmcValue **out, ElmcValue *left, ElmcValue *right);
RC elmc_basics_min(ElmcValue **out, ElmcValue *left, ElmcValue *right);
RC elmc_basics_clamp(ElmcValue **out, ElmcValue *low, ElmcValue *high, ElmcValue *value);
RC elmc_basics_mod_by(ElmcValue **out, ElmcValue *base, ElmcValue *value);
RC elmc_bitwise_and(ElmcValue **out, ElmcValue *left, ElmcValue *right);
RC elmc_bitwise_or(ElmcValue **out, ElmcValue *left, ElmcValue *right);
RC elmc_bitwise_xor(ElmcValue **out, ElmcValue *left, ElmcValue *right);
RC elmc_bitwise_complement(ElmcValue **out, ElmcValue *value);
RC elmc_bitwise_shift_left_by(ElmcValue **out, ElmcValue *bits, ElmcValue *value);
RC elmc_bitwise_shift_right_by(ElmcValue **out, ElmcValue *bits, ElmcValue *value);
RC elmc_bitwise_shift_right_zf_by(ElmcValue **out, ElmcValue *bits, ElmcValue *value);
RC elmc_char_to_code(ElmcValue **out, ElmcValue *value);
RC elmc_debug_log(ElmcValue **out, ElmcValue *label, ElmcValue *value);
RC elmc_debug_todo(ElmcValue **out, ElmcValue *label);
RC elmc_debug_to_string(ElmcValue **out, ElmcValue *value);
/* Defined by generated C (union ctor table); declared here so runtime.c compiles alone. */
const char *elmc_debug_union_ctor_name(elmc_int_t tag);
RC elmc_debug_set_to_string(ElmcValue **out, ElmcValue *set);
RC elmc_append(ElmcValue **out, ElmcValue *left, ElmcValue *right);
RC elmc_string_append(ElmcValue **out, ElmcValue *left, ElmcValue *right);
RC elmc_string_append_native(ElmcValue **out, const char *left, const char *right);
ElmcValue *elmc_string_is_empty(ElmcValue *value);
RC elmc_dict_from_list(ElmcValue **out, ElmcValue *items);
RC elmc_dict_insert(ElmcValue **out, ElmcValue *key, ElmcValue *value, ElmcValue *dict);
RC elmc_dict_get(ElmcValue **out, ElmcValue *key, ElmcValue *dict);
elmc_int_t elmc_dict_get_with_default_int(elmc_int_t default_val, elmc_int_t key, ElmcValue *dict);
elmc_int_t elmc_dict_get_with_default_int_value(elmc_int_t default_val, ElmcValue *key, ElmcValue *dict);
ElmcValue *elmc_dict_member(ElmcValue *key, ElmcValue *dict);
RC elmc_dict_size(ElmcValue **out, ElmcValue *dict);
RC elmc_set_from_list(ElmcValue **out, ElmcValue *items);
RC elmc_set_insert(ElmcValue **out, ElmcValue *value, ElmcValue *set);
RC elmc_set_insert_int(ElmcValue **out, elmc_int_t key, ElmcValue *set);
RC elmc_set_remove_int(ElmcValue **out, elmc_int_t key, ElmcValue *set);
int elmc_set_member_int(elmc_int_t key, ElmcValue *set);
ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set);
RC elmc_set_size(ElmcValue **out, ElmcValue *set);
ElmcValue *elmc_array_empty(void);
ElmcValue *elmc_array_from_list(ElmcValue *items);
RC elmc_array_length(ElmcValue **out, ElmcValue *array);
RC elmc_array_get(ElmcValue **out, ElmcValue *index, ElmcValue *array);
elmc_int_t elmc_array_get_with_default_int(elmc_int_t default_val, elmc_int_t index, ElmcValue *array);
RC elmc_array_set(ElmcValue **out, ElmcValue *index, ElmcValue *value, ElmcValue *array);
RC elmc_array_push(ElmcValue **out, ElmcValue *value, ElmcValue *array);
RC elmc_task_succeed(ElmcValue **out, ElmcValue *value);
RC elmc_task_fail(ElmcValue **out, ElmcValue *value);
RC elmc_task_map(ElmcValue **out, ElmcValue *f, ElmcValue *task);
RC elmc_task_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b);
RC elmc_task_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *task);
ElmcValue *elmc_task_on_error(ElmcValue *f, ElmcValue *task);
ElmcValue *elmc_task_perform(ElmcValue *cmd_desc);
RC elmc_task_command(ElmcValue **out, ElmcValue *task);
RC elmc_task_force(ElmcValue **out, ElmcValue *task);
RC elmc_process_spawn(ElmcValue **out, ElmcValue *task);
void elmc_process_release_all_slots(void);
RC elmc_process_sleep(ElmcValue **out, ElmcValue *milliseconds);
RC elmc_process_kill(ElmcValue **out, ElmcValue *pid);
RC elmc_time_now_millis(ElmcValue **out);
RC elmc_time_zone_offset_minutes(ElmcValue **out);
RC elmc_cmd_backlight_from_maybe(ElmcValue **out, ElmcValue *maybe_mode);

/* --- List operations --- */
RC elmc_list_tail(ElmcValue **out, ElmcValue *list);
ElmcValue *elmc_list_is_empty(ElmcValue *list);
elmc_int_t elmc_list_length_native(ElmcValue *list);
RC elmc_list_length(ElmcValue **out, ElmcValue *list);
ElmcValue *elmc_list_length_gte(ElmcValue *list, elmc_int_t min);
RC elmc_list_reverse(ElmcValue **out, ElmcValue *list);
RC elmc_list_copy(ElmcValue **out, ElmcValue *list);
ElmcValue *elmc_list_member(ElmcValue *value, ElmcValue *list);
RC elmc_list_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_filter(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_find_first(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_filter_record_field(ElmcValue **out, ElmcValue *list, elmc_int_t field_index);
RC elmc_list_filter_record_and(ElmcValue **out, ElmcValue *list, elmc_int_t field_a, elmc_int_t field_b);
RC elmc_list_map_record_field(ElmcValue **out, ElmcValue *list, elmc_int_t field_index);
RC elmc_list_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list);
RC elmc_list_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *list);
RC elmc_list_append(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_list_concat(ElmcValue **out, ElmcValue *lists);
RC elmc_list_concat_array(ElmcValue **out, ElmcValue * const *lists, int count);
RC elmc_list_concat_map(ElmcValue **out, ElmcValue *f, ElmcValue *list);
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
RC elmc_list_range(ElmcValue **out, elmc_int_t lo, elmc_int_t hi);
RC elmc_list_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *value);
RC elmc_list_repeat_count(ElmcValue **out, elmc_int_t count, ElmcValue *value);
RC elmc_list_take(ElmcValue **out, ElmcValue *n, ElmcValue *list);
RC elmc_list_take_int(ElmcValue **out, elmc_int_t count, ElmcValue *list);
RC elmc_list_drop(ElmcValue **out, ElmcValue *n, ElmcValue *list);
RC elmc_list_drop_int(ElmcValue **out, elmc_int_t count, ElmcValue *list);
RC elmc_list_slice_int(ElmcValue **out, elmc_int_t drop, elmc_int_t take, ElmcValue *list);
RC elmc_list_partition(ElmcValue **out, ElmcValue *f, ElmcValue *list);
RC elmc_list_unzip(ElmcValue **out, ElmcValue *list);
RC elmc_list_intersperse(ElmcValue **out, ElmcValue *sep, ElmcValue *list);
RC elmc_list_map2(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b);
RC elmc_list_map3(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c);
RC elmc_list_map4(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d);
RC elmc_list_map5(ElmcValue **out, ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e);

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
RC elmc_result_to_maybe(ElmcValue **out, ElmcValue *result);
RC elmc_result_from_maybe(ElmcValue **out, ElmcValue *err, ElmcValue *maybe);

/* --- String operations (extended) --- */
RC elmc_string_length_val(ElmcValue **out, ElmcValue *s);
RC elmc_string_reverse(ElmcValue **out, ElmcValue *s);
RC elmc_string_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *s);
RC elmc_string_replace(ElmcValue **out, ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s);
RC elmc_string_from_int(ElmcValue **out, ElmcValue *n);
RC elmc_string_from_native_int(ElmcValue **out, elmc_int_t n);
RC elmc_string_to_int(ElmcValue **out, ElmcValue *s);
RC elmc_string_to_upper(ElmcValue **out, ElmcValue *s);
RC elmc_string_to_lower(ElmcValue **out, ElmcValue *s);
RC elmc_string_trim(ElmcValue **out, ElmcValue *s);
RC elmc_string_trim_left(ElmcValue **out, ElmcValue *s);
RC elmc_string_trim_right(ElmcValue **out, ElmcValue *s);
ElmcValue *elmc_string_contains(ElmcValue *sub, ElmcValue *s);
int elmc_string_equals_cstr(ElmcValue *value, const char *literal);
int elmc_string_equals(ElmcValue *left, ElmcValue *right);
int elmc_string_compare(ElmcValue *left, ElmcValue *right);
ElmcValue *elmc_string_starts_with(ElmcValue *prefix, ElmcValue *s);
ElmcValue *elmc_string_ends_with(ElmcValue *suffix, ElmcValue *s);
RC elmc_string_split(ElmcValue **out, ElmcValue *sep, ElmcValue *s);
RC elmc_string_join(ElmcValue **out, ElmcValue *sep, ElmcValue *list);
RC elmc_string_words(ElmcValue **out, ElmcValue *s);
RC elmc_string_lines(ElmcValue **out, ElmcValue *s);
RC elmc_string_slice(ElmcValue **out, ElmcValue *start, ElmcValue *end_idx, ElmcValue *s);
RC elmc_string_left(ElmcValue **out, ElmcValue *n, ElmcValue *s);
RC elmc_string_right(ElmcValue **out, ElmcValue *n, ElmcValue *s);
RC elmc_string_drop_left(ElmcValue **out, ElmcValue *n, ElmcValue *s);
RC elmc_string_drop_right(ElmcValue **out, ElmcValue *n, ElmcValue *s);
RC elmc_string_cons(ElmcValue **out, ElmcValue *ch, ElmcValue *s);
RC elmc_string_uncons(ElmcValue **out, ElmcValue *s);
RC elmc_string_to_list(ElmcValue **out, ElmcValue *s);
RC elmc_string_from_list(ElmcValue **out, ElmcValue *list);
RC elmc_string_from_char(ElmcValue **out, ElmcValue *ch);
RC elmc_string_pad(ElmcValue **out, ElmcValue *n, ElmcValue *ch, ElmcValue *s);
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
RC elmc_basics_negate(ElmcValue **out, ElmcValue *x);
RC elmc_basics_abs(ElmcValue **out, ElmcValue *x);
RC elmc_basics_log(ElmcValue **out, ElmcValue *x);
RC elmc_basics_remainder_by(ElmcValue **out, ElmcValue *base, ElmcValue *value);
RC elmc_basics_pow(ElmcValue **out, ElmcValue *base, ElmcValue *exponent);
ElmcValue *elmc_basics_xor(ElmcValue *a, ElmcValue *b);
RC elmc_basics_compare(ElmcValue **out, ElmcValue *a, ElmcValue *b);

/* --- Char (extended) --- */
ElmcValue *elmc_char_is_upper(ElmcValue *ch);
ElmcValue *elmc_char_is_lower(ElmcValue *ch);
ElmcValue *elmc_char_is_alpha(ElmcValue *ch);
ElmcValue *elmc_char_is_alpha_num(ElmcValue *ch);
ElmcValue *elmc_char_is_digit(ElmcValue *ch);
ElmcValue *elmc_char_is_oct_digit(ElmcValue *ch);
ElmcValue *elmc_char_is_hex_digit(ElmcValue *ch);
RC elmc_char_to_upper(ElmcValue **out, ElmcValue *ch);
RC elmc_char_to_lower(ElmcValue **out, ElmcValue *ch);

/* --- Dict (extended) --- */
RC elmc_dict_remove(ElmcValue **out, ElmcValue *key, ElmcValue *dict);
ElmcValue *elmc_dict_is_empty(ElmcValue *dict);
RC elmc_dict_keys(ElmcValue **out, ElmcValue *dict);
RC elmc_dict_values(ElmcValue **out, ElmcValue *dict);
RC elmc_dict_to_list(ElmcValue **out, ElmcValue *dict);
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
RC elmc_dict_singleton(ElmcValue **out, ElmcValue *key, ElmcValue *value);

/* --- Set (extended) --- */
RC elmc_set_singleton(ElmcValue **out, ElmcValue *value);
RC elmc_set_remove(ElmcValue **out, ElmcValue *value, ElmcValue *set);
ElmcValue *elmc_set_is_empty(ElmcValue *set);
RC elmc_set_to_list(ElmcValue **out, ElmcValue *set);
RC elmc_set_union(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_set_intersect(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_set_diff(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_set_map(ElmcValue **out, ElmcValue *f, ElmcValue *set);
RC elmc_set_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set);
RC elmc_set_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *set);
RC elmc_set_filter(ElmcValue **out, ElmcValue *f, ElmcValue *set);
RC elmc_set_partition(ElmcValue **out, ElmcValue *f, ElmcValue *set);

/* --- Array (extended) --- */
RC elmc_array_initialize(ElmcValue **out, ElmcValue *n, ElmcValue *f);
RC elmc_array_repeat(ElmcValue **out, ElmcValue *n, ElmcValue *value);
ElmcValue *elmc_array_is_empty(ElmcValue *array);
RC elmc_array_to_list(ElmcValue **out, ElmcValue *array);
RC elmc_array_to_indexed_list(ElmcValue **out, ElmcValue *array);
RC elmc_array_map(ElmcValue **out, ElmcValue *f, ElmcValue *array);
RC elmc_array_indexed_map(ElmcValue **out, ElmcValue *f, ElmcValue *array);
RC elmc_array_foldl(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *array);
RC elmc_array_foldr(ElmcValue **out, ElmcValue *f, ElmcValue *acc, ElmcValue *array);
RC elmc_array_filter(ElmcValue **out, ElmcValue *f, ElmcValue *array);
RC elmc_array_append(ElmcValue **out, ElmcValue *a, ElmcValue *b);
RC elmc_array_slice(ElmcValue **out, ElmcValue *start, ElmcValue *end_idx, ElmcValue *array);

/* --- Json.Decode --- */
RC elmc_json_decode_value(ElmcValue **out, ElmcValue *decoder, ElmcValue *value);
RC elmc_json_decode_string(ElmcValue **out, ElmcValue *decoder, ElmcValue *s);
RC elmc_json_decode_string_decoder(ElmcValue **out);
RC elmc_json_decode_int_decoder(ElmcValue **out);
RC elmc_json_decode_bool_decoder(ElmcValue **out);
RC elmc_json_decode_null(ElmcValue **out, ElmcValue *default_val);
RC elmc_json_decode_nullable(ElmcValue **out, ElmcValue *decoder);
RC elmc_json_decode_list(ElmcValue **out, ElmcValue *decoder);
RC elmc_json_decode_array(ElmcValue **out, ElmcValue *decoder);
RC elmc_json_decode_field(ElmcValue **out, ElmcValue *name, ElmcValue *decoder);
RC elmc_json_decode_at(ElmcValue **out, ElmcValue *path, ElmcValue *decoder);
RC elmc_json_decode_index(ElmcValue **out, ElmcValue *idx, ElmcValue *decoder);
RC elmc_json_decode_map(ElmcValue **out, ElmcValue *f, ElmcValue *decoder);
RC elmc_json_decode_map2(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2);
RC elmc_json_decode_map3(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3);
RC elmc_json_decode_map4(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4);
RC elmc_json_decode_map5(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5);
RC elmc_json_decode_map6(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6);
RC elmc_json_decode_map7(ElmcValue **out, ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6, ElmcValue *d7);
RC elmc_json_decode_succeed(ElmcValue **out, ElmcValue *value);
RC elmc_json_decode_fail(ElmcValue **out, ElmcValue *msg);
RC elmc_json_decode_and_then(ElmcValue **out, ElmcValue *f, ElmcValue *decoder);
RC elmc_json_decode_one_of(ElmcValue **out, ElmcValue *decoders);
RC elmc_json_decode_maybe(ElmcValue **out, ElmcValue *decoder);
RC elmc_json_decode_lazy(ElmcValue **out, ElmcValue *thunk);
RC elmc_json_decode_value_decoder(ElmcValue **out);
RC elmc_json_decode_error_to_string(ElmcValue **out, ElmcValue *err);
RC elmc_json_decode_key_value_pairs(ElmcValue **out, ElmcValue *decoder);
RC elmc_json_decode_dict(ElmcValue **out, ElmcValue *decoder);

/* --- Json.Encode --- */
RC elmc_json_encode_string(ElmcValue **out, ElmcValue *s);
RC elmc_json_encode_int(ElmcValue **out, ElmcValue *n);
RC elmc_json_encode_bool(ElmcValue **out, ElmcValue *b);
RC elmc_json_encode_null(ElmcValue **out);
RC elmc_json_encode_list(ElmcValue **out, ElmcValue *f, ElmcValue *items);
RC elmc_json_encode_array(ElmcValue **out, ElmcValue *f, ElmcValue *items);
RC elmc_json_encode_set(ElmcValue **out, ElmcValue *f, ElmcValue *items);
RC elmc_json_encode_object(ElmcValue **out, ElmcValue *pairs);
RC elmc_json_encode_add_field(ElmcValue **out, ElmcValue *key, ElmcValue *value, ElmcValue *obj);
RC elmc_json_encode_add_entry(ElmcValue **out, ElmcValue *func, ElmcValue *value, ElmcValue *arr);
RC elmc_json_encode_dict(ElmcValue **out, ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict);
RC elmc_json_encode_encode(ElmcValue **out, ElmcValue *indent, ElmcValue *value);

/* Internal Json parser/encoder structs (kept in header so pruned runtimes compile). */
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

RC elmc_string_chop_end(ElmcValue **out, ElmcValue *str, ElmcValue *suffix);
RC elmc_string_chop_start(ElmcValue **out, ElmcValue *str, ElmcValue *prefix);
RC elmc_string_chop_forward_slashes(ElmcValue **out, ElmcValue *str);
RC elmc_url_percent_encode(ElmcValue **out, ElmcValue *segment);
RC elmc_url_percent_decode(ElmcValue **out, ElmcValue *segment);
RC elmc_url_from_string(ElmcValue **out, ElmcValue *url);
RC elmc_http_empty_body(ElmcValue **out, ElmcValue *req);
RC elmc_http_pair(ElmcValue **out, ElmcValue *key, ElmcValue *value);
RC elmc_http_to_data_view(ElmcValue **out, ElmcValue *body);
RC elmc_http_expect(ElmcValue **out, ElmcValue *to_msg, ElmcValue *decoder, ElmcValue *req);
RC elmc_http_command(ElmcValue **out, ElmcValue *req);
RC elmc_http_cancel(ElmcValue **out, ElmcValue *tracker);
RC elmc_backend_task_http_get_json(ElmcValue **out, ElmcValue *url, ElmcValue *expect);
RC elmc_backend_task_http_get(ElmcValue **out, ElmcValue *url, ElmcValue *expect);
RC elmc_backend_task_http_get_with_options(ElmcValue **out, ElmcValue *url, ElmcValue *options, ElmcValue *expect);
RC elmc_backend_task_http_expect_json(ElmcValue **out, ElmcValue *decoder);
RC elmc_backend_task_http_expect_string(ElmcValue **out);
RC elmc_backend_task_http_expect_whatever(ElmcValue **out);
RC elmc_backend_task_http_expect_bytes(ElmcValue **out);
RC elmc_backend_task_http_with_metadata(ElmcValue **out, ElmcValue *expect);
RC elmc_backend_task_http_empty_body(ElmcValue **out);
RC elmc_backend_task_http_string_body(ElmcValue **out, ElmcValue *body);
RC elmc_backend_task_http_json_body(ElmcValue **out, ElmcValue *value);
RC elmc_backend_task_http_bytes_body(ElmcValue **out, ElmcValue *bytes);
RC elmc_bytes_encode_sequence(ElmcValue **out, ElmcValue *list);
RC elmc_backend_task_http_request(ElmcValue **out, ElmcValue *req);
RC elmc_backend_task_http_post(ElmcValue **out, ElmcValue *url, ElmcValue *body, ElmcValue *expect);
RC elmc_file_download_task(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content);
RC elmc_file_select(ElmcValue **out, ElmcValue *to_msg, ElmcValue *accept);
RC elmc_file_download(ElmcValue **out, ElmcValue *name, ElmcValue *mime, ElmcValue *content);
RC elmc_random_generate(ElmcValue **out, ElmcValue *to_msg, ElmcValue *generator);
RC elmc_regex_from_string(ElmcValue **out, ElmcValue *pattern);
RC elmc_regex_find(ElmcValue **out, ElmcValue *regex, ElmcValue *str);
RC elmc_regex_contains(ElmcValue **out, ElmcValue *regex, ElmcValue *str);
RC elmc_regex_replace(ElmcValue **out, ElmcValue *regex, ElmcValue *replacement, ElmcValue *str);
RC elmc_time_here(ElmcValue **out);
RC elmc_browser_get_viewport(ElmcValue **out);



RC elmc_record_new(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values);
RC elmc_record_new_take(ElmcValue **out, int field_count, const char **field_names, ElmcValue **field_values);
RC elmc_record_new_ints(ElmcValue **out, int field_count, const char **field_names, const elmc_int_t *field_values);
RC elmc_record_new_static(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values);
RC elmc_record_new_static_take(ElmcValue **out, int field_count, const char * const *field_names, ElmcValue **field_values);
RC elmc_record_new_static_ints(ElmcValue **out, int field_count, const char * const *field_names, const elmc_int_t *field_values);
RC elmc_record_new_values(ElmcValue **out, int field_count, ElmcValue **field_values);
RC elmc_record_new_values_take(ElmcValue **out, int field_count, ElmcValue **field_values);
RC elmc_record_new_values_ints(ElmcValue **out, int field_count, const elmc_int_t *field_values);

RC elmc_record_update(ElmcValue **out, ElmcValue *record, const char *field_name, ElmcValue *new_value);
RC elmc_record_update_index(ElmcValue **out, ElmcValue *record, int index, ElmcValue *new_value);
RC elmc_record_update_index_cow(ElmcValue **out, ElmcValue *record, int index, ElmcValue *new_value);
RC elmc_record_update_index_cow_drop(ElmcValue **out, ElmcValue *record, int index, ElmcValue *new_value);
RC elmc_record_update_index_int_cow(ElmcValue **out, ElmcValue *record, int index, elmc_int_t new_value);
RC elmc_record_update_index_int_cow_drop(ElmcValue **out, ElmcValue *record, int index, elmc_int_t new_value);
RC elmc_record_update_index_bool_cow(ElmcValue **out, ElmcValue *record, int index, bool new_value);
RC elmc_record_update_index_bool_cow_drop(ElmcValue **out, ElmcValue *record, int index, bool new_value);


static inline bool elmc_value_is_true(ElmcValue *v) {
  return v && ((v->tag == ELMC_TAG_BOOL && elmc_as_int(v) != 0) ||
               (v->tag == ELMC_TAG_INT && elmc_as_int(v) == 1));
}

static inline bool elmc_value_is_false(ElmcValue *v) {
  return v && ((v->tag == ELMC_TAG_BOOL && elmc_as_int(v) == 0) ||
               (v->tag == ELMC_TAG_INT && elmc_as_int(v) == 0));
}

static inline ElmcValue *elmc_maybe_just_payload(ElmcValue *v) {
  if (v && v->tag == ELMC_TAG_MAYBE && ((ElmcMaybe *)v->payload)->is_just)
    return ((ElmcMaybe *)v->payload)->value;
  if (v && v->tag == ELMC_TAG_TUPLE2 && v->payload != NULL &&
      elmc_as_int(((ElmcTuple2 *)v->payload)->first) == 1)
    return ((ElmcTuple2 *)v->payload)->second;
  return NULL;
}

static inline bool elmc_maybe_is_just(ElmcValue *v) {
  return elmc_maybe_just_payload(v) != NULL;
}

static inline bool elmc_maybe_is_nothing(ElmcValue *v) {
  if (!v) return true;
  if (v->tag == ELMC_TAG_MAYBE)
    return !((ElmcMaybe *)v->payload)->is_just;
  if (v->tag == ELMC_TAG_INT)
    return elmc_as_int(v) == 0;
  return false;
}

static inline bool elmc_maybe_just_true(ElmcValue *v) {
  return elmc_value_is_true(elmc_maybe_just_payload(v));
}

static inline bool elmc_maybe_just_false(ElmcValue *v) {
  return elmc_value_is_false(elmc_maybe_just_payload(v));
}

static inline elmc_int_t elmc_union_tag_as_int(ElmcValue *v) {
  if (!v) return -1;
  /* Order is a dedicated scalar tag with runtime values LT=-1, EQ=0, GT=1. */
  if (v->tag == ELMC_TAG_ORDER) return elmc_as_int(v);
  if (v->tag == ELMC_TAG_INT) return elmc_as_int(v);
  if (v->tag == ELMC_TAG_TUPLE2 && v->payload != NULL)
    return elmc_as_int(((ElmcTuple2 *)v->payload)->first);
  return -1;
}

static inline bool elmc_union_tag_matches(ElmcValue *v, elmc_int_t tag) {
  if (!v) return false;
  if (v->tag == ELMC_TAG_RESULT && v->payload != NULL) {
    ElmcResult *r = (ElmcResult *)v->payload;
    return r->is_ok ? (tag == 1) : (tag == 2);
  }
  if (v->tag == ELMC_TAG_MAYBE && v->payload != NULL) {
    ElmcMaybe *m = (ElmcMaybe *)v->payload;
    return m->is_just ? (tag == 1) : (tag == 2);
  }
  if (v->tag == ELMC_TAG_ORDER) return elmc_as_int(v) == tag;
  return (v->tag == ELMC_TAG_INT && elmc_as_int(v) == tag) ||
         (v->tag == ELMC_TAG_TUPLE2 && v->payload != NULL &&
          elmc_as_int(((ElmcTuple2 *)v->payload)->first) == tag);
}

static inline ElmcValue *elmc_union_payload(ElmcValue *v) {
  if (v && v->tag == ELMC_TAG_RESULT && v->payload != NULL)
    return ((ElmcResult *)v->payload)->value;
  if (v && v->tag == ELMC_TAG_MAYBE && v->payload != NULL &&
      ((ElmcMaybe *)v->payload)->is_just)
    return ((ElmcMaybe *)v->payload)->value;
  if (v && v->tag == ELMC_TAG_TUPLE2 && v->payload != NULL)
    return ((ElmcTuple2 *)v->payload)->second;
  return v;
}

static inline elmc_int_t elmc_union_payload_int(ElmcValue *v) {
  if (!v) return 0;
  if (v->tag == ELMC_TAG_INT) return elmc_as_int(v);
  if (v->tag == ELMC_TAG_TUPLE2 && v->payload != NULL) {
    ElmcTuple2 *tuple = (ElmcTuple2 *)v->payload;
    return tuple->second ? elmc_as_int(tuple->second) : 0;
  }
  return 0;
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
uint32_t elmc_record_mutation_gen(ElmcValue *record);

RC elmc_closure_new(ElmcValue **out, ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures);
RC elmc_closure_new_rc(ElmcValue **out, RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures);
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
void elmc_rc_track_dump_since(uint32_t min_id, FILE *out);
uint32_t elmc_rc_track_next_alloc_id(void);
ElmcValue *elmc_rc_track_retain(ElmcValue *value, const char *file, int line);
void elmc_rc_track_release(ElmcValue *value, const char *file, int line);
#define elmc_retain(value) elmc_rc_track_retain((value), __FILE__, __LINE__)
#define elmc_release(value) elmc_rc_track_release((value), __FILE__, __LINE__)
#else
ElmcValue *elmc_retain(ElmcValue *value);
void elmc_release(ElmcValue *value);
#endif
void elmc_release_deep(ElmcValue *value);


/* Release each owned slot independently. Do not coalesce by pointer equality:
   phi/retain chains legitimately store the same pointer in multiple slots, each
   with its own rc credit. Coalescing under-releases (rc_track 2048 merge).
   Transfer assigns must null the source slot so true aliases are not double-freed. */
static inline void elmc_release_array_lifo(ElmcValue **slots, size_t count) {
  while (count-- > 0) {
    ElmcValue *value = slots[count];
    if (value) {
      slots[count] = NULL;
      elmc_release(value);
    }
  }
}

static inline void elmc_owned_null_aliases(ElmcValue **slots, size_t count, ElmcValue *value) {
  if (!value) return;
  for (size_t i = 0; i < count; i++) {
    if (slots[i] == value) slots[i] = NULL;
  }
}


#ifndef ELMC_ALLOC_TRACK
#define ELMC_ALLOC_TRACK 0
#endif

#if ELMC_ALLOC_TRACK
#include <stdio.h>
void elmc_alloc_track_reset(void);
uint32_t elmc_alloc_track_live_count(void);
int elmc_alloc_track_check_balanced(void);
void elmc_alloc_track_dump_live(FILE *out);
void elmc_alloc_track_dump_since(uint32_t min_id, FILE *out);
uint32_t elmc_alloc_track_next_alloc_id(void);
/* Cumulative heap fallbacks from elmc_owned_slots_acquire (context "owned_slots"). */
uint32_t elmc_alloc_track_owned_slots_alloc_count(void);
/* Non-static: owned_slots pool heap-fallback and other paths call elmc_free. */
void elmc_free_impl(void *ptr, const char *context, const char *file, int line);
#endif

#ifndef ELMC_ALLOC_TRACE
#define ELMC_ALLOC_TRACE 0
#endif

#if ELMC_ALLOC_TRACK && !ELMC_ALLOC_TRACE
#undef ELMC_ALLOC_TRACE
#define ELMC_ALLOC_TRACE 1
#endif

#if ELMC_ALLOC_TRACK
#define elmc_free(ptr) elmc_free_impl((ptr), __func__, __FILE__, __LINE__)
#else
#define elmc_free(ptr) free(ptr)
#endif

void *elmc_malloc_impl(size_t size, const char *context, const char *file, int line);
void *elmc_calloc_impl(size_t nmemb, size_t size, const char *context, const char *file, int line);
#if ELMC_ALLOC_TRACE
#define elmc_malloc(size, context) elmc_malloc_impl((size), (context), __FILE__, __LINE__)
#define elmc_calloc(nmemb, size, context) elmc_calloc_impl((nmemb), (size), (context), __FILE__, __LINE__)
#else
#define elmc_malloc(size, context) elmc_malloc_impl((size), (context), NULL, 0)
#define elmc_calloc(nmemb, size, context) elmc_calloc_impl((nmemb), (size), (context), NULL, 0)
#endif


#ifndef ELMC_OWNED_SLOTS_POOL_DEPTH
#define ELMC_OWNED_SLOTS_POOL_DEPTH 4
#endif
#ifndef ELMC_OWNED_SLOTS_POOL_CAP
#define ELMC_OWNED_SLOTS_POOL_CAP 128
#endif

typedef struct {
  ElmcValue *frames[ELMC_OWNED_SLOTS_POOL_DEPTH][ELMC_OWNED_SLOTS_POOL_CAP];
  int depth;
} ElmcOwnedSlotsPoolState;

ElmcValue **elmc_owned_slots_acquire(int count);
void elmc_owned_slots_release(ElmcValue **owned, int count);


#ifndef ELMC_ALLOC_PROBE
#define ELMC_ALLOC_PROBE 0
#endif

#if ELMC_ALLOC_PROBE && !ELMC_RC_TRACK
#undef ELMC_RC_TRACK
#define ELMC_RC_TRACK 1
#endif

#if ELMC_ALLOC_PROBE && !ELMC_ALLOC_TRACK
#undef ELMC_ALLOC_TRACK
#define ELMC_ALLOC_TRACK 1
#endif

#if ELMC_ALLOC_PROBE
#include <stdio.h>

typedef struct ElmcAllocProbeSnap {
  uint32_t rc_live;
  uint64_t rc_allocated;
  uint64_t rc_released;
  uint32_t rc_next_id;
#if ELMC_ALLOC_TRACK
  uint32_t malloc_live;
  uint32_t malloc_next_id;
#endif
} ElmcAllocProbeSnap;

void elmc_alloc_probe_snap(ElmcAllocProbeSnap *snap);
void elmc_alloc_probe_diff(const ElmcAllocProbeSnap *before, const char *label, FILE *out);
int elmc_alloc_probe_diff_balanced(const ElmcAllocProbeSnap *before, const char *label, FILE *out);
#endif


#endif
