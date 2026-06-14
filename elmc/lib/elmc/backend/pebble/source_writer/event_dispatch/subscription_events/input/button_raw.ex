defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Input.ButtonRaw do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
        int elmc_pebble_dispatch_button_raw(ElmcPebbleApp *app, int32_t button_id, int32_t pressed) {
          if (!app || !app->initialized) return -1;
          if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BUTTON_RAW)) return -8;
          elmc_int_t event = elmc_pebble_button_event(pressed);
          elmc_int_t tag = elmc_worker_button_raw_msg_tag(&app->worker, button_id, event);
          if (tag <= 0) return 1;
          return elmc_pebble_dispatch_int(app, tag);
        }

    """
  end
end
