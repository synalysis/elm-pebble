defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagPayload do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_payload");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -1);
          if (!payload) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -3);
          ElmcValue *tag_value = elmc_new_int_take(tag);
          if (!tag_value) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -2);

          ElmcValue *msg = elmc_tuple2_take_value(tag_value, payload);
          if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -2);

          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", elmc_pebble_finish_dispatch(app, rc));
        }
"""
  end
end
