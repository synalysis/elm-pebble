defmodule Elmc.Runtime.FloatList do
  @moduledoc false

  @spec header_types() :: String.t()
  def header_types do
    """
    #ifndef ELMC_FLOAT_LIST_CELL_SCALAR
    #define ELMC_FLOAT_LIST_CELL_SCALAR ((elmc_int_t)0x1EC014)
    #endif

    typedef struct ElmcFloatListPayload {
      double *values;
      int length;
      unsigned char owns_buffer;
    } ElmcFloatListPayload;

    typedef struct ElmcFloatListCell {
      ElmcValue value;
      ElmcFloatListPayload data;
    } ElmcFloatListCell;
    """
  end

  @spec implementation() :: String.t()
  def implementation do
    """
    static ElmcFloatListPayload *elmc_float_list_payload(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_FLOAT_LIST || !list->payload) return NULL;
      return (ElmcFloatListPayload *)list->payload;
    }

    static int elmc_float_list_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_FLOAT_LIST || value->scalar != ELMC_FLOAT_LIST_CELL_SCALAR) return 0;
      ElmcFloatListCell *cell = (ElmcFloatListCell *)value;
      if (value->payload != &cell->data) return 0;
      if (cell->data.owns_buffer && cell->data.values) elmc_free(cell->data.values);
      elmc_free(cell);
      return 1;
    }

    int elmc_float_list_is_empty(ElmcValue *list) {
      ElmcFloatListPayload *payload = elmc_float_list_payload(list);
      return !payload || payload->length <= 0;
    }

    static RC elmc_float_list_alloc_copy(ElmcValue **out, const double *items, int count) {
      RC rc = RC_SUCCESS;
      ElmcFloatListCell *cell = NULL;
      CATCH_BEGIN
        if (!items || count <= 0) {
          *out = elmc_list_nil();
        } else {
          cell = (ElmcFloatListCell *)elmc_malloc(sizeof(ElmcFloatListCell), __func__);
          if (!cell) {
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          cell->data.values = (double *)elmc_malloc((size_t)count * sizeof(double), __func__);
          if (!cell->data.values) {
            elmc_free(cell);
            cell = NULL;
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          memcpy(cell->data.values, items, (size_t)count * sizeof(double));
          cell->data.length = count;
          cell->data.owns_buffer = 1;
          cell->value.rc = 1;
          cell->value.tag = ELMC_TAG_FLOAT_LIST;
          cell->value.payload = &cell->data;
          cell->value.scalar = ELMC_FLOAT_LIST_CELL_SCALAR;
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

    RC elmc_list_from_float_array(ElmcValue **out, const double *items, int count) {
      return elmc_float_list_alloc_copy(out, items, count);
    }

    static RC elmc_float_list_drop(ElmcValue **out, int count, ElmcValue *list) {
      ElmcFloatListPayload *payload = elmc_float_list_payload(list);
      if (!payload || count <= 0) {
        *out = elmc_retain(list);
        return RC_SUCCESS;
      }
      if (count >= payload->length) {
        *out = elmc_list_nil();
        return RC_SUCCESS;
      }
      return elmc_float_list_alloc_copy(out, payload->values + count, payload->length - count);
    }

    RC elmc_float_list_head_boxed(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        ElmcFloatListPayload *payload = elmc_float_list_payload(list);
        if (!payload || payload->length <= 0) {
          *out = elmc_int_zero();
        } else {
          rc = elmc_new_float(out, payload->values[0]);
          CHECK_RC(rc);
        }
      CATCH_END;
      return rc;
    }

    RC elmc_float_list_tail(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      CATCH_BEGIN
        rc = elmc_float_list_drop(out, 1, list);
        CHECK_RC(rc);
      CATCH_END;
      return rc;
    }
    """
  end
end
