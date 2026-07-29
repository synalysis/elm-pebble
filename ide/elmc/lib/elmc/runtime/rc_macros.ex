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

  @spec rc_alloc_expr_macros() :: String.t()
  def rc_alloc_expr_macros do
    """
    /* GCC statement-expression helpers for inline boxed alloc in arg lists (outside CATCH). */
    #define ELMC_RC_INT_BOX(value) \\
      ({ ElmcValue *__elmc_rc_box = NULL; \\
         elmc_new_int(&__elmc_rc_box, (value)) == RC_SUCCESS ? __elmc_rc_box : NULL; })

    #define ELMC_RC_BOOL_BOX(value) \\
      ({ ElmcValue *__elmc_rc_box = NULL; \\
         elmc_new_bool(&__elmc_rc_box, (value)) == RC_SUCCESS ? __elmc_rc_box : NULL; })

    #define ELMC_RC_TUPLE2_BOX(left, right) \\
      ({ ElmcValue *__elmc_rc_box = NULL; \\
         elmc_tuple2_take(&__elmc_rc_box, (left), (right)) == RC_SUCCESS ? __elmc_rc_box : NULL; })

    #define ELMC_RC_TUPLE2_INTS_BOX(first, second) \\
      ({ ElmcValue *__elmc_rc_box = NULL; \\
         elmc_tuple2_ints(&__elmc_rc_box, (first), (second)) == RC_SUCCESS ? __elmc_rc_box : NULL; })

    #define ELMC_RC_STRING_BOX(value) \\
      ({ ElmcValue *__elmc_rc_box = NULL; \\
         elmc_new_string(&__elmc_rc_box, (value)) == RC_SUCCESS ? __elmc_rc_box : NULL; })

    #define ELMC_RC_STRING_LEN_BOX(value, len) \\
      ({ ElmcValue *__elmc_rc_box = NULL; \\
         elmc_new_string_len(&__elmc_rc_box, (value), (len)) == RC_SUCCESS ? __elmc_rc_box : NULL; })
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
