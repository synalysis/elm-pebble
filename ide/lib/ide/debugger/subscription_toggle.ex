defmodule Ide.Debugger.SubscriptionToggle do
  @moduledoc false

  alias Ide.Debugger.Attrs
  alias Ide.Debugger.SubscriptionAutoFireState
  alias Ide.Debugger.Types

  @type append_event_fn :: (Types.runtime_state(), String.t(), map() -> Types.runtime_state())

  @type source_root_fn :: (Types.surface_target() -> String.t())

  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())

  @type host :: %{
          required(:append_event) => append_event_fn(),
          required(:normalize_target) => normalize_target_fn(),
          required(:source_root_for_target) => source_root_fn()
        }

  @spec apply(Types.runtime_state(), Types.step_attrs(), host()) :: Types.runtime_state()
  def apply(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    target = host.normalize_target.(Map.get(attrs, :target) || Map.get(attrs, "target"))
    trigger = to_string(Map.get(attrs, :trigger) || Map.get(attrs, "trigger") || "")
    enabled? = Attrs.parse_checkbox_bool(Map.get(attrs, :enabled) || Map.get(attrs, "enabled"))

    if Map.get(state, :running, false) and String.trim(trigger) != "" do
      disabled_subscriptions =
        state
        |> SubscriptionAutoFireState.disabled_subscriptions()
        |> SubscriptionAutoFireState.update_disabled_subscription(
          target,
          trigger,
          enabled?,
          host.source_root_for_target
        )

      state
      |> Map.put(:disabled_subscriptions, disabled_subscriptions)
      |> host.append_event.(
        "debugger.subscription_toggle",
        Types.SubscriptionToggleEventPayload.set_subscription_enabled(
          host.source_root_for_target.(target),
          trigger,
          enabled?,
          disabled_subscriptions
        )
      )
    else
      state
    end
  end
end
