defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagScalars.TagValue do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_tag_value(ElmcPebbleApp *app, int64_t tag, int64_t value) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_value");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -1);
          ElmcValue *tag_value = elmc_new_int_take(tag);
          ElmcValue *payload_value = elmc_new_int_take(value);
          if (!tag_value || !payload_value) {
            if (tag_value) elmc_release(tag_value);
            if (payload_value) elmc_release(payload_value);
            ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -2);
          }

          ElmcValue *msg = elmc_tuple2_take_value(tag_value, payload_value);
          if (!msg) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", -2);

          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_value", elmc_pebble_finish_dispatch(app, rc));
        }

    """
  end
end
