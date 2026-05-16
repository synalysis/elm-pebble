#ifndef ELMC_RUNTIME_H
#define ELMC_RUNTIME_H

#include <stdint.h>
#include <stddef.h>
#define ELMC_PEBBLE_INT32 1


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
  ELMC_TAG_CLOSURE = 12
} ElmcTag;

typedef struct ElmcValue {
  uint32_t rc;
  ElmcTag tag;
  void *payload;
  elmc_int_t scalar;
} ElmcValue;

typedef struct ElmcCons {
  ElmcValue *head;
  ElmcValue *tail;
} ElmcCons;

typedef struct ElmcTuple2 {
  ElmcValue *first;
  ElmcValue *second;
} ElmcTuple2;

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
  const char **field_names;
  ElmcValue **field_values;
} ElmcRecord;

#define ELMC_RECORD_GET_INDEX_INT(record, index) \
  elmc_as_int(((ElmcRecord *)((record)->payload))->field_values[(index)])

typedef struct ElmcClosure {
  ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count);
  int arity;
  int capture_count;
  ElmcValue **captures;
} ElmcClosure;

typedef void (*ElmcPortCallback)(ElmcValue *value, void *context);

ElmcValue *elmc_new_int(elmc_int_t value);
ElmcValue *elmc_new_bool(int value);
ElmcValue *elmc_new_char(elmc_int_t value);
ElmcValue *elmc_new_string(const char *value);
extern ElmcValue ELMC_INT_ZERO;
#define elmc_int_zero() (&ELMC_INT_ZERO)
ElmcValue *elmc_list_nil(void);
ElmcValue *elmc_list_cons(ElmcValue *head, ElmcValue *tail);
ElmcValue *elmc_list_from_values(ElmcValue **items, int count);
ElmcValue *elmc_list_from_values_take(ElmcValue **items, int count);
ElmcValue *elmc_maybe_nothing(void);
ElmcValue *elmc_maybe_just(ElmcValue *value);
ElmcValue *elmc_result_ok(ElmcValue *value);
ElmcValue *elmc_result_err(ElmcValue *value);
ElmcValue *elmc_tuple2(ElmcValue *first, ElmcValue *second);
ElmcValue *elmc_tuple2_take(ElmcValue *first, ElmcValue *second);
ElmcValue *elmc_tuple2_ints(elmc_int_t first, elmc_int_t second);

elmc_int_t elmc_as_int(ElmcValue *value);
elmc_int_t elmc_as_bool(ElmcValue *value);
int elmc_value_equal(ElmcValue *left, ElmcValue *right);
int elmc_string_length(ElmcValue *value);
ElmcValue *elmc_list_head(ElmcValue *list);
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
ElmcValue *elmc_string_append(ElmcValue *left, ElmcValue *right);
ElmcValue *elmc_string_append_native(const char *left, const char *right);
ElmcValue *elmc_string_is_empty(ElmcValue *value);
ElmcValue *elmc_dict_from_list(ElmcValue *items);
ElmcValue *elmc_dict_insert(ElmcValue *key, ElmcValue *value, ElmcValue *dict);
ElmcValue *elmc_dict_get(ElmcValue *key, ElmcValue *dict);
ElmcValue *elmc_dict_member(ElmcValue *key, ElmcValue *dict);
ElmcValue *elmc_dict_size(ElmcValue *dict);
ElmcValue *elmc_set_from_list(ElmcValue *items);
ElmcValue *elmc_set_insert(ElmcValue *value, ElmcValue *set);
ElmcValue *elmc_set_member(ElmcValue *value, ElmcValue *set);
ElmcValue *elmc_set_size(ElmcValue *set);
ElmcValue *elmc_array_empty(void);
ElmcValue *elmc_array_from_list(ElmcValue *items);
ElmcValue *elmc_array_length(ElmcValue *array);
ElmcValue *elmc_array_get(ElmcValue *index, ElmcValue *array);
ElmcValue *elmc_array_set(ElmcValue *index, ElmcValue *value, ElmcValue *array);
ElmcValue *elmc_array_push(ElmcValue *value, ElmcValue *array);
ElmcValue *elmc_task_succeed(ElmcValue *value);
ElmcValue *elmc_task_fail(ElmcValue *value);
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
ElmcValue *elmc_list_reverse(ElmcValue *list);
ElmcValue *elmc_list_member(ElmcValue *value, ElmcValue *list);
ElmcValue *elmc_list_map(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_filter(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *list);
ElmcValue *elmc_list_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *list);
ElmcValue *elmc_list_append(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_list_concat(ElmcValue *lists);
ElmcValue *elmc_list_concat_map(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_indexed_map(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_filter_map(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_sum(ElmcValue *list);
ElmcValue *elmc_list_product(ElmcValue *list);
ElmcValue *elmc_list_maximum(ElmcValue *list);
ElmcValue *elmc_list_minimum(ElmcValue *list);
ElmcValue *elmc_list_any(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_all(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_sort(ElmcValue *list);
ElmcValue *elmc_list_sort_by(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_sort_with(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_singleton(ElmcValue *value);
ElmcValue *elmc_list_range(ElmcValue *lo, ElmcValue *hi);
ElmcValue *elmc_list_repeat(ElmcValue *n, ElmcValue *value);
ElmcValue *elmc_list_take(ElmcValue *n, ElmcValue *list);
ElmcValue *elmc_list_drop(ElmcValue *n, ElmcValue *list);
ElmcValue *elmc_list_partition(ElmcValue *f, ElmcValue *list);
ElmcValue *elmc_list_unzip(ElmcValue *list);
ElmcValue *elmc_list_intersperse(ElmcValue *sep, ElmcValue *list);
ElmcValue *elmc_list_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_list_map3(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c);

/* --- Maybe operations --- */
ElmcValue *elmc_maybe_with_default(ElmcValue *default_val, ElmcValue *maybe);
elmc_int_t elmc_maybe_with_default_int(elmc_int_t default_val, ElmcValue *maybe);
ElmcValue *elmc_maybe_map(ElmcValue *f, ElmcValue *maybe);
ElmcValue *elmc_maybe_map2(ElmcValue *f, ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_maybe_and_then(ElmcValue *f, ElmcValue *maybe);

/* --- Result operations --- */
ElmcValue *elmc_result_map(ElmcValue *f, ElmcValue *result);
ElmcValue *elmc_result_map_error(ElmcValue *f, ElmcValue *result);
ElmcValue *elmc_result_and_then(ElmcValue *f, ElmcValue *result);
ElmcValue *elmc_result_with_default(ElmcValue *default_val, ElmcValue *result);
ElmcValue *elmc_result_to_maybe(ElmcValue *result);
ElmcValue *elmc_result_from_maybe(ElmcValue *err, ElmcValue *maybe);

/* --- String operations (extended) --- */
ElmcValue *elmc_string_length_val(ElmcValue *s);
ElmcValue *elmc_string_reverse(ElmcValue *s);
ElmcValue *elmc_string_repeat(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_replace(ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s);
ElmcValue *elmc_string_from_int(ElmcValue *n);
ElmcValue *elmc_string_from_native_int(elmc_int_t n);
ElmcValue *elmc_string_to_int(ElmcValue *s);
ElmcValue *elmc_string_from_float(ElmcValue *f);
ElmcValue *elmc_string_to_float(ElmcValue *s);
ElmcValue *elmc_string_to_upper(ElmcValue *s);
ElmcValue *elmc_string_to_lower(ElmcValue *s);
ElmcValue *elmc_string_trim(ElmcValue *s);
ElmcValue *elmc_string_trim_left(ElmcValue *s);
ElmcValue *elmc_string_trim_right(ElmcValue *s);
ElmcValue *elmc_string_contains(ElmcValue *sub, ElmcValue *s);
ElmcValue *elmc_string_starts_with(ElmcValue *prefix, ElmcValue *s);
ElmcValue *elmc_string_ends_with(ElmcValue *suffix, ElmcValue *s);
ElmcValue *elmc_string_split(ElmcValue *sep, ElmcValue *s);
ElmcValue *elmc_string_join(ElmcValue *sep, ElmcValue *list);
ElmcValue *elmc_string_words(ElmcValue *s);
ElmcValue *elmc_string_lines(ElmcValue *s);
ElmcValue *elmc_string_slice(ElmcValue *start, ElmcValue *end_idx, ElmcValue *s);
ElmcValue *elmc_string_left(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_right(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_drop_left(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_drop_right(ElmcValue *n, ElmcValue *s);
ElmcValue *elmc_string_cons(ElmcValue *ch, ElmcValue *s);
ElmcValue *elmc_string_uncons(ElmcValue *s);
ElmcValue *elmc_string_to_list(ElmcValue *s);
ElmcValue *elmc_string_from_list(ElmcValue *list);
ElmcValue *elmc_string_from_char(ElmcValue *ch);
ElmcValue *elmc_string_pad(ElmcValue *n, ElmcValue *ch, ElmcValue *s);
ElmcValue *elmc_string_pad_left(ElmcValue *n, ElmcValue *ch, ElmcValue *s);
ElmcValue *elmc_string_pad_right(ElmcValue *n, ElmcValue *ch, ElmcValue *s);
ElmcValue *elmc_string_map(ElmcValue *f, ElmcValue *s);
ElmcValue *elmc_string_filter(ElmcValue *f, ElmcValue *s);
ElmcValue *elmc_string_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *s);
ElmcValue *elmc_string_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *s);
ElmcValue *elmc_string_any(ElmcValue *f, ElmcValue *s);
ElmcValue *elmc_string_all(ElmcValue *f, ElmcValue *s);
ElmcValue *elmc_string_indexes(ElmcValue *sub, ElmcValue *s);

/* --- Tuple operations (extended) --- */
ElmcValue *elmc_tuple_map_first(ElmcValue *f, ElmcValue *t);
ElmcValue *elmc_tuple_map_second(ElmcValue *f, ElmcValue *t);
ElmcValue *elmc_tuple_map_both(ElmcValue *f, ElmcValue *g, ElmcValue *t);

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
ElmcValue *elmc_dict_remove(ElmcValue *key, ElmcValue *dict);
ElmcValue *elmc_dict_is_empty(ElmcValue *dict);
ElmcValue *elmc_dict_keys(ElmcValue *dict);
ElmcValue *elmc_dict_values(ElmcValue *dict);
ElmcValue *elmc_dict_to_list(ElmcValue *dict);
ElmcValue *elmc_dict_map(ElmcValue *f, ElmcValue *dict);
ElmcValue *elmc_dict_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *dict);
ElmcValue *elmc_dict_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *dict);
ElmcValue *elmc_dict_filter(ElmcValue *f, ElmcValue *dict);
ElmcValue *elmc_dict_partition(ElmcValue *f, ElmcValue *dict);
ElmcValue *elmc_dict_union(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_dict_intersect(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_dict_diff(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_dict_merge(ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_dict_update(ElmcValue *key, ElmcValue *f, ElmcValue *dict);
ElmcValue *elmc_dict_singleton(ElmcValue *key, ElmcValue *value);

/* --- Set (extended) --- */
ElmcValue *elmc_set_singleton(ElmcValue *value);
ElmcValue *elmc_set_remove(ElmcValue *value, ElmcValue *set);
ElmcValue *elmc_set_is_empty(ElmcValue *set);
ElmcValue *elmc_set_to_list(ElmcValue *set);
ElmcValue *elmc_set_union(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_set_intersect(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_set_diff(ElmcValue *a, ElmcValue *b);
ElmcValue *elmc_set_map(ElmcValue *f, ElmcValue *set);
ElmcValue *elmc_set_foldl(ElmcValue *f, ElmcValue *acc, ElmcValue *set);
ElmcValue *elmc_set_foldr(ElmcValue *f, ElmcValue *acc, ElmcValue *set);
ElmcValue *elmc_set_filter(ElmcValue *f, ElmcValue *set);
ElmcValue *elmc_set_partition(ElmcValue *f, ElmcValue *set);

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


ElmcValue *elmc_new_float(double value);
double elmc_as_float(ElmcValue *value);
double elmc_basics_sqrt_double(double x);
double elmc_basics_sin_double(double x);
double elmc_basics_cos_double(double x);
double elmc_basics_tan_double(double x);

ElmcValue *elmc_record_new(int field_count, const char **field_names, ElmcValue **field_values);
ElmcValue *elmc_record_new_take(int field_count, const char **field_names, ElmcValue **field_values);
ElmcValue *elmc_record_new_ints(int field_count, const char **field_names, const elmc_int_t *field_values);
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

ElmcValue *elmc_closure_new(ElmcValue *(*fn)(ElmcValue **args, int argc, ElmcValue **captures, int capture_count), int arity, int capture_count, ElmcValue **captures);
ElmcValue *elmc_closure_call(ElmcValue *closure, ElmcValue **args, int argc);
ElmcValue *elmc_apply_extra(ElmcValue *value, ElmcValue **args, int argc);

uint64_t elmc_rc_allocated_count(void);
uint64_t elmc_rc_released_count(void);

ElmcValue *elmc_retain(ElmcValue *value);
void elmc_release(ElmcValue *value);
void elmc_release_deep(ElmcValue *value);

#endif
