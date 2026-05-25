defmodule Ide.Debugger.DeviceRequest do
  @moduledoc false

  alias Ide.Debugger.Types

  @spec from_cmd_call(Types.cmd_call()) :: [Types.device_request()]
  def from_cmd_call(cmd_call) when is_map(cmd_call) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()

    response_ctor =
      Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)

    cond do
      response_ctor in [nil, ""] ->
        []

      name in ["getCurrentTimeString", "currentTimeString"] ->
        [%{kind: "current_time_string", response_message: response_ctor}]

      name in ["getCurrentDateTime", "currentDateTime"] ->
        [%{kind: "current_date_time", response_message: response_ctor}]

      name in ["getBatteryLevel", "batteryLevel"] ->
        [%{kind: "battery_level", response_message: response_ctor}]

      name in ["getConnectionStatus", "connectionStatus"] ->
        [%{kind: "connection_status", response_message: response_ctor}]

      name in ["getClockStyle24h", "clockStyle24h"] ->
        [%{kind: "clock_style_24h", response_message: response_ctor}]

      name in ["getTimezoneIsSet", "timezoneIsSet"] ->
        [%{kind: "timezone_is_set", response_message: response_ctor}]

      name in ["getTimezone", "timezone"] ->
        [%{kind: "timezone", response_message: response_ctor}]

      name in ["getWatchModel", "getModel"] ->
        [%{kind: "watch_model", response_message: response_ctor}]

      name in ["getWatchColor", "getColor"] ->
        [%{kind: "watch_color", response_message: response_ctor}]

      name in ["getFirmwareVersion", "firmwareVersion"] ->
        [%{kind: "firmware_version", response_message: response_ctor}]

      name in ["value"] and health_cmd_target?(cmd_call) ->
        [%{kind: "health_value", response_message: response_ctor}]

      name in ["supported"] and health_cmd_target?(cmd_call) ->
        [%{kind: "health_supported", response_message: response_ctor}]

      name in ["sumToday"] and health_cmd_target?(cmd_call) ->
        [%{kind: "health_sum_today", response_message: response_ctor}]

      name in ["sum"] and health_cmd_target?(cmd_call) ->
        [%{kind: "health_sum", response_message: response_ctor}]

      name in ["accessible"] and health_cmd_target?(cmd_call) ->
        [%{kind: "health_accessible", response_message: response_ctor}]

      true ->
        []
    end
  end

  def from_cmd_call(_cmd_call), do: []

  @spec health_cmd_target?(Types.cmd_call()) :: boolean()
  defp health_cmd_target?(cmd_call) when is_map(cmd_call) do
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    String.contains?(target, "Health.") or
      String.contains?(target, "PebbleWatch.health") or
      String.contains?(target, "Elm.Kernel.PebbleWatch.health")
  end

  defp health_cmd_target?(_cmd_call), do: false
end
