defmodule Ide.Debugger.DeviceData do
  @moduledoc false

  alias Ide.Debugger.DeviceRequest
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.Types

  @spec settings_from_model(map()) :: map()
  defp settings_from_model(model) when is_map(model), do: DebuggerSimulatorSettings.from_model(model)

  @spec now_from_model(map()) :: NaiveDateTime.t()
  defp now_from_model(model) when is_map(model) do
    model
    |> settings_from_model()
    |> now_from_settings()
  end

  @spec now_from_settings(map()) :: NaiveDateTime.t()
  defp now_from_settings(settings) when is_map(settings) do
    fallback = NaiveDateTime.local_now()

    if settings["use_simulated_time"] == true do
      date = parse_simulated_date(settings["simulated_date"], NaiveDateTime.to_date(fallback))
      time = parse_simulated_time(settings["simulated_time"], NaiveDateTime.to_time(fallback))
      NaiveDateTime.new!(date, time)
    else
      fallback
    end
  end

  defp parse_simulated_date(value, fallback) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _} -> fallback
    end
  end

  defp parse_simulated_date(_value, fallback), do: fallback

  defp parse_simulated_time(value, fallback) when is_binary(value) do
    case Time.from_iso8601(String.trim(value)) do
      {:ok, time} -> time
      {:error, _} -> fallback
    end
  end

  defp parse_simulated_time(_value, fallback), do: fallback

  @spec response_message(Types.cmd_call()) :: String.t() | nil
  def response_message(%{
         response_message: ctor,
         kind: "current_time_string",
         preview: preview
       })
       when is_binary(ctor) and ctor != "" and is_map(preview) do
    case Map.get(preview, "string") do
      value when is_binary(value) ->
        escaped =
          value
          |> String.replace("\\", "\\\\")
          |> String.replace("\"", "\\\"")

        "#{ctor} \"#{escaped}\""

      _ ->
        ctor
    end
  end

  def response_message(%{
         response_message: ctor,
         kind: "current_date_time",
         preview: preview
       })
       when is_binary(ctor) and ctor != "" and is_map(preview) do
    "#{ctor} #{Jason.encode!(current_date_time_message_payload(preview))}"
  end

  def response_message(%{
         response_message: ctor,
         kind: kind,
         preview: preview
       })
       when is_binary(ctor) and ctor != "" and kind in ["battery_level", "connection_status"] do
    value =
      case {kind, preview} do
        {"battery_level", %{"batteryLevel" => level}} -> level
        {"connection_status", %{"connected" => connected}} -> connected
        _ -> preview
      end

    "#{ctor} #{elm_literal(value)}"
  end

  def response_message(%{
         response_message: ctor,
         kind: kind,
         preview: preview
       })
       when is_binary(ctor) and ctor != "" and
              kind in [
                "health_value",
                "health_sum_today",
                "health_sum",
                "health_accessible",
                "health_supported"
              ] do
    value =
      case preview do
        %{"value" => metric_value} -> metric_value
        metric_value -> metric_value
      end

    "#{ctor} #{elm_literal(value)}"
  end

  def response_message(%{response_message: ctor}) when is_binary(ctor), do: ctor
  def response_message(_req), do: nil

  def elm_literal(value) when is_boolean(value), do: if(value, do: "True", else: "False")
  def elm_literal(value) when is_integer(value), do: Integer.to_string(value)
  def elm_literal(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  def elm_literal(value) when is_binary(value), do: inspect(value)
  def elm_literal(value), do: inspect(value)

  @spec current_date_time_message_payload(map()) :: map()
  def current_date_time_message_payload(preview) when is_map(preview) do
    Map.update(preview, "dayOfWeek", nil, fn
      value when is_binary(value) -> %{"ctor" => value, "args" => []}
      value -> value
    end)
  end

  @spec health_metric_request_disabled?(map(), map()) :: boolean()
  def health_metric_request_disabled?(model, %{kind: kind})
       when is_map(model) and kind in ["health_value", "health_sum_today", "health_sum", "health_accessible"] do
    launch_context = Map.get(model, "launch_context") || %{}

    health_runtime_disabled?(Map.get(model, "runtime_model") || %{}) or
      Map.get(launch_context, "supports_health") != true
  end

  def health_metric_request_disabled?(_model, _req), do: false

  @spec health_runtime_disabled?(map()) :: boolean()
  def health_runtime_disabled?(%{"supported" => %{"ctor" => "Just", "args" => [false]}}), do: true
  def health_runtime_disabled?(%{"supported" => %{"ctor" => "Just", "args" => [true]}}), do: false
  def health_runtime_disabled?(_runtime_model), do: false
  @spec init_request_already_satisfied?(map(), map()) :: boolean()
  def init_request_already_satisfied?(model, %{kind: kind})
       when is_map(model) and is_binary(kind) do
    Map.has_key?(model, "debugger_device_#{kind}")
  end

  def init_request_already_satisfied?(_model, _req), do: false
  @spec finalize_request(Types.device_request(), map()) :: Types.device_request()
  def finalize_request(%{kind: "current_time_string"} = req, model) do
    now = now_from_model(model)
    hhmm_text = Calendar.strftime(now, "%H:%M")

    hhmm =
      hhmm_text
      |> String.replace(":", "")
      |> Integer.parse()
      |> case do
        {parsed, ""} -> parsed
        _ -> 0
      end

    Map.put(req, :preview, %{
      "string" => hhmm_text,
      "hhmm" => hhmm
    })
  end

  def finalize_request(%{kind: "current_date_time"} = req, model) do
    now = now_from_model(model)
    settings = settings_from_model(model)

    Map.put(req, :preview, %{
      "year" => now.year,
      "month" => now.month,
      "day" => now.day,
      "dayOfWeek" => day_of_week_name(now),
      "hour" => now.hour,
      "minute" => now.minute,
      "second" => now.second,
      "utcOffsetMinutes" => settings["timezone_offset_min"]
    })
  end

  def finalize_request(%{kind: "battery_level"} = req, model) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"batteryLevel" => settings["battery_percent"]})
  end

  def finalize_request(%{kind: "connection_status"} = req, model) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"connected" => settings["connected"]})
  end

  def finalize_request(%{kind: "clock_style_24h"} = req, model) do
    settings = settings_from_model(model)
    Map.put(req, :preview, settings["clock_24h"])
  end

  def finalize_request(%{kind: "timezone_is_set"} = req, _model),
    do: Map.put(req, :preview, true)

  def finalize_request(%{kind: "timezone"} = req, _model) do
    tz = System.get_env("TZ") || "UTC"
    Map.put(req, :preview, tz)
  end

  def finalize_request(%{kind: "watch_model"} = req, model) when is_map(model) do
    launch_context = Map.get(model, "launch_context") || %{}
    watch_model = Map.get(launch_context, "watch_model") || "Pebble Time Round"
    Map.put(req, :preview, watch_model)
  end

  def finalize_request(%{kind: "watch_color"} = req, model) when is_map(model) do
    launch_context = Map.get(model, "launch_context") || %{}
    color_mode = launch_context_color_mode(launch_context)
    Map.put(req, :preview, color_mode)
  end

  def finalize_request(%{kind: "firmware_version"} = req, _model),
    do: Map.put(req, :preview, "v4.4.0-sim")

  def finalize_request(%{kind: "health_value"} = req, model) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps"]})
  end

  def finalize_request(%{kind: "health_supported"} = req, model) do
    launch_context = Map.get(model, "launch_context") || %{}
    supported = Map.get(launch_context, "supports_health") == true
    Map.put(req, :preview, supported)
  end

  def finalize_request(%{kind: "health_sum_today"} = req, model) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps_today"]})
  end

  def finalize_request(%{kind: "health_sum"} = req, model) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps_today"]})
  end

  def finalize_request(%{kind: "health_accessible"} = req, _model),
    do: Map.put(req, :preview, true)

  def finalize_request(req, _model), do: Map.put(req, :preview, nil)

  @spec day_of_week_name(NaiveDateTime.t()) :: String.t()
  def day_of_week_name(%NaiveDateTime{} = now) do
    now
    |> NaiveDateTime.to_date()
    |> Date.day_of_week()
    |> case do
      1 -> "Monday"
      2 -> "Tuesday"
      3 -> "Wednesday"
      4 -> "Thursday"
      5 -> "Friday"
      6 -> "Saturday"
      _ -> "Sunday"
    end
  end

  @spec requests_for_message(map(), map(), String.t(), keyword()) :: [Types.device_request()]
  def requests_for_message(ei, model, current_message, opts)

  def requests_for_message(ei, model, current_message, opts)
       when is_map(model) and is_binary(current_message) and is_list(opts) do
    current_ctor = Keyword.get(opts, :message_constructor, fn msg -> msg end).(current_message)

    update_requests =
      ei
      |> cmd_calls_for("update_cmd_calls")
      |> filter_update_cmd_calls(current_ctor, Keyword.get(opts, :update_cmd_calls_filter))
      |> expand_cmd_calls(ei, Keyword.get(opts, :expand_cmd_calls))
      |> Enum.flat_map(&DeviceRequest.from_cmd_call/1)

    init_requests =
      ei
      |> cmd_calls_for("init_cmd_calls")
      |> expand_cmd_calls(ei, Keyword.get(opts, :expand_cmd_calls))
      |> Enum.flat_map(&DeviceRequest.from_cmd_call/1)
      |> Enum.reject(&init_request_deferred?/1)
      |> Enum.reject(&init_request_already_satisfied?(model, &1))

    (update_requests ++ init_requests)
    |> Enum.reject(&health_metric_request_disabled?(model, &1))
    |> Enum.reject(fn req ->
      not is_binary(req.response_message) or req.response_message == "" or
        req.response_message == current_ctor
    end)
    |> Enum.uniq_by(fn req -> {req.kind, req.response_message} end)
    |> Enum.map(&finalize_request(&1, model))
  end

  def requests_for_message(_ei, _model, _current_message, _opts), do: []

  @spec cmd_calls_for(map(), String.t()) :: [map()]
  defp cmd_calls_for(ei, key) when is_map(ei) and is_binary(key) do
    case Map.get(ei, key) do
      rows when is_list(rows) -> Enum.filter(rows, &is_map/1)
      _ -> []
    end
  end

  defp cmd_calls_for(_, _), do: []

  defp filter_update_cmd_calls(calls, current_ctor, filter_fn) when is_list(calls) do
    if is_function(filter_fn, 2), do: filter_fn.(calls, current_ctor), else: calls
  end

  defp expand_cmd_calls(calls, ei, expand_fn) when is_list(calls) do
    if is_function(expand_fn, 2), do: expand_fn.(calls, ei), else: calls
  end

  defp init_request_deferred?(_req), do: false

  @spec launch_context_color_mode(map()) :: String.t()
  defp launch_context_color_mode(launch_context) when is_map(launch_context) do
    cond do
      get_in(launch_context, ["screen", "color_mode"]) in ["Color", "BlackWhite"] ->
        get_in(launch_context, ["screen", "color_mode"])

      get_in(launch_context, ["screen", "colorMode"]) in ["Color", "BlackWhite"] ->
        get_in(launch_context, ["screen", "colorMode"])

      get_in(launch_context, ["screen", "is_color"]) == true ->
        "Color"

      get_in(launch_context, ["screen", "is_color"]) == false ->
        "BlackWhite"

      true ->
        "Color"
    end
  end
end
