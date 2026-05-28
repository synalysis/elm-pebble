defmodule Ide.Debugger.TriggersApi do
  @moduledoc false

  alias Ide.Debugger.AgentSession
  alias Ide.Debugger.SubscriptionApi
  alias Ide.Debugger.SubscriptionToggle
  alias Ide.Debugger.TraceApi
  alias Ide.Debugger.TriggerInjectionSession
  alias Ide.Debugger.TriggerQueries
  alias Ide.Debugger.Types

  @type runtime_state :: Types.RuntimeState.t() | Types.RuntimeState.wire_map()

  @spec trigger_candidates(runtime_state(), :watch | :companion | :phone | nil) ::
          [Types.trigger_candidate()]
  def trigger_candidates(state, target \\ :watch) do
    AgentSession.with_hosts(fn hosts -> TriggerQueries.candidates(state, target, hosts) end)
  end

  @spec available_triggers(String.t(), Types.available_triggers_attrs()) ::
          {:ok, [Types.trigger_candidate()]}
  def available_triggers(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    target = TriggerQueries.normalize_optional_target(attrs)
    {:ok, state} = TraceApi.snapshot(project_slug, event_limit: 1)
    {:ok, trigger_candidates(state, target)}
  end

  @spec inject_trigger(String.t(), Types.inject_trigger_attrs()) :: {:ok, runtime_state()}
  def inject_trigger(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, &TriggerInjectionSession.apply(&1, attrs, hosts.trigger_injection))
    end)
  end

  @spec subscription_trigger_injection_modal_supported?(runtime_state(), Types.replay_row()) ::
          boolean()
  def subscription_trigger_injection_modal_supported?(state, row) do
    AgentSession.with_hosts(fn hosts -> TriggerQueries.injection_modal_supported?(state, row, hosts) end)
  end

  @spec set_subscription_enabled(String.t(), Types.step_attrs()) :: {:ok, runtime_state()}
  def set_subscription_enabled(project_slug, attrs \\ %{}) when is_binary(project_slug) and is_map(attrs) do
    AgentSession.with_hosts(fn hosts ->
      AgentSession.mutate(project_slug, &SubscriptionToggle.apply(&1, attrs, hosts.subscription_toggle))
    end)
  end

  defdelegate subscription_trigger_display(op, trigger), to: SubscriptionApi, as: :trigger_display

  @spec subscription_trigger_display_for(runtime_state(), String.t(), String.t()) :: String.t()
  defdelegate subscription_trigger_display_for(state, trigger, target_name),
    to: SubscriptionApi,
    as: :trigger_display_label

  @spec subscription_model_active?(runtime_state(), Types.surface_target(), Types.replay_row()) ::
          boolean()
  defdelegate subscription_model_active?(state, target, row), to: SubscriptionApi, as: :model_active?
end
