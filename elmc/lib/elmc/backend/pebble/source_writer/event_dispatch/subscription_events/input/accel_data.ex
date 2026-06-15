defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Input.AccelData do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_accel_data(ElmcPebbleApp *app, int32_t x, int32_t y, int32_t z) {
          if (!app || !app->initialized) return -1;
          if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_DATA)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_ACCEL_DATA);
          if (tag <= 0) return -6;
          const char *names[] = {"x", "y", "z"};
          const int64_t values[] = {x, y, z};
          return elmc_pebble_dispatch_tag_record_int_fields(app, tag, 3, names, values);
        }

    """
  end
end
