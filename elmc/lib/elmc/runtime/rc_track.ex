defmodule Elmc.Runtime.RcTrack do
  @moduledoc false

  @spec header_declarations() :: String.t()
  def header_declarations do
    """
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
    """
  end

  @spec register_macro() :: String.t()
  def register_macro do
    """
    #if ELMC_RC_TRACK
    #define ELMC_RC_TRACK_REGISTER(value, context) \\
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
    """
  end

  @spec source_impl() :: String.t()
  def source_impl do
    """
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
                "    +rc #%u %s rc=%u alloc=%s:%d (%s)\\n",
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
      fprintf(out, "elmc rc track: %u live object(s)\\n", ELMC_RC_TRACK_COUNT);
      for (uint32_t i = 0; i < ELMC_RC_TRACK_COUNT; i++) {
        ElmcRcTrackEntry *entry = &ELMC_RC_TRACK_ENTRIES[i];
        const char *alloc_file = entry->alloc_file ? entry->alloc_file : "?";
        const char *retain_file = entry->last_retain_file ? entry->last_retain_file : "?";
        const char *release_file = entry->last_release_file ? entry->last_release_file : "?";
        fprintf(out,
                "  #%u %s rc=%u retains=%u releases=%u alloc=%s:%d (%s) last_retain=%s:%d last_release=%s:%d\\n",
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
                "elmc rc counters unbalanced: allocated=%llu released=%llu\\n",
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
    """
  end

  @spec retain_release_impl() :: String.t()
  def retain_release_impl do
    """
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
    """
  end
end
