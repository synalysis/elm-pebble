defmodule Ide.Debugger.TriggerInjectionSession do
  @moduledoc false

  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.TriggerInjection
  alias Ide.Debugger.Types

  @type host :: %{
          required(:contexts) => (-> RuntimeContexts.t())
        }

  @spec apply(Types.runtime_state(), Types.inject_trigger_attrs(), host()) ::
          Types.runtime_state()
  def apply(state, attrs, host) when is_map(state) and is_map(attrs) and is_map(host) do
    if Map.get(state, :running, false) do
      target = SurfaceTargets.normalize(Map.get(attrs, :target) || Map.get(attrs, "target"))
      TriggerInjection.apply(state, target, attrs, host.contexts.().trigger_injection)
    else
      state
    end
  end
end
