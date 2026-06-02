defmodule Ide.Debugger.HotReloadSession do
  @moduledoc false

  alias Ide.Debugger.CompanionConfiguration
  alias Ide.Debugger.HotReload
  alias Ide.Debugger.ProjectResourceIndices
  alias Ide.Debugger.RuntimeContexts
  alias Ide.Debugger.SimulatorWatchDelivery
  alias Ide.Debugger.SurfaceTargets
  alias Ide.Debugger.Types

  @type ensure_phone_fn :: (Types.runtime_state() -> Types.runtime_state())

  @type host :: %{
          required(:ensure_phone_state) => ensure_phone_fn(),
          required(:contexts) => (-> RuntimeContexts.t())
        }

  @spec apply(Types.runtime_state(), String.t(), Types.reload_attrs(), host()) ::
          Types.runtime_state()
  def apply(state, project_slug, attrs, host)
      when is_map(state) and is_binary(project_slug) and is_map(attrs) and is_map(host) do
    rel_path = Map.get(attrs, :rel_path) || Map.get(attrs, "rel_path")
    reason = Map.get(attrs, :reason) || Map.get(attrs, "reason") || "manual"
    source = Map.get(attrs, :source) || Map.get(attrs, "source") || ""
    source_root = SurfaceTargets.normalize_source_root(attrs)
    ctx = host.contexts.()

    state
    |> host.ensure_phone_state.()
    |> ProjectResourceIndices.attach_all(project_slug)
    |> HotReload.apply(
      rel_path,
      source,
      reason,
      source_root,
      RuntimeContexts.hot_reload_context(ctx, rel_path, source, source_root)
    )
    |> SimulatorWatchDelivery.deliver_weather(ctx.simulator_watch_delivery)
    |> CompanionConfiguration.attach_to_state(project_slug)
  end
end
