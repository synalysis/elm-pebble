defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagScalars.TagBool do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_tag_bool(ElmcPebbleApp *app, int64_t tag, int value) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_bool");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", -1);
          RC Rc = RC_SUCCESS;
          ElmcValue *tag_value = NULL;
          ElmcValue *payload_value = NULL;
          ElmcValue *msg = NULL;
          CATCH_BEGIN
            Rc = elmc_new_int(&tag_value, tag);
            CHECK_RC(Rc);
            Rc = elmc_new_bool(&payload_value, value ? 1 : 0);
            CHECK_RC(Rc);
            Rc = elmc_tuple2_take(&msg, tag_value, payload_value);
            CHECK_RC(Rc);
          CATCH_END
          if (Rc != RC_SUCCESS) {
            elmc_release(tag_value);
            elmc_release(payload_value);
            ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", -2);
          }
          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_bool", elmc_pebble_finish_dispatch(app, rc));
        }

    """
  end
end
