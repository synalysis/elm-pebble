defmodule Ide.Debugger.TriggerMessageSurface do
  @moduledoc false

  alias Ide.Debugger.IntrospectAccess
  alias Ide.Debugger.SubscriptionPayload
  alias Ide.Debugger.TriggerCandidates
  alias Ide.Debugger.Types

  @type resolve_ctx :: %{
          required(:introspect_for) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect() | map()),
          required(:attach_payload) =>
            (Types.runtime_state(), Types.surface_target(), String.t(), String.t() -> String.t())
        }

  @type payload_ctx :: %{
          optional(:introspect) =>
            (Types.runtime_state(), Types.surface_target() -> Types.elm_introspect() | map()),
          optional(:settings) => (Types.runtime_state() -> map())
        }

  @spec resolve(
          Types.runtime_state(),
          Types.surface_target(),
          String.t(),
          String.t() | nil,
          resolve_ctx()
        ) :: String.t()
  def resolve(state, target, trigger, requested_message, ctx)
      when is_map(state) and target in [:watch, :companion, :phone] and is_binary(trigger) and is_map(ctx) do
    message =
      if is_binary(requested_message) and requested_message != "" do
        requested_message
      else
        ei = ctx.introspect_for.(state, target)
        msg_constructors = IntrospectAccess.list(ei, "msg_constructors")
        update_branches = IntrospectAccess.list(ei, "update_case_branches")
        known_messages = if msg_constructors != [], do: msg_constructors, else: update_branches

        TriggerCandidates.best_message_for_trigger(known_messages, trigger) ||
          List.first(known_messages) ||
          TriggerCandidates.default_message_for_trigger(trigger)
      end

    ctx.attach_payload.(state, target, message, trigger)
  end

  def resolve(_state, _target, _trigger, requested_message, _ctx) when is_binary(requested_message),
    do: requested_message

  def resolve(_state, _target, trigger, _requested_message, ctx) when is_binary(trigger) and is_map(ctx) do
    ctx.attach_payload.(
      %{},
      :watch,
      TriggerCandidates.default_message_for_trigger(trigger),
      trigger
    )
  end

  @spec attach_payload(
          Types.runtime_state() | map(),
          Types.surface_target(),
          String.t(),
          String.t(),
          payload_ctx()
        ) :: String.t()
  def attach_payload(state, target, message, trigger, ctx) when is_binary(message) and is_binary(trigger) do
    SubscriptionPayload.attach(state, target, message, trigger, ctx)
  end
end
