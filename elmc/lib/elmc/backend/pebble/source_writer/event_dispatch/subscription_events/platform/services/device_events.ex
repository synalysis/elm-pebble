defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.Services.DeviceEvents do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BATTERY)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_BATTERY);
          if (tag <= 0) return -6;
          if (level < 0) level = 0;
          if (level > 100) level = 100;
          return elmc_pebble_dispatch_tag_value(app, tag, level);
        }

        int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_CONNECTION)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_CONNECTION);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_bool(app, tag, connected);
        }

        int elmc_pebble_dispatch_health(ElmcPebbleApp *app, int event) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_HEALTH)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_HEALTH);
          if (tag <= 0) return -6;
          if (event < 0) event = 0;
          if (event > 2) event = 0;
          return elmc_pebble_dispatch_tag_value(app, tag, event);
        }

        int elmc_pebble_dispatch_app_focus(ElmcPebbleApp *app, int in_focus) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_APP_FOCUS)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_APP_FOCUS);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, in_focus ? 0 : 1);
        }

"""
  end
end
