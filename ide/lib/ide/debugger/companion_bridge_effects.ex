defmodule Ide.Debugger.CompanionBridgeEffects do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.Types

  @spec apply_command_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.app_model(),
          String.t(),
          CompanionBridgeRuntime.ctx()
        ) :: Types.runtime_state()
  def apply_command_responses(state, target, message, model, message_source, ctx) do
    CompanionBridgeRuntime.maybe_apply_command_responses(
      state,
      target,
      message,
      model,
      message_source,
      ctx
    )
  end

  @spec apply_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          CompanionBridgeRuntime.ctx()
        ) :: Types.runtime_state()
  def apply_responses(state, target, message_source, ctx) do
    CompanionBridgeRuntime.maybe_apply_responses(state, target, message_source, ctx)
  end

  @spec apply_simulator_settings_responses(
          Types.runtime_state(),
          CompanionBridgeRuntime.ctx()
        ) :: Types.runtime_state()
  def apply_simulator_settings_responses(state, ctx) when is_map(state) do
    CompanionBridgeRuntime.maybe_apply_subscription_responses(
      state,
      :companion,
      "simulator_settings",
      ctx
    )
  end

  @spec apply_weather_settings_change(
          Types.runtime_state(),
          Types.simulator_settings(),
          Types.simulator_settings(),
          CompanionBridgeRuntime.ctx()
        ) :: Types.runtime_state()
  def apply_weather_settings_change(state, previous_settings, new_settings, ctx)
      when is_map(state) and is_map(previous_settings) and is_map(new_settings) and is_map(ctx) do
    CompanionBridgeRuntime.maybe_apply_weather_settings_change(
      state,
      previous_settings,
      new_settings,
      ctx
    )
  end
end
