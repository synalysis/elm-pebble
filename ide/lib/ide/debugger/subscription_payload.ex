defmodule Ide.Debugger.SubscriptionPayload do
  @moduledoc false

  alias Ide.Debugger.CompanionSubscriptionTrigger
  alias Ide.Debugger.DeviceData
  alias Ide.Debugger.RuntimeActiveSubscriptions
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.TimelineMessage
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  @type attach_ctx :: %{
          optional(:introspect) => (Types.runtime_state(), Types.surface_target() ->
                                      Types.elm_introspect() | nil),
          optional(:settings) => (Types.runtime_state() -> Types.simulator_settings())
        }

  @spec attach(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          attach_ctx() | nil
        ) ::
          String.t()
  def attach(state, target, message, trigger, ctx \\ nil)

  def attach(state, target, message, trigger, ctx)
      when is_map(state) and is_binary(message) and is_binary(trigger) do
    message_text = String.trim(message)

    cond do
      message_text == "" ->
        message

      message_has_payload?(message_text) ->
        message

      CompanionSubscriptionTrigger.companion_trigger?(trigger) ->
        message

      true ->
        case RuntimeActiveSubscriptions.format_step_message(state, target, trigger, message_text) do
          {:ok, stepped, value} when is_binary(stepped) ->
            if message_has_payload?(stepped) do
              stepped
            else
              runtime_formatted_message(message_text, value) ||
                attach_simulator_stub(state, target, message_text, trigger, ctx)
            end

          _ ->
            runtime_formatted_message(
              message_text,
              RuntimeActiveSubscriptions.message_value_for(state, target, trigger, message_text)
            ) ||
              attach_simulator_stub(state, target, message_text, trigger, ctx)
        end
    end
  end

  def attach(_state, _target, message, _trigger, _ctx) when is_binary(message), do: message

  @spec runtime_formatted_message(String.t(), Types.subscription_payload() | nil) ::
          String.t() | nil
  defp runtime_formatted_message(message_text, value) when is_binary(message_text) do
    case value do
      %{} = wire_value ->
        formatted = TimelineMessage.format(message_text, wire_value)

        if message_has_payload?(formatted) do
          formatted
        else
          nil
        end

      _ ->
        nil
    end
  end

  @spec message_has_payload?(String.t()) :: boolean()
  def message_has_payload?(message) when is_binary(message) do
    case String.split(message, ~r/\s+/, parts: 2) do
      [_ctor, payload] -> String.trim(payload) != ""
      _ -> false
    end
  end

  @spec ensure_message_payload(String.t() | nil, Types.subscription_payload() | nil) ::
          String.t() | nil
  def ensure_message_payload(message, message_value) do
    cond do
      is_binary(message) and message != "" and message_has_payload?(message) ->
        message

      true ->
        case explicit_payload_text(message, message_value) do
          payload when is_binary(payload) and payload != "" ->
            ctor =
              message
              |> case do
                msg when is_binary(msg) and msg != "" ->
                  RuntimeModelMessages.wire_constructor(msg) || String.trim(msg)

                _ ->
                  wire_ctor_from_value(message_value)
              end

            if is_binary(ctor) and ctor != "" do
              "#{ctor} #{payload}"
            else
              message
            end

          _ ->
            message
        end
    end
  end

  @spec sync_simulator_clock_from_subscription(
          Types.runtime_state(),
          String.t(),
          Types.subscription_payload() | nil
        ) :: Types.runtime_state()
  def sync_simulator_clock_from_subscription(state, message, message_value)
      when is_map(state) and is_binary(message) do
    overrides = DeviceData.subscription_clock_overrides(message, message_value)

    if map_size(overrides) > 0 do
      settings = DebuggerSimulatorSettings.from_state(state)

      if settings["use_simulated_time"] == true do
        now = simulator_now_from_settings(settings)
        next = DeviceData.apply_subscription_clock_overrides(now, overrides)

        next_settings = %{
          settings
          | "simulated_date" => next |> NaiveDateTime.to_date() |> Date.to_iso8601(),
            "simulated_time" => next |> NaiveDateTime.to_time() |> format_simulated_time()
        }

        state
        |> Map.put(:simulator_settings, next_settings)
        |> Ide.Debugger.SimulatorSurfaceSettings.apply_to_state()
      else
        state
      end
    else
      state
    end
  end

  def sync_simulator_clock_from_subscription(state, _message, _message_value) when is_map(state),
    do: state

  @spec frame_subscription_trigger?(String.t()) :: boolean()
  def frame_subscription_trigger?(trigger) when is_binary(trigger) do
    normalized =
      trigger
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "")

    String.contains?(normalized, "frame") or String.contains?(normalized, "onframe")
  end

  @spec advance_simulator_clock_for_auto_fire(Types.runtime_state(), String.t()) ::
          Types.runtime_state()
  def advance_simulator_clock_for_auto_fire(state, trigger)
      when is_map(state) and is_binary(trigger) do
    settings = DebuggerSimulatorSettings.from_state(state)

    if settings["use_simulated_time"] == true do
      case clock_unit_for_trigger(state, trigger) do
        unit when unit in [:second, :minute, :hour, :day, :month, :year] ->
          now = simulator_now_from_settings(settings)
          next = advance_naive_datetime(now, unit)

          next_settings = %{
            settings
            | "simulated_date" => next |> NaiveDateTime.to_date() |> Date.to_iso8601(),
              "simulated_time" => next |> NaiveDateTime.to_time() |> format_simulated_time()
          }

          state
          |> Map.put(:simulator_settings, next_settings)
          |> Ide.Debugger.SimulatorSurfaceSettings.apply_to_state()

        _ ->
          state
      end
    else
      state
    end
  end

  def advance_simulator_clock_for_auto_fire(state, _trigger) when is_map(state), do: state

  @spec attach_simulator_stub(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          attach_ctx() | nil
        ) :: String.t()
  defp attach_simulator_stub(state, target, message_text, trigger, ctx) do
    row = %{trigger: trigger, message: message_text}
    cmd = RuntimeActiveSubscriptions.match_for_row(state, target, row)
    cmd_target = if cmd, do: RuntimeActiveSubscriptions.command_target(cmd), else: ""

    case simulator_stub_suffix(state, target, message_text, cmd_target, ctx) do
      suffix when is_binary(suffix) and suffix != "" -> "#{message_text} #{suffix}"
      _ -> message_text
    end
  end

  @spec simulator_stub_suffix(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t(),
          attach_ctx() | nil
        ) :: String.t() | nil
  defp simulator_stub_suffix(state, target, _message_text, cmd_target, ctx) do
    normalized = normalize_target(cmd_target)
    now = simulator_now_for_target(state, target)

    cond do
      frame_target?(normalized) ->
        Jason.encode!(subscription_frame_payload(state, target))

      clock_target?(normalized, "secondchange") or clock_target?(normalized, "onsecond") ->
        Integer.to_string(now.second)

      clock_target?(normalized, "minutechange") or clock_target?(normalized, "onminute") ->
        Integer.to_string(now.minute)

      clock_target?(normalized, "hourchange") or clock_target?(normalized, "onhour") ->
        Integer.to_string(now.hour)

      clock_target?(normalized, "daychange") or clock_target?(normalized, "onday") ->
        Integer.to_string(now.day)

      clock_target?(normalized, "monthchange") or clock_target?(normalized, "onmonth") ->
        Integer.to_string(now.month)

      clock_target?(normalized, "yearchange") or clock_target?(normalized, "onyear") ->
        Integer.to_string(now.year)

      String.contains?(normalized, "onbatterychange") or String.contains?(normalized, "batterychange") ->
        Integer.to_string(subscription_battery_level(state, target, ctx))

      String.contains?(normalized, "onconnectionchange") or
          String.contains?(normalized, "connectionchange") ->
        subscription_connection_status(state, target, ctx)

      String.contains?(normalized, "oncompasschange") or String.contains?(normalized, "compasschange") ->
        Jason.encode!(subscription_compass_heading(state, target, ctx))

      String.contains?(normalized, "onappfocuschange") or String.contains?(normalized, "appfocuschange") ->
        subscription_app_focus_state(state, target, ctx)

      String.contains?(normalized, "onbacklightchange") or String.contains?(normalized, "backlightchange") ->
        if Map.get(resolve_settings(state, ctx), "backlight_on", true) == true, do: "On", else: "Off"

      String.contains?(normalized, "onscreenchange") or String.contains?(normalized, "screenchange") ->
        Jason.encode!(subscription_screen_payload(state, target, ctx))

      String.contains?(normalized, "unobstructedwillchange") ->
        Jason.encode!(subscription_unobstructed_rect(state, target, ctx))

      String.contains?(normalized, "unobstructedchanging") ->
        Integer.to_string(subscription_unobstructed_progress(state))

      String.contains?(normalized, "dictationstatus") ->
        subscription_dictation_status(state, target, ctx)

      String.contains?(normalized, "dictationresult") ->
        Jason.encode!(subscription_dictation_result_payload(state, target, ctx))

      true ->
        nil
    end
  end

  defp normalize_target(target) when is_binary(target) do
    target |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
  end

  defp normalize_target(_), do: ""

  defp frame_target?(normalized) do
    String.contains?(normalized, "frameevery") or String.contains?(normalized, "frameatfps") or
      String.contains?(normalized, "onframe")
  end

  defp clock_target?(normalized, fragment) do
    String.contains?(normalized, fragment)
  end

  defp resolve_settings(state, ctx) do
    case Map.get(ctx || %{}, :settings) do
      fun when is_function(fun, 1) -> fun.(state)
      _ -> DebuggerSimulatorSettings.from_state(state)
    end
  end

  @spec explicit_payload_text(String.t() | nil, Types.subscription_payload() | nil) ::
          String.t() | nil
  defp explicit_payload_text(_message, value) when is_integer(value), do: Integer.to_string(value)

  defp explicit_payload_text(_message, %{"args" => [head | _]}) when is_integer(head),
    do: Integer.to_string(head)

  defp explicit_payload_text(_message, %{args: [head | _]}) when is_integer(head),
    do: Integer.to_string(head)

  defp explicit_payload_text(_message, _value), do: nil

  @spec wire_ctor_from_value(Types.subscription_payload() | nil) :: String.t() | nil
  defp wire_ctor_from_value(%{"ctor" => ctor}) when is_binary(ctor), do: ctor
  defp wire_ctor_from_value(%{ctor: ctor}) when is_binary(ctor), do: ctor
  defp wire_ctor_from_value(_value), do: nil

  @spec simulator_now_for_target(Types.runtime_state(), Types.surface_target()) ::
          NaiveDateTime.t()
  def simulator_now_for_target(state, target)
      when is_map(state) and target in [:watch, :companion, :phone] do
    state
    |> get_in([target, :model])
    |> simulator_now_from_model()
  end

  @spec subscription_compass_heading(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) :: Types.simulator_compass_heading()
  defp subscription_compass_heading(state, _target, ctx) when is_map(state) do
    settings = resolve_settings(state, ctx)

    %{
      "degrees" => Map.get(settings, "compass_heading_deg", 0) / 1.0,
      "isValid" => Map.get(settings, "compass_valid", true) == true
    }
  end

  @spec subscription_app_focus_state(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) :: String.t()
  defp subscription_app_focus_state(state, _target, ctx) when is_map(state) do
    settings = resolve_settings(state, ctx)

    if Map.get(settings, "app_in_focus", true) == true, do: "InFocus", else: "OutOfFocus"
  end

  @spec subscription_screen_payload(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) :: Types.simulator_screen_payload()
  defp subscription_screen_payload(state, _target, _ctx) when is_map(state) do
    launch_context =
      get_in(state, [:watch, :model, "launch_context"]) ||
        get_in(state, [:watch, :model, "runtime_model", "launch_context"]) ||
        %{}

    screen = Map.get(launch_context, "screen") || %{}

    %{
      "width" => Map.get(screen, "width") || 144,
      "height" => Map.get(screen, "height") || 168,
      "shape" => Map.get(screen, "shape") || "Rectangular",
      "colorMode" => Map.get(screen, "color_mode") || Map.get(screen, "colorMode") || "Color"
    }
  end

  @spec subscription_unobstructed_rect(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) :: Types.simulator_rect_payload()
  defp subscription_unobstructed_rect(state, _target, ctx) when is_map(state) do
    settings = resolve_settings(state, ctx)

    launch_context =
      get_in(state, [:watch, :model, "launch_context"]) ||
        get_in(state, [:watch, :model, "runtime_model", "launch_context"]) ||
        %{}

    width = get_in(launch_context, ["screen", "width"]) || 144
    height = get_in(launch_context, ["screen", "height"]) || 168
    peek? = Map.get(settings, "timeline_peek", false) == true
    inset = min(32, div(height, 4))

    if peek? do
      %{"x" => 0, "y" => inset, "w" => width, "h" => height - inset}
    else
      %{"x" => 0, "y" => 0, "w" => width, "h" => height}
    end
  end

  @spec subscription_unobstructed_progress(Types.runtime_state()) :: integer()
  defp subscription_unobstructed_progress(_state), do: 255

  @spec subscription_dictation_status(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) :: String.t()
  defp subscription_dictation_status(state, _target, ctx) when is_map(state) do
    settings = resolve_settings(state, ctx)

    case blank_string?(Map.get(settings, "dictation_error")) do
      true -> "Finished"
      false -> "Recognizing"
    end
  end

  @spec subscription_dictation_result_payload(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) :: Types.protocol_ctor_value()
  defp subscription_dictation_result_payload(state, _target, ctx) when is_map(state) do
    settings = resolve_settings(state, ctx)

    case blank_string?(Map.get(settings, "dictation_error")) do
      true ->
        %{"ctor" => "Ok", "args" => [Map.get(settings, "dictation_transcript", "")]}

      false ->
        %{
          "ctor" => "Err",
          "args" => [%{"ctor" => "Failed", "args" => [Map.get(settings, "dictation_error", "")]}]
        }
    end
  end

  @spec blank_string?(Types.wire_scalar() | Types.protocol_ctor_value() | list()) :: boolean()
  defp blank_string?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_string?(_value), do: true

  @spec subscription_frame_payload(Types.runtime_state(), Types.surface_target()) ::
          Types.wire_map()
  defp subscription_frame_payload(state, target) when is_map(state) do
    model =
      case target do
        surface when surface in [:watch, :companion, :phone] ->
          get_in(state, [surface, :model]) || %{}

        _ ->
          %{}
      end

    frame =
      model
      |> Map.get("_debugger_steps")
      |> normalize_integer(0)
      |> max(0)
      |> Kernel.+(1)

    dt_ms = 16

    %{
      "dtMs" => dt_ms,
      "elapsedMs" => frame * dt_ms,
      "frame" => frame
    }
  end

  @spec subscription_battery_level(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) :: integer()
  defp subscription_battery_level(state, target, ctx) when is_map(state) do
    settings = resolve_settings(state, ctx)

    state
    |> subscription_runtime_value(target, "batteryLevel")
    |> unwrap_elm_maybe()
    |> normalize_integer(settings["battery_percent"])
    |> min(100)
    |> max(0)
  end

  @spec subscription_connection_status(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) :: String.t()
  defp subscription_connection_status(state, target, ctx) when is_map(state) do
    settings = resolve_settings(state, ctx)

    state
    |> subscription_runtime_value(target, "connected")
    |> unwrap_elm_maybe()
    |> normalize_boolean(settings["connected"])
    |> then(fn
      true -> "True"
      false -> "False"
    end)
  end

  @spec subscription_runtime_value(Types.runtime_state(), Types.surface_target(), String.t()) ::
          Types.protocol_wire_arg() | nil
  defp subscription_runtime_value(state, target, key) when is_map(state) and is_binary(key) do
    with surface when surface in [:watch, :companion, :phone] <- target,
         runtime_model when is_map(runtime_model) <-
           get_in(state, [surface, :model, "runtime_model"]) do
      Map.get(runtime_model, key)
    else
      _ -> nil
    end
  end

  @spec unwrap_elm_maybe(Types.subscription_payload()) :: Types.subscription_payload()
  defp unwrap_elm_maybe(%{"ctor" => "Just", "args" => [value | _]}), do: value
  defp unwrap_elm_maybe(%{ctor: "Just", args: [value | _]}), do: value
  defp unwrap_elm_maybe(value), do: value

  @spec normalize_integer(Types.wire_input(), integer()) :: integer()
  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) and is_integer(default) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> default
    end
  end

  defp normalize_integer(_value, default) when is_integer(default), do: default

  @spec normalize_boolean(Types.wire_input(), boolean()) :: boolean()
  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean("True", _default), do: true
  defp normalize_boolean("False", _default), do: false
  defp normalize_boolean("true", _default), do: true
  defp normalize_boolean("false", _default), do: false
  defp normalize_boolean(_value, default) when is_boolean(default), do: default

  @spec simulator_now_from_model(Types.app_model()) :: NaiveDateTime.t()
  defp simulator_now_from_model(model) do
    model
    |> DebuggerSimulatorSettings.from_model()
    |> simulator_now_from_settings()
  end

  @spec simulator_now_from_settings(Types.simulator_settings()) :: NaiveDateTime.t()
  defp simulator_now_from_settings(settings) when is_map(settings) do
    fallback = NaiveDateTime.local_now()

    if settings["use_simulated_time"] == true do
      date = parse_simulated_date(settings["simulated_date"], NaiveDateTime.to_date(fallback))
      time = parse_simulated_time(settings["simulated_time"], NaiveDateTime.to_time(fallback))

      NaiveDateTime.new!(date, time)
    else
      fallback
    end
  end

  @spec parse_simulated_date(Types.wire_input(), Date.t()) :: Date.t()
  defp parse_simulated_date(value, fallback) when is_binary(value) do
    case Date.from_iso8601(String.trim(value)) do
      {:ok, date} -> date
      {:error, _reason} -> fallback
    end
  end

  defp parse_simulated_date(_value, fallback), do: fallback

  @spec parse_simulated_time(Types.wire_input(), Time.t()) :: Time.t()
  defp parse_simulated_time(value, fallback) when is_binary(value) do
    text = String.trim(value)
    normalized = if Regex.match?(~r/^\d{1,2}:\d{2}$/, text), do: text <> ":00", else: text

    case Time.from_iso8601(normalized) do
      {:ok, time} -> Time.truncate(time, :second)
      {:error, _reason} -> fallback
    end
  end

  defp parse_simulated_time(_value, fallback), do: fallback

  @spec clock_unit_for_trigger(Types.runtime_state(), String.t()) ::
          :second | :minute | :hour | :day | :month | :year | nil
  defp clock_unit_for_trigger(state, trigger) when is_map(state) and is_binary(trigger) do
    active = RuntimeActiveSubscriptions.for_surface(state, :watch)

    target =
      active
      |> Enum.find_value(fn command ->
        id = RuntimeActiveSubscriptions.command_target(command)

        if TriggerCandidates.normalize_trigger_id(trigger) ==
             command_trigger_for_target(id) do
          id
        end
      end) || trigger

    normalized = normalize_target(target)

    cond do
      clock_target?(normalized, "secondchange") or clock_target?(normalized, "onsecond") ->
        :second

      clock_target?(normalized, "minutechange") or clock_target?(normalized, "onminute") ->
        :minute

      clock_target?(normalized, "hourchange") or clock_target?(normalized, "onhour") ->
        :hour

      clock_target?(normalized, "daychange") or clock_target?(normalized, "onday") ->
        :day

      clock_target?(normalized, "monthchange") or clock_target?(normalized, "onmonth") ->
        :month

      clock_target?(normalized, "yearchange") or clock_target?(normalized, "onyear") ->
        :year

      true ->
        nil
    end
  end

  defp command_trigger_for_target(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
    |> then(&Ide.Debugger.TriggerCandidates.normalize_trigger_id/1)
  end

  @spec advance_naive_datetime(
          NaiveDateTime.t(),
          :second | :minute | :hour | :day | :month | :year
        ) :: NaiveDateTime.t()
  defp advance_naive_datetime(%NaiveDateTime{} = now, :second),
    do: NaiveDateTime.add(now, 1, :second)

  defp advance_naive_datetime(%NaiveDateTime{} = now, :minute),
    do: NaiveDateTime.add(now, 1, :minute)

  defp advance_naive_datetime(%NaiveDateTime{} = now, :hour), do: NaiveDateTime.add(now, 1, :hour)
  defp advance_naive_datetime(%NaiveDateTime{} = now, :day), do: NaiveDateTime.add(now, 1, :day)

  defp advance_naive_datetime(%NaiveDateTime{} = now, :month) do
    shift_naive_date(now, month: 1)
  end

  defp advance_naive_datetime(%NaiveDateTime{} = now, :year) do
    shift_naive_date(now, year: 1)
  end

  @spec shift_naive_date(NaiveDateTime.t(), keyword()) :: NaiveDateTime.t()
  defp shift_naive_date(%NaiveDateTime{} = now, shifts) when is_list(shifts) do
    date = now |> NaiveDateTime.to_date() |> Date.shift(shifts)
    time = NaiveDateTime.to_time(now)

    {:ok, shifted} = NaiveDateTime.new(date, time)
    shifted
  end

  @spec format_simulated_time(Time.t()) :: String.t()
  defp format_simulated_time(%Time{} = time) do
    time
    |> Time.truncate(:second)
    |> Time.to_iso8601()
  end
end
