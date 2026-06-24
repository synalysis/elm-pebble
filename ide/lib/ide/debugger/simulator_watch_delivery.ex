defmodule Ide.Debugger.SimulatorWatchDelivery do
  @moduledoc false

  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.RuntimeActiveSubscriptions
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.Types

  @phone_to_watch_triggers ~w(phone_to_watch on_phone_to_watch)
  @unobstructed_target_patterns ~w(unobstructedarea.onwillchange unobstructedarea.onchanging unobstructedarea.ondidchange)
  @backlight_target_patterns ~w(light.onchange onbacklightchange)
  @screen_target_patterns ~w(platform.onscreenchange onscreenchange)
  @speaker_target_patterns ~w(speaker.onfinished)

  @type apply_ctx :: %{
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload()
                                         | nil,
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:trigger_candidates) => (Types.runtime_state(), Types.surface_target() ->
                                              [Types.trigger_candidate()]),
          required(:model_active?) => (Types.runtime_state(),
                                       Types.surface_target(),
                                       Types.trigger_candidate() ->
                                         boolean()),
          required(:trigger_message_for_surface) => (Types.runtime_state(),
                                                     Types.surface_target(),
                                                     String.t(),
                                                     String.t()
                                                     | nil ->
                                                       String.t()),
          required(:simulator_settings) => (Types.runtime_state() ->
                                              Types.simulator_settings()),
          optional(:introspect_for) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect())
        }

  @spec deliver_position(Types.runtime_state(), apply_ctx()) :: Types.runtime_state()
  def deliver_position(state, ctx) when is_map(state) and is_map(ctx) do
    settings = ctx.simulator_settings.(state)

    if geolocation_position_delivery_active?(state, ctx) do
      message_value = Geolocation.watch_from_phone_message_value(settings)
      {lat_e6, lon_e6, accuracy_m} = Geolocation.wire_triplet(settings)

      ctx.apply_step_once.(
        state,
        :watch,
        "FromPhone (ProvidePosition #{lat_e6} #{lon_e6} #{accuracy_m})",
        message_value,
        "simulator_settings",
        "simulator_settings"
      )
    else
      state
    end
  end

  @spec inject_unobstructed_triggers(
          Types.runtime_state(),
          Types.simulator_settings(),
          Types.simulator_settings(),
          apply_ctx()
        ) :: Types.runtime_state()
  def inject_unobstructed_triggers(state, previous_settings, new_settings, ctx)
      when is_map(state) and is_map(previous_settings) and is_map(new_settings) and is_map(ctx) do
    if Map.get(previous_settings, "timeline_peek") == Map.get(new_settings, "timeline_peek") do
      state
    else
      inject_active_by_target_patterns(state, @unobstructed_target_patterns, ctx)
    end
  end

  @spec inject_settings_triggers(
          Types.runtime_state(),
          Types.simulator_settings(),
          Types.simulator_settings(),
          apply_ctx()
        ) :: Types.runtime_state()
  def inject_settings_triggers(state, previous_settings, new_settings, ctx)
      when is_map(state) and is_map(previous_settings) and is_map(new_settings) and is_map(ctx) do
    state
    |> maybe_inject_backlight_change(previous_settings, new_settings, ctx)
    |> maybe_apply_launch_context_settings(previous_settings, new_settings)
  end

  @spec inject_screen_change(Types.runtime_state(), apply_ctx()) :: Types.runtime_state()
  def inject_screen_change(state, ctx) when is_map(state) and is_map(ctx) do
    inject_active_by_target_patterns(state, @screen_target_patterns, ctx)
  end

  @spec inject_speaker_finished(Types.runtime_state(), apply_ctx()) :: Types.runtime_state()
  def inject_speaker_finished(state, ctx) when is_map(state) and is_map(ctx) do
    inject_active_by_target_patterns(state, @speaker_target_patterns, ctx)
  end

  @spec inject_subscription_trigger(Types.runtime_state(), String.t(), apply_ctx()) ::
          Types.runtime_state()
  def inject_subscription_trigger(state, trigger, ctx)
      when is_map(state) and is_binary(trigger) and is_map(ctx) do
    row = find_trigger_row(state, trigger, ctx)

    if is_map(row) and ctx.model_active?.(state, :watch, row) do
      inject_row(state, row, ctx)
    else
      state
    end
  end

  @spec inject_subscription_triggers_by_patterns(
          Types.runtime_state(),
          [String.t()],
          apply_ctx()
        ) :: Types.runtime_state()
  def inject_subscription_triggers_by_patterns(state, patterns, ctx)
      when is_map(state) and is_list(patterns) and is_map(ctx) do
    inject_active_by_target_patterns(state, patterns, ctx)
  end

  @spec weather_message_value(String.t(), Types.simulator_settings()) ::
          Types.phone_to_watch_message_value() | nil
  def weather_message_value("ProvideTemperature", weather) when is_map(weather) do
    case DebuggerSimulatorSettings.temperature_celsius(weather) do
      nil ->
        nil

      temp ->
        %{
          "ctor" => "FromPhone",
          "args" => [
            %{
              "ctor" => "ProvideTemperature",
              "args" => [%{"ctor" => "Celsius", "args" => [temp]}]
            }
          ]
        }
    end
  end

  def weather_message_value("ProvideCondition", weather) when is_map(weather) do
    condition = ProtocolEvents.weather_condition_from_settings(%{"weather" => weather})

    %{
      "ctor" => "FromPhone",
      "args" => [
        %{
          "ctor" => "ProvideCondition",
          "args" => [condition]
        }
      ]
    }
  end

  def weather_message_value(_message_name, _weather), do: nil

  @spec weather_step_message(String.t(), Types.simulator_settings()) :: String.t()
  def weather_step_message("ProvideTemperature", weather) when is_map(weather) do
    case DebuggerSimulatorSettings.temperature_celsius(weather) do
      nil -> "FromPhone (ProvideTemperature ...)"
      temp -> "FromPhone (ProvideTemperature (Celsius #{temp}))"
    end
  end

  def weather_step_message("ProvideCondition", weather) when is_map(weather) do
    condition = ProtocolEvents.weather_condition_from_settings(%{"weather" => weather})
    ctor = Map.get(condition, "ctor") || "UnknownWeather"
    "FromPhone (ProvideCondition #{ctor})"
  end

  def weather_step_message(message_name, _weather), do: "FromPhone (#{message_name} ...)"

  @spec inject_active_by_target_patterns(Types.runtime_state(), [String.t()], apply_ctx()) ::
          Types.runtime_state()
  defp inject_active_by_target_patterns(state, patterns, ctx)
       when is_map(state) and is_list(patterns) and is_map(ctx) do
    active = RuntimeActiveSubscriptions.for_surface(state, :watch)

    RuntimeActiveSubscriptions.for_target_patterns(patterns, active)
    |> Enum.reduce(state, fn command, acc ->
      row = trigger_row_for_command(state, command, ctx)

      if is_map(row) and ctx.model_active?.(acc, :watch, row) do
        inject_row(acc, row, ctx)
      else
        acc
      end
    end)
  end

  @spec inject_row(Types.runtime_state(), Types.subscription_row_input(), apply_ctx()) ::
          Types.runtime_state()
  defp inject_row(state, row, ctx) when is_map(state) and is_map(row) and is_map(ctx) do
    trigger = Map.get(row, :trigger) || Map.get(row, "trigger")
    message = Map.get(row, :message) || Map.get(row, "message")
    resolved_message = ctx.trigger_message_for_surface.(state, :watch, trigger, message)
    message_value = Map.get(row, :message_value) || Map.get(row, "message_value")

    message_value =
      case RuntimeActiveSubscriptions.match_for_row(state, :watch, row) do
        %{} = command -> Map.get(command, "message_value") || Map.get(command, :message_value)
        _ -> message_value
      end

    ctx.apply_step_once.(
      state,
      :watch,
      resolved_message,
      message_value,
      "simulator_settings",
      "simulator_settings"
    )
  end

  defp phone_to_watch_active?(state, ctx) when is_map(state) and is_map(ctx) do
    row = find_phone_to_watch_row(state, ctx)
    is_map(row) and ctx.model_active?.(state, :watch, row)
  end

  defp geolocation_position_delivery_active?(state, ctx) when is_map(state) and is_map(ctx) do
    phone_to_watch_active?(state, ctx) and watch_accepts_provide_position?(state, ctx)
  end

  defp watch_accepts_provide_position?(state, ctx) when is_map(state) and is_map(ctx) do
    case Map.get(ctx, :introspect_for) do
      fun when is_function(fun, 2) ->
        ei = fun.(state, :watch)

        Geolocation.init_requested_for_surface?(state, :watch, ei) or
          geolocation_runtime_model?(Map.get(ei, "init_model"))

      _ ->
        false
    end
  end

  defp geolocation_runtime_model?(init_model) when is_map(init_model) do
    Map.has_key?(init_model, "latitudeE6") or Map.has_key?(init_model, "longitudeE6")
  end

  defp geolocation_runtime_model?(_init_model), do: false

  defp find_phone_to_watch_row(state, ctx) do
    state
    |> ctx.trigger_candidates.(:watch)
    |> Enum.find(fn candidate ->
      trigger = Map.get(candidate, :trigger) || Map.get(candidate, "trigger")
      trigger in @phone_to_watch_triggers
    end)
  end

  defp find_trigger_row(state, trigger, ctx) do
    state
    |> ctx.trigger_candidates.(:watch)
    |> Enum.find(fn candidate ->
      candidate_trigger = Map.get(candidate, :trigger) || Map.get(candidate, "trigger")
      candidate_trigger == trigger
    end)
  end

  defp trigger_row_for_command(state, command, ctx) do
    message = Map.get(command, "message") || Map.get(command, :message)
    target = RuntimeActiveSubscriptions.command_target(command)

    find_trigger_row(state, subscription_event_kind_from_target(target), ctx) ||
      find_trigger_row(state, target, ctx) ||
      %{trigger: subscription_event_kind_from_target(target), message: message, target: "watch"}
  end

  defp subscription_event_kind_from_target(target) when is_binary(target) do
    target
    |> String.split(".")
    |> List.last()
    |> to_string()
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp maybe_inject_backlight_change(state, previous_settings, new_settings, ctx) do
    if Map.get(previous_settings, "backlight_on") == Map.get(new_settings, "backlight_on") do
      state
    else
      inject_active_by_target_patterns(state, @backlight_target_patterns, ctx)
    end
  end

  defp maybe_apply_launch_context_settings(state, previous_settings, new_settings) do
    launch_keys = ["launch_reason", "launch_button", "quick_launch_action"]

    if Enum.all?(launch_keys, &(Map.get(previous_settings, &1) == Map.get(new_settings, &1))) do
      state
    else
      profile_id = RuntimeSurfaces.parse_watch_profile_id(Map.get(state, :watch_profile_id))
      launch_reason = Map.get(new_settings, "launch_reason", "LaunchUser")
      launch_context = RuntimeSurfaces.launch_context_for(profile_id, launch_reason, new_settings)

      state
      |> Map.put(:launch_context, launch_context)
      |> RuntimeSurfaces.apply_launch_context_to_watch()
    end
  end
end
