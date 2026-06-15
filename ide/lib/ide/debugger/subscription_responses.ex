defmodule Ide.Debugger.SubscriptionResponses do
  @moduledoc false

  alias Ide.Debugger.CompanionBridge
  alias Ide.Debugger.Types

  @type apply_ctx :: %{
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload(),
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state())
        }

  @spec ok_wire_value(String.t(), Types.subscription_payload()) :: Types.protocol_ctor_value()
  def ok_wire_value(callback, payload) when is_binary(callback) do
    CompanionBridge.subscription_result_message_value(callback, "Ok", payload)
  end

  @spec apply_ok(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload(),
          String.t(),
          String.t(),
          apply_ctx()
        ) :: Types.runtime_state()
  def apply_ok(state, target, callback, payload, source, trigger, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(callback) and
             is_binary(source) and is_binary(trigger) and is_map(ctx) do
    ctx.apply_step_once.(
      state,
      target,
      callback,
      ok_wire_value(callback, payload),
      source,
      trigger
    )
  end

  def apply_ok(state, _target, _callback, _payload, _source, _trigger, _ctx), do: state
end
