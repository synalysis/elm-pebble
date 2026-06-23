defmodule Elmc.Backend.Pebble.Types.FeatureFlags.Keys.Event do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @clock_keys [
    :tick_events,
    :hour_events,
    :minute_events,
    :day_events,
    :month_events,
    :year_events,
    :frame_events
  ]

  @input_keys [
    :button_events,
    :raw_button_events,
    :accel_events,
    :accel_data_events
  ]

  @constructor_platform_keys [:battery_events, :connection_events]

  @subscription_platform_keys [
    :health_events,
    :app_focus_events,
    :compass_events,
    :dictation_events,
    :unobstructed_area_events,
    :backlight_events,
    :screen_change_events,
    :speaker_finished_events,
    :inbox_events
  ]

  @platform_keys @constructor_platform_keys ++ @subscription_platform_keys

  @keys @clock_keys ++ @input_keys ++ @platform_keys

  @spec keys() :: [Types.feature_flag_key()]
  def keys, do: @keys

  @spec clock_keys() :: [Types.feature_flag_key()]
  def clock_keys, do: @clock_keys

  @spec input_keys() :: [Types.feature_flag_key()]
  def input_keys, do: @input_keys

  @spec platform_keys() :: [Types.feature_flag_key()]
  def platform_keys, do: @platform_keys

  @spec constructor_platform_keys() :: [Types.feature_flag_key()]
  def constructor_platform_keys, do: @constructor_platform_keys

  @spec subscription_platform_keys() :: [Types.feature_flag_key()]
  def subscription_platform_keys, do: @subscription_platform_keys
end
