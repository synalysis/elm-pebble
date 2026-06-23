defmodule Elmc.Backend.Pebble.HeaderWriter.ApiDecls.EventHandlers do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    int elmc_pebble_msg_from_appmessage(int32_t key, int32_t value, int64_t *out_tag);
    int elmc_pebble_dispatch_appmessage(ElmcPebbleApp *app, int32_t key, int32_t value);
    int elmc_pebble_dispatch_button(ElmcPebbleApp *app, int32_t button_id);
    int elmc_pebble_dispatch_button_raw(ElmcPebbleApp *app, int32_t button_id, int32_t pressed);
    int elmc_pebble_dispatch_accel_tap(ElmcPebbleApp *app, int32_t axis, int32_t direction);
    int elmc_pebble_dispatch_accel_data(ElmcPebbleApp *app, int32_t x, int32_t y, int32_t z);
    int elmc_pebble_dispatch_storage_string(ElmcPebbleApp *app, const char *value);
    int elmc_pebble_dispatch_random_int(ElmcPebbleApp *app, int32_t value);
    int elmc_pebble_dispatch_battery(ElmcPebbleApp *app, int level);
    int elmc_pebble_dispatch_connection(ElmcPebbleApp *app, int connected);
    int elmc_pebble_dispatch_health(ElmcPebbleApp *app, int event);
    int elmc_pebble_dispatch_app_focus(ElmcPebbleApp *app, int in_focus);
    int elmc_pebble_dispatch_backlight(ElmcPebbleApp *app, int is_on);
    int elmc_pebble_dispatch_screen_change(ElmcPebbleApp *app, int width, int height, int shape, int color_mode);
    int elmc_pebble_dispatch_speaker_finished(ElmcPebbleApp *app, int reason);
    #if ELMC_PEBBLE_FEATURE_COMPASS_EVENTS
    int elmc_pebble_dispatch_compass_heading(ElmcPebbleApp *app, double degrees, int is_valid);
    #endif
    int elmc_pebble_dispatch_dictation_status(ElmcPebbleApp *app, int status);
    int elmc_pebble_dispatch_dictation_result(ElmcPebbleApp *app, int is_ok, int error_code, const char *text);
    int elmc_pebble_dispatch_unobstructed_will_change(ElmcPebbleApp *app, int x, int y, int w, int h);
    int elmc_pebble_dispatch_unobstructed_changing(ElmcPebbleApp *app, int progress);
    int elmc_pebble_dispatch_unobstructed_did_change(ElmcPebbleApp *app);
    int elmc_pebble_dispatch_frame(ElmcPebbleApp *app, int64_t dt_ms, int64_t elapsed_ms, int64_t frame);
    int elmc_pebble_dispatch_hour(ElmcPebbleApp *app, int hour);
    int elmc_pebble_dispatch_minute(ElmcPebbleApp *app, int minute);
    int elmc_pebble_dispatch_day(ElmcPebbleApp *app, int day);
    int elmc_pebble_dispatch_month(ElmcPebbleApp *app, int month);
    int elmc_pebble_dispatch_year(ElmcPebbleApp *app, int year);
"""
  end
end
