defmodule Elmc.Runtime.RecordSeq do
  @moduledoc false

  @spec implementation() :: String.t()
  def implementation do
    """
    static ElmcRecordSeqPayload *elmc_record_seq_payload(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_RECORD_SEQ || !list->payload) return NULL;
      return (ElmcRecordSeqPayload *)list->payload;
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

    int elmc_record_seq_is_empty(ElmcValue *list) {
      ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
      return !payload || payload->length <= 0;
    }

    int elmc_record_seq_length(ElmcValue *list) {
      ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
      return payload ? payload->length : 0;
    }

    ElmcValue *elmc_record_seq_get(ElmcValue *list, elmc_int_t index) {
      ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
      if (!payload || index < 0 || index >= payload->length) return elmc_int_zero();
      return elmc_retain(payload->items[index]);
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

    RC elmc_record_seq_to_cons(ElmcValue **out, ElmcValue *list) {
      ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_list_nil();
      ElmcValue *next = NULL;
      CATCH_BEGIN
        if (!payload || payload->length <= 0) {
          *out = result;
          result = NULL;
        } else {
          for (int i = payload->length - 1; i >= 0; i--) {
            next = NULL;
            rc = elmc_list_cons(&next, payload->items[i], result);
            CHECK_RC(rc);
            elmc_release(result);
            result = next;
            next = NULL;
          }
          *out = result;
          result = NULL;
        }
      CATCH_END;
      elmc_release(next);
      elmc_release(result);
      return rc;
    }

    static RC elmc_record_seq_drop(ElmcValue **out, int count, ElmcValue *list) {
      ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
      if (!payload || count <= 0) {
        *out = elmc_retain(list);
        return RC_SUCCESS;
      }
      if (count >= payload->length) {
        *out = elmc_list_nil();
        return RC_SUCCESS;
      }
      return elmc_record_seq_alloc_copy(out, payload->items + count, payload->length - count);
    }

    RC elmc_record_seq_head_boxed(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        ElmcRecordSeqPayload *payload = elmc_record_seq_payload(list);
        if (!payload || payload->length <= 0) {
          *out = elmc_int_zero();
        } else {
          *out = elmc_retain(payload->items[0]);
        }
      CATCH_END;
      return rc;
    }

    RC elmc_record_seq_tail(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_record_seq_drop(out, 1, list);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }
    """
  end
end
