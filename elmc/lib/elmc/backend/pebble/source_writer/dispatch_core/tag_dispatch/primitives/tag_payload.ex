defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.TagPayload do
  @moduledoc false
  alias Elmc.Types, as: Types


  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        /* Borrows `payload`: retains into the dispatch msg, then drops that retain.
           Callers keep ownership and must release the payload themselves. */
        int elmc_pebble_dispatch_tag_payload(ElmcPebbleApp *app, int64_t tag, ElmcValue *payload) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_tag_payload");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -1);
          if (!payload) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -3);
          RC Rc = RC_SUCCESS;
          ElmcValue *tag_value = NULL;
          ElmcValue *msg = NULL;
          CATCH_BEGIN
            Rc = elmc_new_int(&tag_value, tag);
            CHECK_RC(Rc);
            Rc = elmc_tuple2(&msg, tag_value, payload);
            CHECK_RC(Rc);
            elmc_release(tag_value);
            tag_value = NULL;
          CATCH_END
          if (Rc != RC_SUCCESS) {
            elmc_release(tag_value);
            elmc_release(msg);
            ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", -2);
          }
          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_tag_payload", elmc_pebble_finish_dispatch(app, rc));
        }
"""
  end
end
