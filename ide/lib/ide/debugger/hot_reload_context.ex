defmodule Ide.Debugger.HotReloadContext do
  @moduledoc false

  alias Ide.Debugger.HotReload
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SimulatorSurfaceSettings
  alias Ide.Debugger.SourceRevision
  alias Ide.Debugger.Types

  @type host :: %{
          required(:put_placeholder_views) => (Types.runtime_state(),
                                             String.t(),
                                             String.t(),
                                             String.t() ->
                                               Types.runtime_state()),
          required(:merge_introspect) => (Types.runtime_state() ->
                                            {Types.runtime_state(),
                                             Types.debugger_contract() | nil}),
          required(:append_reload_events) => (Types.runtime_state(),
                                              String.t(),
                                              String.t()
                                              | nil,
                                              String.t(),
                                              String.t(),
                                              Types.debugger_contract()
                                              | nil ->
                                                Types.runtime_state())
        }

  @spec build(String.t() | nil, String.t(), host()) :: HotReload.ctx()
  def build(rel_path, source, host) when is_binary(source) and is_map(host) do
    %{
      compute_revision: &SourceRevision.compute/2,
      prepare_running_state: fn st ->
        st
        |> Map.put(:running, true)
        |> RuntimeSurfaces.apply_launch_context("LaunchUser")
        |> SimulatorSurfaceSettings.apply_to_state()
        |> Map.put(:revision, SourceRevision.compute(rel_path, source))
      end,
      put_reload_fields: &HotReload.put_source_fields/5,
      put_placeholder_views: host.put_placeholder_views,
      merge_introspect: host.merge_introspect,
      append_reload_events: host.append_reload_events
    }
  end
end
