defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Input.Button do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_button(ElmcPebbleApp *app, int32_t button_id) {
          if (!app || !app->initialized) return -1;
          if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
          int64_t required = 0;
          if (button_id == ELMC_PEBBLE_BUTTON_UP) {
            required = ELMC_PEBBLE_SUB_BUTTON_UP;
          } else if (button_id == ELMC_PEBBLE_BUTTON_SELECT) {
            required = ELMC_PEBBLE_SUB_BUTTON_SELECT;
          } else if (button_id == ELMC_PEBBLE_BUTTON_DOWN) {
            required = ELMC_PEBBLE_SUB_BUTTON_DOWN;
          } else {
            return -3;
          }
          if (!elmc_pebble_is_subscribed(app, required)) return -8;
          elmc_int_t tag = elmc_worker_sub_msg_tag(&app->worker, required);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_int(app, tag);
        }

    """
  end
end
