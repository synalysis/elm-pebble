defmodule Elmc.Backend.Pebble.Types.FeatureFlags.Keys.Command do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @storage_keys [
    :cmd_storage_write_int,
    :cmd_storage_read_int,
    :cmd_storage_write_string,
    :cmd_storage_read_string,
    :cmd_random_generate,
    :cmd_storage_delete,
    :cmd_storage_read_max_size,
    :cmd_companion_send
  ]

  @system_keys [
    :cmd_timer_after_ms,
    :cmd_backlight,
    :cmd_get_current_time_string,
    :cmd_get_current_date_time,
    :cmd_get_battery_level,
    :cmd_get_connection_status,
    :cmd_get_clock_style_24h,
    :cmd_get_timezone_is_set,
    :cmd_get_timezone,
    :cmd_get_watch_model,
    :cmd_get_watch_color,
    :cmd_get_firmware_version,
    :cmd_wakeup_schedule_after_seconds,
    :cmd_wakeup_cancel,
    :cmd_log_info_code,
    :cmd_log_warn_code,
    :cmd_log_error_code
  ]

  @timer_wakeup_keys [
    :cmd_timer_after_ms,
    :cmd_wakeup_schedule_after_seconds,
    :cmd_wakeup_cancel
  ]

  @backlight_keys [:cmd_backlight]

  @time_timezone_keys [
    :cmd_get_current_time_string,
    :cmd_get_current_date_time,
    :cmd_get_clock_style_24h,
    :cmd_get_timezone_is_set,
    :cmd_get_timezone
  ]

  @device_query_keys [
    :cmd_get_battery_level,
    :cmd_get_connection_status,
    :cmd_get_watch_model,
    :cmd_get_watch_color,
    :cmd_get_firmware_version
  ]

  @logging_keys [
    :cmd_log_info_code,
    :cmd_log_warn_code,
    :cmd_log_error_code
  ]

  @vibes_keys [
    :cmd_vibes_cancel,
    :cmd_vibes_short_pulse,
    :cmd_vibes_long_pulse,
    :cmd_vibes_double_pulse,
    :cmd_vibes_custom_pattern
  ]

  @health_keys [
    :cmd_health_value,
    :cmd_health_sum_today,
    :cmd_health_sum,
    :cmd_health_accessible,
    :cmd_health_supported
  ]

  @device_services_keys [
    :cmd_data_log_bytes,
    :cmd_data_log_int32,
    :cmd_compass_peek,
    :cmd_dictation_start,
    :cmd_dictation_stop,
    :cmd_unobstructed_bounds_peek
  ]

  @speaker_keys [
    :cmd_speaker_is_muted,
    :cmd_speaker_play_tone,
    :cmd_speaker_play_notes,
    :cmd_speaker_play_tracks,
    :cmd_speaker_stop,
    :cmd_speaker_set_volume,
    :cmd_speaker_get_status,
    :cmd_speaker_stream_open,
    :cmd_speaker_stream_write,
    :cmd_speaker_stream_close
  ]

  @services_keys @vibes_keys ++ @health_keys ++ @device_services_keys ++ @speaker_keys

  @keys [:cmd_timer_after_ms | @storage_keys] ++ Enum.drop(@system_keys, 1) ++ @services_keys

  @spec keys() :: [Types.feature_flag_key()]
  def keys, do: @keys

  @spec storage_keys() :: [Types.feature_flag_key()]
  def storage_keys, do: @storage_keys

  @spec system_keys() :: [Types.feature_flag_key()]
  def system_keys, do: @system_keys

  @spec services_keys() :: [Types.feature_flag_key()]
  def services_keys, do: @services_keys

  @spec timer_wakeup_keys() :: [Types.feature_flag_key()]
  def timer_wakeup_keys, do: @timer_wakeup_keys

  @spec backlight_keys() :: [Types.feature_flag_key()]
  def backlight_keys, do: @backlight_keys

  @spec time_timezone_keys() :: [Types.feature_flag_key()]
  def time_timezone_keys, do: @time_timezone_keys

  @spec device_query_keys() :: [Types.feature_flag_key()]
  def device_query_keys, do: @device_query_keys

  @spec logging_keys() :: [Types.feature_flag_key()]
  def logging_keys, do: @logging_keys

  @spec vibes_keys() :: [Types.feature_flag_key()]
  def vibes_keys, do: @vibes_keys

  @spec health_keys() :: [Types.feature_flag_key()]
  def health_keys, do: @health_keys

  @spec device_services_keys() :: [Types.feature_flag_key()]
  def device_services_keys, do: @device_services_keys

  @spec speaker_keys() :: [Types.feature_flag_key()]
  def speaker_keys, do: @speaker_keys
end
