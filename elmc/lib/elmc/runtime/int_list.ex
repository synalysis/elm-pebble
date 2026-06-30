defmodule Elmc.Runtime.IntList do
  @moduledoc false

  @spec header_types() :: String.t()
  def header_types do
    """
    #ifndef ELMC_INT_LIST_CELL_SCALAR
    #define ELMC_INT_LIST_CELL_SCALAR ((elmc_int_t)0x1EC013)
    #endif

    #ifndef ELMC_INT_SPINE_CELL_SCALAR
    #define ELMC_INT_SPINE_CELL_SCALAR ((elmc_int_t)0x1EC01A)
    #endif

    #ifndef ELMC_RECORD_SEQ_CELL_SCALAR
    #define ELMC_RECORD_SEQ_CELL_SCALAR ((elmc_int_t)0x1EC01B)
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
    """
  end

  @spec core_implementation() :: String.t()
  def core_implementation do
    """
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
    """
  end

  @spec spine_implementation() :: String.t()
  def spine_implementation do
    """
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
    """
  end

  @spec implementation() :: String.t()
  def implementation, do: core_implementation() <> spine_implementation()

  @spec emit_immortal_static(String.t(), String.t(), String.t(), pos_integer()) :: String.t()
  def emit_immortal_static(sym, out_var, values_str, count) do
    """
    static const elmc_int_t #{sym}_values[#{count}] = { #{values_str} };
    static const ElmcIntListPayload #{sym}_payload = { (elmc_int_t *)#{sym}_values, #{count}, 0 };
    static ElmcValue #{sym}_value = { ELMC_RC_IMMORTAL, ELMC_TAG_INT_LIST, (void *)&#{sym}_payload, ELMC_INT_LIST_CELL_SCALAR };
    #{out_var} = (ElmcValue *)&#{sym}_value;
    """
    |> String.trim_trailing()
  end

  @spec emit_immortal_static_prelude(String.t(), String.t(), pos_integer()) :: String.t()
  def emit_immortal_static_prelude(sym, values_str, count) do
    """
    static const elmc_int_t #{sym}_values[#{count}] = { #{values_str} };
    static const ElmcIntListPayload #{sym}_payload = { (elmc_int_t *)#{sym}_values, #{count}, 0 };
    static ElmcValue #{sym}_value = { ELMC_RC_IMMORTAL, ELMC_TAG_INT_LIST, (void *)&#{sym}_payload, ELMC_INT_LIST_CELL_SCALAR };
    """
    |> String.trim_trailing()
  end

  @spec emit_immortal_zeros(String.t(), String.t(), pos_integer()) :: String.t()
  def emit_immortal_zeros(sym, out_var, count) do
    values = Enum.map_join(1..count, ", ", fn _ -> "0" end)
    emit_immortal_static(sym, out_var, values, count)
  end
end
