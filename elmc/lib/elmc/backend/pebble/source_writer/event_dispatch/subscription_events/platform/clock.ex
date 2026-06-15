defmodule Elmc.Backend.Pebble.SourceWriter.EventDispatch.SubscriptionEvents.Platform.Clock do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_HOUR)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_HOUR);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, hour);
        }

        int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_MINUTE)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_MINUTE);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, minute);
        }

        int elmc_pebble_dispatch_day(ElmcPebbleApp *app, int day) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_DAY)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_DAY);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, day);
        }

        int elmc_pebble_dispatch_month(ElmcPebbleApp *app, int month) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_MONTH)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_MONTH);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, month);
        }

        int elmc_pebble_dispatch_year(ElmcPebbleApp *app, int year) {
          if (!app || !app->initialized) return -1;
          if (!elmc_pebble_is_subscribed(app, ELMC_PEBBLE_SUB_YEAR)) return -8;
          elmc_int_t tag = elmc_pebble_sub_tag(app, ELMC_PEBBLE_SUB_YEAR);
          if (tag <= 0) return -6;
          return elmc_pebble_dispatch_tag_value(app, tag, year);
        }

"""
  end
end
