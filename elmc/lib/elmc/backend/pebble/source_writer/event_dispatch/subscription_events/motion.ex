defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Motion do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_dispatch_frame(ElmcPebbleApp *app, int64_t dt_ms, int64_t elapsed_ms, int64_t frame) {
          if (!app || !app->initialized) return -1;
          if (app->run_mode == ELMC_PEBBLE_MODE_WATCHFACE) return -9;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_FRAME)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_FRAME);
          if (tag <= 0) return -6;
          const char *names[] = {"dtMs", "elapsedMs", "frame"};
          const int64_t values[] = {dt_ms, elapsed_ms, frame};
          return elmc_pebble_dispatch_tag_record_int_fields(app, tag, 3, names, values);
        }

"""
  end
end
