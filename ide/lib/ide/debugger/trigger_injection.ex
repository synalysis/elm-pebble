defmodule Ide.Debugger.TriggerInjection do
  @moduledoc false

  alias Ide.Debugger.DeviceDataResponses
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
                                        Types.runtime_state()),
          optional(:apply_device_data_responses) => (Types.runtime_state(),
                                                     Types.surface_target(),
                                                     String.t(),
                                                     Types.subscription_payload() | nil ->
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

      {_step_message, derived_message_value} =
        TimelineMessage.message_value_for_step(resolved_message)

      resolved_message_value =
        SubscriptionTriggerWire.message_value(resolved_message, requested_message_value) ||
          derived_message_value

      row = %{
        trigger: trigger,
        message: resolved_message,
        target: host.source_root_for_target.(target)
      }

      if SubscriptionActivation.model_active?(state, target, row) do
        before_seq = Map.get(state, :debugger_seq, 0)

        stepped =
          state
          |> host.apply_step_once.(
            target,
            resolved_message,
            resolved_message_value,
            "subscription_trigger",
            "subscription_trigger"
          )
          |> maybe_apply_device_data_responses(
            before_seq,
            target,
            resolved_message,
            resolved_message_value,
            host
          )
          |> SubscriptionPayload.sync_simulator_clock_from_subscription(
            resolved_message,
            resolved_message_value
          )

        stepped
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

  @spec maybe_apply_device_data_responses(
          Types.runtime_state(),
          non_neg_integer(),
          Types.surface_target(),
          String.t(),
          Types.subscription_payload() | nil,
          host()
        ) :: Types.runtime_state()
  defp maybe_apply_device_data_responses(
         state,
         before_seq,
         target,
         message,
         message_value,
         host
       )
       when is_map(state) and is_integer(before_seq) and is_binary(message) and is_map(host) do
    if DeviceDataResponses.device_data_response_appended?(
         state,
         before_seq,
         target,
         host.source_root_for_target
       ) do
      state
    else
      case Map.get(host, :apply_device_data_responses) do
        fun when is_function(fun, 4) -> fun.(state, target, message, message_value)
        _ -> state
      end
    end
  end

  defp maybe_apply_device_data_responses(state, _before_seq, _target, _message, _message_value, _host),
    do: state
end
