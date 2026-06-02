defmodule Ide.Debugger.StepOperationHost do
  @moduledoc false

  alias Ide.Debugger.ReplayRecent
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.TickIngress
  alias Ide.Debugger.Types

  @type apply_step_fn ::
          (Types.runtime_state(),
           Types.surface_target(),
           String.t(),
           Types.subscription_payload()
           | nil,
           String.t(),
           String.t() ->
             Types.runtime_state())

  @type append_event_fn ::
          (Types.runtime_state(), String.t(), Types.debugger_timeline_payload() ->
             Types.runtime_state())

  @type normalize_target_fn :: (Types.wire_input() -> Types.surface_target())

  @type replay_label_fn :: (Types.surface_target() | nil -> String.t())

  @type source_root_fn :: (Types.surface_target() -> String.t())

  @type base :: %{
          required(:apply_step_once) => apply_step_fn(),
          required(:append_event) => append_event_fn(),
          required(:normalize_target) => normalize_target_fn(),
          required(:replay_label) => replay_label_fn(),
          required(:source_root_for_target) => source_root_fn()
        }

  @type tick_extras :: %{
          required(:tick_message_for_surface) => (Types.runtime_state(), Types.surface_target() ->
                                                    String.t()),
          required(:update) => (String.t(), (Types.runtime_state() -> Types.runtime_state()) ->
                                  {:ok, Types.runtime_state()}),
          required(:contexts) => (-> RuntimeContexts.t())
        }

  @spec replay_recent(base()) :: ReplayRecent.host()
  def replay_recent(%{} = base) do
    %{
      apply_step_once: base.apply_step_once,
      append_event: base.append_event,
      normalize_target: base.normalize_target,
      replay_label: base.replay_label
    }
  end

  @spec tick_ingress(base(), tick_extras()) :: TickIngress.host()
  def tick_ingress(%{} = base, %{} = extras) do
    Map.merge(base, extras)
  end
end
