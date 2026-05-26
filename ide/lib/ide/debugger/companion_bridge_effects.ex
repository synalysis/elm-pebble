defmodule Ide.Debugger.CompanionBridgeEffects do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge.Runtime, as: CompanionBridgeRuntime
  alias Ide.Debugger.Types

  @spec apply_command_responses(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          map(),
          String.t(),
          CompanionBridgeRuntime.ctx()
        ) :: Types.runtime_state()
  def apply_command_responses(state, target, message, model, message_source, ctx) do
    CompanionBridgeRuntime.maybe_apply_command_responses(state, target, message, model, message_source, ctx)
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
end
