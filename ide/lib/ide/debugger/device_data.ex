defmodule Ide.Debugger.DeviceData do
  @moduledoc false

  alias Ide.Debugger.DeviceRequest
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.Types
  alias Ide.WatchModels

  @subscription_clock_units %{
    "MinuteChanged" => :minute,
    "HourChanged" => :hour,
    "SecondChanged" => :second,
    "DayChanged" => :day,
    "MonthChanged" => :month,
    "YearChanged" => :year
  }

  @spec settings_from_model(Types.app_model()) :: Types.simulator_settings()
  defp settings_from_model(model) when is_map(model), do: DebuggerSimulatorSettings.from_model(model)

  @spec now_from_model(Types.app_model(), String.t() | nil) :: NaiveDateTime.t()
  defp now_from_model(model, current_message) when is_map(model) do
    model
    |> settings_from_model()
    |> now_from_settings()
    |> apply_subscription_clock_overrides(subscription_clock_overrides(current_message))
  end

  @spec subscription_clock_overrides(String.t() | nil) :: %{String.t() => integer()}
  def subscription_clock_overrides(message) when is_binary(message) do
    case RuntimeModelMessages.wire_constructor(message) do
      ctor when is_binary(ctor) ->
        case Map.get(@subscription_clock_units, ctor) do
          unit when not is_nil(unit) ->
            case integer_message_payload(message) do
              value when is_integer(value) -> %{Atom.to_string(unit) => value}
              _ -> %{}
            end

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  def subscription_clock_overrides(_message), do: %{}

  @spec apply_subscription_clock_overrides(NaiveDateTime.t(), %{String.t() => integer()}) ::
          NaiveDateTime.t()
  def apply_subscription_clock_overrides(%NaiveDateTime{} = now, overrides) when is_map(overrides) do
    Enum.reduce(overrides, now, fn
      {"year", value}, acc when is_integer(value) -> %{acc | year: value}
      {"month", value}, acc when is_integer(value) -> %{acc | month: value}
      {"day", value}, acc when is_integer(value) -> %{acc | day: value}
      {"hour", value}, acc when is_integer(value) -> %{acc | hour: value}
      {"minute", value}, acc when is_integer(value) -> %{acc | minute: value}
      {"second", value}, acc when is_integer(value) -> %{acc | second: value}
      _, acc -> acc
    end)
  end

  def apply_subscription_clock_overrides(now, _overrides), do: now

  @spec integer_message_payload(String.t()) :: integer() | nil
  defp integer_message_payload(message) when is_binary(message) do
    message
    |> String.trim()
    |> String.split(~r/\s+/, parts: 2)
    |> case do
      [_constructor, payload] ->
        payload = String.trim(payload)

        cond do
          String.starts_with?(payload, "{") ->
            case Jason.decode(payload) do
              {:ok, %{"args" => [value | _]}} when is_integer(value) -> value
              {:ok, %{args: [value | _]}} when is_integer(value) -> value
              _ -> nil
            end

          true ->
            case Integer.parse(payload) do
              {value, ""} -> value
              _ -> nil
            end
        end

      _ ->
        nil
    end
  end

  @spec now_from_settings(Types.simulator_settings()) :: NaiveDateTime.t()
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

  def response_message(%{response_message: ctor, kind: kind, preview: preview})
      when is_binary(ctor) and ctor != "" and
             kind in ["clock_style_24h", "timezone_is_set"] and is_boolean(preview) do
    "#{ctor} #{elm_literal(preview)}"
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

  def response_message(%{response_message: ctor, kind: "watch_model", preview: preview})
      when is_binary(ctor) and ctor != "" do
    "#{ctor} #{watch_info_model_ctor_literal(preview)}"
  end

  def response_message(%{response_message: ctor, kind: "watch_color", preview: preview})
      when is_binary(ctor) and ctor != "" do
    "#{ctor} #{watch_info_color_ctor_literal(preview)}"
  end

  def response_message(%{response_message: ctor, kind: "firmware_version", preview: preview})
      when is_binary(ctor) and ctor != "" do
    case firmware_version_wire_record(preview) do
      %{} = version ->
        "#{ctor} { major = #{version["major"]}, minor = #{version["minor"]}, patch = #{version["patch"]} }"

      _ ->
        ctor
    end
  end

  def response_message(%{response_message: ctor}) when is_binary(ctor), do: ctor
  def response_message(_req), do: nil

  @doc false
  @spec response_wire_for_callback(
          Types.elm_introspect(),
          Types.app_model(),
          String.t(),
          String.t() | nil
        ) :: Types.protocol_ctor_value() | nil
  def response_wire_for_callback(ei, model, ctor, current_message)
      when is_map(model) and is_binary(ctor) and ctor != "" do
    case device_kind_for_callback(ei, ctor) do
      kind when is_binary(kind) ->
        %{kind: kind, response_message: ctor}
        |> finalize_request(model, current_message)
        |> response_wire_value()

      _ ->
        nil
    end
  end

  def response_wire_for_callback(_ei, _model, _ctor, _current_message), do: nil

  @spec device_kind_for_callback(Types.elm_introspect(), String.t()) :: String.t() | nil
  defp device_kind_for_callback(ei, ctor) when is_map(ei) and is_binary(ctor) do
    ["init_cmd_calls", "update_cmd_calls"]
    |> Enum.reduce_while(nil, fn key, _acc ->
      case cmd_calls_for(ei, key) do
        calls when is_list(calls) ->
          kind =
            Enum.find_value(calls, fn call ->
              callback = Map.get(call, "callback_constructor") || Map.get(call, :callback_constructor)

              if callback == ctor do
                case DeviceRequest.from_cmd_call(call) do
                  [%{kind: kind} | _] -> kind
                  _ -> nil
                end
              end
            end)

          if is_binary(kind), do: {:halt, kind}, else: :cont

        _ ->
          :cont
      end
    end)
  end

  defp device_kind_for_callback(_ei, _ctor), do: nil

  @spec response_wire_value(Types.device_request()) :: Types.protocol_ctor_value() | nil
  def response_wire_value(%{response_message: ctor, kind: "current_date_time", preview: preview})
      when is_binary(ctor) and ctor != "" and is_map(preview) do
    %{"ctor" => ctor, "args" => [current_date_time_message_payload(preview)]}
  end

  def response_wire_value(%{
        response_message: ctor,
        kind: "current_time_string",
        preview: %{"string" => value}
      })
      when is_binary(ctor) and ctor != "" and is_binary(value) do
    %{"ctor" => ctor, "args" => [value]}
  end

  def response_wire_value(%{response_message: ctor, kind: kind, preview: preview})
      when is_binary(ctor) and ctor != "" and
             kind in ["battery_level", "connection_status"] and is_map(preview) do
    value =
      case {kind, preview} do
        {"battery_level", %{"batteryLevel" => level}} -> level
        {"connection_status", %{"connected" => connected}} -> connected
        _ -> preview
      end

    %{"ctor" => ctor, "args" => [value]}
  end

  def response_wire_value(%{response_message: ctor, kind: kind, preview: preview})
      when is_binary(ctor) and ctor != "" and
             kind in ["clock_style_24h", "timezone_is_set"] and is_boolean(preview) do
    %{"ctor" => ctor, "args" => [preview]}
  end

  def response_wire_value(%{response_message: ctor, kind: kind, preview: preview})
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

    %{"ctor" => ctor, "args" => [value]}
  end

  def response_wire_value(%{response_message: ctor, kind: "watch_model", preview: preview})
      when is_binary(ctor) and ctor != "" do
    %{"ctor" => ctor, "args" => [%{"ctor" => watch_info_model_ctor_literal(preview), "args" => []}]}
  end

  def response_wire_value(%{response_message: ctor, kind: "watch_color", preview: preview})
      when is_binary(ctor) and ctor != "" do
    %{"ctor" => ctor, "args" => [%{"ctor" => watch_info_color_ctor_literal(preview), "args" => []}]}
  end

  def response_wire_value(%{response_message: ctor, kind: "firmware_version", preview: preview})
      when is_binary(ctor) and ctor != "" do
    case firmware_version_wire_record(preview) do
      %{} = version -> %{"ctor" => ctor, "args" => [version]}
      _ -> %{"ctor" => ctor, "args" => []}
    end
  end

  def response_wire_value(_req), do: nil

  def elm_literal(value) when is_boolean(value), do: if(value, do: "True", else: "False")
  def elm_literal(value) when is_integer(value), do: Integer.to_string(value)
  def elm_literal(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  def elm_literal(value) when is_binary(value), do: inspect(value)
  def elm_literal(value), do: inspect(value)

  @spec current_date_time_message_payload(Types.wire_map()) :: Types.wire_map()
  def current_date_time_message_payload(preview) when is_map(preview) do
    Map.update(preview, "dayOfWeek", nil, fn
      value when is_binary(value) -> %{"ctor" => value, "args" => []}
      value -> value
    end)
  end

  @spec health_metric_request_disabled?(Types.app_model(), Types.device_request()) :: boolean()
  def health_metric_request_disabled?(model, %{kind: kind})
       when is_map(model) and kind in ["health_value", "health_sum_today", "health_sum", "health_accessible"] do
    launch_context = Map.get(model, "launch_context") || %{}

    health_runtime_disabled?(Map.get(model, "runtime_model") || %{}) or
      Map.get(launch_context, "supports_health") != true
  end

  def health_metric_request_disabled?(_model, _req), do: false

  @spec health_runtime_disabled?(Types.inner_runtime_model()) :: boolean()
  def health_runtime_disabled?(%{"supported" => %{"ctor" => "Just", "args" => [false]}}), do: true
  def health_runtime_disabled?(%{"supported" => %{"ctor" => "Just", "args" => [true]}}), do: false
  def health_runtime_disabled?(_runtime_model), do: false
  @spec init_request_already_satisfied?(Types.app_model(), Types.device_request()) :: boolean()
  def init_request_already_satisfied?(model, %{kind: kind})
       when is_map(model) and is_binary(kind) do
    Map.has_key?(model, "debugger_device_#{kind}")
  end

  def init_request_already_satisfied?(_model, _req), do: false
  @spec finalize_request(Types.device_request(), Types.app_model(), String.t() | nil) ::
          Types.device_request()
  def finalize_request(%{kind: "current_time_string"} = req, model, current_message) do
    now = now_from_model(model, current_message)
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

  def finalize_request(%{kind: "current_date_time"} = req, model, current_message) do
    now = now_from_model(model, current_message)
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

  def finalize_request(%{kind: "battery_level"} = req, model, _current_message) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"batteryLevel" => settings["battery_percent"]})
  end

  def finalize_request(%{kind: "connection_status"} = req, model, _current_message) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"connected" => settings["connected"]})
  end

  def finalize_request(%{kind: "clock_style_24h"} = req, model, _current_message) do
    settings = settings_from_model(model)
    Map.put(req, :preview, settings["clock_24h"])
  end

  def finalize_request(%{kind: "timezone_is_set"} = req, _model, _current_message),
    do: Map.put(req, :preview, true)

  def finalize_request(%{kind: "timezone"} = req, _model, _current_message) do
    tz = System.get_env("TZ") || "UTC"
    Map.put(req, :preview, tz)
  end

  def finalize_request(%{kind: "watch_model"} = req, model, _current_message) when is_map(model) do
    launch_context = Map.get(model, "launch_context") || %{}
    Map.put(req, :preview, launch_context)
  end

  def finalize_request(%{kind: "watch_color"} = req, model, _current_message) when is_map(model) do
    launch_context = Map.get(model, "launch_context") || %{}
    Map.put(req, :preview, launch_context)
  end

  def finalize_request(%{kind: "firmware_version"} = req, _model, _current_message),
    do: Map.put(req, :preview, "v4.4.0-sim")

  def finalize_request(%{kind: "health_value"} = req, model, _current_message) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps"]})
  end

  def finalize_request(%{kind: "health_supported"} = req, model, _current_message) do
    launch_context = Map.get(model, "launch_context") || %{}
    supported = Map.get(launch_context, "supports_health") == true
    Map.put(req, :preview, supported)
  end

  def finalize_request(%{kind: "health_sum_today"} = req, model, _current_message) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps_today"]})
  end

  def finalize_request(%{kind: "health_sum"} = req, model, _current_message) do
    settings = settings_from_model(model)
    Map.put(req, :preview, %{"value" => settings["health_steps_today"]})
  end

  def finalize_request(%{kind: "health_accessible"} = req, _model, _current_message),
    do: Map.put(req, :preview, true)

  def finalize_request(req, _model, _current_message), do: Map.put(req, :preview, nil)

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

  @spec requests_for_message(
          Types.elm_introspect(),
          Types.app_model(),
          String.t(),
          keyword()
        ) :: [Types.device_request()]
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
    |> Enum.map(&finalize_request(&1, model, current_message))
  end

  def requests_for_message(_ei, _model, _current_message, _opts), do: []

  @spec cmd_calls_for(Types.elm_introspect(), String.t()) :: [Types.cmd_call()]
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

  @spec watch_info_model_ctor_literal(Types.wire_map() | String.t()) :: String.t()
  defp watch_info_model_ctor_literal(launch_context) when is_map(launch_context) do
    WatchModels.watch_info_model_ctor_from_launch_context(launch_context)
  end

  defp watch_info_model_ctor_literal(preview) when is_binary(preview), do: preview

  @spec watch_info_color_ctor_literal(Types.wire_map() | String.t()) :: String.t()
  defp watch_info_color_ctor_literal(launch_context) when is_map(launch_context) do
    WatchModels.watch_info_color_ctor_from_launch_context(launch_context)
  end

  defp watch_info_color_ctor_literal(preview) when is_binary(preview), do: preview

  @spec firmware_version_wire_record(String.t() | Types.wire_map() | nil) :: Types.wire_map() | nil
  def firmware_version_wire_record(version) when is_binary(version) do
    trimmed =
      version
      |> String.trim()
      |> String.trim_leading("v")

    case String.split(trimmed, "-", parts: 2) do
      [core, _suffix] -> parse_firmware_version_core(core)
      [core] -> parse_firmware_version_core(core)
      _ -> nil
    end
  end

  def firmware_version_wire_record(_version), do: nil

  defp parse_firmware_version_core(core) when is_binary(core) do
    parts =
      core
      |> String.split(".")
      |> Enum.map(fn part ->
        case Integer.parse(part) do
          {value, ""} -> value
          _ -> 0
        end
      end)

    case parts do
      [major, minor, patch] -> %{"major" => major, "minor" => minor, "patch" => patch}
      [major, minor] -> %{"major" => major, "minor" => minor, "patch" => 0}
      [major] -> %{"major" => major, "minor" => 0, "patch" => 0}
      _ -> nil
    end
  end

end
