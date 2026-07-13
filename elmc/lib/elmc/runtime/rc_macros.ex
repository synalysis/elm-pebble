defmodule Elmc.Runtime.RcMacros do
  @moduledoc """
  C macro fragments for RC control flow and failure logging.
  """

  alias Elmc.Runtime.RcCodes

  @spec header_declarations() :: String.t()
  def header_declarations do
    """
    #{RcCodes.enum_declarations()}

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
    #define ELMC_CHECK_RC_BREAK(rc, file, line) \\
      if (1) { \\
        (void)(rc); \\
        (void)(file); \\
        (void)(line); \\
        break; \\
      }
    #endif

    #define CHECK_RC(rc_var) \\
      if ((rc_var) != RC_SUCCESS) { \\
        elmc_rc_record_fail((rc_var), __LINE__); \\
        ELMC_CHECK_RC_BREAK((rc_var), __FILE__, __LINE__); \\
      }

    #define CHECK_RC_TO(rc_var, expr) \\
      do { \\
        (rc_var) = (expr); \\
        if ((rc_var) != RC_SUCCESS) { \\
          elmc_rc_record_fail((rc_var), __LINE__); \\
          ELMC_CHECK_RC_BREAK((rc_var), __FILE__, __LINE__); \\
        } \\
      } while (0)

    #ifndef ELMC_RELEASE
    #define ELMC_RELEASE(var) \\
      do { \\
        elmc_release(var); \\
        (var) = NULL; \\
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
    #define ELMC_RC_LOG_FAIL(rc, site, ...) \\
      do { \\
        elmc_rc_record_fail((rc), __LINE__); \\
        APP_LOG(APP_LOG_LEVEL_ERROR, "ELMC RC %u at %s", (unsigned)(rc), site); \\
      } while (0)
    #else
    #define ELMC_RC_LOG_FAIL(rc, site, ...) \\
      do { \\
        elmc_rc_record_fail((rc), __LINE__); \\
        (void)(site); \\
      } while (0)
    #endif
    #else
    #define ELMC_RC_LOG_FAIL(rc, site, ...) \\
      do { \\
        elmc_rc_record_fail((rc), __LINE__); \\
        fprintf(stderr, "ELMC RC %s at %s: " __VA_ARGS__ "\\n", elmc_rc_name(rc), site); \\
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
    #define ELMC_TAKE_OR_RETURN(site, take_expr, on_fail) \\
      do { \\
        RC __take_rc = (take_expr); \\
        if (__take_rc != RC_SUCCESS) { \\
          (void)(site); \\
          on_fail; \\
        } \\
      } while (0)
    """
  end

  @spec maybe_pattern_helpers() :: String.t()
  def maybe_pattern_helpers do
    """
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
      if (v->tag == ELMC_TAG_INT) return elmc_as_int(v);
      if (v->tag == ELMC_TAG_TUPLE2 && v->payload != NULL)
        return elmc_as_int(((ElmcTuple2 *)v->payload)->first);
      return -1;
    }

    static inline bool elmc_union_tag_matches(ElmcValue *v, elmc_int_t tag) {
      return v && ((v->tag == ELMC_TAG_INT && elmc_as_int(v) == tag) ||
                   (v->tag == ELMC_TAG_TUPLE2 && v->payload != NULL &&
                    elmc_as_int(((ElmcTuple2 *)v->payload)->first) == tag));
    }

    static inline ElmcValue *elmc_union_payload(ElmcValue *v) {
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
    """
  end

  @spec release_array_lifo_declaration() :: String.t()
  def release_array_lifo_declaration do
    """
    static inline void elmc_release_array_lifo(ElmcValue **slots, size_t count) {
      size_t n = count;
      while (count-- > 0) {
        ElmcValue *value = slots[count];
        if (value) {
          elmc_release(value);
          for (size_t i = 0; i < n; i++) {
            if (slots[i] == value) {
              slots[i] = NULL;
            }
          }
        }
      }
    }
    """
  end

  @spec take_wrapper_declarations() :: String.t()
  def take_wrapper_declarations do
    """
    ElmcValue *elmc_retain(ElmcValue *value);

    static inline ElmcValue *elmc_new_int_take(elmc_int_t value) {
      ElmcValue *out = NULL;
      return elmc_new_int(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_new_bool_take(int value) {
      ElmcValue *out = NULL;
      return elmc_new_bool(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_new_order_take(elmc_int_t value) {
      ElmcValue *out = NULL;
      return elmc_new_order(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_basics_compare_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_basics_compare(&out, a, b) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_cmd0_take(elmc_int_t kind) {
      ElmcValue *out = NULL;
      return elmc_cmd0(&out, kind) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_cmd1_take(elmc_int_t kind, elmc_int_t p0) {
      ElmcValue *out = NULL;
      return elmc_cmd1(&out, kind, p0) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_cmd1_string_take(elmc_int_t kind, elmc_int_t p0, const char *text) {
      ElmcValue *out = NULL;
      return elmc_cmd1_string(&out, kind, p0, text) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_cmd2_take(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1) {
      ElmcValue *out = NULL;
      return elmc_cmd2(&out, kind, p0, p1) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_cmd3_take(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
      ElmcValue *out = NULL;
      return elmc_cmd3(&out, kind, p0, p1, p2) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_cmd4_take(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
      ElmcValue *out = NULL;
      return elmc_cmd4(&out, kind, p0, p1, p2, p3) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_cmd5_take(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
      ElmcValue *out = NULL;
      return elmc_cmd5(&out, kind, p0, p1, p2, p3, p4) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_sub0_take(elmc_int_t mask) {
      ElmcValue *out = NULL;
      return elmc_sub0(&out, mask) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_sub1_take(elmc_int_t mask, elmc_int_t p0) {
      ElmcValue *out = NULL;
      return elmc_sub1(&out, mask, p0) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_sub2_take(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1) {
      ElmcValue *out = NULL;
      return elmc_sub2(&out, mask, p0, p1) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_sub3_take(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
      ElmcValue *out = NULL;
      return elmc_sub3(&out, mask, p0, p1, p2) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_sub4_take(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
      ElmcValue *out = NULL;
      return elmc_sub4(&out, mask, p0, p1, p2, p3) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_sub5_take(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
      ElmcValue *out = NULL;
      return elmc_sub5(&out, mask, p0, p1, p2, p3, p4) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_new_string_take(const char *value) {
      ElmcValue *out = NULL;
      return elmc_new_string(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_new_string_len_take(const char *value, size_t len) {
      ElmcValue *out = NULL;
      return elmc_new_string_len(&out, value, len) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_new_float_take(double value) {
      ElmcValue *out = NULL;
      return elmc_new_float(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_list_from_int_array_take(const elmc_int_t *items, int count) {
      ElmcValue *out = NULL;
      return elmc_list_from_int_array(&out, items, count) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_list_from_float_array_take(const double *items, int count) {
      ElmcValue *out = NULL;
      return elmc_list_from_float_array(&out, items, count) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_list_from_record_array_take(ElmcValue **items, int count) {
      ElmcValue *out = NULL;
      return elmc_list_from_record_array(&out, items, count) == RC_SUCCESS ? out : elmc_int_zero();
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

    static inline ElmcValue *elmc_tuple2_ints_take_value(elmc_int_t first, elmc_int_t second) {
      ElmcValue *out = NULL;
      return elmc_tuple2_ints(&out, first, second) == RC_SUCCESS ? out : elmc_int_zero();
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
      return elmc_maybe_just_own(&out, value) == RC_SUCCESS ? out : elmc_int_zero();
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

    static inline ElmcValue *elmc_int_list_head_boxed_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_int_list_head_boxed(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_int_list_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_int_list_tail(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_float_list_head_boxed_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_float_list_head_boxed(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_float_list_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_float_list_tail(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_record_seq_head_boxed_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_record_seq_head_boxed(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_record_seq_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_record_seq_tail(&out, list) == RC_SUCCESS ? out : elmc_list_nil();
    }

    static inline ElmcValue *elmc_int_spine_head_boxed_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_int_spine_head_boxed(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_int_spine_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_int_spine_tail(&out, list) == RC_SUCCESS ? out : elmc_int_zero();
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

    static inline ElmcValue *elmc_list_concat_map_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_concat_map(&out, f, list) == RC_SUCCESS ? out : elmc_int_zero();
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

    static inline ElmcValue *elmc_list_map4_take(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d) {
      ElmcValue *out = NULL;
      return elmc_list_map4(&out, f, a, b, c, d) == RC_SUCCESS ? out : elmc_int_zero();
    }

    static inline ElmcValue *elmc_list_map5_take(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e) {
      ElmcValue *out = NULL;
      return elmc_list_map5(&out, f, a, b, c, d, e) == RC_SUCCESS ? out : elmc_int_zero();
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
      if (elmc_result_map(&out, f, result) != RC_SUCCESS) return elmc_int_zero();
      return (out == result) ? elmc_retain(out) : out;
    }

    static inline ElmcValue *elmc_result_map_error_take(ElmcValue *f, ElmcValue *result) {
      ElmcValue *out = NULL;
      if (elmc_result_map_error(&out, f, result) != RC_SUCCESS) return elmc_int_zero();
      return (out == result) ? elmc_retain(out) : out;
    }

    static inline ElmcValue *elmc_result_and_then_take(ElmcValue *f, ElmcValue *result) {
      ElmcValue *out = NULL;
      if (elmc_result_and_then(&out, f, result) != RC_SUCCESS) return elmc_int_zero();
      return (out == result) ? elmc_retain(out) : out;
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
    """
  end

  @spec closure_new_take_wrapper() :: String.t()
  def closure_new_take_wrapper do
    """
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
    """
  end

  @spec fail_stash_source_impl() :: String.t()
  def fail_stash_source_impl do
    """
    volatile RC elmc_last_fail_rc = RC_SUCCESS;
    volatile uint16_t elmc_last_fail_line = 0;
    """
    |> String.trim()
  end

  @spec source_impl() :: String.t()
  def source_impl do
    """
    #{fail_stash_source_impl()}

    #ifndef ELMC_PEBBLE_PLATFORM
    #{RcCodes.name_table_source()}
    #endif
    """
    |> String.trim()
  end
end
