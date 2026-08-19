defmodule Elmc.Runtime.LazyMap do
  @moduledoc false

  # Deferred `List.map` over a compact source (INT_LIST). The mapper runs when
  # a consumer walks the list, so storing `List.map f xs` on the model does not
  # allocate one record per element at init.

  @spec header_types() :: String.t()
  def header_types do
    """
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
    """
  end

  @spec header_decls() :: String.t()
  def header_decls do
    """
    typedef RC (*ElmcLazyMapFn)(ElmcValue **out, ElmcValue **args, int argc, ElmcValue **captures, int capture_count);
    RC elmc_lazy_map(ElmcValue **out, ElmcValue *source, ElmcLazyMapFn mapper, ElmcValue **captures, int capture_count);
    int elmc_lazy_map_length(ElmcValue *list);
    RC elmc_lazy_map_nth(ElmcValue **out, ElmcValue *list, int index);
    RC elmc_lazy_map_to_cons(ElmcValue **out, ElmcValue *list);
    """
  end

  @spec implementation() :: String.t()
  def implementation do
    """
    static ElmcLazyMapPayload *elmc_lazy_map_payload(ElmcValue *list) {
      if (!list || list->tag != ELMC_TAG_LAZY_MAP || !list->payload) return NULL;
      return (ElmcLazyMapPayload *)list->payload;
    }

    static int elmc_lazy_map_cell_release(ElmcValue *value) {
      if (!value || value->tag != ELMC_TAG_LAZY_MAP || value->scalar != ELMC_LAZY_MAP_CELL_SCALAR) return 0;
      ElmcLazyMapCell *cell = (ElmcLazyMapCell *)value;
      if (value->payload != &cell->data) return 0;
      if (cell->data.source) elmc_release(cell->data.source);
      if (cell->data.captures) {
        for (int i = 0; i < cell->data.capture_count; i++) {
          if (cell->data.captures[i]) elmc_release(cell->data.captures[i]);
        }
        elmc_free(cell->data.captures);
      }
      elmc_free(cell);
      return 1;
    }

    RC elmc_lazy_map(ElmcValue **out, ElmcValue *source, ElmcLazyMapFn mapper, ElmcValue **captures, int capture_count) {
      RC rc = RC_SUCCESS;
      ElmcLazyMapCell *cell = NULL;
      CATCH_BEGIN
        if (!source || !mapper) {
          rc = RC_ERR_INVALID_ARG;
          CHECK_RC(rc);
        }
        cell = (ElmcLazyMapCell *)elmc_malloc(sizeof(ElmcLazyMapCell), __func__);
        if (!cell) {
          rc = RC_ERR_OUT_OF_MEMORY;
          CHECK_RC(rc);
        }
        cell->data.source = elmc_retain(source);
        cell->data.mapper = mapper;
        cell->data.capture_count = capture_count > 0 ? capture_count : 0;
        cell->data.captures = NULL;
        if (cell->data.capture_count > 0) {
          cell->data.captures = (ElmcValue **)elmc_malloc((size_t)cell->data.capture_count * sizeof(ElmcValue *), __func__);
          if (!cell->data.captures) {
            elmc_release(cell->data.source);
            elmc_free(cell);
            cell = NULL;
            rc = RC_ERR_OUT_OF_MEMORY;
            CHECK_RC(rc);
          }
          for (int i = 0; i < cell->data.capture_count; i++) {
            cell->data.captures[i] = captures && captures[i] ? elmc_retain(captures[i]) : NULL;
          }
        }
        cell->value.rc = 1;
        cell->value.tag = ELMC_TAG_LAZY_MAP;
        cell->value.payload = &cell->data;
        cell->value.scalar = ELMC_LAZY_MAP_CELL_SCALAR;
        ELMC_ALLOCATED += 1;
        ELMC_RC_TRACK_REGISTER(&cell->value, __func__);
        *out = &cell->value;
        cell = NULL;
      CATCH_END
      if (cell) {
        if (cell->data.source) elmc_release(cell->data.source);
        if (cell->data.captures) {
          for (int i = 0; i < cell->data.capture_count; i++) {
            if (cell->data.captures[i]) elmc_release(cell->data.captures[i]);
          }
          elmc_free(cell->data.captures);
        }
        elmc_free(cell);
      }
      return rc;
    }

    int elmc_lazy_map_length(ElmcValue *list) {
      ElmcLazyMapPayload *payload = elmc_lazy_map_payload(list);
      if (!payload) return 0;
      return (int)elmc_list_length_native(payload->source);
    }

    RC elmc_lazy_map_nth(ElmcValue **out, ElmcValue *list, int index) {
      ElmcLazyMapPayload *payload = elmc_lazy_map_payload(list);
      RC rc = RC_SUCCESS;
      ElmcValue *arg = NULL;
      CATCH_BEGIN
        if (!payload || !payload->mapper || index < 0) {
          rc = RC_ERR_INVALID_ARG;
          CHECK_RC(rc);
        }
        if (payload->source && payload->source->tag == ELMC_TAG_INT_LIST) {
          ElmcIntListPayload *src = (ElmcIntListPayload *)payload->source->payload;
          if (!src || index >= src->length) {
            rc = RC_ERR_INVALID_ARG;
            CHECK_RC(rc);
          }
          rc = elmc_new_int(&arg, src->values[index]);
          CHECK_RC(rc);
        } else {
          rc = RC_ERR_UNSUPPORTED;
          CHECK_RC(rc);
        }
        ElmcValue *args[1] = { arg };
        ElmcLazyMapFn mapper = (ElmcLazyMapFn)payload->mapper;
        rc = mapper(out, args, 1, payload->captures, payload->capture_count);
        CHECK_RC(rc);
      CATCH_END
      elmc_release(arg);
      return rc;
    }

    RC elmc_lazy_map_to_cons(ElmcValue **out, ElmcValue *list) {
      RC rc = RC_SUCCESS;
      ElmcValue *result = elmc_list_nil();
      ElmcValue *item = NULL;
      ElmcValue *next = NULL;
      int n = elmc_lazy_map_length(list);
      CATCH_BEGIN
        for (int i = n - 1; i >= 0; i--) {
          item = NULL;
          rc = elmc_lazy_map_nth(&item, list, i);
          CHECK_RC(rc);
          next = NULL;
          rc = elmc_list_cons(&next, item, result);
          CHECK_RC(rc);
          elmc_release(item);
          item = NULL;
          elmc_release(result);
          result = next;
          next = NULL;
        }
        *out = result;
        result = NULL;
      CATCH_END
      elmc_release(item);
      elmc_release(next);
      elmc_release(result);
      return rc;
    }
    """
  end
end
