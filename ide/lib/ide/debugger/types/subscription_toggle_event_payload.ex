defmodule Ide.Debugger.Types.SubscriptionToggleEventPayload do
  @moduledoc "Payload for `debugger.subscription_toggle` subscription gating events."
  alias Ide.Debugger.Types
  alias Ide.Debugger.Types.DisabledSubscription

  @type t :: %{
          optional(:action) => String.t(),
          optional(:target) => String.t(),
          optional(:trigger) => String.t(),
          optional(:message) => String.t(),
          optional(:enabled) => boolean(),
          optional(:disabled_subscriptions) => [map()],
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @spec blocked(String.t(), String.t()) :: t()
  def blocked(target, trigger) when is_binary(target) and is_binary(trigger) do
    %{action: "blocked", target: target, trigger: trigger}
  end

  @spec blocked_inactive(String.t(), String.t(), String.t()) :: t()
  def blocked_inactive(target, trigger, message)
      when is_binary(target) and is_binary(trigger) and is_binary(message) do
    %{action: "blocked_inactive", target: target, trigger: trigger, message: message}
  end

  @spec set_subscription_enabled(
          String.t(),
          String.t(),
          boolean(),
          [DisabledSubscription.wire_map()]
        ) :: t()
  def set_subscription_enabled(target, trigger, enabled?, disabled_subscriptions)
      when is_binary(target) and is_binary(trigger) and is_boolean(enabled?) and
             is_list(disabled_subscriptions) do
    %{
      action: "set_subscription_enabled",
      target: target,
      trigger: trigger,
      enabled: enabled?,
      disabled_subscriptions: disabled_subscriptions
    }
  end
end
