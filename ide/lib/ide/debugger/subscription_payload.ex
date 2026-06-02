defmodule Ide.Debugger.SubscriptionPayload do
  @moduledoc false

  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.Types

  @type attach_ctx :: %{
          optional(:introspect) => (map(), Types.surface_target() ->
                                      Types.elm_introspect() | map() | nil),
          optional(:settings) => (map() -> map())
        }

  defp resolve_introspect(state, target, ctx) do
    case Map.get(ctx || %{}, :introspect) do
      fun when is_function(fun, 2) -> fun.(state, target) || %{}
      _ -> %{}
    end
  end

  defp resolve_settings(state, ctx) do
    case Map.get(ctx || %{}, :settings) do
      fun when is_function(fun, 1) -> fun.(state)
      _ -> DebuggerSimulatorSettings.from_state(state)
    end
  end

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

    if message_text == "" or message_has_payload?(message_text) do
      message
    else
      now = simulator_now_for_target(state, target)
      # `subscription_event_kind/1` turns e.g. `PebbleEvents.onHourChange` into `on_hour_change`.
      # Match after removing punctuation so "on_hour_change", "onHourChange", and "onhourchange"
      # all line up the same way.
      t =
        trigger
        |> to_string()
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9]/, "")

      cond do
        Ide.Debugger.CompanionSubscriptionTrigger.companion_trigger?(trigger) ->
          message

        frame_subscription_trigger?(trigger) and
            subscription_message_arity(state, target, message_text, ctx) == 1 ->
          "#{message_text} #{Jason.encode!(subscription_frame_payload(state, target))}"

        (String.contains?(t, "secondchange") or String.contains?(t, "onsecond")) and
            subscription_message_arity(state, target, message_text, ctx) == 1 ->
          "#{message_text} #{now.second}"

        # Minute before hour so a hypothetical name containing both substrings is unambiguous.
        String.contains?(t, "minutechange") or String.contains?(t, "onminute") ->
          "#{message_text} #{now.minute}"

        String.contains?(t, "hourchange") or String.contains?(t, "onhour") ->
          "#{message_text} #{now.hour}"

        String.contains?(t, "daychange") or String.contains?(t, "onday") ->
          "#{message_text} #{now.day}"

        String.contains?(t, "monthchange") or String.contains?(t, "onmonth") ->
          "#{message_text} #{now.month}"

        String.contains?(t, "yearchange") or String.contains?(t, "onyear") ->
          "#{message_text} #{now.year}"

        String.contains?(t, "batterychange") or String.contains?(t, "onbattery") ->
          "#{message_text} #{subscription_battery_level(state, target, ctx)}"

        String.contains?(t, "connectionchange") or String.contains?(t, "onconnection") ->
          "#{message_text} #{subscription_connection_status(state, target, ctx)}"

        String.contains?(t, "compasschange") or String.contains?(t, "oncompass") ->
          compass_payload = subscription_compass_heading(state, target, ctx)

          if subscription_message_arity(state, target, message_text, ctx) == 1 do
            "#{message_text} #{Jason.encode!(compass_payload)}"
          else
            message
          end

        String.contains?(t, "appfocuschange") or String.contains?(t, "onappfocus") ->
          focus_state = subscription_app_focus_state(state, target, ctx)

          if subscription_message_arity(state, target, message_text, ctx) == 1 do
            "#{message_text} #{focus_state}"
          else
            message
          end

        String.contains?(t, "unobstructedwillchange") or String.contains?(t, "onunobstructedwill") ->
          rect = subscription_unobstructed_rect(state, target, ctx)

          if subscription_message_arity(state, target, message_text, ctx) == 1 do
            "#{message_text} #{Jason.encode!(rect)}"
          else
            message
          end

        String.contains?(t, "unobstructedchanging") or String.contains?(t, "onunobstructedchang") ->
          progress = subscription_unobstructed_progress(state)

          if subscription_message_arity(state, target, message_text, ctx) == 1 do
            "#{message_text} #{progress}"
          else
            message
          end

        String.contains?(t, "dictationstatus") or String.contains?(t, "ondictationstatus") ->
          status = subscription_dictation_status(state, target, ctx)

          if subscription_message_arity(state, target, message_text, ctx) == 1 do
            "#{message_text} #{status}"
          else
            message
          end

        String.contains?(t, "dictationresult") or String.contains?(t, "ondictationresult") ->
          result_payload = subscription_dictation_result_payload(state, target, ctx)

          if subscription_message_arity(state, target, message_text, ctx) == 1 do
            "#{message_text} #{Jason.encode!(result_payload)}"
          else
            message
          end

        subscription_message_arity(state, target, message_text, ctx) == 1 ->
          case subscription_simulated_arg(state, target, message_text, ctx) do
            {:ok, arg} -> "#{message_text} #{arg}"
            :error -> message
          end

        true ->
          message
      end
    end
  end

  def attach(_state, _target, message, _trigger, _ctx) when is_binary(message), do: message

  @spec message_has_payload?(String.t()) :: boolean()
  defp message_has_payload?(message) when is_binary(message) do
    case String.split(message, ~r/\s+/, parts: 2) do
      [_ctor, payload] -> String.trim(payload) != ""
      _ -> false
    end
  end

  @spec simulator_now_for_target(Types.runtime_state(), :watch | :companion | :phone) ::
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
        ) ::
          map()
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
        ) ::
          String.t()
  defp subscription_app_focus_state(state, _target, ctx) when is_map(state) do
    settings = resolve_settings(state, ctx)

    if Map.get(settings, "app_in_focus", true) == true, do: "InFocus", else: "OutOfFocus"
  end

  @spec subscription_unobstructed_rect(
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) ::
          map()
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
        ) ::
          String.t()
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
        ) ::
          map()
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

  @spec subscription_simulated_arg(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          attach_ctx() | nil
        ) ::
          {:ok, String.t()} | :error
  defp subscription_simulated_arg(state, target, constructor, ctx)
       when is_map(state) and is_binary(constructor) do
    with %{} = ei <- resolve_introspect(state, target, ctx),
         arg_type when is_binary(arg_type) <-
           Map.get(ei, "msg_constructor_arg_types", %{}) |> Map.get(constructor) do
      simulated_value_for_msg_arg_type(arg_type, state, target, ctx)
    else
      _ -> :error
    end
  end

  @spec simulated_value_for_msg_arg_type(
          String.t(),
          Types.runtime_state(),
          Types.surface_target(),
          attach_ctx() | nil
        ) ::
          {:ok, String.t()} | :error
  defp simulated_value_for_msg_arg_type(type, state, target, ctx) when is_binary(type) do
    normalized =
      type
      |> String.replace(" ", "")
      |> String.downcase()

    cond do
      String.contains?(normalized, "appfocus") and String.ends_with?(normalized, "state") ->
        {:ok, subscription_app_focus_state(state, target, ctx)}

      true ->
        :error
    end
  end

  @spec subscription_message_arity(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          attach_ctx() | nil
        ) ::
          non_neg_integer()
  defp subscription_message_arity(state, target, message, ctx)
       when is_map(state) and is_binary(message) do
    case resolve_introspect(state, target, ctx) do
      %{"msg_constructor_arities" => arities} when is_map(arities) ->
        arities
        |> Map.get(message, 0)
        |> normalize_integer(0)

      %{} = ei ->
        case Map.get(ei, "msg_constructor_arities") do
          arities when is_map(arities) ->
            arities
            |> Map.get(message, 0)
            |> normalize_integer(0)

          _ ->
            0
        end

      _ ->
        0
    end
  end

  @spec frame_subscription_trigger?(String.t()) :: boolean()
  def frame_subscription_trigger?(trigger) when is_binary(trigger) do
    normalized =
      trigger
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "")

    String.contains?(normalized, "frame") or String.contains?(normalized, "onframe")
  end

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
        ) ::
          integer()
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
        ) ::
          String.t()
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

  @spec advance_simulator_clock_for_auto_fire(Types.runtime_state(), String.t()) ::
          Types.runtime_state()
  def advance_simulator_clock_for_auto_fire(state, trigger)
      when is_map(state) and is_binary(trigger) do
    settings = DebuggerSimulatorSettings.from_state(state)

    if settings["use_simulated_time"] == true do
      case clock_unit_for_trigger(trigger) do
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

  @spec clock_unit_for_trigger(String.t()) ::
          :second | :minute | :hour | :day | :month | :year | nil
  defp clock_unit_for_trigger(trigger) when is_binary(trigger) do
    t =
      trigger
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")

    cond do
      String.contains?(t, "secondchange") or String.contains?(t, "onsecond") -> :second
      String.contains?(t, "minutechange") or String.contains?(t, "onminute") -> :minute
      String.contains?(t, "hourchange") or String.contains?(t, "onhour") -> :hour
      String.contains?(t, "daychange") or String.contains?(t, "onday") -> :day
      String.contains?(t, "monthchange") or String.contains?(t, "onmonth") -> :month
      String.contains?(t, "yearchange") or String.contains?(t, "onyear") -> :year
      true -> nil
    end
  end

  @spec advance_naive_datetime(
          NaiveDateTime.t(),
          :second | :minute | :hour | :day | :month | :year
        ) ::
          NaiveDateTime.t()
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
