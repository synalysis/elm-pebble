defmodule Elmx.Runtime.Pebble.Registry.Device do
  @moduledoc false

  alias Elmx.Runtime.Handler
  alias Elmx.Runtime.Pebble.Dispatch

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    for {name, kind} <- [
          {"elmx_time_current_date_time", "current_date_time"},
          {"elmx_time_current_time_string", "current_time_string"},
          {"elmx_time_clock_style_24h", "clock_style_24h"},
          {"elmx_time_timezone_is_set", "timezone_is_set"},
          {"elmx_time_timezone", "timezone"},
          {"elmx_watch_info_get_model", "watch_model"},
          {"elmx_watch_info_get_color", "watch_color"},
          {"elmx_watch_info_get_firmware_version", "firmware_version"},
          {"elmx_system_battery_level", "battery_level"},
          {"elmx_system_connection_status", "connection_status"}
        ],
        into: %{} do
      {name, {Dispatch, :device_stub, kind: kind}}
    end
    |> Map.merge(%{
      "elmx_platform_launch_reason_to_int" => {Dispatch, :platform_launch_reason},
      "elmx_platform_display_shape_is_round" => {Dispatch, :platform_display_shape_is_round},
      "elmx_platform_color_capability_is_color" => {Dispatch, :platform_color_capability_is_color}
    })
  end
end
