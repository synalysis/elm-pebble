defmodule Ide.Debugger.DeviceRequest do
  @moduledoc false

  alias Ide.Debugger.Types

  @spec from_cmd_call(Types.cmd_call()) :: [Types.device_request()]
  def from_cmd_call(cmd_call) when is_map(cmd_call) do
    response_ctor =
      Map.get(cmd_call, "callback_constructor") || Map.get(cmd_call, :callback_constructor)

    if is_binary(response_ctor) and response_ctor != "" do
      case device_kind(cmd_call) do
        nil ->
          []

        kind ->
          req =
            %{kind: kind, response_message: response_ctor}
            |> maybe_put_health_metric(cmd_call)

          [req]
      end
    else
      []
    end
  end

  def from_cmd_call(_cmd_call), do: []

  @spec device_kind(Types.cmd_call()) :: String.t() | nil
  defp device_kind(cmd_call) when is_map(cmd_call) do
    cond do
      cmd_name_matches?(cmd_call, ["getCurrentTimeString", "currentTimeString"]) ->
        "current_time_string"

      cmd_name_matches?(cmd_call, ["getCurrentDateTime", "currentDateTime"]) ->
        "current_date_time"

      cmd_name_matches?(cmd_call, ["getBatteryLevel", "batteryLevel"]) ->
        "battery_level"

      cmd_name_matches?(cmd_call, ["getConnectionStatus", "connectionStatus"]) ->
        "connection_status"

      cmd_name_matches?(cmd_call, ["getClockStyle24h", "clockStyle24h"]) ->
        "clock_style_24h"

      cmd_name_matches?(cmd_call, ["getTimezoneIsSet", "timezoneIsSet"]) ->
        "timezone_is_set"

      cmd_name_matches?(cmd_call, ["getTimezone", "timezone"]) ->
        "timezone"

      cmd_name_matches?(cmd_call, ["getWatchModel", "getModel"]) ->
        "watch_model"

      cmd_name_matches?(cmd_call, ["getWatchColor", "getColor"]) ->
        "watch_color"

      cmd_name_matches?(cmd_call, ["getFirmwareVersion", "firmwareVersion"]) ->
        "firmware_version"

      cmd_name_matches?(cmd_call, ["value"]) and health_cmd_target?(cmd_call) ->
        "health_value"

      cmd_name_matches?(cmd_call, ["supported"]) and health_cmd_target?(cmd_call) ->
        "health_supported"

      cmd_name_matches?(cmd_call, ["sumToday"]) and health_cmd_target?(cmd_call) ->
        "health_sum_today"

      cmd_name_matches?(cmd_call, ["sum"]) and health_cmd_target?(cmd_call) ->
        "health_sum"

      cmd_name_matches?(cmd_call, ["accessible"]) and health_cmd_target?(cmd_call) ->
        "health_accessible"

      cmd_name_matches?(cmd_call, ["hrvPpiMs"]) and health_cmd_target?(cmd_call) ->
        "health_hrv_ppi_ms"

      cmd_name_matches?(cmd_call, ["next"]) and alarm_cmd_target?(cmd_call) ->
        "alarm_next"

      cmd_name_matches?(cmd_call, ["supported"]) and touch_cmd_target?(cmd_call) ->
        "touch_supported"

      true ->
        nil
    end
  end

  @spec cmd_name_matches?(Types.cmd_call(), [String.t()]) :: boolean()
  defp cmd_name_matches?(cmd_call, candidates) when is_map(cmd_call) and is_list(candidates) do
    name = (Map.get(cmd_call, "name") || Map.get(cmd_call, :name) || "") |> to_string()
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    Enum.any?(candidates, fn candidate ->
      name == candidate or target == candidate or String.ends_with?(target, "." <> candidate)
    end)
  end

  @spec health_cmd_target?(Types.cmd_call()) :: boolean()
  defp health_cmd_target?(cmd_call) when is_map(cmd_call) do
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    String.contains?(target, "Pebble.Health") or
      String.contains?(target, "Health.") or
      String.contains?(target, "PebbleWatch.health") or
      String.contains?(target, "Elm.Kernel.PebbleWatch.health")
  end

  @spec alarm_cmd_target?(Types.cmd_call()) :: boolean()
  defp alarm_cmd_target?(cmd_call) when is_map(cmd_call) do
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    String.contains?(target, "Pebble.Alarm") or
      String.contains?(target, "PebbleWatch.alarm") or
      String.contains?(target, "Elm.Kernel.PebbleWatch.alarm")
  end

  @spec touch_cmd_target?(Types.cmd_call()) :: boolean()
  defp touch_cmd_target?(cmd_call) when is_map(cmd_call) do
    target = (Map.get(cmd_call, "target") || Map.get(cmd_call, :target) || "") |> to_string()

    String.contains?(target, "Pebble.Touch") or
      String.contains?(target, "PebbleWatch.touch") or
      String.contains?(target, "Elm.Kernel.PebbleWatch.touch")
  end

  @spec maybe_put_health_metric(Types.device_request(), Types.cmd_call()) :: Types.device_request()
  defp maybe_put_health_metric(%{kind: "health_value"} = req, cmd_call) do
    case health_metric_from_cmd_call(cmd_call) do
      nil -> req
      metric -> Map.put(req, :metric, metric)
    end
  end

  defp maybe_put_health_metric(req, _cmd_call), do: req

  @spec health_metric_from_cmd_call(Types.cmd_call()) :: String.t() | nil
  defp health_metric_from_cmd_call(cmd_call) when is_map(cmd_call) do
    snippets =
      (Map.get(cmd_call, "arg_snippets") || Map.get(cmd_call, :arg_snippets) || [])
      |> List.wrap()
      |> Enum.map(&to_string/1)

    values = Map.get(cmd_call, "arg_values") || Map.get(cmd_call, :arg_values) || []

    cond do
      Enum.any?(snippets, &String.contains?(&1, "HeartRateBPM")) ->
        "HeartRateBPM"

      Enum.any?(snippets, &String.contains?(&1, "StepCount")) ->
        "StepCount"

      match?([7 | _], values) ->
        "HeartRateBPM"

      true ->
        nil
    end
  end
end
