defmodule Ide.Debugger.TriggerMessageSurface do
  @moduledoc false

  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.RuntimeActiveSubscriptions
  alias Ide.Debugger.SubscriptionPayload
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  @type resolve_ctx :: %{
          required(:introspect_for) => (Types.runtime_state(), Types.surface_target() ->
                                          Types.elm_introspect()),
          required(:attach_payload) => (Types.runtime_state(),
                                        Types.surface_target(),
                                        String.t(),
                                        String.t() ->
                                          String.t())
        }

  @type payload_ctx :: %{
          optional(:introspect) => (Types.runtime_state(), Types.surface_target() ->
                                      Types.elm_introspect()),
          optional(:settings) => (Types.runtime_state() -> Types.simulator_settings())
        }

  @spec resolve(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil,
          resolve_ctx()
        ) :: String.t()
  def resolve(state, target, trigger, requested_message, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(trigger) and
             is_map(ctx) do
    message =
      if is_binary(requested_message) and requested_message != "" do
        requested_message
      else
        case RuntimeActiveSubscriptions.message_for_trigger(state, target, trigger, requested_message) do
          {:ok, runtime_message, _runtime_value} ->
            runtime_message

          :error ->
            if RuntimeActiveSubscriptions.present?(state, target) and
                 RuntimeActiveSubscriptions.for_surface(state, target) != [] do
              case RuntimeActiveSubscriptions.command_for_trigger(state, target, trigger) do
                %{} = command ->
                  case RuntimeActiveSubscriptions.command_message(command) do
                    "" -> TriggerCandidates.default_message_for_trigger(trigger)
                    runtime_message -> runtime_message
                  end

                _ ->
                  TriggerCandidates.default_message_for_trigger(trigger)
              end
            else
              ei = ctx.introspect_for.(state, target)
              msg_constructors = IntrospectAccess.list(ei, "msg_constructors")
              update_branches = IntrospectAccess.list(ei, "update_case_branches")
              known_messages = if msg_constructors != [], do: msg_constructors, else: update_branches

              TriggerCandidates.best_message_for_trigger(known_messages, trigger) ||
                List.first(known_messages) ||
                TriggerCandidates.default_message_for_trigger(trigger)
            end
        end
      end

    ctx.attach_payload.(state, target, message, trigger)
  end

  def resolve(_state, _target, _trigger, requested_message, _ctx)
      when is_binary(requested_message),
      do: requested_message

  def resolve(_state, _target, trigger, _requested_message, ctx)
      when is_binary(trigger) and is_map(ctx) do
    ctx.attach_payload.(
      %{},
      :watch,
      TriggerCandidates.default_message_for_trigger(trigger),
      trigger
    )
  end

  @spec attach_payload(
          Types.runtime_state() | Types.wire_map(),
          Types.surface_target(),
          String.t(),
          String.t(),
          payload_ctx()
        ) :: String.t()
  def attach_payload(state, target, message, trigger, ctx)
      when is_binary(message) and is_binary(trigger) do
    SubscriptionPayload.attach(state, target, message, trigger, ctx)
  end
end
