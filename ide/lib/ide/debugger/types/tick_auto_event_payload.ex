defmodule Ide.Debugger.Types.TickAutoEventPayload do
  @moduledoc "Payload for `debugger.tick_auto` auto-fire control events."
  alias Ide.Debugger.Types

  @type t :: %{
          optional(:action) => String.t(),
          optional(:interval_ms) => pos_integer() | nil,
          optional(:target) => String.t() | nil,
          optional(:targets) => [String.t()],
          optional(:count) => non_neg_integer() | nil,
          optional(:trigger) => String.t() | nil,
          optional(:enabled) => boolean(),
          optional(:subscriptions) => [map()],
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }

  @spec start(
          String.t() | nil,
          pos_integer(),
          [String.t()],
          non_neg_integer() | nil
        ) :: t()
  def start(target, interval_ms, targets, count)
      when is_integer(interval_ms) and interval_ms > 0 and is_list(targets) do
    %{
      action: "start",
      interval_ms: interval_ms,
      target: target,
      targets: targets,
      count: count
    }
  end

  @spec stop() :: t()
  def stop, do: %{action: "stop"}

  @spec set_auto_fire(String.t(), String.t() | nil, boolean(), [String.t()], [map()]) :: t()
  def set_auto_fire(target, trigger, enabled?, targets, subscriptions)
      when is_binary(target) and is_boolean(enabled?) and is_list(targets) and
             is_list(subscriptions) do
    %{
      action: "set_auto_fire",
      target: target,
      trigger: trigger,
      enabled: enabled?,
      targets: targets,
      subscriptions: subscriptions
    }
  end
end
