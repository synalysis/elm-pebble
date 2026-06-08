defmodule Ide.Debugger.SimulatorWatchDelivery do
  @moduledoc false

  alias Ide.Debugger.Geolocation
  alias Ide.Debugger.ProtocolEvents
  alias Ide.Debugger.SimulatorSettings, as: DebuggerSimulatorSettings
  alias Ide.Debugger.Types

  @phone_to_watch_triggers ~w(phone_to_watch on_phone_to_watch)
  @weather_phone_messages ~w(ProvideTemperature ProvideCondition)
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
          required(:protocol_events_ctx) => (-> ProtocolEvents.ctx()),
          required(:protocol_supports_weather?) => (Types.runtime_state() -> boolean())
        }

  @spec deliver_weather(Types.runtime_state(), apply_ctx()) :: Types.runtime_state()
  def deliver_weather(state, ctx) when is_map(state) and is_map(ctx) do
    if ctx.protocol_supports_weather?.(state) do
      deliver_weather_when_declared(state, ctx)
    else
      state
    end
  end

  @spec deliver_weather_when_declared(Types.runtime_state(), apply_ctx()) :: Types.runtime_state()
  def deliver_weather_when_declared(state, ctx) when is_map(state) and is_map(ctx) do
    weather = Map.get(ctx.simulator_settings.(state), "weather") || %{}

    if map_size(weather) == 0 do
      state
    else
      maybe_deliver_weather_messages(state, weather, ctx)
    end
  end

  @spec deliver_position(Types.runtime_state(), apply_ctx()) :: Types.runtime_state()
  def deliver_position(state, ctx) when is_map(state) and is_map(ctx) do
    settings = ctx.simulator_settings.(state)

    if phone_to_watch_active?(state, ctx) do
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

  @spec inject_weather_on_settings_change(
          Types.runtime_state(),
          Types.simulator_settings(),
          Types.simulator_settings(),
          apply_ctx()
        ) :: Types.runtime_state()
  def inject_weather_on_settings_change(state, previous_settings, new_settings, ctx)
      when is_map(state) and is_map(previous_settings) and is_map(new_settings) and is_map(ctx) do
    previous_weather = Map.get(previous_settings, "weather") || %{}
    new_weather = Map.get(new_settings, "weather") || %{}

    if new_weather == %{} or new_weather == previous_weather do
      state
    else
      maybe_deliver_weather_messages(state, new_weather, ctx)
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

  @spec protocol_supports_weather?(Types.runtime_state(), (-> ProtocolEvents.ctx())) :: boolean()
  def protocol_supports_weather?(state, protocol_events_ctx_fun)
      when is_map(state) and is_function(protocol_events_ctx_fun, 0) do
    case ProtocolEvents.project_schema(state, protocol_events_ctx_fun.()) do
      {:ok, schema} ->
        schema
        |> Map.get(:phone_to_watch, [])
        |> List.wrap()
        |> Enum.any?(fn
          %{name: name} when is_binary(name) -> name in @weather_phone_messages
          %{"name" => name} when is_binary(name) -> name in @weather_phone_messages
          _ -> false
        end)

      _ ->
        false
    end
  end

  defp maybe_deliver_weather_messages(state, weather, ctx) when is_map(weather) and is_map(ctx) do
    if phone_to_watch_active?(state, ctx) do
      state
      |> apply_weather_step(weather, "ProvideTemperature", ctx)
      |> apply_weather_step(weather, "ProvideCondition", ctx)
    else
      state
    end
  end

  defp apply_weather_step(state, weather, message_name, ctx)
       when is_map(weather) and is_binary(message_name) and is_map(ctx) do
    case weather_message_value(message_name, weather) do
      %{} = message_value ->
        ctx.apply_step_once.(
          state,
          :watch,
          weather_step_message(message_name, weather),
          message_value,
          "simulator_settings",
          "simulator_settings"
        )

      _ ->
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
