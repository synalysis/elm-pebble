defmodule Elmc.Backend.Pebble.SourceWriter.DispatchCore.TagDispatch.Primitives.IntDispatch do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_int(ElmcPebbleApp *app, int64_t tag) {
          ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_int");
          if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", -1);
          RC Rc = RC_SUCCESS;
          ElmcValue *msg = NULL;
          CATCH_BEGIN
            Rc = elmc_new_int(&msg, tag);
            CHECK_RC(Rc);
          CATCH_END
          if (Rc != RC_SUCCESS) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", -2);
          elmc_pebble_prepare_dispatch(app);
          int rc = elmc_worker_dispatch(&app->worker, msg);
          elmc_release(msg);
          ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_int", elmc_pebble_finish_dispatch(app, rc));
        }

"""
  end
end
