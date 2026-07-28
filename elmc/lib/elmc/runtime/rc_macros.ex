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
    """
  end

  @spec release_array_lifo_declaration() :: String.t()
  def release_array_lifo_declaration do
    """
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
    """
  end

  @spec take_wrapper_declarations() :: String.t()
  def take_wrapper_declarations do
    """
    ElmcValue *elmc_retain(ElmcValue *value);

    static inline ElmcValue *elmc_new_int_take(elmc_int_t value) {
      ElmcValue *out = NULL;
      return elmc_new_int(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_new_bool_take(int value) {
      ElmcValue *out = NULL;
      return elmc_new_bool(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_new_order_take(elmc_int_t value) {
      ElmcValue *out = NULL;
      return elmc_new_order(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_compare_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_basics_compare(&out, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_cmd0_take(elmc_int_t kind) {
      ElmcValue *out = NULL;
      return elmc_cmd0(&out, kind) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_cmd1_take(elmc_int_t kind, elmc_int_t p0) {
      ElmcValue *out = NULL;
      return elmc_cmd1(&out, kind, p0) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_cmd1_string_take(elmc_int_t kind, elmc_int_t p0, const char *text) {
      ElmcValue *out = NULL;
      return elmc_cmd1_string(&out, kind, p0, text) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_cmd2_take(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1) {
      ElmcValue *out = NULL;
      return elmc_cmd2(&out, kind, p0, p1) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_cmd3_take(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
      ElmcValue *out = NULL;
      return elmc_cmd3(&out, kind, p0, p1, p2) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_cmd4_take(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
      ElmcValue *out = NULL;
      return elmc_cmd4(&out, kind, p0, p1, p2, p3) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_cmd5_take(elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
      ElmcValue *out = NULL;
      return elmc_cmd5(&out, kind, p0, p1, p2, p3, p4) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_sub0_take(elmc_int_t mask) {
      ElmcValue *out = NULL;
      return elmc_sub0(&out, mask) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_sub1_take(elmc_int_t mask, elmc_int_t p0) {
      ElmcValue *out = NULL;
      return elmc_sub1(&out, mask, p0) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_sub2_take(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1) {
      ElmcValue *out = NULL;
      return elmc_sub2(&out, mask, p0, p1) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_sub3_take(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2) {
      ElmcValue *out = NULL;
      return elmc_sub3(&out, mask, p0, p1, p2) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_sub4_take(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3) {
      ElmcValue *out = NULL;
      return elmc_sub4(&out, mask, p0, p1, p2, p3) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_sub5_take(elmc_int_t mask, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2, elmc_int_t p3, elmc_int_t p4) {
      ElmcValue *out = NULL;
      return elmc_sub5(&out, mask, p0, p1, p2, p3, p4) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_new_string_take(const char *value) {
      ElmcValue *out = NULL;
      return elmc_new_string(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_new_string_len_take(const char *value, size_t len) {
      ElmcValue *out = NULL;
      return elmc_new_string_len(&out, value, len) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_new_float_take(double value) {
      ElmcValue *out = NULL;
      return elmc_new_float(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_from_int_array_take(const elmc_int_t *items, int count) {
      ElmcValue *out = NULL;
      return elmc_list_from_int_array(&out, items, count) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_from_float_array_take(const double *items, int count) {
      ElmcValue *out = NULL;
      return elmc_list_from_float_array(&out, items, count) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_from_record_array_take(ElmcValue **items, int count) {
      ElmcValue *out = NULL;
      return elmc_list_from_record_array(&out, items, count) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_from_values_take_value(ElmcValue **items, int count) {
      ElmcValue *out = NULL;
      return elmc_list_from_values_take(&out, items, count) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_from_tuple2_int_array_take(const elmc_int_t items[][2], int count) {
      ElmcValue *out = NULL;
      return elmc_list_from_tuple2_int_array(&out, items, count) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_tuple2_take_value(ElmcValue *first, ElmcValue *second) {
      ElmcValue *out = NULL;
      return elmc_tuple2_take(&out, first, second) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_tuple2_ints_take_value(elmc_int_t first, elmc_int_t second) {
      ElmcValue *out = NULL;
      return elmc_tuple2_ints(&out, first, second) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_record_new_take_value(
        int field_count, const char **field_names, ElmcValue **field_values) {
      ElmcValue *out = NULL;
      return elmc_record_new_take(&out, field_count, field_names, field_values) == RC_SUCCESS
          ? out
          : NULL;
    }

    static inline ElmcValue *elmc_record_new_static_take_value(
        int field_count, const char * const *field_names, ElmcValue **field_values) {
      ElmcValue *out = NULL;
      return elmc_record_new_static_take(&out, field_count, field_names, field_values) ==
                 RC_SUCCESS
          ? out
          : NULL;
    }

    static inline ElmcValue *elmc_record_new_values_take_value(
        int field_count, ElmcValue **field_values) {
      ElmcValue *out = NULL;
      return elmc_record_new_values_take(&out, field_count, field_values) == RC_SUCCESS
          ? out
          : NULL;
    }

    static inline ElmcValue *elmc_record_new_values_ints_take(
        int field_count, const elmc_int_t *field_values) {
      ElmcValue *out = NULL;
      return elmc_record_new_values_ints(&out, field_count, field_values) == RC_SUCCESS
          ? out
          : NULL;
    }

    static inline ElmcValue *elmc_maybe_just_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_maybe_just_own(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_result_ok_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_result_ok(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_result_err_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_result_err(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_reverse_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_reverse(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_copy_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_copy(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_int_list_head_boxed_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_int_list_head_boxed(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_head_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_head(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_tail(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_length_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_length(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_replace_nth_int_take(
        ElmcValue *list, elmc_int_t index, elmc_int_t value) {
      ElmcValue *out = NULL;
      return elmc_list_replace_nth_int(&out, list, index, value) == RC_SUCCESS ? out
                                                                                : NULL;
    }

    static inline ElmcValue *elmc_string_to_int_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_to_int(&out, s) == RC_SUCCESS ? out : elmc_maybe_nothing();
    }

    static inline ElmcValue *elmc_string_to_float_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_to_float(&out, s) == RC_SUCCESS ? out : elmc_maybe_nothing();
    }

    static inline ElmcValue *elmc_string_length_val_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_length_val(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_mod_by_take(ElmcValue *base, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_basics_mod_by(&out, base, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_remainder_by_take(ElmcValue *base, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_basics_remainder_by(&out, base, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_pow_take(ElmcValue *base, ElmcValue *exponent) {
      ElmcValue *out = NULL;
      return elmc_basics_pow(&out, base, exponent) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_negate_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_negate(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_abs_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_abs(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_round_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_round(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_floor_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_floor(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_ceiling_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_ceiling(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_truncate_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_truncate(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_bitwise_and_take(ElmcValue *left, ElmcValue *right) {
      ElmcValue *out = NULL;
      return elmc_bitwise_and(&out, left, right) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_bitwise_or_take(ElmcValue *left, ElmcValue *right) {
      ElmcValue *out = NULL;
      return elmc_bitwise_or(&out, left, right) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_bitwise_xor_take(ElmcValue *left, ElmcValue *right) {
      ElmcValue *out = NULL;
      return elmc_bitwise_xor(&out, left, right) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_bitwise_complement_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_bitwise_complement(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_bitwise_shift_left_by_take(ElmcValue *bits, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_bitwise_shift_left_by(&out, bits, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_bitwise_shift_right_by_take(ElmcValue *bits, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_bitwise_shift_right_by(&out, bits, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_bitwise_shift_right_zf_by_take(ElmcValue *bits, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_bitwise_shift_right_zf_by(&out, bits, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_char_to_code_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_char_to_code(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_size_take(ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_size(&out, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_size_take(ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_size(&out, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_array_length_take(ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_length(&out, array) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_time_now_millis_take(void) {
      ElmcValue *out = NULL;
      return elmc_time_now_millis(&out) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_time_zone_offset_minutes_take(void) {
      ElmcValue *out = NULL;
      return elmc_time_zone_offset_minutes(&out) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_result_inc_or_zero_take(ElmcValue *result) {
      ElmcValue *out = NULL;
      return elmc_result_inc_or_zero(&out, result) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_new_char_take(elmc_int_t value) {
      ElmcValue *out = NULL;
      return elmc_new_char(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_char_from_code_take(ElmcValue *code) {
      ElmcValue *out = NULL;
      return elmc_char_from_code(&out, code) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_char_from_code_int_take(elmc_int_t code) {
      ElmcValue *out = NULL;
      return elmc_char_from_code_int(&out, code) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_char_to_upper_take(ElmcValue *ch) {
      ElmcValue *out = NULL;
      return elmc_char_to_upper(&out, ch) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_char_to_lower_take(ElmcValue *ch) {
      ElmcValue *out = NULL;
      return elmc_char_to_lower(&out, ch) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_debug_to_string_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_debug_to_string(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_debug_set_to_string_take(ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_debug_set_to_string(&out, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_debug_todo_take(ElmcValue *label) {
      ElmcValue *out = NULL;
      return elmc_debug_todo(&out, label) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_to_float_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_to_float(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_sin_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_sin(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_cos_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_cos(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_tan_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_tan(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_sqrt_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_sqrt(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_log_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_log(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_log_base_take(ElmcValue *base, ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_log_base(&out, base, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_atan_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_atan(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_atan2_take(ElmcValue *y, ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_atan2(&out, y, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_asin_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_asin(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_acos_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_acos(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_degrees_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_degrees(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_radians_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_radians(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_turns_take(ElmcValue *x) {
      ElmcValue *out = NULL;
      return elmc_basics_turns(&out, x) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_from_polar_take(ElmcValue *polar) {
      ElmcValue *out = NULL;
      return elmc_basics_from_polar(&out, polar) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_basics_to_polar_take(ElmcValue *point) {
      ElmcValue *out = NULL;
      return elmc_basics_to_polar(&out, point) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_from_int_take(ElmcValue *n) {
      ElmcValue *out = NULL;
      return elmc_string_from_int(&out, n) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_left_take(ElmcValue *n, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_left(&out, n, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_right_take(ElmcValue *n, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_right(&out, n, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_drop_left_take(ElmcValue *n, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_drop_left(&out, n, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_drop_right_take(ElmcValue *n, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_drop_right(&out, n, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_cons_take(ElmcValue *ch, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_cons(&out, ch, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_words_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_words(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_lines_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_lines(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_pad_take(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_pad(&out, n, ch, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_array_set_take(ElmcValue *index, ElmcValue *value, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_set(&out, index, value, array) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_array_push_take(ElmcValue *value, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_push(&out, value, array) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_result_to_maybe_take(ElmcValue *result) {
      ElmcValue *out = NULL;
      return elmc_result_to_maybe(&out, result) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_result_from_maybe_take(ElmcValue *err, ElmcValue *maybe) {
      ElmcValue *out = NULL;
      return elmc_result_from_maybe(&out, err, maybe) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_basics_max_take(ElmcValue *left, ElmcValue *right) {
      ElmcValue *out = NULL;
      return elmc_basics_max(&out, left, right) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_basics_min_take(ElmcValue *left, ElmcValue *right) {
      ElmcValue *out = NULL;
      return elmc_basics_min(&out, left, right) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_basics_clamp_take(ElmcValue *low, ElmcValue *high, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_basics_clamp(&out, low, high, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_debug_log_take(ElmcValue *label, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_debug_log(&out, label, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_append_take(ElmcValue *left, ElmcValue *right) {
      ElmcValue *out = NULL;
      return elmc_append(&out, left, right) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_get_take(ElmcValue *index, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_get(&out, index, array) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_cmd_backlight_from_maybe_take(ElmcValue *maybe_mode) {
      ElmcValue *out = NULL;
      return elmc_cmd_backlight_from_maybe(&out, maybe_mode) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_dict_singleton_take(ElmcValue *key, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_dict_singleton(&out, key, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_set_singleton_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_set_singleton(&out, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_set_to_list_take(ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_to_list(&out, set) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_initialize_take(ElmcValue *n, ElmcValue *f) {
      ElmcValue *out = NULL;
      return elmc_array_initialize(&out, n, f) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_repeat_take(ElmcValue *n, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_array_repeat(&out, n, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_to_list_take(ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_to_list(&out, array) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_to_indexed_list_take(ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_to_indexed_list(&out, array) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_map_take(ElmcValue *f, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_map(&out, f, array) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_indexed_map_take(ElmcValue *f, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_indexed_map(&out, f, array) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_foldl(&out, f, acc, array) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_foldr(&out, f, acc, array) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_filter_take(ElmcValue *f, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_filter(&out, f, array) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_append_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_array_append(&out, a, b) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_array_slice_take(ElmcValue *start, ElmcValue *end_idx, ElmcValue *array) {
      ElmcValue *out = NULL;
      return elmc_array_slice(&out, start, end_idx, array) == RC_SUCCESS ? out : NULL;
    }


    static inline ElmcValue *elmc_dict_to_list_take(ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_to_list(&out, dict) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_string_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_json_encode_string(&out, s) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_int_take(ElmcValue *n) {
      ElmcValue *out = NULL;
      return elmc_json_encode_int(&out, n) == RC_SUCCESS ? out : NULL;
    }
    #if ELMC_JSON_FLOAT_NUMBERS
    static inline ElmcValue *elmc_json_encode_float_take(ElmcValue *f) {
      ElmcValue *out = NULL;
      return elmc_json_encode_float(&out, f) == RC_SUCCESS ? out : NULL;
    }
    #endif
    static inline ElmcValue *elmc_json_encode_bool_take(ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_json_encode_bool(&out, b) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_null_take(void) {
      ElmcValue *out = NULL;
      return elmc_json_encode_null(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_list_take(ElmcValue *f, ElmcValue *items) {
      ElmcValue *out = NULL;
      return elmc_json_encode_list(&out, f, items) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_array_take(ElmcValue *f, ElmcValue *items) {
      ElmcValue *out = NULL;
      return elmc_json_encode_array(&out, f, items) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_set_take(ElmcValue *f, ElmcValue *items) {
      ElmcValue *out = NULL;
      return elmc_json_encode_set(&out, f, items) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_object_take(ElmcValue *pairs) {
      ElmcValue *out = NULL;
      return elmc_json_encode_object(&out, pairs) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_add_field_take(ElmcValue *key, ElmcValue *value, ElmcValue *obj) {
      ElmcValue *out = NULL;
      return elmc_json_encode_add_field(&out, key, value, obj) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_add_entry_take(ElmcValue *func, ElmcValue *value, ElmcValue *arr) {
      ElmcValue *out = NULL;
      return elmc_json_encode_add_entry(&out, func, value, arr) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_dict_take(ElmcValue *key_fn, ElmcValue *val_fn, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_json_encode_dict(&out, key_fn, val_fn, dict) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_encode_encode_take(ElmcValue *indent, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_json_encode_encode(&out, indent, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_task_succeed_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_task_succeed(&out, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_task_fail_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_task_fail(&out, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_task_map_take(ElmcValue *f, ElmcValue *task) {
      ElmcValue *out = NULL;
      return elmc_task_map(&out, f, task) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_task_map2_take(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_task_map2(&out, f, a, b) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_task_and_then_take(ElmcValue *f, ElmcValue *task) {
      ElmcValue *out = NULL;
      return elmc_task_and_then(&out, f, task) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_task_command_take(ElmcValue *task) {
      ElmcValue *out = NULL;
      return elmc_task_command(&out, task) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_process_spawn_take(ElmcValue *task) {
      ElmcValue *out = NULL;
      return elmc_process_spawn(&out, task) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_process_sleep_take(ElmcValue *milliseconds) {
      ElmcValue *out = NULL;
      return elmc_process_sleep(&out, milliseconds) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_process_kill_take(ElmcValue *pid) {
      ElmcValue *out = NULL;
      return elmc_process_kill(&out, pid) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_json_decode_value_take(ElmcValue *decoder, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_json_decode_value(&out, decoder, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_string_take(ElmcValue *decoder, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_json_decode_string(&out, decoder, s) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_string_decoder_take(void) {
      ElmcValue *out = NULL;
      return elmc_json_decode_string_decoder(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_int_decoder_take(void) {
      ElmcValue *out = NULL;
      return elmc_json_decode_int_decoder(&out) == RC_SUCCESS ? out : NULL;
    }
    #if ELMC_JSON_FLOAT_NUMBERS
    static inline ElmcValue *elmc_json_decode_float_decoder_take(void) {
      ElmcValue *out = NULL;
      return elmc_json_decode_float_decoder(&out) == RC_SUCCESS ? out : NULL;
    }
    #endif
    static inline ElmcValue *elmc_json_decode_bool_decoder_take(void) {
      ElmcValue *out = NULL;
      return elmc_json_decode_bool_decoder(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_null_take(ElmcValue *default_val) {
      ElmcValue *out = NULL;
      return elmc_json_decode_null(&out, default_val) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_nullable_take(ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_nullable(&out, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_list_take(ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_list(&out, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_array_take(ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_array(&out, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_field_take(ElmcValue *name, ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_field(&out, name, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_at_take(ElmcValue *path, ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_at(&out, path, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_index_take(ElmcValue *idx, ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_index(&out, idx, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_map_take(ElmcValue *f, ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_map(&out, f, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_map2_take(ElmcValue *f, ElmcValue *d1, ElmcValue *d2) {
      ElmcValue *out = NULL;
      return elmc_json_decode_map2(&out, f, d1, d2) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_map3_take(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3) {
      ElmcValue *out = NULL;
      return elmc_json_decode_map3(&out, f, d1, d2, d3) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_map4_take(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4) {
      ElmcValue *out = NULL;
      return elmc_json_decode_map4(&out, f, d1, d2, d3, d4) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_map5_take(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5) {
      ElmcValue *out = NULL;
      return elmc_json_decode_map5(&out, f, d1, d2, d3, d4, d5) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_map6_take(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6) {
      ElmcValue *out = NULL;
      return elmc_json_decode_map6(&out, f, d1, d2, d3, d4, d5, d6) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_map7_take(ElmcValue *f, ElmcValue *d1, ElmcValue *d2, ElmcValue *d3, ElmcValue *d4, ElmcValue *d5, ElmcValue *d6, ElmcValue *d7) {
      ElmcValue *out = NULL;
      return elmc_json_decode_map7(&out, f, d1, d2, d3, d4, d5, d6, d7) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_succeed_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_json_decode_succeed(&out, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_fail_take(ElmcValue *msg) {
      ElmcValue *out = NULL;
      return elmc_json_decode_fail(&out, msg) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_and_then_take(ElmcValue *f, ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_and_then(&out, f, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_one_of_take(ElmcValue *decoders) {
      ElmcValue *out = NULL;
      return elmc_json_decode_one_of(&out, decoders) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_maybe_take(ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_maybe(&out, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_lazy_take(ElmcValue *thunk) {
      ElmcValue *out = NULL;
      return elmc_json_decode_lazy(&out, thunk) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_value_decoder_take(void) {
      ElmcValue *out = NULL;
      return elmc_json_decode_value_decoder(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_error_to_string_take(ElmcValue *err) {
      ElmcValue *out = NULL;
      return elmc_json_decode_error_to_string(&out, err) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_key_value_pairs_take(ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_key_value_pairs(&out, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_json_decode_dict_take(ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_json_decode_dict(&out, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_task_force_take(ElmcValue *task) {
      ElmcValue *out = NULL;
      return elmc_task_force(&out, task) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_cmd_batch_take(ElmcValue *commands) {
      ElmcValue *out = NULL;
      return elmc_cmd_batch(&out, commands) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_cmd_map_take(ElmcValue *f, ElmcValue *cmd) {
      ElmcValue *out = NULL;
      return elmc_cmd_map(&out, f, cmd) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_sub_batch_take(ElmcValue *subs) {
      ElmcValue *out = NULL;
      return elmc_sub_batch(&out, subs) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_sub_map_take(ElmcValue *f, ElmcValue *sub) {
      ElmcValue *out = NULL;
      return elmc_sub_map(&out, f, sub) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_port_outgoing_take(ElmcValue *port_name, ElmcValue *payload) {
      ElmcValue *out = NULL;
      return elmc_port_outgoing(&out, port_name, payload) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_port_incoming_sub_take(ElmcValue *port_name, ElmcValue *callback) {
      ElmcValue *out = NULL;
      return elmc_port_incoming_sub(&out, port_name, callback) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_build_constructor_payload_take(ElmcValue **values, int count) {
      ElmcValue *out = NULL;
      return elmc_build_constructor_payload(&out, values, count) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_record_update_take(
        ElmcValue *record, const char *field_name, ElmcValue *new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update(&out, record, field_name, new_value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_take(
        ElmcValue *record, int index, ElmcValue *new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index(&out, record, index, new_value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_cow_take(
        ElmcValue *record, int index, ElmcValue *new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index_cow(&out, record, index, new_value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_cow_drop_take(
        ElmcValue *record, int index, ElmcValue *new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index_cow_drop(&out, record, index, new_value) == RC_SUCCESS
                 ? out
                 : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_int_cow_take(
        ElmcValue *record, int index, elmc_int_t new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index_int_cow(&out, record, index, new_value) == RC_SUCCESS
                 ? out
                 : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_int_cow_drop_take(
        ElmcValue *record, int index, elmc_int_t new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index_int_cow_drop(&out, record, index, new_value) == RC_SUCCESS
                 ? out
                 : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_bool_cow_take(
        ElmcValue *record, int index, bool new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index_bool_cow(&out, record, index, new_value) == RC_SUCCESS
                 ? out
                 : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_bool_cow_drop_take(
        ElmcValue *record, int index, bool new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index_bool_cow_drop(&out, record, index, new_value) == RC_SUCCESS
                 ? out
                 : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_float_cow_take(
        ElmcValue *record, int index, double new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index_float_cow(&out, record, index, new_value) == RC_SUCCESS
                 ? out
                 : NULL;
    }
    static inline ElmcValue *elmc_record_update_index_float_cow_drop_take(
        ElmcValue *record, int index, double new_value) {
      ElmcValue *out = NULL;
      return elmc_record_update_index_float_cow_drop(&out, record, index, new_value) == RC_SUCCESS
                 ? out
                 : NULL;
    }


    static inline ElmcValue *elmc_string_chop_end_take(ElmcValue *str, ElmcValue *suffix) {
      ElmcValue *out = NULL;
      return elmc_string_chop_end(&out, str, suffix) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_string_chop_start_take(ElmcValue *str, ElmcValue *prefix) {
      ElmcValue *out = NULL;
      return elmc_string_chop_start(&out, str, prefix) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_string_chop_forward_slashes_take(ElmcValue *str) {
      ElmcValue *out = NULL;
      return elmc_string_chop_forward_slashes(&out, str) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_url_percent_encode_take(ElmcValue *segment) {
      ElmcValue *out = NULL;
      return elmc_url_percent_encode(&out, segment) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_url_percent_decode_take(ElmcValue *segment) {
      ElmcValue *out = NULL;
      return elmc_url_percent_decode(&out, segment) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_url_from_string_take(ElmcValue *url) {
      ElmcValue *out = NULL;
      return elmc_url_from_string(&out, url) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_http_empty_body_take(ElmcValue *req) {
      ElmcValue *out = NULL;
      return elmc_http_empty_body(&out, req) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_http_pair_take(ElmcValue *key, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_http_pair(&out, key, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_http_to_data_view_take(ElmcValue *body) {
      ElmcValue *out = NULL;
      return elmc_http_to_data_view(&out, body) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_http_expect_take(ElmcValue *to_msg, ElmcValue *decoder, ElmcValue *req) {
      ElmcValue *out = NULL;
      return elmc_http_expect(&out, to_msg, decoder, req) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_http_command_take(ElmcValue *req) {
      ElmcValue *out = NULL;
      return elmc_http_command(&out, req) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_http_cancel_take(ElmcValue *tracker) {
      ElmcValue *out = NULL;
      return elmc_http_cancel(&out, tracker) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_get_json_take(ElmcValue *url, ElmcValue *expect) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_get_json(&out, url, expect) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_get_take(ElmcValue *url, ElmcValue *expect) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_get(&out, url, expect) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_get_with_options_take(ElmcValue *url, ElmcValue *options, ElmcValue *expect) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_get_with_options(&out, url, options, expect) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_expect_json_take(ElmcValue *decoder) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_expect_json(&out, decoder) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_expect_string_take(void) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_expect_string(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_expect_whatever_take(void) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_expect_whatever(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_expect_bytes_take(void) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_expect_bytes(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_with_metadata_take(ElmcValue *expect) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_with_metadata(&out, expect) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_empty_body_take(void) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_empty_body(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_string_body_take(ElmcValue *body) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_string_body(&out, body) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_json_body_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_json_body(&out, value) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_bytes_body_take(ElmcValue *bytes) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_bytes_body(&out, bytes) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_bytes_encode_sequence_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_bytes_encode_sequence(&out, list) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_request_take(ElmcValue *req) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_request(&out, req) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_backend_task_http_post_take(ElmcValue *url, ElmcValue *body, ElmcValue *expect) {
      ElmcValue *out = NULL;
      return elmc_backend_task_http_post(&out, url, body, expect) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_file_download_task_take(ElmcValue *name, ElmcValue *mime, ElmcValue *content) {
      ElmcValue *out = NULL;
      return elmc_file_download_task(&out, name, mime, content) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_file_select_take(ElmcValue *to_msg, ElmcValue *accept) {
      ElmcValue *out = NULL;
      return elmc_file_select(&out, to_msg, accept) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_file_download_take(ElmcValue *name, ElmcValue *mime, ElmcValue *content) {
      ElmcValue *out = NULL;
      return elmc_file_download(&out, name, mime, content) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_random_generate_take(ElmcValue *to_msg, ElmcValue *generator) {
      ElmcValue *out = NULL;
      return elmc_random_generate(&out, to_msg, generator) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_regex_from_string_take(ElmcValue *pattern) {
      ElmcValue *out = NULL;
      return elmc_regex_from_string(&out, pattern) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_regex_find_take(ElmcValue *regex, ElmcValue *str) {
      ElmcValue *out = NULL;
      return elmc_regex_find(&out, regex, str) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_regex_contains_take(ElmcValue *regex, ElmcValue *str) {
      ElmcValue *out = NULL;
      return elmc_regex_contains(&out, regex, str) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_regex_replace_take(ElmcValue *regex, ElmcValue *replacement, ElmcValue *str) {
      ElmcValue *out = NULL;
      return elmc_regex_replace(&out, regex, replacement, str) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_time_here_take(void) {
      ElmcValue *out = NULL;
      return elmc_time_here(&out) == RC_SUCCESS ? out : NULL;
    }
    static inline ElmcValue *elmc_browser_get_viewport_take(void) {
      ElmcValue *out = NULL;
      return elmc_browser_get_viewport(&out) == RC_SUCCESS ? out : NULL;
    }

        static inline ElmcValue *elmc_list_nth_maybe_take(ElmcValue *list, ElmcValue *index) {
      ElmcValue *out = NULL;
      return elmc_list_nth_maybe(&out, list, index) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_nth_int_default_boxed_take(
        ElmcValue *list, ElmcValue *index, ElmcValue *default_value) {
      ElmcValue *out = NULL;
      return elmc_list_nth_int_default_boxed(&out, list, index, default_value) == RC_SUCCESS
                 ? out
                 : NULL;
    }

    static inline ElmcValue *elmc_int_list_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_int_list_tail(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_float_list_head_boxed_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_float_list_head_boxed(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_float_list_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_float_list_tail(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_record_seq_head_boxed_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_record_seq_head_boxed(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_record_seq_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_record_seq_tail(&out, list) == RC_SUCCESS ? out : elmc_list_nil();
    }

    static inline ElmcValue *elmc_int_spine_head_boxed_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_int_spine_head_boxed(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_int_spine_tail_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_int_spine_tail(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_map_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_map(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_filter_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_filter(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_foldl(&out, f, acc, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_append_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_list_append(&out, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_concat_array_take(ElmcValue * const *lists, int count) {
      ElmcValue *out = NULL;
      return elmc_list_concat_array(&out, lists, count) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_foldr(&out, f, acc, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_concat_take(ElmcValue *lists) {
      ElmcValue *out = NULL;
      return elmc_list_concat(&out, lists) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_concat_map_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_concat_map(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_indexed_map_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_indexed_map(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_filter_map_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_filter_map(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_singleton_take(ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_list_singleton(&out, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_range_take(ElmcValue *lo, ElmcValue *hi) {
      ElmcValue *out = NULL;
      return elmc_list_range(&out, lo, hi) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_repeat_take(ElmcValue *n, ElmcValue *value) {
      ElmcValue *out = NULL;
      return elmc_list_repeat(&out, n, value) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_take_take(ElmcValue *n, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_take(&out, n, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_take_int_take(elmc_int_t count, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_take_int(&out, count, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_drop_take(ElmcValue *n, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_drop(&out, n, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_drop_int_take(elmc_int_t count, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_drop_int(&out, count, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_partition_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_partition(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_unzip_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_unzip(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_intersperse_take(ElmcValue *sep, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_intersperse(&out, sep, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_map2_take(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_list_map2(&out, f, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_map3_take(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c) {
      ElmcValue *out = NULL;
      return elmc_list_map3(&out, f, a, b, c) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_map4_take(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d) {
      ElmcValue *out = NULL;
      return elmc_list_map4(&out, f, a, b, c, d) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_map5_take(ElmcValue *f, ElmcValue *a, ElmcValue *b, ElmcValue *c, ElmcValue *d, ElmcValue *e) {
      ElmcValue *out = NULL;
      return elmc_list_map5(&out, f, a, b, c, d, e) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_sum_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_sum(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_product_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_product(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_maximum_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_maximum(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_minimum_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_minimum(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_any_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_any(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_all_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_all(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_sort_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_sort(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_sort_by_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_sort_by(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_list_sort_with_take(ElmcValue *f, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_list_sort_with(&out, f, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_append_take(ElmcValue *left, ElmcValue *right) {
      ElmcValue *out = NULL;
      return elmc_string_append(&out, left, right) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_append_native_take(const char *left, const char *right) {
      ElmcValue *out = NULL;
      return elmc_string_append_native(&out, left, right) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_replace_take(ElmcValue *old_s, ElmcValue *new_s, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_replace(&out, old_s, new_s, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_reverse_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_reverse(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_repeat_take(ElmcValue *n, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_repeat(&out, n, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_from_float_take(ElmcValue *f) {
      ElmcValue *out = NULL;
      return elmc_string_from_float(&out, f) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_to_upper_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_to_upper(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_to_lower_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_to_lower(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_trim_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_trim(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_trim_left_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_trim_left(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_trim_right_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_trim_right(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_split_take(ElmcValue *sep, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_split(&out, sep, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_join_take(ElmcValue *sep, ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_string_join(&out, sep, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_slice_take(ElmcValue *start, ElmcValue *end_idx, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_slice(&out, start, end_idx, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_from_list_take(ElmcValue *list) {
      ElmcValue *out = NULL;
      return elmc_string_from_list(&out, list) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_from_char_take(ElmcValue *ch) {
      ElmcValue *out = NULL;
      return elmc_string_from_char(&out, ch) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_pad_left_take(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_pad_left(&out, n, ch, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_pad_right_take(ElmcValue *n, ElmcValue *ch, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_pad_right(&out, n, ch, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_map_take(ElmcValue *f, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_map(&out, f, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_filter_take(ElmcValue *f, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_filter(&out, f, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_foldl(&out, f, acc, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_foldr(&out, f, acc, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_any_take(ElmcValue *f, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_any(&out, f, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_all_take(ElmcValue *f, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_all(&out, f, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_indexes_take(ElmcValue *sub, ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_indexes(&out, sub, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_uncons_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_uncons(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_to_list_take(ElmcValue *s) {
      ElmcValue *out = NULL;
      return elmc_string_to_list(&out, s) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_from_list_take(ElmcValue *items) {
      ElmcValue *out = NULL;
      return elmc_dict_from_list(&out, items) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_insert_take(ElmcValue *key, ElmcValue *value, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_insert(&out, key, value, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_get_take(ElmcValue *key, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_get(&out, key, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_remove_take(ElmcValue *key, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_remove(&out, key, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_keys_take(ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_keys(&out, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_values_take(ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_values(&out, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_map_take(ElmcValue *f, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_map(&out, f, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_foldl(&out, f, acc, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_foldr(&out, f, acc, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_filter_take(ElmcValue *f, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_filter(&out, f, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_partition_take(ElmcValue *f, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_partition(&out, f, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_intersect_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_dict_intersect(&out, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_diff_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_dict_diff(&out, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_union_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_dict_union(&out, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_merge_take(ElmcValue *lf, ElmcValue *bf, ElmcValue *rf, ElmcValue *a, ElmcValue *b, ElmcValue *result) {
      ElmcValue *out = NULL;
      return elmc_dict_merge(&out, lf, bf, rf, a, b, result) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_dict_update_take(ElmcValue *key, ElmcValue *f, ElmcValue *dict) {
      ElmcValue *out = NULL;
      return elmc_dict_update(&out, key, f, dict) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_from_list_take(ElmcValue *items) {
      ElmcValue *out = NULL;
      return elmc_set_from_list(&out, items) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_insert_take(ElmcValue *value, ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_insert(&out, value, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_remove_take(ElmcValue *value, ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_remove(&out, value, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_foldl_take(ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_foldl(&out, f, acc, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_foldr_take(ElmcValue *f, ElmcValue *acc, ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_foldr(&out, f, acc, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_filter_take(ElmcValue *f, ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_filter(&out, f, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_partition_take(ElmcValue *f, ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_partition(&out, f, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_union_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_set_union(&out, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_intersect_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_set_intersect(&out, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_diff_take(ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_set_diff(&out, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_set_map_take(ElmcValue *f, ElmcValue *set) {
      ElmcValue *out = NULL;
      return elmc_set_map(&out, f, set) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_string_from_native_int_take(elmc_int_t n) {
      ElmcValue *out = NULL;
      return elmc_string_from_native_int(&out, n) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_maybe_map_take(ElmcValue *f, ElmcValue *maybe) {
      ElmcValue *out = NULL;
      return elmc_maybe_map(&out, f, maybe) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_maybe_map2_take(ElmcValue *f, ElmcValue *a, ElmcValue *b) {
      ElmcValue *out = NULL;
      return elmc_maybe_map2(&out, f, a, b) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_maybe_and_then_take(ElmcValue *f, ElmcValue *maybe) {
      ElmcValue *out = NULL;
      return elmc_maybe_and_then(&out, f, maybe) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_result_map_take(ElmcValue *f, ElmcValue *result) {
      ElmcValue *out = NULL;
      if (elmc_result_map(&out, f, result) != RC_SUCCESS) return NULL;
      return (out == result) ? elmc_retain(out) : out;
    }

    static inline ElmcValue *elmc_result_map_error_take(ElmcValue *f, ElmcValue *result) {
      ElmcValue *out = NULL;
      if (elmc_result_map_error(&out, f, result) != RC_SUCCESS) return NULL;
      return (out == result) ? elmc_retain(out) : out;
    }

    static inline ElmcValue *elmc_result_and_then_take(ElmcValue *f, ElmcValue *result) {
      ElmcValue *out = NULL;
      if (elmc_result_and_then(&out, f, result) != RC_SUCCESS) return NULL;
      return (out == result) ? elmc_retain(out) : out;
    }

    static inline ElmcValue *elmc_tuple_map_first_take(ElmcValue *f, ElmcValue *t) {
      ElmcValue *out = NULL;
      return elmc_tuple_map_first(&out, f, t) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_tuple_map_second_take(ElmcValue *f, ElmcValue *t) {
      ElmcValue *out = NULL;
      return elmc_tuple_map_second(&out, f, t) == RC_SUCCESS ? out : NULL;
    }

    static inline ElmcValue *elmc_tuple_map_both_take(ElmcValue *f, ElmcValue *g, ElmcValue *t) {
      ElmcValue *out = NULL;
      return elmc_tuple_map_both(&out, f, g, t) == RC_SUCCESS ? out : NULL;
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
          : NULL;
    }

    static inline ElmcValue *elmc_closure_new_rc_take(
        RC (*rc_fn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count),
        int arity,
        int capture_count,
        ElmcValue **captures) {
      ElmcValue *out = NULL;
      return elmc_closure_new_rc(&out, rc_fn, arity, capture_count, captures) == RC_SUCCESS
          ? out
          : NULL;
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
