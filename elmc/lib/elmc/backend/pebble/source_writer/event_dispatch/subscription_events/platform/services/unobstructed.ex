defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.Services.Unobstructed do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_dispatch_unobstructed_will_change(ElmcPebbleApp *app, int x, int y, int w, int h) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA);
          if (tag <= 0) return -6;

          const char *names[] = {"x", "y", "w", "h"};
          int64_t values[] = {x, y, w, h};
          return elmc_pebble_dispatch_tag_record_int_fields(app, tag, 4, names, values);
        }

        int elmc_pebble_dispatch_unobstructed_changing(ElmcPebbleApp *app, int progress) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA);
          if (tag <= 0) return -6;
          if (progress < 0) progress = 0;
          if (progress > 255) progress = 255;
          return elmc_pebble_dispatch_tag_value(app, tag, progress);
        }

        int elmc_pebble_dispatch_unobstructed_did_change(ElmcPebbleApp *app) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_UNOBSTRUCTED_AREA);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_int(app, tag);
        }

"""
  end
end
