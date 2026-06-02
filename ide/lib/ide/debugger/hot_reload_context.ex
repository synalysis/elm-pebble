defmodule Ide.Debugger.HotReloadContext do
  @moduledoc false

  alias Ide.Debugger.HotReload
  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SimulatorSurfaceSettings
  alias Ide.Debugger.SourceRevision

  @type host :: %{
          required(:put_placeholder_views) => (map(), String.t(), String.t(), String.t() -> map()),
          required(:merge_introspect) => (map() -> {map(), map() | nil}),
          required(:append_reload_events) => (map(),
                                              String.t(),
                                              String.t()
                                              | nil,
                                              String.t(),
                                              String.t(),
                                              map()
                                              | nil ->
                                                map())
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
