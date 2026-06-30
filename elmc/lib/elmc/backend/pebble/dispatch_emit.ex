defmodule Elmc.Backend.Pebble.DispatchEmit do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec compass_source(Types.compass_dispatch_flags()) :: Types.c_source()
  def compass_source(%{compass_events: true}) do
    """
    int elmc_pebble_dispatch_compass_heading(ElmcPebbleApp *app, double degrees, int is_valid) {
      ELMC_PEBBLE_GENERATED_TRACE_ENTER("elmc_pebble_dispatch_compass_heading");
      if (!app || !app->initialized) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", -1);
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_COMPASS)) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", -8);
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_COMPASS);
      if (tag <= 0) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", -6);

      RC Rc = RC_SUCCESS;
      const char *names[] = {"degrees", "isValid"};
      ElmcValue *values[2];
      ElmcValue *record = NULL;
      ElmcValue *tag_value = NULL;
      ElmcValue *msg = NULL;
      CATCH_BEGIN
        CHECK_RC_TO(Rc, elmc_new_float(&values[0], degrees));
        CHECK_RC_TO(Rc, elmc_new_bool(&values[1], is_valid ? 1 : 0));
        CHECK_RC_TO(Rc, elmc_record_new_take(&record, 2, names, values));
        CHECK_RC_TO(Rc, elmc_new_int(&tag_value, tag));
        CHECK_RC_TO(Rc, elmc_tuple2_take(&msg, tag_value, record));
      CATCH_END
      elmc_release(tag_value);
      elmc_release(record);
      if (Rc != RC_SUCCESS) ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", -2);
      elmc_pebble_prepare_dispatch(app);
      int dispatch_rc = elmc_worker_dispatch(&app->worker, msg);
      elmc_release(msg);
      ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT("elmc_pebble_dispatch_compass_heading", elmc_pebble_finish_dispatch(app, dispatch_rc));
    }
    """
  end

  @spec compass_source(Types.compass_dispatch_flags()) :: Types.c_source()
  def compass_source(_feature_flags), do: ""
end
