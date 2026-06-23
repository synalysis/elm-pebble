defmodule Ide.Debugger.TriggerInjection do
  @moduledoc false

  alias Ide.Debugger.RuntimeActiveSubscriptions
  alias Ide.Debugger.RuntimeModelMessages
  alias Ide.Debugger.SubscriptionActivation
  alias Ide.Debugger.SubscriptionAutoFireState
  alias Ide.Debugger.SubscriptionPayload
  alias Ide.Debugger.SubscriptionTriggerWire
  alias Ide.Debugger.TimelineMessage
  alias Ide.Debugger.Types

  @type host :: %{
          required(:source_root_for_target) => (Types.surface_target() -> String.t()),
          required(:trigger_message_for_surface) => (Types.runtime_state(),
                                                     Types.surface_target(),
                                                     String.t(),
                                                     String.t()
                                                     | nil ->
                                                       String.t()),
          required(:apply_step_once) => (Types.runtime_state(),
                                         Types.surface_target(),
                                         String.t(),
                                         Types.subscription_payload()
                                         | nil,
                                         String.t(),
                                         String.t() ->
                                           Types.runtime_state()),
          required(:append_event) => (Types.runtime_state(),
                                      String.t(),
                                      Types.debugger_timeline_payload() ->
                                        Types.runtime_state())
        }

  @spec apply(Types.runtime_state(), Types.surface_target(), Types.inject_trigger_attrs(), host()) ::
          Types.runtime_state()
  def apply(state, target, attrs, host)
      when is_map(state) and target in [:watch, :companion, :phone] and is_map(host) do
    trigger = attrs |> Map.get(:trigger) |> Kernel.||(Map.get(attrs, "trigger")) |> to_string()
    requested_message = Map.get(attrs, :message) || Map.get(attrs, "message")
    requested_message_value = Map.get(attrs, :message_value) || Map.get(attrs, "message_value")

    if SubscriptionAutoFireState.subscription_trigger_disabled?(
         state,
         target,
         trigger,
         host.source_root_for_target
       ) do
      host.append_event.(
        state,
        "debugger.subscription_toggle",
        Types.SubscriptionToggleEventPayload.blocked(
          host.source_root_for_target.(target),
          trigger
        )
      )
    else
      requested_message =
        SubscriptionPayload.ensure_message_payload(requested_message, requested_message_value)

      resolved_message =
        host.trigger_message_for_surface.(state, target, trigger, requested_message)

      resolved_message_value =
        SubscriptionTriggerWire.message_value(resolved_message, requested_message_value) ||
          case TimelineMessage.message_value_for_step(resolved_message) do
            {_, %{} = value} -> value
            _ -> nil
          end ||
          RuntimeActiveSubscriptions.message_value_for(state, target, trigger, resolved_message)

      activation_message =
        case RuntimeActiveSubscriptions.message_for_trigger(state, target, trigger, nil) do
          {:ok, runtime_message, _} -> runtime_message
          :error -> RuntimeModelMessages.wire_constructor(resolved_message) || resolved_message
        end

      row = %{
        trigger: trigger,
        message: activation_message,
        target: host.source_root_for_target.(target)
      }

      if SubscriptionActivation.model_active?(state, target, row) do
        state
        |> host.apply_step_once.(
          target,
          resolved_message,
          resolved_message_value,
          "subscription_trigger",
          "subscription_trigger"
        )
        |> SubscriptionPayload.sync_simulator_clock_from_subscription(
          resolved_message,
          resolved_message_value
        )
      else
        host.append_event.(
          state,
          "debugger.subscription_toggle",
          Types.SubscriptionToggleEventPayload.blocked_inactive(
            host.source_root_for_target.(target),
            trigger,
            resolved_message
          )
        )
      end
    end
  end
end
