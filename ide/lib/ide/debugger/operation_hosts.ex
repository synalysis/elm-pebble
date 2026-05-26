defmodule Ide.Debugger.OperationHosts do
  @moduledoc false

  alias Ide.Debugger.CompileIngestApply
  alias Ide.Debugger.ReplayRecent
  alias Ide.Debugger.SimulatorSettingsApply
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.StepOperationHost
  alias Ide.Debugger.SubscriptionToggle
  alias Ide.Debugger.TickIngress
  alias Ide.Debugger.Types

  @type append_event_fn :: (Types.runtime_state(), String.t(), map() -> Types.runtime_state())

  @type apply_step_fn ::
          (Types.runtime_state(), Types.surface_target(), String.t(), Types.subscription_payload() | nil,
           String.t(), String.t() -> Types.runtime_state())

  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())

  @type replay_label_fn :: (Types.surface_target() | nil -> String.t())

  @type source_root_fn :: (Types.surface_target() -> String.t())

  @type tick_message_fn :: (Types.runtime_state(), Types.surface_target() -> String.t())

  @type update_fn ::
          (String.t(), (Types.runtime_state() -> Types.runtime_state()) -> {:ok, Types.runtime_state()})

  @type merge_artifacts_fn ::
          (Types.runtime_state(), Types.surface_target() | nil, map() -> Types.runtime_state())

  @type deps :: %{
          required(:apply_step_once) => apply_step_fn(),
          required(:append_event) => append_event_fn(),
          required(:normalize_target) => normalize_target_fn(),
          required(:replay_label) => replay_label_fn(),
          required(:source_root_for_target) => source_root_fn(),
          required(:tick_message_for_surface) => tick_message_fn(),
          required(:update) => update_fn(),
          required(:contexts) => (-> RuntimeContexts.t()),
          optional(:merge_runtime_artifacts) => merge_artifacts_fn(),
          optional(:refresh_from_artifacts) => (Types.runtime_state() -> Types.runtime_state())
        }

  @spec step_operation(deps()) :: StepOperationHost.base()
  def step_operation(%{} = deps) do
    %{
      apply_step_once: deps.apply_step_once,
      append_event: deps.append_event,
      normalize_target: deps.normalize_target,
      replay_label: deps.replay_label,
      source_root_for_target: deps.source_root_for_target
    }
  end

  @spec replay_recent(deps()) :: ReplayRecent.host()
  def replay_recent(deps), do: StepOperationHost.replay_recent(step_operation(deps))

  @spec tick_ingress(deps()) :: TickIngress.host()
  def tick_ingress(%{} = deps) do
    StepOperationHost.tick_ingress(
      step_operation(deps),
      %{
        tick_message_for_surface: deps.tick_message_for_surface,
        update: deps.update,
        contexts: deps.contexts
      }
    )
  end

  @spec subscription_toggle(deps()) :: SubscriptionToggle.host()
  def subscription_toggle(%{} = deps) do
    %{
      append_event: deps.append_event,
      normalize_target: deps.normalize_target,
      source_root_for_target: deps.source_root_for_target
    }
  end

  @spec simulator_settings(deps()) :: SimulatorSettingsApply.host()
  def simulator_settings(%{} = deps) do
    %{append_event: deps.append_event, contexts: deps.contexts}
  end

  @spec compile_ingest(deps()) :: CompileIngestApply.host()
  def compile_ingest(%{} = deps) do
    %{
      append_event: deps.append_event,
      merge_runtime_artifacts: Map.get(deps, :merge_runtime_artifacts),
      refresh_from_artifacts: Map.get(deps, :refresh_from_artifacts)
    }
  end
end
