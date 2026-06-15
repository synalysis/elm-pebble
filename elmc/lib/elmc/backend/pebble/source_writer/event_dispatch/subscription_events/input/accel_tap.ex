defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Input.AccelTap do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction) {
          (void)axis;
          (void)direction;
          if (!app || !app->initialized) return -1;
          if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_ACCEL_TAP)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_ACCEL_TAP);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_int(app, tag);
        }

    """
  end
end
