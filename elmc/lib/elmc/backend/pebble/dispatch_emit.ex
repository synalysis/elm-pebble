defmodule Elmc.Backend.Pebble.DispatchEmit do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec compass_source(Types.compass_dispatch_flags()) :: Types.c_source()
  def compass_source(%{compass_events: true}) do
    """
    int elmc_pebble_dispatch_compass_heading(ElmcPebbleApp *app, double degrees, int is_valid) {
      if (!app || !app->initialized) return -1;
      if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_COMPASS)) return -8;
      elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_COMPASS);
      if (tag <= 0) return -6;

      const char *names[] = {"degrees", "isValid"};
      ElmcValue *values[2];
      values[0] = elmc_new_float_take(degrees);
      values[1] = elmc_new_bool_take(is_valid ? 1 : 0);
      if (!values[0] || !values[1]) {
        if (values[0]) elmc_release(values[0]);
        if (values[1]) elmc_release(values[1]);
        return -2;
      }

      ElmcValue *record = elmc_record_new_take_value(2, names, values);
      if (!record) return -2;

      ElmcValue *tag_value = elmc_new_int_take(tag);
      if (!tag_value) {
        elmc_release(record);
        return -2;
      }

      ElmcValue *msg = elmc_tuple2_take_value(tag_value, record);
      if (!msg) return -2;

      elmc_pebble_prepare_dispatch(app);
      int rc = elmc_worker_dispatch(&app->worker, msg);
      elmc_release(msg);
      return elmc_pebble_finish_dispatch(app, rc);
    }
    """
  end

  @spec compass_source(Types.compass_dispatch_flags()) :: Types.c_source()
  def compass_source(_feature_flags), do: ""
end
