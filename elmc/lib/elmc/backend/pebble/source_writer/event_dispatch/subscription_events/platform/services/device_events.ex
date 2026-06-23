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

        int elmc_pebble_dispatch_backlight(ElmcPebbleApp *app, int is_on) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_BACKLIGHT)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_BACKLIGHT);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, is_on ? 0 : 1);
        }

        int elmc_pebble_dispatch_screen_change(ElmcPebbleApp *app, int width, int height, int shape, int color_mode) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_SCREEN_CHANGE)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_SCREEN_CHANGE);
          if (tag <= 0) return -6;
          const char *field_names[] = {"width", "height", "shape", "colorMode"};
          int64_t field_values[] = {width, height, shape, color_mode};
          return elmc_pebble_dispatch_tag_record_int_fields(app, tag, 4, field_names, field_values);
        }

        int elmc_pebble_dispatch_speaker_finished(ElmcPebbleApp *app, int reason) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_SPEAKER_FINISHED)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_SPEAKER_FINISHED);
          if (tag <= 0) return -6;
          if (reason < 0) reason = 0;
          if (reason > 3) reason = 0;
          return elmc_pebble_dispatch_tag_value(app, tag, reason);
        }

"""
  end
end
