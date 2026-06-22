defmodule Ide.Debugger.SimulatorWatchDelivery do
  @moduledoc false

  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.Types

  @phone_to_watch_triggers ~w(phone_to_watch on_phone_to_watch)
  @unobstructed_triggers ~w(
    on_unobstructed_will_change
    on_unobstructed_changing
    on_unobstructed_did_change
  )

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
      Enum.reduce(@unobstructed_triggers, state, fn trigger, acc ->
        inject_subscription_trigger(acc, trigger, ctx)
      end)
    end
  end

  @spec inject_subscription_trigger(Types.runtime_state(), String.t(), apply_ctx()) ::
          Types.runtime_state()
  def inject_subscription_trigger(state, trigger, ctx)
      when is_map(state) and is_binary(trigger) and is_map(ctx) do
    row = find_trigger_row(state, trigger, ctx)

    if is_map(row) and ctx.model_active?.(state, :watch, row) do
      message = Map.get(row, :message) || Map.get(row, "message")
      resolved_message = ctx.trigger_message_for_surface.(state, :watch, trigger, message)

      ctx.apply_step_once.(
        state,
        :watch,
        resolved_message,
        nil,
        "simulator_settings",
        "simulator_settings"
      )
    else
      state
    end
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

        Geolocation.init_requested_from_introspect?(ei) or
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
end
